#include "include/doclens/doclens_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "doclens_plugin.h"

void DoclensPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  doclens::DoclensPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
