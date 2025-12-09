package model

import (
	"time"

	"gorm.io/gorm"
)

// StartupItem 启动项配置
type StartupItem struct {
	ID                uint   `gorm:"primarykey" json:"id"`
	ResourceID        uint   `gorm:"index" json:"resource_id"`
	NetbarID          uint   `gorm:"index" json:"netbar_id"`
	Name              string `gorm:"size:255;not null" json:"name"`
	DisplayName       string `gorm:"size:255" json:"display_name,omitempty"` // 启动项显示名称
	Path              string `gorm:"size:500" json:"path"`
	Zone              string `gorm:"size:50;default:HEADQUARTERS" json:"zone"`
	Enabled           bool   `gorm:"default:true" json:"enabled"`
	Args              string `gorm:"size:500" json:"args,omitempty"`
	Delay             int    `gorm:"default:0" json:"delay"` // 延迟秒数
	ForceRun          bool   `gorm:"default:false" json:"force_run"`
	WorkingDir        string `gorm:"size:500" json:"working_dir,omitempty"`
	TargetOS          string `gorm:"size:100" json:"target_os,omitempty"`         // win7,win10,win11
	TargetAreas       string `gorm:"size:500" json:"target_areas,omitempty"`      // 目标区域名称,逗号分隔
	TargetIpRanges    string `gorm:"size:2000" json:"target_ip_ranges,omitempty"` // 目标IP范围JSON
	TimeRange         string `gorm:"size:100" json:"time_range,omitempty"`        // 08:00-23:00
	CrashAction       string `gorm:"size:50;default:none" json:"crash_action"`    // none, restart, reboot_os
	RunAsService      bool   `gorm:"default:false" json:"run_as_service"`
	RandomProcessName bool   `gorm:"default:false" json:"random_process_name"` // 随机进程名
	ReleaseFiles      string `gorm:"type:text" json:"release_files,omitempty"` // 释放文件JSON
	// 禁用相关字段
	DisableDuration  string         `gorm:"size:50" json:"disable_duration,omitempty"`     // permanent 或 天数
	DisableStrategy  string         `gorm:"size:20" json:"disable_strategy,omitempty"`     // global 或 specific
	DisabledAreas    string         `gorm:"size:1000" json:"disabled_areas,omitempty"`     // 禁用区域列表, 逗号分隔
	DisabledIpRanges string         `gorm:"size:2000" json:"disabled_ip_ranges,omitempty"` // IP范围JSON
	DisableExpireAt  *time.Time     `json:"disable_expire_at,omitempty"`                   // 临时禁用到期时间
	CreatedAt        time.Time      `json:"created_at"`
	UpdatedAt        time.Time      `json:"updated_at"`
	DeletedAt        gorm.DeletedAt `gorm:"index" json:"-"`
}

func (StartupItem) TableName() string {
	return "startup_items"
}

// StartupItemStats 启动项运行统计
type StartupItemStats struct {
	ID            uint      `gorm:"primarykey" json:"id"`
	StartupItemID uint      `gorm:"index" json:"startup_item_id"`
	NetbarID      uint      `gorm:"index" json:"netbar_id"`
	LaunchCount   int       `gorm:"default:0" json:"launch_count"`
	FailureCount  int       `gorm:"default:0" json:"failure_count"`
	Survival1Min  int       `gorm:"default:0" json:"survival_1min"`  // 存活<1分钟次数
	Survival10Min int       `gorm:"default:0" json:"survival_10min"` // 存活<10分钟次数
	Survival20Min int       `gorm:"default:0" json:"survival_20min"` // 存活<20分钟次数
	LastUpdated   time.Time `json:"last_updated"`
	CreatedAt     time.Time `json:"created_at"`
}

func (StartupItemStats) TableName() string {
	return "startup_item_stats"
}
