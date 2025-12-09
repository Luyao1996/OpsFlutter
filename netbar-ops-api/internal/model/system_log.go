package model

import (
	"time"
)

// SystemLog 存储在日志数据库中
type SystemLog struct {
	ID        uint      `gorm:"primarykey" json:"id"`
	Level     string    `gorm:"size:20;index" json:"level"` // info, warn, error
	Module    string    `gorm:"size:50;index" json:"module"`
	Action    string    `gorm:"size:100" json:"action"`
	Message   string    `gorm:"size:1000" json:"message"`
	UserID    uint      `gorm:"index" json:"user_id"`
	Username  string    `gorm:"size:50" json:"username"`
	IP        string    `gorm:"size:50" json:"ip"`
	UserAgent string    `gorm:"size:255" json:"user_agent"`
	CreatedAt time.Time `gorm:"index" json:"created_at"`
}

func (SystemLog) TableName() string {
	return "system_logs"
}

