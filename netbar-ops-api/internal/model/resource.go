package model

import (
	"time"

	"gorm.io/gorm"
)

// Resource 资源文件
type Resource struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"size:255;not null" json:"name"`
	Path        string         `gorm:"size:500" json:"path"`
	StoragePath string         `gorm:"size:500" json:"storage_path,omitempty"` // 实际磁盘存储路径
	ParentID    *uint          `gorm:"index" json:"parent_id,omitempty"`
	NetbarID    uint           `gorm:"index" json:"netbar_id"`
	IsDirectory bool           `gorm:"default:false" json:"is_directory"`
	Type        string         `gorm:"size:50" json:"type"` // exe, config, archive, script, image, folder, unknown
	Size        int64          `gorm:"default:0" json:"size"`
	Zone        string         `gorm:"size:50;default:HEADQUARTERS" json:"zone"` // HEADQUARTERS, BRANCH, PUBLIC
	Uploader    string         `gorm:"size:100" json:"uploader"`
	UploaderID  uint           `gorm:"index" json:"uploader_id"`
	Hash        string         `gorm:"size:64" json:"hash,omitempty"` // 文件MD5哈希
	IsGlobal    bool           `gorm:"default:true" json:"is_global"`
	Content     string         `gorm:"type:text" json:"content,omitempty"` // 文本文件内容
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Resource) TableName() string {
	return "resources"
}

// ResourceTarget 资源分发目标
type ResourceTarget struct {
	ID         uint      `gorm:"primarykey" json:"id"`
	ResourceID uint      `gorm:"index" json:"resource_id"`
	NetbarID   uint      `gorm:"index" json:"netbar_id"`
	CreatedAt  time.Time `json:"created_at"`
}

func (ResourceTarget) TableName() string {
	return "resource_targets"
}
