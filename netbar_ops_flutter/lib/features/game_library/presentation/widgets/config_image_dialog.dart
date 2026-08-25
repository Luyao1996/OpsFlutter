import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/game_constants.dart';
import '../../data/image_manage_api.dart';
import '../../data/image_manage_logic.dart';

/// 配置镜像弹窗 —— 对标 web ConfigImageDialog.vue（下称 vue）。
/// 单机 = seats 长度 1，批量 = 长度 N；批量时无单台原值，日常区默认全「保持原值」。
class ConfigImageDialog extends StatefulWidget {
  final ImageManageApi api;
  final String platform;
  final List<({String id, String name})> seats;
  final List<DiskImage> images;
  final Map<String, ClientCfg> clientCfgMap;

  /// 每有一台保存成功都会累计；部分失败弹窗不关时也要让父级逐台回拉刷新
  final void Function(List<String> okSeats)? onSaved;

  const ConfigImageDialog({
    super.key,
    required this.api,
    required this.platform,
    required this.seats,
    required this.images,
    required this.clientCfgMap,
    this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required ImageManageApi api,
    required String platform,
    required List<({String id, String name})> seats,
    required List<DiskImage> images,
    required Map<String, ClientCfg> clientCfgMap,
    void Function(List<String> okSeats)? onSaved,
  }) {
    return showAdaptive<void>(
      context,
      (_) => ConfigImageDialog(
        api: api,
        platform: platform,
        seats: seats,
        images: images,
        clientCfgMap: clientCfgMap,
        onSaved: onSaved,
      ),
      barrierDismissible: false,
    );
  }

  @override
  State<ConfigImageDialog> createState() => _ConfigImageDialogState();
}

/// 编辑区一行（disk_id 恒有值：KEEP/0/>0；config_id 的「无值」态用 null 而非 KEEP ——
/// 下拉没有对应选项时才能正常走 placeholder，不漏出 -1）
class _EditRow {
  int diskId;
  int? configId;
  Map<String, bool> virtualSecurity;
  _EditRow({required this.diskId, this.configId, required this.virtualSecurity});
}

class _ConfigImageDialogState extends State<ConfigImageDialog> {
  bool _submitting = false;
  String _errorText = '';
  final _bodyScrollCtrl = ScrollController();

  late List<_EditRow> _dailyRows;
  late List<_EditRow> _tempRows;
  late List<int?> _dailyInitConfig;
  late List<int?> _tempInitConfig;

  /// vsTouched 两组（评审 M2）：提交时传给 buildImageArray 作 VS 省略判据。
  /// 批量编辑没有单台原值可回填，不追踪会把每台原本开着的开关当成「用户想全关」下发
  late List<bool> _dailyVsTouched;
  late List<bool> _tempVsTouched;

  // 到期时间整台一份（后端 restore_time 按 seat 挂一个，不分槽）
  DateTime? _expireDate;
  TimeOfDay? _expireTime;
  // TimeOfDay 无秒，重拼会截秒 → 用户没动控件时必须沿用原 restore_time 原始 unix
  bool _dateTouched = false;
  bool _timeTouched = false;

  bool get _isBatch => widget.seats.length > 1;

  /// cloud 的虚拟安全是每台一份、四槽必然相同，UI 上要联动（API §5.16/§5.17）
  bool get _vsShared => widget.platform == 'cloud';

  /// 单台时该机的完整配置（批量时无单一原值）
  ClientCfg? get _singleCfg =>
      widget.seats.length == 1 ? widget.clientCfgMap[widget.seats[0].id] : null;

  bool get _hasPlan => (_singleCfg?.restoreTime ?? 0) > 0;

  /// 日常镜像的服务端原值。挂了 plan 时语义倒置（API §5.16）：rows 是当前生效的
  /// 临时镜像，restore_image 才是到期后要恢复的日常镜像
  List<ImageSlot>? get _dailyOriginRows =>
      _hasPlan ? _singleCfg?.restoreRows : _singleCfg?.rows;

  /// 临时镜像的服务端原值：挂着 plan 时就是当前生效的 rows，否则没有原值
  List<ImageSlot>? get _tempOriginRows => _hasPlan ? _singleCfg?.rows : null;

  /// 日常区镜像下拉是否给「保持原值」（评审 M1，vue:306-313 三种情况写死）：
  /// 批量 / 挂着 plan（restore_image 槽可缺省）/ 无原值可回填 —— 否则值是 KEEP
  /// 时下拉找不到匹配项
  bool get _allowDailyKeep => _isBatch || _hasPlan || _dailyOriginRows == null;

  /// 该机支持哪几个虚拟安全开关（vue:548-551）。「支不支持」是整机能力，
  /// 取任意一个下发过 VS 的槽当代表；一个都没下发过 → null，信息不足一律放开
  Map<String, bool>? get _vsSupported {
    for (final r in _singleCfg?.rows ?? const <ImageSlot>[]) {
      if (r.vsPresent != null) return r.vsPresent;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _resetForm();
  }

  @override
  void dispose() {
    _bodyScrollCtrl.dispose();
    super.dispose();
  }

  DiskImage? _imageOf(int? diskId) {
    for (final img in widget.images) {
      if (img.diskId == diskId) return img;
    }
    return null;
  }

  /// vue:326-329。打开时配置节下拉初值：优先回填当前 config_id 命中的节；
  /// 命中不了才退 KEEP；镜像是「不选/保持原值」时留 null 走 placeholder
  int? _initialConfigOf(int diskId, int? originConfigId) {
    if (diskId <= 0) return null;
    return hitSectionConfigId(_imageOf(diskId), originConfigId) ?? kKeep;
  }

  _EditRow _makeDailyRow() =>
      _EditRow(diskId: kKeep, configId: null, virtualSecurity: emptyVirtualSecurity());

  _EditRow _makeTempRow() =>
      _EditRow(diskId: 0, configId: null, virtualSecurity: emptyVirtualSecurity());

  /// vue:409-451。单台挂 plan：日常区回填 restore_image、临时区回填当前生效 rows
  /// + 到期时间；单台无 plan：日常回填 rows、临时留空；批量：两区留空
  void _resetForm() {
    _errorText = '';

    final daily = _dailyOriginRows;
    _dailyRows = List.generate(kImageSlotCount, (i) {
      if (daily == null) return _makeDailyRow();
      final slot = i < daily.length ? daily[i] : null;
      // restore_image 的槽可缺省（= KEEP），原样带过来由「保持原值」项承载
      final nextDisk = slot?.diskId ?? 0;
      return _EditRow(
        diskId: nextDisk,
        // 原 config_id 可能是节内配置点；下拉只让选节，回填成所属节根
        configId: _initialConfigOf(nextDisk, slot?.configId),
        // vs 缺省归一成全 false —— 未 touched 时提交整体省略 = 保持
        virtualSecurity: normalizeVirtualSecurity(slot?.virtualSecurity),
      );
    });
    _dailyInitConfig = _dailyRows.map((r) => r.configId).toList();

    final temp = _tempOriginRows;
    _tempRows = List.generate(kImageSlotCount, (i) {
      if (temp == null) return _makeTempRow();
      final slot = i < temp.length ? temp[i] : null;
      final nextDisk = slot?.diskId ?? 0;
      return _EditRow(
        diskId: nextDisk,
        configId: _initialConfigOf(nextDisk, slot?.configId),
        virtualSecurity: normalizeVirtualSecurity(slot?.virtualSecurity),
      );
    });
    _tempInitConfig = _tempRows.map((r) => r.configId).toList();
    _dailyVsTouched = List.filled(kImageSlotCount, false);
    _tempVsTouched = List.filled(kImageSlotCount, false);

    if (_hasPlan) {
      final d = DateTime.fromMillisecondsSinceEpoch(_singleCfg!.restoreTime * 1000);
      _expireDate = DateTime(d.year, d.month, d.day);
      _expireTime = TimeOfDay(hour: d.hour, minute: d.minute);
    } else {
      _expireDate = null;
      _expireTime = null;
    }
    _dateTouched = false;
    _timeTouched = false;
  }

  // ===== 到期时间 =====

  int get _origSecond => _hasPlan
      ? DateTime.fromMillisecondsSinceEpoch(_singleCfg!.restoreTime * 1000).second
      : 0;

  /// 日期 + 时间拼 Unix 秒；任一为空 = 不启用临时镜像（不带 restore_time/image_tmp）。
  /// 两个控件都没动过时原样沿用后端 restore_time —— 重拼会截掉秒，等于每次编辑都改了时间
  int get _restoreUnix {
    final d = _expireDate;
    final t = _expireTime;
    if (d == null || t == null) return 0;
    if (_hasPlan && !_dateTouched && !_timeTouched) return _singleCfg!.restoreTime;
    final sec = _timeTouched ? 0 : _origSecond;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute, sec)
            .millisecondsSinceEpoch ~/
        1000;
  }

  /// vue:370-377。日期/时间是两个独立控件，只填一个 restoreUnix 是 0，界面上却像填了
  String get _expireHint {
    if (_expireDate != null && _expireTime == null) return '还要填时间，只填日期不会生效';
    if (_expireDate == null && _expireTime != null) return '还要填日期，只填时间不会生效';
    // hasPlan 时清空时间 = 撤销（合法操作），不能提示「必须填时间」跟撤销警告打架
    if (_tempPicked && _restoreUnix == 0 && !_hasPlan) return '选了临时镜像就必须填到期时间';
    if (_restoreUnix > 0) return checkRestoreTime(_restoreUnix);
    return '';
  }

  /// vue:384-394。不带 restore_time 的提交 = 撤销该机已有计划，批量时用户看不见
  /// 各机挂着什么，必须在点确定之前讲清楚
  int get _revokeSeatCount => _restoreUnix > 0
      ? 0
      : widget.seats
          .where((s) => (widget.clientCfgMap[s.id]?.restoreTime ?? 0) > 0)
          .length;

  String get _revokeWarning {
    final n = _revokeSeatCount;
    if (n == 0) return '';
    return _isBatch
        ? '选中的机器里有 $n 台正挂着临时镜像，这次提交会把它们一并撤销、立即切回日常镜像'
        : '到期时间为空 = 撤销该机的临时镜像，提交后立即切回日常镜像';
  }

  bool _daySelectable(DateTime day, ({int min, int max}) range) {
    final dayStart = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch ~/ 1000;
    // 整天落在时间窗之外的日期禁掉，少一次提交后才报错的往返（vue:397-401）
    return !(dayStart + 86399 < range.min || dayStart > range.max);
  }

  Future<void> _pickDate() async {
    final range = restoreTimeRange();
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final lastRaw = DateTime.fromMillisecondsSinceEpoch(range.max * 1000);
    final last = DateTime(lastRaw.year, lastRaw.month, lastRaw.day);
    var init = _expireDate ?? first;
    if (init.isBefore(first)) init = first;
    if (init.isAfter(last)) init = last;
    // showDatePicker 断言 initialDate 必须可选：向后找到首个可选日
    while (!_daySelectable(init, range) && init.isBefore(last)) {
      init = DateTime(init.year, init.month, init.day + 1);
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
      selectableDayPredicate: (d) => _daySelectable(d, range),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _expireDate = DateTime(picked.year, picked.month, picked.day);
      _dateTouched = true;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _expireTime ?? const TimeOfDay(hour: 0, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _expireTime = picked;
      _timeTouched = true;
    });
  }

  // ===== 配置节下拉 =====

  /// 原值里的 config_id 可能是 KEEP 哨兵（restore_image 字段缺省），只有正数才是真配置点
  int _currentConfigIdOf(ImageSlot? origin) {
    final id = origin?.configId;
    return (id != null && id > 0) ? id : 0;
  }

  /// vue:474-475。换了镜像必须 false（原 config_id 属旧镜像，后端 400）；
  /// 没换镜像时回填已把当前节选中，只有回填不出来（初值落 KEEP）才需要兜底
  bool _allowConfigKeep(_EditRow row, ImageSlot? origin, int? initConfig) =>
      origin != null && origin.diskId == row.diskId && initConfig == kKeep;

  List<ConfigOption> _configOptionsOf(_EditRow row, int i, {required bool daily}) {
    final img = _imageOf(row.diskId);
    if (img == null) return const [];
    final origin = daily ? _dailyOriginRows : _tempOriginRows;
    final originSlot = (origin != null && i < origin.length) ? origin[i] : null;
    final initConfig = daily ? _dailyInitConfig[i] : _tempInitConfig[i];
    return buildConfigOptions(
      img,
      _currentConfigIdOf(originSlot),
      _allowConfigKeep(row, originSlot, initConfig),
    );
  }

  /// vue:501-515。换镜像：配置节必须重选，默认落新镜像第一节；
  /// 换回原镜像：恢复打开时的回填值（与 allowConfigKeep 给的选项保持一致）
  void _pickConfigOnDiskChange(
      _EditRow row, ImageSlot? origin, int nextDiskId, int? initConfig) {
    if (nextDiskId == kKeep || nextDiskId == 0) {
      row.configId = null;
      return;
    }
    if (origin != null && origin.diskId == nextDiskId) {
      row.configId = initConfig;
      return;
    }
    final img = _imageOf(nextDiskId);
    row.configId = img != null && img.sections.isNotEmpty
        ? img.sections.first.configId
        : null;
  }

  void _onDiskChanged(int i, int next, {required bool daily}) {
    final row = daily ? _dailyRows[i] : _tempRows[i];
    // Flutter Dropdown 选中同值也回调；同值时不能重置用户已选的配置节
    if (next == row.diskId) return;
    final origin = daily ? _dailyOriginRows : _tempOriginRows;
    final originSlot = (origin != null && i < origin.length) ? origin[i] : null;
    final initConfig = daily ? _dailyInitConfig[i] : _tempInitConfig[i];
    setState(() {
      row.diskId = next;
      _pickConfigOnDiskChange(row, originSlot, next, initConfig);
    });
  }

  // ===== 虚拟安全 =====

  /// vue:524-531。cloud 整机一份：任一行改动同步到其余三行，否则后端判「自相矛盾」
  void _syncVsRows(List<_EditRow> rows, int i) {
    if (!_vsShared) return;
    final src = rows[i].virtualSecurity;
    for (var idx = 0; idx < rows.length; idx++) {
      if (idx == i) continue;
      for (final k in kVsKeys) {
        rows[idx].virtualSecurity[k.key] = src[k.key] ?? false;
      }
    }
  }

  /// 评审 M2 写死：cloud 动任何一行 = 该组全 true；否则只标该行
  void _markVsTouched(List<bool> touched, int i) {
    if (_vsShared) {
      for (var idx = 0; idx < touched.length; idx++) {
        touched[idx] = true;
      }
    } else {
      touched[i] = true;
    }
  }

  /// vue:559-564。不让改的两种情况：槽是「不选」（空槽开关无意义，后端强制清零）；
  /// 后端明确没把该开关拉下来。批量无单台原值，只按第 1 条
  bool _vsDisabled(_EditRow row, String key) {
    if (row.diskId == 0) return true;
    if (_isBatch) return false;
    final present = _vsSupported;
    return present != null && !(present[key] ?? false);
  }

  void _onVsChanged(int i, String key, bool value, {required bool daily}) {
    final rows = daily ? _dailyRows : _tempRows;
    final touched = daily ? _dailyVsTouched : _tempVsTouched;
    setState(() {
      rows[i].virtualSecurity[key] = value;
      _syncVsRows(rows, i);
      _markVsTouched(touched, i);
    });
  }

  // ===== 提交 =====

  ImageSlot _toSlot(_EditRow r) => ImageSlot(
      diskId: r.diskId, configId: r.configId, virtualSecurity: r.virtualSecurity);

  List<ImageSlot> _toSlots(List<_EditRow> rows) =>
      rows.map(_toSlot).toList(growable: false);

  /// vue:582-586。配置节回填值只负责展示，用户没动过就不该下发 —— 机器实际挂的
  /// 可能是节内硬件专属配置点，下发节根会让 srv 重新分派。镜像没换 + 配置没动 →
  /// 还原 KEEP（= 字段缺省 = 保持）
  List<ImageSlot> _rowsForSubmit(
      List<_EditRow> rows, List<ImageSlot>? originRows, List<int?> initConfig) {
    return List.generate(rows.length, (i) {
      final row = rows[i];
      final origin =
          (originRows != null && i < originRows.length) ? originRows[i] : null;
      final diskUnchanged = originRows != null && origin?.diskId == row.diskId;
      final configUntouched =
          row.configId != null && row.configId == initConfig[i];
      if (diskUnchanged && configUntouched) {
        return ImageSlot(
            diskId: row.diskId, configId: kKeep, virtualSecurity: row.virtualSecurity);
      }
      return _toSlot(row);
    }, growable: false);
  }

  /// 临时区是否选了镜像 —— 与到期时间必须成对，缺一后端 400
  bool get _tempPicked => _tempRows.any((r) => r.diskId > 0);

  void _showError(String msg) {
    setState(() => _errorText = msg);
    if (msg.isEmpty) return;
    showTopNotice(context, msg, level: NoticeLevel.warning);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_bodyScrollCtrl.hasClients) return;
      _bodyScrollCtrl.animateTo(
        _bodyScrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// vue:591-711 的提交链：成对校验 → 逐台 merge 后校验 → 串行提交
  Future<void> _onSubmit() async {
    setState(() => _errorText = '');
    if (widget.platform.isEmpty) {
      _showError('未识别到无盘平台，无法提交');
      return;
    }
    if (widget.seats.isEmpty) {
      _showError('未选择客户机');
      return;
    }

    // 到期时间与临时镜像必须成对：后端 restore_time / image_tmp 缺一即 400
    final restoreTime = _restoreUnix;
    if (restoreTime > 0 && !_tempPicked) {
      _showError('填了到期时间就必须选临时镜像，否则这些机器会没有可启动的镜像');
      return;
    }
    // hasPlan 时临时区回填的是当前生效的临时镜像，tempPicked 必然 true，
    // 清空到期时间正是撤销这条路 —— 拿 tempPicked 拦会把撤销堵死（vue:609-611）
    if (restoreTime == 0 && _tempPicked && !_hasPlan) {
      _showError('选了临时镜像就必须填完整的到期时间（日期 + 时间），否则不会下发');
      return;
    }
    if (restoreTime > 0) {
      final timeErr = checkRestoreTime(restoreTime);
      if (timeErr.isNotEmpty) {
        _showError(timeErr);
        return;
      }
    }

    // 该机日常镜像的原值：挂着 plan 时是 restore_image，否则是当前 rows
    List<ImageSlot>? dailyOriginOf(ClientCfg? cfg) =>
        (cfg?.restoreTime ?? 0) > 0 ? cfg?.restoreRows : cfg?.rows;

    final dailySlots = _toSlots(_dailyRows);
    final tempSlots = _toSlots(_tempRows);

    // 逐台按「合并后」的最终 4 槽做校验：后端的连续性约束校验的就是合并结果
    final failures = <String>[];
    for (final seat in widget.seats) {
      final cfg = widget.clientCfgMap[seat.id];
      final dailyOrigin = dailyOriginOf(cfg);
      var dailyErr = checkSlotContiguity(mergeRows(dailySlots, dailyOrigin));
      if (dailyErr.isEmpty) {
        dailyErr = checkConfigOnDiskChange(dailySlots, dailyOrigin);
      }
      if (dailyErr.isNotEmpty) {
        failures.add('${seat.id}：日常镜像 $dailyErr');
        continue;
      }
      if (restoreTime > 0) {
        // 临时镜像立即下发，比对基准是当前生效的 rows
        final current = cfg?.rows;
        var tempErr = checkSlotContiguity(mergeRows(tempSlots, current));
        if (tempErr.isEmpty) {
          tempErr = checkConfigOnDiskChange(tempSlots, current);
        }
        if (tempErr.isNotEmpty) failures.add('${seat.id}：临时镜像 $tempErr');
      }
    }
    if (failures.isNotEmpty) {
      _showError(failures.take(3).join('；') +
          (failures.length > 3 ? ' 等 ${failures.length} 项' : ''));
      return;
    }

    final revoking = restoreTime == 0 &&
        widget.seats
            .any((s) => (widget.clientCfgMap[s.id]?.restoreTime ?? 0) > 0);

    setState(() => _submitting = true);
    final okSeats = <String>[];
    final errSeats = <String>[];
    try {
      // 串行提交（vue:656）：批量并发会打垮服务端下游 RPC（502），逐台更稳
      for (final seat in widget.seats) {
        final cfg = widget.clientCfgMap[seat.id];
        final dailyOrigin = dailyOriginOf(cfg);
        final tempOrigin = cfg?.rows;

        // 评审 M2 逐台判定：「保持原值」会被后端理解成「保持临时镜像」的两种情况
        // （本次挂计划 / 该台已挂计划）都必须把日常镜像逐字段落实，否则到期/撤销后
        // 机器留在临时镜像上，日常镜像再也回不来（vue:662-669）
        final needExplicit = restoreTime > 0 || (cfg?.restoreTime ?? 0) > 0;
        final dailySubmit = needExplicit
            ? resolveRestoreTarget(dailySlots, dailyOrigin, _dailyVsTouched)
            : _rowsForSubmit(_dailyRows, dailyOrigin, _dailyInitConfig);

        final body = buildSetClientCfgBody(
          dailySubmit,
          dailyOrigin,
          widget.platform,
          restore: restoreTime > 0
              ? RestoreSpec(
                  tempRows: _rowsForSubmit(_tempRows, tempOrigin, _tempInitConfig),
                  tempOriginRows: tempOrigin,
                  restoreTime: restoreTime,
                )
              : null,
          explicit: needExplicit,
          vsTouched: _dailyVsTouched,
          tempVsTouched: _tempVsTouched,
        );
        final res = await widget.api.setClientCfg(
          platform: widget.platform,
          seat: seat.id,
          body: body,
        );
        if (res.ok) {
          okSeats.add(seat.id);
        } else {
          errSeats.add(
              '${seat.id}：${humanizeCfgError(res.error ?? 'HTTP ${res.status}')}');
        }
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (!mounted) return;

    if (errSeats.isNotEmpty) {
      _showError(errSeats.take(3).join('；') +
          (errSeats.length > 3 ? ' 等 ${errSeats.length} 项失败' : ''));
    }
    if (okSeats.isNotEmpty) {
      if (restoreTime > 0) {
        showTopNotice(context, '已保存 ${okSeats.length} 台，临时镜像已下发，到期后自动切回日常镜像',
            level: NoticeLevel.success);
      } else if (revoking) {
        // 不带 restore_time 的提交会清掉已有计划（API §5.17「撤销」），用户未必察觉
        showTopNotice(context, '已保存 ${okSeats.length} 台，原有的临时镜像已撤销',
            level: NoticeLevel.success);
      } else {
        showTopNotice(context, '已保存 ${okSeats.length} 台', level: NoticeLevel.success);
      }
      widget.onSaved?.call(okSeats);
      if (errSeats.isEmpty) Navigator.of(context).pop();
    }
  }

  // ===== 构建 =====

  String get _seatScopeText {
    if (widget.seats.isEmpty) return '';
    if (widget.seats.length == 1) {
      final s = widget.seats[0];
      return s.name.isNotEmpty ? s.name : s.id;
    }
    return '已选 ${widget.seats.length} 台';
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '配置镜像',
      maxWidth: 1080,
      scrollableBody: false,
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _bodyScrollCtrl,
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, cons) {
                final compact = cons.maxWidth < 560;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildScopeRow(),
                    const SizedBox(height: 12),
                    _buildSectionTitle(daily: true),
                    const SizedBox(height: 8),
                    compact ? _buildSlotCards(daily: true) : _buildSlotTable(daily: true),
                    const SizedBox(height: 18),
                    _buildSectionTitle(daily: false),
                    const SizedBox(height: 8),
                    compact
                        ? _buildSlotCards(daily: false)
                        : _buildSlotTable(daily: false),
                    const SizedBox(height: 10),
                    _buildExpireRow(),
                    if (_errorText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          border: Border.all(color: const Color(0xFFFECACA)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _errorText,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFB91C1C), height: 1.5),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          if (_submitting)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.white.withOpacity(0.5),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _submitting ? null : _onSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeRow() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message: widget.seats.map((s) => s.id).join('、'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _seatScopeText,
              style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFECFEFF),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            kPlatformLabel[widget.platform] ?? widget.platform,
            style: const TextStyle(fontSize: 11, color: Color(0xFF0E7490)),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle({required bool daily}) {
    final children = <Widget>[
      Text(
        daily ? '日常镜像' : '临时镜像',
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
      ),
    ];
    if (daily) {
      String? hint;
      if (_hasPlan) {
        hint = '该机正挂着临时镜像，这里填的是到期后要恢复成的配置';
      } else if (_isBatch) {
        hint = '批量编辑：未改动的行保持各机器原值';
      } else if (_vsShared) {
        hint = '${kPlatformLabel[widget.platform] ?? widget.platform}的虚拟安全为整机一份，四行同步';
      }
      if (hint != null) {
        children.add(Text(hint,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))));
      }
    } else {
      children.add(const Text('（临时镜像到期后会自动切回日常镜像）',
          style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))));
      final warn = _revokeWarning;
      if (warn.isNotEmpty) {
        children.add(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            border: Border.all(color: const Color(0xFFFDE68A)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(warn,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
        ));
      }
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  // ===== 宽屏表格 =====

  Widget _buildSlotTable({required bool daily}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF9FAFB),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: const Row(
              children: [
                SizedBox(
                    width: 72,
                    child: Text('顺序',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
                Expanded(
                    flex: 3,
                    child: Text('镜像',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
                SizedBox(width: 10),
                Expanded(
                    flex: 3,
                    child: Text('配置点',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
                SizedBox(width: 10),
                Expanded(
                    flex: 4,
                    child: Text('虚拟安全',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
              ],
            ),
          ),
          for (var i = 0; i < kImageSlotCount; i++) ...[
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(kSlotLabels[i],
                        style:
                            const TextStyle(fontSize: 13, color: Color(0xFF374151))),
                  ),
                  Expanded(flex: 3, child: _buildImageDropdown(i, daily: daily)),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: _buildConfigDropdown(i, daily: daily)),
                  const SizedBox(width: 10),
                  Expanded(flex: 4, child: _buildVsChecks(i, daily: daily)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===== 手机端按槽折叠卡片 =====

  Widget _buildSlotCards({required bool daily}) {
    return Column(
      children: [
        for (var i = 0; i < kImageSlotCount; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(kSlotLabels[i],
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151))),
                const SizedBox(height: 8),
                _buildImageDropdown(i, daily: daily),
                const SizedBox(height: 8),
                _buildConfigDropdown(i, daily: daily),
                const SizedBox(height: 6),
                _buildVsChecks(i, daily: daily),
              ],
            ),
          ),
      ],
    );
  }

  // ===== 单元控件 =====

  Widget _dropdownShell(Widget child) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }

  Widget _buildImageDropdown(int i, {required bool daily}) {
    final row = daily ? _dailyRows[i] : _tempRows[i];
    final items = <DropdownMenuItem<int>>[
      if (daily && _allowDailyKeep)
        const DropdownMenuItem(value: kKeep, child: Text('保持原值')),
      const DropdownMenuItem(value: 0, child: Text('不选')),
      // diskId<=0 的脏数据会与「不选」撞 value 触发 Dropdown 断言，滤掉
      for (final img in widget.images)
        if (img.diskId > 0)
          DropdownMenuItem(
              value: img.diskId,
              child: Text(img.name, overflow: TextOverflow.ellipsis)),
    ];
    // value 必须在 items 里（Dropdown 断言），rows 挂着服务端已删除的镜像 id 时兜底补项
    if (!items.any((it) => it.value == row.diskId)) {
      items.add(DropdownMenuItem(
          value: row.diskId, child: Text('镜像 ${row.diskId}')));
    }
    return _dropdownShell(DropdownButton<int>(
      value: row.diskId,
      isExpanded: true,
      isDense: true,
      style: const TextStyle(fontSize: 13, color: Colors.black87),
      icon: const Icon(LucideIcons.chevronDown, size: 12),
      items: items,
      onChanged: _submitting
          ? null
          : (v) {
              if (v == null) return;
              _onDiskChanged(i, v, daily: daily);
            },
    ));
  }

  Widget _buildConfigDropdown(int i, {required bool daily}) {
    final row = daily ? _dailyRows[i] : _tempRows[i];
    final img = _imageOf(row.diskId);
    final options = img == null
        ? const <ConfigOption>[]
        : _configOptionsOf(row, i, daily: daily);
    // value 兜底：选项里没有当前值时显示 placeholder，绝不把 KEEP/-1 漏进框里
    final hasValue =
        options.any((o) => !o.disabled && o.value == row.configId);
    return _dropdownShell(DropdownButton<int?>(
      value: hasValue ? row.configId : null,
      isExpanded: true,
      isDense: true,
      hint: Text(
        img != null ? '请选择' : '—',
        style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
      ),
      style: const TextStyle(fontSize: 13, color: Colors.black87),
      icon: const Icon(LucideIcons.chevronDown, size: 12),
      items: [
        for (final opt in options)
          DropdownMenuItem<int?>(
            value: opt.value,
            enabled: !opt.disabled,
            child: Text(
              opt.label,
              overflow: TextOverflow.ellipsis,
              style: opt.disabled
                  ? const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))
                  : null,
            ),
          ),
      ],
      onChanged: (img == null || _submitting)
          ? null
          : (v) {
              if (v == null) return;
              setState(() => row.configId = v);
            },
    ));
  }

  Widget _buildVsChecks(int i, {required bool daily}) {
    final row = daily ? _dailyRows[i] : _tempRows[i];
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        for (final vs in kVsKeys)
          _vsCheckbox(
            label: vs.label,
            value: row.virtualSecurity[vs.key] ?? false,
            disabled: _vsDisabled(row, vs.key) || _submitting,
            onChanged: (v) => _onVsChanged(i, vs.key, v, daily: daily),
          ),
      ],
    );
  }

  Widget _vsCheckbox({
    required String label,
    required bool value,
    required bool disabled,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: disabled ? null : () => onChanged(!value),
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: disabled ? null : (v) => onChanged(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              activeColor: AppColors.iosBlue,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: disabled ? const Color(0xFF9CA3AF) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // ===== 到期时间行 =====

  String get _dateText {
    final d = _expireDate;
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String get _timeText {
    final t = _expireTime;
    if (t == null) return '';
    final sec = _timeTouched ? 0 : _origSecond;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Widget _buildExpireRow() {
    final hint = _expireHint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('到期时间',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            _pickerField(
              icon: LucideIcons.calendar,
              text: _dateText,
              placeholder: '年-月-日',
              width: 132,
              onTap: _pickDate,
              onClear: () => setState(() {
                _expireDate = null;
                _dateTouched = true;
              }),
            ),
            _pickerField(
              icon: LucideIcons.clock,
              text: _timeText,
              placeholder: '00:00:00',
              width: 118,
              onTap: _pickTime,
              onClear: () => setState(() {
                _expireTime = null;
                _timeTouched = true;
              }),
            ),
          ],
        ),
        if (hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(hint,
                style: const TextStyle(fontSize: 12, color: Color(0xFFB45309))),
          ),
      ],
    );
  }

  Widget _pickerField({
    required IconData icon,
    required String text,
    required String placeholder,
    required double width,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final hasValue = text.isNotEmpty;
    return InkWell(
      onTap: _submitting ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: const Color(0xFF9CA3AF)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hasValue ? text : placeholder,
                style: TextStyle(
                  fontSize: 13,
                  color: hasValue ? Colors.black87 : const Color(0xFF9CA3AF),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasValue)
              InkWell(
                onTap: _submitting ? null : onClear,
                child: const Icon(LucideIcons.xCircle,
                    size: 13, color: Color(0xFF9CA3AF)),
              ),
          ],
        ),
      ),
    );
  }
}
