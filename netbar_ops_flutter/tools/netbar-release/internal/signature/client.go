package signature

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type Client struct {
	baseURL string
	path    string
	http    *http.Client
}

type signResponse struct {
	Code int    `json:"code"`
	Msg  string `json:"msg"`
	URL  string `json:"url"`
}

func New(baseURL, path string) *Client {
	return &Client{
		baseURL: baseURL,
		path:    path,
		http:    &http.Client{Timeout: 30 * time.Second},
	}
}

// Sign 申请一个 OSS 预签名上传 URL。
// 调用方传入的 file 形如 "/netbaropsflutter/xxx.apk"（带前导斜杠也兼容）。
// 签名服务要求 file 参数不带前导 '/'，内部斜杠用 %2F 编码，
// 因此这里先 strip 前导 '/' 再交给 query encoder。
func (c *Client) Sign(file string) (string, error) {
	file = strings.TrimLeft(file, "/")
	u, err := url.Parse(c.baseURL + c.path)
	if err != nil {
		return "", fmt.Errorf("parse signature url: %w", err)
	}
	q := u.Query()
	q.Set("file", file)
	u.RawQuery = q.Encode()

	resp, err := c.http.Get(u.String())
	if err != nil {
		return "", fmt.Errorf("get signature: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read signature body: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("signature http %d: %s", resp.StatusCode, string(body))
	}

	var sr signResponse
	if err := json.Unmarshal(body, &sr); err != nil {
		return "", fmt.Errorf("unmarshal signature: %w (body=%s)", err, string(body))
	}
	if sr.Code != 0 {
		return "", fmt.Errorf("signature failed: code=%d msg=%s", sr.Code, sr.Msg)
	}
	if sr.URL == "" {
		return "", fmt.Errorf("signature response has empty url (msg=%s)", sr.Msg)
	}
	return sr.URL, nil
}
