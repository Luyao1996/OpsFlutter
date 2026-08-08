import 'dart:typed_data';

import 'rc4.dart';
import 'totp.dart';

/// 厂商内置 TOTP 种子（「万能码」），与网吧端 `locked/app.go:52`、
/// `server/usermanager.go:27` 是同一个常量。
///
/// 保持 Go 端同款 RC4 密文形态存放，不落明文 base32 常量。
/// ⚠️ 这层混淆强度约等于零（RC4 且密钥字面量就是 "secret"），唯一作用是避免
/// `strings` / `grep` 直接捞到种子。真正的安全边界必须清楚：这个常量一旦泄露，
/// 持有者可以为任意网吧、任意座位生成有效解锁码，且服务端无从知情。
///
/// 之所以选它而不是 secret.dat 那一级的按座位种子：锁屏端与服务端的验证顺序
/// 同构（超级密码 → 内置种子 ±120s → secret.dat ±30s），内置种子在「网吧联网」
/// 与「网吧断网」两种场景下都会被校验通过。
const String _seedCipher = 'uQGbWrfi4e5qjP+bwbO5duFjNLDSx4FvJ05AqpgzAEg=';
const String _seedRc4Key = 'secret';

/// 内置种子那一级的容错窗口（验证端宽容度，见 `locked/app.go:52`）。
///
/// 对生成端的意义：设备时钟与服务端相差在此范围内，算出的码仍会被接受。
/// 注：网吧端这个换算规则本身标注了「对闭源库 KiAuth2FA 的推断，真机待验」
/// （OI-L02-1 / R-L02c），真机联调时需要一并验证。
const Duration builtinSeedTolerance = Duration(seconds: 120);

/// 内置种子的 TOTP 参数。与验证端不一致就永远算不对，真机联调时必须确认。
const int builtinSeedPeriod = 30;
const int builtinSeedDigits = 6;

Uint8List? _cached;
bool _failed = false;

/// 解出内置种子的原始密钥字节（20 字节）。解析失败返回 null。
Uint8List? builtinTotpSeed() {
  if (_failed) return null;
  final cached = _cached;
  if (cached != null) return cached;
  try {
    final seed = Totp.decodeBase32(rc4DecryptBase64(_seedCipher, _seedRc4Key));
    if (seed.isEmpty) {
      _failed = true;
      return null;
    }
    _cached = seed;
    return seed;
  } catch (_) {
    // 对齐网吧端 D84：解析失败绝不打印明文或密文，连长度都不必留在日志里
    _failed = true;
    return null;
  }
}
