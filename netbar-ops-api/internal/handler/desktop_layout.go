package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/datatypes"
	"gorm.io/gorm"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

// GetDesktopLayouts 获取所有桌面布局配置
func GetDesktopLayouts(c *gin.Context) {
	netbarIDStr := c.Query("netbar_id")

	// 默认仅返回全局模板（netbar_id 为空）
	if netbarIDStr == "" {
		var globals []model.DesktopLayout
		if err := database.MainDB.
			Where("netbar_id IS NULL OR netbar_id = 0").
			Find(&globals).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "获取桌面布局失败"})
			return
		}
		c.JSON(http.StatusOK, globals)
		return
	}

	netbarID64, err := strconv.ParseUint(netbarIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的网吧ID"})
		return
	}
	netbarID := uint(netbarID64)

	var globals []model.DesktopLayout
	if err := database.MainDB.
		Where("netbar_id IS NULL OR netbar_id = 0").
		Find(&globals).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取桌面布局失败"})
		return
	}

	var locals []model.DesktopLayout
	if err := database.MainDB.
		Where("netbar_id = ?", netbarID).
		Find(&locals).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取网吧桌面布局失败"})
		return
	}

	// 覆盖逻辑：locals 中 base_layout_id != nil 的记录覆盖同 id 的 global
	overrideByBase := map[uint]model.DesktopLayout{}
	var extra []model.DesktopLayout
	for _, l := range locals {
		if l.BaseLayoutID != nil {
			overrideByBase[*l.BaseLayoutID] = l
		} else {
			extra = append(extra, l)
		}
	}

	merged := make([]model.DesktopLayout, 0, len(globals)+len(extra))
	usedOverride := map[uint]bool{}
	for _, g := range globals {
		if o, ok := overrideByBase[g.ID]; ok {
			merged = append(merged, o)
			usedOverride[g.ID] = true
		} else {
			merged = append(merged, g)
		}
	}
	for baseID, o := range overrideByBase {
		if usedOverride[baseID] {
			continue
		}
		merged = append(merged, o)
	}
	merged = append(merged, extra...)

	c.JSON(http.StatusOK, merged)
}

// GetDesktopLayout 获取单个桌面布局配置
func GetDesktopLayout(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的ID"})
		return
	}

	var layout model.DesktopLayout
	if err := database.MainDB.First(&layout, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "桌面布局不存在"})
		return
	}
	c.JSON(http.StatusOK, layout)
}

// CreateDesktopLayout 创建桌面布局配置
func CreateDesktopLayout(c *gin.Context) {
	var req struct {
		NetbarID        *uint                     `json:"netbar_id"`
		BaseLayoutID    *uint                     `json:"base_layout_id"`
		Name            string                    `json:"name" binding:"required"`
		Resolution      string                    `json:"resolution"`
		BackgroundURL   string                    `json:"background_url"`
		BackgroundMode  string                    `json:"background_mode"`
		BackgroundDelay int                       `json:"background_delay"`
		Icons           []model.DesktopLayoutIcon `json:"icons"`
		LockIcons       bool                      `json:"lock_icons"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	iconsJSON, _ := json.Marshal(req.Icons)

	layout := model.DesktopLayout{
		NetbarID:        req.NetbarID,
		BaseLayoutID:    req.BaseLayoutID,
		Name:            req.Name,
		Resolution:      req.Resolution,
		BackgroundURL:   req.BackgroundURL,
		BackgroundMode:  req.BackgroundMode,
		BackgroundDelay: req.BackgroundDelay,
		Icons:           datatypes.JSON(iconsJSON),
		LockIcons:       req.LockIcons,
	}

	// 覆盖：base_layout_id 仅在网吧模式下允许
	if layout.BaseLayoutID != nil && layout.NetbarID == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "base_layout_id 必须配合 netbar_id 使用"})
		return
	}

	if layout.Resolution == "" {
		layout.Resolution = "1920*1080"
	}
	if layout.BackgroundMode == "" {
		layout.BackgroundMode = "center"
	}

	// 若为覆盖，优先 upsert（避免同一网吧对同一全局模板产生重复覆盖记录）
	if layout.NetbarID != nil && layout.BaseLayoutID != nil {
		var existing model.DesktopLayout
		err := database.MainDB.
			Where("netbar_id = ? AND base_layout_id = ?", *layout.NetbarID, *layout.BaseLayoutID).
			First(&existing).Error
		if err == nil {
			existing.Name = layout.Name
			existing.Resolution = layout.Resolution
			existing.BackgroundURL = layout.BackgroundURL
			existing.BackgroundMode = layout.BackgroundMode
			existing.BackgroundDelay = layout.BackgroundDelay
			existing.Icons = layout.Icons
			existing.LockIcons = layout.LockIcons
			if err := database.MainDB.Save(&existing).Error; err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "保存网吧覆盖布局失败"})
				return
			}
			c.JSON(http.StatusCreated, existing)
			return
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "查询网吧覆盖布局失败"})
			return
		}
	}

	if err := database.MainDB.Create(&layout).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建桌面布局失败"})
		return
	}

	c.JSON(http.StatusCreated, layout)
}

// UpdateDesktopLayout 更新桌面布局配置
func UpdateDesktopLayout(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的ID"})
		return
	}

	var layout model.DesktopLayout
	if err := database.MainDB.First(&layout, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "桌面布局不存在"})
		return
	}

	var req struct {
		NetbarID        *uint                     `json:"netbar_id"`
		BaseLayoutID    *uint                     `json:"base_layout_id"`
		Name            string                    `json:"name"`
		Resolution      string                    `json:"resolution"`
		BackgroundURL   string                    `json:"background_url"`
		BackgroundMode  string                    `json:"background_mode"`
		BackgroundDelay int                       `json:"background_delay"`
		Icons           []model.DesktopLayoutIcon `json:"icons"`
		LockIcons       bool                      `json:"lock_icons"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Name != "" {
		layout.Name = req.Name
	}
	if req.Resolution != "" {
		layout.Resolution = req.Resolution
	}
	if req.BaseLayoutID != nil && req.NetbarID == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "base_layout_id 必须配合 netbar_id 使用"})
		return
	}
	if req.NetbarID != nil {
		layout.NetbarID = req.NetbarID
		layout.BaseLayoutID = req.BaseLayoutID
	}
	layout.BackgroundURL = req.BackgroundURL
	layout.BackgroundMode = req.BackgroundMode
	layout.BackgroundDelay = req.BackgroundDelay
	layout.LockIcons = req.LockIcons

	if req.Icons != nil {
		iconsJSON, _ := json.Marshal(req.Icons)
		layout.Icons = datatypes.JSON(iconsJSON)
	}

	if err := database.MainDB.Save(&layout).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新桌面布局失败"})
		return
	}

	c.JSON(http.StatusOK, layout)
}

// DeleteDesktopLayout 删除桌面布局配置
func DeleteDesktopLayout(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的ID"})
		return
	}

	if err := database.MainDB.Delete(&model.DesktopLayout{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除桌面布局失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}
