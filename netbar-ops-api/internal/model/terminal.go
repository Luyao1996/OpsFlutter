package model

import (
	"time"

	"gorm.io/gorm"
)

// Terminal 终端详细信息（客户端机器）
type Terminal struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"size:100;not null" json:"name"`
	Code        string         `gorm:"uniqueIndex;size:50" json:"code"`
	NetbarID    uint           `gorm:"index" json:"netbar_id"`
	AreaID      *uint          `gorm:"index" json:"area_id,omitempty"`
	IP          string         `gorm:"size:50" json:"ip"`
	MAC         string         `gorm:"size:50" json:"mac"`
	OS          string         `gorm:"size:100" json:"os"`
	Type        string         `gorm:"size:50;default:client" json:"type"` // server, client, console, cashier
	Status      int            `gorm:"default:0" json:"status"`            // 0: 离线, 1: 在线空闲, 2: 使用中
	CPUUsage    float64        `gorm:"default:0" json:"cpu_usage"`         // CPU使用率 0-100
	RAMUsage    float64        `gorm:"default:0" json:"ram_usage"`         // 内存使用率 0-100
	GPUUsage    float64        `gorm:"default:0" json:"gpu_usage"`         // GPU使用率 0-100
	DiskUsage   float64        `gorm:"default:0" json:"disk_usage"`        // 磁盘使用率 0-100
	Uptime      string         `gorm:"size:50" json:"uptime"`              // 运行时长
	LastOnline  *time.Time     `json:"last_online,omitempty"`
	LastHeartbeat *time.Time   `json:"last_heartbeat,omitempty"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Terminal) TableName() string {
	return "terminals"
}

// NetbarArea 网吧区域
type NetbarArea struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	NetbarID  uint           `gorm:"index" json:"netbar_id"`
	Name      string         `gorm:"size:100;not null" json:"name"`
	StartIP   string         `gorm:"size:50" json:"start_ip"`
	EndIP     string         `gorm:"size:50" json:"end_ip"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func (NetbarArea) TableName() string {
	return "netbar_areas"
}

