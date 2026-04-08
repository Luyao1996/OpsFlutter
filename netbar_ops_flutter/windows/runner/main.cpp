#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <DbgHelp.h>
#include <shlobj.h>
#include <ctime>
#include <cstdio>
#include <string>

#pragma comment(lib, "DbgHelp.lib")

#include "flutter_window.h"
#include "utils.h"

#include <flutter_webrtc/flutter_web_r_t_c_plugin.h>
#include <window_manager/window_manager_plugin.h>

// Register selected plugins in sub-windows created by desktop_multi_window
typedef void (*WindowCreatedCallback)(flutter::FlutterViewController *controller);
extern "C" void DesktopMultiWindowSetWindowCreatedCallback(WindowCreatedCallback callback);

// --- Crash handler: covers all threads ---

static std::wstring GetCrashLogDir() {
  wchar_t exePath[MAX_PATH];
  GetModuleFileNameW(nullptr, exePath, MAX_PATH);
  std::wstring dir(exePath);
  dir = dir.substr(0, dir.find_last_of(L'\\')) + L"\\crash_logs";
  CreateDirectoryW(dir.c_str(), nullptr);
  return dir;
}

volatile bool g_isShuttingDown = false;

static LONG WINAPI GlobalCrashHandler(EXCEPTION_POINTERS *exInfo) {
  if (g_isShuttingDown) {
    return EXCEPTION_EXECUTE_HANDLER;
  }

  std::wstring dir = GetCrashLogDir();

  // Generate filename with timestamp
  time_t now = time(nullptr);
  struct tm t;
  localtime_s(&t, &now);
  wchar_t ts[64];
  wcsftime(ts, 64, L"%Y%m%d_%H%M%S", &t);

  // Write MiniDump
  std::wstring dumpPath = dir + L"\\crash_" + ts + L".dmp";
  HANDLE hDump = CreateFileW(dumpPath.c_str(), GENERIC_WRITE, 0, nullptr,
                             CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (hDump != INVALID_HANDLE_VALUE) {
    MINIDUMP_EXCEPTION_INFORMATION mei;
    mei.ThreadId = GetCurrentThreadId();
    mei.ExceptionPointers = exInfo;
    mei.ClientPointers = FALSE;
    MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), hDump,
                      MiniDumpWithDataSegs, &mei, nullptr, nullptr);
    CloseHandle(hDump);
  }

  // Write text log
  std::wstring logPath = dir + L"\\crash_" + ts + L".log";
  HANDLE hLog = CreateFileW(logPath.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (hLog != INVALID_HANDLE_VALUE) {
    char buf[512];
    int len = _snprintf_s(buf, sizeof(buf), _TRUNCATE,
        "Unhandled Exception\r\n"
        "Code: 0x%08lX\r\n"
        "Address: 0x%p\r\n"
        "Thread: %lu\r\n",
        exInfo->ExceptionRecord->ExceptionCode,
        exInfo->ExceptionRecord->ExceptionAddress,
        GetCurrentThreadId());
    DWORD written;
    WriteFile(hLog, buf, len, &written, nullptr);
    CloseHandle(hLog);
  }

  // Show error dialog
  std::wstring msg = L"The application has crashed unexpectedly.\n\n"
                     L"Crash logs saved to:\n" + dir +
                     L"\n\nPlease send the crash_logs folder to the developer.";
  MessageBoxW(nullptr, msg.c_str(), L"Netbar Ops - Crash Report",
              MB_OK | MB_ICONERROR);

  return EXCEPTION_EXECUTE_HANDLER;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  SetUnhandledExceptionFilter(GlobalCrashHandler);
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

  // Register essential plugins in sub-windows for WebRTC remote desktop
  DesktopMultiWindowSetWindowCreatedCallback(
      [](flutter::FlutterViewController *controller) {
        auto engine = controller->engine();
        FlutterWebRTCPluginRegisterWithRegistrar(
            engine->GetRegistrarForPlugin("FlutterWebRTCPlugin"));
        WindowManagerPluginRegisterWithRegistrar(
            engine->GetRegistrarForPlugin("WindowManagerPlugin"));
      });

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1600, 900);
  if (!window.Create(L"netbar_ops_flutter", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  g_isShuttingDown = true;
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
