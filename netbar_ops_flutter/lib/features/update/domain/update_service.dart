import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/logging/webrtc_crash_logger.dart';
import '../data/app_store_lookup_api.dart';
import '../data/installer.dart';
import '../data/installer_factory.dart';
import '../data/update_api.dart';
import '../data/update_downloader.dart';
import '../providers.dart'
    show
        spKeyPinnedBuild,
        spKeyIosLastPromptVersion,
        spKeyIosLastPromptAt,
        spKeyIosSkippedVersion;
import 'models/app_store_check_result.dart';
import 'models/release_info.dart';
import 'models/version_manifest.dart';
import 'update_check_result.dart';

/// SharedPreferences key：本机当前是否运行的是预览版。
/// 由 [UpdateService.check] 拉取 manifest 后写入；UI 启动时读取以决定是否显示 PREVIEW 标签。
const String spKeyIsPreview = 'update.is_preview';

class UpdateService {
  /// 「检查更新」弹窗展示的最近正式版条数。
  static const int _recentReleaseCount = 5;

  final UpdateApi _api;
  final UpdateDownloader _downloader;
  final UpdateInstaller _installer;
  final AppStoreLookupApi _appStoreApi;

  UpdateService({
    UpdateApi? api,
    UpdateDownloader? downloader,
    UpdateInstaller? installer,
    AppStoreLookupApi? appStoreApi,
  })  : _api = api ?? UpdateApi(),
        _downloader = downloader ?? UpdateDownloader(),
        _installer = installer ?? createInstaller(),
        _appStoreApi = appStoreApi ?? AppStoreLookupApi();

  /// 检查更新。所有异常都吞掉，最坏情况返回 skipped。
  ///
  /// 流程：
  /// 1. 拉取 manifest（每次都拉，不走缓存）
  /// 2. 计算 isCurrentPreview = (preview != null && local.build == preview.buildNumber)
  ///    并写入 SharedPreferences（供 UI 离线展示 PREVIEW 标签）
  /// 3. 按身份选候选：
  ///    - 预览版用户 → 只看 preview 字段
  ///    - 正式版用户 → 只看 releases[0]
  /// 4. 比较 build，返回结果
  Future<UpdateCheckResult> check() async {
    try {
      final platform = _currentPlatform();
      if (platform == null) {
        _log('INFO', 'check', 'platform not supported, skip');
        return UpdateCheckResult.skipped();
      }

      final host = await _api.pickFastestHost();
      if (host == null) {
        _log('WARN', 'check', 'no reachable host, skip');
        return UpdateCheckResult.skipped();
      }

      final manifest = await _api.fetchManifest(host);
      if (manifest == null) {
        _log('WARN', 'check', 'fetch manifest failed, skip');
        return UpdateCheckResult.skipped();
      }

      final local = await _localPackageInfo();

      final pm = manifest.forPlatform(platform);
      if (pm == null) {
        _log('INFO', 'check', 'no platform manifest for platform=$platform');
        await _persistIsPreview(false);
        return UpdateCheckResult.upToDate(
          local.version,
          local.build,
          host: host,
        );
      }

      // 1) 算并持久化 isCurrentPreview（无论后续走哪个分支都要做）
      final preview = pm.preview;
      final isCurrentPreview =
          preview != null && local.build == preview.buildNumber;
      await _persistIsPreview(isCurrentPreview);

      // 1.5) 计算最近 N 条正式版（按 uploadTime 倒序），供 UI 展示更新历史
      final sortedByTime = [...pm.releases]
        ..sort((a, b) => b.uploadTime.compareTo(a.uploadTime));
      final recentReleases =
          sortedByTime.take(_recentReleaseCount).toList(growable: false);

      // 1.6) 计算"不论身份"的两个候选，供手动「检查更新」弹窗分区展示。
      //      正式版用户也能在手动检查里主动尝鲜预览版。
      final availableRelease = (pm.latest != null &&
              pm.latest!.buildNumber > local.build)
          ? pm.latest
          : null;
      final availablePreview =
          (preview != null && preview.buildNumber > local.build)
              ? preview
              : null;

      _log('INFO', 'check',
          'localVersion=${local.version} localBuild=${local.build} '
          'isCurrentPreview=$isCurrentPreview '
          'preview=${preview?.buildNumber} '
          'latestRelease=${pm.latest?.buildNumber} '
          'min=${pm.minSupportedBuild}');

      // 2) 按身份选候选
      final ReleaseInfo? candidate;
      final List<ReleaseInfo> changelogs;
      if (isCurrentPreview) {
        // 预览版用户：只看 preview，正式版当不存在
        candidate = preview;
        changelogs = preview != null && preview.buildNumber > local.build
            ? <ReleaseInfo>[preview]
            : const <ReleaseInfo>[];
      } else {
        // 正式版用户：只看 releases，preview 字段被忽略
        candidate = pm.latest;
        changelogs = pm.changelogsSince(local.build);
      }

      if (candidate == null || local.build >= candidate.buildNumber) {
        return UpdateCheckResult.upToDate(
          local.version,
          local.build,
          host: host,
          isCurrentPreview: isCurrentPreview,
          recentReleases: recentReleases,
          availableRelease: availableRelease,
          availablePreview: availablePreview,
        );
      }

      final isForced = candidate.forceUpdate ||
          (!isCurrentPreview && local.build < pm.minSupportedBuild);
      return UpdateCheckResult(
        status: isForced ? UpdateStatus.forced : UpdateStatus.optional,
        latest: candidate,
        aggregatedChangelogs: changelogs,
        host: host,
        localVersion: local.version,
        localBuildNumber: local.build,
        isCurrentPreview: isCurrentPreview,
        recentReleases: recentReleases,
        availableRelease: availableRelease,
        availablePreview: availablePreview,
      );
    } catch (e, st) {
      _log('ERROR', 'check', 'unhandled error=$e stack=$st');
      return UpdateCheckResult.skipped();
    }
  }

  /// 本机当前是否被"安装此版本"固定到 pinned_build。
  /// 启动检查时调用：返回 true → 跳过自动弹窗；返回 false → 正常检查。
  ///
  /// 副作用：如果 SP 里有 pinned 但本地 build 已经不是它了（用户外部装了别的版本），
  /// 会自动清掉 SP 中的 pinned，让自动检查恢复正常。
  Future<bool> isPinnedToCurrentBuild() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final pinned = sp.getInt(spKeyPinnedBuild) ?? 0;
      if (pinned <= 0) return false;
      final local = await _localPackageInfo();
      if (local.build == pinned) return true;
      // 本地已变 → 清掉 pin
      await sp.remove(spKeyPinnedBuild);
      return false;
    } catch (e) {
      _log('WARN', 'isPinnedToCurrentBuild', 'error=$e');
      return false;
    }
  }

  // ===================== iOS App Store 更新检查 =====================
  // iOS 独立路径：不碰 manifest / _downloader / _installer（守住 Apple 2.5.2），
  // 只查 App Store 版本 + 比较 + 跳转。_currentPlatform() 对 iOS 仍返回 null，
  // 确保 iOS 永远不会进入下载安装流程。

  /// 查 App Store 是否有新版本。所有异常吞掉，返回 skipped。
  Future<AppStoreCheckResult> checkAppStore() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version; // CFBundleShortVersionString
      final bundleId = info.packageName; // iOS = CFBundleIdentifier
      if (bundleId.isEmpty) return AppStoreCheckResult.skipped();

      final store = await _appStoreApi.lookup(bundleId);
      if (store == null) {
        _log('INFO', 'checkAppStore', 'lookup empty/failed, skip');
        return AppStoreCheckResult.skipped();
      }

      final newer = _isStoreVersionNewer(store.version, localVersion);
      _log('INFO', 'checkAppStore',
          'local=$localVersion store=${store.version} newer=$newer');
      if (!newer) {
        return AppStoreCheckResult.upToDate(localVersion,
            storeVersion: store.version);
      }

      final url = store.trackViewUrl.isNotEmpty
          ? store.trackViewUrl
          : (store.trackId != null
              ? 'https://apps.apple.com/cn/app/id${store.trackId}'
              : '');
      return AppStoreCheckResult.update(
        localVersion: localVersion,
        storeVersion: store.version,
        storeUrl: url,
        releaseNotes: store.releaseNotes,
      );
    } catch (e) {
      _log('WARN', 'checkAppStore', 'error=$e');
      return AppStoreCheckResult.skipped();
    }
  }

  /// 语义化版本比较：store 是否【严格新于】local。
  /// 必须逐段数值比较，绝不能用字符串 compareTo（否则 1.0.10 < 1.0.9 会被误判）。
  bool _isStoreVersionNewer(String store, String local) {
    List<int> parse(String v) => v
        .trim()
        .split('.')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList(growable: false);
    final a = parse(store);
    final b = parse(local);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// 启动自动检查时调用：该 storeVersion 现在是否应该弹提示。
  /// 规则：用户已"跳过此版本"→否；同一版本一天内已弹过→否；否则是。
  Future<bool> shouldPromptAppStore(String storeVersion) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (sp.getString(spKeyIosSkippedVersion) == storeVersion) return false;
      final lastVer = sp.getString(spKeyIosLastPromptVersion);
      final lastAt = sp.getInt(spKeyIosLastPromptAt) ?? 0;
      if (lastVer == storeVersion) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - lastAt;
        if (elapsed < 24 * 60 * 60 * 1000) return false;
      }
      return true;
    } catch (e) {
      _log('WARN', 'shouldPromptAppStore', 'error=$e');
      return true;
    }
  }

  /// 记录"已对该 storeVersion 弹过启动提示"（用于一天一次节流）。
  Future<void> markAppStorePrompted(String storeVersion) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(spKeyIosLastPromptVersion, storeVersion);
      await sp.setInt(
          spKeyIosLastPromptAt, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      _log('WARN', 'markAppStorePrompted', 'error=$e');
    }
  }

  /// 用户点"稍后/跳过此版本"：记下后该 storeVersion 启动不再自动弹。
  Future<void> skipAppStoreVersion(String storeVersion) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(spKeyIosSkippedVersion, storeVersion);
    } catch (e) {
      _log('WARN', 'skipAppStoreVersion', 'error=$e');
    }
  }

  Future<void> _persistIsPreview(bool isPreview) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(spKeyIsPreview, isPreview);
    } catch (e) {
      _log('WARN', 'persistIsPreview', 'error=$e');
    }
  }

  /// 仅下载并校验，返回下载完成的最终文件。不会触发安装。
  ///
  /// 多源回退：先用调用方选中的 [host]，失败（新源没有该文件 404、网络错、
  /// 校验失败等）时按 新→老 优先级尝试其余源；用户主动取消不回退直接抛出。
  /// 断点续传的 .tmp 跨源续用，最终以 MD5 校验兜底。
  ///
  /// [onPhase] 让 UI 感知 preparing/downloading/verifying 阶段切换；
  /// [onProgress] 用于下载阶段的字节级进度回调。
  Future<File> downloadOnly(
    ReleaseInfo release,
    String host, {
    required DownloadProgress onProgress,
    PhaseCallback? onPhase,
    CancelToken? cancelToken,
  }) async {
    final saveDir = await _downloadDir();
    final fileName = release.path.split('/').last;
    final savePath = '${saveDir.path}${Platform.pathSeparator}$fileName';

    final candidates = <String>[
      host,
      ...UpdateApi.hosts.where((h) => h != host),
    ];

    Object? lastError;
    for (final h in candidates) {
      final url = '$h${release.path}';
      _log('INFO', 'downloadOnly',
          'url=$url save=$savePath size=${release.size}');
      try {
        return await _downloader.download(
          url: url,
          savePath: savePath,
          expectedMd5: release.md5,
          expectedSize: release.size,
          onProgress: onProgress,
          cancelToken: cancelToken,
          onPhase: onPhase,
        );
      } catch (e) {
        if (e is DioException && e.type == DioExceptionType.cancel) rethrow;
        lastError = e;
        _log('WARN', 'downloadOnly', 'host=$h failed: $e, try next');
      }
    }
    throw lastError ?? UpdateDownloadException('没有可用的下载源');
  }

  /// 触发安装。Windows 启动 setup.exe 后主程序会 exit(0)；
  /// Android 拉起系统安装页。
  Future<void> install(File file) => _installer.install(file);

  /// 下载并安装。保留作为旧调用方的兼容入口。
  /// 新代码建议用 [downloadOnly] + [install]，可在中间插入"显示路径"等 UI 交互。
  Future<void> downloadAndInstall(
    ReleaseInfo release,
    String host, {
    required DownloadProgress onProgress,
    PhaseCallback? onPhase,
    CancelToken? cancelToken,
  }) async {
    final file = await downloadOnly(
      release,
      host,
      onProgress: onProgress,
      onPhase: onPhase,
      cancelToken: cancelToken,
    );
    await install(file);
  }

  // -------- helpers --------

  String? _currentPlatform() {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return null;
  }

  Future<({String version, int build})> _localPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return (
        version: info.version,
        build: int.tryParse(info.buildNumber) ?? 0,
      );
    } catch (e) {
      _log('WARN', 'localPackageInfo', 'error=$e');
      return (version: '', build: 0);
    }
  }

  Future<Directory> _downloadDir() async {
    Directory base;
    if (Platform.isAndroid) {
      base = await getApplicationSupportDirectory();
    } else {
      final tmp = await getTemporaryDirectory();
      base = tmp;
    }
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  void _log(String level, String op, String msg) {
    WebRtcCrashLogger.I.log(level, 'update', op, '-', msg);
  }
}
