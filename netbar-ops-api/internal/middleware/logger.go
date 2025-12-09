package middleware

import (
	"time"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

func SystemLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 处理请求
		c.Next()

		// 记录日志到日志数据库
		userID, _ := c.Get("user_id")
		username, _ := c.Get("username")

		uid, _ := userID.(uint)
		uname, _ := username.(string)

		log := model.SystemLog{
			Level:     getLogLevel(c.Writer.Status()),
			Module:    "api",
			Action:    c.Request.Method + " " + c.Request.URL.Path,
			Message:   "",
			UserID:    uid,
			Username:  uname,
			IP:        c.ClientIP(),
			UserAgent: c.Request.UserAgent(),
			CreatedAt: time.Now(),
		}

		// 异步写入日志
		go func() {
			database.LogsDB.Create(&log)
		}()
	}
}

func getLogLevel(status int) string {
	if status >= 500 {
		return "error"
	} else if status >= 400 {
		return "warn"
	}
	return "info"
}

