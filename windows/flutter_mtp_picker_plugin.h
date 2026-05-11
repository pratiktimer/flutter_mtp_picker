#ifndef FLUTTER_PLUGIN_FLUTTER_MTP_PICKER_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_MTP_PICKER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_mtp_picker {

class FlutterMtpPickerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterMtpPickerPlugin();

  virtual ~FlutterMtpPickerPlugin();

  // Disallow copy and assign.
  FlutterMtpPickerPlugin(const FlutterMtpPickerPlugin&) = delete;
  FlutterMtpPickerPlugin& operator=(const FlutterMtpPickerPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace flutter_mtp_picker

#endif  // FLUTTER_PLUGIN_FLUTTER_MTP_PICKER_PLUGIN_H_
