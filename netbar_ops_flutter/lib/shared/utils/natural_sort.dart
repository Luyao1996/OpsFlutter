/// 列表 / 表格排序的公共比较器 —— 移植自 toolboxPage `src/utils/sort.js`。
///
/// 三处在用：镜像管理表格、进程管理列表、游戏管理列表。它们的共同点是「字段混着
/// 数字和带数字的字符串」（机号 T9/T10、IP 192.168.1.9/.10、进程名、游戏名），
/// 默认的字符串比较会把 T10 排到 T9 前面，所以统一走自然序。
///
/// ⚠️ 与 web 的一处已知差异：web 用 `Intl.Collator('zh-CN', {numeric:true})`，
/// 中文按拼音排；Dart 没有 Collator，项目也没有拼音依赖（见 game_library/utils/
/// pinyin_match.dart 的说明），所以**纯中文串按 UTF-16 码位序**，与 web 顺序不同。
/// 数字、字母、机号、IP、大小、时间这些主力字段的结果与 web 完全一致。
library;

/// element-plus 口径的排序方向；null 表示不排序，列表原样返回。
enum SortOrder { ascending, descending }

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// 无值判定：null / '' 都算没有值
bool isEmptySortValue(Object? v) => v == null || (v is String && v.isEmpty);

/// 自然序字符串比较：'T9' < 'T10'、'192.168.1.9' < '192.168.1.10'
///
/// 逐段扫描：两边同时是数字就整段取出按数值比（去前导零后先比位数再比字典序，
/// 避免超长数字 int.parse 溢出），否则按字符比（大小写不敏感，对齐 web 的
/// sensitivity:'base'）。
int naturalCompare(Object? a, Object? b) {
  final sa = a?.toString() ?? '';
  final sb = b?.toString() ?? '';
  var i = 0;
  var j = 0;
  while (i < sa.length && j < sb.length) {
    final ca = sa.codeUnitAt(i);
    final cb = sb.codeUnitAt(j);
    if (_isDigit(ca) && _isDigit(cb)) {
      final si = i;
      final sj = j;
      while (i < sa.length && _isDigit(sa.codeUnitAt(i))) {
        i++;
      }
      while (j < sb.length && _isDigit(sb.codeUnitAt(j))) {
        j++;
      }
      // 去前导零：'007' 与 '7' 数值相等，位数不同不能直接比长度
      final na = sa.substring(si, i).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final nb = sb.substring(sj, j).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (na.length != nb.length) return na.length - nb.length;
      final c = na.compareTo(nb);
      if (c != 0) return c;
    } else {
      final c = String.fromCharCode(ca)
          .toLowerCase()
          .compareTo(String.fromCharCode(cb).toLowerCase());
      if (c != 0) return c;
      i++;
      j++;
    }
  }
  // 前缀相同则短的在前
  return (sa.length - i) - (sb.length - j);
}

/// 通用值比较：布尔按 false < true，两边都是有限数字按数值比，其余按自然序
int compareValues(Object? a, Object? b) {
  if (a is bool || b is bool) {
    return ((a == true) ? 1 : 0) - ((b == true) ? 1 : 0);
  }
  final na = a is num ? a.toDouble() : double.tryParse(a?.toString() ?? '');
  final nb = b is num ? b.toDouble() : double.tryParse(b?.toString() ?? '');
  if (na != null && na.isFinite && nb != null && nb.isFinite) {
    return na.compareTo(nb);
  }
  return naturalCompare(a, b);
}

/// 按 getter 取值排序，返回新列表（不改原列表）
///
/// [getter] 返回 null / '' 表示该行此字段无值 —— 无值恒沉底（升降序都一样），
/// 否则按「已配置镜像」降序时，一屏全是「未配置」。
List<T> sortByGetter<T>(
  List<T> list,
  Object? Function(T) getter,
  SortOrder? order, {
  int Function(Object? a, Object? b) compare = compareValues,
}) {
  if (order == null) return list;
  final dir = order == SortOrder.descending ? -1 : 1;
  final out = [...list];
  out.sort((a, b) {
    final va = getter(a);
    final vb = getter(b);
    if (isEmptySortValue(va) && isEmptySortValue(vb)) return 0;
    if (isEmptySortValue(va)) return 1;
    if (isEmptySortValue(vb)) return -1;
    return dir * compare(va, vb);
  });
  return out;
}
