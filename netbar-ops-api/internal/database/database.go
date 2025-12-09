package database

import (
	"os"
	"path/filepath"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"netbar-ops-api/internal/config"
)

var (
	MainDB *gorm.DB // 主数据库 - 业务数据
	LogsDB *gorm.DB // 日志数据库 - 系统日志
)

func Init() error {
	var err error

	// 确保数据目录存在
	if err = ensureDir(config.AppConfig.Database.Main.Path); err != nil {
		return err
	}
	if err = ensureDir(config.AppConfig.Database.Logs.Path); err != nil {
		return err
	}

	// 连接主数据库
	MainDB, err = gorm.Open(sqlite.Open(config.AppConfig.Database.Main.Path), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return err
	}

	// 连接日志数据库
	LogsDB, err = gorm.Open(sqlite.Open(config.AppConfig.Database.Logs.Path), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return err
	}

	return nil
}

func ensureDir(filePath string) error {
	dir := filepath.Dir(filePath)
	return os.MkdirAll(dir, 0755)
}

func Close() {
	if MainDB != nil {
		db, _ := MainDB.DB()
		db.Close()
	}
	if LogsDB != nil {
		db, _ := LogsDB.DB()
		db.Close()
	}
}

