#include "include/flutter_mtp_picker/flutter_mtp_picker_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_mtp_picker_plugin.h"

void FlutterMtpPickerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_mtp_picker::FlutterMtpPickerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
