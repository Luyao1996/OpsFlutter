import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netbar_ops_flutter/core/security/builtin_totp_seed.dart';
import 'package:netbar_ops_flutter/core/security/rc4.dart';
import 'package:netbar_ops_flutter/core/security/server_clock.dart';
import 'package:netbar_ops_flutter/core/security/totp.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

void main() {
  group('TOTP — RFC 6238 附录 B 官方测试向量', () {
    // 官方向量的种子就是 ASCII "12345678901234567890"（SHA1 模式，20 字节）
    final seed = utf8.encode('12345678901234567890');

    // Unix 秒 → 期望的 8 位码
    const vectors = <int, String>{
      59: '94287082',
      1111111109: '07081804',
      1111111111: '14050471',
      1234567890: '89005924',
      2000000000: '69279037',
      20000000000: '65353130',
    };

    vectors.forEach((unix, expected8) {
      test('T=$unix', () {
        final t = DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
        expect(Totp.generate(seed: seed, time: t, digits: 8), expected8);
        // 生产用 6 位；同一 binary 取模，6 位结果就是 8 位结果的后 6 位
        expect(
          Totp.generate(seed: seed, time: t, digits: 6),
          expected8.substring(2),
        );
      });
    });

    test('同一时间窗内取值稳定，跨窗即变', () {
      final base = DateTime.fromMillisecondsSinceEpoch(1111111111 * 1000,
          isUtc: true);
      final sameWindow = base.add(const Duration(seconds: 1));
      final nextWindow = base.add(const Duration(seconds: 30));
      expect(
        Totp.generate(seed: seed, time: sameWindow),
        Totp.generate(seed: seed, time: base),
      );
      expect(
        Totp.generate(seed: seed, time: nextWindow),
        isNot(Totp.generate(seed: seed, time: base)),
      );
    });
  });

  group('Base32 解码', () {
    test('与 RFC 4648 一致', () {
      expect(
        Totp.decodeBase32('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),
        utf8.encode('12345678901234567890'),
      );
    });

    test('大小写不敏感、忽略 padding 与空白', () {
      final a = Totp.decodeBase32('GEZDGNBVGY3TQOJQ');
      expect(Totp.decodeBase32('gezdgnbvgy3tqojq'), a);
      expect(Totp.decodeBase32('GEZD GNBV GY3T QOJQ=='), a);
    });

    test('非法字符抛 FormatException', () {
      expect(() => Totp.decodeBase32('GEZD1NBV'), throwsFormatException);
    });
  });

  group('RC4', () {
    test('已知向量 key="Key" / "Plaintext"', () {
      expect(
        _hex(rc4(utf8.encode('Key'), utf8.encode('Plaintext'))),
        'BBF316E8D940AF0AD3',
      );
    });

    test('加解密可逆', () {
      final key = utf8.encode('secret');
      final plain = utf8.encode('GEZDGNBVGY3TQOJQ');
      expect(rc4(key, rc4(key, plain)), plain);
    });
  });

  group('内置种子', () {
    // 只断言形状，绝不断言/打印明文种子 —— 测试报告也是会外泄的载体
    test('可解出 20 字节密钥', () {
      final seed = builtinTotpSeed();
      expect(seed, isNotNull);
      expect(seed!.length, 20);
    });

    test('参数与网吧端一致', () {
      expect(builtinSeedPeriod, 30);
      expect(builtinSeedDigits, 6);
      expect(builtinSeedTolerance, const Duration(seconds: 120));
    });

    test('生成 6 位纯数字码', () {
      final code = Totp.generate(
        seed: builtinTotpSeed()!,
        time: DateTime.utc(2026, 8, 8, 12, 0, 0),
        period: builtinSeedPeriod,
        digits: builtinSeedDigits,
      );
      expect(code, matches(RegExp(r'^\d{6}$')));
    });
  });

  group('HTTP Date 解析', () {
    test('标准 RFC 1123', () {
      expect(
        parseHttpDate('Wed, 21 Oct 2015 07:28:00 GMT'),
        DateTime.utc(2015, 10, 21, 7, 28, 0),
      );
    });

    test('单位数日期', () {
      expect(
        parseHttpDate('Fri, 7 Aug 2026 03:04:05 GMT'),
        DateTime.utc(2026, 8, 7, 3, 4, 5),
      );
    });

    test('无法解析时返回 null 而不是猜一个时间', () {
      expect(parseHttpDate('garbage'), isNull);
      expect(parseHttpDate('Wed, 21 Xxx 2015 07:28:00 GMT'), isNull);
      expect(parseHttpDate(''), isNull);
    });
  });
}
