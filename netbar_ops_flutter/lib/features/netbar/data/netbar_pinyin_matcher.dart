import 'netbar_api.dart';

/// 网吧关键词模糊匹配，三级主策略 + ID/Token/分组兜底。
///
/// 主策略顺序（对齐搜索框 placeholder "搜索名称、ID、拼音或Token..."）：
/// 1) name 子串
/// 2) pinyin_full 子串（后端下发的全拼）
/// 3) pinyin 子串（后端下发的首字母）
///
/// 兜底：id / token / groups[].name 子串。
/// 所有比较在 lower-case 下进行；空关键词视为匹配通过。
class NetbarMatcher {
  static bool match(Netbar row, String keyword) {
    final kw = keyword.trim().toLowerCase();
    if (kw.isEmpty) return true;

    if (row.name.toLowerCase().contains(kw)) return true;

    final full = row.pinyinFull;
    if (full != null && full.isNotEmpty && full.toLowerCase().contains(kw)) {
      return true;
    }

    final initials = row.pinyin;
    if (initials != null && initials.isNotEmpty && initials.toLowerCase().contains(kw)) {
      return true;
    }

    if (row.id.toString().contains(kw)) return true;
    if (row.token.toLowerCase().contains(kw)) return true;

    final groups = row.groups;
    if (groups != null) {
      for (final g in groups) {
        if (g.name.toLowerCase().contains(kw)) return true;
      }
    }

    return false;
  }
}
