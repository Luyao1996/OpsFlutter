package handler

import (
	"encoding/csv"
	"fmt"
	"time"

	"github.com/gin-gonic/gin"

	"netbar-ops-api/internal/database"
	"netbar-ops-api/internal/model"
)

func ExportNetbars(c *gin.Context) {
	var netbars []model.Netbar
	database.MainDB.Find(&netbars)

	c.Header("Content-Type", "text/csv; charset=utf-8")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=netbars_%s.csv", time.Now().Format("20060102")))
	c.Writer.Write([]byte{0xEF, 0xBB, 0xBF}) // UTF-8 BOM for Excel

	writer := csv.NewWriter(c.Writer)
	writer.Write([]string{"ID", "名称", "编码", "地址", "联系人", "电话", "总座位", "在线座位", "状态", "创建时间"})

	for _, nb := range netbars {
		status := "在线"
		if nb.Status == 0 {
			status = "离线"
		}
		writer.Write([]string{
			fmt.Sprintf("%d", nb.ID),
			nb.Name,
			nb.Code,
			nb.Address,
			nb.Contact,
			nb.Phone,
			fmt.Sprintf("%d", nb.TotalSeats),
			fmt.Sprintf("%d", nb.OnlineSeats),
			status,
			nb.CreatedAt.Format("2006-01-02 15:04:05"),
		})
	}
	writer.Flush()
}

func ExportChannels(c *gin.Context) {
	var channels []model.Channel
	database.MainDB.Find(&channels)

	c.Header("Content-Type", "text/csv; charset=utf-8")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=channels_%s.csv", time.Now().Format("20060102")))
	c.Writer.Write([]byte{0xEF, 0xBB, 0xBF})

	writer := csv.NewWriter(c.Writer)
	writer.Write([]string{"ID", "名称", "编码", "类型", "带宽(Mbps)", "状态", "描述", "创建时间"})

	for _, ch := range channels {
		status := "启用"
		if ch.Status == 0 {
			status = "禁用"
		}
		writer.Write([]string{
			fmt.Sprintf("%d", ch.ID),
			ch.Name,
			ch.Code,
			ch.Type,
			fmt.Sprintf("%d", ch.Bandwidth),
			status,
			ch.Description,
			ch.CreatedAt.Format("2006-01-02 15:04:05"),
		})
	}
	writer.Flush()
}

func ExportDesktops(c *gin.Context) {
	var desktops []model.Desktop
	database.MainDB.Find(&desktops)

	c.Header("Content-Type", "text/csv; charset=utf-8")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=desktops_%s.csv", time.Now().Format("20060102")))
	c.Writer.Write([]byte{0xEF, 0xBB, 0xBF})

	writer := csv.NewWriter(c.Writer)
	writer.Write([]string{"ID", "名称", "编码", "网吧ID", "IP", "MAC", "操作系统", "状态", "最后在线", "创建时间"})

	statusMap := map[int]string{0: "离线", 1: "空闲", 2: "使用中"}
	for _, d := range desktops {
		lastOnline := ""
		if d.LastOnline != nil {
			lastOnline = d.LastOnline.Format("2006-01-02 15:04:05")
		}
		writer.Write([]string{
			fmt.Sprintf("%d", d.ID),
			d.Name,
			d.Code,
			fmt.Sprintf("%d", d.NetbarID),
			d.IP,
			d.MAC,
			d.OS,
			statusMap[d.Status],
			lastOnline,
			d.CreatedAt.Format("2006-01-02 15:04:05"),
		})
	}
	writer.Flush()
}

func ExportLogs(c *gin.Context) {
	var logs []model.SystemLog
	database.LogsDB.Order("created_at DESC").Limit(1000).Find(&logs)

	c.Header("Content-Type", "text/csv; charset=utf-8")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=logs_%s.csv", time.Now().Format("20060102")))
	c.Writer.Write([]byte{0xEF, 0xBB, 0xBF})

	writer := csv.NewWriter(c.Writer)
	writer.Write([]string{"ID", "级别", "模块", "操作", "消息", "用户", "IP", "时间"})

	for _, l := range logs {
		writer.Write([]string{
			fmt.Sprintf("%d", l.ID),
			l.Level,
			l.Module,
			l.Action,
			l.Message,
			l.Username,
			l.IP,
			l.CreatedAt.Format("2006-01-02 15:04:05"),
		})
	}
	writer.Flush()
}
