import 'dart:html' as html;

void openInNewTab(String url) {
  html.window.open(url, '_blank', 'noopener');
}

String buildWebUrlForLocation(String location) {
  final base = Uri.base;
  final normalized = location.startsWith('/') ? location : '/$location';
  if (base.fragment.isNotEmpty) {
    return base.replace(fragment: normalized, query: '').toString();
  }
  return base.replace(path: normalized, fragment: '', query: '').toString();
}

