#pragma once

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>

#include <windows.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <mutex>
#include <condition_variable>
#include <memory>
#include <atomic>
#include <thread>

#define WM_VCLIPBOARD_REQUEST (WM_APP + 100)

struct VClipboardRequestParams {
    void* plugin;
    int fileIndex;
    int64_t offset;
    int64_t size;
};

struct VirtualFileEntry {
    std::string name;
    int64_t fileSize;
    int index;
    bool isDir = false;
};

class VirtualClipboardPlugin {
public:
    static void Register(flutter::BinaryMessenger* messenger);
    static VirtualClipboardPlugin* GetInstance() { return instance_; }
    void SetWindowHandle(HWND hwnd) { hwnd_ = hwnd; }

    void ProvideFileData(int fileIndex, const std::vector<uint8_t>& data);
    void ProvideFileError(int fileIndex);

    bool RequestFileData(int fileIndex, int64_t offset, int64_t requestSize,
                         std::vector<uint8_t>& outData);

private:
    VirtualClipboardPlugin(flutter::BinaryMessenger* messenger);
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    void SetVirtualClipboard(const std::vector<VirtualFileEntry>& files);
    void ClearClipboard();

    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
    flutter::BinaryMessenger* messenger_;
    HWND hwnd_ = nullptr;

    std::mutex pull_mutex_;
    std::condition_variable pull_cv_;
    std::vector<uint8_t> pull_buffer_;
    bool pull_data_ready_ = false;
    bool pull_error_ = false;

    std::thread ole_thread_;
    std::atomic<bool> ole_active_{false};
    std::vector<VirtualFileEntry> current_files_;

    static VirtualClipboardPlugin* instance_;
};
