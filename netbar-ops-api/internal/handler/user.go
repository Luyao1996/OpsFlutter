package handler

import (
	"crypto/rand"
	"math/big"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/middleware"
	"netbar-ops-api/internal/model"
)

type CreateUserRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password"`
	Name     string `json:"name"`
	Role     string `json:"role"`
	Email    string `json:"email"`
	Phone    string `json:"phone"`
	GroupID  *uint  `json:"group_id"`
	// 可选：创建后自动加入某个网吧账号组（用于“新建用户并加入组”）
	NetbarID      *uint `json:"netbar_id,omitempty"`
	NetbarGroupID *uint `json:"netbar_group_id,omitempty"`
}

func GetUsers(c *gin.Context) {
	var users []model.User

	// 只查询启用状态的用户（status=1），软删除的用户不显示
	query := database.MainDB.Model(&model.User{}).Where("status = ?", 1)

	// 权限：
	// - 超级管理员：可查看所有用户
	// - 网吧管理员：admin：仅可查看（1）自己网吧下的成员；（2）未分组成员（无任何网吧组归属）
	if !middleware.IsSuperAdmin(c) {
		allowed := middleware.GetAllowedNetbarIDs(c)
		// left join to keep "unassigned" users (no netbar group)
		query = query.
			Joins("LEFT JOIN "+model.UserGroup{}.TableName()+" AS ug ON ug.user_id = users.id").
			Joins("LEFT JOIN "+model.Group{}.TableName()+" AS g ON g.id = ug.group_id AND g.netbar_id IS NOT NULL").
			Where("(g.netbar_id IN ? OR g.netbar_id IS NULL)", allowed).
			Group("users.id")
	}

	if search := c.Query("search"); search != "" {
		query = query.Where("username LIKE ? OR name LIKE ?", "%"+search+"%", "%"+search+"%")
	}

	if role := c.Query("role"); role != "" {
		query = query.Where("role = ?", role)
	}

	if err := query.Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	// 附加：每个用户所在的 netbar_ids（通过网吧账号组）
	userIDs := make([]uint, 0, len(users))
	for _, u := range users {
		userIDs = append(userIDs, u.ID)
	}
	type relRow struct {
		UserID   uint `gorm:"column:user_id"`
		NetbarID uint `gorm:"column:netbar_id"`
	}
	var rels []relRow
	if len(userIDs) > 0 {
		_ = database.MainDB.
			Table(model.UserGroup{}.TableName()+" AS ug").
			Select("ug.user_id, g.netbar_id").
			Joins("JOIN "+model.Group{}.TableName()+" AS g ON g.id = ug.group_id").
			Where("ug.user_id IN ?", userIDs).
			Where("g.netbar_id IS NOT NULL").
			Group("ug.user_id, g.netbar_id").
			Scan(&rels).Error
	}
	netbarIDsByUser := map[uint][]uint{}
	for _, r := range rels {
		if r.NetbarID == 0 {
			continue
		}
		netbarIDsByUser[r.UserID] = append(netbarIDsByUser[r.UserID], r.NetbarID)
	}

	// 非超级管理员不暴露其他网吧信息，仅保留与自己权限交集
	if !middleware.IsSuperAdmin(c) {
		allowed := middleware.GetAllowedNetbarIDs(c)
		allowedSet := map[uint]bool{}
		for _, id := range allowed {
			allowedSet[id] = true
		}
		for uid, ids := range netbarIDsByUser {
			filtered := make([]uint, 0, len(ids))
			for _, id := range ids {
				if allowedSet[id] {
					filtered = append(filtered, id)
				}
			}
			netbarIDsByUser[uid] = filtered
		}
	}

	out := make([]gin.H, 0, len(users))
	for _, u := range users {
		out = append(out, gin.H{
			"id":           u.ID,
			"username":     u.Username,
			"name":         u.Name,
			"role":         u.Role,
			"email":        u.Email,
			"phone":        u.Phone,
			"group_id":     u.GroupID,
			"status":       u.Status,
			"is_2fa_bound": u.Is2FABound,
			"created_at":   u.CreatedAt,
			"updated_at":   u.UpdatedAt,
			"netbar_ids":   netbarIDsByUser[u.ID],
		})
	}

	c.JSON(http.StatusOK, out)
}

func GetUser(c *gin.Context) {
	id := c.Param("id")

	var user model.User
	if err := database.MainDB.First(&user, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}
	if !middleware.IsSuperAdmin(c) {
		if ok, err := canManageUser(c, user.ID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
			return
		} else if !ok {
			c.JSON(http.StatusForbidden, gin.H{"error": "无权限访问该用户"})
			return
		}
	}

	c.JSON(http.StatusOK, user)
}

func CreateUser(c *gin.Context) {
	var req CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	if req.Password != "" && len(req.Password) < 6 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "密码长度至少 6 位"})
		return
	}
	passwordPlain := req.Password
	if passwordPlain == "" {
		passwordPlain = generateRandomPassword(12)
	}

	// 加密密码
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(passwordPlain), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "密码加密失败"})
		return
	}

	user := model.User{
		Username: req.Username,
		Password: string(hashedPassword),
		Name:     req.Name,
		Role:     req.Role,
		Email:    req.Email,
		Phone:    req.Phone,
		GroupID:  req.GroupID,
		Status:   1,
	}

	if err := database.MainDB.Create(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}

	// 可选：加入网吧账号组
	if req.NetbarID != nil && req.NetbarGroupID != nil && *req.NetbarID > 0 && *req.NetbarGroupID > 0 {
		if !middleware.RequireNetbarAccess(c, *req.NetbarID) {
			return
		}
		var group model.Group
		if err := database.MainDB.First(&group, *req.NetbarGroupID).Error; err == nil {
			if group.NetbarID != nil && *group.NetbarID == *req.NetbarID {
				rel := model.UserGroup{UserID: user.ID, GroupID: group.ID}
				_ = database.MainDB.Where("user_id = ? AND group_id = ?", user.ID, group.ID).FirstOrCreate(&rel).Error
			}
		}
	}

	c.JSON(http.StatusCreated, gin.H{
		"user":             user,
		"initial_password": passwordPlain,
	})
}

func UpdateUser(c *gin.Context) {
	id := c.Param("id")

	var user model.User
	if err := database.MainDB.First(&user, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}
	if !middleware.IsSuperAdmin(c) {
		if ok, err := canManageUser(c, user.ID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
			return
		} else if !ok {
			c.JSON(http.StatusForbidden, gin.H{"error": "无权限管理该用户"})
			return
		}
	}

	var updates map[string]interface{}
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	// 密码请使用 reset-password 接口
	delete(updates, "password")

	// 角色限制：网吧管理员不可设置 super_admin
	if v, ok := updates["role"].(string); ok && v != "" {
		if v != "user" && v != "admin" && v != "super_admin" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "无效的角色"})
			return
		}
		if v == "super_admin" && !middleware.IsSuperAdmin(c) {
			c.JSON(http.StatusForbidden, gin.H{"error": "无权限设置超级管理员"})
			return
		}
	}

	if err := database.MainDB.Model(&user).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// ResetUserPassword resets user's password to a random one and returns it once.
func ResetUserPassword(c *gin.Context) {
	id64, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil || id64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的用户ID"})
		return
	}
	id := uint(id64)

	var user model.User
	if err := database.MainDB.First(&user, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}
	if !middleware.IsSuperAdmin(c) {
		if ok, err := canManageUser(c, user.ID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
			return
		} else if !ok {
			c.JSON(http.StatusForbidden, gin.H{"error": "无权限管理该用户"})
			return
		}
	}

	newPassword := generateRandomPassword(12)
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "密码加密失败"})
		return
	}

	if err := database.MainDB.Model(&user).Update("password", string(hashedPassword)).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "重置失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"new_password": newPassword})
}

func DeleteUser(c *gin.Context) {
	id := c.Param("id")

	if err := database.MainDB.Delete(&model.User{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

func generateRandomPassword(length int) string {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#%*"
	if length <= 0 {
		return "ChangeMe123!"
	}
	out := make([]byte, length)
	for i := 0; i < length; i++ {
		nBig, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			// fallback (shouldn't happen)
			out[i] = alphabet[i%len(alphabet)]
			continue
		}
		out[i] = alphabet[nBig.Int64()]
	}
	return string(out)
}

// canManageUser checks if current requester (non-super admin) can manage the user:
// - user belongs to at least one allowed netbar, OR
// - user has no netbar-scoped groups at all (unassigned member)
func canManageUser(c *gin.Context, userID uint) (bool, error) {
	allowed := middleware.GetAllowedNetbarIDs(c)
	if len(allowed) == 0 {
		// can only manage unassigned users
	}

	var cnt int64
	err := database.MainDB.
		Table(model.UserGroup{}.TableName()+" AS ug").
		Joins("JOIN "+model.Group{}.TableName()+" AS g ON g.id = ug.group_id").
		Where("ug.user_id = ?", userID).
		Where("g.netbar_id IS NOT NULL").
		Count(&cnt).Error
	if err != nil {
		return false, err
	}
	if cnt == 0 {
		// no netbar memberships => unassigned
		return true, nil
	}

	var allowedCnt int64
	err = database.MainDB.
		Table(model.UserGroup{}.TableName()+" AS ug").
		Joins("JOIN "+model.Group{}.TableName()+" AS g ON g.id = ug.group_id").
		Where("ug.user_id = ?", userID).
		Where("g.netbar_id IN ?", allowed).
		Count(&allowedCnt).Error
	if err != nil {
		return false, err
	}
	return allowedCnt > 0, nil
}
