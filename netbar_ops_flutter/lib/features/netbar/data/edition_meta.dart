import 'dart:ui';

/// 更新通道（版本类型）元数据
/// 对齐 web NetbarPage.vue 的 EDITION_OPTIONS / getEditionLabel / getEditionTagType
class EditionMeta {
  final String value;
  final String label;

  /// 对应 element-plus tag type 的项目惯例配色：
  /// 灰 info / 橙 warning（同 top_notice warning 色）/ 蓝 primary（AppColors.iosBlue）
  /// / 绿 success（同 netbar_multi_select_table 在线色）
  final Color color;

  const EditionMeta({
    required this.value,
    required this.label,
    required this.color,
  });
}

/// 可选通道（版本筛选下拉 / 单网吧更新选通道下拉共用），顺序与 web 一致；
/// Go 版通道值与批量更新弹窗的 'gorelease' 保持一致
const List<EditionMeta> kEditionOptions = [
  EditionMeta(value: 'check', label: '技术版', color: Color(0xFF909399)),
  EditionMeta(value: 'debug', label: '内测版', color: Color(0xFFF59E0B)),
  EditionMeta(value: 'beta', label: '公测版', color: Color(0xFF007AFF)),
  EditionMeta(value: 'release', label: '正式版', color: Color(0xFF16A34A)),
  EditionMeta(value: 'gorelease', label: 'Go版', color: Color(0xFFDC2626)),
];

EditionMeta? _find(String? edition) {
  if (edition == null || edition.isEmpty) return null;
  for (final m in kEditionOptions) {
    if (m.value == edition) return m;
  }
  return null;
}

/// 配置外的非空值原样返回，防止未知通道被误标成已知版本（对齐 web `|| edition`）
String editionLabel(String? edition) {
  if (edition == null || edition.isEmpty) return '';
  return _find(edition)?.label ?? edition;
}

/// 未知通道回退灰（对齐 web getEditionTagType 的 `|| 'info'`）
Color editionTagColor(String? edition) =>
    _find(edition)?.color ?? const Color(0xFF909399);
