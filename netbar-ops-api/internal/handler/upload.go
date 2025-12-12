package handler

import (
	"archive/zip"
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

const uploadDir = "./uploads"
const uploadImageDir = "./uploads/images"

func init() {
	// 确保上传目录存在
	os.MkdirAll(uploadDir, 0755)
	// 桌面壁纸/应用图标等静态资源的默认存储目录。
	// TODO: 后续可能拆到独立存储服务或 CDN。
	os.MkdirAll(uploadImageDir, 0755)
}

// ensureDirectoryExists 确保目录路径存在，如果不存在则创建
// 返回最终的父目录ID
func ensureDirectoryExists(dirPath string, parentID *uint, zone string, username string, userID uint, netbarID uint) (*uint, error) {
	if dirPath == "" {
		return parentID, nil
	}

	// 统一路径分隔符（Windows 使用 \，需要转换为 /）
	normalizedPath := strings.ReplaceAll(dirPath, "\\", "/")

	// 分割路径
	parts := strings.Split(normalizedPath, "/")
	currentParentID := parentID

	for _, part := range parts {
		if part == "" {
			continue
		}

		// 检查目录是否已存在
		var existingDir model.Resource
		query := database.MainDB.Where("name = ? AND zone = ? AND is_directory = ?", part, zone, true)
		if currentParentID != nil {
			query = query.Where("parent_id = ?", *currentParentID)
		} else {
			query = query.Where("parent_id IS NULL")
		}
		// 加上 netbar_id 过滤
		if netbarID > 0 {
			query = query.Where("netbar_id = ?", netbarID)
		}

		if err := query.First(&existingDir).Error; err == nil {
			// 目录已存在
			currentParentID = &existingDir.ID
		} else {
			// 创建目录
			var dirPathStr string
			if currentParentID != nil {
				var parent model.Resource
				if err := database.MainDB.First(&parent, *currentParentID).Error; err == nil {
					dirPathStr = parent.Path + "/" + part
				}
			} else {
				dirPathStr = part
			}

			newDir := model.Resource{
				Name:        part,
				Path:        dirPathStr,
				ParentID:    currentParentID,
				NetbarID:    netbarID,
				IsDirectory: true,
				Type:        "folder",
				Zone:        zone,
				Uploader:    username,
				UploaderID:  userID,
				IsGlobal:    true,
			}

			if err := database.MainDB.Create(&newDir).Error; err != nil {
				return nil, err
			}
			currentParentID = &newDir.ID
		}
	}

	return currentParentID, nil
}

// UploadFile 上传文件
func UploadFile(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请选择文件"})
		return
	}

	zone := c.PostForm("zone")
	if zone == "" {
		zone = "HEADQUARTERS"
	}

	parentIDStr := c.PostForm("parent_id")
	var parentID *uint
	if parentIDStr != "" && parentIDStr != "null" {
		id, _ := strconv.ParseUint(parentIDStr, 10, 32)
		pid := uint(id)
		parentID = &pid
	}

	// 获取网吧ID
	netbarIDStr := c.PostForm("netbar_id")
	var netbarID uint
	if netbarIDStr != "" && netbarIDStr != "null" {
		id, _ := strconv.ParseUint(netbarIDStr, 10, 32)
		netbarID = uint(id)
	}

	// 获取相对路径（用于目录上传）
	relativePath := c.PostForm("relative_path")
	// 统一路径分隔符
	relativePath = strings.ReplaceAll(relativePath, "\\", "/")

	// 获取是否需要解压ZIP
	extractZip := c.PostForm("extract_zip") == "true"

	username, _ := c.Get("username")
	userID, _ := c.Get("user_id")

	// 如果有相对路径，解析目录结构并创建
	fileName := file.Filename
	if relativePath != "" {
		// 分离目录和文件名（使用 / 分隔符）
		lastSlash := strings.LastIndex(relativePath, "/")
		var dir string
		if lastSlash >= 0 {
			dir = relativePath[:lastSlash]
			fileName = relativePath[lastSlash+1:]
		} else {
			dir = ""
			fileName = relativePath
		}

		if dir != "" {
			// 创建中间目录
			newParentID, err := ensureDirectoryExists(dir, parentID, zone, username.(string), userID.(uint), netbarID)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "创建目录失败: " + err.Error()})
				return
			}
			parentID = newParentID
		}
	}

	// 生成唯一文件名（存储用）
	ext := filepath.Ext(fileName)
	timestamp := time.Now().UnixNano()
	savedName := fmt.Sprintf("%d%s", timestamp, ext)
	savePath := filepath.Join(uploadDir, savedName)

	// 保存文件
	if err := c.SaveUploadedFile(file, savePath); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "保存文件失败"})
		return
	}

	// 检查是否需要解压ZIP文件
	if extractZip && isZipFile(fileName) {
		resources, err := extractZipFile(savePath, parentID, zone, netbarID, username.(string), userID.(uint))
		if err != nil {
			os.Remove(savePath)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "解压文件失败: " + err.Error()})
			return
		}
		// 删除原始zip文件
		os.Remove(savePath)
		c.JSON(http.StatusCreated, gin.H{
			"message":   "解压成功",
			"count":     len(resources),
			"resources": resources,
		})
		return
	}

	// 计算MD5
	f, _ := os.Open(savePath)
	defer f.Close()
	hash := md5.New()
	io.Copy(hash, f)
	md5Hash := hex.EncodeToString(hash.Sum(nil))

	// 判断文件类型
	fileType := getFileType(fileName)

	// 生成唯一的文件名（防重名）
	uniqueName := generateUniqueNameForUpload(fileName, parentID, zone)

	// 构建路径
	var resourcePath string
	if parentID != nil {
		var parent model.Resource
		if err := database.MainDB.First(&parent, *parentID).Error; err == nil {
			resourcePath = parent.Path + "/" + uniqueName
		}
	} else {
		resourcePath = uniqueName
	}

	// 对于文本类型文件，读取内容保存到数据库
	var content string
	if isTextFileType(fileType) {
		contentBytes, err := os.ReadFile(savePath)
		if err == nil {
			content = string(contentBytes)
		}
	}

	resource := model.Resource{
		Name:        uniqueName,
		Path:        resourcePath,
		StoragePath: savePath,
		ParentID:    parentID,
		NetbarID:    netbarID,
		IsDirectory: false,
		Type:        fileType,
		Size:        file.Size,
		Zone:        zone,
		Uploader:    username.(string),
		UploaderID:  userID.(uint),
		Hash:        md5Hash,
		IsGlobal:    true,
		Content:     content,
	}

	if err := database.MainDB.Create(&resource).Error; err != nil {
		os.Remove(savePath) // 删除已保存的文件
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建资源记录失败"})
		return
	}

	c.JSON(http.StatusCreated, resource)
}

// UploadDesktopImage 上传桌面壁纸/应用图标等图片到 uploads/images 目录。
// 逻辑与 UploadFile 基本一致，只是强制落盘到 images 子目录，便于后续独立拆分。
func UploadDesktopImage(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请选择文件"})
		return
	}

	zone := c.PostForm("zone")
	if zone == "" {
		zone = "HEADQUARTERS"
	}

	parentIDStr := c.PostForm("parent_id")
	var parentID *uint
	if parentIDStr != "" && parentIDStr != "null" {
		if id, convErr := strconv.ParseUint(parentIDStr, 10, 32); convErr == nil {
			pid := uint(id)
			parentID = &pid
		}
	}

	netbarIDStr := c.PostForm("netbar_id")
	var netbarID uint
	if netbarIDStr != "" && netbarIDStr != "null" {
		if id, convErr := strconv.ParseUint(netbarIDStr, 10, 32); convErr == nil {
			netbarID = uint(id)
		}
	}

	username, _ := c.Get("username")
	userID, _ := c.Get("user_id")

	fileName := file.Filename

	ext := filepath.Ext(fileName)
	timestamp := time.Now().UnixNano()
	savedName := fmt.Sprintf("%d%s", timestamp, ext)
	savePath := filepath.Join(uploadImageDir, savedName)

	if err := c.SaveUploadedFile(file, savePath); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "保存文件失败"})
		return
	}

	f, _ := os.Open(savePath)
	hash := md5.New()
	io.Copy(hash, f)
	f.Close()
	md5Hash := hex.EncodeToString(hash.Sum(nil))

	fileType := getFileType(fileName)

	uniqueName := generateUniqueNameForUpload(fileName, parentID, zone)

	var resourcePath string
	if parentID != nil {
		var parent model.Resource
		if err := database.MainDB.First(&parent, *parentID).Error; err == nil {
			resourcePath = parent.Path + "/" + uniqueName
		}
	} else {
		resourcePath = uniqueName
	}

	resource := model.Resource{
		Name:        uniqueName,
		Path:        resourcePath,
		StoragePath: savePath,
		ParentID:    parentID,
		NetbarID:    netbarID,
		IsDirectory: false,
		Type:        fileType,
		Size:        file.Size,
		Zone:        zone,
		Uploader:    username.(string),
		UploaderID:  userID.(uint),
		Hash:        md5Hash,
		IsGlobal:    true,
	}

	if err := database.MainDB.Create(&resource).Error; err != nil {
		os.Remove(savePath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建资源记录失败"})
		return
	}

	c.JSON(http.StatusCreated, resource)
}

// isZipFile 检查文件是否为ZIP文件
func isZipFile(filename string) bool {
	ext := strings.ToLower(filepath.Ext(filename))
	return ext == ".zip"
}

// extractZipFile 解压ZIP文件到指定目录
func extractZipFile(zipPath string, parentID *uint, zone string, netbarID uint, username string, userID uint) ([]model.Resource, error) {
	reader, err := zip.OpenReader(zipPath)
	if err != nil {
		return nil, fmt.Errorf("打开ZIP文件失败: %v", err)
	}
	defer reader.Close()

	var resources []model.Resource
	dirCache := make(map[string]*uint) // 缓存已创建的目录

	for _, file := range reader.File {
		// 处理文件路径
		filePath := strings.ReplaceAll(file.Name, "\\", "/")
		// 跳过隐藏文件和特殊文件
		if strings.HasPrefix(filepath.Base(filePath), ".") || strings.HasPrefix(filePath, "__MACOSX") {
			continue
		}

		if file.FileInfo().IsDir() {
			// 创建目录
			_, err := ensureDirectoryExistsWithCache(filePath, parentID, zone, username, userID, netbarID, dirCache)
			if err != nil {
				continue
			}
		} else {
			// 处理文件
			resource, err := extractSingleFile(file, filePath, parentID, zone, netbarID, username, userID, dirCache)
			if err != nil {
				fmt.Printf("解压文件失败 %s: %v\n", filePath, err)
				continue
			}
			if resource != nil {
				resources = append(resources, *resource)
			}
		}
	}

	return resources, nil
}

// ensureDirectoryExistsWithCache 使用缓存确保目录存在
func ensureDirectoryExistsWithCache(dirPath string, parentID *uint, zone string, username string, userID uint, netbarID uint, cache map[string]*uint) (*uint, error) {
	if dirPath == "" {
		return parentID, nil
	}

	// 移除尾部斜杠
	dirPath = strings.TrimSuffix(dirPath, "/")

	// 检查缓存
	cacheKey := fmt.Sprintf("%v-%s", parentID, dirPath)
	if cachedID, ok := cache[cacheKey]; ok {
		return cachedID, nil
	}

	// 分割路径
	parts := strings.Split(dirPath, "/")
	currentParentID := parentID

	for i, part := range parts {
		if part == "" {
			continue
		}

		// 构建当前路径的缓存键
		currentPath := strings.Join(parts[:i+1], "/")
		currentCacheKey := fmt.Sprintf("%v-%s", parentID, currentPath)

		// 检查缓存
		if cachedID, ok := cache[currentCacheKey]; ok {
			currentParentID = cachedID
			continue
		}

		// 检查目录是否已存在
		var existingDir model.Resource
		query := database.MainDB.Where("name = ? AND zone = ? AND is_directory = ?", part, zone, true)
		if currentParentID != nil {
			query = query.Where("parent_id = ?", *currentParentID)
		} else {
			query = query.Where("parent_id IS NULL")
		}
		if netbarID > 0 {
			query = query.Where("netbar_id = ?", netbarID)
		}

		if err := query.First(&existingDir).Error; err == nil {
			currentParentID = &existingDir.ID
			cache[currentCacheKey] = currentParentID
		} else {
			// 创建目录
			var dirPathStr string
			if currentParentID != nil {
				var parent model.Resource
				if err := database.MainDB.First(&parent, *currentParentID).Error; err == nil {
					dirPathStr = parent.Path + "/" + part
				}
			} else {
				dirPathStr = part
			}

			newDir := model.Resource{
				Name:        part,
				Path:        dirPathStr,
				ParentID:    currentParentID,
				NetbarID:    netbarID,
				IsDirectory: true,
				Type:        "folder",
				Zone:        zone,
				Uploader:    username,
				UploaderID:  userID,
				IsGlobal:    true,
			}

			if err := database.MainDB.Create(&newDir).Error; err != nil {
				return nil, err
			}
			currentParentID = &newDir.ID
			cache[currentCacheKey] = currentParentID
		}
	}

	cache[cacheKey] = currentParentID
	return currentParentID, nil
}

// extractSingleFile 解压单个文件
func extractSingleFile(file *zip.File, filePath string, parentID *uint, zone string, netbarID uint, username string, userID uint, dirCache map[string]*uint) (*model.Resource, error) {
	// 获取目录和文件名
	dir := filepath.Dir(filePath)
	fileName := filepath.Base(filePath)

	if fileName == "" || fileName == "." {
		return nil, nil
	}

	// 确保父目录存在
	fileParentID := parentID
	if dir != "" && dir != "." {
		var err error
		fileParentID, err = ensureDirectoryExistsWithCache(dir, parentID, zone, username, userID, netbarID, dirCache)
		if err != nil {
			return nil, err
		}
	}

	// 打开文件
	rc, err := file.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()

	// 生成存储文件名
	ext := filepath.Ext(fileName)
	timestamp := time.Now().UnixNano()
	savedName := fmt.Sprintf("%d%s", timestamp, ext)
	savePath := filepath.Join(uploadDir, savedName)

	// 创建目标文件
	outFile, err := os.Create(savePath)
	if err != nil {
		return nil, err
	}

	// 复制内容
	written, err := io.Copy(outFile, rc)
	outFile.Close()
	if err != nil {
		os.Remove(savePath)
		return nil, err
	}

	// 计算MD5
	f, _ := os.Open(savePath)
	hash := md5.New()
	io.Copy(hash, f)
	f.Close()
	md5Hash := hex.EncodeToString(hash.Sum(nil))

	// 判断文件类型
	fileType := getFileType(fileName)

	// 生成唯一的文件名
	uniqueName := generateUniqueNameForUpload(fileName, fileParentID, zone)

	// 构建路径
	var resourcePath string
	if fileParentID != nil {
		var parent model.Resource
		if err := database.MainDB.First(&parent, *fileParentID).Error; err == nil {
			resourcePath = parent.Path + "/" + uniqueName
		}
	} else {
		resourcePath = uniqueName
	}

	// 对于文本类型文件，读取内容
	var content string
	if isTextFileType(fileType) {
		contentBytes, err := os.ReadFile(savePath)
		if err == nil {
			content = string(contentBytes)
		}
	}

	resource := model.Resource{
		Name:        uniqueName,
		Path:        resourcePath,
		StoragePath: savePath,
		ParentID:    fileParentID,
		NetbarID:    netbarID,
		IsDirectory: false,
		Type:        fileType,
		Size:        written,
		Zone:        zone,
		Uploader:    username,
		UploaderID:  userID,
		Hash:        md5Hash,
		IsGlobal:    true,
		Content:     content,
	}

	if err := database.MainDB.Create(&resource).Error; err != nil {
		os.Remove(savePath)
		return nil, err
	}

	return &resource, nil
}

// DownloadFile 下载文件
func DownloadFile(c *gin.Context) {
	id := c.Param("id")

	var resource model.Resource
	if err := database.MainDB.First(&resource, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "资源不存在"})
		return
	}

	if resource.IsDirectory {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不能下载目录"})
		return
	}

	// 使用存储路径下载文件
	if resource.StoragePath != "" {
		if _, err := os.Stat(resource.StoragePath); err == nil {
			c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", resource.Name))
			c.File(resource.StoragePath)
			return
		}
	}

	// 兼容旧数据：尝试通过 hash 查找
	files, _ := filepath.Glob(filepath.Join(uploadDir, "*"))
	for _, f := range files {
		if strings.Contains(f, resource.Hash) {
			c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", resource.Name))
			c.File(f)
			return
		}
	}

	c.JSON(http.StatusNotFound, gin.H{"error": "文件不存在"})
}

func getFileType(filename string) string {
	ext := strings.ToLower(filepath.Ext(filename))
	switch ext {
	case ".exe", ".msi":
		return "exe"
	case ".ini", ".cfg", ".conf", ".yaml", ".yml", ".json", ".xml", ".txt":
		return "config"
	case ".zip", ".rar", ".7z", ".tar", ".gz":
		return "archive"
	case ".bat", ".ps1", ".sh", ".cmd":
		return "script"
	case ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".ico":
		return "image"
	default:
		return "unknown"
	}
}

// isTextFileType 判断是否为可编辑的文本文件类型
func isTextFileType(fileType string) bool {
	switch fileType {
	case "config", "script":
		return true
	default:
		return false
	}
}

// DownloadDirectory 下载目录为zip文件
func DownloadDirectory(c *gin.Context) {
	id := c.Param("id")

	var resource model.Resource
	if err := database.MainDB.First(&resource, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "资源不存在"})
		return
	}

	if !resource.IsDirectory {
		c.JSON(http.StatusBadRequest, gin.H{"error": "只能下载目录"})
		return
	}

	// 设置响应头
	zipName := resource.Name + ".zip"
	c.Header("Content-Type", "application/zip")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", zipName))

	// 创建zip writer直接写入响应
	zipWriter := zip.NewWriter(c.Writer)
	defer zipWriter.Close()

	// 递归添加目录内容到zip，从根目录名称开始
	if err := addDirectoryToZip(zipWriter, resource.ID, resource.Name); err != nil {
		// 注意：由于已经开始写入响应，无法再返回JSON错误
		// 错误会导致zip文件不完整
		return
	}
}

// addDirectoryToZip 递归添加目录内容到zip
func addDirectoryToZip(zipWriter *zip.Writer, dirID uint, basePath string) error {
	// 获取目录下所有子项（未被软删除的）
	var children []model.Resource
	if err := database.MainDB.Where("parent_id = ?", dirID).Find(&children).Error; err != nil {
		return err
	}

	// 如果目录为空，也要创建目录条目
	if len(children) == 0 && basePath != "" {
		_, err := zipWriter.Create(basePath + "/")
		return err
	}

	for _, child := range children {
		relativePath := child.Name
		if basePath != "" {
			relativePath = basePath + "/" + child.Name
		}

		if child.IsDirectory {
			// 递归处理子目录（目录条目会在有内容时自动创建，或空目录时在上面创建）
			if err := addDirectoryToZip(zipWriter, child.ID, relativePath); err != nil {
				return err
			}
		} else {
			// 添加文件到zip
			if err := addFileToZip(zipWriter, &child, relativePath); err != nil {
				// 记录错误但继续处理其他文件
				fmt.Printf("添加文件失败 %s: %v\n", child.Name, err)
				continue
			}
		}
	}

	return nil
}

// addFileToZip 添加单个文件到zip
func addFileToZip(zipWriter *zip.Writer, resource *model.Resource, relativePath string) error {
	// 检查存储路径
	if resource.StoragePath == "" {
		return fmt.Errorf("文件存储路径为空: %s", resource.Name)
	}

	// 检查文件是否存在
	if _, err := os.Stat(resource.StoragePath); err != nil {
		return fmt.Errorf("文件不存在: %s -> %s", resource.Name, resource.StoragePath)
	}

	// 创建zip条目，使用原始文件名作为路径
	header := &zip.FileHeader{
		Name:   relativePath,
		Method: zip.Deflate,
	}

	// 设置修改时间
	header.Modified = resource.UpdatedAt

	// 创建zip条目
	writer, err := zipWriter.CreateHeader(header)
	if err != nil {
		return err
	}

	// 读取文件内容并写入
	file, err := os.Open(resource.StoragePath)
	if err != nil {
		return err
	}
	defer file.Close()

	_, err = io.Copy(writer, file)
	return err
}
