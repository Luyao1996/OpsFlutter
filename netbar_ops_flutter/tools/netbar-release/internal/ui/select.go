package ui

import "github.com/AlecAivazis/survey/v2"

// SelectPlatformWithBoth 在 windows/android 基础上多一个 "both" 选项，
// 用于 release 命令的一键双端发布。
func SelectPlatformWithBoth() (string, error) {
	var ans string
	prompt := &survey.Select{
		Message: "选择平台:",
		Options: []string{"windows", "android", "both"},
		Default: "windows",
	}
	err := survey.AskOne(prompt, &ans)
	return ans, err
}
