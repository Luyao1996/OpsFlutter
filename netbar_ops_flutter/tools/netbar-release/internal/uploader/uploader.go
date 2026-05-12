package uploader

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/schollz/progressbar/v3"
)

var httpClient = &http.Client{Timeout: 30 * time.Minute}

// UploadFile 通过预签名 URL 上传本地文件（PUT 方式）。
//
// 关键约定：
//   - 必须用 PUT（OSS 预签名 URL 不接受 POST raw body）
//   - 不发送 Content-Type 头部。原因：阿里云 OSS V1 签名把 Content-Type 纳入 StringToSign，
//     如果服务端 PHP 签名时 Content-Type 为空，客户端就必须也为空，否则 SignatureDoesNotMatch。
//     Go 的 net/http 在用户没显式 Set 时不会自动添加 Content-Type。
func UploadFile(signedURL, filePath string) error {
	f, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("open %s: %w", filePath, err)
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil {
		return err
	}

	bar := progressbar.DefaultBytes(stat.Size(), "上传中")
	body := io.TeeReader(f, bar)

	req, err := http.NewRequest(http.MethodPut, signedURL, body)
	if err != nil {
		return err
	}
	req.ContentLength = stat.Size()

	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("upload do: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("upload http %d: %s", resp.StatusCode, string(b))
	}
	return nil
}

// UploadBytes 通过预签名 URL 上传内存中的字节（用于 version.json 等小文件）。
// 同 UploadFile 的约定：PUT + 不发 Content-Type。
func UploadBytes(signedURL string, data []byte) error {
	req, err := http.NewRequest(http.MethodPut, signedURL, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.ContentLength = int64(len(data))

	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("upload bytes do: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("upload bytes http %d: %s", resp.StatusCode, string(b))
	}
	return nil
}

// Download 通过 GET 下载 URL 内容到内存。
func Download(url string) ([]byte, error) {
	resp, err := httpClient.Get(url)
	if err != nil {
		return nil, fmt.Errorf("download get: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return nil, ErrNotFound
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("download http %d", resp.StatusCode)
	}
	return io.ReadAll(resp.Body)
}

// ErrNotFound 用于区分"首次发布"的场景。
var ErrNotFound = fmt.Errorf("not found")
