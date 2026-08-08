import 'dart:convert';
import 'dart:typed_data';

/// RC4 流密码，与网吧端 `RC4To` / `RC4Base64` 同构。
///
/// ⚠️ RC4 早已被认为不安全，这里存在的唯一理由是要和既有的网吧端实现对齐
/// （内置 TOTP 种子、secret.dat 都是这么加的）。不要用于任何新的保密用途。
Uint8List rc4(List<int> key, List<int> data) {
  if (key.isEmpty) throw ArgumentError('RC4 密钥不能为空');

  final s = List<int>.generate(256, (i) => i);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) & 0xFF;
    final tmp = s[i];
    s[i] = s[j];
    s[j] = tmp;
  }

  final out = Uint8List(data.length);
  var i = 0;
  j = 0;
  for (var k = 0; k < data.length; k++) {
    i = (i + 1) & 0xFF;
    j = (j + s[i]) & 0xFF;
    final tmp = s[i];
    s[i] = s[j];
    s[j] = tmp;
    out[k] = data[k] ^ s[(s[i] + s[j]) & 0xFF];
  }
  return out;
}

/// base64 密文 → RC4 解密 → UTF-8 明文（对应网吧端的 RC4Base64 解密方向）。
String rc4DecryptBase64(String cipherBase64, String key) {
  final bytes = base64Decode(cipherBase64);
  return utf8.decode(rc4(utf8.encode(key), bytes));
}
