package config

import (
	"fmt"

	"github.com/spf13/viper"
)

type Config struct {
	Signature struct {
		BaseURL string `mapstructure:"base_url"`
		Path    string `mapstructure:"path"`
	} `mapstructure:"signature"`

	Manifest struct {
		Key          string `mapstructure:"key"`
		BackupPrefix string `mapstructure:"backup_prefix"`
	} `mapstructure:"manifest"`

	PublicURLs []string `mapstructure:"public_urls"`

	OSS struct {
		Prefix string `mapstructure:"prefix"`
	} `mapstructure:"oss"`

	MaxReleases int `mapstructure:"max_releases"`
}

func Load(path string) (*Config, error) {
	v := viper.New()
	v.SetConfigFile(path)
	if err := v.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("read config %s: %w", path, err)
	}
	var c Config
	if err := v.Unmarshal(&c); err != nil {
		return nil, fmt.Errorf("unmarshal config: %w", err)
	}
	if c.MaxReleases == 0 {
		c.MaxReleases = 20
	}
	if c.Signature.BaseURL == "" || c.Signature.Path == "" {
		return nil, fmt.Errorf("signature.base_url / signature.path required")
	}
	if c.Manifest.Key == "" {
		return nil, fmt.Errorf("manifest.key required")
	}
	if len(c.PublicURLs) == 0 {
		return nil, fmt.Errorf("public_urls required (at least 1)")
	}
	return &c, nil
}
