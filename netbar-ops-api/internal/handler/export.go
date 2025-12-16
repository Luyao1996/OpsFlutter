package handler

import (
	"encoding/csv"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/xuri/excelize/v2"

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
	query := database.LogsDB.Model(&model.SystemLog{}).Order("created_at DESC")

	if level := c.Query("level"); level != "" {
		query = query.Where("level = ?", level)
	}

	if module := c.Query("module"); module != "" {
		query = query.Where("module = ?", module)
	}

	if search := c.Query("search"); search != "" {
		like := "%" + search + "%"
		query = query.Where("message LIKE ? OR action LIKE ? OR username LIKE ?", like, like, like)
		if id, err := strconv.Atoi(search); err == nil && id > 0 {
			query = query.Or("id = ?", id)
		}
	}

	// 时间范围（按日期，包含 end_date 当天）
	if startDate := c.Query("start_date"); startDate != "" {
		if endDate := c.Query("end_date"); endDate != "" {
			start, err1 := time.ParseInLocation("2006-01-02", startDate, time.Local)
			end, err2 := time.ParseInLocation("2006-01-02", endDate, time.Local)
			if err1 == nil && err2 == nil {
				if end.Before(start) {
					start, end = end, start
				}
				endExclusive := end.AddDate(0, 0, 1)
				query = query.Where("created_at >= ? AND created_at < ?", start, endExclusive)
			}
		}
	}

	if err := query.Find(&logs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "导出失败"})
		return
	}

	format := strings.ToLower(c.Query("format"))
	if format == "" {
		format = "csv"
	}

	if format == "csv" {
		c.Header("Content-Type", "text/csv; charset=utf-8")
		filename := fmt.Sprintf("logs_%s.csv", time.Now().Format("20060102_150405"))
		c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
		c.Header("Access-Control-Expose-Headers", "Content-Disposition")
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
		return
	}

	f := excelize.NewFile()
	const sheet = "Logs"
	f.SetSheetName("Sheet1", sheet)

	headerStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Color: "#111827"},
		Fill: excelize.Fill{Type: "pattern", Color: []string{"#F3F4F6"}, Pattern: 1},
	})

	sw, _ := f.NewStreamWriter(sheet)
	headers := []string{"ID", "级别", "模块", "操作", "消息", "用户", "IP", "时间"}
	headerRow := make([]interface{}, 0, len(headers))
	for _, h := range headers {
		headerRow = append(headerRow, excelize.Cell{StyleID: headerStyle, Value: h})
	}
	_ = sw.SetRow("A1", headerRow)

	for i, l := range logs {
		rowIdx := i + 2
		cell, _ := excelize.CoordinatesToCellName(1, rowIdx)
		_ = sw.SetRow(cell, []interface{}{
			l.ID,
			l.Level,
			l.Module,
			l.Action,
			l.Message,
			l.Username,
			l.IP,
			l.CreatedAt.Format("2006-01-02 15:04:05"),
		})
	}
	_ = sw.Flush()

	_ = f.SetColWidth(sheet, "A", "A", 10)
	_ = f.SetColWidth(sheet, "B", "C", 14)
	_ = f.SetColWidth(sheet, "D", "D", 18)
	_ = f.SetColWidth(sheet, "E", "E", 60)
	_ = f.SetColWidth(sheet, "F", "G", 18)
	_ = f.SetColWidth(sheet, "H", "H", 22)

	filename := fmt.Sprintf("logs_%s.xlsx", time.Now().Format("20060102_150405"))
	c.Header("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
	c.Header("Access-Control-Expose-Headers", "Content-Disposition")
	c.Status(http.StatusOK)
	if err := f.Write(c.Writer); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "导出失败"})
		return
	}
}
