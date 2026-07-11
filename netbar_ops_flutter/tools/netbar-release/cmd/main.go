package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"netbar-release/internal/config"
	"netbar-release/internal/hash"
	"netbar-release/internal/manifest"
	"netbar-release/internal/release"
	"netbar-release/internal/signature"
	"netbar-release/internal/ui"
)

var (
	cfgPath  string
	platform string
)

func main() {
	rootCmd := &cobra.Command{
		Use:   "netbar-release",
		Short: "NetBar-Ops Flutter 客户端发布工具",
	}
	rootCmd.PersistentFlags().StringVarP(&cfgPath, "config", "c", "config.yaml", "配置文件路径")

	rootCmd.AddCommand(
		releaseCmd(),
		promoteCmd(),
		publishCmd(),
		listCmd(),
		rollbackCmd(),
		setMinCmd(),
	)
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func loadStore() (*config.Config, *manifest.Store, error) {
	cfg, err := config.Load(cfgPath)
	if err != nil {
		return nil, nil, err
	}
	primary, legacy := newSigners(cfg)
	store := manifest.NewStore(primary, legacy, cfg.Manifest.Key, cfg.Manifest.BackupPrefix, cfg.PublicURLs)
	return cfg, store, nil
}

// newSigners 构造新老双源签名器：
// primary = 新源（RustFS，本地 SigV4 预签名）；legacy = 老源（PHP 签名服务）。
func newSigners(cfg *config.Config) (signature.Signer, signature.Signer) {
	primary := signature.NewS3(cfg.S3.Endpoint, cfg.S3.Bucket, cfg.S3.Region, cfg.S3.AccessKey, cfg.S3.SecretKey)
	legacy := signature.New(cfg.Signature.BaseURL, cfg.Signature.Path)
	return primary, legacy
}

// ---------------- publish ----------------

func publishCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "publish",
		Short: "发布新版本（交互式）",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runPublish()
		},
	}
}

func runPublish() error {
	cfg, store, err := loadStore()
	if err != nil {
		return err
	}
	primary, legacy := newSigners(cfg)

	fmt.Println("╔══════════════════════════════════╗")
	fmt.Println("║  NetBar-Ops 发布工具             ║")
	fmt.Println("╚══════════════════════════════════╝")
	fmt.Println()

	// [1] 平台
	plat, err := ui.SelectPlatform()
	if err != nil {
		return err
	}

	// [2] 安装包路径
	pkgPath, err := ui.AskString("安装包路径（apk 或 setup.exe）", "")
	if err != nil {
		return err
	}
	pkgPath = strings.TrimSpace(pkgPath)
	stat, err := os.Stat(pkgPath)
	if err != nil {
		return fmt.Errorf("文件无法访问: %w", err)
	}
	if stat.IsDir() {
		return fmt.Errorf("路径是目录，请指定具体文件")
	}
	fmt.Printf("   ✓ 文件: %s (%.2f MB)\n", filepath.Base(pkgPath), float64(stat.Size())/1024/1024)

	md5sum, err := hash.FileMD5(pkgPath)
	if err != nil {
		return fmt.Errorf("计算 MD5 失败: %w", err)
	}
	fmt.Printf("   ✓ MD5 : %s\n", md5sum)

	// [3] 版本号 + buildNumber
	version, err := ui.AskString("版本号 (例如 1.0.5)", "")
	if err != nil {
		return err
	}
	build, err := ui.AskInt("Build Number (单调递增整数)", 0)
	if err != nil {
		return err
	}

	// [4] 拉取当前 manifest
	fmt.Println()
	fmt.Println("→ 拉取当前 version.json ...")
	curManifest, err := store.Fetch()
	if err != nil {
		return fmt.Errorf("拉取 manifest 失败: %w", err)
	}
	curPlat := curManifest.Get(plat)
	if curPlat != nil && len(curPlat.Releases) > 0 {
		latest := curPlat.Releases[0]
		fmt.Printf("   ✓ 当前最新 %s: %s (build %d)\n", plat, latest.Version, latest.BuildNumber)
		if build <= latest.BuildNumber {
			return fmt.Errorf("新 buildNumber %d 必须大于当前最新 %d", build, latest.BuildNumber)
		}
	} else {
		fmt.Printf("   ✓ %s 平台首次发布\n", plat)
	}

	// [5] 强制更新 + minSupportedBuild + changelog
	forceUpdate, err := ui.AskConfirm("此版本是否强制更新?", false)
	if err != nil {
		return err
	}
	curMin := 1
	if curPlat != nil {
		curMin = curPlat.MinSupportedBuild
	}
	newMin, err := ui.AskInt(fmt.Sprintf("minSupportedBuild (当前=%d，回车保持)", curMin), curMin)
	if err != nil {
		return err
	}

	changelog, err := ui.AskMultiline("输入 changelog:")
	if err != nil {
		return err
	}
	if changelog == "" {
		return fmt.Errorf("changelog 不能为空")
	}

	// 生成 OSS key
	ext := strings.ToLower(filepath.Ext(pkgPath))
	if plat == "android" && ext != ".apk" {
		return fmt.Errorf("Android 平台应该上传 .apk 文件")
	}
	if plat == "windows" && ext != ".exe" {
		return fmt.Errorf("Windows 平台应该上传 .exe 文件")
	}
	ossKey := fmt.Sprintf("%s/netbar-%s-%d%s", strings.TrimRight(cfg.OSS.Prefix, "/"), version, build, ext)

	// 预览
	fmt.Println()
	fmt.Println("┌──────────── 预览 ────────────┐")
	fmt.Printf("│ platform       : %s\n", plat)
	fmt.Printf("│ version        : %s\n", version)
	fmt.Printf("│ buildNumber    : %d\n", build)
	fmt.Printf("│ ossKey         : %s\n", ossKey)
	fmt.Printf("│ md5            : %s\n", md5sum)
	fmt.Printf("│ size           : %d bytes (%.2f MB)\n", stat.Size(), float64(stat.Size())/1024/1024)
	fmt.Printf("│ forceUpdate    : %v\n", forceUpdate)
	fmt.Printf("│ minSupportBuild: %d\n", newMin)
	fmt.Printf("│ changelog:\n")
	for _, line := range strings.Split(changelog, "\n") {
		fmt.Printf("│   %s\n", line)
	}
	fmt.Println("└──────────────────────────────┘")

	ok, err := ui.AskConfirm("确认上传?", false)
	if err != nil {
		return err
	}
	if !ok {
		fmt.Println("已取消")
		return nil
	}

	// [6] 备份
	fmt.Println()
	fmt.Println("→ 备份当前 version.json ...")
	backupKey, err := store.Backup(curManifest)
	if err != nil {
		// 首次发布场景：本地 manifest 是空的，备份也是空的，可以忽略
		fmt.Printf("   ⚠ 备份失败（可能首次发布）: %v\n", err)
	} else {
		fmt.Printf("   ✓ 备份: %s\n", backupKey)
	}

	// [7] 上传安装包（新老双源）
	fmt.Println()
	fmt.Printf("→ 上传安装包 (key=%s) ...\n", ossKey)
	if err := release.DualUploadFile(primary, legacy, ossKey, pkgPath); err != nil {
		return fmt.Errorf("上传失败: %w", err)
	}
	fmt.Println("   ✓ 安装包上传完成")

	// [8] 更新 manifest
	rel := manifest.Release{
		Version:     version,
		BuildNumber: build,
		Path:        ossKey,
		MD5:         md5sum,
		Size:        stat.Size(),
		ForceUpdate: forceUpdate,
		IsInstaller: plat == "windows",
		Changelog:   changelog,
		UploadTime:  time.Now(),
	}
	if err := curManifest.AddRelease(plat, rel, cfg.MaxReleases); err != nil {
		return fmt.Errorf("更新 manifest 失败: %w", err)
	}
	if err := curManifest.SetMinSupportedBuild(plat, newMin); err != nil {
		return err
	}

	fmt.Println("→ 更新 version.json ...")
	if err := store.Upload(curManifest); err != nil {
		return fmt.Errorf("上传 manifest 失败: %w", err)
	}
	fmt.Println("   ✓ version.json 已更新")

	fmt.Println()
	fmt.Println("══════════════════════════════════")
	fmt.Println("✓ 发布完成")
	fmt.Printf("  公共下载地址: %s\n", store.PublicURL(ossKey))
	fmt.Println("══════════════════════════════════")
	return nil
}

// ---------------- list ----------------

func listCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "list",
		Short: "查看历史版本",
		RunE: func(cmd *cobra.Command, args []string) error {
			_, store, err := loadStore()
			if err != nil {
				return err
			}
			m, err := store.Fetch()
			if err != nil {
				return err
			}
			for _, plat := range []string{"android", "windows"} {
				p := m.Get(plat)
				fmt.Printf("\n=== %s ===\n", plat)
				if p == nil || (len(p.Releases) == 0 && p.Preview == nil) {
					fmt.Println("  (空)")
					continue
				}
				fmt.Printf("  minSupportedBuild: %d\n", p.MinSupportedBuild)
				if p.Preview != nil {
					tag := " [PREVIEW]"
					if p.Preview.ForceUpdate {
						tag += " [强制]"
					}
					fmt.Printf("  + %s (build %d)%s  %s\n",
						p.Preview.Version, p.Preview.BuildNumber, tag,
						p.Preview.UploadTime.Format("2006-01-02 15:04:05"))
				}
				for _, r := range p.Releases {
					tag := ""
					if r.ForceUpdate {
						tag = " [强制]"
					}
					fmt.Printf("  - %s (build %d)%s  %s\n", r.Version, r.BuildNumber, tag, r.UploadTime.Format("2006-01-02 15:04:05"))
				}
			}
			return nil
		},
	}
	return cmd
}

// ---------------- rollback ----------------

func rollbackCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "rollback",
		Short: "删除某平台最新一条 release",
		RunE: func(cmd *cobra.Command, args []string) error {
			_, store, err := loadStore()
			if err != nil {
				return err
			}
			if platform == "" {
				return fmt.Errorf("--platform 必填 (android/windows)")
			}
			m, err := store.Fetch()
			if err != nil {
				return err
			}
			p := m.Get(platform)
			if p == nil || len(p.Releases) == 0 {
				return fmt.Errorf("%s 没有可回滚的版本", platform)
			}
			latest := p.Releases[0]
			ok, err := ui.AskConfirm(fmt.Sprintf("确认删除 %s 的最新版本 %s (build %d)?", platform, latest.Version, latest.BuildNumber), false)
			if err != nil || !ok {
				fmt.Println("已取消")
				return nil
			}
			if _, err := store.Backup(m); err != nil {
				fmt.Printf("⚠ 备份失败: %v\n", err)
			}
			if _, err := m.RemoveLatest(platform); err != nil {
				return err
			}
			if err := store.Upload(m); err != nil {
				return err
			}
			fmt.Println("✓ 已回滚")
			return nil
		},
	}
	cmd.Flags().StringVarP(&platform, "platform", "p", "", "android | windows")
	return cmd
}

// ---------------- set-min ----------------

func setMinCmd() *cobra.Command {
	var build int
	cmd := &cobra.Command{
		Use:   "set-min",
		Short: "调整某平台的 minSupportedBuild",
		RunE: func(cmd *cobra.Command, args []string) error {
			_, store, err := loadStore()
			if err != nil {
				return err
			}
			if platform == "" {
				return fmt.Errorf("--platform 必填")
			}
			if build <= 0 {
				return fmt.Errorf("--build 必须 > 0")
			}
			m, err := store.Fetch()
			if err != nil {
				return err
			}
			if _, err := store.Backup(m); err != nil {
				fmt.Printf("⚠ 备份失败: %v\n", err)
			}
			if err := m.SetMinSupportedBuild(platform, build); err != nil {
				return err
			}
			if err := store.Upload(m); err != nil {
				return err
			}
			fmt.Printf("✓ %s minSupportedBuild 已设置为 %d\n", platform, build)
			return nil
		},
	}
	cmd.Flags().StringVarP(&platform, "platform", "p", "", "android | windows")
	cmd.Flags().IntVarP(&build, "build", "b", 0, "新的 minSupportedBuild")
	return cmd
}
