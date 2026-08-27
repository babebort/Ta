# Ta CLI 与 Agent Skill 一键安装设计

## 目标

让普通用户只执行一条终端命令，就能同时获得 `ta` CLI 与 Ta Agent Skill；不要求理解压缩包、PATH 或不同 Agent 的 Skills 目录。拓的 Agent 设置页同时提供终端命令和一段可直接发给 Agent 的安装提示词。

## 分发方式

安装器、CLI、Skill 与 `SHA256SUMS.txt` 都作为同一个 GitHub Release 的资产发布。用户执行：

```bash
curl -fsSL https://github.com/kangarooking/Ta/releases/latest/download/install.sh | bash
```

安装器自身携带对应 Release 版本，始终下载同版本的 CLI 与 Skill。下载完成后先校验 SHA-256，再写入用户目录，避免依赖 `main` 分支路径或安装到一半的状态。

## 安装位置与兼容性

- CLI：`~/.local/bin/ta`；若 PATH 尚未包含该目录，幂等写入 `~/.zprofile`。
- Codex Skill：`${CODEX_HOME:-~/.codex}/skills/ta`。
- 通用 Agent Skills：`~/.agents/skills/ta`。
- 已存在 `~/.claude` 时，同时安装到 `~/.claude/skills/ta`。

Skill 的启动检查在找不到 PATH 中的 `ta` 时，会回退到 `~/.local/bin/ta`，因此已经运行的 Agent 不会因为尚未重新加载 shell 配置而误报未安装。

## App 体验

“设置 → Agent”顶部增加安装区域：

1. 显示 CLI 和 Skill 的本机安装状态；
2. “终端安装”展示一行命令与复制按钮；
3. “交给 Agent”展示包含安装、验证和安全边界的完整提示词与复制按钮；
4. 提醒安装后重启 Agent，并用 `ta status --json` 验证 Bridge。

## 验收

- 离线模拟 GitHub Release，在空用户目录安装并重复安装两次；
- 校验 CLI 可执行、Skill 文件完整、安装过程幂等；
- Swift 单元测试验证 UI 展示内容与本机状态检测；
- 从真实 GitHub Release URL 执行安装，并运行 `ta status --json`。
