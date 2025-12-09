package main

import (
	"log"
	"os"

	"netbar-ops-api/internal/config"
	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
	"netbar-ops-api/internal/seed"
)

func main() {
	// 加载配置
	if err := config.Load("config.yaml"); err != nil {
		log.Fatalf("加载配置失败: %v", err)
	}

	// 初始化数据库
	if err := database.Init(); err != nil {
		log.Fatalf("初始化数据库失败: %v", err)
	}
	defer database.Close()

	// 自动迁移 - 主数据库
	if err := database.MainDB.AutoMigrate(
		&model.User{},
		&model.Netbar{},
		&model.Channel{},
		&model.Desktop{},
		&model.DesktopLayout{},
		&model.Terminal{},
		&model.NetbarArea{},
		&model.Resource{},
		&model.ResourceTarget{},
		&model.StartupItem{},
		&model.StartupItemStats{},
		&model.Group{},
		&model.UserGroup{},
		&model.NetbarGroup{},
		&model.NetbarGroupRelation{},
	); err != nil {
		log.Fatalf("主数据库迁移失败: %v", err)
	}

	// 自动迁移 - 日志数据库
	if err := database.LogsDB.AutoMigrate(
		&model.SystemLog{},
	); err != nil {
		log.Fatalf("日志数据库迁移失败: %v", err)
	}

	log.Println("开始生成测试数据...")

	// 设置日志数据库
	seed.LogsDB = database.LogsDB

	if err := seed.Run(database.MainDB); err != nil {
		log.Fatalf("生成测试数据失败: %v", err)
	}

	log.Println("✅ 测试数据生成完成！")
	log.Println("默认账户: admin / admin123")
	log.Println("测试账户: operator1, operator2, tech1, manager 密码均为 123456")
	os.Exit(0)
}
