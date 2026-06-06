import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

/// SharedPreferences key：用户主动通过"安装此版本"固定到的 buildNumber。
/// 0 / 未设置表示未固定，启动时正常检查更新；
/// 非 0 时启动检查会判断 local.build == 此值则跳过自动弹窗（手动检查不受影响）。
const String spKeyPinnedBuild = 'update.pinned_build';

/// iOS App Store 更新检查的节流/跳过状态（仅 iOS 用，与上面的下载安装体系无关）：
/// - [spKeyIosLastPromptVersion] / [spKeyIosLastPromptAt]：上次"启动自动提示"的 storeVersion 与时间戳，
///   用于同一版本一天最多自动弹一次；
/// - [spKeyIosSkippedVersion]：用户点"稍后/跳过此版本"时记下的 storeVersion，该版本启动不再自动弹。
/// 三者都以 storeVersion 字符串为准，App Store 发新版后旧记录自然失效，不会永久静音。
const String spKeyIosLastPromptVersion = 'update.ios_last_prompt_version';
const String spKeyIosLastPromptAt = 'update.ios_last_prompt_at';
const String spKeyIosSkippedVersion = 'update.ios_skipped_version';

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

/// 本机当前是否被"安装此版本"固定到某个 build（启动不自动弹更新）。
///
/// - 初始值：SP 里 [spKeyPinnedBuild] > 0 即视为锁定（同步读，无网也能展示）。
/// - 精确校正：`main()` 启动检查会用 [UpdateService.isPinnedToCurrentBuild]
///   校验 local.build 是否仍等于 pinned，并把结果同步回此 provider，
///   纠正"外部装了别的版本但 SP 残留 pin"的误判。
final isPinnedProvider = StateProvider<bool>((ref) {
  try {
    return (SharedPreferencesHolder.instance.getInt(spKeyPinnedBuild) ?? 0) > 0;
  } catch (_) {
    return false;
  }
});
