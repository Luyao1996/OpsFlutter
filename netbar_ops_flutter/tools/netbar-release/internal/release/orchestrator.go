package release

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"netbar-release/internal/builder"
	"netbar-release/internal/config"
	"netbar-release/internal/hash"
	"netbar-release/internal/manifest"
	"netbar-release/internal/signature"
	"netbar-release/internal/uploader"
)

// Inputs 是 release 命令收集到的所有用户输入。
type Inputs struct {
	Platform          string // "windows" | "android" | "both"
	Version           string
	AndroidBuild      int // 仅当涉及 android 时使用
	WindowsBuild      int // 仅当涉及 windows 时使用
	ForceUpdate       bool
	MinSupportedBuild int    // 0 表示不修改
	Changelog         string // 多行字符串
}

// Orchestrator 串联：编译 → 打包 → 计算 MD5 → 上传 → 更新 manifest。
type Orchestrator struct {
	cfg   *config.Config
	sig   *signature.Client
	store *manifest.Store
	fb    *builder.FlutterBuilder
	inno  *builder.InnoSetupBuilder
}

func NewOrchestrator(cfg *config.Config, sig *signature.Client, store *manifest.Store) *Orchestrator {
	fb := builder.NewFlutterBuilder(
		cfg.Flutter.Command,
		cfg.ResolvePath(cfg.Flutter.ProjectDir),
	)
	var inno *builder.InnoSetupBuilder
	if cfg.InnoSetup.ISCCPath != "" {
		inno = builder.NewInnoSetupBuilder(
			cfg.InnoSetup.ISCCPath,
			cfg.ResolvePath(cfg.InnoSetup.Script),
			cfg.ResolvePath(cfg.InnoSetup.OutputDir),
		)
	}
	return &Orchestrator{cfg: cfg, sig: sig, store: store, fb: fb, inno: inno}
}

// ExpandPlatforms 把 "both" 展开成具体平台列表，单平台原样返回。
func ExpandPlatforms(p string) []string {
	if p == "both" {
		return []string{"android", "windows"}
	}
	return []string{p}
}

// BuildOSSKey 根据平台/版本/build 生成 OSS key。
func (o *Orchestrator) BuildOSSKey(platform, version string, build int) string {
	ext := ".apk"
	if platform == "windows" {
		ext = ".exe"
	}
	return fmt.Sprintf("%s/netbar-%s-%d%s",
		strings.TrimRight(o.cfg.OSS.Prefix, "/"), version, build, ext)
}

// Run 执行完整发布流程。
// m 是已经从 OSS 拉取下来的当前 manifest（会在内存中被改写后再上传）。
func (o *Orchestrator) Run(in Inputs, m *manifest.Manifest) error {
	platforms := ExpandPlatforms(in.Platform)

	// 编译 + 打包 + 上传安装包
	for _, p := range platforms {
		build := o.buildOf(p, in)
		artifact, err := o.buildPlatform(p, in.Version, build)
		if err != nil {
			return fmt.Errorf("[%s] build/package: %w", p, err)
		}
		if err := o.uploadAndRecord(p, in.Version, build, artifact, in, m); err != nil {
			return fmt.Errorf("[%s] upload: %w", p, err)
		}
	}

	// 最后统一上传 manifest（先备份）
	fmt.Println()
	fmt.Println("▸ 备份 + 上传 version.json ...")
	if _, err := o.store.Backup(m); err != nil {
		fmt.Printf("   ⚠ 备份失败: %v\n", err)
	}
	if err := o.store.Upload(m); err != nil {
		return fmt.Errorf("upload manifest: %w", err)
	}
	fmt.Println("   ✓ version.json 已更新")
	return nil
}

func (o *Orchestrator) buildOf(p string, in Inputs) int {
	switch p {
	case "android":
		return in.AndroidBuild
	case "windows":
		return in.WindowsBuild
	}
	return 0
}

func (o *Orchestrator) buildPlatform(platform, version string, build int) (string, error) {
	fmt.Println()
	fmt.Printf("════ 编译 %s (version=%s build=%d) ════\n", platform, version, build)
	switch platform {
	case "android":
		return o.fb.BuildAPK(version, build)
	case "windows":
		releaseDir, err := o.fb.BuildWindows(version, build)
		if err != nil {
			return "", err
		}
		if o.inno == nil {
			return "", fmt.Errorf("inno_setup 未配置，无法打包 setup.exe")
		}
		fmt.Println()
		fmt.Println("════ Inno Setup 打包 ════")
		return o.inno.Build(releaseDir, version, build)
	}
	return "", fmt.Errorf("未知平台: %s", platform)
}

func (o *Orchestrator) uploadAndRecord(
	platform, version string, build int, artifact string,
	in Inputs, m *manifest.Manifest,
) error {
	fmt.Println()
	fmt.Printf("════ 上传 %s ════\n", platform)

	info, err := os.Stat(artifact)
	if err != nil {
		return err
	}
	md5sum, err := hash.FileMD5(artifact)
	if err != nil {
		return fmt.Errorf("md5: %w", err)
	}
	fmt.Printf("▸ artifact : %s\n", filepath.Base(artifact))
	fmt.Printf("▸ MD5      : %s\n", md5sum)
	fmt.Printf("▸ Size     : %.2f MB\n", float64(info.Size())/1024/1024)

	ossKey := o.BuildOSSKey(platform, version, build)
	fmt.Printf("▸ ossKey   : %s\n", ossKey)

	fmt.Println("▸ 申请签名 URL ...")
	signedURL, err := o.sig.Sign(ossKey)
	if err != nil {
		return fmt.Errorf("sign: %w", err)
	}

	fmt.Println("▸ 上传 ...")
	if err := uploader.UploadFile(signedURL, artifact); err != nil {
		return fmt.Errorf("upload: %w", err)
	}

	release := manifest.Release{
		Version:     version,
		BuildNumber: build,
		Path:        ossKey,
		MD5:         md5sum,
		Size:        info.Size(),
		ForceUpdate: in.ForceUpdate,
		IsInstaller: platform == "windows",
		Changelog:   in.Changelog,
		UploadTime:  time.Now(),
	}
	if err := m.AddRelease(platform, release, o.cfg.MaxReleases); err != nil {
		return err
	}
	if in.MinSupportedBuild > 0 {
		if err := m.SetMinSupportedBuild(platform, in.MinSupportedBuild); err != nil {
			return err
		}
	}
	fmt.Printf("   ✓ %s release 记录已更新\n", platform)
	return nil
}
