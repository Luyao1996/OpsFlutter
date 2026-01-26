package handler

import (
	"math/rand"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/middleware"
	"netbar-ops-api/internal/model"
)

type MonitorStats struct {
	TotalNetbars   int64          `json:"total_netbars"`
	OnlineNetbars  int64          `json:"online_netbars"`
	TotalDesktops  int64          `json:"total_desktops"`
	OnlineDesktops int64          `json:"online_desktops"`
	IdleDesktops   int64          `json:"idle_desktops"`
	BusyDesktops   int64          `json:"busy_desktops"`
	TotalBandwidth int64          `json:"total_bandwidth"`
	UsedBandwidth  int64          `json:"used_bandwidth"`
	NetbarStats    []NetbarStat   `json:"netbar_stats"`
	ChannelStats   []ChannelStat  `json:"channel_stats"`
	TrafficHistory []TrafficPoint `json:"traffic_history"`
}

type NetbarStat struct {
	ID          uint    `json:"id"`
	Name        string  `json:"name"`
	TotalSeats  int     `json:"total_seats"`
	OnlineSeats int     `json:"online_seats"`
	Status      int     `json:"status"`
	UsageRate   float64 `json:"usage_rate"`
}

type ChannelStat struct {
	ID        uint    `json:"id"`
	Name      string  `json:"name"`
	Type      string  `json:"type"`
	Bandwidth int     `json:"bandwidth"`
	UsedBW    int     `json:"used_bw"`
	Status    int     `json:"status"`
	UsageRate float64 `json:"usage_rate"`
}

type TrafficPoint struct {
	Time     string `json:"time"`
	Upload   int64  `json:"upload"`
	Download int64  `json:"download"`
}

func GetMonitorStats(c *gin.Context) {
	var stats MonitorStats
	rand.Seed(time.Now().UnixNano())

	isSuperAdmin := middleware.IsSuperAdmin(c)
	allowed := middleware.GetAllowedNetbarIDs(c)
	if !isSuperAdmin && len(allowed) == 0 {
		c.JSON(http.StatusOK, stats)
		return
	}

	// 网吧统计
	netbarQuery := database.MainDB.Model(&model.Netbar{})
	netbarOnlineQuery := database.MainDB.Model(&model.Netbar{}).Where("status = 1")
	if !isSuperAdmin {
		netbarQuery = netbarQuery.Where("id IN ?", allowed)
		netbarOnlineQuery = netbarOnlineQuery.Where("id IN ?", allowed)
	}
	netbarQuery.Count(&stats.TotalNetbars)
	netbarOnlineQuery.Count(&stats.OnlineNetbars)

	// 桌面统计
	desktopQuery := database.MainDB.Model(&model.Desktop{})
	desktopOnlineQuery := database.MainDB.Model(&model.Desktop{}).Where("status > 0")
	desktopIdleQuery := database.MainDB.Model(&model.Desktop{}).Where("status = 1")
	desktopBusyQuery := database.MainDB.Model(&model.Desktop{}).Where("status = 2")
	if !isSuperAdmin {
		desktopQuery = desktopQuery.Where("netbar_id IN ?", allowed)
		desktopOnlineQuery = desktopOnlineQuery.Where("netbar_id IN ?", allowed)
		desktopIdleQuery = desktopIdleQuery.Where("netbar_id IN ?", allowed)
		desktopBusyQuery = desktopBusyQuery.Where("netbar_id IN ?", allowed)
	}
	desktopQuery.Count(&stats.TotalDesktops)
	desktopOnlineQuery.Count(&stats.OnlineDesktops)
	desktopIdleQuery.Count(&stats.IdleDesktops)
	desktopBusyQuery.Count(&stats.BusyDesktops)

	// 通道带宽统计
	var channels []model.Channel
	database.MainDB.Where("status = 1").Find(&channels)
	for _, ch := range channels {
		stats.TotalBandwidth += int64(ch.Bandwidth)
		stats.UsedBandwidth += int64(float64(ch.Bandwidth) * (0.3 + rand.Float64()*0.5))
	}

	// 网吧详细统计
	var netbars []model.Netbar
	nbQuery := database.MainDB.Model(&model.Netbar{})
	if !isSuperAdmin {
		nbQuery = nbQuery.Where("id IN ?", allowed)
	}
	nbQuery.Find(&netbars)
	for _, nb := range netbars {
		usageRate := 0.0
		if nb.TotalSeats > 0 {
			usageRate = float64(nb.OnlineSeats) / float64(nb.TotalSeats) * 100
		}
		stats.NetbarStats = append(stats.NetbarStats, NetbarStat{
			ID:          nb.ID,
			Name:        nb.Name,
			TotalSeats:  nb.TotalSeats,
			OnlineSeats: nb.OnlineSeats,
			Status:      nb.Status,
			UsageRate:   usageRate,
		})
	}

	// 通道详细统计
	for _, ch := range channels {
		usedBW := int(float64(ch.Bandwidth) * (0.3 + rand.Float64()*0.5))
		stats.ChannelStats = append(stats.ChannelStats, ChannelStat{
			ID:        ch.ID,
			Name:      ch.Name,
			Type:      ch.Type,
			Bandwidth: ch.Bandwidth,
			UsedBW:    usedBW,
			Status:    ch.Status,
			UsageRate: float64(usedBW) / float64(ch.Bandwidth) * 100,
		})
	}

	// 流量历史 (模拟最近24小时数据)
	now := time.Now()
	for i := 23; i >= 0; i-- {
		t := now.Add(-time.Duration(i) * time.Hour)
		stats.TrafficHistory = append(stats.TrafficHistory, TrafficPoint{
			Time:     t.Format("15:04"),
			Upload:   int64(rand.Intn(500) + 100),
			Download: int64(rand.Intn(2000) + 500),
		})
	}

	c.JSON(http.StatusOK, stats)
}
