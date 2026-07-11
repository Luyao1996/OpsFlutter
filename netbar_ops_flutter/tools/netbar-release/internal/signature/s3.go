package signature

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// Signer 抽象"根据 OSS key 换取预签名上传 URL"的能力。
// 老的 PHP 签名服务 (*Client) 与新的本地 S3 签名器 (*S3Signer) 都实现它。
type Signer interface {
	Sign(file string) (string, error)
}

// S3Signer 本地生成 AWS SigV4 预签名 PUT URL（S3 兼容存储，RustFS/MinIO）。
// 不依赖远端签名服务，密钥直接参与本地 HMAC 计算。
type S3Signer struct {
	endpoint string // 形如 http://host[:port]，不带末尾斜杠
	bucket   string
	region   string
	ak, sk   string
}

func NewS3(endpoint, bucket, region, accessKey, secretKey string) *S3Signer {
	return &S3Signer{
		endpoint: strings.TrimRight(endpoint, "/"),
		bucket:   bucket,
		region:   region,
		ak:       accessKey,
		sk:       secretKey,
	}
}

// Sign 生成 PUT 预签名 URL。file 形如 "/netbaropsflutter/xxx.apk"（带前导斜杠也兼容）。
// 签名只覆盖 host 头 + UNSIGNED-PAYLOAD，与 uploader 的"PUT 且不带 Content-Type"约定兼容。
// 有效期 1 小时，足够大安装包在慢速网络上传完（签名只校验开始时刻）。
func (s *S3Signer) Sign(file string) (string, error) {
	return s.presign("PUT", file, 3600)
}

func (s *S3Signer) presign(method, file string, expires int) (string, error) {
	key := strings.TrimLeft(file, "/")
	u, err := url.Parse(s.endpoint)
	if err != nil {
		return "", fmt.Errorf("parse s3 endpoint: %w", err)
	}
	host := u.Host // 非默认端口必须保留在 host 里参与签名

	now := time.Now().UTC()
	amzDate := now.Format("20060102T150405Z")
	dateStamp := now.Format("20060102")
	scope := dateStamp + "/" + s.region + "/s3/aws4_request"

	canonicalURI := "/" + s.bucket + "/" + uriEncodePath(key)

	q := url.Values{}
	q.Set("X-Amz-Algorithm", "AWS4-HMAC-SHA256")
	q.Set("X-Amz-Credential", s.ak+"/"+scope)
	q.Set("X-Amz-Date", amzDate)
	q.Set("X-Amz-Expires", fmt.Sprintf("%d", expires))
	q.Set("X-Amz-SignedHeaders", "host")
	canonicalQuery := q.Encode()

	canonicalRequest := strings.Join([]string{
		method,
		canonicalURI,
		canonicalQuery,
		"host:" + host,
		"",
		"host",
		"UNSIGNED-PAYLOAD",
	}, "\n")

	stringToSign := strings.Join([]string{
		"AWS4-HMAC-SHA256",
		amzDate,
		scope,
		sha256hex(canonicalRequest),
	}, "\n")

	kDate := hmacSHA256([]byte("AWS4"+s.sk), []byte(dateStamp))
	kRegion := hmacSHA256(kDate, []byte(s.region))
	kService := hmacSHA256(kRegion, []byte("s3"))
	kSigning := hmacSHA256(kService, []byte("aws4_request"))
	sig := hex.EncodeToString(hmacSHA256(kSigning, []byte(stringToSign)))

	return s.endpoint + canonicalURI + "?" + canonicalQuery + "&X-Amz-Signature=" + sig, nil
}

// uriEncodePath 按 SigV4 规范逐段编码路径（保留 '/'，空格用 %20）。
func uriEncodePath(p string) string {
	segs := strings.Split(p, "/")
	for i, seg := range segs {
		enc := url.QueryEscape(seg)
		segs[i] = strings.ReplaceAll(enc, "+", "%20")
	}
	return strings.Join(segs, "/")
}

func hmacSHA256(key, data []byte) []byte {
	h := hmac.New(sha256.New, key)
	h.Write(data)
	return h.Sum(nil)
}

func sha256hex(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}
