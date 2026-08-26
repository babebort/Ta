# 让 Agent 使用拓：Skill、CLI 与 DeepSeek Harness 插件

拓可以作为 Agent 的视觉输入层，在不接管鼠标键盘的前提下完成截图、确定性标注、OCR、AI 识图、翻译和结果交付。三种适配器共用同一个由「拓.app」托管的本机 Bridge，因此 macOS 权限、模型配置和 API Key 只需要在拓里管理一次。

```text
Agent Skill ──> ta CLI ─────────────┐
                                    ├──> Ta Local Bridge ──> 截图 / OCR / AI / 翻译
DeepSeek Harness ──> dsh-ta Plugin ─┘
```

## 1. 前置条件

1. 安装 Ta v1.0.0 或更高版本，并把「拓.app」放入 `/Applications`。
2. 打开拓，在“设置 → 权限”中允许屏幕录制。
3. 打开“设置 → Agent”，确认“允许本机 Agent 调用拓”已开启。
4. 如需 AI 识图、远程 OCR 或翻译，先在拓中配置模型。Agent 无法读取 Keychain 中的 API Key。

普通 Agent 截图使用 ScreenCaptureKit 在后台完成：不弹框选层、不激活拓、不移动鼠标、不发送键盘事件。钉图、交互框选、标注等会改变屏幕状态的能力不属于无感调用。

## 2. 安装 `ta` CLI

从 GitHub Release 下载 `Ta-CLI-1.0.0-macOS-universal.tar.gz`，然后安装到用户目录：

```bash
tar -xzf Ta-CLI-1.0.0-macOS-universal.tar.gz
mkdir -p "$HOME/.local/bin"
install -m 755 ta-cli-1.0.0/bin/ta "$HOME/.local/bin/ta"
export PATH="$HOME/.local/bin:$PATH"
ta status --json
```

压缩包同时支持 Apple Silicon 与 Intel Mac，并包含 `manifest.json`：

```json
{
  "name": "ta",
  "version": "1.0.0",
  "bridgeProtocol": 1,
  "requiresTaApp": ">=1.0.0",
  "minimumMacOS": "14.0",
  "architectures": ["arm64", "x86_64"]
}
```

### 常用命令

```bash
# 检查 Bridge、版本和权限
ta status --json
ta capabilities --json
ta permissions --json

# 不抢焦点地截取当前前台窗口
ta capture frontmost --json

# 列出并截取指定窗口
ta window list --app Safari --json
ta capture window --window-id 1234 --json

# 使用最近截图执行本地 OCR
ta ocr last --json

# AI 识图；会遵循拓中的云端策略
ta analyze last --task general --cloud auto --json

# 文字翻译
ta translate text --text "Hello from Ta" --cloud auto --json

# 保存最近图片到明确的绝对路径
ta save last --output "$PWD/ta-capture.png" --json

# 按 JSON 配方添加箭头、文字等标注；全程本地执行
ta transform last --recipe "$PWD/annotations.json" --output "$PWD/marked.png" --json

# 撤销或重做上一条标注配方
ta transform undo --json
ta transform redo --json
```

Agent 应始终检查 JSON 顶层的 `ok`。图片命令还必须确认 `artifacts` 非空；不能仅根据命令已经发出就宣称成功。

## 3. 安装 Ta Agent Skill

从 Release 下载并解压 `Ta-Agent-Skill-1.0.0.zip`。Skill 不重复实现截图算法，它负责教 Agent 选择正确的 `ta` 命令、验证结果并遵守隐私边界。

Codex 示例：

```bash
unzip Ta-Agent-Skill-1.0.0.zip
mkdir -p "$HOME/.codex/skills"
ditto ta "$HOME/.codex/skills/ta"
```

其他支持 Agent Skills 的工具，把解压后的 `ta/` 放入对应 Skills 目录即可。确保 `ta` CLI 已经位于该 Agent 进程的 `PATH` 中，然后重新启动 Agent。

Skill 的启动检查只有一条命令：

```bash
ta status --json
```

它不会读取 API Key，也不会在没有明确需求时修改剪贴板或保存文件。

## 4. 安装 DeepSeek Harness 原生插件

`dsh-ta` 是原生 Cordis Plugin + Bundle，不是 MCP 配置别名。它需要 DeepSeek Harness `0.1.0-rc.7` 或更高版本，以及 Node.js `22.19.0` 或更高版本。

```bash
dsh plugin --profile web add ./dsh-ta-1.0.0.tgz
dsh --profile web --dump-config
```

配置输出中应出现：

```yaml
- id: ta
  name: dsh-ta
```

插件注册以下 Harness Tools：

| Tool | 用途 |
|------|------|
| `ta_system` | 状态、能力与权限 |
| `ta_list_targets` | 显示器和窗口发现 |
| `ta_capture` | 前台窗口、显示器、窗口 ID 或已知区域截图 |
| `ta_ocr` | OCR 识别 |
| `ta_analyze` | 多模态识图 |
| `ta_translate` | 文字或图片翻译 |
| `ta_deliver` | 保存或按授权写入剪贴板 |

图片结果会导入 Harness Attachment Store。模型上下文收到的是持久附件引用，不是巨大 Base64，也不是可长期访问的 Ta 缓存路径。

### 覆盖插件配置

编辑 `$DSH_HOME/profiles/<profile>/cordis.patch.yml`，用同一个 `id: ta` 覆盖配置。例如强制禁止云端并禁止修改剪贴板：

```yaml
- id: ta
  config:
    defaultCloud: deny
    allowClipboard: false
```

未填写的字段会使用插件默认值：`/Applications/拓.app`、当前用户的 Ta Socket、15 秒超时和自动后台启动。`allowClipboard` 默认是 `false`，只有明确需要 Agent 改写剪贴板时才开启。

卸载：

```bash
dsh plugin --profile web remove dsh-ta
```

## 5. App 内隐私控制与审计

“设置 → Agent”提供：

- Agent 总开关和无感自动截图开关；
- `auto`、`allow`、`deny` 三种默认云端策略；
- 按 Bundle ID 配置的隐私 App 黑名单；
- 是否允许截取拓自身；
- 临时截图缓存清理；
- 最近 100 次调用的本地审计。

设置修改会从下一次请求开始生效，不需要重启 Bridge。审计只保存调用时间、调用方、方法、成功状态、耗时、错误码和是否上云；不保存请求参数、API Key、OCR/翻译正文或图片数据。调用记录权限为当前用户可读写。

## 6. Bridge v1 能力与限制

当前公开 Bridge v1 已实现：

- 状态、能力和权限检查；
- 显示器与窗口发现；
- 显示器、前台窗口、指定窗口和已知坐标区域截图；
- OCR、AI 识图、文字翻译和图片翻译；
- JSON Recipe v1 标注变换、稳定 ID 擦除以及 100 步撤销/重做；
- 复制与保存。

标注变换支持裁剪、矩形、圆形、箭头、画笔、高亮、文字、编号、矩形/笔刷马赛克、模糊、按 ID 擦除和放大镜。它使用左上角像素坐标、只在本机渲染，每次成功调用都会返回新的 PNG Artifact。

拓 App 已有但 Bridge v1 尚未开放的能力包括：交互框选、长截图、钉图、交互式标注编辑器和 AI 美化。Agent 必须先检查 `ta capabilities --json`，不得虚构不存在的命令。后续版本会继续按 `Capture → Understand → Transform → Deliver` 顺序扩展 Bridge，而不是在每个适配器中复制一套实现。

## 7. 故障排查

| 错误 | 处理方法 |
|------|----------|
| `TA_APP_NOT_INSTALLED` | 确认 `/Applications/拓.app` 已安装 |
| `BRIDGE_UNAVAILABLE` | 启动拓后重试一次，不要无限重试 |
| `SCREEN_PERMISSION_REQUIRED` | 在“设置 → 权限”开启屏幕录制 |
| `TARGET_NOT_FOUND` | 重新运行 `ta window list --json` |
| `TARGET_BLOCKED_BY_PRIVACY_POLICY` | 检查 Agent 总开关和隐私 App 黑名单 |
| `CLOUD_UPLOAD_NOT_ALLOWED` | 使用本地 OCR，或在获得许可后调整云端策略 |
| `MODEL_PROFILE_NOT_CONFIGURED` | 在拓中配置对应视觉或翻译模型 |
| `ARTIFACT_EXPIRED` | 重新截图；需要长期保留时使用 `ta save` |

## 8. 从源码生成发布包

```bash
./scripts/package-ta-cli.sh 1.0.0
./scripts/package-ta-skill.sh 1.0.0
TA_NODE_BIN=/path/to/node ./scripts/package-dsh-ta.sh 1.0.0
```

完整发布脚本会同时生成 App DMG/ZIP、CLI、Skill、Harness TGZ 和统一校验文件：

```bash
./scripts/package-release.sh 1.0.0
```

最终文件位于 `artifacts/release/v1.0.0/`，并全部写入 `SHA256SUMS.txt`。
