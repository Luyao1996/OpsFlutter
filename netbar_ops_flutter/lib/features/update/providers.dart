import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

/// 同步访问 SharedPreferences 的入口。`main()` 启动时必须先调用
/// [ensureInitialized] 一次，之后 UI 同步线程才能用 [instance]。
class SharedPreferencesHolder {
  SharedPreferencesHolder._();
  static SharedPreferences? _instance;

  static Future<SharedPreferences> ensureInitialized() async {
    _instance ??= await SharedPreferences.getInstance();
    return _instance!;
  }

  static SharedPreferences get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
        'SharedPreferencesHolder 未初始化，请在 main() 中先 await ensureInitialized()',
      );
    }
    return i;
  }
}

/// 本机当前是否运行的是预览版。
///
/// - 启动初始值：从 SharedPreferences 同步读取上次缓存值（无网时也能用）。
/// - 后续：由 [UpdateService.check] 拉取 manifest 后通过 `ref.read(...).state = x` 更新。
final isPreviewProvider = StateProvider<bool>((ref) {
  try {
    return SharedPreferencesHolder.instance.getBool(spKeyIsPreview) ?? false;
  } catch (_) {
    return false;
  }
});
