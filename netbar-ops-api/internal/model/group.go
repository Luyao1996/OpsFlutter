package model

import (
	"time"

	"gorm.io/gorm"
)

// Group 用户组
type Group struct {
	ID uint `gorm:"primarykey" json:"id"`
	// NetbarID 为空表示“全局分组”（历史用途，如分公司/组织）；非空表示“网吧内账号组”
	NetbarID  *uint          `gorm:"index" json:"netbar_id,omitempty"`
	Name      string         `gorm:"size:100;not null" json:"name"`
	ParentID  *uint          `gorm:"index" json:"parent_id,omitempty"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Group) TableName() string {
	return "groups"
}

// UserGroup 用户与组的关联
type UserGroup struct {
	ID        uint      `gorm:"primarykey" json:"id"`
	UserID    uint      `gorm:"index" json:"user_id"`
	GroupID   uint      `gorm:"index" json:"group_id"`
	CreatedAt time.Time `json:"created_at"`
}

func (UserGroup) TableName() string {
	return "user_groups"
}

// NetbarGroup 网吧分组
type NetbarGroup struct {
	ID        uint           `gorm:"primarykey" json:"id"`
	Name      string         `gorm:"size:100;not null" json:"name"`
	ParentID  *uint          `gorm:"index" json:"parent_id,omitempty"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func (NetbarGroup) TableName() string {
	return "netbar_groups"
}

// NetbarGroupRelation 网吧与分组的关联
type NetbarGroupRelation struct {
	ID        uint      `gorm:"primarykey" json:"id"`
	NetbarID  uint      `gorm:"index" json:"netbar_id"`
	GroupID   uint      `gorm:"index" json:"group_id"`
	CreatedAt time.Time `json:"created_at"`
}

func (NetbarGroupRelation) TableName() string {
	return "netbar_group_relations"
}
