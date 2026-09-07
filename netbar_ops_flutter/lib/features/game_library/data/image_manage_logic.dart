/// 镜像管理纯逻辑层 —— 逐函数移植自 web toolboxPage `src/api/imageManage.js`（下称 js）。
/// 不含网络；网络层见 image_manage_api.dart。
///
/// 可空性铁律（评审 M3）：模型字段一律 int? / Map?，「缺键/null」与「假值/0/false」
/// 必须可区分 —— 三处强依赖：
/// 1. [vsPresence] 以原始 Map 的 containsKey 判后端下发了哪些开关（js:62-68）
/// 2. [resolveRestoreTarget] 中 origin.virtual_security 为 null 必须透传 null 而非全 false
///    （js:574-579：否则回滚时会把机器原本开着的虚拟安全静默关掉）
/// 3. [normalizeRestoreSlots] 的缺省→KEEP 与 [normalizeClientRows] 的 `||0` 是两套口径
///    （js:242-258），不可混用
library;

// ==================== 常量（js:14-36） ====================

/// 无盘平台白名单：只有这两个平台有镜像概念（goodgame/story 是下载器，显式传会 400）
const List<String> kDisklessPlatforms = ['icafe8', 'cloud'];

/// 镜像槽固定 4 个，按位对应默认 / 第二 / 第三 / 第四
const int kImageSlotCount = 4;
const List<String> kSlotLabels = ['默认镜像', '第二镜像', '第三镜像', '第四镜像'];

/// 「保持原值」在前端模型里的哨兵值（提交时转成「字段缺省」而非真的传 -1）
const int kKeep = -1;

/// restore_time 下限：后端要求 > now + 50s
const int kRestoreMinLeadSeconds = 50;

/// CST 固定 +08 —— 后端上限算的是「明年今天+1天 00:00 CST」，不跟随设备时区
const int _cstOffsetMs = 8 * 3600 * 1000;

/// 虚拟安全 4 个开关。响应与提交都是正向语义（true = 启用）
class VsKey {
  final String key;
  final String label;
  const VsKey(this.key, this.label);
}

const List<VsKey> kVsKeys = [
  VsKey('enable_safe_start', '安全启动'),
  VsKey('enable_tpm2', 'TPM2'),
  VsKey('hvci', 'HVCI'),
  VsKey('dma', 'DMA'),
];

// ==================== 基础工具 ====================

/// JS 真值语义（false/0/''/null → false），归一/比较开关时与 js 的 `!!x` 对齐
bool _truthy(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !(v is double && v.isNaN);
  if (v is String) return v.isNotEmpty;
  return true;
}

/// JS `Number(x)` 的定向替身：数值/数字串 → int；解析不了 → null（对应 NaN）。
/// 注意 JS `Number(null)` 是 0 不是 NaN —— 依赖该行为的调用点单独处理，不进本函数。
int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.toInt() : null;
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }
  return null;
}

T? _at<T>(List<T?>? list, int i) =>
    (list != null && i >= 0 && i < list.length) ? list[i] : null;

// ==================== 模型 ====================

/// 单个镜像槽（rows / restore_image / 编辑区 / 提交前中间态共用）。
/// diskId/configId 语义域：null=没有值、kKeep=保持原值、0=不选/清空、>0=真实 id。
/// virtualSecurity 为 null = 原值未知（缺键），提交时整体省略（= 保持）。
class ImageSlot {
  final int? diskId;
  final int? configId;
  final Map<String, bool>? virtualSecurity;

  /// 后端实际下发了哪几个开关（仅 get_clientcfg 的 rows 有意义，见 [vsPresence]）
  final Map<String, bool>? vsPresent;

  const ImageSlot({this.diskId, this.configId, this.virtualSecurity, this.vsPresent});
}

/// get_clientcfg 单台机器归一结果（js normalizeClientRows 的 out[seat]）
class ClientCfg {
  final String seat;
  final String ip;

  /// 4 行；diskId/configId 恒非空（`||0` 口径），virtualSecurity 恒非空（全归一）
  final List<ImageSlot> rows;
  final int restoreTime;

  /// 挂 plan 时的回滚目标 4 槽（KEEP 口径）；无 plan 为 null
  final List<ImageSlot>? restoreRows;

  const ClientCfg({
    required this.seat,
    required this.ip,
    required this.rows,
    required this.restoreTime,
    required this.restoreRows,
  });
}

/// image_info 归一后的镜像（js normalizeImages 只保证 UI 用到的字段；
/// 其余字段（size_gb/memo 等）Flutter 端不消费，不透传）
class DiskImage {
  final int diskId;
  final String name;
  final String path;
  final List<ImageSection> sections;
  const DiskImage({
    required this.diskId,
    required this.name,
    required this.path,
    required this.sections,
  });
}

class ImageSection {
  final int configId;
  final String name;
  final List<ConfigPoint> points;
  const ImageSection({required this.configId, required this.name, required this.points});
}

class ConfigPoint {
  final int id;
  final String name;
  const ConfigPoint({required this.id, required this.name});
}

/// 槽位展示视图（js buildSlotViews 的元素）
class SlotView {
  final int diskId;
  final String imageName;
  final String sectionName;
  final String expireText;
  final Map<String, bool> virtualSecurity;
  const SlotView({
    required this.diskId,
    required this.imageName,
    required this.sectionName,
    required this.expireText,
    required this.virtualSecurity,
  });
}

/// 配置节下拉选项（js buildConfigOptions 的元素）。
/// value：kKeep / 节根 config_id；配置点 disabled 展示项恒为 null ——
/// Flutter DropdownMenuItem 用 enabled:false 表达，不混 String 类型 value
class ConfigOption {
  final int? value;
  final String label;
  final bool disabled;
  final bool isSection;
  final bool current;
  const ConfigOption({
    required this.value,
    required this.label,
    this.disabled = false,
    this.isSection = false,
    this.current = false,
  });
}

/// buildSetClientCfgBody 的临时镜像参数（js:603-605 的 restore 对象）
class RestoreSpec {
  final List<ImageSlot> tempRows;
  final List<ImageSlot>? tempOriginRows;
  final int restoreTime;
  const RestoreSpec({
    required this.tempRows,
    required this.tempOriginRows,
    required this.restoreTime,
  });
}

// ==================== 虚拟安全（js:38-71） ====================

Map<String, bool> emptyVirtualSecurity() => {for (final k in kVsKeys) k.key: false};

/// js:45-50。入参任意（原始 JSON Map / 已归一 Map / null），键全补齐
Map<String, bool> normalizeVirtualSecurity(dynamic vs) => {
      for (final k in kVsKeys) k.key: _truthy(vs is Map ? vs[k.key] : null),
    };

/// js:62-68。判据是「有没有拉下来」：整个对象缺省 → null（这台机不支持）；
/// 返了对象但缺某键 → 那一项不支持。只能拿 get_clientcfg 的 rows 当判据 ——
/// restore_image 字段缺省是「保持原值」不是「不支持」
Map<String, bool>? vsPresence(dynamic vs) {
  if (vs is! Map) return null;
  return {for (final k in kVsKeys) k.key: vs.containsKey(k.key)};
}

/// js:70-71
bool isSameVirtualSecurity(Map<String, dynamic>? a, Map<String, dynamic>? b) =>
    kVsKeys.every((k) => _truthy(a?[k.key]) == _truthy(b?[k.key]));

// ==================== pickedConfigId（js:83-89） ====================

/// 取编辑行里真正要下发的 config_id；不下发时返回 null。
/// null（没有值，须与 KEEP 区分：UI 上无对应选项时不能漏出 -1）→ null；
/// kKeep（显式选了保持原值）→ null；其余原样返回 —— 0 也照样返回（js `n || 0`）
int? pickedConfigId(ImageSlot? row) {
  final raw = row?.configId;
  if (raw == null || raw == kKeep) return null;
  return raw;
}

// ==================== 临时镜像时间窗（js:129-165） ====================

/// js:129-138。后端接受的 restore_time 区间（Unix 秒）：
/// `(now + 50s, 明年今天+1天 00:00 CST)`，上限按固定 +08 算不受设备时区影响。
/// Dart 月份 1 基（JS getUTCMonth 0 基），两端各自喂各自的构造器，不存在偏移；
/// DateTime.utc 的 day 溢出与 Date.UTC 同样自动进位
({int min, int max}) restoreTimeRange() {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final cst = DateTime.fromMillisecondsSinceEpoch(nowMs + _cstOffsetMs, isUtc: true);
  final maxMs =
      DateTime.utc(cst.year + 1, cst.month, cst.day + 1).millisecondsSinceEpoch -
          _cstOffsetMs;
  return (min: nowMs ~/ 1000 + kRestoreMinLeadSeconds, max: maxMs ~/ 1000);
}

/// js:144-151。空串表示通过
String checkRestoreTime(int? unix) {
  final ts = unix ?? 0;
  if (ts <= 0) return '请选择临时镜像的到期时间';
  final range = restoreTimeRange();
  if (ts <= range.min) return '到期时间太近，至少要比当前时间晚 $kRestoreMinLeadSeconds 秒';
  if (ts >= range.max) return '到期时间太远，最多只能设到明年的今天';
  return '';
}

String _p2(int n) => n.toString().padLeft(2, '0');

/// js:154-165。当天只给时分秒，跨天补月日 —— 表格/卡片里位置窄
String formatRestoreTime(int? unix) {
  final ts = unix ?? 0;
  if (ts <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final hms = '${_p2(d.hour)}:${_p2(d.minute)}:${_p2(d.second)}';
  final now = DateTime.now();
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  return sameDay ? hms : '${_p2(d.month)}-${_p2(d.day)} $hms';
}

// ==================== 错误文案（js:174-202） ====================

/// 后端错误响应是 text/plain 的 Go 调用链串，按关键字翻成人话；
/// 顺序保持 js 原序，find 首中
final List<(RegExp, String)> _errorRules = [
  (RegExp('未找到编号|找不到客户机'), '该机器未接入无盘系统 —— 无盘平台上没有这个机号'),
  (RegExp('not_a_diskless_platform'), '该平台没有镜像管理功能（仅网维大师 / 云更新支持）'),
  (RegExp('platform not enabled'), '无盘平台未启用，请检查网吧服务端'),
  (RegExp('missing platform'), '未指定平台，无法下发'),
  (RegExp('连续|contiguous'), '镜像槽必须从第 1 行开始连续，中间不能空'),
  (RegExp('必须显式给 config_id'), '换了镜像就必须重新选择配置点'),
  (RegExp('服务端没有 disk_id'), '服务端上没有这个镜像，请刷新后重试'),
  (RegExp('下没有 config_id'), '该镜像下没有这个配置点，请重新选择'),
  (RegExp('virtual_security 与前面的条目不一致'), '云更新的虚拟安全是整机一份，四个槽必须相同'),
  (RegExp('seat 只允许字母'), '机号格式不合法（只允许字母、数字、下划线、连字符、点）'),
  (RegExp('restore_time 与 image_tmp 必须同时出现'), '临时镜像和到期时间必须同时填写'),
  (RegExp('restore_time .*太近'), '到期时间太近，至少要比当前时间晚 $kRestoreMinLeadSeconds 秒'),
  (RegExp('restore_time .*太远'), '到期时间太远，最多只能设到明年的今天'),
  (RegExp('image_tmp 下发失败'), '临时镜像下发失败，机器配置未改动'),
  (RegExp('restore scheduler stopped'), '服务端正在重启，请稍后重试'),
  (RegExp('IP 冲突'), 'IP 冲突，云更新拒绝了本次修改'),
  (RegExp('MAC 冲突'), 'MAC 冲突，云更新拒绝了本次修改'),
  (RegExp('not connected|dial|timeout|超时'), '连不上无盘服务端，请检查网络或服务状态'),
];

/// 响应体是 HTML / XML 文档（frp、nginx 等网关的错误页），而不是后端给的错误文案
final RegExp kGatewayPageRe =
    RegExp(r'^\s*(<!doctype|<html|<\?xml)', caseSensitive: false);

/// js:195-202。未命中保留原文截 80 字（UTF-16 计数，与 js slice 同口径）
String humanizeCfgError(dynamic raw) {
  final text = (raw ?? '').toString().trim();
  if (text.isEmpty) return '操作失败';
  for (final (re, msg) in _errorRules) {
    if (re.hasMatch(text)) return msg;
  }
  // 兜底：网吧服务端没起来时请求会被 frp / nginx 拦下并返回一整页 HTML 错误页，
  // 那段源码不能当文案透出去，否则界面上会出现一屏尖括号
  if (kGatewayPageRe.hasMatch(text)) return '连不上网吧服务端，请检查服务状态';
  return text.length > 80 ? '${text.substring(0, 80)}…' : text;
}

// ==================== 响应解析（js:211-325） ====================

/// js:211-216。拆平台键封装：遍历模式下未启用平台不入结果、
/// 出错平台是 { error: ... }，都要滤掉
List<({String platform, Map<String, dynamic> data})> extractPlatformEntries(
    dynamic data) {
  if (data is! Map) return const [];
  final out = <({String platform, Map<String, dynamic> data})>[];
  for (final platform in kDisklessPlatforms) {
    final d = data[platform];
    if (d is Map && !_truthy(d['error'])) {
      out.add((platform: platform, data: d.cast<String, dynamic>()));
    }
  }
  return out;
}

/// js:223-237。归一 image_info 单平台的 images，只保证 UI 用到的字段一定存在
List<DiskImage> normalizeImages(Map<String, dynamic>? platData) {
  final list = platData?['images'];
  if (list is! List) return const [];
  return list.map((img) {
    final m = img is Map ? img : const {};
    final diskId = _asInt(m['disk_id']) ?? 0;
    final rawName = m['name'];
    final rawSections = m['sections'];
    return DiskImage(
      diskId: diskId,
      name: _truthy(rawName) ? rawName.toString() : '镜像 $diskId',
      path: m['path']?.toString() ?? '',
      sections: (rawSections is! List)
          ? const []
          : rawSections.map((sec) {
              final s = sec is Map ? sec : const {};
              final points = s['points'];
              return ImageSection(
                configId: _asInt(s['config_id']) ?? 0,
                name: _truthy(s['name']) ? s['name'].toString() : '未命名配置',
                points: (points is! List)
                    ? const []
                    : points.map((p) {
                        final pm = p is Map ? p : const {};
                        final pid = _asInt(pm['id']) ?? 0;
                        return ConfigPoint(
                          id: pid,
                          name: _truthy(pm['name']) ? pm['name'].toString() : '$pid',
                        );
                      }).toList(growable: false),
              );
            }).toList(growable: false),
    );
  }).toList(growable: false);
}

/// js:248-258。归一 restore_image（到期回滚目标 4 槽）。
/// 结构 ≠ rows：每个字段全部可选，缺省 = 保持原值 —— 缺省一律落 KEEP 哨兵，
/// 不能像 rows 那样 `||0`（会把「缺省」误读成「不选」）。无 plan 返回 null
List<ImageSlot>? normalizeRestoreSlots(dynamic slots) {
  if (slots is! List) return null;
  return List.generate(kImageSlotCount, (i) {
    final raw = i < slots.length ? slots[i] : null;
    final s = raw is Map ? raw : null;
    final rawVs = s?['virtual_security'];
    return ImageSlot(
      // js `s?.disk_id == null ? KEEP : (Number(s.disk_id) || 0)`
      diskId: s?['disk_id'] == null ? kKeep : (_asInt(s!['disk_id']) ?? 0),
      configId: s?['config_id'] == null ? kKeep : (_asInt(s!['config_id']) ?? 0),
      // 缺省 → null（原值未知），不归一成全 false
      virtualSecurity: rawVs is Map ? normalizeVirtualSecurity(rawVs) : null,
    );
  }, growable: false);
}

/// js:269-291。归一 get_clientcfg 单平台 clients → map<seat, ClientCfg>。
/// 挂 plan 时语义倒置：rows = 当前生效的临时镜像，restore_image = 日常镜像；
/// 无 plan 时后端完全不下发 restore_time / restore_image
Map<String, ClientCfg> normalizeClientRows(Map<String, dynamic>? platData) {
  final clients = platData?['clients'];
  final out = <String, ClientCfg>{};
  if (clients is! Map) return out;
  clients.forEach((seatKey, cfg) {
    final seat = seatKey.toString();
    final c = cfg is Map ? cfg : const {};
    final rows = c['rows'] is List ? c['rows'] as List : const [];
    final restoreTime = _asInt(c['restore_time']) ?? 0;
    final cfgSeat = c['seat'];
    out[seat] = ClientCfg(
      seat: _truthy(cfgSeat) ? cfgSeat.toString() : seat,
      ip: c['ip']?.toString() ?? '',
      rows: List.generate(kImageSlotCount, (i) {
        final raw = i < rows.length ? rows[i] : null;
        final r = raw is Map ? raw : null;
        final rawVs = r?['virtual_security'];
        return ImageSlot(
          diskId: _asInt(r?['disk_id']) ?? 0,
          configId: _asInt(r?['config_id']) ?? 0,
          virtualSecurity: normalizeVirtualSecurity(rawVs),
          vsPresent: vsPresence(rawVs),
        );
      }, growable: false),
      restoreTime: restoreTime,
      restoreRows: restoreTime > 0 ? normalizeRestoreSlots(c['restore_image']) : null,
    );
  });
  return out;
}

/// js:294。该机是否挂着临时镜像计划
bool hasRestorePlan(ClientCfg? cfg) => (cfg?.restoreTime ?? 0) > 0;

/// js:309-325。派生可直接渲染的槽位视图：只保留 disk_id > 0 的有效槽；
/// 到期时间整台一份，只标在第一槽（过滤后的首个有效槽）上
List<SlotView> buildSlotViews(
  List<ImageSlot>? rows,
  Map<int, DiskImage> imageIndex, [
  int restoreTime = 0,
]) {
  final valid = (rows ?? const [])
      .where((r) => (r.diskId ?? 0) > 0)
      .toList(growable: false);
  return List.generate(valid.length, (i) {
    final r = valid[i];
    final diskId = r.diskId!;
    final img = imageIndex[diskId];
    final configId = r.configId ?? 0;
    ImageSection? sec;
    if (img != null) {
      for (final s in img.sections) {
        if (s.configId == configId || s.points.any((p) => p.id == configId)) {
          sec = s;
          break;
        }
      }
    }
    return SlotView(
      diskId: diskId,
      imageName: img?.name ?? '镜像 $diskId',
      sectionName: sec?.name ?? (configId != 0 ? '配置 $configId' : '—'),
      expireText: i == 0 ? formatRestoreTime(restoreTime) : '',
      virtualSecurity: normalizeVirtualSecurity(r.virtualSecurity),
    );
  }, growable: false);
}

// ==================== 配置节下拉（js:335-398） ====================

/// js:335-338。当前 config_id 命中的配置节（节根或节内配置点都算命中）
ImageSection? _findHitSection(DiskImage? image, int currentConfigId) {
  for (final sec in image?.sections ?? const <ImageSection>[]) {
    if (sec.configId == currentConfigId ||
        sec.points.any((p) => p.id == currentConfigId)) {
      return sec;
    }
  }
  return null;
}

/// js:344-348。回填用：当前 config_id 应选中哪一项（= 命中节的节根）。
/// 命中不了返回 null，交调用方走「保持原值」或留空
int? hitSectionConfigId(DiskImage? image, int? currentConfigId) {
  final id = currentConfigId ?? 0;
  if (id <= 0) return null;
  return _findHitSection(image, id)?.configId;
}

/// js:361-398。只让用户选配置节（value = 节根 config_id）；配置点仅作 disabled
/// 展示项（value=null）标当前值命中在哪儿。一节一点且点即节根时该点行纯冗余，不渲染。
/// allowKeep：换了镜像必须为 false（§5.17）
List<ConfigOption> buildConfigOptions(
    DiskImage? image, int currentConfigId, bool allowKeep) {
  final options = <ConfigOption>[];
  if (allowKeep) {
    options.add(const ConfigOption(value: kKeep, label: '保持原值'));
  }
  final hit = _findHitSection(image, currentConfigId);
  for (final sec in image?.sections ?? const <ImageSection>[]) {
    final onlyPointIsRoot =
        sec.points.length == 1 && sec.points[0].id == sec.configId;
    options.add(ConfigOption(
      value: sec.configId,
      label: sec.name,
      isSection: true,
      current: identical(sec, hit),
    ));
    if (onlyPointIsRoot) continue;
    for (final p in sec.points) {
      options.add(ConfigOption(
        value: null,
        label: '　• ${p.name}${p.id == currentConfigId ? '（当前）' : ''}',
        disabled: true,
      ));
    }
  }
  return options;
}

// ==================== 提交前校验 + body 构造（js:413-625） ====================

/// js:413-433。把「编辑值」与「服务端原值」合并成最终 4 槽。
/// 后端连续性校验算的是合并后结果，前端必须先合并再校验。
/// disk 的 KEEP 穿透（原值本身也是 KEEP 时保持 KEEP）在 js 里是显式三元；
/// config 的 KEEP 穿透在 js 里靠 `Number(x)||0` 中 -1 truthy 的巧合 ——
/// 这里必须显式写「origin 为 KEEP 时结果保持 KEEP」，写成 `>0?:0` 会毁掉穿透
List<ImageSlot> mergeRows(
    List<ImageSlot?>? editRows, List<ImageSlot?>? originRows) {
  return List.generate(kImageSlotCount, (i) {
    final edit = _at(editRows, i);
    final origin = _at(originRows, i);

    final editDisk = edit?.diskId;
    final originDisk = origin?.diskId;
    final diskId = editDisk == kKeep
        ? (originDisk == kKeep ? kKeep : (originDisk ?? 0))
        : (editDisk ?? 0);

    final editConfig = edit?.configId;
    final originConfig = origin?.configId;
    var configId = editConfig == kKeep
        ? (originConfig == kKeep ? kKeep : (originConfig ?? 0))
        : (editConfig ?? 0);
    // 清空槽时后端会把 config_id 一并归零，前端合并结果保持同一口径
    if (diskId == 0) configId = 0;

    return ImageSlot(
      diskId: diskId,
      configId: configId,
      virtualSecurity:
          normalizeVirtualSecurity(edit?.virtualSecurity ?? origin?.virtualSecurity),
    );
  }, growable: false);
}

/// js:441-457。连续性校验：有效镜像必须占据前缀。传入必须是 mergeRows 后的最终值。
/// 合并后仍是 KEEP 的槽前端判不了 → 跳过不判；但前面已明确清空(0)的仍拦后续有效槽
String checkSlotContiguity(List<ImageSlot>? rows) {
  var cleared = false;
  final list = rows ?? const <ImageSlot>[];
  for (var i = 0; i < list.length; i++) {
    final diskId = list[i].diskId ?? 0;
    if (diskId == kKeep) continue;
    if (diskId <= 0) {
      cleared = true;
      continue;
    }
    if (cleared) {
      final label = i < kSlotLabels.length ? kSlotLabels[i] : '第 ${i + 1} 槽';
      return '$label已选镜像，但前面有槽是「不选」—— 4 个镜像槽必须从第 1 行起连续，不能跳着设置';
    }
  }
  return '';
}

/// js:464-476。换镜像必须显式给 config_id：入参是编辑区 rows（非合并结果）。
/// disk 为 KEEP/<=0（含 null）跳过；仅「disk 换了 + pickedConfigId==null」拦
String checkConfigOnDiskChange(
    List<ImageSlot?>? rows, List<ImageSlot?>? originRows) {
  final list = rows ?? const <ImageSlot?>[];
  for (var i = 0; i < list.length; i++) {
    final diskId = list[i]?.diskId;
    if (diskId == null || diskId == kKeep || diskId <= 0) continue;
    final originDiskId = _at(originRows, i)?.diskId ?? 0;
    // 「保持原值」和「没有值」都算没给 config_id，换镜像时两者后端都会拦
    if (diskId != originDiskId && pickedConfigId(list[i]) == null) {
      final label = i < kSlotLabels.length ? kSlotLabels[i] : '第 ${i + 1} 槽';
      return '$label换了镜像，必须选择配置点';
    }
  }
  return '';
}

/// js:498-536。构造 body 里的一个 4 槽数组（image / image_tmp 共用）。
/// 逐槽：KEEP → 缺省 disk_id（但用户单独动过 config 仍带 config_id）；
/// 0/null → {disk_id:0}；其余 → {disk_id[, config_id]}。
/// VS：vsTouched 判据优先于「与原值比对」（批量编辑无单台原值，逐台比对会把
/// 原本开着的开关当成「用户想关掉」）；explicit 时逐字段显式下发；
/// row.virtualSecurity 为 null = 不知道原值，一律省略（explicit 也不例外）；
/// cloud 整机一份只挂 image[0]（含全清空仍改 VS 的分支），icafe8 逐槽
List<Map<String, dynamic>> _buildImageArray(
  List<ImageSlot?> rows,
  List<ImageSlot?>? originRows,
  String platform, {
  bool explicit = false,
  List<bool>? vsTouched,
}) {
  bool vsChanged(int i, ImageSlot? row) {
    if (explicit) return true;
    if (vsTouched != null) return i < vsTouched.length && vsTouched[i];
    return !isSameVirtualSecurity(
        row?.virtualSecurity, _at(originRows, i)?.virtualSecurity);
  }

  final slice = rows.take(kImageSlotCount).toList(growable: false);
  final image = <Map<String, dynamic>>[];
  for (var i = 0; i < slice.length; i++) {
    final row = slice[i];
    final diskId = row?.diskId;
    final configId = pickedConfigId(row);
    final item = <String, dynamic>{};

    if (diskId == kKeep) {
      // 整槽保持原值：disk_id 缺省。此时若用户单独动了配置节，仍要把 config_id 带上
      if (configId != null) item['config_id'] = configId;
    } else if (diskId == null || diskId <= 0) {
      item['disk_id'] = 0;
    } else {
      item['disk_id'] = diskId;
      if (configId != null) item['config_id'] = configId;
    }

    // 清空槽的开关后端会强制归零；virtual_security 为 null = 不知道原值，省略 = 保持
    if (platform != 'cloud' &&
        item['disk_id'] != 0 &&
        row?.virtualSecurity != null &&
        vsChanged(i, row)) {
      item['virtual_security'] = normalizeVirtualSecurity(row!.virtualSecurity);
    }
    image.add(item);
  }

  // cloud：整机一份 VS，统一挂 image[0]（含「全部槽清空但仍要改 VS」的极端场景）
  final first = slice.isNotEmpty ? slice[0] : null;
  if (platform == 'cloud' &&
      image.isNotEmpty &&
      first?.virtualSecurity != null &&
      vsChanged(0, first)) {
    image[0]['virtual_security'] = normalizeVirtualSecurity(first!.virtualSecurity);
  }

  return image;
}

/// js:555-586。把「回滚目标」4 槽逐字段落实成具体值。
/// 带 restore_time 时 body.image 不是立即下发，而是到期那一刻 fire —— 届时字段缺省
/// 的语义是「保持那一刻（= 临时镜像）的值」，缺省会导致日常镜像永远回不来。
/// editDisk 非有限数（Dart 里即 null）视为 KEEP 同款处理；
/// config 用户没选时忠实回原值 —— 哪怕它是节内硬件专属配置点；
/// origin.virtual_security 为 null 必须透传 null（不知道 ≠ 全关）
List<ImageSlot> resolveRestoreTarget(
  List<ImageSlot?>? rows,
  List<ImageSlot?>? originRows, [
  List<bool>? vsTouched,
]) {
  return List.generate(kImageSlotCount, (i) {
    final row = _at(rows, i);
    final origin = _at(originRows, i);

    final editDisk = row?.diskId;
    final originDisk = origin?.diskId;
    final diskId = (editDisk == kKeep || editDisk == null)
        ? (originDisk ?? kKeep)
        : editDisk;

    final editConfig = pickedConfigId(row);
    final originConfig = origin?.configId;
    final configId = editConfig ?? originConfig ?? kKeep;

    final touched = vsTouched != null && i < vsTouched.length && vsTouched[i];
    final vs = touched
        ? normalizeVirtualSecurity(row?.virtualSecurity)
        : (origin?.virtualSecurity != null
            ? normalizeVirtualSecurity(origin!.virtualSecurity)
            : null);

    return ImageSlot(
      diskId: diskId,
      configId: diskId == 0 ? 0 : configId,
      virtualSecurity: vs,
    );
  }, growable: false);
}

/// js:607-625。构造 set_clientcfg 的 body。
/// 不带 restore：{image}（并清掉已有临时镜像计划）；
/// 带 restore：{image, restore_time, image_tmp} —— 两字段必须同现，缺一后端 400。
/// 带 restore 时 rows 必须已过 resolveRestoreTarget；image_tmp 是立即下发，照常走省略规则
Map<String, dynamic> buildSetClientCfgBody(
  List<ImageSlot> rows,
  List<ImageSlot?>? originRows,
  String platform, {
  RestoreSpec? restore,
  bool explicit = false,
  List<bool>? vsTouched,
  List<bool>? tempVsTouched,
}) {
  final body = <String, dynamic>{
    'image': _buildImageArray(rows, originRows, platform,
        explicit: explicit, vsTouched: vsTouched),
  };
  final restoreTime = restore?.restoreTime ?? 0;
  if (restoreTime > 0 && restore != null) {
    body['restore_time'] = restoreTime;
    body['image_tmp'] = _buildImageArray(
        restore.tempRows, restore.tempOriginRows, platform,
        vsTouched: tempVsTouched);
  }
  return body;
}

// ==================== 移植自查清单（人工验证记录，替代单元测试） ====================
//
// 逐函数核对 js 陷阱点的自查结论：
//
// 1. pickedConfigId（js:83-89）
//    ✓ null → null；kKeep → null；0 → 0 照样返回（js `n||0` 中 0||0=0，未把 0 归 null）。
//    ✓ js 的 ''（字符串空）入口在 Dart 类型系统里不存在（configId 是 int?），无需处理。
// 2. mergeRows（js:413-433）
//    ✓ disk KEEP 穿透：edit==KEEP 且 origin==KEEP → 结果 KEEP（显式三元，与 js 同构）。
//    ✓ config KEEP 穿透：js 靠 `Number(origin.config_id)||0` 中 -1 truthy 的巧合返回 -1；
//      Dart 显式写 `originConfig == kKeep ? kKeep : (originConfig ?? 0)`，未写成 `>0?:0`。
//    ✓ origin.config_id 为 null 时 js Number(null)=0 → Dart `?? 0` 同口径。
//    ✓ diskId==0 ⇒ configId 强制 0（清空槽归零口径）。
// 3. checkSlotContiguity（js:441-457）
//    ✓ KEEP 槽 continue 跳过不判；cleared 标记不因 KEEP 重置，前面明确清空(0)仍拦后续有效槽。
// 4. checkConfigOnDiskChange（js:464-476）
//    ✓ disk KEEP/<=0 跳过；仅「disk != originDisk && pickedConfigId==null」拦。
//    ✓ 入参是编辑区 rows 而非 mergeRows 结果（与 ConfigImageDialog.vue:631-641 调用一致）。
//    △ diskId==null（js 里是 NaN，NaN<=0 为 false 不跳过、NaN!==origin 恒 true）Dart 选择跳过：
//      编辑区 disk_id 恒为 KEEP/0/>0，该分支实际不可达；null 语义上「没有值」不构成「换镜像」。
// 5. buildImageArray（js:498-536）
//    ✓ KEEP → 缺省 disk_id，但 pickedConfigId 非 null（用户单独动过 config）仍带 config_id。
//    ✓ 0（及防御性的 null）→ {disk_id:0}。
//    ✓ VS 判据优先级：explicit > vsTouched（数组存在即用，含越界=false）> 与原值比对。
//    ✓ row.virtualSecurity == null 时一律省略 —— explicit 也不越过该门（js:524 先判 truthy）。
//    ✓ item['disk_id'] != 0 门：KEEP 槽 disk_id 键缺省（null != 0）→ VS 允许挂上，与 js
//      `item.disk_id !== 0`（undefined !== 0）同构。
//    ✓ cloud：只挂 image[0]，判据取 rows[0]（含四槽全清空仍改 VS 的分支）；icafe8 逐槽。
// 6. resolveRestoreTarget（js:555-586）
//    ✓ editDisk 非有限数（null）按 KEEP 处理：落到 originDisk ?? kKeep（js Number.isFinite 分支）。
//    ✓ originDisk 本身是 KEEP(-1) 时 js isFinite(-1)=true 原样穿透 → Dart `?? kKeep` 仅补 null，同构。
//    ✓ config：editConfig(pickedConfigId) 优先；否则忠实回 originConfig（哪怕是节内硬件专属点，
//      不换算成节根）；origin 也没有 → kKeep。
//    ✓ vs：touched → 编辑值；未 touched 且 origin.virtualSecurity==null → 返回 null 而非全 false
//      （老计划的 restore_image 只有 disk/config 时，归一成 false 会在回滚时静默关掉虚拟安全）。
//    ✓ diskId==0 ⇒ configId 强制 0。
// 7. buildSetClientCfgBody（js:607-625）
//    ✓ restore_time>0 且 tempRows 存在时 restore_time 与 image_tmp 同现，否则两者都不出现。
//    ✓ image_tmp 不透传 explicit（立即下发，照常省略），只透传 tempVsTouched。
// 8. normalizeRestoreSlots（js:248-258）
//    ✓ disk_id/config_id 缺省(null) → kKeep；有值但解析失败 → 0（js `Number(x)||0`）。
//    ✓ virtual_security 缺省 → null（不归一），与 normalizeClientRows 的恒归一是两套口径。
// 9. normalizeClientRows（js:269-291）
//    ✓ rows 不足 4 行补齐；disk_id/config_id `||0` 口径；vs 恒归一 + vsPresent 取自原始 Map。
//    ✓ restore_rows 仅 restoreTime>0 时解析；seat 字段 falsy 时回退 map 键。
// 10. vsPresence（js:62-68）
//    ✓ 非 Map（含 null）→ null；否则逐键 containsKey（含键值为 null 也算「下发过」，
//      与 js hasOwnProperty 同构）。
// 11. normalizeVirtualSecurity / isSameVirtualSecurity（js:45-50/70-71）
//    ✓ JS `!!x` 真值语义由 _truthy 对齐（false/0/''/null → false）。
// 12. restoreTimeRange（js:129-138）
//    ✓ CST 固定 +08：nowMs+8h 后用 isUtc:true 读 y/m/d，再 DateTime.utc(y+1, m, day+1) 减 8h。
//    ✓ 月份基准：js getUTCMonth(0 基) 喂 Date.UTC(0 基)，Dart .month(1 基) 喂 DateTime.utc(1 基)，
//      各自闭环无偏移；day+1 溢出两边都自动进位。
//    ✓ min = now/1000 向下取整 + 50。
// 13. checkRestoreTime / formatRestoreTime（js:144-165）
//    ✓ 边界：<=min 太近、>=max 太远（开区间）；展示当天只时分秒、跨天补月日（本地时区）。
// 14. humanizeCfgError（js:174-202）
//    ✓ 18 条规则逐条对照原文迁移，顺序保持，find 首中；未命中截 80 字（UTF-16 计数同 js slice）
//      加省略号；空串 → '操作失败'。
// 15. extractPlatformEntries（js:211-216）
//    ✓ 只遍历白名单两平台；d 非 Map 或 d.error truthy（含非空串/true/非零）滤掉。
// 16. buildSlotViews（js:309-325）
//    ✓ 只留 diskId>0；expireText 只标过滤后第一槽（js 的 i 也是 filter 后索引）；
//      sectionName 命中节根或节内点都归节名，未命中 configId!=0 → '配置 N'，0 → '—'。
// 17. hitSectionConfigId / buildConfigOptions（js:344-398）
//    ✓ currentConfigId<=0/null → null；命中节返回节根 id。
//    ✓ 只有配置节可选（value=节根）；配置点 disabled 展示（value=null，DropdownMenuItem
//      enabled:false，不与 int value 混类型）；一节一点且点即节根时不渲染点行；
//      点行标注（当前）后缀、节行不带（避免漏进收起态显示）。
