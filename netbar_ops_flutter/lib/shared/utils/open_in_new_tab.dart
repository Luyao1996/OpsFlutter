import 'open_in_new_tab_stub.dart'
    if (dart.library.html) 'open_in_new_tab_web.dart' as impl;

void openInNewTab(String url) => impl.openInNewTab(url);

/// Build a full URL for a GoRouter location.
///
/// Supports both hash-based (default Flutter web) and path-based strategies.
String buildWebUrlForLocation(String location) =>
    impl.buildWebUrlForLocation(location);

