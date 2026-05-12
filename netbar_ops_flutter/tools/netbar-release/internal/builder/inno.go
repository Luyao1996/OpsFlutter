package builder

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
)

// InnoSetupBuilder 封装 ISCC.exe 调用。
type InnoSetupBuilder struct {
	ISCCPath  string // ISCC.exe 绝对路径
	Script    string // installer.iss 路径
	OutputDir string // dist/ 目录
}

func NewInnoSetupBuilder(iscc, script, outputDir string) *InnoSetupBuilder {
	return &InnoSetupBuilder{
		ISCCPath:  iscc,
		Script:    script,
		OutputDir: outputDir,
	}
}

// Build 用 ISCC 打包 setup.exe，返回 setup.exe 绝对路径。
// sourceDir 是 flutter build windows --release 的产物目录。
func (b *InnoSetupBuilder) Build(sourceDir, version string, build int) (string, error) {
	if _, err := os.Stat(b.ISCCPath); err != nil {
		return "", fmt.Errorf("ISCC not found at %s: %w", b.ISCCPath, err)
	}
	script, _ := filepath.Abs(b.Script)
	output, _ := filepath.Abs(b.OutputDir)
	source, _ := filepath.Abs(sourceDir)

	if err := os.MkdirAll(output, 0o755); err != nil {
		return "", err
	}

	args := []string{
		"/DMyAppVersion=" + version,
		"/DMyAppBuild=" + strconv.Itoa(build),
		"/DSourceDir=" + source,
		"/DOutputDir=" + output,
		script,
	}
	cmd := exec.Command(b.ISCCPath, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	fmt.Printf("→ %s %v\n", filepath.Base(b.ISCCPath), args)
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("ISCC failed: %w", err)
	}

	setupName := fmt.Sprintf("netbar-setup-%s-%d.exe", version, build)
	setupPath := filepath.Join(output, setupName)
	if _, err := os.Stat(setupPath); err != nil {
		return "", fmt.Errorf("setup not found at %s: %w", setupPath, err)
	}
	return setupPath, nil
}
