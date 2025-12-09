package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

func GetTerminals(c *gin.Context) {
	var terminals []model.Terminal

	query := database.MainDB.Model(&model.Terminal{})

	if search := c.Query("search"); search != "" {
		query = query.Where("name LIKE ? OR code LIKE ? OR ip LIKE ?", "%"+search+"%", "%"+search+"%", "%"+search+"%")
	}

	if netbarID := c.Query("netbar_id"); netbarID != "" {
		query = query.Where("netbar_id = ?", netbarID)
	}

	if status := c.Query("status"); status != "" {
		query = query.Where("status = ?", status)
	}

	if termType := c.Query("type"); termType != "" {
		query = query.Where("type = ?", termType)
	}

	if err := query.Find(&terminals).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, terminals)
}

func GetTerminal(c *gin.Context) {
	id := c.Param("id")

	var terminal model.Terminal
	if err := database.MainDB.First(&terminal, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "终端不存在"})
		return
	}

	c.JSON(http.StatusOK, terminal)
}

type CreateTerminalRequest struct {
	Name     string `json:"name" binding:"required"`
	Code     string `json:"code"`
	NetbarID uint   `json:"netbar_id" binding:"required"`
	AreaID   *uint  `json:"area_id,omitempty"`
	IP       string `json:"ip"`
	MAC      string `json:"mac"`
	OS       string `json:"os"`
	Type     string `json:"type"`
}

func CreateTerminal(c *gin.Context) {
	var req CreateTerminalRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	terminal := model.Terminal{
		Name:     req.Name,
		Code:     req.Code,
		NetbarID: req.NetbarID,
		AreaID:   req.AreaID,
		IP:       req.IP,
		MAC:      req.MAC,
		OS:       req.OS,
		Type:     req.Type,
		Status:   0,
	}

	if err := database.MainDB.Create(&terminal).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}

	c.JSON(http.StatusCreated, terminal)
}

func UpdateTerminal(c *gin.Context) {
	id := c.Param("id")

	var terminal model.Terminal
	if err := database.MainDB.First(&terminal, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "终端不存在"})
		return
	}

	var updates map[string]interface{}
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	if err := database.MainDB.Model(&terminal).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}

	c.JSON(http.StatusOK, terminal)
}

func DeleteTerminal(c *gin.Context) {
	id := c.Param("id")

	if err := database.MainDB.Delete(&model.Terminal{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// TerminalRemoteAction 远程操作
type TerminalRemoteAction struct {
	Action string `json:"action" binding:"required"` // restart, shutdown, wakeup, screenshot, remote
}

func TerminalRemote(c *gin.Context) {
	id := c.Param("id")

	var terminal model.Terminal
	if err := database.MainDB.First(&terminal, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "终端不存在"})
		return
	}

	var req TerminalRemoteAction
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	// TODO: 实际实现远程操作逻辑，这里先返回成功
	c.JSON(http.StatusOK, gin.H{
		"message":     "操作指令已下发",
		"terminal_id": terminal.ID,
		"action":      req.Action,
	})
}

// GetTerminalHeartbeat 获取终端心跳状态
func GetTerminalHeartbeat(c *gin.Context) {
	id := c.Param("id")

	var terminal model.Terminal
	if err := database.MainDB.First(&terminal, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "终端不存在"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"terminal_id":    terminal.ID,
		"status":         terminal.Status,
		"cpu_usage":      terminal.CPUUsage,
		"ram_usage":      terminal.RAMUsage,
		"gpu_usage":      terminal.GPUUsage,
		"disk_usage":     terminal.DiskUsage,
		"uptime":         terminal.Uptime,
		"last_heartbeat": terminal.LastHeartbeat,
	})
}

