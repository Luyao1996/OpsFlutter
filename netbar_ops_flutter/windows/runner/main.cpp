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

// Relaunch exe from an ASCII junction path if current path contains non-ASCII.
// Returns true if relaunch was initiated (caller should exit immediately).
static bool RelaunchFromAsciiPath() {
  wchar_t exeFullPath[MAX_PATH];
  GetModuleFileNameW(nullptr, exeFullPath, MAX_PATH);
  std::wstring exePath(exeFullPath);
  std::wstring exeDir = exePath.substr(0, exePath.find_last_of(L'\\'));
  std::wstring exeName = exePath.substr(exePath.find_last_of(L'\\') + 1);

  // Check for non-ASCII characters in path
  bool hasNonAscii = false;
  for (wchar_t ch : exeDir) {
    if (ch > 127) { hasNonAscii = true; break; }
  }
  if (!hasNonAscii) return false;

  // Fixed ASCII junction path
  std::wstring junctionDir = L"C:\\ProgramData\\NetbarOps_run";

  // Already running from junction - do not re-launch (prevent infinite loop)
  if (exeDir.size() >= junctionDir.size() &&
      _wcsnicmp(exeDir.c_str(), junctionDir.c_str(), junctionDir.size()) == 0) {
    return false;
  }

  // Remove old junction (safe: RemoveDirectoryW on junction only removes the
  // link, not the target; fails harmlessly on non-empty real directories)
  RemoveDirectoryW(junctionDir.c_str());

  // Create NTFS junction via cmd (no admin required)
  std::wstring cmdLine = L"cmd.exe /c mklink /J \"" + junctionDir +
                         L"\" \"" + exeDir + L"\"";
  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION pi = {};
  if (CreateProcessW(nullptr, &cmdLine[0], nullptr, nullptr, FALSE,
                     CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
    WaitForSingleObject(pi.hProcess, 5000);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
  }

  // Verify junction was created
  if (GetFileAttributesW(junctionDir.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return false;
  }

  // Re-launch exe from the junction path
  std::wstring newExe = junctionDir + L"\\" + exeName;
  STARTUPINFOW si2 = {};
  si2.cb = sizeof(si2);
  PROCESS_INFORMATION pi2 = {};
  if (CreateProcessW(newExe.c_str(), GetCommandLineW(), nullptr, nullptr, FALSE,
                     0, nullptr, junctionDir.c_str(), &si2, &pi2)) {
    CloseHandle(pi2.hThread);
    CloseHandle(pi2.hProcess);
    return true;
  }

  return false;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // If exe path contains non-ASCII, relaunch from an ASCII junction
  if (RelaunchFromAsciiPath()) {
    return 0;
  }

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
