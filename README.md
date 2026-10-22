# 多多翻译

一款面向 macOS 的原生截图翻译工具。框选屏幕上的文字后，使用 Apple Vision 识别内容，并通过 OpenAI 或 DeepSeek API 翻译成目标语言。

## ✨ 功能

- 框选屏幕区域，确认后识别并翻译
- 翻译剪贴板文字或图片，衔接 macOS 自带截图工具
- 图片识别可选本地 Apple Vision OCR 或大模型图片识别
- 单独识别文字，结果自动复制到剪贴板
- 支持中文、英文、日文、韩文和自动识别
- 支持直接编辑识别结果，点击“翻译原文”或按 `⌘ Enter` 翻译
- 一键复制译文，主窗口支持缩放、半屏布局和上下滚动
- 在独立悬浮窗口中查看翻译结果
- 自动生成学习笔记，整理句意、表达要点和重点词汇
- 快捷键可在设置中重新录制
- API Key 保存到 macOS 钥匙串
- 请求日志写入 macOS 统一日志和本地日志文件

## 🖥️ 系统要求

- macOS 14.0 或更高版本
- Swift 5.9 或更高版本
- 一个可用的 [OpenAI API Key](https://platform.openai.com/api-keys) 或 [DeepSeek API Key](https://platform.deepseek.com/)
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

构建完成后，应用位于 `dist/多多翻译.app`：

```bash
open dist/多多翻译.app
```

脚本会执行 Release 构建、签名和签名校验。没有可用的证书时，脚本会直接报错，不会退回到 ad-hoc 签名。

### 3. 配置 API Key

启动应用后：

1. 点击右上角的“设置”。
2. 在设置中选择 OpenAI 或 DeepSeek，填写对应的 API Key。
3. 选择模型和目标语言。
4. 点击“保存 API Key”或“完成”。

DeepSeek 默认模型是 `deepseek-flash`，OpenAI 默认模型是 `gpt-4o-mini`，都可以根据账户中可用的模型自行修改。

## ⌨️ 使用方式

| 操作 | 默认快捷键 | 说明 |
| --- | --- | --- |
| 框选翻译 | `⌃ ⇧ T` | 框选屏幕区域，识别文字并翻译 |
| 翻译剪贴板 | `⌃ ⇧ V` | 翻译剪贴板中的文字或图片 |
| 仅识别 | — | 框选区域并识别文字，结果自动复制到剪贴板 |
| 翻译编辑后的原文 | `⌘ Enter` | 修改“识别原文”后重新提交翻译 |

截图翻译和 OCR 也可以从菜单栏图标或主窗口中执行。看到文字后按下“框选翻译”快捷键，再拖出包含文字的区域，松开后按 Enter 或点击“确认”开始识别和翻译。确认前可再次拖动重选，按 Esc 或点击“取消”退出框选；快捷键可以在“设置”中重新录制。

### 使用系统截图翻译

1. 保持多多翻译运行，按 `⌃ ⌘ ⇧ 4` 使用系统截图工具框选，图片会写入剪贴板。
2. 按多多翻译的剪贴板快捷键（默认 `⌃ ⇧ V`），或点击“翻译剪贴板”。图片先识别，再翻译；文字剪贴板直接翻译。图片与文字同时存在时，优先处理图片。
3. 在“设置 → 图片识别”选择模式，此配置同时用于框选翻译、剪贴板图片和“仅识别”。

- **本地 OCR（默认）**：使用 macOS Apple Vision，图片在本机识别，识别原文交给所选翻译服务。识别语言在“语言偏好”中配置，Apple Vision 的模型由系统管理。
- **大模型图片识别**：填写识别服务 Base URL、支持图片输入的模型名称和独立 API Key。默认地址为 `https://api.openai.com/v1`，模型名称可修改；也可填写兼容 Chat Completions 图片输入的其他服务或本机服务。图片会发送到指定服务，可能产生费用；更换服务时也应更换对应密钥。此模式先转录原文，再交给“翻译服务”翻译，不生成图片内容摘要。

识别服务与翻译服务可以分别选择，例如使用支持图片输入的服务识别，再用 DeepSeek 翻译。仅修改模型名称不会让不支持图片输入的接口获得图片能力。大模型识别失败会提示错误，不自动切换到其他服务。

## 🔐 系统权限

首次使用相关功能时，请在“系统设置 → 隐私与安全性”中授予权限：

- **屏幕录制**：用于截取框选区域，截图翻译和 OCR 都需要此权限。

权限与应用的签名身份和路径有关。重新签名、修改 Bundle ID 或更换应用位置后，macOS 可能要求重新授权。

## 🛠️ 开发构建

只编译可执行文件：

```bash
swift build
```

构建并运行签名后的 App：

```bash
CODESIGN_IDENTITY='Apple Development: Your Name (TEAMID)' ./Scripts/build-app.sh
open dist/多多翻译.app
```

日常测试建议使用打包后的 App。这样可以保持应用身份稳定，避免 `swift run`、Xcode 运行和打包应用之间反复切换导致隐私权限失效。

翻译请求进行中也可再次框选或翻译剪贴板，新操作会取消旧请求；截图识别或翻译过程中可点击“取消并重选”。翻译完成后，结果窗口会自动显示在前台。

## 🧪 单元测试

在项目根目录执行：

```bash
swift test
```

目前包含 63 个 XCTest 用例（其中 2 个真实 Vision 集成测试需显式启用），覆盖学习笔记解析、翻译与学习笔记异步请求隔离、截图坐标换算、OCR 阅读顺序、快捷键显示及注册回滚，默认测试不访问外部网络、钥匙串或屏幕录制权限；剪贴板测试使用独立的临时剪贴板。覆盖范围与调试方法见 [单元测试说明](./docs/单元测试说明.md)。

## 🧱 技术栈

- **SwiftUI**：主界面和设置界面
- **AppKit**：菜单栏、窗口管理、全局快捷键和选区面板
- **Vision**：本地文字识别
- **OpenAI / DeepSeek Chat Completions API**：翻译和学习笔记
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
Packaging/AppIcon.png               # 图标源图
Packaging/AppIcon.icns              # macOS 多尺寸图标
Packaging/StatusIcon-source.png     # 配套状态栏透明单色源图
Packaging/StatusIcon*.png            # 状态栏普通及 Retina 资源
Scripts/build-icon.sh               # 图标转换脚本
Scripts/build-app.sh                 # Release 构建与签名脚本
docs/design/icon-history/           # 历史图标设计稿和提示词
```

图标设计过程、接入方式和替换步骤见 [图标设计与接入](./docs/图标设计与接入.md)。
当前色块版与配套状态栏图标见 [色块图标与状态栏图标](./docs/色块图标与状态栏图标.md)。
与图标配套的暖色界面、明暗预览及验证说明见 [界面美化说明](./docs/界面美化说明.md)。

## 📝 日志

日志文件默认位于：

```text
~/Library/Logs/MacScreenTranslator/translation.log
```

可以在应用设置中点击“打开日志”。日志记录请求状态、HTTP 状态码和耗时，不记录 API Key 或原文内容。

## 📄 许可证

本项目采用 [MIT License](./LICENSE) 开源。

你可以自由使用、修改、分发和商业化本项目，但需要保留版权声明和许可证文本。许可证仅覆盖本项目代码，不覆盖 Apple 系统框架、DeepSeek API 或其他第三方服务各自的使用条款。

界面与流程的三轮审计、前后截图及验证范围见 [2026-10-22 审计记录](./docs/audit-2026-10-22/审计记录.md)。
