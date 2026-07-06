#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kAppTitle[] = L"\u9487\u68d2\u6587\u4ef6S";
constexpr const wchar_t kSecondInstancePrompt[] =
    L"\u68c0\u6d4b\u5230\u9487\u68d2\u6587\u4ef6S\u5df2\u7ecf\u5728\u8fd0\u884c\u3002\n\n"
    L"\u662f\uff1a\u5207\u6362\u5230\u5df2\u6253\u5f00\u7684\u7a97\u53e3\u5e76"
    L"\u5173\u95ed\u5f53\u524d\u542f\u52a8\n"
    L"\u5426\uff1a\u7ee7\u7eed\u6253\u5f00\u65b0\u7684\u7a97\u53e3\n"
    L"\u53d6\u6d88\uff1a\u9000\u51fa\u5f53\u524d\u542f\u52a8";
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\DiuBangFileS.SingleInstance";
HANDLE g_instance_mutex = nullptr;

void ActivateExistingInstanceWindow() {
  HWND existing_window = ::FindWindow(nullptr, kAppTitle);
  if (existing_window == nullptr) {
    return;
  }

  if (::IsIconic(existing_window)) {
    ::ShowWindow(existing_window, SW_RESTORE);
  } else {
    ::ShowWindow(existing_window, SW_SHOW);
  }
  ::BringWindowToTop(existing_window);
  ::SetForegroundWindow(existing_window);
  ::SetFocus(existing_window);
}

bool ShouldContinueLaunching() {
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  if (instance_mutex == nullptr) {
    return true;
  }

  const DWORD last_error = ::GetLastError();
  if (last_error != ERROR_ALREADY_EXISTS) {
    g_instance_mutex = instance_mutex;
    return true;
  }

  const int selection = ::MessageBoxW(
      nullptr, kSecondInstancePrompt, kAppTitle,
      MB_YESNOCANCEL | MB_ICONWARNING | MB_DEFBUTTON1 | MB_SETFOREGROUND);

  switch (selection) {
    case IDYES:
      ActivateExistingInstanceWindow();
      [[fallthrough]];
    case IDCANCEL:
      ::CloseHandle(instance_mutex);
      return false;
    case IDNO:
    default:
      ::CloseHandle(instance_mutex);
      return true;
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!ShouldContinueLaunching()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kAppTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
