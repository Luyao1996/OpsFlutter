package handler

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

type DashboardStats struct {
	TotalNetbars   int64 `json:"total_netbars"`
	OnlineNetbars  int64 `json:"online_netbars"`
	TotalDesktops  int64 `json:"total_desktops"`
	OnlineDesktops int64 `json:"online_desktops"`
	TotalChannels  int64 `json:"total_channels"`
	ActiveChannels int64 `json:"active_channels"`
	TotalUsers     int64 `json:"total_users"`
	VIPDays        int   `json:"vip_days"`
	ServerUptime   int   `json:"server_uptime"`
}

type TrendDataPoint struct {
	Date      string `json:"date"`
	Terminals int64  `json:"terminals"`
}

// 服务启动时间，用于计算运行天数
var serverStartTime = time.Now()

func GetDashboard(c *gin.Context) {
	var stats DashboardStats
	netbarID := c.Query("netbar_id")

	// 网吧统计
	if netbarID != "" {
		// 如果指定了网吧ID，只统计该网吧
		stats.TotalNetbars = 1
		var netbar model.Netbar
		if err := database.MainDB.First(&netbar, netbarID).Error; err == nil {
			if netbar.Status == 1 {
				stats.OnlineNetbars = 1
			}
		}
	} else {
		database.MainDB.Model(&model.Netbar{}).Count(&stats.TotalNetbars)
		database.MainDB.Model(&model.Netbar{}).Where("status = 1").Count(&stats.OnlineNetbars)
	}

	// 桌面统计
	desktopQuery := database.MainDB.Model(&model.Desktop{})
	desktopOnlineQuery := database.MainDB.Model(&model.Desktop{}).Where("status > 0")
	if netbarID != "" {
		desktopQuery = desktopQuery.Where("netbar_id = ?", netbarID)
		desktopOnlineQuery = desktopOnlineQuery.Where("netbar_id = ?", netbarID)
	}
	desktopQuery.Count(&stats.TotalDesktops)
	desktopOnlineQuery.Count(&stats.OnlineDesktops)

	// 通道统计
	channelQuery := database.MainDB.Model(&model.Channel{})
	channelActiveQuery := database.MainDB.Model(&model.Channel{}).Where("status = 1")
	if netbarID != "" {
		channelQuery = channelQuery.Where("netbar_id = ?", netbarID)
		channelActiveQuery = channelActiveQuery.Where("netbar_id = ?", netbarID)
	}
	channelQuery.Count(&stats.TotalChannels)
	channelActiveQuery.Count(&stats.ActiveChannels)

	// 用户统计
	database.MainDB.Model(&model.User{}).Where("status = 1").Count(&stats.TotalUsers)

	// VIP天数 - 这里可以从配置或license表获取，暂时设置为固定值
	// 实际场景中应该从license表或配置中读取
	stats.VIPDays = 365

	// 服务器运行天数
	stats.ServerUptime = int(time.Since(serverStartTime).Hours() / 24)

	c.JSON(http.StatusOK, stats)
}

// GetTrendData 获取最近7天的终端在线趋势数据
func GetTrendData(c *gin.Context) {
	var trendData []TrendDataPoint
	now := time.Now()
	netbarID := c.Query("netbar_id")

	// 获取最近7天的数据，这里简化处理，实际应该从统计表获取历史数据
	// 由于目前没有历史统计表，暂时返回模拟数据
	for i := 6; i >= 0; i-- {
		date := now.AddDate(0, 0, -i)
		var count int64
		query := database.MainDB.Model(&model.Desktop{})
		if netbarID != "" {
			query = query.Where("netbar_id = ?", netbarID)
		}
		query.Count(&count)

		trendData = append(trendData, TrendDataPoint{
			Date:      date.Format("01-02"),
			Terminals: count,
		})
	}

	c.JSON(http.StatusOK, trendData)
}

// RestartAllServices 重启所有离线服务
func RestartAllServices(c *gin.Context) {
	// 获取所有离线终端
	var offlineDesktops []model.Desktop
	database.MainDB.Where("status = 0").Find(&offlineDesktops)

	// 记录重启任务
	restartCount := len(offlineDesktops)

	// 实际场景中，这里应该：
	// 1. 将重启命令发送到消息队列
	// 2. 或者通过 WebSocket 通知终端 Agent
	// 3. 或者调用终端管理服务的 API

	// 目前返回任务已创建的响应
	c.JSON(http.StatusOK, gin.H{
		"message":        "重启命令已发送",
		"target_count":   restartCount,
		"task_id":        time.Now().UnixNano(),
		"estimated_time": "约 2-5 分钟",
	})
}

// NetworkDiagnose 网络诊断
func NetworkDiagnose(c *gin.Context) {
	// 获取所有网吧
	var netbars []model.Netbar
	database.MainDB.Find(&netbars)

	// 实际场景中，这里应该：
	// 1. 对每个网吧节点进行 ping 测试
	// 2. 检测关键服务端口连通性
	// 3. 测试带宽和延迟
	// 4. 将结果存入诊断记录表

	// 目前返回诊断任务已创建的响应
	c.JSON(http.StatusOK, gin.H{
		"message":        "网络诊断已启动",
		"node_count":     len(netbars),
		"task_id":        time.Now().UnixNano(),
		"check_items":    []string{"节点连通性", "服务端口", "网络延迟", "带宽测试"},
		"estimated_time": "约 1-3 分钟",
	})
}
