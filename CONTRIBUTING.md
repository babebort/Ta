# Contributing to Ta

感谢你愿意改进「拓 · Ta」。当前项目处于 Alpha 阶段，优先接受可复现的问题、明确的 macOS 交互改进和带验证步骤的修复。

## 开始之前

1. 搜索现有 Issues，确认问题尚未被报告；
2. 对较大的功能先创建 Issue，说明用户场景、预期行为和隐私影响；
3. 不要在 Issue、日志、测试或提交中包含真实 API Key、私人截图和个人信息。

## 本地开发

要求 macOS 14+ 与 Swift 6.2 工具链。

```bash
swift test
./scripts/build-app.sh
open "artifacts/拓.app"
```

涉及截图、自动滚动或快捷键的修改，请同时记录：

- macOS 版本与 Mac 芯片；
- 使用的目标应用；
- 是否开启屏幕录制/辅助功能权限；
- 可复现步骤、预期结果与实际结果；
- 不含私人内容的截图或录屏。

## Pull Request

- 保持改动聚焦，避免把无关格式调整混入功能修复；
- 行为变化应补充单元测试或手工验收步骤；
- UI 修改请附修改前后截图；
- 新增云端调用必须明确上传内容、触发条件和 Keychain 存储方式；
- 提交前运行 `swift test`，确保没有提交 `.build/`、`artifacts/`、OCR 权重或密钥。

提交 Pull Request 即表示你同意按本仓库的 MIT License 授权贡献内容。
