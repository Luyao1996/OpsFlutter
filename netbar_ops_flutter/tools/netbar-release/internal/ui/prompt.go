package ui

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/AlecAivazis/survey/v2"
)

// SelectPlatform 选择平台。
func SelectPlatform() (string, error) {
	var ans string
	prompt := &survey.Select{
		Message: "选择平台:",
		Options: []string{"android", "windows"},
		Default: "android",
	}
	err := survey.AskOne(prompt, &ans)
	return ans, err
}

// AskString 通用字符串输入。
func AskString(message, defaultVal string) (string, error) {
	var ans string
	prompt := &survey.Input{
		Message: message,
		Default: defaultVal,
	}
	err := survey.AskOne(prompt, &ans, survey.WithValidator(survey.Required))
	return strings.TrimSpace(ans), err
}

// AskStringOptional 可选字符串输入（允许空）。
func AskStringOptional(message, defaultVal string) (string, error) {
	var ans string
	prompt := &survey.Input{
		Message: message,
		Default: defaultVal,
	}
	err := survey.AskOne(prompt, &ans)
	return strings.TrimSpace(ans), err
}

// AskInt 整数输入。
func AskInt(message string, defaultVal int) (int, error) {
	def := ""
	if defaultVal > 0 {
		def = strconv.Itoa(defaultVal)
	}
	var ans string
	prompt := &survey.Input{
		Message: message,
		Default: def,
	}
	err := survey.AskOne(prompt, &ans, survey.WithValidator(func(v interface{}) error {
		s, _ := v.(string)
		if _, err := strconv.Atoi(strings.TrimSpace(s)); err != nil {
			return fmt.Errorf("请输入整数")
		}
		return nil
	}))
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(strings.TrimSpace(ans))
}

// AskConfirm 是否确认。
func AskConfirm(message string, defaultVal bool) (bool, error) {
	var ans bool
	prompt := &survey.Confirm{
		Message: message,
		Default: defaultVal,
	}
	err := survey.AskOne(prompt, &ans)
	return ans, err
}

// AskMultiline changelog 多行输入。survey 的 Multiline 在 Windows 控制台有兼容问题，
// 这里用更稳定的"按提示逐行读取，空行结束"方式。
// 输入 "remake"（不区分大小写）会清空已输入的所有行并重新开始。
func AskMultiline(message string) (string, error) {
	fmt.Println(message)
	fmt.Println("  （每行一条，输入空行结束；输入 remake 清空重来）")
	reader := bufio.NewReader(os.Stdin)
	var lines []string
	for {
		fmt.Print("  > ")
		line, err := reader.ReadString('\n')
		if err != nil {
			return "", err
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break
		}
		if strings.EqualFold(strings.TrimSpace(line), "remake") {
			lines = lines[:0]
			fmt.Println("  ⟳ 已清空，请重新输入：")
			continue
		}
		lines = append(lines, line)
	}
	return strings.Join(lines, "\n"), nil
}
