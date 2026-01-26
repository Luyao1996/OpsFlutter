package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/middleware"
	"netbar-ops-api/internal/model"
)

func GetDesktops(c *gin.Context) {
	var desktops []model.Desktop

	query := database.MainDB.Model(&model.Desktop{})

	if search := c.Query("search"); search != "" {
		query = query.Where("name LIKE ? OR code LIKE ? OR ip LIKE ?", "%"+search+"%", "%"+search+"%", "%"+search+"%")
	}

	if netbarID := c.Query("netbar_id"); netbarID != "" {
		if id64, err := strconv.ParseUint(netbarID, 10, 32); err == nil && id64 > 0 {
			if !middleware.RequireNetbarAccess(c, uint(id64)) {
				return
			}
		}
		query = query.Where("netbar_id = ?", netbarID)
	} else {
		// 非管理员默认仅可见自己有权限的网吧
		if !middleware.IsSuperAdmin(c) {
			allowed := middleware.GetAllowedNetbarIDs(c)
			if len(allowed) == 0 {
				c.JSON(http.StatusOK, []model.Desktop{})
				return
			}
			query = query.Where("netbar_id IN ?", allowed)
		}
	}

	if status := c.Query("status"); status != "" {
		query = query.Where("status = ?", status)
	}

	if err := query.Find(&desktops).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, desktops)
}

func GetDesktop(c *gin.Context) {
	id := c.Param("id")

	var desktop model.Desktop
	if err := database.MainDB.First(&desktop, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "桌面不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, desktop.NetbarID) {
		return
	}

	c.JSON(http.StatusOK, desktop)
}

func CreateDesktop(c *gin.Context) {
	var desktop model.Desktop
	if err := c.ShouldBindJSON(&desktop); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}
	if !middleware.RequireNetbarAccess(c, desktop.NetbarID) {
		return
	}

	if err := database.MainDB.Create(&desktop).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}

	c.JSON(http.StatusCreated, desktop)
}

func UpdateDesktop(c *gin.Context) {
	id := c.Param("id")

	var desktop model.Desktop
	if err := database.MainDB.First(&desktop, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "桌面不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, desktop.NetbarID) {
		return
	}

	if err := c.ShouldBindJSON(&desktop); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}
	if !middleware.RequireNetbarAccess(c, desktop.NetbarID) {
		return
	}

	if err := database.MainDB.Save(&desktop).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}

	c.JSON(http.StatusOK, desktop)
}

func DeleteDesktop(c *gin.Context) {
	id := c.Param("id")

	var desktop model.Desktop
	if err := database.MainDB.First(&desktop, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "桌面不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, desktop.NetbarID) {
		return
	}

	if err := database.MainDB.Delete(&model.Desktop{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}
