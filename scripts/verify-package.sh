#!/usr/bin/env bash
set -Eeuo pipefail

PKG_DIR=""
SKIP_GPG=0
EXPECTED_GPG_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

usage() {
  cat <<USAGE
校验 Claude Code 离线包

参数：
  --package DIR   离线包目录，默认当前脚本所在目录
  --no-gpg        跳过 GPG 签名校验，只校验 SHA256
  -h, --help      显示帮助
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package) PKG_DIR="${2:-}"; shift 2 ;;
    --no-gpg) SKIP_GPG=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

if [[ -z "$PKG_DIR" ]]; then
  PKG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
else
  PKG_DIR="$(cd "$PKG_DIR" && pwd)"
fi

[[ -f "$PKG_DIR/meta/checksums.txt" ]] || die "缺少 $PKG_DIR/meta/checksums.txt"
[[ -f "$PKG_DIR/bin/claude" ]] || die "缺少 $PKG_DIR/bin/claude"

(
  cd "$PKG_DIR"
  sha256sum -c meta/checksums.txt
) >/dev/null
log "SHA256 校验通过。"

if [[ "$SKIP_GPG" -eq 1 ]]; then
  warn "已跳过 GPG 签名校验。"
  exit 0
fi

if [[ ! -f "$PKG_DIR/meta/manifest.json" || ! -f "$PKG_DIR/meta/manifest.json.sig" || ! -f "$PKG_DIR/meta/claude-code.asc" ]]; then
  warn "缺少 manifest/signature/key，跳过 GPG 签名校验。"
  exit 0
fi

if ! command -v gpg >/dev/null 2>&1; then
  warn "未安装 gpg，跳过 GPG 签名校验。"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/gnupg"
chmod 700 "$WORK/gnupg"
GNUPGHOME="$WORK/gnupg" gpg --batch --import "$PKG_DIR/meta/claude-code.asc" >/dev/null 2>&1
FP="$(GNUPGHOME="$WORK/gnupg" gpg --batch --with-colons --fingerprint security@anthropic.com 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
[[ "${FP^^}" == "$EXPECTED_GPG_FPR" ]] || die "GPG 指纹不匹配：$FP"
GNUPGHOME="$WORK/gnupg" gpg --batch --verify "$PKG_DIR/meta/manifest.json.sig" "$PKG_DIR/meta/manifest.json" >/dev/null 2>&1 || die "manifest 签名校验失败"
log "manifest GPG 签名校验通过。"
