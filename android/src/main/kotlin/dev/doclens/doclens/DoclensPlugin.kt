package dev.doclens.doclens

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executors

private const val CAMERA_PERMISSION_REQUEST = 0x4F4E

class DoclensPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var textureRegistry: TextureRegistry
    private lateinit var context: Context

    private val eventStream = QuadEventStream()
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val backgroundExecutor = Executors.newSingleThreadExecutor()

    private var session: ScannerSession? = null
    private var pendingPermissionInit: (() -> Unit)? = null
    private var nativeUIScanner: NativeUIScanner? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textureRegistry = binding.textureRegistry
        methodChannel = MethodChannel(binding.binaryMessenger, "doclens/methods")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "doclens/events")
        eventChannel.setStreamHandler(eventStream)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        session?.dispose()
        session = null
        backgroundExecutor.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        val ui = NativeUIScanner(context).also { nativeUIScanner = it }
        binding.addActivityResultListener(ui)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        nativeUIScanner?.let { activityBinding?.removeActivityResultListener(it) }
        nativeUIScanner = null
        activity = null
        activityBinding = null
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "dispose" -> { session?.dispose(); session = null; result.success(null) }
            "capture" -> {
                val s = session
                if (s == null) { result.error("init_failed", "Not initialized", null); return }
                s.capture(result)
            }
            "warpImage" -> handleWarp(call, result)
            "setFlashMode" -> { session?.setFlashMode(call.argument<String>("mode") ?: "auto"); result.success(null) }
            "switchCamera" -> { session?.switchCamera(); result.success(null) }
            "pause" -> { session?.pause(); result.success(null) }
            "resume" -> { session?.resume(); result.success(null) }
            "focusAt" -> {
                val x = (call.argument<Number>("x") ?: 0.5).toFloat()
                val y = (call.argument<Number>("y") ?: 0.5).toFloat()
                session?.focus(x, y)
                result.success(null)
            }
            "scanWithNativeUI" -> handleNativeUIScan(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleNativeUIScan(call: MethodCall, result: MethodChannel.Result) {
        val activity = this.activity
        val ui = nativeUIScanner
        if (activity == null || ui == null) {
            result.error("init_failed", "No activity attached", null); return
        }
        ui.launch(
            activity = activity,
            pageLimit = (call.argument<Int>("pageLimit") ?: 100),
            allowGalleryImport = call.argument<Boolean>("allowGalleryImport") ?: false,
            jpegQuality = call.argument<Int>("jpegQuality") ?: 100,
            result = result,
        )
    }

    private fun handleWarp(call: MethodCall, result: MethodChannel.Result) {
        val rawPath = call.argument<String>("rawImagePath")
        val quadMap = call.argument<Map<String, Any?>>("quad")
        val quality = call.argument<Int>("jpegQuality") ?: 100
        if (rawPath == null || quadMap == null) {
            result.error("capture_failed", "Invalid warp args", null); return
        }
        backgroundExecutor.execute {
            try {
                val q = Quad.fromMap(quadMap)
                val out = ImageWarper.warpFile(rawPath, q, quality)
                mainHandler.post { result.success(out) }
            } catch (e: Exception) {
                mainHandler.post { result.error("capture_failed", e.message, null) }
            }
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val activity = this.activity
        if (activity == null) {
            result.error("init_failed", "No activity attached", null); return
        }
        // Tear down any previous session — never leak a running camera.
        session?.dispose()
        session = null

        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            pendingPermissionInit = { doInitialize(call, result) }
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST,
            )
            return
        }
        doInitialize(call, result)
    }

    @Suppress("UNCHECKED_CAST")
    private fun doInitialize(call: MethodCall, result: MethodChannel.Result) {
        val activity = this.activity ?: run {
            result.error("init_failed", "No activity attached", null); return
        }
        val cfg = ScannerConfig.fromMap(call.arguments as? Map<String, Any?> ?: emptyMap())
        val entry = textureRegistry.createSurfaceTexture()
        val s = ScannerSession(
            activity = activity,
            context = context,
            config = cfg,
            textureEntry = entry,
            eventSink = { eventStream.send(it) },
        )
        session = s
        s.start { startResult ->
            startResult.fold(
                onSuccess = { result.success(it) },
                onFailure = { err ->
                    val code = when (err) {
                        is ScannerException.PermissionDenied -> "permission_denied"
                        is ScannerException.Unavailable -> "unavailable"
                        else -> "init_failed"
                    }
                    entry.release()
                    session = null
                    result.error(code, err.message, null)
                },
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_PERMISSION_REQUEST) return false
        val pending = pendingPermissionInit ?: return true
        pendingPermissionInit = null
        // Either way, invoke the pending init: on grant it will start the
        // session normally; on denial `ScannerSession.start` re-checks
        // permission and surfaces `permission_denied` via the Result's
        // failure path.
        mainHandler.post(pending)
        return true
    }
}

class QuadEventStream : EventChannel.StreamHandler {
    @Volatile private var sink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    fun send(payload: Map<String, Any?>) {
        val s = sink ?: return
        mainHandler.post {
            try { s.success(payload) } catch (_: Exception) {}
        }
    }
}
