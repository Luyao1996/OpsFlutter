package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/spf13/cobra"

	"netbar-release/internal/manifest"
	"netbar-release/internal/release"
	"netbar-release/internal/signature"
	"netbar-release/internal/ui"
)

func releaseCmd() *cobra.Command {
	var (
		flagPlatform      string
		flagVersion       string
		flagAndroidBuild  int
		flagWindowsBuild  int
		flagForce         bool
		flagMinSupported  int
		flagChangelog     string
		flagChangelogFile string
		flagYes           bool
	)

	cmd := &cobra.Command{
		Use:   "release",
		Short: "一键编译 + 打包 + 上传发布新预览版",
		Long: `发布新预览版（写入 version.json 的 preview 字段，不影响正式版用户）。
预览版通过 release-preview-promote 命令提升为正式版。`,
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, store, err := loadStore()
			if err != nil {
				return err
			}
			sig := signature.New(cfg.Signature.BaseURL, cfg.Signature.Path)

			fmt.Println("╔══════════════════════════════════╗")
			fmt.Println("║  NetBar-Ops 一键发布预览版        ║")
			fmt.Println("╚══════════════════════════════════╝")

			// 1. 拉 manifest 显示当前各平台最新版本（正式版 + 预览版）
			fmt.Println()
			fmt.Println("→ 拉取当前 version.json ...")
			cur, err := store.Fetch()
			if err != nil {
				return fmt.Errorf("fetch manifest: %w", err)
			}
			for _, p := range []string{"android", "windows"} {
				pm := cur.Get(p)
				if pm != nil && len(pm.Releases) > 0 {
					fmt.Printf("   ✓ %-7s 正式版: %s (build %d)\n",
						p, pm.Releases[0].Version, pm.Releases[0].BuildNumber)
				} else {
					fmt.Printf("   · %-7s 暂无正式版\n", p)
				}
				if pm != nil && pm.Preview != nil {
					fmt.Printf("     %-7s 预览版: %s (build %d)  [本次发布将覆盖]\n",
						"", pm.Preview.Version, pm.Preview.BuildNumber)
				}
			}

			// 2. 平台
			platform := flagPlatform
			if platform == "" {
				platform, err = ui.SelectPlatformWithBoth()
				if err != nil {
					return err
				}
			}
			if platform != "android" && platform != "windows" && platform != "both" {
				return fmt.Errorf("无效平台: %s", platform)
			}
			platforms := release.ExpandPlatforms(platform)

			// 3. 版本号（默认 = 所有目标平台最新版本中较大者 +1，按"小版本满 10 进位"规则）
			version := flagVersion
			if version == "" {
				defaultVersion := calcNextVersion(cur, platforms)
				version, err = ui.AskString("版本号", defaultVersion)
				if err != nil {
					return err
				}
			}

			// 4. 每平台单独确认 buildNumber（默认 = 该平台当前最新 + 1）
			inputs := release.Inputs{Platform: platform, Version: version}
			for _, p := range platforms {
				next := calcNextBuild(cur, p)
				var b int
				preset := 0
				if p == "android" {
					preset = flagAndroidBuild
				} else if p == "windows" {
					preset = flagWindowsBuild
				}
				if preset > 0 {
					b = preset
				} else {
					b, err = ui.AskInt(fmt.Sprintf("%s buildNumber", p), next)
					if err != nil {
						return err
					}
				}
				if pm := cur.Get(p); pm != nil {
					curMax := 0
					if len(pm.Releases) > 0 && pm.Releases[0].BuildNumber > curMax {
						curMax = pm.Releases[0].BuildNumber
					}
					if pm.Preview != nil && pm.Preview.BuildNumber > curMax {
						curMax = pm.Preview.BuildNumber
					}
					if b <= curMax {
						return fmt.Errorf("%s buildNumber %d 必须 > 当前最大 %d (含 preview)",
							p, b, curMax)
					}
				}
				switch p {
				case "android":
					inputs.AndroidBuild = b
				case "windows":
					inputs.WindowsBuild = b
				}
			}

			// 5. 强制更新 / minSupportedBuild / changelog
			if cmd.Flags().Changed("force") {
				inputs.ForceUpdate = flagForce
			} else {
				inputs.ForceUpdate, _ = ui.AskConfirm("是否强制更新（默认否，回车跳过）", false)
			}

			curMin := getMinSupportedBuild(cur, platforms)
			if flagMinSupported > 0 {
				inputs.MinSupportedBuild = flagMinSupported
			} else {
				v, err := ui.AskInt("minSupportedBuild", curMin)
				if err != nil {
					return err
				}
				inputs.MinSupportedBuild = v
			}

			changelog := flagChangelog
			if changelog == "" && flagChangelogFile != "" {
				data, err := os.ReadFile(flagChangelogFile)
				if err != nil {
					return fmt.Errorf("read changelog file: %w", err)
				}
				changelog = string(data)
			}
			if changelog == "" {
				changelog, err = ui.AskMultiline("输入 changelog:")
				if err != nil {
					return err
				}
			}
			if strings.TrimSpace(changelog) == "" {
				return fmt.Errorf("changelog 不能为空")
			}
			inputs.Changelog = changelog

			// 6. 预览
			fmt.Println()
			fmt.Println("┌──────── 预览版发布预览 [PREVIEW] ────────")
			fmt.Printf("│ platform        : %s\n", platform)
			fmt.Printf("│ version         : %s\n", version)
			if contains(platforms, "android") {
				fmt.Printf("│ android build   : %d\n", inputs.AndroidBuild)
			}
			if contains(platforms, "windows") {
				fmt.Printf("│ windows build   : %d\n", inputs.WindowsBuild)
			}
			fmt.Printf("│ forceUpdate     : %v\n", inputs.ForceUpdate)
			fmt.Printf("│ minSupportBuild : %d\n", inputs.MinSupportedBuild)
			fmt.Println("│ changelog       :")
			for _, line := range strings.Split(changelog, "\n") {
				fmt.Printf("│   %s\n", line)
			}
			fmt.Println("└──────────────────────────────")

			// 6.5 检测到 preview 已存在 → 覆盖确认（CI 场景 -y 跳过）
			if !flagYes {
				var existed []string
				for _, p := range platforms {
					if pm := cur.Get(p); pm != nil && pm.Preview != nil {
						existed = append(existed, fmt.Sprintf("%s 当前 preview = %s (build %d)",
							p, pm.Preview.Version, pm.Preview.BuildNumber))
					}
				}
				if len(existed) > 0 {
					fmt.Println()
					fmt.Println("⚠ 检测到已存在预览版，本次发布将覆盖：")
					for _, line := range existed {
						fmt.Println("  -", line)
					}
					ok, _ := ui.AskConfirm("继续覆盖?", false)
					if !ok {
						fmt.Println("已取消")
						return nil
					}
				}
				ok, _ := ui.AskConfirm("开始 编译 + 打包 + 上传 预览版?", false)
				if !ok {
					fmt.Println("已取消")
					return nil
				}
			}

			// 7. 执行
			orch := release.NewOrchestrator(cfg, sig, store)
			if err := orch.Run(inputs, cur); err != nil {
				return err
			}

			// 8. 输出公共下载地址
			fmt.Println()
			fmt.Println("══════════════════════════════════")
			fmt.Println("✓ 预览版发布完成")
			for _, p := range platforms {
				build := inputs.AndroidBuild
				if p == "windows" {
					build = inputs.WindowsBuild
				}
				ossKey := orch.BuildOSSKey(p, version, build)
				fmt.Printf("  %s: %s\n", p, store.PublicURL(ossKey))
			}
			fmt.Println("══════════════════════════════════")
			fmt.Println()
			fmt.Printf("ℹ 预览版 v%s 已发布成功\n", version)
			fmt.Println("  使用以下命令将预览版升级为正式版：")
			fmt.Println("      netbar-release release-preview-promote")
			return nil
		},
	}

	cmd.Flags().StringVarP(&flagPlatform, "platform", "p", "", "windows | android | both")
	cmd.Flags().StringVarP(&flagVersion, "version", "v", "", "版本号 (例 1.0.2)")
	cmd.Flags().IntVar(&flagAndroidBuild, "android-build", 0, "Android buildNumber (默认 = 当前 +1)")
	cmd.Flags().IntVar(&flagWindowsBuild, "windows-build", 0, "Windows buildNumber (默认 = 当前 +1)")
	cmd.Flags().BoolVar(&flagForce, "force", false, "是否强制更新")
	cmd.Flags().IntVar(&flagMinSupported, "min-supported", 0, "minSupportedBuild (0 走交互输入)")
	cmd.Flags().StringVar(&flagChangelog, "changelog", "", "Changelog 直接传入")
	cmd.Flags().StringVar(&flagChangelogFile, "changelog-file", "", "从文件读 changelog")
	cmd.Flags().BoolVarP(&flagYes, "yes", "y", false, "跳过最终确认 (CI 友好)")
	return cmd
}

func calcNextBuild(m *manifest.Manifest, platform string) int {
	pm := m.Get(platform)
	if pm == nil {
		return 1
	}
	curMax := 0
	if len(pm.Releases) > 0 {
		curMax = pm.Releases[0].BuildNumber
	}
	if pm.Preview != nil && pm.Preview.BuildNumber > curMax {
		curMax = pm.Preview.BuildNumber
	}
	return curMax + 1
}

// calcNextVersion 计算推荐的下一个版本号：
// 取目标平台中最新版本号最大的一个作为基准，按"小版本满 10 进位"规则递增。
// 如果所有目标平台都没发布过，默认返回 "1.0.0"。
func calcNextVersion(m *manifest.Manifest, platforms []string) string {
	var latest string
	for _, p := range platforms {
		pm := m.Get(p)
		if pm == nil {
			continue
		}
		// 候选包含 releases[0] 和 preview，取版本号较大者
		var candidates []string
		if len(pm.Releases) > 0 {
			candidates = append(candidates, pm.Releases[0].Version)
		}
		if pm.Preview != nil {
			candidates = append(candidates, pm.Preview.Version)
		}
		for _, v := range candidates {
			if latest == "" || compareVersion(v, latest) > 0 {
				latest = v
			}
		}
	}
	if latest == "" {
		return "1.0.0"
	}
	return bumpVersion(latest)
}

// bumpVersion 按"满 10 进位"规则递增版本号。
// 例：1.0.2 -> 1.0.3；1.0.9 -> 1.1.0；1.9.9 -> 2.0.0
// 非三段式版本号原样返回。
func bumpVersion(v string) string {
	parts := strings.Split(v, ".")
	if len(parts) != 3 {
		return v
	}
	major, err1 := strconv.Atoi(parts[0])
	minor, err2 := strconv.Atoi(parts[1])
	patch, err3 := strconv.Atoi(parts[2])
	if err1 != nil || err2 != nil || err3 != nil {
		return v
	}
	patch++
	if patch >= 10 {
		patch = 0
		minor++
		if minor >= 10 {
			minor = 0
			major++
		}
	}
	return fmt.Sprintf("%d.%d.%d", major, minor, patch)
}

// compareVersion 比较两个三段式版本号。返回正/零/负 表示 a 大于/等于/小于 b。
// 非数字段当 0 处理。
func compareVersion(a, b string) int {
	ap := strings.Split(a, ".")
	bp := strings.Split(b, ".")
	for i := 0; i < 3; i++ {
		av, bv := 0, 0
		if i < len(ap) {
			av, _ = strconv.Atoi(ap[i])
		}
		if i < len(bp) {
			bv, _ = strconv.Atoi(bp[i])
		}
		if av != bv {
			return av - bv
		}
	}
	return 0
}

func getMinSupportedBuild(m *manifest.Manifest, platforms []string) int {
	for _, p := range platforms {
		if pm := m.Get(p); pm != nil && pm.MinSupportedBuild > 0 {
			return pm.MinSupportedBuild
		}
	}
	return 1
}

func contains(s []string, v string) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}
