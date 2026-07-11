package manifest

import (
	"errors"
	"fmt"
	"time"

	"netbar-release/internal/signature"
	"netbar-release/internal/uploader"
)

type Store struct {
	primary      signature.Signer // 新源（RustFS），必须成功
	legacy       signature.Signer // 老源（阿里 OSS 签名服务），失败仅警告
	manifestKey  string
	backupPrefix string
	publicURLs   []string
}

func NewStore(primary, legacy signature.Signer, manifestKey, backupPrefix string, publicURLs []string) *Store {
	return &Store{
		primary:      primary,
		legacy:       legacy,
		manifestKey:  manifestKey,
		backupPrefix: backupPrefix,
		publicURLs:   publicURLs,
	}
}

// Fetch 通过公共 URL 拉取当前 version.json。
// 双源迁移期语义：某个源 404（例如新源还没有 version.json）继续尝试下一个源，
// 只有【所有】源都 404 才视为首次发布返回空 Manifest；
// 否则任何一个源成功即返回其内容，避免把"新源暂时没文件"误判成首次发布而清空历史。
func (s *Store) Fetch() (*Manifest, error) {
	if len(s.publicURLs) == 0 {
		return &Manifest{}, nil
	}
	var lastErr error
	notFound := 0
	for _, base := range s.publicURLs {
		url := base + s.manifestKey
		data, err := uploader.Download(url)
		if err != nil {
			if errors.Is(err, uploader.ErrNotFound) {
				notFound++
				continue
			}
			lastErr = err
			continue
		}
		return FromJSON(data)
	}
	if notFound == len(s.publicURLs) {
		// 所有源都没有 version.json → 真正的首次发布
		return &Manifest{}, nil
	}
	return nil, fmt.Errorf("fetch manifest from all public urls failed: %w", lastErr)
}

// Backup 将当前 manifest 备份到新老双源。
func (s *Store) Backup(m *Manifest) (string, error) {
	data, err := m.ToJSON()
	if err != nil {
		return "", err
	}
	backupKey := fmt.Sprintf("%sversion-%s.json", s.backupPrefix, time.Now().Format("20060102-150405"))
	if err := s.putBoth(backupKey, data); err != nil {
		return "", err
	}
	return backupKey, nil
}

// Upload 上传 manifest 覆盖新老双源上的 version.json。
func (s *Store) Upload(m *Manifest) error {
	data, err := m.ToJSON()
	if err != nil {
		return err
	}
	return s.putBoth(s.manifestKey, data)
}

// putBoth 双写：新源必须成功；老源失败只打警告不影响发布
//（老源签名服务当前 key 失效，等运维修复后双写自动恢复）。
func (s *Store) putBoth(key string, data []byte) error {
	signedURL, err := s.primary.Sign(key)
	if err != nil {
		return fmt.Errorf("sign(新源) %s: %w", key, err)
	}
	if err := uploader.UploadBytes(signedURL, data); err != nil {
		return fmt.Errorf("upload(新源) %s: %w", key, err)
	}
	if s.legacy != nil {
		if lu, err := s.legacy.Sign(key); err != nil {
			fmt.Printf("   ⚠ 老源签名失败（不影响发布，老客户端暂不可见）: %v\n", err)
		} else if err := uploader.UploadBytes(lu, data); err != nil {
			fmt.Printf("   ⚠ 老源上传失败（不影响发布，老客户端暂不可见）: %v\n", err)
		}
	}
	return nil
}

// PublicURL 返回某个 OSS key 的第一个公共下载地址（提示用）。
func (s *Store) PublicURL(key string) string {
	if len(s.publicURLs) == 0 {
		return key
	}
	return s.publicURLs[0] + key
}
