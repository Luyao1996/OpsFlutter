package handler

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/middleware"
	"netbar-ops-api/internal/model"
)

type createNetbarUserGroupRequest struct {
	Name     string `json:"name" binding:"required"`
	ParentID *uint  `json:"parent_id,omitempty"`
}

func GetNetbarUserGroups(c *gin.Context) {
	netbarID64, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil || netbarID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的网吧ID"})
		return
	}
	netbarID := uint(netbarID64)
	if !middleware.RequireNetbarAccess(c, netbarID) {
		return
	}

	var groups []model.Group
	query := database.MainDB.Model(&model.Group{}).Where("netbar_id = ?", netbarID)

	if search := c.Query("search"); search != "" {
		query = query.Where("name LIKE ?", "%"+search+"%")
	}

	if err := query.Order("id ASC").Find(&groups).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, groups)
}

func CreateNetbarUserGroup(c *gin.Context) {
	netbarID64, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil || netbarID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的网吧ID"})
		return
	}
	netbarID := uint(netbarID64)
	if !middleware.RequireNetbarAccess(c, netbarID) {
		return
	}

	var req createNetbarUserGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	group := model.Group{
		NetbarID:  &netbarID,
		Name:      req.Name,
		ParentID:  req.ParentID,
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}

	if err := database.MainDB.Create(&group).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}

	c.JSON(http.StatusCreated, group)
}

func UpdateNetbarUserGroup(c *gin.Context) {
	netbarID64, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil || netbarID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的网吧ID"})
		return
	}
	netbarID := uint(netbarID64)
	if !middleware.RequireNetbarAccess(c, netbarID) {
		return
	}

	groupID64, err := strconv.ParseUint(c.Param("group_id"), 10, 32)
	if err != nil || groupID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的分组ID"})
		return
	}
	groupID := uint(groupID64)

	var group model.Group
	if err := database.MainDB.First(&group, groupID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "分组不存在"})
		return
	}
	if group.NetbarID == nil || *group.NetbarID != netbarID {
		c.JSON(http.StatusForbidden, gin.H{"error": "无权限操作该分组"})
		return
	}

	var updates map[string]interface{}
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}
	delete(updates, "id")
	delete(updates, "netbar_id")

	if err := database.MainDB.Model(&group).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
		return
	}

	c.JSON(http.StatusOK, group)
}

func DeleteNetbarUserGroup(c *gin.Context) {
	netbarID64, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil || netbarID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的网吧ID"})
		return
	}
	netbarID := uint(netbarID64)
	if !middleware.RequireNetbarAccess(c, netbarID) {
		return
	}

	groupID64, err := strconv.ParseUint(c.Param("group_id"), 10, 32)
	if err != nil || groupID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的分组ID"})
		return
	}
	groupID := uint(groupID64)

	var group model.Group
	if err := database.MainDB.First(&group, groupID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "分组不存在"})
		return
	}
	if group.NetbarID == nil || *group.NetbarID != netbarID {
		c.JSON(http.StatusForbidden, gin.H{"error": "无权限操作该分组"})
		return
	}

	// 删除分组及成员关系（事务）
	if err := database.MainDB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("group_id = ?", groupID).Delete(&model.UserGroup{}).Error; err != nil {
			return err
		}
		if err := tx.Delete(&model.Group{}, groupID).Error; err != nil {
			return err
		}
		return nil
	}); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// ---- Members ----

type addUserToGroupRequest struct {
	UserID uint `json:"user_id" binding:"required"`
}

func GetNetbarGroupUsers(c *gin.Context) {
	netbarID64, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil || netbarID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的网吧ID"})
		return
	}
	netbarID := uint(netbarID64)
	if !middleware.RequireNetbarAccess(c, netbarID) {
		return
	}

	groupID64, err := strconv.ParseUint(c.Param("group_id"), 10, 32)
	if err != nil || groupID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的分组ID"})
		return
	}
	groupID := uint(groupID64)

	var group model.Group
	if err := database.MainDB.First(&group, groupID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "分组不存在"})
		return
	}
	if group.NetbarID == nil || *group.NetbarID != netbarID {
		c.JSON(http.StatusForbidden, gin.H{"error": "无权限访问该分组"})
		return
	}

	type row struct {
		User model.User `gorm:"embedded"`
	}
	var users []model.User
	err = database.MainDB.
		Table(model.User{}.TableName()+" AS u").
		Select("u.*").
		Joins("JOIN "+model.UserGroup{}.TableName()+" AS ug ON ug.user_id = u.id").
		Where("ug.group_id = ?", groupID).
		Where("u.status = 1").
		Order("u.id ASC").
		Scan(&users).Error
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, users)
}

func AddUserToNetbarGroup(c *gin.Context) {
	netbarID64, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil || netbarID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的网吧ID"})
		return
	}
	netbarID := uint(netbarID64)
	if !middleware.RequireNetbarAccess(c, netbarID) {
		return
	}

	groupID64, err := strconv.ParseUint(c.Param("group_id"), 10, 32)
	if err != nil || groupID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的分组ID"})
		return
	}
	groupID := uint(groupID64)

	var group model.Group
	if err := database.MainDB.First(&group, groupID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "分组不存在"})
		return
	}
	if group.NetbarID == nil || *group.NetbarID != netbarID {
		c.JSON(http.StatusForbidden, gin.H{"error": "无权限操作该分组"})
		return
	}

	var req addUserToGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.UserID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	var user model.User
	if err := database.MainDB.First(&user, req.UserID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}
	if user.Status != 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "用户已被禁用"})
		return
	}

	rel := model.UserGroup{
		UserID:  user.ID,
		GroupID: groupID,
	}
	if err := database.MainDB.Where("user_id = ? AND group_id = ?", user.ID, groupID).FirstOrCreate(&rel).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "加入失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "加入成功"})
}

func RemoveUserFromNetbarGroup(c *gin.Context) {
	netbarID64, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil || netbarID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的网吧ID"})
		return
	}
	netbarID := uint(netbarID64)
	if !middleware.RequireNetbarAccess(c, netbarID) {
		return
	}

	groupID64, err := strconv.ParseUint(c.Param("group_id"), 10, 32)
	if err != nil || groupID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的分组ID"})
		return
	}
	groupID := uint(groupID64)

	userID64, err := strconv.ParseUint(c.Param("user_id"), 10, 32)
	if err != nil || userID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的用户ID"})
		return
	}
	userID := uint(userID64)

	var group model.Group
	if err := database.MainDB.First(&group, groupID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "分组不存在"})
		return
	}
	if group.NetbarID == nil || *group.NetbarID != netbarID {
		c.JSON(http.StatusForbidden, gin.H{"error": "无权限操作该分组"})
		return
	}

	if err := database.MainDB.Where("user_id = ? AND group_id = ?", userID, groupID).Delete(&model.UserGroup{}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "移除失败"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "移除成功"})
}

// GetNetbarUsers lists all enabled users that already belong to at least one group under the given netbar.
func GetNetbarUsers(c *gin.Context) {
	netbarID64, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil || netbarID64 == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的网吧ID"})
		return
	}
	netbarID := uint(netbarID64)
	if !middleware.RequireNetbarAccess(c, netbarID) {
		return
	}

	// Query distinct users within this netbar.
	type userRow struct {
		ID       uint   `json:"id"`
		Username string `json:"username"`
		Name     string `json:"name"`
		Role     string `json:"role"`
		Email    string `json:"email"`
		Phone    string `json:"phone"`
		Status   int    `json:"status"`
	}
	var users []userRow
	q := database.MainDB.
		Table(model.User{}.TableName()+" AS u").
		Select("DISTINCT u.id, u.username, u.name, u.role, u.email, u.phone, u.status").
		Joins("JOIN "+model.UserGroup{}.TableName()+" AS ug ON ug.user_id = u.id").
		Joins("JOIN "+model.Group{}.TableName()+" AS g ON g.id = ug.group_id").
		Where("g.netbar_id = ?", netbarID).
		Where("u.status = 1")

	if search := c.Query("search"); search != "" {
		q = q.Where("u.username LIKE ? OR u.name LIKE ? OR u.phone LIKE ?", "%"+search+"%", "%"+search+"%", "%"+search+"%")
	}

	if err := q.Order("u.id ASC").Scan(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	// Build group_ids per user within this netbar.
	type relRow struct {
		UserID  uint `gorm:"column:user_id"`
		GroupID uint `gorm:"column:group_id"`
	}
	var rels []relRow
	relQ := database.MainDB.
		Table(model.UserGroup{}.TableName()+" AS ug").
		Select("ug.user_id, ug.group_id").
		Joins("JOIN "+model.Group{}.TableName()+" AS g ON g.id = ug.group_id").
		Where("g.netbar_id = ?", netbarID)
	if err := relQ.Scan(&rels).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	userGroups := map[uint][]uint{}
	for _, r := range rels {
		userGroups[r.UserID] = append(userGroups[r.UserID], r.GroupID)
	}

	out := make([]gin.H, 0, len(users))
	for _, u := range users {
		out = append(out, gin.H{
			"id":        u.ID,
			"username":  u.Username,
			"name":      u.Name,
			"role":      u.Role,
			"email":     u.Email,
			"phone":     u.Phone,
			"status":    u.Status,
			"group_ids": userGroups[u.ID],
		})
	}
	c.JSON(http.StatusOK, out)
}
