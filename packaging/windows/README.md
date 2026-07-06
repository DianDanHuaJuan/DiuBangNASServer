# Windows 安装包构建

## 前置条件

- Windows 10/11 x64 构建机
- Flutter 3.38+、`flutter doctor -v` 无 Windows/VS 红叉
- Visual Studio 2022（「使用 C++ 的桌面开发」）
- [Inno Setup 6](https://jrsoftware.org/isinfo.php)（生成 `.exe` 安装包时需要）
- 能稳定访问 **github.com**（bootstrap 下载 media_kit / FFmpeg）
- 建议安装 [7-Zip](https://www.7-zip.org/)（CMake 解压 `.7z` 时使用）
- 仓库根目录已创建 `Encryption_key`（与客户端同密钥；见根目录 [README.md](../../README.md) 第 3 步）

## Windows 构建依赖（统一 bootstrap）

克隆后未纳入 Git 的外部依赖由统一脚本准备：

```powershell
.\tool\bootstrap_windows.ps1
```

| 依赖 | 说明 |
|------|------|
| **media_kit** | libmpv + ANGLE → `build/windows/x64/`，固定 MD5；避免 `Integrity check failed` |
| **FFmpeg LGPL** | [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) `win64-lgpl` 静态构建 → `assets/ffmpeg.exe`（HLS 编码：`h264_mf` / `libopenh264`） |

安装包构建时会将根目录 [`THIRD_PARTY_NOTICES.txt`](../../THIRD_PARTY_NOTICES.txt) 复制到 Release 目录，供 LGPL 等第三方许可声明。

特性：有限次重试（默认 3）、下载中断或 MD5/校验失败自动删文件重下、全部重试用尽后输出**具体失败依赖清单**。

单独修复：

```powershell
.\tool\bootstrap_windows.ps1 -Only media_kit -Force
.\tool\bootstrap_windows.ps1 -Only ffmpeg -Force
```

`build_installer.ps1` 构建前会自动调用上述脚本。

## MSVC 运行库（自动提取，约 700 KB）

不再内嵌完整的 `vc_redist.x64.exe`（~24 MB）。构建时会将以下 DLL 部署到 Release / 安装目录（应用本地，Win10/11 依赖系统 UCRT）：

- `vcruntime140.dll`
- `vcruntime140_1.dll`
- `msvcp140.dll`

`build_installer.ps1` 会调用 `collect_vc_runtime.ps1`：

1. 优先使用 `assets\vc_runtime\x64\` 缓存（若三文件齐全）
2. 否则从本机 Visual Studio 2022 的 `VC\Redist\MSVC\...\x64\Microsoft.VC143.CRT\` 复制并缓存

无 VS 的构建机可手动将上述三文件放入 `assets\vc_runtime\x64\`。

## 一键构建安装包

在仓库根目录 PowerShell 中执行：

```powershell
.\packaging\windows\build_installer.ps1
```

脚本流程：

1. 引导 Windows 构建依赖（`tool\bootstrap_windows.ps1`：media_kit + FFmpeg）
2. `flutter build windows --release`（自动注入 `NAS_APP_VERSION` / `NAS_BUILD_SHA` / `NAS_BUILD_TIME`）
3. 部署 MSVC 运行库 DLL 到 Release
4. 校验 `build\windows\x64\runner\Release\` 完整性
5. 调用 ISCC 编译 `packaging\windows\diubang_file_s.iss`

输出安装包：`packaging\windows\output\DiuBangFileS-Setup-<version>.exe`

### 常用参数

```powershell
# 已有 Release 产物，只打安装包
.\packaging\windows\build_installer.ps1 -SkipFlutterBuild

# 只构建 Release，不编译安装包（本机未装 Inno Setup 时）
.\packaging\windows\build_installer.ps1 -SkipInstaller
```

## 仅校验 Release 产物（smoke test）

```powershell
.\packaging\windows\verify_bundle.ps1
```

## 手动分步（等价于脚本）

```powershell
.\tool\bootstrap_windows.ps1
flutter build windows --release `
  --dart-define=NAS_APP_VERSION=1.0.2+2 `
  --dart-define=NAS_BUILD_SHA=<git-sha> `
  --dart-define=NAS_BUILD_TIME=<utc-iso8601>

& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" `
  /DMyAppVersion=1.0.2 `
  /DMyAppVersionFull=1.0.2+2 `
  packaging\windows\diubang_file_s.iss
```

## 发给测试者的说明要点

- **系统**：Windows 10 或 11，64 位；**不支持 Windows 7/8**
- **防火墙**：首次运行需允许专用/公用网络（默认 HTTPS 端口 8080）
- **默认口令**：`admin` / `admin`，内测请尽快修改
- **Encryption_key**：须与客户端使用同一份密钥（仓库根目录 `Encryption_key`，构建时自动打包）
- **托盘**：关闭窗口默认缩到托盘，非退出
