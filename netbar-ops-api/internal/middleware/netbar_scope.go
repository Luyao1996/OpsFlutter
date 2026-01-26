package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

const ctxAllowedNetbarIDsKey = "allowed_netbar_ids"

// NetbarScope loads the netbar access scope for the current user and stores it in context.
// Strategy B: non-admin users can only access netbars where they belong to at least one netbar-scoped group.
func NetbarScope() gin.HandlerFunc {
	return func(c *gin.Context) {
		if IsSuperAdmin(c) {
			c.Next()
			return
		}

		userIDAny, ok := c.Get("user_id")
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "未登录"})
			c.Abort()
			return
		}

		userID, ok := userIDAny.(uint)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "未登录"})
			c.Abort()
			return
		}

		type row struct {
			NetbarID uint `gorm:"column:netbar_id"`
		}
		var rows []row

		// Only groups bound to a netbar contribute to access.
		err := database.MainDB.
			Table(model.UserGroup{}.TableName()+" AS ug").
			Select("g.netbar_id AS netbar_id").
			Joins("JOIN "+model.Group{}.TableName()+" AS g ON g.id = ug.group_id").
			Where("ug.user_id = ?", userID).
			Where("g.netbar_id IS NOT NULL").
			Group("g.netbar_id").
			Scan(&rows).Error
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "加载网吧权限失败"})
			c.Abort()
			return
		}

		allowed := make([]uint, 0, len(rows))
		for _, r := range rows {
			if r.NetbarID > 0 {
				allowed = append(allowed, r.NetbarID)
			}
		}
		c.Set(ctxAllowedNetbarIDsKey, allowed)
		c.Next()
	}
}

func GetAllowedNetbarIDs(c *gin.Context) []uint {
	if IsSuperAdmin(c) {
		return nil
	}
	v, ok := c.Get(ctxAllowedNetbarIDsKey)
	if !ok {
		return []uint{}
	}
	ids, ok := v.([]uint)
	if !ok {
		return []uint{}
	}
	return ids
}

func HasNetbarAccess(c *gin.Context, netbarID uint) bool {
	if netbarID == 0 {
		// HQ/global resources
		return true
	}
	if IsSuperAdmin(c) {
		return true
	}
	allowed := GetAllowedNetbarIDs(c)
	for _, id := range allowed {
		if id == netbarID {
			return true
		}
	}
	return false
}

func RequireNetbarAccess(c *gin.Context, netbarID uint) bool {
	if HasNetbarAccess(c, netbarID) {
		return true
	}
	c.JSON(http.StatusForbidden, gin.H{"error": "无权限访问该网吧"})
	c.Abort()
	return false
}
