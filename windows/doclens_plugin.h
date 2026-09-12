#ifndef FLUTTER_PLUGIN_DOCLENS_PLUGIN_H_
#define FLUTTER_PLUGIN_DOCLENS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace doclens {

class DoclensPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  DoclensPlugin();

  virtual ~DoclensPlugin();

  // Disallow copy and assign.
  DoclensPlugin(const DoclensPlugin&) = delete;
  DoclensPlugin& operator=(const DoclensPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace doclens

#endif  // FLUTTER_PLUGIN_DOCLENS_PLUGIN_H_
