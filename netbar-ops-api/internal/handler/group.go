package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

// ==================== 用户组 ====================

func GetGroups(c *gin.Context) {
	var groups []model.Group

	query := database.MainDB.Model(&model.Group{})

	if search := c.Query("search"); search != "" {
		query = query.Where("name LIKE ?", "%"+search+"%")
	}

	if err := query.Find(&groups).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, groups)
}

func GetGroup(c *gin.Context) {
	id := c.Param("id")

	var group model.Group
	if err := database.MainDB.First(&group, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "分组不存在"})
		return
	}

	c.JSON(http.StatusOK, group)
}

type CreateGroupRequest struct {
	Name     string `json:"name" binding:"required"`
	ParentID *uint  `json:"parent_id,omitempty"`
}

func CreateGroup(c *gin.Context) {
	var req CreateGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	group := model.Group{
		Name:     req.Name,
		ParentID: req.ParentID,
	}

	if err := database.MainDB.Create(&group).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}

	c.JSON(http.StatusCreated, group)
}

func UpdateGroup(c *gin.Context) {
	id := c.Param("id")

	var group model.Group
	if err := database.MainDB.First(&group, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "分组不存在"})
		return
	}

	var updates map[string]interface{}
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	if err := database.MainDB.Model(&group).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}

	c.JSON(http.StatusOK, group)
}

func DeleteGroup(c *gin.Context) {
	id := c.Param("id")

	if err := database.MainDB.Delete(&model.Group{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// ==================== 网吧分组 ====================

func GetNetbarGroups(c *gin.Context) {
	var groups []model.NetbarGroup

	query := database.MainDB.Model(&model.NetbarGroup{})

	if search := c.Query("search"); search != "" {
		query = query.Where("name LIKE ?", "%"+search+"%")
	}

	if err := query.Find(&groups).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, groups)
}

func CreateNetbarGroup(c *gin.Context) {
	var req CreateGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	group := model.NetbarGroup{
		Name:     req.Name,
		ParentID: req.ParentID,
	}

	if err := database.MainDB.Create(&group).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}

	c.JSON(http.StatusCreated, group)
}

func UpdateNetbarGroup(c *gin.Context) {
	id := c.Param("id")

	var group model.NetbarGroup
	if err := database.MainDB.First(&group, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "分组不存在"})
		return
	}

	var updates map[string]interface{}
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	if err := database.MainDB.Model(&group).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}

	c.JSON(http.StatusOK, group)
}

func DeleteNetbarGroup(c *gin.Context) {
	id := c.Param("id")

	if err := database.MainDB.Delete(&model.NetbarGroup{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

