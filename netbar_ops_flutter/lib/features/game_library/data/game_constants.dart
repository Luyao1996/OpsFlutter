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
