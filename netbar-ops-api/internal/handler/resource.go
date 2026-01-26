package handler

import (
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/middleware"
	"netbar-ops-api/internal/model"
)

// generateUniqueName 生成唯一的文件名，如果有重名则添加 (1), (2) 等后缀（不考虑netbar_id，向后兼容）
func generateUniqueName(name string, parentID *uint, zone string, excludeID uint) string {
	return generateUniqueNameWithNetbar(name, parentID, zone, 0, excludeID)
}

// generateUniqueNameWithNetbar 生成唯一的文件名，考虑netbar_id
func generateUniqueNameWithNetbar(name string, parentID *uint, zone string, netbarID uint, excludeID uint) string {
	baseName := name
	ext := ""

	// 分离文件名和扩展名
	if dotIndex := strings.LastIndex(name, "."); dotIndex > 0 {
		baseName = name[:dotIndex]
		ext = name[dotIndex:]
	}

	// 检查是否已存在同名文件
	query := database.MainDB.Model(&model.Resource{}).Where("zone = ?", zone).Where("netbar_id = ?", netbarID)
	if parentID != nil {
		query = query.Where("parent_id = ?", *parentID)
	} else {
		query = query.Where("parent_id IS NULL")
	}
	if excludeID > 0 {
		query = query.Where("id != ?", excludeID)
	}

	// 检查原始名称
	var count int64
	query.Where("name = ?", name).Count(&count)
	if count == 0 {
		return name
	}

	// 查找可用的后缀
	for i := 1; ; i++ {
		newName := fmt.Sprintf("%s (%d)%s", baseName, i, ext)
		var cnt int64
		q := database.MainDB.Model(&model.Resource{}).Where("zone = ?", zone).Where("netbar_id = ?", netbarID)
		if parentID != nil {
			q = q.Where("parent_id = ?", *parentID)
		} else {
			q = q.Where("parent_id IS NULL")
		}
		if excludeID > 0 {
			q = q.Where("id != ?", excludeID)
		}
		q.Where("name = ?", newName).Count(&cnt)
		if cnt == 0 {
			return newName
		}
	}
}

// generateUniqueNameForUpload 上传时生成唯一文件名
func generateUniqueNameForUpload(name string, parentID *uint, zone string) string {
	return generateUniqueName(name, parentID, zone, 0)
}

func GetResources(c *gin.Context) {
	var resources []model.Resource

	query := database.MainDB.Model(&model.Resource{})

	zone := c.Query("zone")
	netbarID := c.Query("netbar_id")

	// 调试日志
	println("GetResources - zone:", zone, "netbar_id:", netbarID)

	if zone != "" {
		query = query.Where("zone = ?", zone)
	}

	// netbar_id 过滤逻辑：
	// - 总部(HEADQUARTERS): netbar_id = 0
	// - 分公司(BRANCH): netbar_id = 分组ID
	// - 本网吧(PUBLIC): netbar_id = 网吧ID
	if netbarID != "" {
		if id64, err := strconv.ParseUint(netbarID, 10, 32); err == nil && id64 > 0 {
			if !middleware.RequireNetbarAccess(c, uint(id64)) {
				return
			}
		}
		query = query.Where("netbar_id = ?", netbarID)
	}

	// parent_id 过滤逻辑：
	// - 如果提供了 parent_id 参数，按该值过滤
	// - 如果没有提供或为空/null，默认返回根目录（parent_id IS NULL）
	parentID := c.Query("parent_id")
	if parentID == "" || parentID == "null" {
		query = query.Where("parent_id IS NULL")
	} else {
		query = query.Where("parent_id = ?", parentID)
	}

	if resType := c.Query("type"); resType != "" {
		query = query.Where("type = ?", resType)
	}

	// 排序：目录在前
	query = query.Order("is_directory DESC, name ASC")

	if err := query.Find(&resources).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, resources)
}

// SearchResources 搜索资源（递归搜索子目录）
func SearchResources(c *gin.Context) {
	keyword := c.Query("keyword")
	if keyword == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "搜索关键词不能为空"})
		return
	}

	zone := c.Query("zone")
	netbarID := c.Query("netbar_id")

	query := database.MainDB.Model(&model.Resource{})

	if zone != "" {
		query = query.Where("zone = ?", zone)
	}

	if netbarID != "" {
		if id64, err := strconv.ParseUint(netbarID, 10, 32); err == nil && id64 > 0 {
			if !middleware.RequireNetbarAccess(c, uint(id64)) {
				return
			}
		}
		query = query.Where("netbar_id = ?", netbarID)
	}

	// 搜索文件名（模糊匹配）
	query = query.Where("name LIKE ?", "%"+keyword+"%")

	// 排序：目录在前，然后按名称排序
	query = query.Order("is_directory DESC, name ASC")

	var resources []model.Resource
	if err := query.Find(&resources).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "搜索失败"})
		return
	}

	// 构建搜索结果，包含完整路径信息
	type SearchResult struct {
		ID          uint   `json:"id"`
		Name        string `json:"name"`
		Path        string `json:"path"`
		Size        int64  `json:"size"`
		Type        string `json:"type"`
		IsDirectory bool   `json:"is_directory"`
		Uploader    string `json:"uploader"`
		CreatedAt   string `json:"created_at"`
		UpdatedAt   string `json:"updated_at"`
		ParentID    *uint  `json:"parent_id"`
	}

	results := make([]SearchResult, 0, len(resources))
	for _, r := range resources {
		results = append(results, SearchResult{
			ID:          r.ID,
			Name:        r.Name,
			Path:        r.Path,
			Size:        r.Size,
			Type:        r.Type,
			IsDirectory: r.IsDirectory,
			Uploader:    r.Uploader,
			CreatedAt:   r.CreatedAt.Format("2006-01-02 15:04:05"),
			UpdatedAt:   r.UpdatedAt.Format("2006-01-02 15:04:05"),
			ParentID:    r.ParentID,
		})
	}

	c.JSON(http.StatusOK, results)
}

func GetResource(c *gin.Context) {
	id := c.Param("id")

	var resource model.Resource
	if err := database.MainDB.First(&resource, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "资源不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, resource.NetbarID) {
		return
	}

	c.JSON(http.StatusOK, resource)
}

// GetResourceContent 获取资源文件内容（原始内容）
func GetResourceContent(c *gin.Context) {
	id := c.Param("id")

	var resource model.Resource
	if err := database.MainDB.First(&resource, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "资源不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, resource.NetbarID) {
		return
	}

	if resource.IsDirectory {
		c.JSON(http.StatusBadRequest, gin.H{"error": "目录没有内容"})
		return
	}

	if resource.StoragePath == "" {
		c.JSON(http.StatusNotFound, gin.H{"error": "文件不存在"})
		return
	}

	content, err := os.ReadFile(resource.StoragePath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "读取文件失败"})
		return
	}

	// 直接返回原始内容
	c.Data(http.StatusOK, "text/plain; charset=utf-8", content)
}

type CreateResourceRequest struct {
	Name        string `json:"name" binding:"required"`
	ParentID    *uint  `json:"parent_id,omitempty"`
	IsDirectory bool   `json:"is_directory"`
	Type        string `json:"type"`
	Zone        string `json:"zone"`
	Content     string `json:"content,omitempty"`
	IsGlobal    bool   `json:"is_global"`
	NetbarID    uint   `json:"netbar_id"`
}

func CreateResource(c *gin.Context) {
	var req CreateResourceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}
	if !middleware.RequireNetbarAccess(c, req.NetbarID) {
		return
	}

	username, _ := c.Get("username")
	userID, _ := c.Get("user_id")

	zone := req.Zone
	if zone == "" {
		zone = "HEADQUARTERS"
	}

	// 生成唯一的文件名
	uniqueName := generateUniqueName(req.Name, req.ParentID, zone, 0)

	resource := model.Resource{
		Name:        uniqueName,
		ParentID:    req.ParentID,
		IsDirectory: req.IsDirectory,
		Type:        req.Type,
		Zone:        zone,
		Uploader:    username.(string),
		UploaderID:  userID.(uint),
		IsGlobal:    req.IsGlobal,
		Content:     req.Content,
		NetbarID:    req.NetbarID,
	}

	if resource.Type == "" && resource.IsDirectory {
		resource.Type = "folder"
	}

	// 构建路径
	if req.ParentID != nil {
		var parent model.Resource
		if err := database.MainDB.First(&parent, *req.ParentID).Error; err == nil {
			resource.Path = parent.Path + "/" + uniqueName
		}
	} else {
		resource.Path = uniqueName
	}

	if err := database.MainDB.Create(&resource).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败"})
		return
	}

	c.JSON(http.StatusCreated, resource)
}

func UpdateResource(c *gin.Context) {
	id := c.Param("id")

	var resource model.Resource
	if err := database.MainDB.First(&resource, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "资源不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, resource.NetbarID) {
		return
	}

	var updates map[string]any
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	// 如果有 content 字段，保存文件内容
	if content, ok := updates["content"].(string); ok {
		if resource.StoragePath != "" {
			if err := os.WriteFile(resource.StoragePath, []byte(content), 0644); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "保存文件内容失败"})
				return
			}
			// 更新文件大小
			updates["size"] = int64(len(content))
		}
		// 从数据库更新中移除 content 字段
		delete(updates, "content")
	}

	// 如果更新名称，需要检查是否重名
	if newName, ok := updates["name"].(string); ok && newName != "" && newName != resource.Name {
		uniqueName := generateUniqueName(newName, resource.ParentID, resource.Zone, resource.ID)
		updates["name"] = uniqueName
		// 同时更新路径
		if resource.ParentID != nil {
			var parent model.Resource
			if err := database.MainDB.First(&parent, *resource.ParentID).Error; err == nil {
				updates["path"] = parent.Path + "/" + uniqueName
			}
		} else {
			updates["path"] = uniqueName
		}
	}

	if len(updates) > 0 {
		if err := database.MainDB.Model(&resource).Updates(updates).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败"})
			return
		}
	}

	// 重新查询以获取更新后的完整数据
	database.MainDB.First(&resource, id)

	c.JSON(http.StatusOK, resource)
}

func DeleteResource(c *gin.Context) {
	id := c.Param("id")

	var resource model.Resource
	if err := database.MainDB.First(&resource, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "资源不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, resource.NetbarID) {
		return
	}
	// 如果是目录，需要删除所有子资源
	if resource.IsDirectory {
		database.MainDB.Where("parent_id = ?", id).Delete(&model.Resource{})
	}

	if err := database.MainDB.Delete(&resource).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

type CopyMoveRequest struct {
	TargetParentID *uint  `json:"target_parent_id"`
	NetbarID       *uint  `json:"netbar_id"`
	Zone           string `json:"zone"`
}

// copyResourceRecursive 递归拷贝资源（包括目录内的所有子资源）
func copyResourceRecursive(sourceID uint, targetParentID *uint, targetZone string, targetNetbarID uint, username string, userID uint) (*model.Resource, error) {
	var source model.Resource
	if err := database.MainDB.First(&source, sourceID).Error; err != nil {
		return nil, err
	}

	// 生成唯一的文件名
	uniqueName := generateUniqueNameWithNetbar(source.Name, targetParentID, targetZone, targetNetbarID, 0)

	// 构建新路径
	newPath := uniqueName
	if targetParentID != nil {
		var parent model.Resource
		if err := database.MainDB.First(&parent, *targetParentID).Error; err == nil {
			newPath = parent.Path + "/" + uniqueName
		}
	}

	// 创建副本
	newResource := model.Resource{
		Name:        uniqueName,
		Path:        newPath,
		ParentID:    targetParentID,
		IsDirectory: source.IsDirectory,
		Type:        source.Type,
		Size:        source.Size,
		Zone:        targetZone,
		NetbarID:    targetNetbarID,
		Uploader:    username,
		UploaderID:  userID,
		Hash:        source.Hash,
		IsGlobal:    source.IsGlobal,
		Content:     source.Content,
		StoragePath: source.StoragePath, // 共享同一个存储文件
	}

	if err := database.MainDB.Create(&newResource).Error; err != nil {
		return nil, err
	}

	// 如果是目录，递归拷贝所有子资源
	if source.IsDirectory {
		var children []model.Resource
		if err := database.MainDB.Where("parent_id = ?", sourceID).Find(&children).Error; err != nil {
			return &newResource, nil // 即使获取子资源失败，也返回已创建的目录
		}

		for _, child := range children {
			_, err := copyResourceRecursive(child.ID, &newResource.ID, targetZone, targetNetbarID, username, userID)
			if err != nil {
				// 记录错误但继续处理其他子资源
				continue
			}
		}
	}

	return &newResource, nil
}

// CopyResource 复制资源到目标目录
func CopyResource(c *gin.Context) {
	id := c.Param("id")

	var resource model.Resource
	if err := database.MainDB.First(&resource, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "资源不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, resource.NetbarID) {
		return
	}

	var req CopyMoveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	username, _ := c.Get("username")
	userID, _ := c.Get("user_id")

	// 使用请求中的zone，如果没有则使用源资源的zone
	targetZone := resource.Zone
	if req.Zone != "" {
		targetZone = req.Zone
	}

	// 使用请求中的netbar_id，如果没有则使用源资源的netbar_id
	targetNetbarID := resource.NetbarID
	if req.NetbarID != nil {
		targetNetbarID = *req.NetbarID
	}
	if !middleware.RequireNetbarAccess(c, targetNetbarID) {
		return
	}

	// 使用递归拷贝（支持目录）
	newResource, err := copyResourceRecursive(resource.ID, req.TargetParentID, targetZone, targetNetbarID, username.(string), userID.(uint))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "复制失败"})
		return
	}

	c.JSON(http.StatusCreated, newResource)
}

// MoveResource 移动资源到目标目录
func MoveResource(c *gin.Context) {
	id := c.Param("id")

	var resource model.Resource
	if err := database.MainDB.First(&resource, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "资源不存在"})
		return
	}
	if !middleware.RequireNetbarAccess(c, resource.NetbarID) {
		return
	}

	var req CopyMoveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
		return
	}

	// 构建新路径
	newPath := resource.Name
	if req.TargetParentID != nil {
		var parent model.Resource
		if err := database.MainDB.First(&parent, *req.TargetParentID).Error; err == nil {
			newPath = parent.Path + "/" + resource.Name
		}
	}

	// 更新资源
	updates := map[string]any{
		"parent_id": req.TargetParentID,
		"path":      newPath,
	}

	// 如果提供了zone，也更新zone
	if req.Zone != "" {
		updates["zone"] = req.Zone
	}

	// 如果提供了netbar_id，也更新netbar_id
	if req.NetbarID != nil {
		updates["netbar_id"] = *req.NetbarID
		if !middleware.RequireNetbarAccess(c, *req.NetbarID) {
			return
		}
	}

	if err := database.MainDB.Model(&resource).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "移动失败"})
		return
	}

	// 重新查询以获取更新后的完整数据
	database.MainDB.First(&resource, id)

	c.JSON(http.StatusOK, resource)
}
