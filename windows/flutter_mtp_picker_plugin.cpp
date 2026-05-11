#include "flutter_mtp_picker_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <PortableDeviceApi.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <memory>
#include <string>
#include <vector>

namespace flutter_mtp_picker {
namespace {

using Microsoft::WRL::ComPtr;

std::string WideToUtf8(const wchar_t* value) {
  if (value == nullptr || value[0] == L'\0') {
    return "";
  }

  const int size = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0,
                                       nullptr, nullptr);
  if (size <= 0) {
    return "";
  }

  std::string result(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), size, nullptr,
                      nullptr);
  return result;
}

std::string HResultMessage(HRESULT hr) {
  wchar_t* message = nullptr;
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, static_cast<DWORD>(hr), MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<wchar_t*>(&message), 0, nullptr);

  if (length == 0 || message == nullptr) {
    return "Windows Portable Devices call failed.";
  }

  std::string result = WideToUtf8(message);
  LocalFree(message);
  return result;
}

class ScopedComInitializer {
 public:
  ScopedComInitializer() {
    hr_ = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    should_uninitialize_ = SUCCEEDED(hr_);
  }

  ~ScopedComInitializer() {
    if (should_uninitialize_) {
      CoUninitialize();
    }
  }

  HRESULT result() const {
    if (hr_ == RPC_E_CHANGED_MODE) {
      return S_OK;
    }
    return hr_;
  }

 private:
  HRESULT hr_ = E_FAIL;
  bool should_uninitialize_ = false;
};

std::string GetDeviceFriendlyName(IPortableDeviceManager* device_manager,
                                  const wchar_t* device_id) {
  DWORD name_length = 0;
  HRESULT hr =
      device_manager->GetDeviceFriendlyName(device_id, nullptr, &name_length);
  if (FAILED(hr) || name_length == 0) {
    return WideToUtf8(device_id);
  }

  std::vector<wchar_t> name(name_length);
  hr = device_manager->GetDeviceFriendlyName(device_id, name.data(),
                                             &name_length);
  if (FAILED(hr) || name.empty() || name[0] == L'\0') {
    return WideToUtf8(device_id);
  }

  return WideToUtf8(name.data());
}

HRESULT EnumerateMtpDevices(flutter::EncodableList* devices) {
  ScopedComInitializer com;
  HRESULT hr = com.result();
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IPortableDeviceManager> device_manager;
  hr = CoCreateInstance(CLSID_PortableDeviceManager, nullptr, CLSCTX_INPROC_SERVER,
                        IID_PPV_ARGS(&device_manager));
  if (FAILED(hr)) {
    return hr;
  }

  DWORD device_count = 0;
  hr = device_manager->GetDevices(nullptr, &device_count);
  if (FAILED(hr)) {
    return hr;
  }

  if (device_count == 0) {
    return S_OK;
  }

  std::vector<PWSTR> device_ids(device_count, nullptr);
  hr = device_manager->GetDevices(device_ids.data(), &device_count);
  if (FAILED(hr)) {
    return hr;
  }

  for (DWORD i = 0; i < device_count; ++i) {
    PWSTR device_id = device_ids[i];
    if (device_id == nullptr) {
      continue;
    }

    flutter::EncodableMap device;
    device[flutter::EncodableValue("id")] =
        flutter::EncodableValue(WideToUtf8(device_id));
    device[flutter::EncodableValue("name")] =
        flutter::EncodableValue(GetDeviceFriendlyName(device_manager.Get(),
                                                      device_id));
    devices->push_back(flutter::EncodableValue(device));

    CoTaskMemFree(device_id);
  }

  return S_OK;
}

void ReplyWithHResultError(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
    const std::string& operation,
    HRESULT hr) {
  result->Error("windows_wpd_error",
                operation + " failed: " + HResultMessage(hr),
                flutter::EncodableValue(static_cast<int>(hr)));
}

}  // namespace

// static
void FlutterMtpPickerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "flutter_mtp_picker",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterMtpPickerPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FlutterMtpPickerPlugin::FlutterMtpPickerPlugin() {}

FlutterMtpPickerPlugin::~FlutterMtpPickerPlugin() {}

void FlutterMtpPickerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getDevices") == 0) {
    flutter::EncodableList devices;
    const HRESULT hr = EnumerateMtpDevices(&devices);
    if (FAILED(hr)) {
      ReplyWithHResultError(std::move(result), "getDevices", hr);
      return;
    }

    result->Success(flutter::EncodableValue(devices));
  } else {
    result->NotImplemented();
  }
}

}  // namespace flutter_mtp_picker
