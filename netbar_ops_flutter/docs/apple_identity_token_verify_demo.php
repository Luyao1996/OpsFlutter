<?php
/**
 * ============================================================================
 * Sign in with Apple — identityToken 服务端验证 Demo（可直接运行）
 * ============================================================================
 *
 * 【依赖与环境】
 *   - PHP >= 7.4（含 ext-curl / ext-openssl / ext-json，均为常规扩展）
 *   - composer require firebase/php-jwt:^6.0
 *   - 本文件自包含：配置 + JWKS 拉取缓存 + 完整验证 + CLI 测试入口
 *
 * 【信源（写前已逐一核对，2026-08-03）】
 *   1. Apple 官方文档 developer.apple.com/documentation/signinwithapple/verifying-a-user：
 *      验证要求 = RS256 验签（公钥来自 Apple JWKS）+ iss + aud + exp + nonce 四项 claim 校验
 *   2. 实测 https://appleid.apple.com/auth/keys（公开接口，无需任何 Apple 密钥）：
 *      当前返回 3 把 RSA 公钥，每把含 kty/kid/use/alg/n/e 字段，alg 均为 RS256
 *   3. firebase/php-jwt 官方 README：JWK::parseKeySet($jwks) 返回 kid→Key 关联数组，
 *      直接作为 JWT::decode() 第二参数，decode 自动按 token header 的 kid 选钥，
 *      并自动完成 验签 + exp/nbf 校验；异常：ExpiredException / SignatureInvalidException /
 *      BeforeValidException / UnexpectedValueException / DomainException / InvalidArgumentException
 *
 * 【精准性要点（容易踩的坑，本 demo 已处理）】
 *   A. ExpiredException / SignatureInvalidException 都是 UnexpectedValueException 的子类，
 *      所以"kid 不在缓存密钥集"（苹果轮换密钥）不能靠 catch 异常类型区分。
 *      本 demo 先解 JWT header 预查 kid，未命中才强刷 JWKS —— 确定性方案。
 *   B. payload 里不要依赖 email 字段（App 端 scopes 为空不索取），用户身份只认 sub。
 *   C. nonce 比对用 hash_equals()（恒时比较），比对对象是 sha256(客户端送来的 nonce 原文)。
 *   D. identityToken 有效期约 10 分钟 —— 联调时用 App debug 包日志里的 [SIWA][debug] token，
 *      拿到后立刻测；或临时打开下面的 DEV_HUGE_LEEWAY 开关反复调试（生产严禁）。
 *
 * 【CLI 测试用法】
 *   php apple_identity_token_verify_demo.php '<identityToken>' '<nonce原文>'
 *
 * 【接入映射（对应《SignInWithApple后端接口技术方案.md》）】
 *   AppleTokenException            → HTTP 401 {code:"INVALID_APPLE_TOKEN"}
 *   验证通过后拿 $payload->sub 查 apple_binding：
 *     无记录                        → HTTP 404 {code:"APPLE_ID_NOT_BOUND"}
 *     有记录但账号停用              → HTTP 403 {code:"ACCOUNT_DISABLED"}
 *     正常                          → 发业务 access_token（与 /alpha/passport/login 同构）
 * ============================================================================
 */

declare(strict_types=1);

require __DIR__ . '/vendor/autoload.php'; // TODO: 按实际项目的 autoload 路径调整

use Firebase\JWT\JWT;
use Firebase\JWT\JWK;
use Firebase\JWT\ExpiredException;
use Firebase\JWT\SignatureInvalidException;

// ===========================  配置  ===========================

const APPLE_ISS       = 'https://appleid.apple.com';
const APPLE_AUD       = 'com.netbarops.netbarOpsFlutter'; // 我们 iOS App 的 Bundle ID，建议移到配置文件
const APPLE_JWKS_URL  = 'https://appleid.apple.com/auth/keys';
const JWKS_CACHE_FILE = '/tmp/apple_jwks_cache.json';     // 按需换成项目缓存目录或 redis
const JWKS_CACHE_TTL  = 86400;                            // JWKS 缓存 24 小时

/**
 * ⚠️ 仅联调用：true 时把时钟容差放大到 10 年，等效跳过 exp 校验，
 * 一个真机 token 可反复回放调试（其余验签/iss/aud/nonce 校验全部保留）。
 * 生产环境必须为 false。
 */
const DEV_HUGE_LEEWAY = false;

// ===========================  异常  ===========================

/** 验证失败统一异常 → 接口层返回 401 INVALID_APPLE_TOKEN（细分原因写日志，不外露给客户端） */
final class AppleTokenException extends \RuntimeException
{
}

// ===========================  JWKS 拉取与缓存  ===========================

/**
 * 获取 Apple JWKS（带文件缓存；拉取失败时回退旧缓存保可用性）。
 *
 * @return array{keys: array<int, array<string, string>>}
 */
function fetchAppleJwks(bool $forceRefresh = false): array
{
    $cacheFresh = is_file(JWKS_CACHE_FILE)
        && (time() - (int) filemtime(JWKS_CACHE_FILE)) < JWKS_CACHE_TTL;

    if (!$forceRefresh && $cacheFresh) {
        $cached = json_decode((string) file_get_contents(JWKS_CACHE_FILE), true);
        if (is_array($cached) && !empty($cached['keys'])) {
            return $cached;
        }
    }

    $ch = curl_init(APPLE_JWKS_URL);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 3,
        CURLOPT_TIMEOUT        => 5,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
    ]);
    $body     = curl_exec($ch);
    $httpCode = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);

    $jwks = is_string($body) ? json_decode($body, true) : null;
    if ($httpCode === 200 && is_array($jwks) && !empty($jwks['keys'])) {
        // 原子写缓存：先写临时文件再 rename，防并发请求读到半截文件
        $tmp = JWKS_CACHE_FILE . '.' . uniqid('', true) . '.tmp';
        if (@file_put_contents($tmp, $body) !== false) {
            @rename($tmp, JWKS_CACHE_FILE);
        }
        return $jwks;
    }

    // 拉取失败：有旧缓存（哪怕已过 TTL）先用旧的，别让登录全挂
    if (is_file(JWKS_CACHE_FILE)) {
        $stale = json_decode((string) file_get_contents(JWKS_CACHE_FILE), true);
        if (is_array($stale) && !empty($stale['keys'])) {
            return $stale;
        }
    }

    throw new AppleTokenException('无法获取 Apple JWKS（网络失败且无本地缓存），HTTP ' . $httpCode);
}

// ===========================  核心验证  ===========================

/**
 * 验证 Apple identityToken，通过则返回 payload（用 ->sub 查绑定关系）。
 *
 * @param string $identityToken App 端送来的 JWT 原文（三段式 xxx.yyy.zzz）
 * @param string $rawNonce      App 端送来的 nonce 原文（App 端把它的 sha256 传给了 Apple）
 *
 * @throws AppleTokenException 任何一步验证不通过
 */
function verifyAppleIdentityToken(string $identityToken, string $rawNonce): \stdClass
{
    // ---- 0. 基础格式 ----
    $parts = explode('.', $identityToken);
    if (count($parts) !== 3) {
        throw new AppleTokenException('token 格式错误：不是三段式 JWT');
    }

    // ---- 1. 解 header 预查 kid（见文件头【精准性要点 A】）----
    $header = json_decode(JWT::urlsafeB64Decode($parts[0]), false);
    $kid    = is_object($header) ? (string) ($header->kid ?? '') : '';
    if ($kid === '') {
        throw new AppleTokenException('token header 缺少 kid');
    }

    $jwks = fetchAppleJwks(false);
    $kids = array_column($jwks['keys'], 'kid');
    if (!in_array($kid, $kids, true)) {
        // 缓存密钥集没有该 kid：苹果可能刚轮换了密钥，强刷一次再试
        $jwks = fetchAppleJwks(true);
        if (!in_array($kid, array_column($jwks['keys'], 'kid'), true)) {
            throw new AppleTokenException('kid 在 Apple 当前密钥集中不存在: ' . $kid);
        }
    }

    // ---- 2. 验签 + exp（JWT::decode 内部自动完成，按 kid 自动选钥）----
    JWT::$leeway = DEV_HUGE_LEEWAY ? 315360000 : 30; // 生产 30s 时钟容差
    try {
        $payload = JWT::decode($identityToken, JWK::parseKeySet($jwks, 'RS256'));
    } catch (ExpiredException $e) {
        throw new AppleTokenException('token 已过期（有效期约 10 分钟）');
    } catch (SignatureInvalidException $e) {
        throw new AppleTokenException('签名验证失败');
    } catch (\Throwable $e) {
        // BeforeValidException / UnexpectedValueException / DomainException 等
        throw new AppleTokenException('token 无效: ' . get_class($e) . ' ' . $e->getMessage());
    }

    // ---- 3. iss / aud ----
    if (($payload->iss ?? '') !== APPLE_ISS) {
        throw new AppleTokenException('iss 不符: ' . (string) ($payload->iss ?? '(空)'));
    }
    if (($payload->aud ?? '') !== APPLE_AUD) {
        throw new AppleTokenException('aud 不符: ' . (string) ($payload->aud ?? '(空)'));
    }

    // ---- 4. nonce（恒时比较，防重放）----
    $expectedNonce = hash('sha256', $rawNonce);
    $tokenNonce    = $payload->nonce ?? null;
    if (!is_string($tokenNonce) || !hash_equals($expectedNonce, $tokenNonce)) {
        throw new AppleTokenException('nonce 校验失败');
    }

    // ---- 5. sub ----
    if (!is_string($payload->sub ?? null) || $payload->sub === '') {
        throw new AppleTokenException('payload 缺少 sub');
    }

    return $payload;
}

// ===========================  CLI 测试入口  ===========================
// php apple_identity_token_verify_demo.php '<identityToken>' '<nonce原文>'
// token 来源：iOS App debug 包点"通过 Apple 登录"后，日志里的 [SIWA][debug] 两行

if (PHP_SAPI === 'cli' && isset($argv[0]) && realpath($argv[0]) === __FILE__) {
    if ($argc < 3) {
        fwrite(STDERR, "用法: php {$argv[0]} '<identityToken>' '<nonce原文>'\n");
        exit(1);
    }
    try {
        $payload = verifyAppleIdentityToken($argv[1], $argv[2]);
        echo "✅ 验证通过\n";
        echo 'sub = ' . $payload->sub . "\n";
        echo 'payload = ' . json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
        echo "\n下一步：拿 sub 查 apple_binding → 命中发业务token / 未命中返回 APPLE_ID_NOT_BOUND\n";
        exit(0);
    } catch (AppleTokenException $e) {
        echo '❌ 验证失败（接口应返回 401 INVALID_APPLE_TOKEN）: ' . $e->getMessage() . "\n";
        exit(2);
    }
}
