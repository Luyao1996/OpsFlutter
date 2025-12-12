package model

import (
	"time"

	"gorm.io/datatypes"
	"gorm.io/gorm"
)

// DesktopLayoutIcon 桌面图标配置
type DesktopLayoutIcon struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	ExePath string `json:"exePath"`
	Args    string `json:"args,omitempty"`
	WorkDir string `json:"workDir,omitempty"`
	IconPath string `json:"iconPath,omitempty"`
	X       int    `json:"x"`
	Y       int    `json:"y"`
}

// DesktopLayout 桌面布局配置
type DesktopLayout struct {
	ID              uint           `gorm:"primarykey" json:"id"`
	Name            string         `gorm:"size:100;not null" json:"name"`
	Resolution      string         `gorm:"size:20;default:'1920*1080'" json:"resolution"`
	BackgroundURL   string         `gorm:"size:500" json:"background_url"`
	BackgroundMode  string         `gorm:"size:20;default:'center'" json:"background_mode"`
	BackgroundDelay int            `gorm:"default:10" json:"background_delay"`
	Icons           datatypes.JSON `gorm:"type:json" json:"icons"`
	LockIcons       bool           `gorm:"default:false" json:"lock_icons"`
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`
}

func (DesktopLayout) TableName() string {
	return "desktop_layouts"
}
