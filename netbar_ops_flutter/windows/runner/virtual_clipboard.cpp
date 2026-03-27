#include "virtual_clipboard.h"
#include <algorithm>
#include <cstring>

static UINT g_cfFileDescriptorW = 0;
static UINT g_cfFileContents = 0;

static void EnsureFormats() {
    if (!g_cfFileDescriptorW) {
        g_cfFileDescriptorW = RegisterClipboardFormatW(CFSTR_FILEDESCRIPTORW);
        g_cfFileContents = RegisterClipboardFormatW(CFSTR_FILECONTENTS);
    }
}

static std::wstring Utf8ToWide(const std::string& str) {
    if (str.empty()) return {};
    int wlen = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, nullptr, 0);
    if (wlen <= 0) return {};
    std::wstring wstr(wlen - 1, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, &wstr[0], wlen);
    return wstr;
}

// ==================== VirtualFileStream ====================

class VirtualFileStream : public IStream {
public:
    VirtualFileStream(VirtualClipboardPlugin* plug, int idx, int64_t fsize)
        : plugin_(plug), file_index_(idx), file_size_(fsize),
          position_(0), ref_(1) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IStream || riid == IID_ISequentialStream) {
            *ppv = static_cast<IStream*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++ref_; }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG c = --ref_;
        if (c == 0) delete this;
        return c;
    }

    HRESULT STDMETHODCALLTYPE Read(void* pv, ULONG cb, ULONG* pcbRead) override {
        if (!pv) return E_POINTER;
        if (pcbRead) *pcbRead = 0;
        if (position_ >= file_size_) return S_FALSE;

        int64_t remaining = file_size_ - position_;
        ULONG toRead = static_cast<ULONG>((std::min)(static_cast<int64_t>(cb), remaining));

        std::vector<uint8_t> buf;
        bool ok = plugin_->RequestFileData(file_index_, position_, toRead, buf);
        if (!ok || buf.empty()) return E_FAIL;

        ULONG actual = static_cast<ULONG>((std::min)(static_cast<size_t>(toRead), buf.size()));
        memcpy(pv, buf.data(), actual);
        position_ += actual;
        if (pcbRead) *pcbRead = actual;
        return (position_ >= file_size_) ? S_FALSE : S_OK;
    }

    HRESULT STDMETHODCALLTYPE Write(const void*, ULONG, ULONG*) override { return E_NOTIMPL; }

    HRESULT STDMETHODCALLTYPE Seek(LARGE_INTEGER move, DWORD origin, ULARGE_INTEGER* newPos) override {
        int64_t np;
        switch (origin) {
            case STREAM_SEEK_SET: np = move.QuadPart; break;
            case STREAM_SEEK_CUR: np = position_ + move.QuadPart; break;
            case STREAM_SEEK_END: np = file_size_ + move.QuadPart; break;
            default: return E_INVALIDARG;
        }
        if (np < 0) np = 0;
        position_ = np;
        if (newPos) newPos->QuadPart = position_;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE SetSize(ULARGE_INTEGER) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE CopyTo(IStream*, ULARGE_INTEGER, ULARGE_INTEGER*, ULARGE_INTEGER*) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE Commit(DWORD) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE Revert() override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE LockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE UnlockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE Stat(STATSTG* pst, DWORD) override {
        if (!pst) return E_POINTER;
        memset(pst, 0, sizeof(*pst));
        pst->type = STGTY_STREAM;
        pst->cbSize.QuadPart = file_size_;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Clone(IStream**) override { return E_NOTIMPL; }

private:
    VirtualClipboardPlugin* plugin_;
    int file_index_;
    int64_t file_size_;
    int64_t position_;
    ULONG ref_;
};

// ==================== VirtualEnumFORMATETC ====================

class VirtualEnumFORMATETC : public IEnumFORMATETC {
public:
    VirtualEnumFORMATETC(const std::vector<FORMATETC>& fmts)
        : fmts_(fmts), pos_(0), ref_(1) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IEnumFORMATETC) {
            *ppv = this; AddRef(); return S_OK;
        }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++ref_; }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG c = --ref_;
        if (c == 0) delete this;
        return c;
    }
    HRESULT STDMETHODCALLTYPE Next(ULONG celt, FORMATETC* rgelt, ULONG* pceltFetched) override {
        ULONG fetched = 0;
        while (fetched < celt && pos_ < fmts_.size()) {
            rgelt[fetched++] = fmts_[pos_++];
        }
        if (pceltFetched) *pceltFetched = fetched;
        return (fetched == celt) ? S_OK : S_FALSE;
    }
    HRESULT STDMETHODCALLTYPE Skip(ULONG celt) override {
        pos_ += celt;
        return (pos_ <= fmts_.size()) ? S_OK : S_FALSE;
    }
    HRESULT STDMETHODCALLTYPE Reset() override { pos_ = 0; return S_OK; }
    HRESULT STDMETHODCALLTYPE Clone(IEnumFORMATETC** ppEnum) override {
        auto* e = new VirtualEnumFORMATETC(fmts_);
        e->pos_ = pos_;
        *ppEnum = e;
        return S_OK;
    }

private:
    std::vector<FORMATETC> fmts_;
    size_t pos_;
    ULONG ref_;
};

// ==================== VirtualFileDataObject ====================

class VirtualFileDataObject : public IDataObject {
public:
    VirtualFileDataObject(VirtualClipboardPlugin* plug,
                          const std::vector<VirtualFileEntry>& files)
        : plugin_(plug), files_(files), ref_(1) {
        EnsureFormats();
    }

    virtual ~VirtualFileDataObject() {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IDataObject) {
            *ppv = static_cast<IDataObject*>(this); AddRef(); return S_OK;
        }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++ref_; }
    ULONG STDMETHODCALLTYPE Release() override {
        ULONG c = --ref_;
        if (c == 0) delete this;
        return c;
    }

    HRESULT STDMETHODCALLTYPE GetData(FORMATETC* pFE, STGMEDIUM* pMedium) override {
        if (!pFE || !pMedium) return E_POINTER;
        memset(pMedium, 0, sizeof(*pMedium));

        if (pFE->cfFormat == g_cfFileDescriptorW && (pFE->tymed & TYMED_HGLOBAL)) {
            size_t count = files_.size();
            size_t allocSize = sizeof(FILEGROUPDESCRIPTORW) +
                (count > 0 ? (count - 1) * sizeof(FILEDESCRIPTORW) : 0);
            HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, allocSize);
            if (!hMem) return E_OUTOFMEMORY;

            auto* fgd = static_cast<FILEGROUPDESCRIPTORW*>(GlobalLock(hMem));
            if (!fgd) { GlobalFree(hMem); return E_OUTOFMEMORY; }
            fgd->cItems = static_cast<UINT>(count);

            for (size_t i = 0; i < count; i++) {
                FILEDESCRIPTORW& fd = fgd->fgd[i];
                fd.dwFlags = FD_FILESIZE | FD_PROGRESSUI | FD_ATTRIBUTES;
                if (files_[i].isDir) {
                    fd.dwFileAttributes = FILE_ATTRIBUTE_DIRECTORY;
                    fd.nFileSizeLow = 0;
                    fd.nFileSizeHigh = 0;
                } else {
                    fd.dwFileAttributes = FILE_ATTRIBUTE_NORMAL;
                    fd.nFileSizeLow = static_cast<DWORD>(files_[i].fileSize & 0xFFFFFFFF);
                    fd.nFileSizeHigh = static_cast<DWORD>(files_[i].fileSize >> 32);
                }

                std::wstring wname = Utf8ToWide(files_[i].name);
                for (auto& ch : wname) { if (ch == L'/') ch = L'\\'; }
                wcsncpy_s(fd.cFileName, MAX_PATH, wname.c_str(), _TRUNCATE);
            }

            GlobalUnlock(hMem);
            pMedium->tymed = TYMED_HGLOBAL;
            pMedium->hGlobal = hMem;
            return S_OK;
        }

        if (pFE->cfFormat == g_cfFileContents && (pFE->tymed & TYMED_ISTREAM)) {
            int idx = pFE->lindex;
            if (idx < 0 || idx >= static_cast<int>(files_.size())) return DV_E_LINDEX;

            // Directory entries don't need IStream content
            if (files_[idx].isDir) return DV_E_LINDEX;

            auto* stream = new VirtualFileStream(plugin_, files_[idx].index, files_[idx].fileSize);
            pMedium->tymed = TYMED_ISTREAM;
            pMedium->pstm = stream;
            return S_OK;
        }

        return DV_E_FORMATETC;
    }

    HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC*, STGMEDIUM*) override {
        return E_NOTIMPL;
    }

    HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC* pFE) override {
        if (!pFE) return E_POINTER;
        if (pFE->cfFormat == g_cfFileDescriptorW) return S_OK;
        if (pFE->cfFormat == g_cfFileContents) return S_OK;
        return DV_E_FORMATETC;
    }

    HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC*, FORMATETC* pOut) override {
        if (pOut) pOut->ptd = nullptr;
        return DATA_S_SAMEFORMATETC;
    }

    HRESULT STDMETHODCALLTYPE SetData(FORMATETC*, STGMEDIUM*, BOOL) override {
        return E_NOTIMPL;
    }

    HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD dir, IEnumFORMATETC** ppEnum) override {
        if (dir != DATADIR_GET) return E_NOTIMPL;
        std::vector<FORMATETC> fmts;
        FORMATETC fe = {};
        fe.dwAspect = DVASPECT_CONTENT;
        fe.lindex = -1;
        fe.cfFormat = static_cast<CLIPFORMAT>(g_cfFileDescriptorW);
        fe.tymed = TYMED_HGLOBAL;
        fmts.push_back(fe);
        fe.cfFormat = static_cast<CLIPFORMAT>(g_cfFileContents);
        fe.tymed = TYMED_ISTREAM;
        fmts.push_back(fe);
        *ppEnum = new VirtualEnumFORMATETC(fmts);
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override {
        return OLE_E_ADVISENOTSUPPORTED;
    }
    HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override {
        return OLE_E_ADVISENOTSUPPORTED;
    }
    HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA**) override {
        return OLE_E_ADVISENOTSUPPORTED;
    }

private:
    VirtualClipboardPlugin* plugin_;
    std::vector<VirtualFileEntry> files_;
    ULONG ref_;
};

// ==================== VirtualClipboardPlugin ====================

VirtualClipboardPlugin* VirtualClipboardPlugin::instance_ = nullptr;

VirtualClipboardPlugin::VirtualClipboardPlugin(flutter::BinaryMessenger* messenger)
    : messenger_(messenger) {
    instance_ = this;
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "com.webrtcgo/virtual_clipboard",
        &flutter::StandardMethodCodec::GetInstance());

    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            HandleMethodCall(call, std::move(result));
        });
}

void VirtualClipboardPlugin::Register(flutter::BinaryMessenger* messenger) {
    new VirtualClipboardPlugin(messenger);
}

void VirtualClipboardPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    if (call.method_name() == "setVirtualClipboard") {
        const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
        if (!args) { result->Error("args", "Expected list"); return; }

        std::vector<VirtualFileEntry> files;
        for (const auto& item : *args) {
            const auto* map = std::get_if<flutter::EncodableMap>(&item);
            if (!map) continue;
            VirtualFileEntry entry;
            entry.fileSize = 0;
            entry.index = 0;
            auto nameIt = map->find(flutter::EncodableValue("name"));
            auto sizeIt = map->find(flutter::EncodableValue("size"));
            auto indexIt = map->find(flutter::EncodableValue("index"));
            auto isDirIt = map->find(flutter::EncodableValue("isDir"));
            if (nameIt != map->end()) {
                entry.name = std::get<std::string>(nameIt->second);
            }
            if (sizeIt != map->end()) {
                const auto& v = sizeIt->second;
                if (auto* pi = std::get_if<int32_t>(&v)) entry.fileSize = *pi;
                else if (auto* pl = std::get_if<int64_t>(&v)) entry.fileSize = *pl;
            }
            if (indexIt != map->end()) {
                const auto& v = indexIt->second;
                if (auto* pi = std::get_if<int32_t>(&v)) entry.index = *pi;
                else if (auto* pl = std::get_if<int64_t>(&v)) entry.index = static_cast<int>(*pl);
            }
            if (isDirIt != map->end()) {
                if (auto* pb = std::get_if<bool>(&isDirIt->second)) entry.isDir = *pb;
            }
            files.push_back(entry);
        }

        SetVirtualClipboard(files);
        result->Success();

    } else if (call.method_name() == "provideFileData") {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) { result->Error("args", "Expected map"); return; }

        auto dataIt = args->find(flutter::EncodableValue("data"));
        if (dataIt == args->end()) {
            result->Error("args", "Missing data");
            return;
        }
        const auto& dataVec = std::get<std::vector<uint8_t>>(dataIt->second);
        ProvideFileData(0, dataVec);
        result->Success();

    } else if (call.method_name() == "provideFileError") {
        ProvideFileError(0);
        result->Success();

    } else if (call.method_name() == "clearClipboard") {
        ClearClipboard();
        result->Success();
    } else {
        result->NotImplemented();
    }
}

void VirtualClipboardPlugin::SetVirtualClipboard(const std::vector<VirtualFileEntry>& files) {
    ole_active_.store(false);
    if (ole_thread_.joinable()) ole_thread_.join();

    current_files_ = files;
    ole_active_.store(true);

    ole_thread_ = std::thread([this]() {
        OleInitialize(nullptr);

        auto* dataObj = new VirtualFileDataObject(this, current_files_);
        HRESULT hr = OleSetClipboard(dataObj);

        if (FAILED(hr)) {
            OutputDebugStringA("[VirtualClipboard] OleSetClipboard failed\n");
            dataObj->Release();
            OleUninitialize();
            return;
        }

        OutputDebugStringA("[VirtualClipboard] OLE clipboard set OK\n");

        while (ole_active_.load()) {
            MSG msg;
            while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
                if (msg.message == WM_QUIT) {
                    ole_active_.store(false);
                    break;
                }
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
            Sleep(50);
        }

        OleSetClipboard(nullptr);
        OleUninitialize();
    });
}

void VirtualClipboardPlugin::ClearClipboard() {
    ole_active_.store(false);
    if (ole_thread_.joinable()) ole_thread_.join();
}

bool VirtualClipboardPlugin::RequestFileData(int fileIndex, int64_t offset, int64_t requestSize,
                                              std::vector<uint8_t>& outData) {
    {
        std::lock_guard<std::mutex> lk(pull_mutex_);
        pull_buffer_.clear();
        pull_data_ready_ = false;
        pull_error_ = false;
    }

    auto* params = new VClipboardRequestParams{this, fileIndex, offset, requestSize};
    PostMessage(hwnd_, WM_VCLIPBOARD_REQUEST, reinterpret_cast<WPARAM>(params), 0);

    {
        std::unique_lock<std::mutex> lk(pull_mutex_);
        pull_cv_.wait_for(lk, std::chrono::seconds(60), [this]() {
            return pull_data_ready_ || pull_error_;
        });
        if (pull_error_ || !pull_data_ready_) return false;
        outData = std::move(pull_buffer_);
        return true;
    }
}

void VirtualClipboardPlugin::ProvideFileData(int, const std::vector<uint8_t>& data) {
    std::lock_guard<std::mutex> lk(pull_mutex_);
    pull_buffer_ = data;
    pull_data_ready_ = true;
    pull_cv_.notify_one();
}

void VirtualClipboardPlugin::ProvideFileError(int) {
    std::lock_guard<std::mutex> lk(pull_mutex_);
    pull_error_ = true;
    pull_cv_.notify_one();
}
