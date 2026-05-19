import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'netbar_api.dart';

/// 网吧列表唯一数据源。
///
/// 合并自原先两个同名 `netbarListProvider`（netbar_list_page.dart 的
/// `List<Netbar>` 版 + netbar_selector_modal.dart 的 `NetbarListResponse` 版），
/// 统一返回完整响应（merchants + groups + summary），消除同一份 `/merchant`
/// 被两个独立 provider 各拉一次的重复请求。
///
/// 缓存策略保持 `autoDispose`（与合并前完全一致，本次未改动 P0-3 缓存策略）。
final netbarListProvider = FutureProvider.autoDispose<NetbarListResponse>(
  (ref) async => NetbarApi().getListFull(),
);
