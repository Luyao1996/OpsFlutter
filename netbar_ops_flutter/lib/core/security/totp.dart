import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// RFC 6238 TOTP 生成器，与网吧端 `internal/pkg/crypto/auth2fa.go` 同构：
/// base32 种子 → 计数器大端 8 字节 → HMAC-SHA1 → RFC 4226 动态截断 → 取模左补零。
///
/// 时间由调用方注入（[generate] 的 time 参数），不读全局时钟 —— 离线场景要用
/// [ServerClock] 校准过的时间，不能直接用 `DateTime.now()`。
class Totp {
  const Totp._();

  /// RFC 4648 Base32 字母表。
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// 解码 base32 种子。大小写不敏感，忽略 `=` padding 与空白字符。
  static Uint8List decodeBase32(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s=]'), '');
    var buffer = 0;
    var bits = 0;
    final out = <int>[];
    for (var i = 0; i < s.length; i++) {
      final idx = _alphabet.indexOf(s[i]);
      if (idx < 0) {
        throw FormatException('非法的 base32 字符（位置 $i）');
      }
      buffer = (buffer << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xFF);
      }
    }
    return Uint8List.fromList(out);
  }

  /// 按时间生成 TOTP 码。
  ///
  /// [seed] 是 base32 解码后的原始密钥字节（内置种子为 20 字节）。
  /// [period] 与 [digits] 必须与验证端一致，差一个就永远算不对。
  static String generate({
    required List<int> seed,
    required DateTime time,
    int period = 30,
    int digits = 6,
  }) {
    if (period <= 0) throw ArgumentError('period 必须为正数');
    final counter = time.millisecondsSinceEpoch ~/ 1000 ~/ period;
    return generateForCounter(seed: seed, counter: counter, digits: digits);
  }

  /// 按计数器生成（HOTP，RFC 4226）。TOTP 只是把计数器定义成时间片序号。
  static String generateForCounter({
    required List<int> seed,
    required int counter,
    int digits = 6,
  }) {
    if (seed.isEmpty) throw ArgumentError('种子不能为空');
    if (digits < 1 || digits > 9) throw ArgumentError('digits 必须在 1..9');

    // 计数器 → 大端 8 字节
    final msg = Uint8List(8);
    var c = counter;
    for (var i = 7; i >= 0; i--) {
      msg[i] = c & 0xFF;
      c >>= 8;
    }

    final hash = Hmac(sha1, seed).convert(msg).bytes;

    // RFC 4226 动态截断：末字节低 4 位作偏移，取 4 字节并屏蔽符号位
    final offset = hash[hash.length - 1] & 0x0F;
    final binary = ((hash[offset] & 0x7F) << 24) |
        ((hash[offset + 1] & 0xFF) << 16) |
        ((hash[offset + 2] & 0xFF) << 8) |
        (hash[offset + 3] & 0xFF);

    return (binary % _pow10(digits)).toString().padLeft(digits, '0');
  }

  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }
}
