#!/usr/bin/env bash
# =============================================================================
#  夸克网盘 (deepin-wine-quarkclouddrive) 一键安装脚本 — Arch / CachyOS
#  仓库: https://github.com/lilyco-42/deepin-wine-quarkclouddrive-fix
#
#  用法:
#    bash install.sh                 交互安装
#    bash install.sh -y --launch     全自动并立即启动
#    bash install.sh --dry-run       只下载 + 校验，不改系统
#    bash install.sh --local pkg/    用本地已下好的包
#    bash install.sh -u              卸载
# =============================================================================
set -Eeuo pipefail

readonly REPO="lilyco-42/deepin-wine-quarkclouddrive-fix"
readonly TAG="v3.2.6spark4-4"
readonly PREFIX_URL="https://github.com/${REPO}/releases/download/${TAG}"

PKGS=(
  spark-transhell-1.1-5-x86_64.pkg.tar.zst
  deepin-wine8-stable-8.16deepin25_1-1-x86_64.pkg.tar.zst
  spark-dwine-helper-5.8_5.3.14-1-any.pkg.tar.zst
  deepin-wine-quarkclouddrive-3.2.6spark4-4-x86_64.pkg.tar.zst
)

declare -A SUMS=(
  ["spark-transhell-1.1-5-x86_64.pkg.tar.zst"]="61f73a9203b48903ef223b2b9c79cefcfc39de8d3e768a0e6024e9ff98580238"
  ["deepin-wine8-stable-8.16deepin25_1-1-x86_64.pkg.tar.zst"]="2f2ecf6af0e09e905071db1b3e7e9efc074721d0cb54c6ee3262789bd8c851d6"
  ["spark-dwine-helper-5.8_5.3.14-1-any.pkg.tar.zst"]="eaaa0486e893744c46f1a1f89d7e830d945b3d9fd135bcca7b77c51f93908d9a"
  ["deepin-wine-quarkclouddrive-3.2.6spark4-4-x86_64.pkg.tar.zst"]="92f4215cd8e3f2499de3b8383177b7ebf25569eefecd7b28e1a292b37e293a45"
)

ASSUME_YES=0
DRY_RUN=0
DO_LAUNCH=0
SKIP_VERIFY=0
UNINSTALL=0
LOCAL_DIR=""
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quarkclouddrive-fix/${TAG}"
SUDO=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_R=$'\e[31m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_B=$'\e[34m'; C_D=$'\e[2m'; C_0=$'\e[0m'
else
  C_R=""; C_G=""; C_Y=""; C_B=""; C_D=""; C_0=""
fi
info() { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
err()  { printf '%s  ✗%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { err "$*"; exit 1; }
step() { printf '\n%s[%s]%s %s\n' "$C_B" "$1" "$C_0" "$2"; }

trap 'err "第 $LINENO 行命令失败，脚本中止"' ERR

usage() {
  cat <<'USAGE'
夸克网盘 (deepin-wine-quarkclouddrive) 一键安装脚本  —  Arch / CachyOS

用法: bash install.sh [选项]

  -y, --yes          全部使用默认答案，不交互
      --launch       安装完成后立即启动夸克网盘
      --dry-run      只检查环境、下载并校验安装包，不修改系统
      --skip-verify  跳过 SHA256 校验（不推荐）
      --local DIR    使用本地目录中的 .pkg.tar.zst，不联网下载
      --cache DIR    自定义下载缓存目录
  -u, --uninstall    卸载软件包并询问是否清理 Wine 数据
  -h, --help         显示本帮助

装的是 4 个包，已修复 AUR 原版在非 Deepin 桌面上的 4 个启动问题:
  1. --no-sandbox 被夸克自研参数解析器拒绝 (bad option, RC=9)
  2. 继承 ELECTRON_RUN_AS_NODE 导致启动约 2 秒后静默退出
  3. zenity 缩放选择弹窗阻塞首次启动
  4. C:/ 盘符大小写不匹配导致 cd 失败
USAGE
}

while (( $# )); do
  case "$1" in
    -y|--yes)       ASSUME_YES=1 ;;
    --launch)       DO_LAUNCH=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    --skip-verify)  SKIP_VERIFY=1 ;;
    --local)        LOCAL_DIR="${2:?--local 需要一个目录参数}"; shift ;;
    --cache)        CACHE_DIR="${2:?--cache 需要一个目录参数}"; shift ;;
    -u|--uninstall) UNINSTALL=1 ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "未知参数: $1  （用 -h 查看帮助）" ;;
  esac
  shift
done

arch_ok() {
  [[ -f /etc/pacman.conf ]] || return 1
  grep -qiE 'arch|cachyos|manjaro|endeavouros' /etc/os-release 2>/dev/null
}

need_root_backend() {
  if (( EUID == 0 )); then
    SUDO=()
  elif command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
  elif command -v doas >/dev/null 2>&1; then
    SUDO=(doas)
  else
    die "需要 root 权限但没找到 sudo / doas，请用 root 运行: su -c 'bash install.sh'"
  fi
}

confirm() {
  local prompt="$1" default="${2:-y}" hint ans
  (( ASSUME_YES )) && return 0
  [[ -t 0 ]] || return 0
  hint="[Y/n]"; [[ "$default" == "n" ]] && hint="[y/N]"
  read -r -p "$prompt $hint " ans || true
  ans="${ans:-$default}"
  [[ "$ans" =~ ^[Yy] ]]
}

human() { numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "$1 B"; }
free_bytes() { df -B1 --output=avail "$1" 2>/dev/null | tail -1 | tr -d ' '; }

preflight() {
  step 1/6 "环境检查"

  arch_ok || die "这不是 Arch 系系统（没有 /etc/pacman.conf 或 os-release 不匹配）。仅支持 Arch / CachyOS / Manjaro / EndeavourOS。"
  ok "发行版: $(. /etc/os-release; echo "${PRETTY_NAME:-$ID}")"

  [[ "$(uname -m)" == "x86_64" ]] || die "只支持 x86_64（当前 $(uname -m)），夸克网盘没有 Linux arm64 构建。"
  ok "架构: x86_64"

  need_root_backend
  if (( DRY_RUN )); then
    ok "提权方式: ${SUDO[*]:-root}  （dry-run 不验证密码）"
  elif (( ${#SUDO[@]} )); then
    "${SUDO[@]}" -v 2>/dev/null || die "sudo 需要密码，请先在终端手动执行一次 sudo -v 再重跑本脚本。"
    ok "提权方式: ${SUDO[*]}"
  else
    ok "提权方式: 已是 root"
  fi

  local t miss=()
  for t in curl sha256sum awk sed; do
    command -v "$t" >/dev/null 2>&1 || miss+=("$t")
  done
  if (( ${#miss[@]} )); then
    warn "缺少命令: ${miss[*]}，尝试安装 coreutils / curl …"
    (( DRY_RUN )) || "${SUDO[@]}" pacman -S --needed --noconfirm coreutils curl
  fi
  ok "基础命令齐全"

  # 注意不能用 pacman -Qq quarkclouddrive 判断——本包 provides 同名，
  # 那个查询会匹配到本包自己。必须比对 Name 字段。
  local prov
  prov="$(pacman -Qi quarkclouddrive 2>/dev/null | awk -F': *' '/^Name/{print $2; exit}')"
  if [[ "$prov" == "quarkclouddrive" ]]; then
    warn "检测到冲突包 quarkclouddrive（与本包冲突）"
    if confirm "先卸载 quarkclouddrive？" y; then
      (( DRY_RUN )) || "${SUDO[@]}" pacman -Rdd --noconfirm quarkclouddrive
    else
      die "存在冲突包，请手动 pacman -Rdd quarkclouddrive 后重跑。"
    fi
  fi

  [[ -e /var/lib/pacman/db.lck ]] && die "/var/lib/pacman/db.lck 存在——有 pacman 在运行或上次异常退出。确认后删除该文件再重试。"

  local free_opt free_home
  free_opt="$(free_bytes /opt || true)"; [[ -n "$free_opt" ]] || free_opt="$(free_bytes / || true)"
  free_home="$(free_bytes "$HOME" || true)"
  if [[ -n "$free_opt" ]] && (( free_opt < 1572864000 )); then
    die "/opt 所在分区空间不足：需要约 1.5 GiB，当前可用 $(human "$free_opt")"
  fi
  if [[ -n "$free_home" ]] && (( free_home < 1258291200 )); then
    die "家目录空间不足：首次启动需约 1.2 GiB，当前可用 $(human "$free_home")"
  fi
  ok "磁盘空间充足（/opt 可用 $(human "${free_opt:-0}")，家目录可用 $(human "${free_home:-0}")）"

  local p cur
  for p in spark-transhell deepin-wine8-stable spark-dwine-helper deepin-wine-quarkclouddrive; do
    if cur="$(pacman -Q "$p" 2>/dev/null | awk '{print $2}')"; then
      ok "已安装 $p $cur"
    fi
  done
}

verify_one() {
  local name sum actual
  name="$(basename "$1")"
  sum="${SUMS[$name]:-}"
  [[ -n "$sum" ]] || return 2
  actual="$(sha256sum "$1" | awk '{print $1}')"
  [[ "$actual" == "$sum" ]]
}

fetch() {
  step 2/6 "获取安装包"
  mkdir -p "$CACHE_DIR"

  local f miss=() src
  for f in "${PKGS[@]}"; do
    if [[ -n "$LOCAL_DIR" ]]; then
      src="$LOCAL_DIR/$f"
      [[ -f "$src" ]] || die "--local 目录里没有 $f"
      cp -f "$src" "$CACHE_DIR/$f"
      ok "本地复制 $f"
      continue
    fi
    if [[ -f "$CACHE_DIR/$f" ]] && verify_one "$CACHE_DIR/$f"; then
      ok "缓存命中且校验通过: $f"
      continue
    fi
    miss+=("$f")
  done

  if (( ${#miss[@]} == 0 )); then
    ok "全部就绪，无需下载"
    return 0
  fi

  command -v curl >/dev/null 2>&1 || die "需要 curl 下载安装包"
  info "需要下载 ${#miss[@]} 个文件（约 388 MiB）"

  local url
  for f in "${miss[@]}"; do
    url="$PREFIX_URL/$f"
    info "下载 $f"
    if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -C - \
         --progress-bar -o "$CACHE_DIR/$f.part" "$url"; then
      rm -f "$CACHE_DIR/$f.part"
      die "下载失败: $url"
    fi
    mv -f "$CACHE_DIR/$f.part" "$CACHE_DIR/$f"
  done
  ok "下载完成"
}

verify_all() {
  step 3/6 "校验安装包"
  if (( SKIP_VERIFY )); then
    warn "已按要求跳过 SHA256 校验（--skip-verify）"
    return 0
  fi
  local f bad=0
  for f in "${PKGS[@]}"; do
    [[ -f "$CACHE_DIR/$f" ]] || die "缺文件: $CACHE_DIR/$f"
    if verify_one "$CACHE_DIR/$f"; then
      ok "$f"
    else
      err "校验失败: $f"; bad=1
    fi
  done
  if (( bad )); then
    for f in "${PKGS[@]}"; do verify_one "$CACHE_DIR/$f" || rm -f "$CACHE_DIR/$f"; done
    die "SHA256 不匹配（已删除坏文件，请重跑）——可能下载损坏或被篡改"
  fi
  ok "4 个包 SHA256 全部匹配"
}

do_install() {
  step 4/6 "安装软件包"
  local files=() f
  for f in "${PKGS[@]}"; do files+=("$CACHE_DIR/$f"); done

  if (( DRY_RUN )); then
    info "dry-run: 将执行 ${SUDO[*]:-} pacman -U --needed --noconfirm <4 个包>"
    return 0
  fi

  confirm "即将安装以上 4 个软件包到系统，继续？" y || die "已取消"

  if ! "${SUDO[@]}" pacman -U --needed --noconfirm "${files[@]}"; then
    err "pacman 安装失败。常见原因："
    err "  · 有其它 pacman / 包管理器在运行 → 等它结束后重跑"
    err "  · btrfs/snapper 快照 hook 报错 → 通常无害，看上面输出确认包是否已装上"
    err "  · 缺系统依赖 → 手动 pacman -S alsa-lib libpulse libgphoto2 sane wayland"
    die "安装未完成"
  fi
  ok "软件包安装完成"
}

post_verify() {
  step 5/6 "验证安装结果"
  if (( DRY_RUN )); then
    info "dry-run: 跳过验证"
    return 0
  fi

  local fail=0 miss

  if [[ -x /usr/bin/deepin-wine-quarkclouddrive ]] && grep -q 'unset ELECTRON_RUN_AS_NODE' /usr/bin/deepin-wine-quarkclouddrive; then
    ok "启动脚本已带 ELECTRON_RUN_AS_NODE 修复"
  else
    err "启动脚本缺少 ELECTRON 修复（可能装成了上游原版）"; fail=1
  fi

  if [[ -f /opt/deepinwine/tools/spark_run_v4_app_configs/Deepin-QuarkCloudDrive.sh ]]; then
    ok "spark 缩放钩子已就位（首次启动不会弹 zenity）"
  else
    err "缺少 spark 钩子，首次启动可能卡在缩放弹窗"; fail=1
  fi

  if grep -qs -- '--no-sandbox' /usr/share/applications/deepin-wine-quarkclouddrive.desktop; then
    err "desktop 文件仍带 --no-sandbox（会导致 bad option 秒退）"; fail=1
  else
    ok "desktop 入口未注入 --no-sandbox"
  fi

  if [[ -x /opt/deepin-wine8-stable/bin/wine ]]; then
    miss="$(ldd /opt/deepin-wine8-stable/bin/wine 2>/dev/null | grep -c 'not found' || true)"
    if [[ "${miss:-0}" -eq 0 ]]; then
      ok "wine 动态库依赖完整"
    else
      err "wine 有 $miss 个动态库缺失（ldd /opt/deepin-wine8-stable/bin/wine | grep 'not found'）"; fail=1
    fi
  else
    err "缺少 /opt/deepin-wine8-stable/bin/wine"; fail=1
  fi

  # 注意 set -o pipefail：不能用 `fc-list | grep -q`，grep 提前退出会让 fc-list 收到
  # SIGPIPE 从而令整个管道返回非 0，造成"没中文字体"的误报。
  local zh_font
  zh_font="$(fc-list :lang=zh 2>/dev/null | head -1 || true)"
  if [[ -n "$zh_font" ]]; then
    ok "系统中文字体可用（界面不会显示方块）"
  else
    warn "没有中文字体，界面可能显示方块，建议: pacman -S noto-fonts-cjk"
  fi

  local stale="$HOME/.deepinwine/Spark-QuarkCloudDrive"
  if [[ -d "$stale" ]]; then
    warn "发现旧 bottle: $stale（$(du -sh "$stale" 2>/dev/null | cut -f1)）"
    if confirm "删除它？（其中的旧登录状态会丢失）" y; then
      rm -rf "$stale" && ok "已删除旧 bottle"
    fi
  fi

  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  command -v kbuildsycoca6 >/dev/null 2>&1 && { kbuildsycoca6 >/dev/null 2>&1 || true; }

  (( fail )) && die "验证发现问题，见上面的 ✗ 项"
  ok "全部检查通过"
}

finish() {
  step 6/6 "完成"
  cat <<EOF

${C_G}夸克网盘已就绪${C_0}

  启动方式:
    · 应用菜单 → 夸克网盘
    · 终端执行  ${C_B}deepin-wine-quarkclouddrive${C_0}

  首次启动会创建 Wine 环境，约 1 分钟，期间窗口可能空白，属正常现象。
  程序按屏幕 DPI 自动设定缩放，不会再弹任何选择框。

  遇到问题看 ${C_B}https://github.com/${REPO}${C_0} 的 README。

EOF

  if [[ -n "${ELECTRON_RUN_AS_NODE:-}" ]]; then
    warn "当前 shell 有 ELECTRON_RUN_AS_NODE=${ELECTRON_RUN_AS_NODE}（Electron IDE 的集成终端常见）"
    warn "安装包已做兼容，但用普通终端启动更干净。"
  fi

  if (( DO_LAUNCH )); then
    if (( DRY_RUN )); then
      info "dry-run: 不实际启动"
      return 0
    fi
    info "启动夸克网盘…"
    setsid deepin-wine-quarkclouddrive >/dev/null 2>&1 < /dev/null &
    sleep 2
    ok "已在后台启动（首次启动请等约 1 分钟）"
  fi
}

do_uninstall() {
  step 1/3 "检查已装状态"
  need_root_backend
  local p installed=()
  for p in spark-transhell deepin-wine8-stable spark-dwine-helper deepin-wine-quarkclouddrive; do
    pacman -Qq "$p" &>/dev/null && installed+=("$p")
  done
  if (( ${#installed[@]} == 0 )); then
    ok "这几个包都没安装，无需卸载"
    return 0
  fi
  ok "将卸载: ${installed[*]}"

  step 2/3 "卸载软件包"
  if (( DRY_RUN )); then
    info "dry-run: 将执行 ${SUDO[*]:-} pacman -Rns ${installed[*]}"
  else
    confirm "确认卸载？" n || die "已取消"
    "${SUDO[@]}" pacman -Rns --noconfirm "${installed[@]}" || warn "部分包卸载失败，可手动处理"
    ok "软件包已卸载"
  fi

  step 3/3 "清理数据"
  local b bottles=("$HOME/.deepinwine/Deepin-QuarkCloudDrive" "$HOME/.deepinwine/Spark-QuarkCloudDrive")
  for b in "${bottles[@]}"; do
    [[ -d "$b" ]] || continue
    warn "Wine 数据目录: $b（$(du -sh "$b" 2>/dev/null | cut -f1)）"
    if confirm "删除它？其中的登录状态会一并删除。" n; then
      (( DRY_RUN )) || rm -rf "$b"
      ok "已删除 $b"
    else
      info "保留 $b"
    fi
  done
  local cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/quarkclouddrive-fix"
  if [[ -d "$cache_root" ]]; then
    if confirm "删除下载缓存 $cache_root ？" n; then
      (( DRY_RUN )) || rm -rf "$cache_root"
      ok "缓存已删除"
    fi
  fi
  ok "卸载完成"
}

main() {
  printf '%s\n' "${C_B}夸克网盘 · Arch/CachyOS 一键安装${C_0}" "${C_D}https://github.com/${REPO}   版本 ${TAG}${C_0}"

  if (( UNINSTALL )); then
    do_uninstall
    exit 0
  fi

  (( DRY_RUN )) && warn "dry-run 模式：只下载与校验，不修改系统"

  preflight
  fetch
  verify_all
  do_install
  post_verify
  finish
}

main "$@"
