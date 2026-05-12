// ============================================================================
// TODO: 验证完崩溃日志机制后整个 lib/features/debug/ 目录可以删除
//       同时移除 user_profile_dialog.dart 里的 _buildCrashTestButton 入口
// ============================================================================
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/logging/webrtc_crash_logger.dart';

/// 崩溃测试 BottomSheet
///
/// 用途：验证 main.dart 的崩溃捕获 + WebRtcCrashLogger 的同步落盘机制
/// 在用户真实设备（含 HarmonyOS）能否真正抓到崩溃前最后一刻的日志。
class CrashTestSheet extends StatelessWidget {
  const CrashTestSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CrashTestSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFAFAFA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(LucideIcons.bug, size: 20, color: Color(0xFFEA580C)),
                  SizedBox(width: 8),
                  Text(
                    '崩溃测试（开发者）',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: Text(
                '点击下方任一测试，APP 可能会闪退。重启后到"导出崩溃日志"分享给开发者。',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  _CrashTestCard(
                    title: '1. Dart 同步 throw',
                    desc: '直接 throw Exception。预期：APP 不崩，日志写入 (FlutterError + Zone 捕获)。',
                    expected: '不崩',
                    onTap: () => _fireWith(context, _fireSyncThrow),
                  ),
                  _CrashTestCard(
                    title: '2. Dart 异步 throw',
                    desc: 'Future(() => throw)。预期：APP 不崩，日志写入 (PlatformDispatcher + Zone)。',
                    expected: '不崩',
                    onTap: () => _fireWith(context, _fireAsyncThrow),
                  ),
                  _CrashTestCard(
                    title: '3. Widget build 时 throw',
                    desc: '跳转到一个 build 时抛异常的页面。预期：红屏错误页，日志写入 (FlutterError)。',
                    expected: '红屏',
                    onTap: () => _fireBuildThrow(context),
                  ),
                  _CrashTestCard(
                    title: '4. Stack overflow（无限递归）',
                    desc: '递归调用自身，栈溢出。预期：APP 进程被杀。',
                    expected: '崩 ⚠',
                    isHard: true,
                    onTap: () => _fireWith(context, _fireStackOverflow),
                  ),
                  _CrashTestCard(
                    title: '5. OOM 内存耗尽',
                    desc: '持续分配 100MB 大块直到 LMK 杀进程。预期：APP 进程被杀。',
                    expected: '崩 ⚠',
                    isHard: true,
                    onTap: () => _fireWith(context, _fireOom),
                  ),
                  _CrashTestCard(
                    title: '6. Native SIGSEGV ⭐',
                    desc: 'dart:ffi 解引用 nullptr。预期：APP 进程被杀（与华为 Mate X6 崩溃同类型）。',
                    expected: '崩 ⚠⚠',
                    isHard: true,
                    onTap: () => _fireWith(context, _fireNativeSegfault),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 二次确认 + 写"测试入口"日志后调用 fn
  Future<void> _fireWith(BuildContext context, void Function() fn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认触发崩溃测试？'),
        content: const Text('这会主动触发一次崩溃用于验证日志机制，APP 可能会闪退。\n崩溃前会写入"prep + fire"两条日志，重启后可在"导出崩溃日志"取出。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEA580C)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认触发'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'user_confirm', '-',
        'user confirmed crash test, about to call test function');
    fn();
  }

  // ----------------------------- 各场景实现 -----------------------------

  static void _fireSyncThrow() {
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'sync_throw', '-', 'prep: sync throw');
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'sync_throw', '-', 'fire: throwing now');
    throw Exception('[crash_test] sync throw via button');
  }

  static void _fireAsyncThrow() {
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'async_throw', '-', 'prep: async throw');
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'async_throw', '-', 'fire: scheduling unawaited Future');
    // ignore: unawaited_futures, discarded_futures
    Future(() {
      throw Exception('[crash_test] async throw via button');
    });
  }

  static void _fireBuildThrow(BuildContext context) {
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'build_throw', '-', 'prep: navigating to CrashOnBuildPage');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _CrashOnBuildPage()),
    );
  }

  static void _fireStackOverflow() {
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'stack_overflow', '-', 'prep: stack overflow');
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'stack_overflow', '-', 'fire: starting infinite recursion');
    _recurse(0);
  }

  static int _recurse(int n) => _recurse(n + 1);

  static void _fireOom() {
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'oom', '-', 'prep: oom');
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'oom', '-', 'fire: allocating 100MB chunks until LMK');
    final list = <Uint8List>[];
    while (true) {
      list.add(Uint8List(100 * 1024 * 1024));
      WebRtcCrashLogger.I.log(
          'INFO', 'crash_test', 'oom', '-', 'allocated=${list.length * 100}MB count=${list.length}');
    }
  }

  static void _fireNativeSegfault() {
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'native_sigsegv', '-', 'prep: native sigsegv via ffi nullptr');
    WebRtcCrashLogger.I.log('FATAL', 'crash_test', 'native_sigsegv', '-', 'fire: deref nullptr now');
    final ptr = ffi.Pointer<ffi.Int32>.fromAddress(0);
    // 读取 0 地址 -> SIGSEGV
    // ignore: unused_local_variable
    final v = ptr.value;
  }
}

class _CrashTestCard extends StatelessWidget {
  final String title;
  final String desc;
  final String expected;
  final bool isHard;
  final VoidCallback onTap;

  const _CrashTestCard({
    required this.title,
    required this.desc,
    required this.expected,
    required this.onTap,
    this.isHard = false,
  });

  @override
  Widget build(BuildContext context) {
    final tagColor = isHard ? const Color(0xFFDC2626) : const Color(0xFF2563EB);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tagColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      expected,
                      style: TextStyle(fontSize: 11, color: tagColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                desc,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 仅用于"3. Widget build 时 throw"测试。
class _CrashOnBuildPage extends StatelessWidget {
  const _CrashOnBuildPage();

  @override
  Widget build(BuildContext context) {
    WebRtcCrashLogger.I.log(
        'FATAL', 'crash_test', 'build_throw', '-', 'fire: throwing in build()');
    throw Exception('[crash_test] build throw via _CrashOnBuildPage');
  }
}
