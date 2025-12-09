package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

func GetChannels(c *gin.Context) {
	var channels []model.Channel
	
	query := database.MainDB.Model(&model.Channel{})
	
	if search := c.Query("search"); search != "" {
		query = query.Where("name LIKE ? OR code LIKE ?", "%"+search+"%", "%"+search+"%")
	}
	
	if channelType := c.Query("type"); channelType != "" {
		query = query.Where("type = ?", channelType)
	}

	if err := query.Find(&channels).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, channels)
}

func GetChannel(c *gin.Context) {
	id := c.Param("id")
	
	var channel model.Channel
	if err := database.MainDB.First(&channel, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "通道不存在"})
		return
	}

	c.JSON(http.StatusOK, channel)
}

func CreateChannel(c *gin.Context) {
	var channel model.Channel
	if err := c.ShouldBindJSON(&channel); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	if err := database.MainDB.Create(&channel).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}

	c.JSON(http.StatusCreated, channel)
}

func UpdateChannel(c *gin.Context) {
	id := c.Param("id")
	
	var channel model.Channel
	if err := database.MainDB.First(&channel, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "通道不存在"})
		return
	}

	if err := c.ShouldBindJSON(&channel); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	if err := database.MainDB.Save(&channel).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}

	c.JSON(http.StatusOK, channel)
}

func DeleteChannel(c *gin.Context) {
	id := c.Param("id")
	
	if err := database.MainDB.Delete(&model.Channel{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

