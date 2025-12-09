package handler

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"gorm.io/datatypes"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

// GetDesktopLayouts 获取所有桌面布局配置
func GetDesktopLayouts(c *gin.Context) {
	var layouts []model.DesktopLayout
	if err := database.MainDB.Find(&layouts).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取桌面布局失败"})
		return
	}
	c.JSON(http.StatusOK, layouts)
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
		Name:            req.Name,
		Resolution:      req.Resolution,
		BackgroundURL:   req.BackgroundURL,
		BackgroundMode:  req.BackgroundMode,
		BackgroundDelay: req.BackgroundDelay,
		Icons:           datatypes.JSON(iconsJSON),
		LockIcons:       req.LockIcons,
	}

	if layout.Resolution == "" {
		layout.Resolution = "1920*1080"
	}
	if layout.BackgroundMode == "" {
		layout.BackgroundMode = "center"
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
