import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/app_providers.dart';
import '../../netbar/data/netbar_list_provider.dart';
import '../data/application_api.dart';

/// 应用中心 / 应用策略 API Provider
final applicationApiProvider = Provider<ApplicationApi>((ref) => ApplicationApi());

/// 当前网吧所属分组 id（应用引用/策略接口的 group_id 维度）。
///
/// 与 Web 端 RemoteWakePage.vue currentGroupId 同构：按当前网吧 id 从
/// 网吧列表取 groups[0].id（Web 取自 MERCHANTS_SNAPSHOT 快照，这里取自
/// netbarListProvider，终端详情独立子窗口内会自行发一次 /merchant 请求）。
final currentGroupIdProvider = FutureProvider.autoDispose<int?>((ref) async {
  final netbarId = ref.watch(currentNetbarIdProvider);
  if (netbarId == null) return null;
  final list = await ref.watch(netbarListProvider.future);
  for (final n in list.merchants) {
    if (n.id == netbarId) {
      final groups = n.groups;
      return (groups != null && groups.isNotEmpty) ? groups.first.id : null;
    }
  }
  return null;
});
