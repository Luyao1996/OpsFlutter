package model

import (
	"time"

	"gorm.io/gorm"
)

type Netbar struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"size:100;not null" json:"name"`
	Code        string         `gorm:"uniqueIndex;size:50" json:"code"`
	Address     string         `gorm:"size:255" json:"address"`
	Contact     string         `gorm:"size:50" json:"contact"`
	Phone       string         `gorm:"size:20" json:"phone"`
	TotalSeats  int            `gorm:"default:0" json:"total_seats"`
	OnlineSeats int            `gorm:"default:0" json:"online_seats"`
	Status      int            `gorm:"default:1" json:"status"` // 1: 在线, 0: 离线
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Netbar) TableName() string {
	return "netbars"
}

