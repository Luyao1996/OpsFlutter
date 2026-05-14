/// 搜索关键词匹配。
///
/// 当前实现：substring（大小写不敏感）。
///
/// 与 Web 端 `pinyin-pro` 的全拼/首字母连续匹配相比，本实现暂未覆盖
/// "yzdj → 原神大军" 这类纯 ASCII 关键词命中中文名的能力。
/// 若后续需要，请加入 `lpinyin` 依赖并在此扩展。预留接口签名兼容。
bool matchKeyword(String? text, String keyword) {
  if (text == null || text.isEmpty || keyword.isEmpty) return false;
  return text.toLowerCase().contains(keyword);
}

/// 关键词是否"看起来像拼音"（纯 ASCII 字母/数字，长度 >= 2）。
/// 当前未启用拼音匹配，但保留判定供未来扩展。
final RegExp _asciiLetters = RegExp(r'^[a-z0-9]+$', caseSensitive: false);
bool keywordLooksLikePinyin(String keyword) =>
    keyword.length >= 2 && _asciiLetters.hasMatch(keyword);
