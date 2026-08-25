import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/top_notice.dart';
import '../data/channel_v2_api.dart';
import '../data/channel_v2_models.dart';

/// ChannelV2 文件操作层（移植 web composables/channel-v2/useFileActions.js
/// + ChannelV2Page.vue 的 delete / move / distribute / unzip 分发段）。
///
/// 三种批量操作的并发口径**照抄 web，不做统一**（每种都有各自的事故背景）：
///   - 删除：并发（Promise.allSettled → Future.wait），失败文案不带后端 message
///   - 移动：串行 for（同批移进同一目录与后端建目录竞态同类），失败带去重聚合的 message
///   - 下发：并发；拖拽下发带 message，右键「复制 N 项到下发区」不带 message
/// 任何"顺手统一成一种写法"的改动都是行为偏离。

/// 统一取错误文案：ApiError.toString() 即后端 message；其余异常退回 toString。
String v2ErrMessage(Object e, String fallback) {
  if (e is ApiError) return e.message.isNotEmpty ? e.message : fallback;
  final s = e.toString();
  return s.isEmpty ? fallback : s;
}

void _log(String operType, String message) {
  debugPrint(
      '[${DateTime.now().toIso8601String()}][WARN][channel_v2][$operType][-] $message');
}

// ==================== 继承节点守卫 ====================

/// 继承节点只读守卫：批量集合里**只要含继承项就整体拒绝**
/// （逐行移植 ChannelV2Page.vue:469-485 blockIfInherited）。
///
/// 与 `canWriteForFile` 的 inherited 判断是**两层**，不是冗余：
/// 前者只管被右键的那一个文件（决定菜单项是否置灰），本函数管整个批量集合
/// （右键的那个可写、但选中集合里混进了继承项时，菜单不会置灰，必须在这里拦）。
///
/// 返回 true = 已拦截并提示，调用方应中止。
bool v2BlockIfInherited(
  List<V2File> files, {
  String action = '操作',
  required void Function(String message) warn,
}) {
  final count = files.where((f) => f.inherited).length;
  if (count == 0) return false;
  warn(count == files.length
      ? '继承自上级的文件只能查看，不能$action'
      : '选中项中有 $count 个继承自上级的文件，只能查看，请取消选择后再$action');
  return true;
}

// ==================== 删除 ====================

/// 危险操作二次确认（对齐 web ElMessageBox.confirm 的 warning 型）
Future<bool> v2ConfirmDanger(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(message, style: const TextStyle(fontSize: 13, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r == true;
}

/// 【对 web 的刻意偏离，留痕（S11 安全增强）】
/// web 的删除确认文案只说"此操作不可撤销"，没提文件夹会连带内容。
/// 后端 /file/destroy 对文件夹是否递归删除**未验证**，但两种可能里
/// "递归删且用户不知情"是不可逆损失，故选中项含文件夹时补一句强提示。
String _folderWarnSuffix(List<V2File> files) {
  final folders = files.where((f) => f.isFolder).length;
  if (folders == 0) return '';
  if (files.length == 1) return '\n\n该文件夹将连同其中内容一并删除。';
  return '\n\n其中含 $folders 个文件夹，将连同文件夹内的内容一并删除。';
}

/// 取删除用的 id。
///
/// 【M6 刻意偏离，留痕】web 用 `f.delivery_id ?? f.id` 兜底
/// （useFileActions.js:45,79）：下发节点缺 delivery_node_id 时会把**源文件 id**
/// 发给 `DELETE /delivery/{id}`，两个 id 空间重叠即删掉别人的下发记录（数据损坏）。
/// 这里不兜底：为 null 直接判该项失败并记日志。
int? _deleteIdOf(V2File f, String zoneKey) {
  if (zoneKey == 'distribution') {
    if (f.deliveryNodeId == null) {
      _log('delete',
          'delivery node missing delivery_node_id, refuse to fall back to group_file_id=${f.id} name=${f.name}');
      return null;
    }
    return f.deliveryNodeId;
  }
  return f.groupFileId;
}

/// 单文件删除：二次确认 + 按区分流（资源文件 vs 下发记录）
/// （移植 useFileActions.js:66-91）。返回是否删除成功。
Future<bool> v2ConfirmAndDelete(
  BuildContext context, {
  required ChannelV2Api api,
  required V2File file,
  required String zoneKey,
  required void Function(String message, NoticeLevel level) notice,
}) async {
  final ok = await v2ConfirmDanger(
    context,
    title: '删除确认',
    message: '确认删除「${file.name}」？此操作不可撤销。${_folderWarnSuffix([file])}',
    confirmLabel: '删除',
  );
  if (!ok) return false;

  final id = _deleteIdOf(file, zoneKey);
  if (id == null) {
    notice('该下发节点缺少下发记录 id，已跳过（避免误删源文件）', NoticeLevel.error);
    return false;
  }
  try {
    if (zoneKey == 'distribution') {
      await api.deleteDeliveryNode(id);
    } else {
      await api.destroyResource(id);
    }
    notice('已删除', NoticeLevel.success);
    return true;
  } catch (e) {
    // 单删带后端 message（对齐 useFileActions.js:80-88）
    notice(v2ErrMessage(e, '删除失败'), NoticeLevel.error);
    return false;
  }
}

/// 批量删除：二次确认 + **并发**调用
/// （移植 useFileActions.js:32-58：Promise.allSettled → Future.wait）。
///
/// 失败文案**不带**后端 message —— 与单删不同，这是 web 的既有口径，勿统一。
Future<bool> v2ConfirmAndBatchDelete(
  BuildContext context, {
  required ChannelV2Api api,
  required List<V2File> files,
  required String zoneKey,
  required void Function(String message, NoticeLevel level) notice,
}) async {
  if (files.isEmpty) return false;
  final confirmed = await v2ConfirmDanger(
    context,
    title: '批量删除确认',
    message: '确认删除选中的 ${files.length} 项？此操作不可撤销。${_folderWarnSuffix(files)}',
    confirmLabel: '删除 ${files.length} 项',
  );
  if (!confirmed) return false;

  final results = await Future.wait(files.map((f) async {
    final id = _deleteIdOf(f, zoneKey);
    if (id == null) return false;
    try {
      if (zoneKey == 'distribution') {
        await api.deleteDeliveryNode(id);
      } else {
        await api.destroyResource(id);
      }
      return true;
    } catch (_) {
      return false;
    }
  }));
  final ok = results.where((r) => r).length;
  final fail = files.length - ok;
  if (fail == 0) {
    notice('已删除 $ok 项', NoticeLevel.success);
  } else if (ok > 0) {
    notice('已删除 $ok 项，$fail 项失败', NoticeLevel.warning);
  } else {
    notice('全部删除失败', NoticeLevel.error);
  }
  return ok > 0;
}

// ==================== 移动（串行 + 去重聚合） ====================

/// 一批移动的结果（供弹窗与拖拽两条路径共用）
class V2MoveOutcome {
  final int ok;
  final int total;

  /// 后端原文（未去重，用于计数）；展示时按 web 口径 `[...new Set()].join('；')`
  final List<String> failMessages;

  const V2MoveOutcome(
      {required this.ok, required this.total, required this.failMessages});

  bool get allOk => ok == total && total > 0;
  bool get partial => ok > 0 && ok < total;
  bool get allFailed => ok == 0;

  /// 失败原文去重聚合（对齐 MoveTargetDialog.vue:259 / ChannelV2Page.vue:690）
  String get uniqueFailMessage => failMessages.toSet().join('；');
}

/// 批量移动：**串行 for**，不并发。
///
/// 【口径固定，勿"优化"为并发】同一批文件移进同一目录，与后端建目录的竞态同类
/// （web MoveTargetDialog.vue:236-255、ChannelV2Page.vue:658-677 都是串行）。
/// 失败不回滚：部分成功照样算成功（调用方据 [V2MoveOutcome.ok] 决定是否关窗/刷新）。
///
/// [destIdFor] 按区返回目标父 id：
///   - 资源区 → dest_group_file_id（根目录 '0'）
///   - 下发区 → delivery parent_id（根目录 '0'）
Future<V2MoveOutcome> v2MoveFilesSerially({
  required ChannelV2Api api,
  required List<V2File> files,
  required String zoneKey,
  required Object destId,
}) async {
  var ok = 0;
  final failMessages = <String>[];
  for (final f in files) {
    try {
      if (zoneKey == 'distribution') {
        // M6：下发移动必须用 delivery_node_id，不兜底源文件 id
        final nodeId = f.deliveryNodeId;
        if (nodeId == null) {
          _log('move',
              'delivery node missing delivery_node_id, refuse fallback group_file_id=${f.id} name=${f.name}');
          failMessages.add('「${f.name}」缺少下发记录 id');
          continue;
        }
        await api.moveDeliveryNode(id: nodeId, parentId: destId);
      } else {
        final gid = f.groupFileId;
        if (gid == null) {
          failMessages.add('「${f.name}」缺少文件 id');
          continue;
        }
        await api.moveFile(groupFileId: gid, destGroupFileId: destId);
      }
      ok++;
    } catch (e) {
      failMessages.add(v2ErrMessage(e, '请求异常'));
    }
  }
  return V2MoveOutcome(ok: ok, total: files.length, failMessages: failMessages);
}

// ==================== 下发（复制到下发区） ====================

/// 右键「复制 N 项到下发区」：批量下发到下发区当前选中的 scope。
///
/// 【口径固定】并发（对齐 ChannelV2Page.vue:752-767 Promise.allSettled），
/// 且失败文案**不带**后端 message —— 与拖拽下发（onDropResource，带 message）不同，
/// 这是 web 的既有差异，不要统一。
Future<bool> v2DistributeMany({
  required ChannelV2Api api,
  required List<V2File> files,
  required DistributionScope? target,
  required void Function(String message, NoticeLevel level) notice,
}) async {
  if (files.isEmpty) return false;
  if (target == null) {
    notice('请先在左侧分组树选择目标', NoticeLevel.warning);
    return false;
  }
  final results = await Future.wait(files.map((f) async {
    try {
      await api.addDeliveryResource(
        scopeType: target.scopeType,
        scopeId: target.scopeId,
        parentId: 0,
        // 下发的是**源文件**：这里恒取 groupFileId，与 deliveryNodeId 无关
        groupFileId: f.groupFileId,
      );
      return true;
    } catch (_) {
      return false;
    }
  }));
  final ok = results.where((r) => r).length;
  final fail = files.length - ok;
  if (fail == 0) {
    notice('已下发 $ok 项到 ${target.name}', NoticeLevel.success);
  } else if (ok > 0) {
    notice('已下发 $ok 项，$fail 项失败', NoticeLevel.warning);
  } else {
    notice('全部下发失败', NoticeLevel.error);
  }
  return ok > 0;
}
