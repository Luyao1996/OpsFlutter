package handler

import (
	"math/rand"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

func GetStartupItems(c *gin.Context) {
	var items []model.StartupItem

	query := database.MainDB.Model(&model.StartupItem{})

	if zone := c.Query("zone"); zone != "" {
		query = query.Where("zone = ?", zone)
	}

	// netbar_id 过滤逻辑：
	// - 总部(HEADQUARTERS): netbar_id = 0
	// - 分公司(BRANCH): netbar_id = 分组ID
	// - 本网吧(PUBLIC): netbar_id = 网吧ID
	if netbarID := c.Query("netbar_id"); netbarID != "" {
		query = query.Where("netbar_id = ?", netbarID)
	}

	if enabled := c.Query("enabled"); enabled != "" {
		query = query.Where("enabled = ?", enabled == "true")
	}

	if search := c.Query("search"); search != "" {
		query = query.Where("name LIKE ?", "%"+search+"%")
	}

	if err := query.Find(&items).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, items)
}

func GetStartupItem(c *gin.Context) {
	id := c.Param("id")

	var item model.StartupItem
	if err := database.MainDB.First(&item, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "启动项不存在"})
		return
	}

	c.JSON(http.StatusOK, item)
}

type CreateStartupItemRequest struct {
	ResourceID   uint   `json:"resource_id"`
	NetbarID     uint   `json:"netbar_id"`
	Name         string `json:"name" binding:"required"`
	DisplayName  string `json:"display_name,omitempty"` // 启动项显示名称
	Path         string `json:"path" binding:"required"`
	Zone         string `json:"zone"`
	Enabled      bool   `json:"enabled"`
	Args         string `json:"args,omitempty"`
	Delay        int    `json:"delay"`
	ForceRun     bool   `json:"force_run"`
	WorkingDir   string `json:"working_dir,omitempty"`
	TargetOS     string `json:"target_os,omitempty"`
	TargetAreas  string `json:"target_areas,omitempty"`
	TimeRange    string `json:"time_range,omitempty"`
	CrashAction  string `json:"crash_action"`
	RunAsService bool   `json:"run_as_service"`
}

func CreateStartupItem(c *gin.Context) {
	var req CreateStartupItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	item := model.StartupItem{
		ResourceID:   req.ResourceID,
		NetbarID:     req.NetbarID,
		Name:         req.Name,
		DisplayName:  req.DisplayName,
		Path:         req.Path,
		Zone:         req.Zone,
		Enabled:      req.Enabled,
		Args:         req.Args,
		Delay:        req.Delay,
		ForceRun:     req.ForceRun,
		WorkingDir:   req.WorkingDir,
		TargetOS:     req.TargetOS,
		TargetAreas:  req.TargetAreas,
		TimeRange:    req.TimeRange,
		CrashAction:  req.CrashAction,
		RunAsService: req.RunAsService,
	}

	if item.Zone == "" {
		item.Zone = "HEADQUARTERS"
	}
	if item.CrashAction == "" {
		item.CrashAction = "none"
	}

	if err := database.MainDB.Create(&item).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}

	c.JSON(http.StatusCreated, item)
}

func UpdateStartupItem(c *gin.Context) {
	id := c.Param("id")

	var item model.StartupItem
	if err := database.MainDB.First(&item, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "启动项不存在"})
		return
	}

	var updates map[string]interface{}
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误: " + err.Error()})
		return
	}

	// 转换字段名从 snake_case 到数据库字段
	dbUpdates := make(map[string]interface{})
	fieldMapping := map[string]string{
		"name":                "name",
		"display_name":        "display_name",
		"path":                "path",
		"enabled":             "enabled",
		"args":                "args",
		"delay":               "delay",
		"force_run":           "force_run",
		"working_dir":         "working_dir",
		"target_os":           "target_os",
		"target_areas":        "target_areas",
		"target_ip_ranges":    "target_ip_ranges",
		"time_range":          "time_range",
		"crash_action":        "crash_action",
		"run_as_service":      "run_as_service",
		"random_process_name": "random_process_name",
		"release_files":       "release_files",
		"disable_duration":    "disable_duration",
		"disable_strategy":    "disable_strategy",
		"disabled_areas":      "disabled_areas",
		"disabled_ip_ranges":  "disabled_ip_ranges",
	}

	for key, value := range updates {
		if dbField, ok := fieldMapping[key]; ok {
			dbUpdates[dbField] = value
		}
	}

	if len(dbUpdates) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "没有有效的更新字段"})
		return
	}

	if err := database.MainDB.Model(&item).Updates(dbUpdates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败: " + err.Error()})
		return
	}

	// 重新加载更新后的数据
	database.MainDB.First(&item, id)
	c.JSON(http.StatusOK, item)
}

func DeleteStartupItem(c *gin.Context) {
	id := c.Param("id")

	if err := database.MainDB.Delete(&model.StartupItem{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// GetStartupItemMonitor 获取启动项监控数据
func GetStartupItemMonitor(c *gin.Context) {
	// 获取网吧及其启动项统计
	var netbars []model.Netbar
	netbarQuery := database.MainDB.Model(&model.Netbar{})
	if netbarID := c.Query("netbar_id"); netbarID != "" {
		netbarQuery = netbarQuery.Where("id = ?", netbarID)
	}
	netbarQuery.Find(&netbars)

	var items []model.StartupItem
	database.MainDB.Where("enabled = ?", true).Find(&items)

	rand.Seed(time.Now().UnixNano())

	result := make([]gin.H, 0)
	for _, nb := range netbars {
		itemStats := make([]gin.H, 0)
		// 随机选择一些启动项
		for _, item := range items {
			if rand.Float32() > 0.5 {
				launchCount := rand.Intn(200)
				failureCount := rand.Intn(launchCount / 5)
				survival1min := rand.Intn(launchCount)
				survival10min := rand.Intn(survival1min)
				itemStats = append(itemStats, gin.H{
					"id":             item.ID,
					"name":           item.Name,
					"path":           item.Path,
					"launch_count":   launchCount,
					"failure_count":  failureCount,
					"survival_1min":  survival1min,
					"survival_10min": survival10min,
					"survival_20min": rand.Intn(survival10min + 1),
					"last_updated":   time.Now().Add(-time.Duration(rand.Intn(3600)) * time.Second).Format("2006-01-02 15:04"),
				})
			}
		}

		result = append(result, gin.H{
			"id":             nb.ID,
			"name":           nb.Name,
			"status":         nb.Status,
			"terminal_count": nb.TotalSeats,
			"items":          itemStats,
		})
	}

	c.JSON(http.StatusOK, result)
}
