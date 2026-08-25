import '../../../core/network/api_client.dart';
import 'startup_monitor_models.dart';

// T8c-0：本文件从 startup_item_api.dart 拆出。
// 原因：startup_item_api.dart 整体搬去了 features/strategy（策略共享层），
// 而启动项监控走的是 /channel 监控接口、依赖 channel 自己的 startup_monitor_models，
// 与策略数据层无关；跟着搬会让 strategy 反向依赖 channel。逻辑一字未改。

/// 启动项监控 API - 使用 /channel 接口
class StartupItemMonitorApi {
  final ApiClient _client = ApiClient.instance;

  Future<List<NetbarMonitorData>> getMonitor({String? keyword}) async {
    final params = <String, dynamic>{
      'page': 1,
      'size': 100,
      'type': 'merchant',
    };
    if (keyword != null && keyword.isNotEmpty) {
      params['keyword'] = keyword;
    }

    final response = await _client.get('/channel', queryParameters: params);
    final data = response.data;

    // 解析 paginator.data
    List<dynamic> merchantList = [];
    if (data is Map<String, dynamic>) {
      final paginator = data['paginator'] as Map<String, dynamic>?;
      if (paginator != null) {
        final raw = paginator['data'];
        if (raw is List) {
          merchantList = raw;
        } else if (raw is Map) {
          // 后端单条数据时可能返回 Map 而非 List
          merchantList = [raw];
        }
      }
    }

    return merchantList
        .map((e) => NetbarMonitorData.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
