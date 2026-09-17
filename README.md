# macOS 原生截图翻译器

SwiftUI + AppKit + Vision 实现的 macOS 原生桌面应用，使用 DeepSeek API 翻译。

## 运行

```bash
cd mac-screen-translator
swift run
```

首次运行后，在应用的“设置”中填写 DeepSeek API Key。默认模型为 `deepseek-flash`，可按账户可用模型修改。按全局快捷键 `Ctrl+Shift+T` 框选区域；OCR 由 macOS Vision 完成，无需安装 Tesseract。

也可以先复制一段文字，再点击主窗口或菜单栏中的“翻译剪贴板”，译文会显示在置顶悬浮窗口中。

DeepSeek API Key 保存在 macOS Keychain（钥匙串）中，不会以明文写入应用偏好设置。

请在“系统设置 → 隐私与安全性 → 屏幕录制”允许 Terminal（开发运行）或之后打包的 App 访问屏幕。

## 打包为 macOS App

```bash
./Scripts/build-app.sh
open dist/MacScreenTranslator.app
```

生成的应用位于 `dist/MacScreenTranslator.app`。本地构建默认使用 ad-hoc 签名；如需分发给其他用户，请使用 Apple Developer 证书签名并进行公证。
