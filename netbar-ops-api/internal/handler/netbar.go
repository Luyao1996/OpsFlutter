package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/middleware"
	"netbar-ops-api/internal/model"
)

func GetNetbars(c *gin.Context) {
	var netbars []model.Netbar

	query := database.MainDB.Model(&model.Netbar{})

	// 网吧可见性隔离（策略B）：非管理员只返回自己有权限的网吧
	if !middleware.IsSuperAdmin(c) {
		allowed := middleware.GetAllowedNetbarIDs(c)
		// 无权限则返回空列表
		if len(allowed) == 0 {
			c.JSON(http.StatusOK, []model.Netbar{})
			return
		}
		query = query.Where("id IN ?", allowed)
	}

	// 搜索
	if search := c.Query("search"); search != "" {
		query = query.Where("name LIKE ? OR code LIKE ?", "%"+search+"%", "%"+search+"%")
	}

	// 状态过滤
	if status := c.Query("status"); status != "" {
		query = query.Where("status = ?", status)
	}

	if err := query.Find(&netbars).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, netbars)
}

func GetNetbar(c *gin.Context) {
	id := c.Param("id")

	if id64, err := strconv.ParseUint(id, 10, 32); err == nil && id64 > 0 {
		if !middleware.RequireNetbarAccess(c, uint(id64)) {
			return
		}
	}

	var netbar model.Netbar
	if err := database.MainDB.First(&netbar, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "网吧不存在"})
		return
	}

	c.JSON(http.StatusOK, netbar)
}

func CreateNetbar(c *gin.Context) {
	var netbar model.Netbar
	if err := c.ShouldBindJSON(&netbar); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	if err := database.MainDB.Create(&netbar).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}

	c.JSON(http.StatusCreated, netbar)
}

func UpdateNetbar(c *gin.Context) {
	id := c.Param("id")

	var netbar model.Netbar
	if err := database.MainDB.First(&netbar, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "网吧不存在"})
		return
	}

	if err := c.ShouldBindJSON(&netbar); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	if err := database.MainDB.Save(&netbar).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}

	c.JSON(http.StatusOK, netbar)
}

func DeleteNetbar(c *gin.Context) {
	id := c.Param("id")

	if err := database.MainDB.Delete(&model.Netbar{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}
