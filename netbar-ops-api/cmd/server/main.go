package main

import (
	"fmt"
	"log"

	"golang.org/x/crypto/bcrypt"

	"netbar-ops-api/internal/config"
	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
	"netbar-ops-api/internal/router"
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

	// 初始化默认管理员
	initDefaultAdmin()

	// 启动服务器
	r := router.Setup(config.AppConfig.Server.Mode)

	addr := fmt.Sprintf(":%d", config.AppConfig.Server.Port)
	log.Printf("服务器启动在 http://localhost%s", addr)

	if err := r.Run(addr); err != nil {
		log.Fatalf("服务器启动失败: %v", err)
	}
}

func initDefaultAdmin() {
	var count int64
	database.MainDB.Model(&model.User{}).Count(&count)

	if count == 0 {
		hashedPassword, _ := bcrypt.GenerateFromPassword([]byte("admin123"), bcrypt.DefaultCost)
		admin := model.User{
			Username: "admin",
			Password: string(hashedPassword),
			Name:     "Administrator",
			Role:     "admin",
			Status:   1,
		}
		database.MainDB.Create(&admin)
		log.Println("已创建默认管理员账户: admin / admin123")
	}
}
