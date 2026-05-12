package builder

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
)

// FlutterBuilder 封装 flutter build apk / windows 调用。
// 子进程的 stdout/stderr 直接转发到父进程，能看到完整编译日志。
type FlutterBuilder struct {
	Command    string // "flutter" 或绝对路径
	ProjectDir string // Flutter 项目根目录（含 pubspec.yaml）
}

func NewFlutterBuilder(command, projectDir string) *FlutterBuilder {
	if command == "" {
		command = "flutter"
	}
	return &FlutterBuilder{Command: command, ProjectDir: projectDir}
}

func (b *FlutterBuilder) run(args ...string) error {
	cmd := exec.Command(b.Command, args...)
	cmd.Dir = b.ProjectDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	fmt.Printf("→ %s %v\n", b.Command, args)
	return cmd.Run()
}

// BuildAPK 编译 release APK，返回 APK 绝对路径。
func (b *FlutterBuilder) BuildAPK(version string, build int) (string, error) {
	if err := b.run(
		"build", "apk", "--release",
		"--build-name="+version,
		"--build-number="+strconv.Itoa(build),
	); err != nil {
		return "", fmt.Errorf("flutter build apk failed: %w", err)
	}
	apk := filepath.Join(b.ProjectDir,
		"build", "app", "outputs", "flutter-apk", "app-release.apk")
	if _, err := os.Stat(apk); err != nil {
		return "", fmt.Errorf("apk not found at %s: %w", apk, err)
	}
	abs, _ := filepath.Abs(apk)
	return abs, nil
}

// BuildWindows 编译 Windows Release 目录，返回该目录绝对路径。
func (b *FlutterBuilder) BuildWindows(version string, build int) (string, error) {
	if err := b.run(
		"build", "windows", "--release",
		"--build-name="+version,
		"--build-number="+strconv.Itoa(build),
	); err != nil {
		return "", fmt.Errorf("flutter build windows failed: %w", err)
	}
	dir := filepath.Join(b.ProjectDir,
		"build", "windows", "x64", "runner", "Release")
	if _, err := os.Stat(dir); err != nil {
		return "", fmt.Errorf("release dir not found at %s: %w", dir, err)
	}
	abs, _ := filepath.Abs(dir)
	return abs, nil
}
