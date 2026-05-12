package manifest

import (
	"errors"
	"fmt"
	"time"

	"netbar-release/internal/signature"
	"netbar-release/internal/uploader"
)

type Store struct {
	sig          *signature.Client
	manifestKey  string
	backupPrefix string
	publicURLs   []string
}

func NewStore(sig *signature.Client, manifestKey, backupPrefix string, publicURLs []string) *Store {
	return &Store{
		sig:          sig,
		manifestKey:  manifestKey,
		backupPrefix: backupPrefix,
		publicURLs:   publicURLs,
	}
}

// Fetch 通过公共 URL 拉取当前 version.json。首次发布场景返回空 Manifest。
func (s *Store) Fetch() (*Manifest, error) {
	if len(s.publicURLs) == 0 {
		return &Manifest{}, nil
	}
	// 尝试每个 publicURL，第一个成功的获胜
	var lastErr error
	for _, base := range s.publicURLs {
		url := base + s.manifestKey
		data, err := uploader.Download(url)
		if err != nil {
			if errors.Is(err, uploader.ErrNotFound) {
				// 首次发布：文件还不存在
				return &Manifest{}, nil
			}
			lastErr = err
			continue
		}
		return FromJSON(data)
	}
	return nil, fmt.Errorf("fetch manifest from all public urls failed: %w", lastErr)
}

// Backup 将当前 manifest 备份到 OSS。
func (s *Store) Backup(m *Manifest) (string, error) {
	data, err := m.ToJSON()
	if err != nil {
		return "", err
	}
	backupKey := fmt.Sprintf("%sversion-%s.json", s.backupPrefix, time.Now().Format("20060102-150405"))
	signedURL, err := s.sig.Sign(backupKey)
	if err != nil {
		return "", fmt.Errorf("sign backup: %w", err)
	}
	if err := uploader.UploadBytes(signedURL, data); err != nil {
		return "", err
	}
	return backupKey, nil
}

// Upload 上传 manifest 覆盖 OSS 上的 version.json。
func (s *Store) Upload(m *Manifest) error {
	data, err := m.ToJSON()
	if err != nil {
		return err
	}
	signedURL, err := s.sig.Sign(s.manifestKey)
	if err != nil {
		return fmt.Errorf("sign manifest: %w", err)
	}
	return uploader.UploadBytes(signedURL, data)
}

// PublicURL 返回某个 OSS key 的第一个公共下载地址（提示用）。
func (s *Store) PublicURL(key string) string {
	if len(s.publicURLs) == 0 {
		return key
	}
	return s.publicURLs[0] + key
}
