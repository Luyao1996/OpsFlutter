package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

func GetDesktops(c *gin.Context) {
	var desktops []model.Desktop
	
	query := database.MainDB.Model(&model.Desktop{})
	
	if search := c.Query("search"); search != "" {
		query = query.Where("name LIKE ? OR code LIKE ? OR ip LIKE ?", "%"+search+"%", "%"+search+"%", "%"+search+"%")
	}
	
	if netbarID := c.Query("netbar_id"); netbarID != "" {
		query = query.Where("netbar_id = ?", netbarID)
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

	c.JSON(http.StatusOK, desktop)
}

func CreateDesktop(c *gin.Context) {
	var desktop model.Desktop
	if err := c.ShouldBindJSON(&desktop); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
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

	if err := c.ShouldBindJSON(&desktop); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
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
	
	if err := database.MainDB.Delete(&model.Desktop{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

