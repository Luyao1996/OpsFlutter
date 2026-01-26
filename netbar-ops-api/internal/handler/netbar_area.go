package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/middleware"
	"netbar-ops-api/internal/model"
)

func GetNetbarAreas(c *gin.Context) {
	netbarID := c.Param("netbar_id")
	if id64, err := strconv.ParseUint(netbarID, 10, 32); err == nil && id64 > 0 {
		if !middleware.RequireNetbarAccess(c, uint(id64)) {
			return
		}
	}

	var areas []model.NetbarArea
	if err := database.MainDB.Where("netbar_id = ?", netbarID).Find(&areas).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, areas)
}

func GetNetbarArea(c *gin.Context) {
	id := c.Param("id")

	var area model.NetbarArea
	if err := database.MainDB.First(&area, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "区域不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, area.NetbarID) {
		return
	}

	c.JSON(http.StatusOK, area)
}

type CreateNetbarAreaRequest struct {
	NetbarID uint   `json:"netbar_id" binding:"required"`
	Name     string `json:"name" binding:"required"`
	StartIP  string `json:"start_ip"`
	EndIP    string `json:"end_ip"`
}

func CreateNetbarArea(c *gin.Context) {
	var req CreateNetbarAreaRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}
	if !middleware.RequireNetbarAccess(c, req.NetbarID) {
		return
	}

	// 从URL获取netbar_id
	netbarIDStr := c.Param("netbar_id")
	if netbarIDStr != "" {
		if id64, err := strconv.ParseUint(netbarIDStr, 10, 32); err == nil && id64 > 0 {
			if !middleware.RequireNetbarAccess(c, uint(id64)) {
				return
			}
		}
		// 验证网吧存在
		var netbar model.Netbar
		if err := database.MainDB.First(&netbar, netbarIDStr).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "网吧不存在"})
			return
		}
	}

	area := model.NetbarArea{
		NetbarID: req.NetbarID,
		Name:     req.Name,
		StartIP:  req.StartIP,
		EndIP:    req.EndIP,
	}

	if err := database.MainDB.Create(&area).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}

	c.JSON(http.StatusCreated, area)
}

func UpdateNetbarArea(c *gin.Context) {
	id := c.Param("id")

	var area model.NetbarArea
	if err := database.MainDB.First(&area, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "区域不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, area.NetbarID) {
		return
	}

	var updates map[string]interface{}
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	if err := database.MainDB.Model(&area).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}

	c.JSON(http.StatusOK, area)
}

func DeleteNetbarArea(c *gin.Context) {
	id := c.Param("id")

	var area model.NetbarArea
	if err := database.MainDB.First(&area, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "区域不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, area.NetbarID) {
		return
	}

	if err := database.MainDB.Delete(&model.NetbarArea{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// GetAllAreas 获取所有区域（跨网吧）
func GetAllAreas(c *gin.Context) {
	var areas []model.NetbarArea

	query := database.MainDB.Model(&model.NetbarArea{})

	if search := c.Query("search"); search != "" {
		query = query.Where("name LIKE ?", "%"+search+"%")
	}

	if err := query.Find(&areas).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, areas)
}
