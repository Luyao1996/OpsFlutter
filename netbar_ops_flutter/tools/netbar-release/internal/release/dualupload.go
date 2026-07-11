package release

import (
	"fmt"

	"netbar-release/internal/signature"
	"netbar-release/internal/uploader"
)

// DualUploadFile 把同一个本地文件按同一个 key 上传到新老双源。
// 新源（RustFS）必须成功，否则返回错误中断发布；
// 老源（阿里 OSS）失败只打警告——老签名服务 key 失效期间发布不被阻塞，
// 修复后无需改代码即自动恢复双写。
func DualUploadFile(primary, legacy signature.Signer, key, filePath string) error {
	fmt.Println("▸ 上传新源 ...")
	signedURL, err := primary.Sign(key)
	if err != nil {
		return fmt.Errorf("sign(新源): %w", err)
	}
	if err := uploader.UploadFile(signedURL, filePath); err != nil {
		return fmt.Errorf("upload(新源): %w", err)
	}
	fmt.Println("   ✓ 新源上传完成")

	if legacy == nil {
		return nil
	}
	fmt.Println("▸ 上传老源 ...")
	lu, err := legacy.Sign(key)
	if err != nil {
		fmt.Printf("   ⚠ 老源签名失败（发布继续，老客户端暂不可见此版本）: %v\n", err)
		return nil
	}
	if err := uploader.UploadFile(lu, filePath); err != nil {
		fmt.Printf("   ⚠ 老源上传失败（发布继续，老客户端暂不可见此版本）: %v\n", err)
		return nil
	}
	fmt.Println("   ✓ 老源上传完成")
	return nil
}
