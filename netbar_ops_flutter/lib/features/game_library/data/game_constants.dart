import 'package:flutter/painting.dart';

/// 平台 key（与后端 game_library 服务字段对齐）
const String kPlatformIcafe8 = 'icafe8';
const String kPlatformCloud = 'cloud';
const String kPlatformGoodgame = 'goodgame';
const String kPlatformStory = 'story';

/// 全部支持的平台 key（顺序影响 UI 遍历）
const List<String> kAllPlatforms = [
  kPlatformIcafe8,
  kPlatformCloud,
  kPlatformGoodgame,
  kPlatformStory,
];

/// 平台 -> 友好中文名
const Map<String, String> kPlatformLabel = {
  kPlatformIcafe8: '网维大师',
  kPlatformCloud: '云更新',
  kPlatformGoodgame: '盖伦',
  kPlatformStory: '蘑菇',
};

/// 平台主色（Tailwind 调色板风格，与 Web 版一致）
const Map<String, Color> kPlatformAccent = {
  kPlatformIcafe8: Color(0xFF409EFF),
  kPlatformCloud: Color(0xFF10B981),
  kPlatformGoodgame: Color(0xFFF59E0B),
  kPlatformStory: Color(0xFFEC4899),
};

/// 平台主色（弱化版，用作背景）
const Map<String, Color> kPlatformAccentSoft = {
  kPlatformIcafe8: Color(0x1A409EFF),
  kPlatformCloud: Color(0x1A10B981),
  kPlatformGoodgame: Color(0x1FF59E0B),
  kPlatformStory: Color(0x1AEC4899),
};

Color platformAccent(String? platform) =>
    kPlatformAccent[platform] ?? const Color(0xFF6B7280);

Color platformAccentSoft(String? platform) =>
    kPlatformAccentSoft[platform] ?? const Color(0x1A6B7280);

/// 游戏状态枚举（与后端 §4 文档对齐）
class GameStatus {
  static const int notDownloaded = 0;
  static const int downloaded = 1;
  static const int downloading = 2;
  static const int pendingUpdate = 3;
  static const int deleted = 4;
  static const int waiting = 5;
  static const int paused = 6;
  static const int deleting = 7;
  static const int indexing = 8;
  static const int unknown = 9;
}

/// 状态 -> 文案
const Map<int, String> kGameStatusLabel = {
  0: '未下载',
  1: '已下载',
  2: '下载中',
  3: '待更新',
  4: '已删除',
  5: '等待中',
  6: '已暂停',
  7: '正在删除',
  8: '准备中',
  9: '未知',
};

/// 行渲染状态（前端推导，非后端字段）
enum GameRowState { installed, upgrade, deprecated, pending }

const Map<GameRowState, String> kGameRowStateLabel = {
  GameRowState.installed: '已下载',
  GameRowState.upgrade: '可更新',
  GameRowState.deprecated: '已废弃',
  GameRowState.pending: '未下载',
};

/// 触底加载相关
const int kRenderBatch = 40;
const double kLoadMoreDistance = 360.0;

/// downloads tab 轮询周期
const Duration kDownloadPollInterval = Duration(seconds: 2);

/// 搜索防抖
const Duration kSearchDebounce = Duration(milliseconds: 150);

/// 工具箱身份：seat picker 未选机号时使用。配合 from='wwls' 旁路 seat 单任务约束。
/// 与真实机号不冲突（真实机号普遍 'A001'/'B-12' 短串）。
const String kToolboxSeat = 'WW_TOOLBOX';

/// 受保护分类：命中则跳过自动回收 / 闲置列表（与 Web 端 isProtectedCategory 对齐）
const Map<String, List<String>> kProtectedCatsByPlatform = {
  kPlatformIcafe8: ['系统更新', '客户机系统补丁'],
  kPlatformGoodgame: ['系统更新', '客户机系统补丁'],
  kPlatformCloud: ['显卡PNP', '系统资源'],
  kPlatformStory: ['显卡PNP'],
};

/// 全平台一刀切的受保护分类
const String kProtectedCatLocalApp = '网吧本地应用';

/// 回收策略默认值（与 Web 端 RECYCLE_DEFAULTS 对齐）
/// freeThreshold = 90 是「占用%」UI 语义；API 存的是「剩余%」（100-X 反转在 api 层做）
/// delFlags=3 = bit1|bit2，同时回收"从未启动 + 云端下架"，与 retain_days 配合还会回收 expired
class RecycleDefaults {
  static const int freeThresholdUi = 90; // 占用%
  static const int retainDays = 30;
  static const String time = '06:00';
  static const int delFlags = 3;
  static const List<int> weekdays = []; // 空数组 → 未配置
}

/// 周天选项（周一在前更符合中文习惯）。value 仍按 Go time.Weekday: Sun=0..Sat=6
class WeekdayOption {
  final int value;
  final String label;
  const WeekdayOption(this.value, this.label);
}

const List<WeekdayOption> kWeekdayOptions = [
  WeekdayOption(1, '周一'),
  WeekdayOption(2, '周二'),
  WeekdayOption(3, '周三'),
  WeekdayOption(4, '周四'),
  WeekdayOption(5, '周五'),
  WeekdayOption(6, '周六'),
  WeekdayOption(0, '周日'),
];
