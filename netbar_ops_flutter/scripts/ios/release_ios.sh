#!/usr/bin/env bash
#
# release_ios.sh —— Flutter -> iOS App Store 交互式发布脚本
# ============================================================================
# 适用项目: netbar_ops_flutter  (Bundle ID: com.netbarops.netbarOpsFlutter)
#
# 这个脚本【只能在 macOS 上运行】(iOS 编译/上传是 macOS 独占的)。
# 它假设你: ① 用自己的 Mac(已装 Xcode 16+); ② 用 App Store Connect API Key 上传;
#           ③ 用 Xcode 自动签名; ④ 完全没发布过 iOS app(所以每步都会详细提示)。
#
# 全流程分 6 个阶段, 失败即停, 改完可从断点重跑:
#   A 本地环境体检   (全自动·只读)
#   B 配置 + 认证预验证 (交互填 Team ID / Key ID / Issuer ID, 立即验证能认证)
#   C 网页/Xcode 暂停点1 (签协议→新建App记录→Xcode登录并生成证书)
#   D 构建            (处理 4 条上架红线→自增build号→生成ExportOptions→flutter build ipa)
#   E 上传            (先 validate 再 upload, 内置 ITMS 报错诊断)
#   F 网页/提审 暂停点2 (填元数据/截图/隐私问卷→选构建→提交审核)
#
# 用法:
#   ./release_ios.sh              # 跑完整流程 A->F
#   ./release_ios.sh --from D     # 从阶段 D 开始(修复后重跑常用)
#   ./release_ios.sh --only A     # 只跑某一个阶段
#   ./release_ios.sh -h           # 帮助
#
# 安全: 你的 .p8 私钥等同账号凭证, 脚本会确保它和 .env 永远不进 git。
# ============================================================================

set -uo pipefail

# 必须用 bash 运行(脚本用了数组/PIPESTATUS 等 bash 特性); 防止被 sh/zsh 误跑
if [ -z "${BASH_VERSION:-}" ]; then
  echo "请用 bash 运行: ./release_ios.sh 或 bash release_ios.sh (不要用 sh/zsh 执行)。" >&2
  exit 1
fi
# 统一 locale, 保证 flutter doctor 等多字节输出可被稳定匹配
export LANG="${LANG:-en_US.UTF-8}"

# ---------------------------------------------------------------------------
# 0. 基础: 路径 / 颜色 / 日志(遵循 [time][level][module][operType][contextId] message)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 项目根 = 脚本目录上两级 (scripts/ios -> 项目根)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.ipa_release.env"
LOG_DIR="$SCRIPT_DIR/logs"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/release_${RUN_ID}.log"

BUNDLE_ID="com.netbarops.netbarOpsFlutter"
INFO_PLIST="$PROJECT_ROOT/ios/Runner/Info.plist"
PBXPROJ="$PROJECT_ROOT/ios/Runner.xcodeproj/project.pbxproj"
PUBSPEC="$PROJECT_ROOT/pubspec.yaml"
IPA_DIR="$PROJECT_ROOT/build/ios/ipa"
EXPORT_OPTIONS="$PROJECT_ROOT/ios/ExportOptions.plist"
PRIVATE_KEYS_DIR="$HOME/.appstoreconnect/private_keys"

if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'; C_BOLD=$'\033[1m'; C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_BOLD=""; C_RST=""
fi

mkdir -p "$LOG_DIR" 2>/dev/null || true

_ts() { date '+%Y-%m-%d %H:%M:%S'; }
# 统一日志: 同时打印到终端(带色)和日志文件(无色)
_log() {
  local level="$1" oper="$2" msg="$3" color="$4"
  local line="[$(_ts)][$level][release_ios][$oper][$RUN_ID] $msg"
  printf '%s%s%s\n' "$color" "$line" "$C_RST"
  printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
}
log_info() { _log "INFO" "${2:-step}" "$1" "$C_BLU"; }
log_ok()   { _log "INFO" "${2:-ok}"   "$1" "$C_GRN"; }
log_warn() { _log "WARN" "${2:-warn}" "$1" "$C_YEL"; }
log_err()  { _log "ERROR" "${2:-err}" "$1" "$C_RED"; }

# 致命错误: 打印 "症状/原因/怎么办" 三段式, 然后退出
die() {
  local title="$1"; shift
  log_err "$title" "fatal"
  echo "${C_RED}${C_BOLD}"
  echo "================ 出错了, 请按下面处理 ================"
  echo " 现象: $title"
  for line in "$@"; do echo " $line"; done
  echo " 日志: $LOG_FILE"
  echo "===================================================="
  echo "${C_RST}"
  exit 1
}

# 让用户回车继续(网页/GUI 暂停点)
pause_for_user() {
  echo ""
  printf '%s>>> %s%s\n' "$C_YEL$C_BOLD" "$1" "$C_RST"
  read -r -p "    完成后按 [回车] 继续 (Ctrl+C 退出) ... " _ || true
  echo ""
}

# yes/no 询问, 默认值由第2参数给(y/n)
confirm() {
  local prompt="$1" def="${2:-n}" ans=""
  local hint="[y/N]"; [ "$def" = "y" ] && hint="[Y/n]"
  read -r -p "$prompt $hint " ans || true
  ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
  [ -z "$ans" ] && ans="$def"
  [ "$ans" = "y" ] || [ "$ans" = "yes" ]
}

# 命令是否存在
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# 版本号比较: ver_ge A B  -> A>=B 返回0。用 sort -V 不可靠时用纯数字拆分。
ver_ge() {
  # 取每段主.次.修做整数比较, 缺位补0
  local a="$1" b="$2"
  local IFS=.
  local -a aa bb
  # shellcheck disable=SC2206
  aa=($a); bb=($b)
  local i av bv
  for i in 0 1 2; do
    av="${aa[$i]:-0}"; bv="${bb[$i]:-0}"
    # 去掉非数字尾巴(如 16.2beta)
    av="$(printf '%s' "$av" | tr -cd '0-9')"; av="${av:-0}"
    bv="$(printf '%s' "$bv" | tr -cd '0-9')"; bv="${bv:-0}"
    if [ "$av" -gt "$bv" ]; then return 0; fi
    if [ "$av" -lt "$bv" ]; then return 1; fi
  done
  return 0
}

# 在 PROJECT_ROOT 执行
in_root() { ( cd "$PROJECT_ROOT" && "$@" ); }

# ---------------------------------------------------------------------------
# 配置读写: .ipa_release.env (git 之外, 存 Team ID/Key ID/Issuer ID/上次build号)
# ---------------------------------------------------------------------------
TEAM_ID=""; KEY_ID=""; ISSUER_ID=""; LAST_BUILD=""

load_env() {
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    TEAM_ID="${TEAM_ID:-}"; KEY_ID="${KEY_ID:-}"
    ISSUER_ID="${ISSUER_ID:-}"; LAST_BUILD="${LAST_BUILD:-}"
    log_info "已读取配置: $ENV_FILE" "config"
  fi
}

save_env() {
  umask 077
  cat > "$ENV_FILE" <<EOF
# 由 release_ios.sh 自动维护; 此文件含发布配置, 已被 .gitignore 忽略, 切勿提交。
TEAM_ID="$TEAM_ID"
KEY_ID="$KEY_ID"
ISSUER_ID="$ISSUER_ID"
LAST_BUILD="$LAST_BUILD"
EOF
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  log_ok "配置已保存: $ENV_FILE" "config"
}

# 确保 .gitignore 含敏感条目
ensure_gitignore() {
  local gi="$PROJECT_ROOT/.gitignore"
  local entries=("*.p8" "AuthKey_*.p8" "scripts/ios/.ipa_release.env" "scripts/ios/logs/" "*.bak.*" "ios/ExportOptions.plist")
  local added=0
  [ -f "$gi" ] || touch "$gi"
  local e
  for e in "${entries[@]}"; do
    if ! grep -qxF "$e" "$gi" 2>/dev/null; then
      [ "$added" -eq 0 ] && printf '\n# iOS 发布脚本: 敏感文件, 切勿提交\n' >> "$gi"
      printf '%s\n' "$e" >> "$gi"
      added=1
    fi
  done
  [ "$added" -eq 1 ] && log_ok ".gitignore 已追加敏感忽略规则" "git"
}

# ===========================================================================
# 阶段 A: 本地环境体检 (全自动·只读·可反复跑)
# ===========================================================================
phase_a_preflight() {
  echo "${C_BOLD}===== 阶段 A: 本地环境体检 =====${C_RST}"

  # A0 必须是 macOS
  if [ "$(uname -s)" != "Darwin" ]; then
    die "当前不是 macOS, 无法编译/上传 iOS app" \
        "iOS 构建链(Xcode/xcodebuild/CocoaPods/altool)只在 macOS 存在。" \
        "请把项目拷到一台装了 Xcode 16+ 的 Mac 上, 在 Mac 终端里运行本脚本。"
  fi
  log_ok "macOS: $(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))" "os"

  # A1 xcode-select 指向完整 Xcode 而非 CommandLineTools
  local devdir
  devdir="$(xcode-select -p 2>/dev/null || true)"
  case "$devdir" in
    *Xcode*.app*) log_ok "xcode-select 指向: $devdir" "xcode" ;;
    *CommandLineTools*|"")
      die "xcode-select 指向的是命令行工具而非完整 Xcode" \
          "当前: ${devdir:-未设置}" \
          "修复(会要求输入 Mac 密码):" \
          "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" \
          "若还没装完整 Xcode: 打开 Mac App Store 搜索 Xcode 安装(约十几GB), 装完重跑本脚本。"
      ;;
    *) log_warn "xcode-select 指向异常: $devdir (继续, 但若构建失败请检查)" "xcode" ;;
  esac

  # A2 Xcode 版本 >= 16 (2025-04-24 起 App Store 发布硬性要求, 不是 14)
  if ! has_cmd xcodebuild; then
    die "找不到 xcodebuild" \
        "说明没装完整 Xcode, 或 xcode-select 没指向 Xcode.app。" \
        "装好 Xcode 后执行: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  fi
  local xcode_ver xcode_major
  xcode_ver="$(xcodebuild -version 2>/dev/null | head -n1 | awk '{print $2}')"
  if [ -z "$xcode_ver" ]; then
    # 多半是没接受许可
    if xcodebuild -version 2>&1 | grep -qi 'license'; then
      log_warn "Xcode 许可未接受, 尝试自动接受(需 Mac 密码)..." "xcode"
      sudo xcodebuild -license accept || die "无法接受 Xcode 许可" \
          "请手动执行: sudo xcodebuild -license accept"
      xcode_ver="$(xcodebuild -version 2>/dev/null | head -n1 | awk '{print $2}')"
    fi
  fi
  [ -z "$xcode_ver" ] && die "无法读取 Xcode 版本" \
      "请打开一次 Xcode.app 完成首次初始化, 再执行 sudo xcodebuild -runFirstLaunch 后重跑。"
  xcode_major="$(printf '%s' "$xcode_ver" | cut -d. -f1 | tr -cd '0-9')"
  [ -n "$xcode_major" ] || die "无法解析 Xcode 主版本号: $xcode_ver" \
      "请执行 xcodebuild -version 确认输出格式是否正常(应形如 'Xcode 16.2')。"
  if [ "$xcode_major" -lt 16 ]; then
    die "Xcode 版本过低: $xcode_ver (App Store 要求 16+)" \
        "自 2025-04-24 起, 上传 App Store 的包必须用 Xcode 16+ / iOS 18 SDK 构建, 否则被拒。" \
        "请升级 Xcode 到 16 或更高(Mac App Store 或 developer.apple.com/download)。" \
        "注意: 不是'Xcode 14 就行', 发布必须 16+。"
  fi
  log_ok "Xcode: $xcode_ver (>=16 OK)" "xcode"

  # A3 接受许可(幂等, 已接受会很快返回)
  if xcodebuild -version 2>&1 | grep -qi 'license'; then
    sudo xcodebuild -license accept || true
  fi

  # A4 Flutter
  if ! has_cmd flutter; then
    die "找不到 flutter 命令" \
        "请安装 Flutter SDK 并把其 bin 目录加入 PATH(在 ~/.zshrc 里 export PATH=\"\$PATH:/路径/flutter/bin\"),"\
        "然后重开终端, 执行 flutter --version 确认后重跑本脚本。"
  fi
  log_ok "Flutter: $(flutter --version 2>/dev/null | head -n1)" "flutter"

  # A5 flutter doctor 的 iOS toolchain
  log_info "运行 flutter doctor 检查 iOS toolchain (稍等)..." "flutter"
  local doctor
  doctor="$(flutter doctor 2>&1 | tee -a "$LOG_FILE")"
  if printf '%s\n' "$doctor" | grep -A3 -i 'iOS toolchain' | grep -qiE '✗|✘|\[!\]|not installed|missing'; then
    log_warn "flutter doctor 报 iOS toolchain 有问题, 详情:" "flutter"
    printf '%s\n' "$doctor" | grep -A4 -i 'iOS toolchain'
    confirm "iOS toolchain 未完全通过, 是否仍要继续?" "n" || \
      die "请先按上面 flutter doctor 的提示修复 iOS toolchain" \
          "常见: 装/修 CocoaPods, 或在 Xcode 里同意许可。修好执行 flutter doctor 全绿后重跑。"
  else
    log_ok "flutter doctor: iOS toolchain 看起来正常" "flutter"
  fi

  # A6 CocoaPods + Ruby 来源
  if ! has_cmd pod; then
    die "找不到 CocoaPods (pod 命令)" \
        "Flutter iOS 构建需要它。推荐用 Homebrew 安装(自带较新 Ruby, 避开系统 Ruby 权限坑):" \
        "  brew install cocoapods" \
        "(不要用 sudo gem install 装到系统 Ruby) 装完执行 pod --version 确认后重跑。"
  fi
  log_ok "CocoaPods: $(pod --version 2>/dev/null)" "pod"
  local ruby_path
  ruby_path="$(command -v ruby || true)"
  if [ "$ruby_path" = "/usr/bin/ruby" ]; then
    log_warn "正在用 macOS 系统 Ruby ($(ruby -v 2>/dev/null | awk '{print $2}'))。若后续 pod 报权限/版本错," "ruby"
    log_warn "  建议 brew install cocoapods, 或用 rbenv/mise 装新 Ruby。" "ruby"
  fi

  # A7 磁盘空间(BSD df: 用 -k 取可用 KB 再换算, 避免 -g 在 APFS 上行为不一致)
  local avail_kb avail_gb
  avail_kb="$(df -k "$PROJECT_ROOT" 2>/dev/null | awk 'NR==2{print $4}')"
  if printf '%s' "$avail_kb" | grep -qE '^[0-9]+$'; then
    avail_gb=$(( avail_kb / 1024 / 1024 ))
    if [ "$avail_gb" -lt 15 ]; then
      log_warn "磁盘可用空间约 ${avail_gb}GB, 偏低(建议>=15GB), 构建可能中途失败。" "disk"
    else
      log_ok "磁盘可用空间约 ${avail_gb}GB" "disk"
    fi
  fi

  # A8 网络
  if curl -sI --max-time 8 https://www.apple.com >/dev/null 2>&1; then
    log_ok "网络可达 apple.com" "net"
  else
    log_warn "访问 apple.com 失败, pub get/pod install/上传可能受影响, 请检查网络/代理。" "net"
  fi

  log_ok "阶段 A 通过" "phaseA"
  echo ""
}

# ===========================================================================
# 阶段 B: 收集并持久化配置 + 认证预验证
# ===========================================================================
# 提示用户输入并校验, 用法: prompt_validate 变量名 提示 正则 当前值
prompt_validate() {
  local __var="$1" prompt="$2" regex="$3" cur="$4" val=""
  while true; do
    if [ -n "$cur" ]; then
      read -r -p "$prompt [当前: $cur, 直接回车沿用] " val \
        || die "读取输入失败(非交互环境?)" "本脚本需在交互式终端运行, 不要用管道/重定向喂入。"
      [ -z "$val" ] && val="$cur"
    else
      read -r -p "$prompt " val \
        || die "读取输入失败(非交互环境?)" "本脚本需在交互式终端运行, 不要用管道/重定向喂入。"
    fi
    if printf '%s' "$val" | grep -qE "$regex"; then
      eval "$__var=\"\$val\""
      return 0
    fi
    log_warn "格式不对, 请重新输入(要求匹配: $regex)" "input"
  done
}

phase_b_config() {
  echo "${C_BOLD}===== 阶段 B: 配置 + 认证预验证 =====${C_RST}"
  ensure_gitignore
  load_env

  # B1 Team ID (10 位大写字母数字)
  echo "Team ID 在哪看: 浏览器登录 https://developer.apple.com/account -> Membership details -> Team ID"
  echo "  (也可在 Xcode > Settings > Accounts 选中团队查看)"
  prompt_validate TEAM_ID "请输入 Team ID:" '^[A-Z0-9]{10}$' "$TEAM_ID"

  # B2 .p8 / Key ID / Issuer ID
  mkdir -p "$PRIVATE_KEYS_DIR"
  local found_p8 auto_keyid=""
  found_p8="$(ls "$PRIVATE_KEYS_DIR"/AuthKey_*.p8 2>/dev/null | head -n1 || true)"
  if [ -z "$found_p8" ]; then
    echo ""
    echo "${C_YEL}未在 $PRIVATE_KEYS_DIR 找到 .p8 私钥。请先创建 API Key:${C_RST}"
    echo "  1) 浏览器打开 https://appstoreconnect.apple.com"
    echo "  2) Users and Access(用户和访问) -> Integrations(集成) -> App Store Connect API"
    echo "  3) Team Keys 标签 -> 点 + 生成 -> 名称随便填, 角色选 [App Manager]"
    echo "  4) 生成后【立即点 Download 下载 .p8】(全网只能下载这一次!)"
    echo "  5) 回到本终端, 把下载的 .p8 路径告诉脚本(下一步), 脚本会帮你放到规范目录。"
    has_cmd open && confirm "现在打开 App Store Connect 网页?" "y" && open "https://appstoreconnect.apple.com" 2>/dev/null
    local p8src=""
    while true; do
      read -r -p "请输入刚下载的 .p8 完整路径(如 ~/Downloads/AuthKey_ABC123DEF4.p8): " p8src || true
      # 展开 ~
      p8src="${p8src/#\~/$HOME}"
      if [ -f "$p8src" ]; then
        local base; base="$(basename "$p8src")"
        cp "$p8src" "$PRIVATE_KEYS_DIR/$base"
        chmod 600 "$PRIVATE_KEYS_DIR/$base"
        found_p8="$PRIVATE_KEYS_DIR/$base"
        log_ok "已复制并锁定权限: $found_p8" "p8"
        break
      fi
      log_warn "找不到该文件, 请重输(或 Ctrl+C 退出去下载)。" "p8"
    done
  else
    log_ok "找到 .p8: $found_p8" "p8"
  fi
  chmod 600 "$found_p8" 2>/dev/null || true
  # 从文件名 AuthKey_<KeyID>.p8 解析 Key ID
  auto_keyid="$(basename "$found_p8" | sed -E 's/^AuthKey_(.*)\.p8$/\1/')"
  [ -n "$auto_keyid" ] && [ -z "$KEY_ID" ] && KEY_ID="$auto_keyid"

  echo "Key ID = .p8 文件名 AuthKey_<这部分>.p8; Issuer ID 在 API Key 网页顶部(UUID, 有 Copy 按钮)。"
  prompt_validate KEY_ID    "请确认 Key ID:"    '^[A-Z0-9]{8,}$' "$KEY_ID"
  prompt_validate ISSUER_ID "请输入 Issuer ID:" '^[0-9a-fA-F-]{36}$' "$ISSUER_ID"

  save_env

  # B3 立即验证三要素能认证(把"Key 填错"提前到网页操作之前发现)
  # 注意: altool 的 --list-providers 不支持 API Key 认证(会报 "list-providers does not
  #       support APIKey authentication"); --list-apps 支持 API Key, 用它做轻量预验证。
  log_info "正在用 altool 验证 API Key 是否可认证..." "auth"
  local out rc
  out="$(xcrun altool --list-apps --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID" 2>&1)"
  rc=$?
  printf '%s\n' "$out" >> "$LOG_FILE"
  if [ "$rc" -eq 0 ]; then
    log_ok "API Key 认证通过(三要素正确)" "auth"
  elif printf '%s' "$out" | grep -qiE 'AuthenticationFailure|Unauthorized|NOT_FOUND|invalid|forbidden|does not have access|401|403'; then
    log_err "API Key 认证失败, altool 输出:" "auth"
    printf '%s\n' "$out" | sed 's/^/    /'
    die "App Store Connect API Key 认证不通过" \
        "请检查: ① Key ID/Issuer ID 是否填反或填错(Issuer 是 UUID, Key ID 较短);" \
        "        ② .p8 文件名是否为 AuthKey_<KeyID>.p8 且 KeyID 与输入完全一致(大小写敏感);" \
        "        ③ 该 Key 角色是否为 App Manager(Developer 角色权限不足会被拒)。" \
        "改完重跑: ./release_ios.sh --from B"
  else
    # 命令本身不被支持/网络问题等非认证错误: 不误杀, 降级跳过, 留给阶段 E 的 --validate-app 真正验证
    log_warn "无法在此自动预验证 API Key(可能 altool 版本差异/网络), 跳过预验证;" "auth"
    log_warn "  将在阶段 E 上传时用 --validate-app 真正验证。altool 输出摘要: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-160)" "auth"
  fi
  log_ok "阶段 B 通过" "phaseB"
  echo ""
}

# ===========================================================================
# 阶段 C: 网页/Xcode 暂停点1
# ===========================================================================
phase_c_manual() {
  echo "${C_BOLD}===== 阶段 C: 网页/Xcode 操作(脚本无法代办) =====${C_RST}"

  echo "${C_BOLD}C1. 确认付费会员 + 签署所有待签协议(这是新建 App 的硬前提)${C_RST}"
  echo "   - 若 Agreements/Tax/Banking 里有未签协议, '+ 新建 App' 按钮会变灰、上传也会报错。"
  has_cmd open && open "https://appstoreconnect.apple.com/agreements" 2>/dev/null
  pause_for_user "请确认: 开发者会员状态 Active, 且 Agreements 页所有协议已是 Active(无 pending)。"

  echo "${C_BOLD}C2. 在 App Store Connect 新建 App 记录(首次发布必须先建)${C_RST}"
  echo "   - 我的 App -> 左上 + -> 新建 App: 平台选 iOS;"
  echo "   - Bundle ID 选 $BUNDLE_ID (下拉没有就先去 developer.apple.com 注册同名 App ID);"
  echo "   - 名称(全局唯一,<=30字)、SKU(内部唯一标识,如 netbarops-ios-001)、主要语言。"
  has_cmd open && open "https://appstoreconnect.apple.com/apps" 2>/dev/null
  pause_for_user "请确认: 已在 App Store Connect 创建好绑定 $BUNDLE_ID 的 App 记录。"

  echo "${C_BOLD}C3. 在 Xcode 登录账号并生成签名证书(首次发布必做, 否则命令行导出会失败)${C_RST}"
  echo "   - Xcode > Settings > Accounts: 用付费 Apple ID 登录(不要 Personal Team);"
  echo "   - 打开 ios/Runner.xcworkspace -> 选 Runner target -> Signing & Capabilities:"
  echo "     勾选 Automatically manage signing, Team 选你的付费团队;"
  echo "   - 让 Xcode 联网自动生成 Apple Distribution 证书与描述文件(看到面板无红色报错即可)。"
  if has_cmd open; then
    confirm "现在用 Xcode 打开 Runner.xcworkspace?" "y" && \
      open "$PROJECT_ROOT/ios/Runner.xcworkspace" 2>/dev/null
  fi
  pause_for_user "请确认: Xcode 已登录付费账号、勾了自动签名、Signing 面板无红色报错。"

  # 旁证: 钥匙串里是否已有签名证书
  if security find-identity -v -p codesigning 2>/dev/null | grep -q '0 valid identities found'; then
    log_warn "钥匙串里暂未发现签名证书。若构建报 'no signing certificate', 请回 C3 让 Xcode 生成证书。" "sign"
  else
    log_ok "检测到可用签名证书" "sign"
  fi
  log_ok "阶段 C 完成" "phaseC"
  echo ""
}

# ===========================================================================
# 阶段 D: 构建 (红线处理 -> build号自增 -> ExportOptions -> flutter build ipa)
# ===========================================================================

# 红线② 出口合规
handle_export_compliance() {
  if /usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$INFO_PLIST" >/dev/null 2>&1; then
    log_ok "Info.plist 已有 ITSAppUsesNonExemptEncryption" "compliance"
    return 0
  fi
  echo ""
  echo "${C_YEL}${C_BOLD}[红线-出口合规] Info.plist 没有声明加密合规(ITSAppUsesNonExemptEncryption)。${C_RST}"
  echo "  不声明的话, 每次上传后都要在网页手动回答出口合规, 否则构建卡住无法送审。"
  echo "  你的 App 含 WebRTC(DTLS-SRTP 加密)。判断口径:"
  echo "    - 若只用 HTTPS/TLS 和 WebRTC/系统标准加密、没有自研加密算法 -> 通常可声明 false(豁免)。"
  echo "    - 若用了自研/非标准加密算法 -> 不能填 false, 需走完整出口合规申报(法律声明, 别乱填)。"
  echo "  选择: [1] 写入 false(豁免)  [2] 跳过(以后每次在网页手动答)  [3] 中止让我先咨询"
  local c=""; read -r -p "  请输入 1/2/3: " c || true
  case "$c" in
    1)
      cp "$INFO_PLIST" "$INFO_PLIST.bak.$RUN_ID"
      /usr/libexec/PlistBuddy -c 'Add :ITSAppUsesNonExemptEncryption bool false' "$INFO_PLIST" \
        && log_ok "已写入 ITSAppUsesNonExemptEncryption=false (备份: $INFO_PLIST.bak.$RUN_ID)" "compliance"
      ;;
    3) die "已按你的要求中止" "确认加密合规口径后, 重跑: ./release_ios.sh --from D" ;;
    *) log_warn "跳过出口合规声明, 上传后请在网页手动回答。" "compliance" ;;
  esac
}

# 红线① 权限用途串
handle_usage_strings() {
  echo ""
  echo "${C_BOLD}[红线-权限用途串] 检查 Info.plist 隐私用途说明(缺失会被 ITMS-90683 拒)。${C_RST}"
  echo "  你的项目含 webrtc_remote(远控,可能用相机/麦克风/本地网络)、file_picker。"
  echo "  对每个权限: 若 App 确实会用到就填中文用途说明, 用不到就跳过(留空)。"
  # 候选权限(键 | 说明) —— bash 3.2 用并列数组, 不用关联数组
  local keys=( \
    "NSCameraUsageDescription" \
    "NSMicrophoneUsageDescription" \
    "NSLocalNetworkUsageDescription" \
    "NSPhotoLibraryUsageDescription" \
    "NSPhotoLibraryAddUsageDescription" )
  local notes=( \
    "相机(WebRTC 视频/远控画面采集时需要)" \
    "麦克风(WebRTC 音频时需要)" \
    "本地网络(局域网设备发现/直连时需要)" \
    "读取相册(file_picker 选图片/文件时可能需要)" \
    "保存到相册(向相册写图片时需要)" )
  local i k note desc backup_done=0
  for i in "${!keys[@]}"; do
    k="${keys[$i]}"; note="${notes[$i]}"
    if /usr/libexec/PlistBuddy -c "Print :$k" "$INFO_PLIST" >/dev/null 2>&1; then
      log_ok "已存在 $k" "perm"
      continue
    fi
    echo ""
    echo "  $k —— $note"
    read -r -p "    若需要请输入用途文案(中文; 用不到直接回车跳过): " desc || true
    if [ -n "$desc" ]; then
      if [ "$backup_done" -eq 0 ]; then
        cp "$INFO_PLIST" "$INFO_PLIST.bak.$RUN_ID"; backup_done=1
      fi
      # 用 plutil(value 作为独立 argv, 含空格/中文/标点都安全; 不经 PlistBuddy 二次分词截断)
      if plutil -insert "$k" -string "$desc" "$INFO_PLIST" 2>/dev/null; then
        local got
        got="$(/usr/libexec/PlistBuddy -c "Print :$k" "$INFO_PLIST" 2>/dev/null || true)"
        if [ "$got" = "$desc" ]; then
          log_ok "已写入 $k" "perm"
        else
          log_warn "$k 回读不一致(疑似写入异常): 实际=[$got], 请在 Xcode 里手动核对。" "perm"
        fi
      else
        log_warn "写入 $k 失败, 请手动在 Xcode 的 Info 配置里添加 $k。" "perm"
      fi
    fi
  done
  [ "$backup_done" -eq 1 ] && log_info "Info.plist 已修改(备份: $INFO_PLIST.bak.$RUN_ID)" "perm"
}

# 红线③ 隐私清单(只检测+提示, 不乱建空文件)
check_privacy_manifest() {
  echo ""
  echo "${C_BOLD}[红线-隐私清单] 检查 Required Reason API 隐私清单(.xcprivacy)。${C_RST}"
  # 用户自建的空清单反而会"盖住"插件清单 -> 警告
  if [ -f "$PROJECT_ROOT/ios/Runner/PrivacyInfo.xcprivacy" ]; then
    log_warn "发现 ios/Runner/PrivacyInfo.xcprivacy。若内容不完整, 反而可能触发 ITMS-91061。" "privacy"
    log_warn "  原则: 优先依赖各插件自带的 .xcprivacy, 不要在 Runner 里放空/不全的清单。" "privacy"
  fi
  local found
  found="$(find "$PROJECT_ROOT/ios/Pods" -name '*.xcprivacy' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${found:-0}" -gt 0 ]; then
    log_ok "Pods 里检测到 $found 个插件自带隐私清单(.xcprivacy)" "privacy"
  else
    log_warn "Pods 里暂未发现 .xcprivacy(可能 Pod 还没装/插件版本较旧)。" "privacy"
    log_warn "  若上传报 ITMS-91053/91061, 请升级 shared_preferences/path_provider 等插件到自带清单的新版本。" "privacy"
  fi
}

# build 号自增并写回 pubspec.yaml
bump_build_number() {
  local noconfirm="${1:-}"
  local verline cur_name cur_build new_build
  verline="$(grep -E '^version:' "$PUBSPEC" | head -n1)"
  # 形如 version: 1.0.0+3
  cur_name="$(printf '%s' "$verline" | sed -E 's/^version:[[:space:]]*([0-9.]+)\+([0-9]+).*/\1/')"
  cur_build="$(printf '%s' "$verline" | sed -E 's/^version:[[:space:]]*([0-9.]+)\+([0-9]+).*/\2/')"
  if ! printf '%s' "$cur_build" | grep -qE '^[0-9]+$'; then
    die "无法从 pubspec.yaml 解析 build 号" \
        "当前 version 行: $verline" \
        "请确保格式为  version: x.y.z+N  后重跑。"
  fi
  new_build=$(( cur_build + 1 ))
  # 与上次上传成功的号比较, 取更大者+0(确保严格递增)
  if printf '%s' "$LAST_BUILD" | grep -qE '^[0-9]+$' && [ "$new_build" -le "$LAST_BUILD" ]; then
    new_build=$(( LAST_BUILD + 1 ))
  fi
  echo ""
  echo "版本: $cur_name  build号: $cur_build -> ${C_BOLD}$new_build${C_RST} (上次成功上传: ${LAST_BUILD:-无})"
  if [ "$noconfirm" != "--yes" ]; then
    confirm "确认用 $cur_name+$new_build 进行构建?" "y" || \
      die "已取消" "如需手动指定版本, 修改 pubspec.yaml 的 version 行后重跑 --from D"
  fi
  cp "$PUBSPEC" "$PUBSPEC.bak.$RUN_ID"
  # 仅替换 version 行的 build 号
  sed -i.sedtmp -E "s/^(version:[[:space:]]*[0-9.]+)\+[0-9]+/\1+$new_build/" "$PUBSPEC"
  rm -f "$PUBSPEC.sedtmp"
  BUILD_NAME="$cur_name"; BUILD_NUMBER="$new_build"
  log_ok "pubspec.yaml 已更新为 $cur_name+$new_build (备份: $PUBSPEC.bak.$RUN_ID)" "version"
}

# 生成 ExportOptions.plist (自动签名 + App Store)
gen_export_options() {
  local xcode_major method
  xcode_major="$(xcodebuild -version 2>/dev/null | head -n1 | awk '{print $2}' | cut -d. -f1)"
  if [ "${xcode_major:-16}" -ge 15 ]; then method="app-store-connect"; else method="app-store"; fi
  cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>$method</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>uploadSymbols</key>
  <true/>
  <key>uploadBitcode</key>
  <false/>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
PLIST
  if ! plutil -lint "$EXPORT_OPTIONS" >/dev/null 2>&1; then
    die "生成的 ExportOptions.plist 格式非法" "文件: $EXPORT_OPTIONS"
  fi
  log_ok "已生成 ExportOptions.plist (method=$method, teamID=$TEAM_ID)" "export"
  EXPORT_METHOD="$method"
}

phase_d_build() {
  echo "${C_BOLD}===== 阶段 D: 构建 IPA =====${C_RST}"
  load_env
  [ -n "$TEAM_ID" ] || die "缺少 Team ID" "请先跑阶段 B: ./release_ios.sh --from B"

  handle_export_compliance
  handle_usage_strings
  bump_build_number
  gen_export_options

  echo ""
  log_info "flutter clean ..." "build"
  in_root flutter clean 2>&1 | tee -a "$LOG_FILE"
  [ "${PIPESTATUS[0]}" -eq 0 ] || log_warn "flutter clean 返回非0(通常无害, 继续)" "build"
  log_info "flutter pub get ..." "build"
  in_root flutter pub get 2>&1 | tee -a "$LOG_FILE"
  [ "${PIPESTATUS[0]}" -eq 0 ] || die "flutter pub get 失败" \
      "多为网络/代理问题(无法访问 pub.dev)。检查网络后重跑: ./release_ios.sh --from D"

  # pub get 后插件清单才落到 Pods, 再检查一次隐私清单
  check_privacy_manifest

  # 清空旧 ipa, 避免上传时通配匹配到旧包
  rm -f "$IPA_DIR"/*.ipa 2>/dev/null || true

  echo ""
  log_info "flutter build ipa (release, build=$BUILD_NUMBER) ... 这一步可能要几分钟" "build"
  set -o pipefail
  in_root flutter build ipa --release \
      --export-options-plist="$EXPORT_OPTIONS" 2>&1 | tee -a "$LOG_FILE"
  local build_rc=${PIPESTATUS[0]}
  if [ "$build_rc" -ne 0 ]; then
    diagnose_build_log
    die "flutter build ipa 失败(退出码 $build_rc)" \
        "请按上面的诊断提示修复后重跑: ./release_ios.sh --from D" \
        "完整日志: $LOG_FILE"
  fi

  # 校验产物
  local ipa
  ipa="$(ls -t "$IPA_DIR"/*.ipa 2>/dev/null | head -n1 || true)"
  [ -n "$ipa" ] || die "构建结束但没找到 .ipa" "预期目录: $IPA_DIR" "请检查上方构建日志。"
  if ! unzip -l "$ipa" 2>/dev/null | grep -q 'SwiftSupport/'; then
    log_warn "IPA 内未见 SwiftSupport/(若上传报 ITMS-90426, 说明导出方式不对)。" "build"
  fi
  IPA_PATH="$ipa"
  log_ok "构建成功: $ipa ($(du -h "$ipa" 2>/dev/null | awk '{print $1}'))" "build"
  log_ok "阶段 D 通过" "phaseD"
  echo ""
}

# 从最近日志里诊断构建期常见错误
diagnose_build_log() {
  local L="$LOG_FILE"
  echo "${C_YEL}---- 构建错误诊断 ----${C_RST}"
  if grep -qi 'requires a development team\|No profiles\|no signing certificate' "$L"; then
    echo " * 签名问题: 回阶段 C3, 在 Xcode 勾 Automatically manage signing 并选付费 Team, 让它生成证书/描述文件。"
  fi
  if grep -qi 'higher minimum .*deployment target\|deployment target' "$L"; then
    echo " * 某插件要求更高的最低 iOS 版本: 调高 ios/Podfile 顶部 platform :ios, 和工程 IPHONEOS_DEPLOYMENT_TARGET, 再 flutter clean 重试。"
  fi
  if grep -qi 'CocoaPods could not find\|Unable to find a specification\|pod install' "$L"; then
    echo " * CocoaPods 依赖问题: 删 ios/Pods 与 ios/Podfile.lock, 执行 pod repo update, 再 flutter clean / pub get 重试。"
  fi
  if grep -qi 'Missing required icon\|app icon' "$L"; then
    echo " * 缺图标: 检查 ios/Runner/Assets.xcassets/AppIcon.appiconset 是否齐全(尤其不含 alpha 的 1024x1024)。"
  fi
  if grep -qi "is deprecated.*app-store\|expected one of" "$L"; then
    echo " * ExportOptions method 取值: 脚本会按 Xcode 版本自动选 app-store-connect/app-store, 若仍报错可手动改 $EXPORT_OPTIONS。"
  fi
  echo "${C_YEL}----------------------${C_RST}"
}

# ===========================================================================
# 阶段 E: 上传 (先 validate 再 upload, 内置 ITMS 诊断)
# ===========================================================================

# 把 altool 输出映射到中文修复指引; 返回 0=可重试(build号问题) 其它=不可自动重试
diagnose_itms() {
  local out="$1"
  echo "${C_YEL}---- 上传结果诊断 ----${C_RST}"
  local retryable=1
  if printf '%s' "$out" | grep -qiE 'ITMS-90186|ITMS-90189|already been used|bundle version must be higher'; then
    echo " * 构建号重复(ITMS-90186/90189): 该版本下这个 build 号已传过。脚本可自增 build 号后自动重试一次。"
    retryable=0
  fi
  if printf '%s' "$out" | grep -qiE 'ITMS-90683|ITMS-90713|Missing.*purpose string|NS.*UsageDescription'; then
    echo " * 缺隐私用途串(ITMS-90683/90713): 回阶段 D 给对应权限补 NSxxxUsageDescription。"
  fi
  if printf '%s' "$out" | grep -qiE 'ITMS-91053|ITMS-91061|privacy manifest|API declaration'; then
    echo " * 隐私清单问题(ITMS-91053/91061): 升级相关插件到自带 .xcprivacy 的新版本; 不要手建空清单。"
  fi
  if printf '%s' "$out" | grep -qiE 'ITMS-90426|SwiftSupport'; then
    echo " * 缺 SwiftSupport(ITMS-90426): 用正式版 Xcode + app-store 导出重新构建(脚本默认已如此)。"
  fi
  if printf '%s' "$out" | grep -qiE 'ITMS-90022|ITMS-90023|required icon'; then
    echo " * 缺图标(ITMS-90022/90023): 补齐 AppIcon 全尺寸(从 1024 一键生成, 去 alpha)后重新构建。"
  fi
  if printf '%s' "$out" | grep -qiE 'Unable to authenticate|NOT_FOUND|Could not find the API key|does not have access|401'; then
    echo " * 认证问题: 回阶段 B 检查 Key ID/Issuer ID/.p8 文件名与角色(App Manager)。"
  fi
  if printf '%s' "$out" | grep -qiE 'ITMS-90161|ITMS-90034|invalid signature|provisioning'; then
    echo " * 签名/描述文件问题(ITMS-90161/90034): 回阶段 C3 用自动签名重新生成 Distribution 证书与 profile。"
  fi
  if printf '%s' "$out" | grep -qiE 'required agreement is missing or has expired'; then
    echo " * 协议未签/过期(403): 用 Account Holder 登录 https://appstoreconnect.apple.com -> 协议、税务和银行, 接受待签协议;"
    echo "   developer.apple.com/account 首页若有新版许可协议(PLA)横幅也要接受。刚签完可能需等 15-30 分钟生效, 之后重跑 --from E。"
  fi
  echo "${C_YEL}----------------------${C_RST}"
  return $retryable
}

# 封装 altool 调用; $1=validate-app|upload-app
run_altool() {
  local sub="$1"
  xcrun altool --"$sub" -f "$IPA_PATH" -t ios \
      --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID" --output-format normal 2>&1
}

# altool 会打印 ERROR 却仍返回退出码 0(实测: 403 协议未签被误报"上传成功"), 不能只信退出码;
# 但分片上传遇网络抖动也会打 "ERROR: ... WILL RETRY PART N" 后自动重试成功(实测), 故以最终成功标记为准:
# 有成功标记 -> 成功(无视中途重试 ERROR); 无成功标记且含 ERROR: -> 失败
altool_out_failed() {
  printf '%s' "$1" | grep -qE 'UPLOAD SUCCEEDED|No errors (uploading|validating) archive' && return 1
  printf '%s' "$1" | grep -qE '(^|[[:space:]])ERROR: '
}

phase_e_upload() {
  echo "${C_BOLD}===== 阶段 E: 上传到 App Store Connect =====${C_RST}"
  load_env
  [ -n "$KEY_ID" ] && [ -n "$ISSUER_ID" ] || die "缺少 API Key 配置" "请先跑阶段 B: ./release_ios.sh --from B"

  # 定位 IPA(若直接从 E 开始, 取最新)
  if [ -z "${IPA_PATH:-}" ]; then
    IPA_PATH="$(ls -t "$IPA_DIR"/*.ipa 2>/dev/null | head -n1 || true)"
  fi
  [ -n "${IPA_PATH:-}" ] && [ -f "$IPA_PATH" ] || \
    die "找不到要上传的 .ipa" "请先跑阶段 D 构建: ./release_ios.sh --from D"
  log_info "待上传: $IPA_PATH" "upload"

  # 防止上传到错的 app: 核对 IPA 内的 Bundle ID, 顺带读出真实 build 号
  local ipa_bid tmpd inner_plist ipa_build
  tmpd="$(mktemp -d)"
  if unzip -o -q "$IPA_PATH" -d "$tmpd" 'Payload/*/Info.plist' >/dev/null 2>&1; then
    inner_plist="$(ls "$tmpd"/Payload/*/Info.plist 2>/dev/null | head -n1 || true)"
    if [ -n "$inner_plist" ]; then
      ipa_bid="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$inner_plist" 2>/dev/null || true)"
      ipa_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$inner_plist" 2>/dev/null || true)"
    fi
  fi
  rm -rf "$tmpd"
  if [ -n "${ipa_bid:-}" ] && [ "$ipa_bid" != "$BUNDLE_ID" ]; then
    die "IPA 里的 Bundle ID 与预期不符" \
        "IPA 内: $ipa_bid, 预期: $BUNDLE_ID" \
        "请确认构建的是正确工程, 不要上传到错的 App。"
  fi
  [ -n "${ipa_bid:-}" ] && log_ok "Bundle ID 核对一致: $ipa_bid" "upload"

  # E1 先 validate
  log_info "上传前预校验 (altool --validate-app) ..." "upload"
  local vout vrc
  vout="$(run_altool validate-app)"; vrc=$?
  if [ "$vrc" -eq 0 ] && altool_out_failed "$vout"; then vrc=1; fi
  printf '%s\n' "$vout" >> "$LOG_FILE"
  if [ "$vrc" -ne 0 ]; then
    printf '%s\n' "$vout" | sed 's/^/    /'
    diagnose_itms "$vout" || true
    die "预校验未通过, 已阻止上传" \
        "请按上面诊断修复后重跑 --from D(改了代码/版本) 或 --from E(仅重试上传)。"
  fi
  log_ok "预校验通过" "upload"

  # E2 正式上传
  log_info "正式上传 (altool --upload-app) ... 大包可能要几分钟到十几分钟" "upload"
  local uout urc dret rebuild_rc
  uout="$(run_altool upload-app)"; urc=$?
  if [ "$urc" -eq 0 ] && altool_out_failed "$uout"; then urc=1; fi
  printf '%s\n' "$uout" >> "$LOG_FILE"
  printf '%s\n' "$uout" | sed 's/^/    /'

  if [ "$urc" -ne 0 ]; then
    diagnose_itms "$uout"; dret=$?
    if [ "$dret" -eq 0 ]; then
      # dret=0 表示"build 号重复"可重试: 自增(非交互)并重新构建上传一次
      log_warn "检测到构建号重复, 自动自增 build 号并重新构建上传一次..." "upload"
      bump_build_number --yes
      gen_export_options
      rm -f "$IPA_DIR"/*.ipa 2>/dev/null || true
      in_root flutter build ipa --release --export-options-plist="$EXPORT_OPTIONS" 2>&1 | tee -a "$LOG_FILE"
      rebuild_rc=${PIPESTATUS[0]}
      if [ "$rebuild_rc" -ne 0 ]; then
        diagnose_build_log
        die "自动重试时重新构建失败(退出码 $rebuild_rc)" "请按上面诊断修复后重跑 --from D"
      fi
      IPA_PATH="$(ls -t "$IPA_DIR"/*.ipa 2>/dev/null | head -n1 || true)"
      [ -n "$IPA_PATH" ] && [ -f "$IPA_PATH" ] || die "重试构建后未找到 .ipa" "预期目录: $IPA_DIR"
      ipa_build="$BUILD_NUMBER"
      # 重试也先校验再上传, 与正常流程一致
      vout="$(run_altool validate-app)"; vrc=$?
      if [ "$vrc" -eq 0 ] && altool_out_failed "$vout"; then vrc=1; fi
      printf '%s\n' "$vout" >> "$LOG_FILE"
      if [ "$vrc" -ne 0 ]; then
        printf '%s\n' "$vout" | sed 's/^/    /'
        diagnose_itms "$vout"
        die "重试预校验未通过" "请按上面诊断修复后重跑 --from D。完整日志: $LOG_FILE"
      fi
      uout="$(run_altool upload-app)"; urc=$?
      if [ "$urc" -eq 0 ] && altool_out_failed "$uout"; then urc=1; fi
      printf '%s\n' "$uout" >> "$LOG_FILE"
      printf '%s\n' "$uout" | sed 's/^/    /'
    fi
  fi

  if [ "$urc" -ne 0 ]; then
    die "上传失败(退出码 $urc)" "请按上面的诊断提示修复后重跑 --from E。完整日志: $LOG_FILE"
  fi

  # 记录成功上传的 build 号(--from E 直传时 BUILD_NUMBER 为空, 改从 IPA 实际读到的 CFBundleVersion)
  if printf '%s' "${BUILD_NUMBER:-}" | grep -qE '^[0-9]+$'; then
    LAST_BUILD="$BUILD_NUMBER"
  elif printf '%s' "${ipa_build:-}" | grep -qE '^[0-9]+$'; then
    LAST_BUILD="$ipa_build"
  fi
  save_env
  log_ok "上传成功! 构建已进入 App Store Connect(状态先是'正在处理')。" "upload"
  log_ok "阶段 E 通过" "phaseE"
  echo ""
}

# ===========================================================================
# 阶段 TF: TestFlight 测试引导(上传后先测, 测好用同一个包直接提审, 不重编)
# ===========================================================================
phase_testflight() {
  echo "${C_BOLD}===== 阶段 TF: TestFlight 测试(先测后发, 同一个包) =====${C_RST}"
  echo "你刚上传的构建会进入 TestFlight, 可先装到手机测试; 测好后用【同一个构建】直接提审发布, 无需重新编译。"
  echo ""
  echo "${C_BOLD}在 App Store Connect 网页:${C_RST}"
  echo "  1) 进入你的 App -> TestFlight 标签, 等构建从'正在处理(Processing)'变为可用"
  echo "     (一般几分钟, 首个构建可能要几小时; 会收到 Apple 处理结果邮件);"
  echo "  2) 首个构建若提示补'测试信息/出口合规', 按提示填一次;"
  echo "  3) 选测试方式:"
  echo "     - 内部测试(最快): TestFlight -> 内部测试群组 -> 加测试员(团队成员的 Apple ID),"
  echo "       无需 Beta 审核, 几分钟即可在手机上装;"
  echo "     - 外部测试(给团队外的人): 需提交一次 Beta App Review, 通过后才能测。"
  echo "${C_BOLD}在 iPhone 上:${C_RST}"
  echo "  4) App Store 搜索并安装 Apple 官方的 [TestFlight] app;"
  echo "  5) 用被加为测试员的 Apple ID 登录 TestFlight, 即可看到并安装你的 app, 像正式版一样跑。"
  has_cmd open && confirm "现在打开 App Store Connect 的 TestFlight 页?" "y" && \
    open "https://appstoreconnect.apple.com/apps" 2>/dev/null
  echo ""
  echo "${C_BOLD}测试完成后:${C_RST}"
  echo "  - 满意   -> 用同一个构建直接提交审核发布(不用重新编译);"
  echo "  - 不满意 -> 改代码后重跑 ./release_ios.sh --from D 出新构建再测。"
  echo ""
  if confirm "现在就进入【提交审核/发布】(阶段 F)吗?" "n"; then
    log_info "进入阶段 F 提审..." "testflight"
    return 0
  fi
  log_ok "已暂停在 TestFlight 阶段。去测试吧; 测好后运行: ./release_ios.sh --only F 进行提审发布。" "testflight"
  exit 0
}

# ===========================================================================
# 阶段 F: 网页/提审 暂停点2
# ===========================================================================
phase_f_submit() {
  echo "${C_BOLD}===== 阶段 F: 网页填资料并提交审核 =====${C_RST}"
  echo "上传成功后, 构建要先在 ASC 处理(Processing), 几分钟到几小时不等(首个构建更久)。"
  echo ""
  echo "${C_BOLD}请在 App Store Connect 网页完成(脚本无法代办):${C_RST}"
  echo "  1) 等构建从'正在处理'变为可选(TestFlight/构建版本 里能看到);"
  echo "  2) App 信息: 名称、副标题、类别;"
  echo "  3) '准备提交'版本页: 描述、关键词、技术支持URL(必须真实可访问)、版权;"
  echo "  4) 截图: iPhone 6.9\" = 1290x2796(竖) 至少 1 张; 若支持 iPad 另传 13\" iPad 截图;"
  echo "     (必须用真苹果设备截图, 像素严格匹配, 不能用安卓/伪造图, 否则按 2.3.3 拒);"
  echo "  5) App 隐私(App Privacy): 如实填数据收集问卷 + 隐私政策URL(必填且页面要真实);"
  echo "  6) 年龄分级问卷;"
  echo "  7) 选本次构建 -> 回答 IDFA(本项目无广告SDK应选'否') 和出口合规(已写 false 则自动跳过);"
  echo "  8) 点 [添加以供审核 / 提交以供审核] -> 状态变为'等待审核'。"
  echo ""
  echo "  提示: 只是上架的话不必先过 TestFlight 外部测试; 构建处理完直接选它提审即可。"
  has_cmd open && confirm "现在打开 App Store Connect?" "y" && open "https://appstoreconnect.apple.com/apps" 2>/dev/null
  pause_for_user "提交审核后会收到确认邮件, 状态: 等待审核->正在审核->可供销售。"
  log_ok "全流程结束。后续审核结果留意 Apple 邮件和'解决方案中心'。" "phaseF"
}

# ===========================================================================
# 主流程 / 参数解析
# ===========================================================================
usage() {
  cat <<EOF
用法: $0 [选项]
  (无参数)        跑完整流程 A->F (上传后会先引导你做 TestFlight 测试, 再提审)
  --from <阶段>   从指定阶段开始(修复后重跑常用), 如 --from D
  --only <阶段>   只跑指定一个阶段, 如 --only F (TestFlight 测好后单独回来提审)
  -h, --help      显示帮助

阶段: A体检 B配置+认证 C网页/Xcode暂停 D构建 E上传 TF(TestFlight测试) F提审
配置文件: $ENV_FILE
日志目录: $LOG_DIR
EOF
}

# 运行期共享变量
BUILD_NAME=""; BUILD_NUMBER=""; EXPORT_METHOD=""; IPA_PATH=""

run_from() {
  local start="$1"
  case "$start" in
    A) phase_a_preflight; phase_b_config; phase_c_manual; phase_d_build; phase_e_upload; phase_testflight; phase_f_submit ;;
    B) phase_b_config; phase_c_manual; phase_d_build; phase_e_upload; phase_testflight; phase_f_submit ;;
    C) phase_c_manual; phase_d_build; phase_e_upload; phase_testflight; phase_f_submit ;;
    D) phase_d_build; phase_e_upload; phase_testflight; phase_f_submit ;;
    E) phase_e_upload; phase_testflight; phase_f_submit ;;
    TF) phase_testflight; phase_f_submit ;;
    F) phase_f_submit ;;
    *) usage; exit 1 ;;
  esac
}
run_only() {
  case "$1" in
    A) phase_a_preflight ;;
    B) phase_b_config ;;
    C) phase_c_manual ;;
    D) phase_d_build ;;
    E) phase_e_upload ;;
    TF) phase_testflight ;;
    F) phase_f_submit ;;
    *) usage; exit 1 ;;
  esac
}

main() {
  log_info "===== iOS 发布脚本启动 (项目: $PROJECT_ROOT) =====" "start"
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --from) [ -n "${2:-}" ] || { usage; exit 1; }; run_from "$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')" ;;
    --only) [ -n "${2:-}" ] || { usage; exit 1; }; run_only "$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')" ;;
    "") run_from A ;;
    *) usage; exit 1 ;;
  esac
  log_ok "===== 脚本执行完毕 =====" "done"
}

main "$@"
