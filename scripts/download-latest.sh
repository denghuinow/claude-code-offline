#!/usr/bin/env bash
set -Eeuo pipefail

# Claude Code 最新/指定版本离线包制作脚本（Linux / Windows）
# 用法：
#   ./scripts/download-latest.sh --channel latest --platform auto
#   ./scripts/download-latest.sh --version 2.1.89 --platform linux-x64
#   ./scripts/download-latest.sh --platform all
#   ./scripts/download-latest.sh --platform win32-x64
#   ./scripts/download-latest.sh --platform all-windows

REPO_DEFAULT="https://downloads.claude.ai/claude-code-releases"
GCS_REPO_DEFAULT="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
KEY_URL_DEFAULT="https://downloads.claude.ai/keys/claude-code.asc"
NPM_REGISTRY_URL="https://registry.npmjs.org/@anthropic-ai%2fclaude-code"
EXPECTED_GPG_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

REPO="${CLAUDE_CODE_RELEASE_REPO:-$REPO_DEFAULT}"
GCS_REPO="${CLAUDE_CODE_GCS_REPO:-$GCS_REPO_DEFAULT}"
KEY_URL="${CLAUDE_CODE_KEY_URL:-$KEY_URL_DEFAULT}"
OUT_DIR="dist"
CHANNEL="latest"
VERSION=""
PLATFORM="auto"
SKIP_GPG=0
KEEP_WORK=0
WORK_DIR=""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"; }

usage() {
  cat <<USAGE
Claude Code 离线包制作脚本

参数：
  --channel latest|stable      下载渠道，默认 latest
  --version X.Y.Z              固定版本；设置后不再解析 channel
  --platform auto|all|all-windows|linux-x64|linux-arm64|linux-x64-musl|linux-arm64-musl|win32-x64|win32-arm64
                              默认 auto，自动识别当前在线机器平台（Linux）
                              all=全部 Linux；all-windows=全部 Windows
  --out DIR                    输出目录，默认 dist
  --no-gpg                     不校验 manifest 签名，仅校验 SHA256
  --keep-work                  保留临时工作目录，便于排错
  -h, --help                   显示帮助

示例：
  ./scripts/download-latest.sh --channel latest --platform auto
  ./scripts/download-latest.sh --channel stable --platform linux-x64
  ./scripts/download-latest.sh --version 2.1.89 --platform all
  ./scripts/download-latest.sh --channel latest --platform win32-x64
  ./scripts/download-latest.sh --channel latest --platform all-windows

输出：
  dist/claude-code-offline-<version>-<platform>.tar.gz
  dist/claude-code-offline-<version>-<platform>.tar.gz.sha256
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    --no-gpg) SKIP_GPG=1; shift ;;
    --keep-work) KEEP_WORK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

[[ "$CHANNEL" == "latest" || "$CHANNEL" == "stable" ]] || die "--channel 只能是 latest 或 stable"
case "$PLATFORM" in
  auto|all|all-windows|linux-x64|linux-arm64|linux-x64-musl|linux-arm64-musl|win32-x64|win32-arm64) ;;
  *) die "不支持的平台：$PLATFORM" ;;
esac

need_cmd curl
need_cmd sha256sum
need_cmd tar
need_cmd python3

fetch_text() {
  local url="$1"
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 "$url"
}

download_file() {
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --progress-bar "$url" -o "$out"
}

resolve_version() {
  if [[ -n "$VERSION" ]]; then
    printf '%s\n' "$VERSION"
    return 0
  fi

  local v=""
  # 官方原生安装器使用的 release channel。部分网络环境下 downloads 域名可能不可达，因此保留 GCS 兜底。
  for base in "$REPO" "$GCS_REPO"; do
    if v="$(fetch_text "$base/$CHANNEL" 2>/dev/null | tr -d '[:space:]')" && [[ -n "$v" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  done

  # 兜底：npm dist-tag。官方文档说明 npm 包安装的是同一个原生二进制。
  local tmp_json
  tmp_json="$(mktemp)"
  if download_file "$NPM_REGISTRY_URL" "$tmp_json" >/dev/null 2>&1; then
    v="$(python3 - "$tmp_json" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
print(data.get('dist-tags', {}).get('latest', ''))
PY
)"
    rm -f "$tmp_json"
    if [[ -n "$v" ]]; then
      printf '%s\n' "$v"
      return 0
    fi
  fi
  rm -f "$tmp_json" 2>/dev/null || true

  return 1
}

detect_platform() {
  local arch cpu libc suffix
  arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
  case "$arch" in
    x86_64|amd64) cpu="x64" ;;
    aarch64|arm64) cpu="arm64" ;;
    *) die "无法自动识别 CPU 架构：$arch，请手动传 --platform" ;;
  esac

  libc="glibc"
  if (ldd --version 2>&1 || true) | grep -qi musl; then
    libc="musl"
  elif ls /lib/libc.musl-* >/dev/null 2>&1 || ls /usr/lib/libc.musl-* >/dev/null 2>&1; then
    libc="musl"
  fi

  suffix="linux-$cpu"
  [[ "$libc" == "musl" ]] && suffix="$suffix-musl"
  printf '%s\n' "$suffix"
}

platforms_to_download() {
  case "$PLATFORM" in
    auto) detect_platform ;;
    all) printf '%s\n' linux-x64 linux-arm64 linux-x64-musl linux-arm64-musl ;;
    all-windows) printf '%s\n' win32-x64 win32-arm64 ;;
    *) printf '%s\n' "$PLATFORM" ;;
  esac
}

is_windows_platform() {
  [[ "$1" == win32-* ]]
}

json_binary_name() {
  local manifest="$1" platform="$2"
  python3 - "$manifest" "$platform" <<'PY'
import json, sys
manifest, platform = sys.argv[1], sys.argv[2]
with open(manifest, 'r', encoding='utf-8') as f:
    data = json.load(f)
item = data.get('platforms', {}).get(platform)
if not item:
    raise SystemExit(f'platform not found in manifest: {platform}')
binary = item.get('binary')
if not binary:
    raise SystemExit(f'binary name not found for platform: {platform}')
print(binary)
PY
}

json_checksum() {
  local manifest="$1" platform="$2"
  python3 - "$manifest" "$platform" <<'PY'
import json, sys
manifest, platform = sys.argv[1], sys.argv[2]
with open(manifest, 'r', encoding='utf-8') as f:
    data = json.load(f)
item = data.get('platforms', {}).get(platform)
if not item:
    raise SystemExit(f'platform not found in manifest: {platform}')
checksum = item.get('checksum') or item.get('sha256') or item.get('sha256sum')
if not checksum:
    raise SystemExit(f'checksum not found for platform: {platform}')
print(checksum.strip().lower())
PY
}

verify_manifest_signature() {
  local work="$1" manifest="$2" sig="$3" key="$4"

  if [[ "$SKIP_GPG" -eq 1 ]]; then
    warn "已跳过 GPG 签名校验。"
    return 0
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    warn "未安装 gpg，跳过 manifest 签名校验；仍会校验 SHA256。"
    return 0
  fi
  if [[ ! -s "$sig" ]]; then
    warn "未找到 manifest.json.sig，可能是旧版本；跳过签名校验。"
    return 0
  fi

  local gnupg fp
  gnupg="$work/gnupg"
  mkdir -p "$gnupg"
  chmod 700 "$gnupg"
  GNUPGHOME="$gnupg" gpg --batch --import "$key" >/dev/null 2>&1
  fp="$(GNUPGHOME="$gnupg" gpg --batch --with-colons --fingerprint security@anthropic.com 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')"
  [[ "${fp^^}" == "$EXPECTED_GPG_FPR" ]] || die "GPG 指纹不匹配：$fp"
  GNUPGHOME="$gnupg" gpg --batch --verify "$sig" "$manifest" >/dev/null 2>&1 || die "manifest 签名校验失败"
  log "manifest 签名校验通过。"
}

make_one_package() {
  local version="$1" platform="$2" work="$3" out_dir="$4"
  local manifest="$work/manifest.json"
  local sig="$work/manifest.json.sig"
  local key="$work/claude-code.asc"
  local binary_name binary checksum_expected checksum_actual pkg_name pkg_dir archive

  binary_name="$(json_binary_name "$manifest" "$platform")"
  binary="$work/$platform/$binary_name"

  log "下载 $platform 二进制（$binary_name）。"
  download_file "$REPO/$version/$platform/$binary_name" "$binary"
  if is_windows_platform "$platform"; then
    chmod +x "$binary" 2>/dev/null || true
  else
    chmod +x "$binary"
  fi

  checksum_expected="$(json_checksum "$manifest" "$platform")"
  checksum_actual="$(sha256sum "$binary" | awk '{print tolower($1)}')"
  [[ "$checksum_actual" == "$checksum_expected" ]] || die "$platform SHA256 不匹配：expected=$checksum_expected actual=$checksum_actual"
  log "$platform SHA256 校验通过。"

  pkg_name="claude-code-offline-$version-$platform"
  pkg_dir="$out_dir/$pkg_name"
  rm -rf "$pkg_dir"
  mkdir -p "$pkg_dir/bin" "$pkg_dir/meta"

  install -m 755 "$binary" "$pkg_dir/bin/$binary_name"
  cp "$manifest" "$pkg_dir/meta/manifest.json"
  [[ -s "$sig" ]] && cp "$sig" "$pkg_dir/meta/manifest.json.sig" || true
  cp "$key" "$pkg_dir/meta/claude-code.asc"

  if is_windows_platform "$platform"; then
    cp "$PROJECT_ROOT/scripts/install-offline.ps1" "$pkg_dir/install-offline.ps1"
    cp "$PROJECT_ROOT/scripts/verify-package.ps1" "$pkg_dir/verify-package.ps1"
    cp "$PROJECT_ROOT/scripts/uninstall.ps1" "$pkg_dir/uninstall.ps1"
    cat > "$pkg_dir/README-OFFLINE.md" <<README
# Claude Code 离线安装包

版本：$version
平台：$platform

## 离线安装

以管理员身份打开 PowerShell，进入解压目录后执行：

\`\`\`powershell
.\verify-package.ps1
.\install-offline.ps1
claude --version
\`\`\`

仅当前用户安装（无需管理员）：

\`\`\`powershell
.\install-offline.ps1 -User
claude --version
\`\`\`

默认安装路径：

- 系统级：\`C:\Program Files\Claude Code\bin\claude.exe\`
- 用户级：\`%LOCALAPPDATA%\Programs\claude-code\bin\claude.exe\`

## 安装前校验

\`\`\`powershell
.\verify-package.ps1
\`\`\`

## 卸载

\`\`\`powershell
.\uninstall.ps1
# 或：.\uninstall.ps1 -User
\`\`\`

说明：离线安装只解决安装包分发问题；首次使用仍需要可访问 Claude 服务并完成登录或配置企业/API 认证。
README
  else
    cp "$PROJECT_ROOT/scripts/install-offline.sh" "$pkg_dir/install-offline.sh"
    cp "$PROJECT_ROOT/scripts/verify-package.sh" "$pkg_dir/verify-package.sh"
    cp "$PROJECT_ROOT/scripts/uninstall.sh" "$pkg_dir/uninstall.sh"
    chmod +x "$pkg_dir"/*.sh
    cat > "$pkg_dir/README-OFFLINE.md" <<README
# Claude Code 离线安装包

版本：$version
平台：$platform

## 离线安装

系统级安装：

\`\`\`bash
sudo ./install-offline.sh
claude --version
\`\`\`

仅当前用户安装：

\`\`\`bash
./install-offline.sh --user
~/.local/bin/claude --version
\`\`\`

## 安装前校验

\`\`\`bash
./verify-package.sh
\`\`\`

## 卸载

\`\`\`bash
sudo ./uninstall.sh
# 或：./uninstall.sh --user
\`\`\`

说明：离线安装只解决安装包分发问题；首次使用仍需要可访问 Claude 服务并完成登录或配置企业/API 认证。
README
  fi

  cat > "$pkg_dir/meta/checksums.txt" <<CHECKSUMS
$checksum_actual  bin/$binary_name
CHECKSUMS
  cat > "$pkg_dir/VERSION" <<VERSIONFILE
$version
VERSIONFILE
  cat > "$pkg_dir/PLATFORM" <<PLATFORMFILE
$platform
PLATFORMFILE

  archive="$out_dir/$pkg_name.tar.gz"
  tar -C "$out_dir" -czf "$archive" "$pkg_name"
  sha256sum "$archive" > "$archive.sha256"
  log "已生成：$archive"
}

main() {
  local version abs_out manifest sig key
  version="$(resolve_version)" || die "无法解析 Claude Code $CHANNEL 最新版本；可用 --version 手动指定。"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "解析到的版本号异常：$version"
  log "目标版本：$version"

  mkdir -p "$OUT_DIR"
  abs_out="$(cd "$OUT_DIR" && pwd)"
  WORK_DIR="$(mktemp -d)"
  if [[ "$KEEP_WORK" -eq 0 ]]; then
    trap 'rm -rf "$WORK_DIR"' EXIT
  else
    warn "保留临时目录：$WORK_DIR"
  fi

  manifest="$WORK_DIR/manifest.json"
  sig="$WORK_DIR/manifest.json.sig"
  key="$WORK_DIR/claude-code.asc"

  log "下载 manifest、签名和公钥。"
  download_file "$REPO/$version/manifest.json" "$manifest"
  download_file "$REPO/$version/manifest.json.sig" "$sig" || warn "manifest.json.sig 下载失败，可能是旧版本或临时网络问题。"
  download_file "$KEY_URL" "$key"

  verify_manifest_signature "$WORK_DIR" "$manifest" "$sig" "$key"

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    make_one_package "$version" "$p" "$WORK_DIR" "$abs_out"
  done < <(platforms_to_download)

  log "完成。输出目录：$abs_out"
}

main "$@"
