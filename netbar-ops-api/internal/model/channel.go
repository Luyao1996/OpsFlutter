package model

import (
	"time"

	"gorm.io/gorm"
)

type Channel struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"size:100;not null" json:"name"`
	Code        string         `gorm:"uniqueIndex;size:50" json:"code"`
	Type        string         `gorm:"size:50" json:"type"` // game, video, download
	Bandwidth   int            `gorm:"default:0" json:"bandwidth"` // Mbps
	Status      int            `gorm:"default:1" json:"status"` // 1: 启用, 0: 禁用
	Description string         `gorm:"size:500" json:"description"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Channel) TableName() string {
	return "channels"
}

