package handler

import (
	"net/http"
	"strconv"
	"time"

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
		like := "%" + search + "%"
		query = query.Where("message LIKE ? OR action LIKE ? OR username LIKE ?", like, like, like)
		if id, err := strconv.Atoi(search); err == nil && id > 0 {
			query = query.Or("id = ?", id)
		}
	}

	// 时间范围（按日期，包含 end_date 当天）
	if startDate := c.Query("start_date"); startDate != "" {
		if endDate := c.Query("end_date"); endDate != "" {
			start, err1 := time.ParseInLocation("2006-01-02", startDate, time.Local)
			end, err2 := time.ParseInLocation("2006-01-02", endDate, time.Local)
			if err1 == nil && err2 == nil {
				if end.Before(start) {
					start, end = end, start
				}
				endExclusive := end.AddDate(0, 0, 1)
				query = query.Where("created_at >= ? AND created_at < ?", start, endExclusive)
			}
		}
	}

	// 分页
	page := 1
	pageSize := 50
	if p, err := strconv.Atoi(c.Query("page")); err == nil && p > 0 {
		page = p
	}
	if ps, err := strconv.Atoi(c.Query("page_size")); err == nil && ps > 0 {
		pageSize = ps
	}
	if pageSize > 200 {
		pageSize = 200
	}

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
