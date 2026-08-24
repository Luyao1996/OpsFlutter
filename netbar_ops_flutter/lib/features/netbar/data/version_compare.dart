// 网吧客户端版本号解析与比较。
//
// 与 toolboxPage `stores/merchant.js` 的 parseVersion / compareVersion 语义严格一致，
// 保证 Flutter 端与 Web 端的版本号下拉排序结果完全相同。

/// 解析 `v1.2.3` / `1.2.3.4` → `[1,2,3,4]`；空值、或首段不是数字时返回 null。
///
/// 缺失的段补 0，返回值固定 4 个元素；正则不加 `$`，允许 `1.2.3-beta` 这类后缀被忽略。
List<int>? parseVersion(String? v) {
  if (v == null || v.isEmpty) return null;
  final s = v.replaceFirst(RegExp(r'^v', caseSensitive: false), '');
  final m = RegExp(r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\.(\d+))?').firstMatch(s);
  if (m == null) return null;
  return List<int>.generate(4, (i) => int.tryParse(m.group(i + 1) ?? '') ?? 0);
}

/// 逐段比较版本号。
///
/// 无法解析的版本（null / 空串 / 非法格式）始终排在最后，不随 [desc] 反转——
/// 否则降序时一堆没上报版本号的网吧会顶到列表最前面。
int compareVersion(String? a, String? b, {bool desc = false}) {
  final va = parseVersion(a);
  final vb = parseVersion(b);
  if (va == null && vb == null) return 0;
  if (va == null) return 1;
  if (vb == null) return -1;
  var diff = 0;
  for (var i = 0; i < 4; i++) {
    diff = va[i] - vb[i];
    if (diff != 0) break;
  }
  return desc ? -diff : diff;
}
