package dev.doclens.doclens

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.ActivityCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions.RESULT_FORMAT_JPEG
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions.SCANNER_MODE_FULL
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/**
 * Presents Google's native document scanner (ML Kit `GmsDocumentScanner`).
 *
 * References:
 * - https://developers.google.com/ml-kit/vision/doc-scanner/android
 * - https://developers.google.com/ml-kit/reference/android
 *
 * Implementation notes:
 * - Uses legacy `startIntentSenderForResult` + `PluginRegistry.ActivityResultListener`
 *   because Flutter plugins can't easily use `ActivityResultLauncher`
 *   (the host Activity is already created by the time we attach).
 * - Copies the returned `content://` URIs to our own cache directory so
 *   callers get stable file paths and aren't bitten by Play Services
 *   reclaiming its private cache.
 * - Camera permission is NOT requested here — the scanner Activity lives
 *   in the Play Services process and handles its own permission prompts.
 */
class NativeUIScanner(
    private val context: Context,
) : PluginRegistry.ActivityResultListener {

    private val ioExecutor: Executor = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var pendingJpegQuality: Int = 92

    fun isRegistered(): Boolean = pending != null

    fun launch(
        activity: Activity,
        pageLimit: Int,
        allowGalleryImport: Boolean,
        jpegQuality: Int,
        result: MethodChannel.Result,
    ) {
        if (pending != null) {
            result.error("capture_failed", "Native scanner already presented", null)
            return
        }
        // Block early when the device has no Google Play services at all.
        val gpsAvail = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(context)
        if (gpsAvail != ConnectionResult.SUCCESS) {
            result.error(
                "unavailable",
                "Google Play services unavailable (code $gpsAvail). " +
                    "ML Kit Document Scanner is unsupported on this device.",
                null,
            )
            return
        }

        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(allowGalleryImport)
            .setPageLimit(pageLimit.coerceIn(1, 100))
            .setResultFormats(RESULT_FORMAT_JPEG)
            .setScannerMode(SCANNER_MODE_FULL)
            .build()
        pending = result
        pendingJpegQuality = jpegQuality.coerceIn(1, 100)

        GmsDocumentScanning.getClient(options)
            .getStartScanIntent(activity)
            .addOnSuccessListener { intentSender ->
                try {
                    ActivityCompat.startIntentSenderForResult(
                        activity, intentSender, REQUEST_CODE, null, 0, 0, 0, null,
                    )
                } catch (e: Exception) {
                    val cb = pending; pending = null
                    cb?.error("capture_failed",
                        "Failed launching native scanner: ${e.message}", null)
                }
            }
            .addOnFailureListener { e ->
                val cb = pending; pending = null
                cb?.error("unavailable",
                    "Cannot start native scanner: ${e.message}", null)
            }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val cb = pending
        pending = null
        if (cb == null) return true
        if (resultCode != Activity.RESULT_OK) {
            // User cancelled — consistent with iOS: return null.
            cb.success(null)
            return true
        }
        val parsed = GmsDocumentScanningResult.fromActivityResultIntent(data)
        val uris: List<Uri> = parsed?.pages?.map { it.imageUri } ?: emptyList()
        // Copy off the IO thread so MethodChannel reply stays snappy.
        ioExecutor.execute {
            val paths = ArrayList<String>(uris.size)
            try {
                uris.forEachIndexed { i, uri ->
                    paths.add(copyToCache(uri, i))
                }
                postSuccess(cb, paths)
            } catch (e: Exception) {
                postError(cb, "capture_failed",
                    "Failed copying scanned page: ${e.message}")
            }
        }
        return true
    }

    private fun copyToCache(uri: Uri, index: Int): String {
        val outFile = File(
            context.cacheDir,
            "fnds_native_${System.currentTimeMillis()}_${index}.jpg",
        )
        context.contentResolver.openInputStream(uri)?.use { input ->
            outFile.outputStream().use { output -> input.copyTo(output) }
        } ?: error("Cannot open scanner output: $uri")
        return outFile.absolutePath
    }

    private fun postSuccess(cb: MethodChannel.Result, paths: List<String>) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            cb.success(paths)
        }
    }

    private fun postError(cb: MethodChannel.Result, code: String, message: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            cb.error(code, message, null)
        }
    }

    companion object {
        private const val REQUEST_CODE = 0x4F4D
    }
}
