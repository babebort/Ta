# Ta v1.0.0 · 首个公开版本

「拓」是一款 AI 原生截图工具。这是第一个可以直接下载安装的公开版本，同时支持 Apple Silicon 与 Intel Mac。

## 主要能力

- 快捷键框选后，本地 OCR 并自动复制文字
- 通用截图、复制图片、原位标注与图片钉住
- 自动滚动长截图、重复帧过滤、拼接与接缝检查
- 截图翻译、AI 识图与 OpenAI-compatible 模型配置
- Apple Vision OCR，以及可选的离线 PaddleOCR 增强包
- 自定义快捷键、Keychain API Key 存储与明确的云端上传确认

## 下载与安装

1. 下载 `Ta-1.0.0-macOS-universal.dmg`。
2. 打开 DMG，把「拓」拖入 `Applications`。
3. 当前版本尚未完成 Apple notarization。首次启动请在 Finder 中按住 Control 点击「拓」，选择“打开”，再确认一次。
4. 按提示开启“屏幕与系统音频录制”权限；自动滚动长截图还需要“辅助功能”权限。

ZIP 是备用安装包；`SHA256SUMS.txt` 可用于校验下载文件完整性。

## 系统要求

- macOS 14 或更高版本
- Apple Silicon 或 Intel Mac

## 已知限制

- 持续动画、视频、半透明浮层或大幅重排的页面，长截图可能仍需手动修正接缝。
- 图片翻译对复杂纹理、阴影、竖排文字和极密集排版仍可能留下覆盖痕迹。
- 本次公开包使用 Apple Development 签名，尚未使用 Developer ID 签名与 Apple notarization。

完整说明请查看 [README](https://github.com/kangarooking/Ta#readme)。问题和建议欢迎提交 [Issue](https://github.com/kangarooking/Ta/issues)。
