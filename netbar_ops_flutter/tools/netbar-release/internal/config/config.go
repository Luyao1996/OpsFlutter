package config

import (
	"fmt"
	"path/filepath"

	"github.com/spf13/viper"
)

type Config struct {
	Signature struct {
		BaseURL string `mapstructure:"base_url"`
		Path    string `mapstructure:"path"`
	} `mapstructure:"signature"`

	// S3 新源（RustFS，S3 兼容）：上传下载同一接口。
	// 字段留空时使用内置默认值（密钥为永不过期的固定 key，经确认直接内置）。
	S3 struct {
		Endpoint  string `mapstructure:"endpoint"`
		Bucket    string `mapstructure:"bucket"`
		Region    string `mapstructure:"region"`
		AccessKey string `mapstructure:"access_key"`
		SecretKey string `mapstructure:"secret_key"`
	} `mapstructure:"s3"`

	Manifest struct {
		Key          string `mapstructure:"key"`
		BackupPrefix string `mapstructure:"backup_prefix"`
	} `mapstructure:"manifest"`

	PublicURLs []string `mapstructure:"public_urls"`

	OSS struct {
		Prefix string `mapstructure:"prefix"`
	} `mapstructure:"oss"`

	MaxReleases int `mapstructure:"max_releases"`

	// 以下为 release 子命令所需

	Flutter struct {
		ProjectDir string `mapstructure:"project_dir"`
		Command    string `mapstructure:"command"`
	} `mapstructure:"flutter"`

	InnoSetup struct {
		ISCCPath  string `mapstructure:"iscc_path"`
		Script    string `mapstructure:"script"`
		OutputDir string `mapstructure:"output_dir"`
	} `mapstructure:"inno_setup"`

	Android struct {
		APKOutput string `mapstructure:"apk_output"`
	} `mapstructure:"android"`

	// 配置文件所在目录，用于把配置中的相对路径转换为绝对路径
	BaseDir string `mapstructure:"-"`
}

// ResolvePath 把可能是相对路径的配置项转换为基于 BaseDir 的绝对路径
func (c *Config) ResolvePath(p string) string {
	if p == "" {
		return ""
	}
	if filepath.IsAbs(p) {
		return p
	}
	return filepath.Join(c.BaseDir, p)
}

func Load(path string) (*Config, error) {
	absPath, err := filepath.Abs(path)
	if err != nil {
		return nil, fmt.Errorf("abs config path: %w", err)
	}
	v := viper.New()
	v.SetConfigFile(absPath)
	if err := v.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("read config %s: %w", absPath, err)
	}
	var c Config
	if err := v.Unmarshal(&c); err != nil {
		return nil, fmt.Errorf("unmarshal config: %w", err)
	}
	c.BaseDir = filepath.Dir(absPath)

	if c.MaxReleases == 0 {
		c.MaxReleases = 20
	}
	if c.Flutter.Command == "" {
		c.Flutter.Command = "flutter"
	}
	if c.Flutter.ProjectDir == "" {
		c.Flutter.ProjectDir = "../.."
	}

	if c.Signature.BaseURL == "" || c.Signature.Path == "" {
		return nil, fmt.Errorf("signature.base_url / signature.path required")
	}
	if c.S3.Endpoint == "" {
		c.S3.Endpoint = "http://server.guanliyuangong.com:9000"
	}
	if c.S3.Bucket == "" {
		c.S3.Bucket = "ops-package"
	}
	if c.S3.Region == "" {
		c.S3.Region = "us-east-1"
	}
	if c.S3.AccessKey == "" {
		c.S3.AccessKey = "ctGJ7vBMUzFTUujsmdNs"
	}
	if c.S3.SecretKey == "" {
		c.S3.SecretKey = "jJgCesmkXIHrvSrYpF2d5P55hDmWQj5RuJfJhJeH"
	}
	if c.Manifest.Key == "" {
		return nil, fmt.Errorf("manifest.key required")
	}
	if len(c.PublicURLs) == 0 {
		return nil, fmt.Errorf("public_urls required (at least 1)")
	}
	return &c, nil
}
