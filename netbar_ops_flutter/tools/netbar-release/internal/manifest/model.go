package manifest

import (
	"encoding/json"
	"fmt"
	"sort"
	"time"
)

// Release 单个版本元数据。
type Release struct {
	Version     string    `json:"version"`
	BuildNumber int       `json:"buildNumber"`
	Path        string    `json:"path"`
	MD5         string    `json:"md5"`
	Size        int64     `json:"size"`
	ForceUpdate bool      `json:"forceUpdate"`
	IsInstaller bool      `json:"isInstaller,omitempty"` // Windows 专用：path 是否为 setup.exe
	Changelog   string    `json:"changelog"`
	UploadTime  time.Time `json:"uploadTime"`
}

// Platform 单个平台的版本清单。
type Platform struct {
	MinSupportedBuild int       `json:"minSupportedBuild"`
	Releases          []Release `json:"releases"`
}

// Manifest version.json 顶层结构。
type Manifest struct {
	Android *Platform `json:"android,omitempty"`
	Windows *Platform `json:"windows,omitempty"`
}

func (m *Manifest) platformPtr(name string) **Platform {
	switch name {
	case "android":
		return &m.Android
	case "windows":
		return &m.Windows
	}
	return nil
}

// Get 返回指定平台（不存在则返回 nil）。
func (m *Manifest) Get(platform string) *Platform {
	pp := m.platformPtr(platform)
	if pp == nil {
		return nil
	}
	return *pp
}

// AddRelease 在指定平台添加一条 release，按 buildNumber 降序排，并截断到 max。
func (m *Manifest) AddRelease(platform string, r Release, max int) error {
	pp := m.platformPtr(platform)
	if pp == nil {
		return fmt.Errorf("unknown platform: %s", platform)
	}
	if *pp == nil {
		*pp = &Platform{MinSupportedBuild: 1}
	}
	p := *pp
	for _, existing := range p.Releases {
		if existing.BuildNumber == r.BuildNumber {
			return fmt.Errorf("buildNumber %d already exists", r.BuildNumber)
		}
	}
	p.Releases = append(p.Releases, r)
	sort.Slice(p.Releases, func(i, j int) bool {
		return p.Releases[i].BuildNumber > p.Releases[j].BuildNumber
	})
	if max > 0 && len(p.Releases) > max {
		p.Releases = p.Releases[:max]
	}
	return nil
}

// RemoveLatest 删除指定平台最新的一条 release（用于 rollback）。
func (m *Manifest) RemoveLatest(platform string) (*Release, error) {
	pp := m.platformPtr(platform)
	if pp == nil {
		return nil, fmt.Errorf("unknown platform: %s", platform)
	}
	if *pp == nil || len((*pp).Releases) == 0 {
		return nil, fmt.Errorf("no releases for %s", platform)
	}
	p := *pp
	first := p.Releases[0]
	p.Releases = p.Releases[1:]
	return &first, nil
}

// SetMinSupportedBuild 调整最低支持版本。
func (m *Manifest) SetMinSupportedBuild(platform string, build int) error {
	pp := m.platformPtr(platform)
	if pp == nil {
		return fmt.Errorf("unknown platform: %s", platform)
	}
	if *pp == nil {
		*pp = &Platform{}
	}
	(*pp).MinSupportedBuild = build
	return nil
}

func (m *Manifest) ToJSON() ([]byte, error) {
	return json.MarshalIndent(m, "", "  ")
}

func FromJSON(data []byte) (*Manifest, error) {
	if len(data) == 0 {
		return &Manifest{}, nil
	}
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	return &m, nil
}
