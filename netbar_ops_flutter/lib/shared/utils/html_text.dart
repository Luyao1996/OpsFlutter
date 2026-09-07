/// 富文本备注（后端存的是 HTML 串）转纯文本。
///
/// 终端备注在卡片角标、备注搜索、列表预览三处都要以纯文本出现，统一走这里。
/// 只做「去标签 + 反转义常见实体 + 合并空白」，不追求完整的 HTML 解析：
/// 备注由 quill 编辑器产出，结构简单（p / br / strong 之类）。
String stripHtml(String? html) {
  if (html == null || html.isEmpty) return '';
  var text = html
      // 块级标签之间补一个空格，否则 "<p>a</p><p>b</p>" 会粘成 "ab"
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'</(p|div|li|h[1-6])>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), '');
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      // &amp; 必须最后换，否则 "&amp;lt;" 会被二次解成 "<"
      .replaceAll('&amp;', '&');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
