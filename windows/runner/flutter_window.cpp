#include "flutter_window.h"

#include <windows.h>
#include <wincred.h>

#include <limits>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/standard_method_codec.h>

namespace {

constexpr wchar_t kCredentialTarget[] = L"AgentTower/connection.v1";
constexpr wchar_t kPreferencesRegistryPath[] = L"Software\\AgentTower";
constexpr wchar_t kPreferencesRegistryName[] = L"project_preferences";

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  if (value.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
    return {};
  }
  const int input_size = static_cast<int>(value.size());
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       value.data(), input_size, nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          input_size, result.data(), size) != size) {
    return {};
  }
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  if (value.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
    return {};
  }
  const int input_size = static_cast<int>(value.size());
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                       value.data(), input_size, nullptr, 0,
                                       nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(size, '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                          input_size, result.data(), size, nullptr,
                          nullptr) != size) {
    return {};
  }
  return result;
}

std::optional<std::string> ReadCredential() {
  PCREDENTIALW credential = nullptr;
  if (!CredReadW(kCredentialTarget, CRED_TYPE_GENERIC, 0, &credential)) {
    return std::nullopt;
  }
  std::string result(
      reinterpret_cast<const char*>(credential->CredentialBlob),
      credential->CredentialBlobSize);
  CredFree(credential);
  return result;
}

bool WriteCredential(const std::string& value) {
  CREDENTIALW credential{};
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = const_cast<wchar_t*>(kCredentialTarget);
  credential.CredentialBlobSize = static_cast<DWORD>(value.size());
  credential.CredentialBlob = reinterpret_cast<LPBYTE>(
      const_cast<char*>(value.data()));
  credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
  credential.UserName = const_cast<wchar_t*>(L"AgentTower");
  return CredWriteW(&credential, 0) == TRUE;
}

bool DeleteCredential() {
  if (CredDeleteW(kCredentialTarget, CRED_TYPE_GENERIC, 0)) return true;
  return GetLastError() == ERROR_NOT_FOUND;
}

std::optional<std::string> ReadProjectPreferences() {
  DWORD size = 0;
  const LSTATUS measured = RegGetValueW(
      HKEY_CURRENT_USER, kPreferencesRegistryPath, kPreferencesRegistryName,
      RRF_RT_REG_SZ, nullptr, nullptr, &size);
  if (measured == ERROR_FILE_NOT_FOUND) return std::nullopt;
  if (measured != ERROR_SUCCESS || size < sizeof(wchar_t)) return std::nullopt;
  std::wstring value(size / sizeof(wchar_t), L'\0');
  if (RegGetValueW(HKEY_CURRENT_USER, kPreferencesRegistryPath,
                   kPreferencesRegistryName, RRF_RT_REG_SZ, nullptr,
                   value.data(), &size) != ERROR_SUCCESS) {
    return std::nullopt;
  }
  while (!value.empty() && value.back() == L'\0') value.pop_back();
  return WideToUtf8(value);
}

bool WriteProjectPreferences(const std::string& value) {
  const std::wstring wide = Utf8ToWide(value);
  if (!value.empty() && wide.empty()) return false;
  return RegSetKeyValueW(
             HKEY_CURRENT_USER, kPreferencesRegistryPath,
             kPreferencesRegistryName, REG_SZ, wide.c_str(),
             static_cast<DWORD>((wide.size() + 1) * sizeof(wchar_t))) ==
         ERROR_SUCCESS;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  credentials_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.agenttower.mobile/credentials",
      &flutter::StandardMethodCodec::GetInstance());
  credentials_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        const std::string& method = call.method_name();
        if (method == "read") {
          const auto value = ReadCredential();
          if (value) {
            result->Success(flutter::EncodableValue(*value));
          } else if (GetLastError() == ERROR_NOT_FOUND) {
            result->Success();
          } else {
            result->Error("secure_storage", "Windows 凭证读取失败");
          }
          return;
        }
        if (method == "write") {
          const auto* value =
              std::get_if<std::string>(call.arguments());
          if (!value) {
            result->Error("argument", "Expected credential string");
          } else if (!WriteCredential(*value)) {
            result->Error("secure_storage", "Windows 凭证写入失败");
          } else {
            result->Success();
          }
          return;
        }
        if (method == "clear") {
          if (DeleteCredential()) {
            result->Success();
          } else {
            result->Error("secure_storage", "Windows 凭证删除失败");
          }
          return;
        }
        if (method == "readProjectPreferences") {
          const auto value = ReadProjectPreferences();
          value ? result->Success(flutter::EncodableValue(*value))
                : result->Success();
          return;
        }
        if (method == "writeProjectPreferences") {
          const auto* value =
              std::get_if<std::string>(call.arguments());
          if (!value) {
            result->Error("preferences", "Invalid preferences");
          } else if (!WriteProjectPreferences(*value)) {
            result->Error("preferences", "Windows 项目偏好写入失败");
          } else {
            result->Success();
          }
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    credentials_channel_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
