#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX="/usr/local"
USER_MODE=0
REMOVE_DATA=0

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<USAGE
卸载脚本

参数：
  --user              删除 ~/.local/bin/claude
  --prefix DIR        删除 DIR/bin/claude，默认 /usr/local/bin/claude
  --remove-user-data  同时删除 ~/.claude 和 ~/.claude.json；谨慎使用
  -h, --help          显示帮助
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER_MODE=1; PREFIX="$HOME/.local"; shift ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --remove-user-data) REMOVE_DATA=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

TARGET="$PREFIX/bin/claude"
run_as_root_if_needed() {
  if [[ "$USER_MODE" -eq 0 && "$(id -u)" -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || die "需要 root 权限，请使用 sudo 运行。"
    sudo "$@"
  else
    "$@"
  fi
}

if [[ -e "$TARGET" ]]; then
  run_as_root_if_needed rm -f "$TARGET"
  log "已删除：$TARGET"
else
  warn "未找到：$TARGET"
fi

if [[ "$REMOVE_DATA" -eq 1 ]]; then
  rm -rf "$HOME/.claude" "$HOME/.claude.json"
  log "已删除用户配置/历史：~/.claude ~/.claude.json"
else
  warn "未删除用户配置/历史。如需删除，加 --remove-user-data。"
fi
