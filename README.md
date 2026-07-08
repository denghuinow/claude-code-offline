# Claude Code 离线包下载与安装脚本

这个项目用于在**有网机器**上下载 Claude Code 最新版，然后生成可拷贝到**离线机器**安装的 tar.gz 包。

默认走官方二进制发布通道，支持：

**Linux**

- `linux-x64`：普通 x86_64 glibc Linux，Ubuntu/Debian/openEuler/CentOS/RHEL 常用
- `linux-arm64`：ARM64 glibc Linux
- `linux-x64-musl`：x86_64 musl，例如 Alpine
- `linux-arm64-musl`：ARM64 musl

**Windows**

- `win32-x64`：Windows x64
- `win32-arm64`：Windows ARM64

项目也附带一个可选的 `.deb` 下载脚本，适合 Debian/Ubuntu 体系。

## 1. 在线机器：下载最新版并打包

```bash
unzip claude-code-offline-project.zip
cd claude-code-offline
chmod +x scripts/*.sh

# 自动识别当前机器架构，下载 latest 渠道
./scripts/download-latest.sh --channel latest --platform auto
```

输出示例：

```text
dist/claude-code-offline-2.x.x-linux-x64.tar.gz
dist/claude-code-offline-2.x.x-linux-x64.tar.gz.sha256
```

下载所有 Linux 平台：

```bash
./scripts/download-latest.sh --channel latest --platform all
```

下载 Windows 平台（在有网的 Linux/macOS 机器上打包，拷贝到离线 Windows 安装）：

```bash
./scripts/download-latest.sh --channel latest --platform win32-x64
./scripts/download-latest.sh --channel latest --platform all-windows
```

或使用 Makefile：

```bash
make all-windows
```

固定版本：

```bash
./scripts/download-latest.sh --version 2.1.89 --platform linux-x64
```

使用 stable 渠道：

```bash
./scripts/download-latest.sh --channel stable --platform linux-x64
```

## 2. 离线机器：安装

### Linux

把 `dist/claude-code-offline-*-linux-*.tar.gz` 拷贝到离线 Linux 机器：

```bash
tar xzf claude-code-offline-*.tar.gz
cd claude-code-offline-*

# 可选：先校验包
./verify-package.sh

# 系统级安装到 /usr/local/bin/claude
sudo ./install-offline.sh

claude --version
```

仅当前用户安装：

```bash
./install-offline.sh --user
~/.local/bin/claude --version
```

如果 `~/.local/bin` 不在 PATH：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Windows

把 `dist/claude-code-offline-*-win32-*.tar.gz` 拷贝到离线 Windows 机器，解压后（Windows 10+ 自带 `tar`，或用 7-Zip）：

```powershell
tar -xzf claude-code-offline-*-win32-x64.tar.gz
cd claude-code-offline-*-win32-x64

# 可选：先校验包
.\verify-package.ps1

# 系统级安装（需管理员 PowerShell）
.\install-offline.ps1
claude --version
```

仅当前用户安装：

```powershell
.\install-offline.ps1 -User
claude --version
```

## 3. 可选：下载 Debian/Ubuntu `.deb` 离线包

在有网的 Debian/Ubuntu 机器上：

```bash
./scripts/download-deb-latest.sh --channel latest
```

离线机器安装：

```bash
cd dist/deb
sudo ./install-deb-offline.sh
```

或：

```bash
sudo apt install ./claude-code_*.deb
```

## 4. 常用场景

### Ubuntu 24.04 x86_64

```bash
./scripts/download-latest.sh --channel latest --platform linux-x64
```

### openEuler / CentOS / RHEL x86_64

```bash
./scripts/download-latest.sh --channel latest --platform linux-x64
```

离线安装建议用 tar.gz 二进制包，不依赖 dnf 仓库。

### ARM64 Linux

```bash
./scripts/download-latest.sh --channel latest --platform linux-arm64
```

### Alpine Linux

```bash
./scripts/download-latest.sh --channel latest --platform linux-x64-musl
```

Alpine 可能还需要：

```bash
apk add libgcc libstdc++ ripgrep
```

## 5. 校验说明

下载脚本会：

1. 解析 `latest` 或 `stable` 版本；
2. 下载 `manifest.json`、`manifest.json.sig` 和 Anthropic GPG 公钥；
3. 校验 GPG 指纹；
4. 校验 manifest 签名；
5. 下载对应平台的 `claude` 二进制；
6. 按 manifest 中的平台 SHA256 校验二进制；
7. 生成离线 tar.gz 包和 tar.gz 的 SHA256。

如果在线机器没有 `gpg`，脚本会提示并退化为 SHA256 校验。建议安装：

```bash
sudo apt install gpg curl ca-certificates
```

## 6. 卸载

### Linux

系统级安装卸载：

```bash
sudo ./uninstall.sh
```

用户级安装卸载：

```bash
./uninstall.sh --user
```

如需删除 Claude Code 用户配置、历史和会话：

```bash
./uninstall.sh --user --remove-user-data
```

### Windows

```powershell
.\uninstall.ps1
# 或：.\uninstall.ps1 -User
# 删除用户数据：.\uninstall.ps1 -User -RemoveUserData
```

## 7. 注意

离线包只解决“安装过程离线”。Claude Code 运行和首次登录仍需要能访问 Claude 服务，或配置 Anthropic Console、Amazon Bedrock、Google Vertex AI、Microsoft Foundry 等受支持认证方式。
