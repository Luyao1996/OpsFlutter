//
// Created by yangbin on 2022/1/11.
//

#include "flutter_window.h"
#include "../../../windows/runner/virtual_clipboard.h"

#include "flutter_windows.h"

#include "tchar.h"
#include <windowsx.h>

#include <iostream>
#include <utility>

#include "include/desktop_multi_window/desktop_multi_window_plugin.h"
#include "multi_window_plugin_internal.h"

namespace {

WindowCreatedCallback _g_window_created_callback = nullptr;

TCHAR kFlutterWindowClassName[] = _T("FlutterMultiWindow");

int32_t class_registered_ = 0;

void RegisterWindowClass(WNDPROC wnd_proc) {
  if (class_registered_ == 0) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kFlutterWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, IDI_APPLICATION);
    window_class.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = wnd_proc;
    RegisterClass(&window_class);
  }
  class_registered_++;
}

void UnregisterWindowClass() {
  class_registered_--;
  if (class_registered_ != 0) {
    return;
  }
  UnregisterClass(kFlutterWindowClassName, nullptr);
}

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
inline int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling *>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
    FreeLibrary(user32_module);
  }
}

bool ShouldHideNativeChrome(const std::string &args) {
  const auto key_pos = args.find("\"hideNativeChrome\"");
  if (key_pos == std::string::npos) return false;
  const auto true_pos = args.find("true", key_pos);
  if (true_pos == std::string::npos) return false;
  return (true_pos - key_pos) < 64;
}

// System-aware resize border width (matches Windows native behavior).
inline int GetResizeBorderWidth() {
  return GetSystemMetrics(SM_CXSIZEFRAME) + GetSystemMetrics(SM_CXPADDEDBORDER);
}

}

FlutterWindow::FlutterWindow(
    int64_t id,
    std::string args,
    const std::shared_ptr<FlutterWindowCallback> &callback
) : callback_(callback), id_(id), window_handle_(nullptr), scale_factor_(1) {
  RegisterWindowClass(FlutterWindow::WndProc);

  const POINT target_point = {static_cast<LONG>(10),
                              static_cast<LONG>(10)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  scale_factor_ = dpi / 96.0;

  hide_chrome_ = ShouldHideNativeChrome(args);

  // Use chromeless style at creation time to avoid flicker
  const DWORD style = hide_chrome_
      ? (WS_OVERLAPPEDWINDOW & ~(WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX))
      : WS_OVERLAPPEDWINDOW;

  HWND window_handle = CreateWindow(
      kFlutterWindowClassName, L"", style,
      Scale(target_point.x, scale_factor_), Scale(target_point.y, scale_factor_),
      Scale(1280, scale_factor_), Scale(720, scale_factor_),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  RECT frame;
  GetClientRect(window_handle, &frame);
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments({"multi_window", std::to_string(id), std::move(args)});
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    std::cerr << "Failed to setup FlutterViewController." << std::endl;
  }
  auto view_handle = flutter_controller_->view()->GetNativeWindow();
  SetParent(view_handle, window_handle);
  MoveWindow(view_handle, 0, 0, frame.right - frame.left, frame.bottom - frame.top, true);

  // Subclass the Flutter child view so its border zone returns HTTRANSPARENT,
  // allowing the parent window's WM_NCHITTEST to handle resize hit-testing.
  if (hide_chrome_ && view_handle) {
    child_view_handle_ = view_handle;
    SetWindowSubclass(view_handle, FlutterWindow::ChildHitTestSubclassProc,
                      /*uIdSubclass=*/1,
                      reinterpret_cast<DWORD_PTR>(window_handle));
  }

  InternalMultiWindowPluginRegisterWithRegistrar(
      flutter_controller_->engine()->GetRegistrarForPlugin("DesktopMultiWindowPlugin"));
  window_channel_ = WindowChannel::RegisterWithRegistrar(
      flutter_controller_->engine()->GetRegistrarForPlugin("DesktopMultiWindowPlugin"), id_);

  if (_g_window_created_callback) {
    _g_window_created_callback(flutter_controller_.get());
  }

  // Register virtual clipboard plugin for remote clipboard file sync
  VirtualClipboardPlugin::Register(flutter_controller_->engine()->messenger());
  if (auto* vcp = VirtualClipboardPlugin::GetInstance()) {
    vcp->SetWindowHandle(window_handle);
  }

  // hide the window when created.
  ShowWindow(window_handle, SW_HIDE);

}

// static
FlutterWindow *FlutterWindow::GetThisFromHandle(HWND window) noexcept {
  return reinterpret_cast<FlutterWindow *>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

// static - Subclass proc for the Flutter child view window.
// When the mouse is within the parent's resize border zone, returns HTTRANSPARENT
// so that Windows forwards WM_NCHITTEST to the parent (our custom handler).
LRESULT CALLBACK FlutterWindow::ChildHitTestSubclassProc(
    HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam,
    UINT_PTR uIdSubclass, DWORD_PTR dwRefData) {
  if (uMsg == WM_NCHITTEST) {
    HWND parent = reinterpret_cast<HWND>(dwRefData);
    LONG style = GetWindowLong(parent, GWL_STYLE);
    // Only transparent at border when resizable (has WS_THICKFRAME) and not maximized.
    // Fullscreen removes WS_THICKFRAME, so border stays opaque to preserve hover events.
    if ((style & WS_THICKFRAME) && !IsZoomed(parent)) {
      const int border = GetResizeBorderWidth();
      RECT rc;
      GetWindowRect(parent, &rc);
      const int x = GET_X_LPARAM(lParam);
      const int y = GET_Y_LPARAM(lParam);
      if (x < rc.left + border || x > rc.right  - border ||
          y < rc.top  + border || y > rc.bottom - border) {
        return HTTRANSPARENT;
      }
    }
  } else if (uMsg == WM_NCDESTROY) {
    // Clean up subclass when child window is destroyed
    RemoveWindowSubclass(hWnd, ChildHitTestSubclassProc, uIdSubclass);
  }
  return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

// static
LRESULT CALLBACK FlutterWindow::WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT *>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<FlutterWindow *>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (FlutterWindow *that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {

  // Highest priority: hideNativeChrome interception.
  // Must run BEFORE Flutter engine and plugins (e.g. window_manager),
  // otherwise plugins will handle the message first and restore the title bar.
  if (hide_chrome_) {
    switch (message) {
      case WM_NCCALCSIZE:
        // Entire window rect is client area - no title bar, no border
        return 0;
      case WM_NCPAINT:
        // Skip all non-client area painting
        return 0;
      case WM_NCHITTEST: {
        // No resize when maximized or fullscreen (WS_THICKFRAME removed)
        if (IsZoomed(hwnd)) return HTCLIENT;
        if (!(GetWindowLong(hwnd, GWL_STYLE) & WS_THICKFRAME)) return HTCLIENT;
        // System-aware resize border (matches ChildHitTestSubclassProc)
        const int border = GetResizeBorderWidth();
        RECT rc;
        GetWindowRect(hwnd, &rc);
        int x = GET_X_LPARAM(lparam);
        int y = GET_Y_LPARAM(lparam);
        bool left   = x < rc.left   + border;
        bool right  = x > rc.right  - border;
        bool top    = y < rc.top    + border;
        bool bottom = y > rc.bottom - border;
        if (top    && left)  return HTTOPLEFT;
        if (top    && right) return HTTOPRIGHT;
        if (bottom && left)  return HTBOTTOMLEFT;
        if (bottom && right) return HTBOTTOMRIGHT;
        if (left)   return HTLEFT;
        if (right)  return HTRIGHT;
        if (top)    return HTTOP;
        if (bottom) return HTBOTTOM;
        return HTCLIENT;
      }
      // Forward non-client button messages directly to DefWindowProc,
      // bypassing Flutter engine / plugins (e.g. window_manager) that
      // may consume them and prevent the system resize modal loop.
      case WM_NCLBUTTONDOWN:
      case WM_NCLBUTTONDBLCLK:
        return DefWindowProc(hwnd, message, wparam, lparam);
      case WM_GETMINMAXINFO: {
        MINMAXINFO* mmi = reinterpret_cast<MINMAXINFO*>(lparam);
        mmi->ptMinTrackSize.x = static_cast<LONG>(400 * scale_factor_);
        mmi->ptMinTrackSize.y = static_cast<LONG>(300 * scale_factor_);
        return 0;
      }
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result = flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  auto child_content_ = flutter_controller_ ? flutter_controller_->view()->GetNativeWindow() : nullptr;

  switch (message) {
    case WM_FONTCHANGE: {
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    }
    case WM_DESTROY: {
      Destroy();
      if (!destroyed_) {
        destroyed_ = true;
        if (auto callback = callback_.lock()) {
          callback->OnWindowDestroy(id_);
        }
      }
      return 0;
    }
    case WM_CLOSE: {
      if (auto callback = callback_.lock()) {
        callback->OnWindowClose(id_);
      }
      break;
    }
    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT *>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect;
      GetClientRect(window_handle_, &rect);
      if (child_content_ != nullptr) {
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE: {
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;
    }
    case WM_VCLIPBOARD_REQUEST: {
      auto* params = reinterpret_cast<VClipboardRequestParams*>(wparam);
      if (params && flutter_controller_) {
        auto* plugin = VirtualClipboardPlugin::GetInstance();
        if (plugin && plugin == params->plugin) {
          auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
              flutter_controller_->engine()->messenger(),
              "com.webrtcgo/virtual_clipboard",
              &flutter::StandardMethodCodec::GetInstance());

          flutter::EncodableMap args;
          args[flutter::EncodableValue("fileIndex")] = flutter::EncodableValue(params->fileIndex);
          args[flutter::EncodableValue("offset")] = flutter::EncodableValue(params->offset);
          args[flutter::EncodableValue("size")] = flutter::EncodableValue(params->size);

          channel->InvokeMethod("requestFileData",
              std::make_unique<flutter::EncodableValue>(flutter::EncodableValue(args)));
        }
        delete params;
      }
      return 0;
    }
    default: break;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void FlutterWindow::Destroy() {
  if (window_channel_) {
    window_channel_ = nullptr;
  }
  // Remove subclass before destroying the Flutter controller
  if (child_view_handle_) {
    RemoveWindowSubclass(child_view_handle_, ChildHitTestSubclassProc, 1);
    child_view_handle_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
}

FlutterWindow::~FlutterWindow() {
  if (window_handle_) {
    std::cout << "window_handle leak." << std::endl;
  }
  UnregisterWindowClass();
}

void DesktopMultiWindowSetWindowCreatedCallback(WindowCreatedCallback callback) {
  _g_window_created_callback = callback;
}
