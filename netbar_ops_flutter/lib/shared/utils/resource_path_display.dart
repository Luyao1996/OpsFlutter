String zoneLabelFromCode(String zone) {
  switch (zone.toUpperCase()) {
    case 'HEADQUARTERS':
      return '总公司资源';
    case 'BRANCH':
      return '分公司资源';
    case 'SHARED':
      return '共享区资源';
    case 'PUBLIC':
      return '本网吧资源';
    default:
      return zone;
  }
}

String? detectZoneFromPath(String fullPath) {
  if (fullPath.isEmpty) return null;
  var p = fullPath.replaceAll('\\', '/');
  if (p.startsWith('/')) p = p.substring(1);
  final upper = p.toUpperCase();
  const prefixes = ['HEADQUARTERS/', 'BRANCH/', 'SHARED/', 'PUBLIC/'];
  for (final pre in prefixes) {
    if (upper.startsWith(pre)) {
      return pre.substring(0, pre.length - 1);
    }
  }
  return null;
}

String stripZonePrefix(String fullPath) {
  if (fullPath.isEmpty) return fullPath;
  var p = fullPath.replaceAll('\\', '/');
  if (p.startsWith('/')) p = p.substring(1);
  final upper = p.toUpperCase();
  const prefixes = ['HEADQUARTERS/', 'BRANCH/', 'SHARED/', 'PUBLIC/'];
  for (final pre in prefixes) {
    if (upper.startsWith(pre)) {
      p = p.substring(pre.length);
      break;
    }
  }
  return p;
}

String formatPathWithZone(
  String fullPath,
  String zone, {
  int keepSegments = 2,
  int maxLength = 32,
}) {
  final label = zoneLabelFromCode(zone);
  final rel = stripZonePrefix(fullPath);
  if (rel.isEmpty) return label;

  final combined = '$label / $rel';
  if (combined.length <= maxLength) return combined;

  final parts = rel.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return label;
  final tail = parts.length <= keepSegments
      ? parts.join('/')
      : parts.sublist(parts.length - keepSegments).join('/');
  return '$label / .../$tail';
}

String deriveDirectoryFromPath(String fullPath) {
  if (fullPath.isEmpty) return '';
  final normalized = fullPath.replaceAll('\\', '/');
  final idx = normalized.lastIndexOf('/');
  if (idx <= 0) return '';
  return normalized.substring(0, idx);
}
