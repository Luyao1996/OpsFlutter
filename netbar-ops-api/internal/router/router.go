package router

import (
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/handler"
	"netbar-ops-api/internal/middleware"
)

func Setup(mode string) *gin.Engine {
	gin.SetMode(mode)
	r := gin.Default()

	// CORS 配置
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
	}))

	// 健康检查
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	// API v1
	v1 := r.Group("/api/v1")
	{
		// 公开路由
		v1.POST("/auth/login", handler.Login)
		v1.POST("/auth/qr/create", handler.CreateQRSession)
		v1.GET("/auth/qr/status/:session_id", handler.CheckQRStatus)

		// 需要认证的路由
		auth := v1.Group("")
		auth.Use(middleware.JWTAuth())
		auth.Use(middleware.SystemLogger())
		{
			// 认证相关
			auth.GET("/auth/me", handler.GetCurrentUser)
			auth.POST("/auth/logout", handler.Logout)
			auth.POST("/auth/qr/scan/:session_id", handler.ScanQRCode)
			auth.POST("/auth/qr/confirm/:session_id", handler.ConfirmQRLogin)

			// 仪表盘
			auth.GET("/dashboard", handler.GetDashboard)
			auth.GET("/dashboard/trend", handler.GetTrendData)
			auth.POST("/dashboard/restart-all", handler.RestartAllServices)
			auth.POST("/dashboard/network-diagnose", handler.NetworkDiagnose)

			// 开发工具 - 生成测试数据 (需要认证，仅管理员可用)
			auth.POST("/seed", handler.RunSeed)

			// 网吧管理
			auth.GET("/netbars", handler.GetNetbars)
			auth.GET("/netbars/:id", handler.GetNetbar)
			auth.POST("/netbars", handler.CreateNetbar)
			auth.PUT("/netbars/:id", handler.UpdateNetbar)
			auth.DELETE("/netbars/:id", handler.DeleteNetbar)

			// 通道管理
			auth.GET("/channels", handler.GetChannels)
			auth.GET("/channels/:id", handler.GetChannel)
			auth.POST("/channels", handler.CreateChannel)
			auth.PUT("/channels/:id", handler.UpdateChannel)
			auth.DELETE("/channels/:id", handler.DeleteChannel)

			// 桌面管理
			auth.GET("/desktops", handler.GetDesktops)
			auth.GET("/desktops/:id", handler.GetDesktop)
			auth.POST("/desktops", handler.CreateDesktop)
			auth.PUT("/desktops/:id", handler.UpdateDesktop)
			auth.DELETE("/desktops/:id", handler.DeleteDesktop)

			// 桌面布局配置
			auth.GET("/desktop-layouts", handler.GetDesktopLayouts)
			auth.GET("/desktop-layouts/:id", handler.GetDesktopLayout)
			auth.POST("/desktop-layouts", handler.CreateDesktopLayout)
			auth.PUT("/desktop-layouts/:id", handler.UpdateDesktopLayout)
			auth.DELETE("/desktop-layouts/:id", handler.DeleteDesktopLayout)

			// 用户管理 (需要管理员权限)
			users := auth.Group("/users")
			users.Use(middleware.AdminOnly())
			{
				users.GET("", handler.GetUsers)
				users.GET("/:id", handler.GetUser)
				users.POST("", handler.CreateUser)
				users.PUT("/:id", handler.UpdateUser)
				users.DELETE("/:id", handler.DeleteUser)
			}

			// 系统日志
			auth.GET("/logs", handler.GetSystemLogs)
			auth.GET("/logs/:id", handler.GetSystemLog)

			// 实时监控
			auth.GET("/monitor", handler.GetMonitorStats)

			// 数据导出
			auth.GET("/export/netbars", handler.ExportNetbars)
			auth.GET("/export/channels", handler.ExportChannels)
			auth.GET("/export/desktops", handler.ExportDesktops)
			auth.GET("/export/logs", handler.ExportLogs)

			// 终端管理
			auth.GET("/terminals", handler.GetTerminals)
			auth.GET("/terminals/:id", handler.GetTerminal)
			auth.POST("/terminals", handler.CreateTerminal)
			auth.PUT("/terminals/:id", handler.UpdateTerminal)
			auth.DELETE("/terminals/:id", handler.DeleteTerminal)
			auth.POST("/terminals/:id/remote", handler.TerminalRemote)
			auth.GET("/terminals/:id/heartbeat", handler.GetTerminalHeartbeat)

			// 资源管理
			auth.GET("/resources", handler.GetResources)
			auth.GET("/resources/search", handler.SearchResources)
			auth.GET("/resources/:id", handler.GetResource)
			auth.GET("/resources/:id/content", handler.GetResourceContent)
			auth.POST("/resources", handler.CreateResource)
			auth.PUT("/resources/:id", handler.UpdateResource)
			auth.DELETE("/resources/:id", handler.DeleteResource)
			auth.POST("/resources/upload", handler.UploadFile)
			auth.POST("/resources/upload-image", handler.UploadDesktopImage)
			auth.GET("/resources/:id/download", handler.DownloadFile)
			auth.GET("/resources/:id/download-dir", handler.DownloadDirectory)
			auth.POST("/resources/:id/copy", handler.CopyResource)
			auth.PUT("/resources/:id/move", handler.MoveResource)

			// 启动项管理
			auth.GET("/startup-items", handler.GetStartupItems)
			auth.GET("/startup-items/:id", handler.GetStartupItem)
			auth.POST("/startup-items", handler.CreateStartupItem)
			auth.PUT("/startup-items/:id", handler.UpdateStartupItem)
			auth.DELETE("/startup-items/:id", handler.DeleteStartupItem)
			auth.GET("/startup-items/monitor", handler.GetStartupItemMonitor)

			// 用户组管理
			auth.GET("/groups", handler.GetGroups)
			auth.GET("/groups/:id", handler.GetGroup)
			auth.POST("/groups", handler.CreateGroup)
			auth.PUT("/groups/:id", handler.UpdateGroup)
			auth.DELETE("/groups/:id", handler.DeleteGroup)

			// 网吧分组管理
			auth.GET("/netbar-groups", handler.GetNetbarGroups)
			auth.POST("/netbar-groups", handler.CreateNetbarGroup)
			auth.PUT("/netbar-groups/:id", handler.UpdateNetbarGroup)
			auth.DELETE("/netbar-groups/:id", handler.DeleteNetbarGroup)

			// 网吧区域管理
			auth.GET("/areas", handler.GetAllAreas)
			auth.GET("/areas/netbar/:netbar_id", handler.GetNetbarAreas)
			auth.POST("/areas/netbar/:netbar_id", handler.CreateNetbarArea)
			auth.PUT("/areas/:id", handler.UpdateNetbarArea)
			auth.DELETE("/areas/:id", handler.DeleteNetbarArea)
		}
	}

	return r
}
