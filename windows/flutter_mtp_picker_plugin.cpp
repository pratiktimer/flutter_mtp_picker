#include "flutter_mtp_picker_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <PortableDeviceApi.h>
#include <PortableDevice.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <memory>
#include <set>
#include <string>
#include <variant>
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

std::string ToLowerAscii(std::string value) {
  for (char& character : value) {
    if (character >= 'A' && character <= 'Z') {
      character = static_cast<char>(character - 'A' + 'a');
    }
  }
  return value;
}

std::string NormalizeExtension(std::string extension) {
  extension = ToLowerAscii(extension);
  if (!extension.empty() && extension.front() == '.') {
    extension.erase(extension.begin());
  }
  return extension;
}

std::string FileExtension(const std::string& name) {
  const size_t dot = name.find_last_of('.');
  if (dot == std::string::npos || dot == name.size() - 1) {
    return "";
  }
  return ToLowerAscii(name.substr(dot + 1));
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }

  const int size =
      MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }

  std::wstring result(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), size);
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

HRESULT CreateClientInfo(IPortableDeviceValues** client_info) {
  ComPtr<IPortableDeviceValues> values;
  HRESULT hr = CoCreateInstance(CLSID_PortableDeviceValues, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&values));
  if (FAILED(hr)) {
    return hr;
  }

  values->SetStringValue(WPD_CLIENT_NAME, L"flutter_mtp_picker");
  values->SetUnsignedIntegerValue(WPD_CLIENT_MAJOR_VERSION, 1);
  values->SetUnsignedIntegerValue(WPD_CLIENT_MINOR_VERSION, 0);
  values->SetUnsignedIntegerValue(WPD_CLIENT_REVISION, 0);

  *client_info = values.Detach();
  return S_OK;
}

HRESULT OpenPortableDevice(const std::string& device_id,
                           IPortableDevice** device) {
  ComPtr<IPortableDevice> portable_device;
  HRESULT hr = CoCreateInstance(CLSID_PortableDevice, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&portable_device));
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IPortableDeviceValues> client_info;
  hr = CreateClientInfo(&client_info);
  if (FAILED(hr)) {
    return hr;
  }

  const std::wstring wide_device_id = Utf8ToWide(device_id);
  if (wide_device_id.empty()) {
    return E_INVALIDARG;
  }

  hr = portable_device->Open(wide_device_id.c_str(), client_info.Get());
  if (FAILED(hr)) {
    return hr;
  }

  *device = portable_device.Detach();
  return S_OK;
}

HRESULT CreateObjectPropertyKeys(IPortableDeviceKeyCollection** keys) {
  ComPtr<IPortableDeviceKeyCollection> key_collection;
  HRESULT hr = CoCreateInstance(CLSID_PortableDeviceKeyCollection, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&key_collection));
  if (FAILED(hr)) {
    return hr;
  }

  hr = key_collection->Add(WPD_OBJECT_NAME);
  if (FAILED(hr)) {
    return hr;
  }
  hr = key_collection->Add(WPD_OBJECT_ORIGINAL_FILE_NAME);
  if (FAILED(hr)) {
    return hr;
  }
  hr = key_collection->Add(WPD_OBJECT_CONTENT_TYPE);
  if (FAILED(hr)) {
    return hr;
  }
  hr = key_collection->Add(WPD_OBJECT_SIZE);
  if (FAILED(hr)) {
    return hr;
  }

  *keys = key_collection.Detach();
  return S_OK;
}

std::string GetStringProperty(IPortableDeviceValues* values,
                              const PROPERTYKEY& key) {
  PWSTR value = nullptr;
  const HRESULT hr = values->GetStringValue(key, &value);
  if (FAILED(hr) || value == nullptr) {
    return "";
  }

  std::string result = WideToUtf8(value);
  CoTaskMemFree(value);
  return result;
}

bool IsFolderContentType(const GUID& content_type) {
  return IsEqualGUID(content_type, WPD_CONTENT_TYPE_FOLDER) ||
         IsEqualGUID(content_type, WPD_CONTENT_TYPE_FUNCTIONAL_OBJECT);
}

uint64_t GetUnsignedLargeIntegerProperty(IPortableDeviceValues* values,
                                         const PROPERTYKEY& key) {
  ULONGLONG value = 0;
  const HRESULT hr = values->GetUnsignedLargeIntegerValue(key, &value);
  if (FAILED(hr)) {
    return 0;
  }
  return static_cast<uint64_t>(value);
}

HRESULT AppendObject(IPortableDeviceProperties* properties,
                     IPortableDeviceKeyCollection* keys,
                     const wchar_t* object_id,
                     flutter::EncodableList* children) {
  ComPtr<IPortableDeviceValues> values;
  HRESULT hr = properties->GetValues(object_id, keys, &values);
  if (FAILED(hr)) {
    return hr;
  }

  GUID content_type = GUID_NULL;
  values->GetGuidValue(WPD_OBJECT_CONTENT_TYPE, &content_type);

  std::string name = GetStringProperty(values.Get(), WPD_OBJECT_ORIGINAL_FILE_NAME);
  if (name.empty()) {
    name = GetStringProperty(values.Get(), WPD_OBJECT_NAME);
  }
  if (name.empty()) {
    name = WideToUtf8(object_id);
  }

  flutter::EncodableMap child;
  child[flutter::EncodableValue("id")] =
      flutter::EncodableValue(WideToUtf8(object_id));
  child[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
  child[flutter::EncodableValue("isFolder")] =
      flutter::EncodableValue(IsFolderContentType(content_type));
  children->push_back(flutter::EncodableValue(child));

  return S_OK;
}

HRESULT ReadObjectInfo(IPortableDeviceProperties* properties,
                       IPortableDeviceKeyCollection* keys,
                       const wchar_t* object_id,
                       std::string* name,
                       bool* is_folder,
                       uint64_t* size) {
  ComPtr<IPortableDeviceValues> values;
  HRESULT hr = properties->GetValues(object_id, keys, &values);
  if (FAILED(hr)) {
    return hr;
  }

  GUID content_type = GUID_NULL;
  values->GetGuidValue(WPD_OBJECT_CONTENT_TYPE, &content_type);

  *name = GetStringProperty(values.Get(), WPD_OBJECT_ORIGINAL_FILE_NAME);
  if (name->empty()) {
    *name = GetStringProperty(values.Get(), WPD_OBJECT_NAME);
  }
  if (name->empty()) {
    *name = WideToUtf8(object_id);
  }

  *is_folder = IsFolderContentType(content_type);
  *size = GetUnsignedLargeIntegerProperty(values.Get(), WPD_OBJECT_SIZE);
  return S_OK;
}

HRESULT AppendMediaFile(const wchar_t* object_id,
                        const std::string& name,
                        uint64_t size,
                        flutter::EncodableList* files) {
  flutter::EncodableMap file;
  file[flutter::EncodableValue("id")] =
      flutter::EncodableValue(WideToUtf8(object_id));
  file[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
  file[flutter::EncodableValue("size")] =
      flutter::EncodableValue(static_cast<int64_t>(size));
  files->push_back(flutter::EncodableValue(file));
  return S_OK;
}

bool MatchesExtension(const std::string& name,
                      const std::set<std::string>& extensions) {
  if (extensions.empty()) {
    return true;
  }
  return extensions.find(FileExtension(name)) != extensions.end();
}

HRESULT TraverseMediaFiles(IPortableDeviceContent* content,
                           IPortableDeviceProperties* properties,
                           IPortableDeviceKeyCollection* keys,
                           const std::wstring& parent_id,
                           const std::set<std::string>& extensions,
                           flutter::EncodableList* files) {
  ComPtr<IEnumPortableDeviceObjectIDs> enum_object_ids;
  HRESULT hr = content->EnumObjects(0, parent_id.c_str(), nullptr,
                                    &enum_object_ids);
  if (FAILED(hr)) {
    return hr;
  }

  constexpr DWORD kBatchSize = 16;
  PWSTR object_ids[kBatchSize] = {};
  DWORD fetched = 0;

  while (SUCCEEDED(hr = enum_object_ids->Next(kBatchSize, object_ids, &fetched)) &&
         fetched > 0) {
    for (DWORD i = 0; i < fetched; ++i) {
      if (object_ids[i] == nullptr) {
        continue;
      }

      std::string name;
      bool is_folder = false;
      uint64_t size = 0;
      const HRESULT info_hr = ReadObjectInfo(
          properties, keys, object_ids[i], &name, &is_folder, &size);
      if (FAILED(info_hr)) {
        CoTaskMemFree(object_ids[i]);
        object_ids[i] = nullptr;
        return info_hr;
      }

      HRESULT child_hr = S_OK;
      if (is_folder) {
        child_hr = TraverseMediaFiles(content, properties, keys, object_ids[i],
                                      extensions, files);
      } else if (MatchesExtension(name, extensions)) {
        child_hr = AppendMediaFile(object_ids[i], name, size, files);
      }

      CoTaskMemFree(object_ids[i]);
      object_ids[i] = nullptr;
      if (FAILED(child_hr)) {
        return child_hr;
      }
    }
  }

  if (hr == S_FALSE) {
    return S_OK;
  }

  return hr;
}

HRESULT ListMtpChildren(const std::string& device_id,
                        const std::string& object_id,
                        flutter::EncodableList* children) {
  ScopedComInitializer com;
  HRESULT hr = com.result();
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IPortableDevice> device;
  hr = OpenPortableDevice(device_id, &device);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IPortableDeviceContent> content;
  hr = device->Content(&content);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IPortableDeviceProperties> properties;
  hr = content->Properties(&properties);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IPortableDeviceKeyCollection> keys;
  hr = CreateObjectPropertyKeys(&keys);
  if (FAILED(hr)) {
    return hr;
  }

  const std::wstring parent_id =
      object_id == "ROOT" ? std::wstring(WPD_DEVICE_OBJECT_ID)
                          : Utf8ToWide(object_id);
  if (parent_id.empty()) {
    return E_INVALIDARG;
  }

  ComPtr<IEnumPortableDeviceObjectIDs> enum_object_ids;
  hr = content->EnumObjects(0, parent_id.c_str(), nullptr, &enum_object_ids);
  if (FAILED(hr)) {
    return hr;
  }

  constexpr DWORD kBatchSize = 16;
  PWSTR object_ids[kBatchSize] = {};
  DWORD fetched = 0;

  while (SUCCEEDED(hr = enum_object_ids->Next(kBatchSize, object_ids, &fetched)) &&
         fetched > 0) {
    for (DWORD i = 0; i < fetched; ++i) {
      if (object_ids[i] != nullptr) {
        const HRESULT append_hr =
            AppendObject(properties.Get(), keys.Get(), object_ids[i], children);
        CoTaskMemFree(object_ids[i]);
        object_ids[i] = nullptr;
        if (FAILED(append_hr)) {
          return append_hr;
        }
      }
    }
  }

  if (hr == S_FALSE) {
    return S_OK;
  }

  return hr;
}

HRESULT ListMtpMediaFiles(const std::string& device_id,
                          const std::string& folder_id,
                          const std::set<std::string>& extensions,
                          flutter::EncodableList* files) {
  ScopedComInitializer com;
  HRESULT hr = com.result();
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IPortableDevice> device;
  hr = OpenPortableDevice(device_id, &device);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IPortableDeviceContent> content;
  hr = device->Content(&content);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IPortableDeviceProperties> properties;
  hr = content->Properties(&properties);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IPortableDeviceKeyCollection> keys;
  hr = CreateObjectPropertyKeys(&keys);
  if (FAILED(hr)) {
    return hr;
  }

  const std::wstring parent_id =
      folder_id == "ROOT" ? std::wstring(WPD_DEVICE_OBJECT_ID)
                          : Utf8ToWide(folder_id);
  if (parent_id.empty()) {
    return E_INVALIDARG;
  }

  return TraverseMediaFiles(content.Get(), properties.Get(), keys.Get(),
                            parent_id, extensions, files);
}

bool ReadStringArgument(const flutter::EncodableMap& arguments,
                        const char* key,
                        std::string* value) {
  const auto it = arguments.find(flutter::EncodableValue(key));
  if (it == arguments.end() || !std::holds_alternative<std::string>(it->second)) {
    return false;
  }

  *value = std::get<std::string>(it->second);
  return true;
}

bool ReadStringListArgument(const flutter::EncodableMap& arguments,
                            const char* key,
                            std::set<std::string>* values) {
  const auto it = arguments.find(flutter::EncodableValue(key));
  if (it == arguments.end() ||
      !std::holds_alternative<flutter::EncodableList>(it->second)) {
    return false;
  }

  const auto& list = std::get<flutter::EncodableList>(it->second);
  for (const flutter::EncodableValue& item : list) {
    if (!std::holds_alternative<std::string>(item)) {
      return false;
    }

    const std::string normalized =
        NormalizeExtension(std::get<std::string>(item));
    if (!normalized.empty()) {
      values->insert(normalized);
    }
  }

  return true;
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
  } else if (method_call.method_name().compare("listChildren") == 0) {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments == nullptr) {
      result->Error("invalid_arguments", "listChildren expects an argument map.");
      return;
    }

    std::string device_id;
    std::string object_id;
    if (!ReadStringArgument(*arguments, "deviceId", &device_id) ||
        !ReadStringArgument(*arguments, "objectId", &object_id)) {
      result->Error(
          "invalid_arguments",
          "listChildren requires string arguments: deviceId and objectId.");
      return;
    }

    flutter::EncodableList children;
    const HRESULT hr = ListMtpChildren(device_id, object_id, &children);
    if (FAILED(hr)) {
      ReplyWithHResultError(std::move(result), "listChildren", hr);
      return;
    }

    result->Success(flutter::EncodableValue(children));
  } else if (method_call.method_name().compare("listMediaFiles") == 0) {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments == nullptr) {
      result->Error("invalid_arguments",
                    "listMediaFiles expects an argument map.");
      return;
    }

    std::string device_id;
    std::string folder_id;
    std::set<std::string> extensions;
    if (!ReadStringArgument(*arguments, "deviceId", &device_id) ||
        !ReadStringArgument(*arguments, "folderId", &folder_id) ||
        !ReadStringListArgument(*arguments, "extensions", &extensions)) {
      result->Error(
          "invalid_arguments",
          "listMediaFiles requires deviceId, folderId, and extensions.");
      return;
    }

    flutter::EncodableList files;
    const HRESULT hr =
        ListMtpMediaFiles(device_id, folder_id, extensions, &files);
    if (FAILED(hr)) {
      ReplyWithHResultError(std::move(result), "listMediaFiles", hr);
      return;
    }

    result->Success(flutter::EncodableValue(files));
  } else {
    result->NotImplemented();
  }
}

}  // namespace flutter_mtp_picker
