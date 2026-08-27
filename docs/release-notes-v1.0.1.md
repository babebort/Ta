# Ta v1.0.1 · AI 识图、长截图与 Agent 能力更新

Ta v1.0.1 汇总了首个公开版本之后的稳定性修复、交互优化与 Agent 集成能力。

## 主要更新

- AI 识图改为视觉理解优先：没有文字的动物、图标和场景也会被正常描述；遇到仅返回“没有文字”的无效结果会自动恢复一次。
- 重构长截图的自动滚动、进度判断、重复帧过滤、接缝匹配与底部收尾，降低重复、吞字和提前结束。
- 优化截图定格、窗口识别、自由框选、选区调整、右键取消和工具栏鼠标反馈。
- 改进钉图尺寸、移动边界、窗口边框与阴影控制。
- 重新整理 AI 模型与翻译配置，支持多套 Provider、智谱渠道、Keychain 持久化和翻译模型复用。
- 改进结果提示胶囊、标注工具栏与截图后的原位操作体验。
- 发布 `ta` CLI、Ta Agent Skill 与 DeepSeek Harness 插件，并在“设置 → Agent”提供一键安装命令。
- Agent 截图支持无感运行、隐私黑名单、云端策略、审计记录和本地图片标注配方。

## 下载

- `Ta-1.0.1-macOS-universal.dmg`：推荐安装包，支持 Apple Silicon 与 Intel Mac。
- `Ta-1.0.1-macOS-universal.zip`：备用 App 压缩包。
- `Ta-CLI-1.0.1-macOS-universal.tar.gz`：Agent 使用的通用 CLI。
- `Ta-Agent-Skill-1.0.1.zip`：适用于 Codex、Claude Code 等 Agent 的 Skill。
- `dsh-ta-1.0.1.tgz`：DeepSeek Harness 插件包。
- `install.sh`：CLI 与 Skill 一键安装脚本。
- `SHA256SUMS.txt`：所有发布资产的 SHA-256 校验值。

一键安装 CLI 与 Skill：

```bash
curl -fsSL --retry 3 --retry-all-errors --retry-delay 1 https://github.com/kangarooking/Ta/releases/latest/download/install.sh | bash
```

## macOS 提示

当前发布包使用 Apple Development 签名，尚未完成 Developer ID 公证。首次启动时，请在 Finder 中按住 Control 点击「拓」，选择“打开”，并再次确认。
