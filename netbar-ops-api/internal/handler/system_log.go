package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

func GetSystemLogs(c *gin.Context) {
	var logs []model.SystemLog
	
	query := database.LogsDB.Model(&model.SystemLog{}).Order("created_at DESC")
	
	if level := c.Query("level"); level != "" {
		query = query.Where("level = ?", level)
	}
	
	if module := c.Query("module"); module != "" {
		query = query.Where("module = ?", module)
	}
	
	if search := c.Query("search"); search != "" {
		query = query.Where("message LIKE ? OR action LIKE ?", "%"+search+"%", "%"+search+"%")
	}

	// 分页
	page := 1
	pageSize := 50
	
	var total int64
	query.Count(&total)
	
	query = query.Offset((page - 1) * pageSize).Limit(pageSize)

	if err := query.Find(&logs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data":      logs,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func GetSystemLog(c *gin.Context) {
	id := c.Param("id")
	
	var log model.SystemLog
	if err := database.LogsDB.First(&log, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "日志不存在"})
		return
	}

	c.JSON(http.StatusOK, log)
}

