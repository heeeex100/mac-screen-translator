# 截图翻译器

一款面向 macOS 的原生截图翻译工具。框选屏幕上的文字后，使用 Apple Vision 识别内容，并通过 DeepSeek API 翻译成目标语言。

## ✨ 功能

- 框选屏幕区域，自动 OCR 并翻译
- 单独执行 OCR，识别结果自动复制到剪贴板
- 翻译当前剪贴板中的文字
- 翻译其他应用当前选中的文字，点击按钮后会自动切回原应用读取选区
- 支持中文、英文、日文、韩文和自动识别
- 支持直接编辑识别结果，再按 `⌘ Enter` 翻译
- 在独立悬浮窗口中查看翻译结果
- 自动生成学习笔记，整理句意、表达要点和重点词汇
- 快捷键可在设置中重新录制
- API Key 保存到 macOS 钥匙串
- 请求日志写入 macOS 统一日志和本地日志文件

## 🖥️ 系统要求

- macOS 14.0 或更高版本
- Swift 5.9 或更高版本
- 一个可用的 [DeepSeek API Key](https://platform.deepseek.com/)
- 本地构建需要 Xcode Command Line Tools 或完整 Xcode

## 🚀 快速开始

### 1. 获取代码

```bash
git clone https://github.com/heeeex100/mac-screen-translator.git
cd mac-screen-translator
```

### 2. 构建应用

应用需要稳定的代码签名身份，才能让 macOS 持续保留屏幕录制等隐私权限。请使用本机已安装的 Apple Development 或 Developer ID 证书：

```bash
CODESIGN_IDENTITY='Apple Development: Your Name (TEAMID)' ./Scripts/build-app.sh
```

构建完成后，应用位于 `dist/MacScreenTranslator.app`：

```bash
open dist/MacScreenTranslator.app
```

脚本会执行 Release 构建、签名和签名校验。没有可用的证书时，脚本会直接报错，不会退回到 ad-hoc 签名。

### 3. 配置 API Key

启动应用后：

1. 点击右上角的“设置”。
2. 填写 DeepSeek API Key。
3. 选择模型和目标语言。
4. 点击“保存 API Key”或“完成”。

默认模型是 `deepseek-flash`，可以根据 DeepSeek 账户中可用的模型自行修改。

## ⌨️ 使用方式

| 操作 | 默认快捷键 | 说明 |
| --- | --- | --- |
| 框选翻译 | `⌃ ⇧ T` | 框选屏幕区域，识别文字并翻译 |
| 翻译剪贴板 | `⌃ ⇧ V` | 翻译剪贴板中的纯文本 |
| 翻译选中文字 | — | 先在其他应用中选中文字，再点击主窗口按钮；应用会自动恢复原选区 |
| 仅 OCR | — | 框选区域并识别文字，结果自动复制到剪贴板 |
| 翻译编辑后的原文 | `⌘ Enter` | 修改“识别原文”后重新提交翻译 |

截图翻译、OCR 和翻译选中文字也可以从菜单栏图标或主窗口中执行。快捷键可以在“设置”中重新录制。

## 🔐 系统权限

首次使用相关功能时，请在“系统设置 → 隐私与安全性”中授予权限：

- **屏幕录制**：用于截取框选区域，截图翻译和 OCR 都需要此权限。
- **辅助功能**：用于读取其他应用当前选中的文字。没有此权限时，应用会尝试通过模拟 `⌘ C` 获取选区。

权限与应用的签名身份和路径有关。重新签名、修改 Bundle ID 或更换应用位置后，macOS 可能要求重新授权。

## 🛠️ 开发构建

只编译可执行文件：

```bash
swift build
```

构建并运行签名后的 App：

```bash
CODESIGN_IDENTITY='Apple Development: Your Name (TEAMID)' ./Scripts/build-app.sh
open dist/MacScreenTranslator.app
```

日常测试建议使用打包后的 App。这样可以保持应用身份稳定，避免 `swift run`、Xcode 运行和打包应用之间反复切换导致隐私权限失效。

## 🧱 技术栈

- **SwiftUI**：主界面和设置界面
- **AppKit**：菜单栏、窗口管理、全局快捷键和选区面板
- **Vision**：本地文字识别
- **DeepSeek Chat Completions API**：翻译和学习笔记
- **Security.framework**：保存 API Key 到 macOS 钥匙串
- **CoreGraphics**：屏幕截图和选区裁剪

## 📁 项目结构

```text
Sources/
├── MacScreenTranslatorApp.swift    # SwiftUI 应用入口
├── AppDelegate.swift                # 生命周期、菜单栏和全局快捷键
├── AppVisibilityController.swift   # 主窗口显示状态
├── ContentView.swift                # 主界面和设置界面
├── SelectionOverlay.swift           # 屏幕框选面板
├── TranslationStore.swift            # OCR、翻译和状态管理
├── TranslationResultPanel.swift     # 悬浮翻译结果窗口
├── ShortcutRecorder.swift           # 快捷键录制
├── KeychainStore.swift              # 钥匙串读写
└── AppLogger.swift                  # 请求日志

Packaging/Info.plist                # App 元数据和权限说明
Scripts/build-app.sh                 # Release 构建与签名脚本
```

## 📝 日志

日志文件默认位于：

```text
~/Library/Logs/MacScreenTranslator/translation.log
```

可以在应用设置中点击“打开日志”。日志记录请求状态、HTTP 状态码和耗时，不记录 API Key 或原文内容。

## 📄 许可证

本项目采用 [MIT License](./LICENSE) 开源。

你可以自由使用、修改、分发和商业化本项目，但需要保留版权声明和许可证文本。许可证仅覆盖本项目代码，不覆盖 Apple 系统框架、DeepSeek API 或其他第三方服务各自的使用条款。
