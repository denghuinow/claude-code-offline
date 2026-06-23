#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX="/usr/local"
USER_MODE=0
FORCE=0
PKG_DIR=""
NO_VERIFY=0

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

usage() {
  cat <<USAGE
Claude Code 离线安装脚本

参数：
  --user              安装到 ~/.local/bin/claude
  --prefix DIR        安装前缀，默认 /usr/local；最终路径为 DIR/bin/claude
  --package DIR       离线包目录，默认自动使用当前脚本所在目录
  --force             覆盖已有 claude
  --no-verify         跳过包内 SHA256 校验
  -h, --help          显示帮助

示例：
  sudo ./install-offline.sh
  ./install-offline.sh --user
  sudo ./install-offline.sh --prefix /opt/claude-code --force
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER_MODE=1; PREFIX="$HOME/.local"; shift ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --package) PKG_DIR="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --no-verify) NO_VERIFY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

if [[ -z "$PKG_DIR" ]]; then
  PKG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
else
  PKG_DIR="$(cd "$PKG_DIR" && pwd)"
fi

[[ -x "$PKG_DIR/bin/claude" ]] || die "未找到离线包二进制：$PKG_DIR/bin/claude"

if [[ "$NO_VERIFY" -eq 0 && -x "$PKG_DIR/verify-package.sh" ]]; then
  "$PKG_DIR/verify-package.sh" --package "$PKG_DIR"
fi

TARGET_DIR="$PREFIX/bin"
TARGET="$TARGET_DIR/claude"

if [[ -e "$TARGET" && "$FORCE" -eq 0 ]]; then
  warn "目标已存在：$TARGET"
  warn "使用 --force 覆盖，或先运行 uninstall.sh。"
  exit 1
fi

run_as_root_if_needed() {
  if [[ "$USER_MODE" -eq 0 && "$(id -u)" -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || die "需要 root 权限，请使用 sudo 运行。"
    sudo "$@"
  else
    "$@"
  fi
}

log "安装 Claude Code 到：$TARGET"
run_as_root_if_needed install -d -m 0755 "$TARGET_DIR"
run_as_root_if_needed install -m 0755 "$PKG_DIR/bin/claude" "$TARGET"

if [[ "$USER_MODE" -eq 1 ]]; then
  case ":$PATH:" in
    *":$TARGET_DIR:"*) ;;
    *) warn "$TARGET_DIR 不在 PATH 中，可加入：export PATH=\"$TARGET_DIR:\$PATH\"" ;;
  esac
fi

log "安装完成。"
"$TARGET" --version || warn "claude --version 执行失败，请检查系统兼容性。"
