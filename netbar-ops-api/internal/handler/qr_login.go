package handler

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"

	"netbar-ops-api/internal/config"
	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/middleware"
	"netbar-ops-api/internal/model"
)

// QR登录会话状态
type QRSession struct {
	SessionID string    `json:"session_id"`
	Status    string    `json:"status"` // pending, scanned, confirmed, expired
	UserID    uint      `json:"-"`
	User      *model.User `json:"user,omitempty"`
	Token     string    `json:"token,omitempty"`
	ExpiresAt time.Time `json:"expires_at"`
	CreatedAt time.Time `json:"-"`
}

// 内存存储QR会话（生产环境应使用Redis）
var (
	qrSessions = make(map[string]*QRSession)
	qrMutex    sync.RWMutex
)

// 生成随机会话ID
func generateSessionID() string {
	bytes := make([]byte, 16)
	rand.Read(bytes)
	return hex.EncodeToString(bytes)
}

// CreateQRSession 创建QR登录会话
func CreateQRSession(c *gin.Context) {
	sessionID := generateSessionID()
	expiresAt := time.Now().Add(5 * time.Minute) // 5分钟过期

	session := &QRSession{
		SessionID: sessionID,
		Status:    "pending",
		ExpiresAt: expiresAt,
		CreatedAt: time.Now(),
	}

	qrMutex.Lock()
	qrSessions[sessionID] = session
	qrMutex.Unlock()

	// 启动过期清理
	go func() {
		time.Sleep(5 * time.Minute)
		qrMutex.Lock()
		if s, ok := qrSessions[sessionID]; ok && s.Status == "pending" {
			s.Status = "expired"
		}
		qrMutex.Unlock()
	}()

	c.JSON(http.StatusOK, gin.H{
		"session_id": sessionID,
		"qr_data":    "netbar-ops://login?session=" + sessionID,
		"expires_at": expiresAt.Format(time.RFC3339),
	})
}

// CheckQRStatus 检查QR登录状态
func CheckQRStatus(c *gin.Context) {
	sessionID := c.Param("session_id")

	qrMutex.RLock()
	session, exists := qrSessions[sessionID]
	qrMutex.RUnlock()

	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "会话不存在"})
		return
	}

	// 检查是否过期
	if time.Now().After(session.ExpiresAt) && session.Status == "pending" {
		qrMutex.Lock()
		session.Status = "expired"
		qrMutex.Unlock()
	}

	response := gin.H{
		"status": session.Status,
	}

	if session.Status == "confirmed" && session.Token != "" {
		response["token"] = session.Token
		response["user"] = session.User
	}

	c.JSON(http.StatusOK, response)
}

// ConfirmQRLogin 确认QR登录（移动端调用）
func ConfirmQRLogin(c *gin.Context) {
	sessionID := c.Param("session_id")

	// 获取当前登录用户
	claims, exists := c.Get("claims")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "未登录"})
		return
	}
	userClaims := claims.(*middleware.Claims)

	qrMutex.Lock()
	defer qrMutex.Unlock()

	session, exists := qrSessions[sessionID]
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "会话不存在"})
		return
	}

	if session.Status != "pending" && session.Status != "scanned" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "会话状态无效"})
		return
	}

	if time.Now().After(session.ExpiresAt) {
		session.Status = "expired"
		c.JSON(http.StatusBadRequest, gin.H{"error": "会话已过期"})
		return
	}

	// 获取用户信息
	var user model.User
	if err := database.MainDB.First(&user, userClaims.UserID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "获取用户信息失败"})
		return
	}

	// 生成新的JWT token
	newClaims := middleware.Claims{
		UserID:   user.ID,
		Username: user.Username,
		Role:     user.Role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Duration(config.AppConfig.JWT.ExpireHours) * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, newClaims)
	tokenString, err := token.SignedString([]byte(config.AppConfig.JWT.Secret))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "生成令牌失败"})
		return
	}

	session.Status = "confirmed"
	session.UserID = user.ID
	session.User = &user
	session.Token = tokenString

	c.JSON(http.StatusOK, gin.H{"message": "登录确认成功"})
}

// ScanQRCode 扫描QR码（移动端调用，标记为已扫描）
func ScanQRCode(c *gin.Context) {
	sessionID := c.Param("session_id")

	qrMutex.Lock()
	defer qrMutex.Unlock()

	session, exists := qrSessions[sessionID]
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "会话不存在"})
		return
	}

	if session.Status != "pending" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "会话状态无效"})
		return
	}

	if time.Now().After(session.ExpiresAt) {
		session.Status = "expired"
		c.JSON(http.StatusBadRequest, gin.H{"error": "会话已过期"})
		return
	}

	session.Status = "scanned"
	c.JSON(http.StatusOK, gin.H{"message": "扫描成功"})
}

