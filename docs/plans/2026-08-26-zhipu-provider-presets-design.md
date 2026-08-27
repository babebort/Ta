# 智谱模型渠道与服务商图标设计

## 目标

在现有 780 × 600 的三步 AI 模型向导中增加两个独立入口，并把用户提供的真实服务商图标用于服务商列表与配置摘要：

- 智谱 API：通用开放平台额度，支持视觉与文字模型。
- 智谱 Coding Plan：订阅套餐专属端点，仅配置官方直连支持的文字模型。
- 自定义：作为明确的服务商卡片保留在列表末尾，不再藏在文字链接中。

## 预设参数

| 渠道 | 协议 | Base URL | 视觉模型 | 文字模型 |
|---|---|---|---|---|
| 智谱 API | OpenAI Compatible | `https://open.bigmodel.cn/api/paas/v4` | `glm-5v-turbo` | `glm-5.2` |
| 智谱 Coding Plan | OpenAI Compatible | `https://open.bigmodel.cn/api/coding/paas/v4` | 不支持直接图片输入 | `glm-5.2` |

Coding Plan 官方要求在支持的 Coding Agent 工具中使用，直连模型不提供截图视觉输入。拓允许保存并测试它的文字模型配置，但不会把它列入 AI 识图或截图翻译可选模型，界面必须明确提示这一限制。

## 图标

从用户提供的目录导入 DeepSeek、OpenAI、Claude、Gemini、OpenRouter 图标。智谱 API 与智谱 Coding Plan 共用同一枚 Z.ai/智谱图标。Azure 与自定义继续使用系统图标。

图标复制到 `Resources/Brand/Providers`，构建脚本把该目录复制进 App Bundle。SwiftUI 通过 `Bundle.main` 读取真实 PNG；开发或测试环境缺少资源时回退到 SF Symbols。

## 交互

- 服务商列表改为可滚动区域，以容纳 9 个入口并保持窗口尺寸不变。
- 选择智谱 API 后自动填写通用端点、视觉模型与文字模型。
- 选择智谱 Coding Plan 后只显示文字模型字段和限制提示。
- Coding Plan 的“测试并保存”只测试文字请求；成功后仍提示它不能用于截图识图与截图翻译。
- 自定义渠道进入第二步后展开高级设置，便于小白直接找到服务地址和协议。

## 验收

- 预设顺序、端点、模型与视觉能力由单元测试覆盖。
- 图标资源必须存在于最终 `拓.app`。
- 在真实 App 中验证智谱两个入口、自定义入口、图标和自动填充内容。

## 视觉调整（2026-08-26）

- 智谱 API 与智谱 Coding Plan 固定排在服务商列表最前，并显示“推荐”。
- OpenAI、Claude、智谱图标统一使用透明底 PNG，只保留品牌图形，不显示素材自带的白框、黑边或不透明蒙层。
- DeepSeek 继续保留“推荐”标记。
