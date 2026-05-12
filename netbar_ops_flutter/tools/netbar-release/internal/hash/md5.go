package hash

import (
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"io"
	"os"
)

// FileMD5 计算文件的 MD5（小写 hex）。
func FileMD5(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()
	h := md5.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
