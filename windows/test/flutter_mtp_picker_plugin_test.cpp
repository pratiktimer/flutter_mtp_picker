#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "flutter_mtp_picker_plugin.h"

namespace flutter_mtp_picker {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(FlutterMtpPickerPlugin, GetDevices) {
  FlutterMtpPickerPlugin plugin;
  // Save the reply value from the success callback.
  EncodableValue result_value;
  plugin.HandleMethodCall(
      MethodCall("getDevices", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&result_value](const EncodableValue* result) {
            result_value = *result;
          },
          nullptr, nullptr));

  EXPECT_TRUE(std::holds_alternative<flutter::EncodableList>(result_value));
}

}  // namespace test
}  // namespace flutter_mtp_picker
