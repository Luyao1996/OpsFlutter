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

// UploadFile 通过预签名 URL 上传本地文件。
// 上传方式：POST + Content-Type: application/octet-stream + 文件二进制 body。
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

	req, err := http.NewRequest(http.MethodPost, signedURL, body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/octet-stream")
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

// UploadBytes 通过预签名 URL 上传内存中的字节。用于上传 version.json。
func UploadBytes(signedURL string, data []byte) error {
	req, err := http.NewRequest(http.MethodPost, signedURL, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/octet-stream")
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
