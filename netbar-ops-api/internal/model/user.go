package model

import (
	"time"

	"gorm.io/gorm"
)

type User struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Username    string         `gorm:"uniqueIndex;size:50;not null" json:"username"`
	Password    string         `gorm:"size:255;not null" json:"-"`
	Name        string         `gorm:"size:100" json:"name"`
	Role        string         `gorm:"size:50;default:user" json:"role"` // admin, user
	Email       string         `gorm:"size:100" json:"email"`
	Phone       string         `gorm:"size:20" json:"phone"`
	GroupID     *uint          `gorm:"index" json:"group_id,omitempty"`
	Status      int            `gorm:"default:1" json:"status"` // 1: 启用, 0: 禁用
	TwoFASecret string         `gorm:"size:64" json:"-"`        // 2FA 密钥
	Is2FABound  bool           `gorm:"default:false" json:"is_2fa_bound"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

func (User) TableName() string {
	return "users"
}
