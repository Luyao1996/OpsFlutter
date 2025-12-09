package model

import (
	"time"

	"gorm.io/gorm"
)

type Desktop struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"size:100;not null" json:"name"`
	Code        string         `gorm:"uniqueIndex;size:50" json:"code"`
	NetbarID    uint           `gorm:"index" json:"netbar_id"`
	IP          string         `gorm:"size:50" json:"ip"`
	MAC         string         `gorm:"size:50" json:"mac"`
	OS          string         `gorm:"size:100" json:"os"`
	Status      int            `gorm:"default:0" json:"status"` // 0: 离线, 1: 空闲, 2: 使用中
	LastOnline  *time.Time     `json:"last_online"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Desktop) TableName() string {
	return "desktops"
}

