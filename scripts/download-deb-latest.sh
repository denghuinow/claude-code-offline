#!/usr/bin/env bash
set -Eeuo pipefail

# 可选：Debian/Ubuntu .deb 离线包下载脚本。
# 注意：只能在有 apt 的在线 Debian/Ubuntu 机器上运行。

CHANNEL="latest"
OUT_DIR="dist/deb"
ARCH=""
KEY_URL="https://downloads.claude.ai/keys/claude-code.asc"
EXPECTED_GPG_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<USAGE
下载 Claude Code .deb 离线包

参数：
  --channel latest|stable   默认 latest
  --arch amd64|arm64        默认自动识别 dpkg 架构
  --out DIR                 输出目录，默认 dist/deb
  -h, --help                显示帮助

示例：
  ./scripts/download-deb-latest.sh --channel latest
  ./scripts/download-deb-latest.sh --channel stable --arch amd64
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="${2:-}"; shift 2 ;;
    --arch) ARCH="${2:-}"; shift 2 ;;
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

[[ "$CHANNEL" == "latest" || "$CHANNEL" == "stable" ]] || die "--channel 只能是 latest 或 stable"
command -v apt-get >/dev/null 2>&1 || die "需要 apt-get"
command -v apt-cache >/dev/null 2>&1 || die "需要 apt-cache"
command -v curl >/dev/null 2>&1 || die "需要 curl"
command -v gpg >/dev/null 2>&1 || warn "未安装 gpg，无法显示 key 指纹"

if [[ -z "$ARCH" ]]; then
  ARCH="$(dpkg --print-architecture)"
fi
[[ "$ARCH" == "amd64" || "$ARCH" == "arm64" ]] || die "仅支持 amd64/arm64，当前：$ARCH"

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/lists/partial" "$WORK/cache/archives/partial" "$WORK/sourceparts" "$WORK/etc/apt/trusted.gpg.d"

curl -fsSL "$KEY_URL" -o "$WORK/claude-code.asc"
if command -v gpg >/dev/null 2>&1; then
  FP="$(gpg --show-keys --with-colons "$WORK/claude-code.asc" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
  [[ "${FP^^}" == "$EXPECTED_GPG_FPR" ]] || die "GPG 指纹不匹配：$FP"
  log "GPG 指纹校验通过。"
fi

cat > "$WORK/sources.list" <<SRC
deb [arch=$ARCH signed-by=$WORK/claude-code.asc] https://downloads.claude.ai/claude-code/apt/$CHANNEL $CHANNEL main
SRC
: > "$WORK/status"

APT_OPTS=(
  -o "Dir::Etc::sourcelist=$WORK/sources.list"
  -o "Dir::Etc::sourceparts=$WORK/sourceparts"
  -o "Dir::Etc::main=$WORK/apt.conf"
  -o "Dir::State::status=$WORK/status"
  -o "Dir::State::Lists=$WORK/lists"
  -o "Dir::Cache::archives=$WORK/cache/archives"
  -o "APT::Architecture=$ARCH"
  -o "Acquire::Languages=none"
)

log "更新临时 apt 索引：$CHANNEL/$ARCH"
apt-get "${APT_OPTS[@]}" update
VERSION="$(apt-cache "${APT_OPTS[@]}" policy claude-code | awk '/Candidate:/ {print $2; exit}')"
[[ -n "$VERSION" && "$VERSION" != "(none)" ]] || die "找不到 claude-code candidate 版本"
log "Candidate：$VERSION"

(
  cd "$OUT_DIR"
  apt-get "${APT_OPTS[@]}" download "claude-code=$VERSION"
)

DEB="$(ls -1 "$OUT_DIR"/claude-code_*_${ARCH}.deb | tail -n1)"
sha256sum "$DEB" > "$DEB.sha256"
cat > "$OUT_DIR/install-deb-offline.sh" <<'INSTALL'
#!/usr/bin/env bash
set -Eeuo pipefail
DEB="${1:-}"
if [[ -z "$DEB" ]]; then
  DEB="$(ls -1 ./claude-code_*.deb 2>/dev/null | tail -n1 || true)"
fi
[[ -n "$DEB" && -f "$DEB" ]] || { echo "找不到 claude-code_*.deb；也可传入 .deb 路径" >&2; exit 1; }
sudo apt install "./$DEB"
claude --version
INSTALL
chmod +x "$OUT_DIR/install-deb-offline.sh"
log "已生成：$DEB"
