package seed

import (
	"fmt"
	"math/rand"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"

	"netbar-ops-api/internal/model"
)

var LogsDB *gorm.DB

func Run(db *gorm.DB) error {
	// 清空现有数据 (system_logs 在日志数据库中，单独处理)
	db.Exec("DELETE FROM startup_items")
	db.Exec("DELETE FROM resources")
	db.Exec("DELETE FROM terminals")
	db.Exec("DELETE FROM netbar_areas")
	db.Exec("DELETE FROM desktops")
	db.Exec("DELETE FROM channels")
	db.Exec("DELETE FROM netbar_groups")
	db.Exec("DELETE FROM user_groups")
	db.Exec("DELETE FROM netbars")
	db.Exec("DELETE FROM users WHERE username != 'admin'")

	// 创建用户组
	if err := seedUserGroups(db); err != nil {
		return err
	}

	// 创建网吧分组
	if err := seedNetbarGroups(db); err != nil {
		return err
	}

	// 创建用户
	if err := seedUsers(db); err != nil {
		return err
	}

	// 创建网吧
	netbars, err := seedNetbars(db)
	if err != nil {
		return err
	}

	// 创建网吧区域
	if err := seedNetbarAreas(db, netbars); err != nil {
		return err
	}

	// 创建通道
	if err := seedChannels(db); err != nil {
		return err
	}

	// 创建桌面
	if err := seedDesktops(db, netbars); err != nil {
		return err
	}

	// 创建终端
	if err := seedTerminals(db, netbars); err != nil {
		return err
	}

	// 创建资源
	if err := seedResources(db); err != nil {
		return err
	}

	// 创建启动项
	if err := seedStartupItems(db); err != nil {
		return err
	}

	// 创建系统日志 (使用日志数据库)
	if LogsDB != nil {
		LogsDB.Exec("DELETE FROM system_logs")
		if err := seedSystemLogs(LogsDB); err != nil {
			return err
		}
	}

	return nil
}

func seedUserGroups(db *gorm.DB) error {
	groups := []model.Group{
		{Name: "运维组"},
		{Name: "技术组"},
		{Name: "管理组"},
	}
	return db.Create(&groups).Error
}

func seedNetbarGroups(db *gorm.DB) error {
	groups := []model.NetbarGroup{
		{Name: "华北区"},
		{Name: "华东区"},
		{Name: "华南区"},
		{Name: "西南区"},
		{Name: "测试组"},
	}
	return db.Create(&groups).Error
}

func seedUsers(db *gorm.DB) error {
	password, _ := bcrypt.GenerateFromPassword([]byte("123456"), bcrypt.DefaultCost)
	groupID1 := uint(1)
	groupID2 := uint(2)
	users := []model.User{
		{Username: "operator1", Password: string(password), Name: "张三", Role: "user", Email: "zhangsan@example.com", Phone: "13800138001", Status: 1, GroupID: &groupID1},
		{Username: "operator2", Password: string(password), Name: "李四", Role: "user", Email: "lisi@example.com", Phone: "13800138002", Status: 1, GroupID: &groupID1},
		{Username: "tech1", Password: string(password), Name: "王五", Role: "user", Email: "wangwu@example.com", Phone: "13800138003", Status: 1, GroupID: &groupID2},
		{Username: "manager", Password: string(password), Name: "赵经理", Role: "admin", Email: "zhao@example.com", Phone: "13800138004", Status: 1},
	}
	return db.Create(&users).Error
}

func seedNetbars(db *gorm.DB) ([]model.Netbar, error) {
	netbars := []model.Netbar{
		{Name: "星际网咖旗舰店", Code: "NB001", Address: "北京市朝阳区三里屯路88号", Contact: "张店长", Phone: "010-12345678", TotalSeats: 120, OnlineSeats: 98, Status: 1},
		{Name: "极速网络会所", Code: "NB002", Address: "上海市浦东新区陆家嘴环路100号", Contact: "李经理", Phone: "021-87654321", TotalSeats: 80, OnlineSeats: 65, Status: 1},
		{Name: "电竞之家网咖", Code: "NB003", Address: "广州市天河区体育西路200号", Contact: "王主管", Phone: "020-11111111", TotalSeats: 150, OnlineSeats: 120, Status: 1},
		{Name: "梦幻网游城", Code: "NB004", Address: "深圳市南山区科技园路50号", Contact: "赵店长", Phone: "0755-22222222", TotalSeats: 100, OnlineSeats: 0, Status: 0},
		{Name: "网动力电竞馆", Code: "NB005", Address: "成都市锦江区春熙路168号", Contact: "陈经理", Phone: "028-33333333", TotalSeats: 200, OnlineSeats: 180, Status: 1},
		{Name: "飞速网咖", Code: "NB006", Address: "杭州市西湖区文三路300号", Contact: "林店长", Phone: "0571-44444444", TotalSeats: 60, OnlineSeats: 45, Status: 1},
		{Name: "雷霆电竞中心", Code: "NB007", Address: "武汉市武昌区珞喻路100号", Contact: "刘主管", Phone: "027-55555555", TotalSeats: 180, OnlineSeats: 150, Status: 1},
		{Name: "极光网络空间", Code: "NB008", Address: "南京市鼓楼区中山路88号", Contact: "黄经理", Phone: "025-66666666", TotalSeats: 90, OnlineSeats: 70, Status: 1},
	}
	if err := db.Create(&netbars).Error; err != nil {
		return nil, err
	}
	return netbars, nil
}

func seedChannels(db *gorm.DB) error {
	channels := []model.Channel{
		{Name: "游戏加速通道A", Code: "CH001", Type: "game", Bandwidth: 1000, Status: 1, Description: "主力游戏加速通道，支持主流网游"},
		{Name: "游戏加速通道B", Code: "CH002", Type: "game", Bandwidth: 500, Status: 1, Description: "备用游戏通道"},
		{Name: "视频流媒体通道", Code: "CH003", Type: "video", Bandwidth: 2000, Status: 1, Description: "高清视频流媒体专用通道"},
		{Name: "下载加速通道", Code: "CH004", Type: "download", Bandwidth: 5000, Status: 1, Description: "大文件下载加速"},
		{Name: "直播推流通道", Code: "CH005", Type: "video", Bandwidth: 1000, Status: 1, Description: "游戏直播推流专用"},
		{Name: "测试通道", Code: "CH006", Type: "game", Bandwidth: 100, Status: 0, Description: "测试用通道，暂停使用"},
	}
	return db.Create(&channels).Error
}

func seedDesktops(db *gorm.DB, netbars []model.Netbar) error {
	rand.Seed(time.Now().UnixNano())
	osList := []string{"Windows 11 Pro", "Windows 10 Pro", "Windows 11 Home"}

	var desktops []model.Desktop
	for _, nb := range netbars {
		count := nb.TotalSeats / 5 // 每个网吧创建部分桌面作为示例
		if count > 20 {
			count = 20
		}
		for i := 1; i <= count; i++ {
			status := rand.Intn(3) // 0: 离线, 1: 空闲, 2: 使用中
			lastOnline := time.Now().Add(-time.Duration(rand.Intn(24)) * time.Hour)
			desktops = append(desktops, model.Desktop{
				Name:       fmt.Sprintf("%s-%02d", nb.Code, i),
				Code:       fmt.Sprintf("PC-%s-%03d", nb.Code, i),
				NetbarID:   nb.ID,
				IP:         fmt.Sprintf("192.168.%d.%d", nb.ID, 100+i),
				MAC:        fmt.Sprintf("00:1A:2B:3C:%02X:%02X", nb.ID, i),
				OS:         osList[rand.Intn(len(osList))],
				Status:     status,
				LastOnline: &lastOnline,
			})
		}
	}
	return db.Create(&desktops).Error
}

func seedNetbarAreas(db *gorm.DB, netbars []model.Netbar) error {
	var areas []model.NetbarArea
	areaNames := []string{"VIP区", "普通区", "竞技区", "包间区"}
	for _, nb := range netbars {
		for i, name := range areaNames {
			if i >= 2 && rand.Intn(2) == 0 {
				continue // 随机跳过部分区域
			}
			areas = append(areas, model.NetbarArea{
				NetbarID: nb.ID,
				Name:     name,
				StartIP:  fmt.Sprintf("192.168.%d.%d", nb.ID, i*50+1),
				EndIP:    fmt.Sprintf("192.168.%d.%d", nb.ID, i*50+50),
			})
		}
	}
	return db.Create(&areas).Error
}

func seedTerminals(db *gorm.DB, netbars []model.Netbar) error {
	osList := []string{"Windows 11 Pro", "Windows 10 Pro", "Windows Server 2022"}
	typeList := []string{"pc", "server", "console", "cashier"}

	var terminals []model.Terminal
	for _, nb := range netbars {
		// 每个网吧创建一些特殊终端
		for i, termType := range typeList {
			if termType != "pc" {
				status := 1
				if rand.Intn(4) == 0 {
					status = 0
				}
				terminals = append(terminals, model.Terminal{
					Name:     fmt.Sprintf("%s-%s", nb.Code, termType),
					Code:     fmt.Sprintf("T-%s-%s", nb.Code, termType),
					NetbarID: nb.ID,
					IP:       fmt.Sprintf("192.168.%d.%d", nb.ID, 200+i),
					MAC:      fmt.Sprintf("00:2A:3B:4C:%02X:%02X", nb.ID, 200+i),
					OS:       osList[rand.Intn(len(osList))],
					Type:     termType,
					Status:   status,
					CPUUsage: float64(rand.Intn(80)),
					RAMUsage: float64(rand.Intn(70)),
					GPUUsage: float64(rand.Intn(60)),
					Uptime:   fmt.Sprintf("%d天%d小时", rand.Intn(30), rand.Intn(24)),
				})
			}
		}
		// 每个网吧创建若干普通PC终端
		pcCount := nb.TotalSeats / 10
		if pcCount > 15 {
			pcCount = 15
		}
		for i := 1; i <= pcCount; i++ {
			status := rand.Intn(3)
			terminals = append(terminals, model.Terminal{
				Name:     fmt.Sprintf("PC-%s-%02d", nb.Code, i),
				Code:     fmt.Sprintf("T-%s-PC%03d", nb.Code, i),
				NetbarID: nb.ID,
				IP:       fmt.Sprintf("192.168.%d.%d", nb.ID, 10+i),
				MAC:      fmt.Sprintf("00:3A:4B:5C:%02X:%02X", nb.ID, i),
				OS:       osList[rand.Intn(2)],
				Type:     "pc",
				Status:   status,
				CPUUsage: float64(rand.Intn(100)),
				RAMUsage: float64(rand.Intn(90)),
				GPUUsage: float64(rand.Intn(80)),
				Uptime:   fmt.Sprintf("%d天%d小时", rand.Intn(7), rand.Intn(24)),
			})
		}
	}
	return db.Create(&terminals).Error
}

func seedResources(db *gorm.DB) error {
	resources := []model.Resource{
		{Name: "游戏工具", Path: "/games", Type: "folder", Zone: "global"},
		{Name: "系统工具", Path: "/system", Type: "folder", Zone: "global"},
		{Name: "驱动程序", Path: "/drivers", Type: "folder", Zone: "global"},
		{Name: "LOL启动器.exe", Path: "/games/lol-launcher.exe", Type: "file", Zone: "global", Size: 15360000},
		{Name: "Steam.exe", Path: "/games/steam.exe", Type: "file", Zone: "global", Size: 8192000},
		{Name: "WeGame.exe", Path: "/games/wegame.exe", Type: "file", Zone: "global", Size: 12288000},
		{Name: "驱动精灵.exe", Path: "/drivers/drivergenius.exe", Type: "file", Zone: "global", Size: 25600000},
		{Name: "系统修复工具.bat", Path: "/system/repair.bat", Type: "file", Zone: "global", Size: 2048},
		{Name: "网络诊断.exe", Path: "/system/netdiag.exe", Type: "file", Zone: "global", Size: 1024000},
	}
	return db.Create(&resources).Error
}

func seedStartupItems(db *gorm.DB) error {
	items := []model.StartupItem{
		{Name: "Steam客户端", Path: "/games/steam.exe", Zone: "global", Enabled: true, Delay: 0},
		{Name: "WeGame平台", Path: "/games/wegame.exe", Zone: "global", Enabled: true, Delay: 5},
		{Name: "LOL启动器", Path: "/games/lol-launcher.exe", Zone: "global", Enabled: true, Delay: 10},
		{Name: "系统监控", Path: "/system/monitor.exe", Zone: "global", Enabled: true, Delay: 0},
		{Name: "网络优化", Path: "/system/netopt.exe", Zone: "global", Enabled: false, Delay: 15},
	}
	return db.Create(&items).Error
}

func seedSystemLogs(db *gorm.DB) error {
	modules := []string{"auth", "terminal", "netbar", "channel", "system"}
	actions := []string{"登录", "登出", "创建", "更新", "删除", "重启", "关机", "远程连接"}
	levels := []string{"info", "warn", "error"}
	users := []string{"admin", "operator1", "operator2", "system"}

	var logs []model.SystemLog
	now := time.Now()
	for i := 0; i < 100; i++ {
		logTime := now.Add(-time.Duration(rand.Intn(7*24)) * time.Hour)
		level := levels[rand.Intn(len(levels))]
		if rand.Intn(10) > 2 {
			level = "info" // 大部分是info
		}
		logs = append(logs, model.SystemLog{
			Module:    modules[rand.Intn(len(modules))],
			Action:    actions[rand.Intn(len(actions))],
			Level:     level,
			Message:   fmt.Sprintf("用户执行了%s操作", actions[rand.Intn(len(actions))]),
			Username:  users[rand.Intn(len(users))],
			IP:        fmt.Sprintf("192.168.1.%d", rand.Intn(254)+1),
			CreatedAt: logTime,
		})
	}
	return db.Create(&logs).Error
}
