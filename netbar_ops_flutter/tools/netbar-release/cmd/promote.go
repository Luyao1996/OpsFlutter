package main

import (
	"fmt"

	"github.com/spf13/cobra"

	"netbar-release/internal/release"
	"netbar-release/internal/ui"
)

func promoteCmd() *cobra.Command {
	var (
		flagPlatform string
		flagYes      bool
	)

	cmd := &cobra.Command{
		Use:   "release-preview-promote",
		Short: "把 version.json 中的 preview 提升为正式版",
		Long: `把 version.json 中各平台的 preview 字段移入 releases 数组并清空 preview，
随后上传更新后的 manifest。不会重新上传安装包文件。`,
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, store, err := loadStore()
			if err != nil {
				return err
			}

			platform := flagPlatform
			if platform == "" {
				platform = "both"
			}
			if platform != "android" && platform != "windows" && platform != "both" {
				return fmt.Errorf("无效平台: %s (期望 android | windows | both)", platform)
			}
			platforms := release.ExpandPlatforms(platform)

			fmt.Println("╔══════════════════════════════════╗")
			fmt.Println("║  NetBar-Ops 预览版升级正式版      ║")
			fmt.Println("╚══════════════════════════════════╝")
			fmt.Println()

			fmt.Println("→ 拉取当前 version.json ...")
			cur, err := store.Fetch()
			if err != nil {
				return fmt.Errorf("fetch manifest: %w", err)
			}

			// 收集待 promote 的平台
			type pending struct {
				platform string
				version  string
				build    int
			}
			var todo []pending
			for _, p := range platforms {
				pm := cur.Get(p)
				if pm == nil || pm.Preview == nil {
					fmt.Printf("   · %-7s 无预览版，跳过\n", p)
					continue
				}
				todo = append(todo, pending{
					platform: p,
					version:  pm.Preview.Version,
					build:    pm.Preview.BuildNumber,
				})
				fmt.Printf("   ✓ %-7s 待升级: %s (build %d)\n", p, pm.Preview.Version, pm.Preview.BuildNumber)
			}
			if len(todo) == 0 {
				fmt.Println()
				fmt.Println("没有需要升级的预览版，已退出")
				return nil
			}

			// 二次确认
			if !flagYes {
				fmt.Println()
				fmt.Println("⚠ 确认后所有正式版用户下次启动检查将收到此版本更新提示")
				ok, _ := ui.AskConfirm("继续升级以上预览版为正式版?", false)
				if !ok {
					fmt.Println("已取消")
					return nil
				}
			}

			// 备份
			fmt.Println()
			fmt.Println("→ 备份当前 version.json ...")
			if backupKey, err := store.Backup(cur); err != nil {
				fmt.Printf("   ⚠ 备份失败: %v\n", err)
			} else {
				fmt.Printf("   ✓ 备份: %s\n", backupKey)
			}

			// 执行 promote
			for _, t := range todo {
				promoted, err := cur.PromotePreview(t.platform, cfg.MaxReleases)
				if err != nil {
					return fmt.Errorf("promote %s: %w", t.platform, err)
				}
				if promoted == nil {
					// 理论上不会到这里，因为 todo 已校验
					continue
				}
				fmt.Printf("   ✓ %s: %s (build %d) 已移入 releases\n",
					t.platform, promoted.Version, promoted.BuildNumber)
			}

			// 上传
			fmt.Println()
			fmt.Println("→ 上传 version.json ...")
			if err := store.Upload(cur); err != nil {
				return fmt.Errorf("upload manifest: %w", err)
			}
			fmt.Println("   ✓ version.json 已更新")

			fmt.Println()
			fmt.Println("══════════════════════════════════")
			fmt.Println("✓ 预览版升级完成")
			for _, t := range todo {
				fmt.Printf("  %s: v%s (build %d)\n", t.platform, t.version, t.build)
			}
			fmt.Println("══════════════════════════════════")
			return nil
		},
	}

	cmd.Flags().StringVarP(&flagPlatform, "platform", "p", "both", "android | windows | both")
	cmd.Flags().BoolVarP(&flagYes, "yes", "y", false, "跳过确认 (CI 友好)")
	return cmd
}
