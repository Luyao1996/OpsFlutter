package signature

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
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
// file 形如 "/netbaropsflutter/xxx.apk"，必须以 / 开头。
func (c *Client) Sign(file string) (string, error) {
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
