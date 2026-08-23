# AI 截图软件市场、用户痛点与产品机会调研

> 调研日期：2026-08-22
> 调研范围：桌面截图、OCR、截图后 AI、截图管理、截图美化，以及录屏/语音输入产品的 UI 参考
> 目标：为一款“快捷键截图后，立即识别内容并复制到剪贴板”的 AI 截图软件确定产品切入口与后续路线

## 一、结论先行

这个方向成立，但“截图 + OCR”本身已经不是空白市场。TextSniper、PixPin、CleanShot X、Windows Snipping Tool、NormCap 等都能完成不同程度的截图取字；ScreenAI、SnippedAI、ShotSolve 等新产品已经在尝试“截图后直接问 AI”。真正的机会不在于给传统截图工具简单加一个聊天框，而在于把下面这条链路做到明显更快、更稳、更可信：

**看到内容 → 一个快捷键 → 框选 → 自动判断内容类型 → 得到可直接粘贴的正确结果。**

最值得占领的产品心智是：

> **截完即得。默认本地处理，复杂内容才调用 AI。**

建议首版不要追求成为另一个 ShareX，而是先把“截图取内容”做到极致：

1. 默认用本地 OCR，截图不出设备，速度快且无调用成本。
2. 自动识别普通文本、代码、表格、公式、二维码等内容类型。
3. 普通文字直接复制；复杂版式可选择复制为 Markdown、表格或 LaTeX。
4. 识别失败或低置信度时，才使用用户配置的视觉模型做纠错。
5. 用一个很轻的结果条告诉用户“已复制什么”，允许立即编辑、重试、翻译或问 AI。

长期壁垒不应只是模型接入，而应是：跨应用稳定截图、低延迟、本地优先、结构化内容恢复、隐私防泄漏，以及逐步积累的截图工作流。

## 二、研究方法与限制

本次采用的是方向性定性调研，不是统计学意义上的市场调查：

- 官方资料：产品官网、帮助文档、定价页、官方 GitHub 仓库。
- 开源信号：GitHub Stars、Forks、最近更新时间、Issues 和 Discussions。
- 用户讨论：Reddit 真实使用反馈、产品发布帖下的反对意见和功能请求。
- X：公开索引结果更适合发现具体用法和产品展示，痛点讨论的可检索样本较少，因此不把 X 作为痛点频次的主要证据。
- 竞品星标数据取自 GitHub API，快照时间为 2026-08-22；这些数字会继续变化。

本文中的“高频”代表多个独立来源重复出现的方向性信号，不等同于严格的提及次数统计。下一步仍需通过 20 名以上目标用户访谈和真实任务测试验证。

## 三、市场版图

### 3.1 四类产品正在汇合

| 类别 | 代表产品 | 当前优势 | 当前缺口 |
|---|---|---|---|
| 系统原生截图 | Windows Snipping Tool、Windows Click to Do、Apple Visual Intelligence | 零安装、权限和系统能力强、本地模型 | 受系统/硬件限制，跨平台差，可配置性和专业工作流有限 |
| 专业截图工具 | CleanShot X、Shottr、PixPin、ShareX、Flameshot | 截图、标注、滚动截图和导出成熟 | AI 往往是附加功能；部分产品臃肿或设置复杂 |
| OCR/取字工具 | TextSniper、NormCap、PowerToys Text Extractor | 路径极短，解决明确刚需 | 通常只返回纯文本，表格、公式、代码和语义处理不足 |
| AI 原生屏幕助手 | ScreenAI、SnippedAI、ShotSolve、ChillShot AI、AIPointer | 截图后提问、多模型、BYOK | 多数较新，成熟度、稳定性、隐私解释和留存尚未被充分验证 |

这四类产品最终都在争夺同一个入口：**用户对屏幕上现有内容采取下一步动作的入口**。微软 Click to Do 已经把文本复制、摘要、改写、表格提取、背景移除、视觉搜索和问 Copilot 放到屏幕内容之上；Apple Visual Intelligence 也把截图后的搜索、提问、摘要、朗读和添加日历事件放在同一层。这说明“截图软件”正在向“屏幕内容操作系统”演化。[Microsoft Click to Do](https://learn.microsoft.com/en-us/windows/ai/cards/click-to-do-application-card) · [Apple Visual Intelligence](https://support.apple.com/guide/iphone/use-visual-intelligence-iph12eb1545e/26/ios/26)

### 3.2 直接竞品与可借鉴点

| 产品 | 平台/定位 | 关键能力 | 对本项目的启发 |
|---|---|---|---|
| [TextSniper](https://textsniper.app/) | macOS，专用 OCR | `Cmd+Shift+2` 框选后直接把识别文本复制到剪贴板；单机许可官网价 $7.99 | 证明“快捷键—框选—剪贴板”是一个可以单独付费的极简价值点 |
| [PixPin](https://pixpin.com/docs/start/quick-start) | Windows/macOS，截图全家桶 | 本地 OCR、贴图、滚动截图、GIF/视频；会员提供翻译、表格和 LaTeX 识别 | 中文场景覆盖强；内容类型识别值得借鉴，但功能入口需要分层 |
| [CleanShot X](https://cleanshot.com/pricing) | macOS，成熟商业截图工具 | OCR、滚动截图、录屏、云分享；基础版 $29 买断并含一年更新 | 快速截图浮层和完整编辑器分离；成熟商业定价基准 |
| [Shottr](https://shottr.cc/) | macOS，轻量原生 | 小体积、快速截图、OCR、滚动截图、漂亮背景、像素工具和对象移除 | “轻、快、专业感”本身就是差异化；不要让 AI 增加启动负担 |
| [Xnapper](https://xnapper.com/) | macOS，截图美化 | 自动平衡、自动背景、敏感信息遮挡、OCR、社交媒体比例、预设 | AI 美化应以“一键得到可分享结果”为目标，不应变成复杂图片编辑器 |
| [ScreenAI](https://getscreenai.com/) | 跨平台 AI 截图助手 | 多模型、OCR、问 AI、滚动截图、历史、自动遮挡、BYOK/Ollama | 功能愿景最接近本项目；但其 [GitHub 仓库](https://github.com/Nono81/ScreenAI) 在调研日为 0 Star、无正式 Release 信号，成熟度需要实际测试，不能只看官网功能表 |
| [SnippedAI](https://snippedai.com/) | macOS 15.2+ 测试版 | 框选后提问，OpenAI/Claude/Gemini/Groq/本地模型切换，强调简洁答案 | 多供应商和模型选择可以存在，但应藏在设置和轻量的模型切换器中 |
| [ShotSolve](https://shotsolve.com/) | macOS，单一截图问答 | 免费、原生、BYOK，截图后询问 GPT-4o | 证明最小 AI 工作流可以非常简单；支持自定义 API 地址是社区明确提出的需求之一 |
| [ChillShot AI](https://www.chilltool.com/) | Windows/macOS，AI 全家桶 | 滚动截图、OCR、视觉问答、图片翻译、对话式图片编辑 | 是未来功能池参考，但不宜首版一次性复制全部能力 |
| [Windows Snipping Tool](https://support.microsoft.com/en-us/windows/apps/use-snipping-tool-to-capture-screenshots) | Windows 原生 | OCR、复制全部文字、本地识别、快速遮挡邮箱/电话；Copilot+ PC 上有 Perfect Screenshot | 系统原生已把普通 OCR 变成基础能力，第三方必须在结构化识别、速度和跨平台上更强 |

### 3.3 开源产品：谁“最好用”不能只给一个答案

按 2026-08-22 的 GitHub 采用度、活跃度和功能匹配度，建议这样理解“最好用”：

| 场景 | 当前更值得研究的开源项目 | 采用度快照 | 判断 |
|---|---|---:|---|
| Windows 全能截图 | [ShareX](https://github.com/ShareX/ShareX) | 39,236 Stars / 3,900 Forks | 最成熟、自动化能力强；也是“功能太多、界面复杂”反馈最集中的样本 |
| 跨平台基础截图与标注 | [Flameshot](https://github.com/flameshot-org/flameshot) | 30,663 Stars / 1,997 Forks | 社区大、标注流程成熟；Wayland、剪贴板、多显示器仍有长期兼容问题 |
| 跨平台 OCR/翻译工作流 | [eSearch](https://github.com/xushengfeng/eSearch) | 7,001 Stars / 505 Forks | 截屏、离线 OCR、搜索、翻译、贴图、录屏、滚动截图和自定义 AI 翻译较完整，中文用户尤其值得研究 |
| 专注截图取字 | [NormCap](https://github.com/dynobo/normcap) | 2,690 Stars / 124 Forks | 与本项目 MVP 最接近：捕获的是“信息而不是图片”；适合作为交互和 OCR 管线参考 |
| 原生 macOS 全能截图 | [macshot](https://github.com/sw33tLie/macshot) | 3,031 Stars / 182 Forks | 2026 年快速增长，原生 Swift/AppKit，包含 OCR、翻译、滚动截图、自动隐私遮挡和美化 |
| Windows 新式截图与语义历史 | [Yoink](https://github.com/jasperdevs/yoink) | 272 Stars / 16 Forks | OCR、100+ 语言、滚动截图、贴纸抠图、OCR/语义历史搜索，功能方向很新；仍属早期项目 |
| 本地截图语义检索 | [LiveRecall](https://github.com/VedankPurohit/LiveRecall) | 165 Stars / 5 Forks | 本地 OCR、图像/文本向量、混合搜索与加密，适合研究“截图记忆库”而非即时截图 |

**结论：**

- 如果问“最成熟的开源截图工具”，Windows 是 ShareX，跨平台是 Flameshot。
- 如果问“最贴近截图即取字”，NormCap 是最聚焦的参考，eSearch 的能力更完整。
- 如果问“最好用的开源 AI 截图工具”，目前还没有形成公认赢家。ScreenAI 愿景完整但仓库很新；Yoink、LiveRecall 分别在语义历史和本地记忆上有亮点；eSearch 在 OCR + 翻译 + AI 接口方面的现实采用度更高。
- 这反而说明市场存在窗口：**成熟截图工具缺少自然的 AI 路径，而 AI 截图新品还没有建立稳定性和信任。**

## 四、真实用户痛点

### 4.1 痛点优先级

| 优先级 | 痛点 | 公开证据 | 产品机会 |
|---|---|---|---|
| P0 | 截图后还要打开图片、裁剪、OCR、复制，工作流打断 | 用户直接描述“截图 → 打开另一应用 → 裁剪 → OCR → 复制 → 搜索”的多步流程；也有人要求 OCR 后无需点击直接输出文字。[Scani 讨论](https://www.reddit.com/r/macapps/comments/1thr2eb/scani_an_instantly_capture_text_from_images_and/) · [无按钮 OCR 需求](https://www.reddit.com/r/computervision/comments/12n31fw/help_im_doing_manual_data_entry_off_receipts_and/) | 首版核心就是零中转、自动复制；所有附加 UI 都不得阻塞粘贴 |
| P0 | OCR 能读字，但结构丢失或顺序错误 | CJK、代码、LaTeX、表格、多行顺序都是持续问题；用户希望从截图粘贴到 Word/邮件时保留真正的表格。[FrameOCR 讨论](https://www.reddit.com/r/macapps/comments/1nfa1n0/frameocr_a_simple_powerful_ocr_tool_for_macos_30/) · [表格复制需求](https://www.reddit.com/r/macapps/comments/1uxgnlz/app_request_table_capture/) · [多行顺序问题](https://github.com/thanhkeke97/RSTGameTranslation/issues/51) | 自动内容分类；输出纯文本/Markdown/表格/LaTeX；低置信度复核 |
| P0 | 剪贴板“不可靠”或粘贴目标不兼容 | Flameshot、NormCap 在 Wayland/快捷键场景都有复制失败案例；ShareX 用户还要求一次复制图片、文件和路径等多种格式。[Flameshot #4118](https://github.com/flameshot-org/flameshot/issues/4118) · [NormCap #422](https://github.com/dynobo/normcap/issues/422) · [ShareX #8501](https://github.com/ShareX/ShareX/issues/8501) | 把剪贴板当核心系统做：多格式写入、粘贴目标兼容测试、失败可见且可重试 |
| P0 | 隐私信息被截图并发到 AI/群聊 | API Key、邮箱、电话、客户信息可能在分享或问 AI 时泄露；录屏用户也在请求自动遮挡敏感信息。[ClipScrub 讨论](https://www.reddit.com/r/macapps/comments/1vrrfe9/clipscrub_strips_names_and_ids_out_of_screenshots/) · [Screen Studio 请求](https://hub.screen.studio/en) | 云端前本地检测 PII；展示“将发送的区域”；一键遮挡；本地模式清晰可见 |
| P1 | 长截图容易拼接失败 | 静态侧栏、输入框、粘性标题、无限滚动、懒加载、GIF/视频会造成重复、缺口或停止。[ShareX #7334](https://github.com/ShareX/ShareX/issues/7334) · [Shottr 使用警告](https://shottr.cc/kb/scrollingcapture) · [粘性标题/懒加载讨论](https://www.reddit.com/r/chrome_extensions/comments/1u5p2cc/sick_of_broken_screenshots_on_infinite_scroll/) | 长截图不能只做像素拼接：检测固定元素、懒加载、动态区域；允许暂停、手动校正和分页导出 |
| P1 | 功能全但太臃肿，简单截图反而难 | ShareX 被形容为“像开航天飞机”，新界面也被批评按钮过大、流程变慢；但另一部分用户又依赖它的自动化能力。[界面讨论](https://www.reddit.com/r/software/comments/1cym5pc/what_you_use_for_screenshot_annotation_tools/) · [ShareX 20 反馈](https://www.reddit.com/r/sharex/comments/1t2lpxs/newest_version_of_sharex_is_a_bust_so_far/) | 用渐进披露解决：默认只显示 3–5 个高频动作，高级能力通过命令面板和设置开启 |
| P1 | 截图越来越多，之后找不到 | 用户用截图当临时记忆，却面对桌面/相册堆积；新的截图管理产品普遍以 OCR 和语义搜索为卖点。[Shard 讨论](https://www.reddit.com/r/apps/comments/1rztpo6/i_got_tired_of_scrolling_through_hundreds_of/) · [ScreenBrain 讨论](https://www.reddit.com/r/opensource/comments/1sd4f0r/open_sourced_a_macos_screenshot_manager_because/) | 可选的本地历史；OCR 自动索引；按“我记得的意思”搜索，而不只按文件名 |
| P1 | HDR、缩放、多显示器导致颜色或坐标错误 | ShareX HDR 请求获得大量反应；Flameshot 也有发白问题，多显示器/DPI 会让编辑器错位。[ShareX #6688](https://github.com/ShareX/ShareX/issues/6688) · [Flameshot #3151](https://github.com/flameshot-org/flameshot/issues/3151) · [ShareX #4007](https://github.com/ShareX/ShareX/issues/4007) | 把 HDR→SDR 色调映射、混合 DPI 和多屏布局加入早期兼容测试矩阵 |
| P1 | 权限、全局快捷键和系统冲突 | Wayland 门户权限、macOS 屏幕录制权限、系统占用 Print Screen 都会让“快捷键没反应”。[Flameshot #4463](https://github.com/flameshot-org/flameshot/issues/4463) · [Flameshot v14 说明](https://github.com/flameshot-org/flameshot/discussions/4624) | 权限向导必须能检测当前状态、解释原因并一键跳转系统设置；提供快捷键冲突检测 |
| P2 | 截图分享不够漂亮，还要进入设计工具 | 用户希望自动背景、留白、比例、阴影、窗口框和品牌预设；Xnapper、Pika、Shottr 已验证这类需求。[Xnapper](https://xnapper.com/) · [Pika](https://pika.style/) · [Shottr](https://shottr.cc/) | 提供“一键美化预设”，优先参数化、可逆的布局，不先做复杂生成式图片编辑 |

### 4.2 两个看似矛盾、实际必须同时满足的需求

公开讨论中反复出现两种用户：

1. **极简用户**：只想按快捷键、框选、粘贴；讨厌后台常驻、弹窗和几十个工具。
2. **高级用户**：需要滚动截图、自动命名、上传、工作流、表格、公式、录屏和自托管。

解决方法不是选一边，而是把产品设计成两层：

- 第一层是“无界面工作流”：快捷键后直接得到结果。
- 第二层是“可召唤工作台”：用户需要编辑、问 AI、批处理或找历史时才出现。

## 五、建议的产品定义

### 5.1 核心 Jobs-to-be-Done

> 当屏幕上出现无法直接复制或难以整理的内容时，我想用一次框选得到可粘贴、可编辑、格式正确的结果，这样我可以继续当前工作，而不是切换到多个应用。

第一目标用户建议聚焦三类：

- 开发者：错误信息、终端输出、代码、UI 问题、二维码。
- 内容创作者/研究者：文章段落、字幕、图表、引用、翻译、社交图片。
- 办公用户：表格、票据、会议截图、聊天记录、敏感信息遮挡。

### 5.2 MVP：先把截图取内容做到极致

#### 必须有

1. 全局快捷键：区域、窗口、全屏三种捕获。
2. 截图完成后自动 OCR，并立即把文本复制到剪贴板。
3. 中英混排识别；自动保留段落、换行和基本标点。
4. 轻量结果条：显示“已复制 86 个字”，可展开编辑、重新识别或复制图片。
5. 默认本地 OCR；设置里清楚标注哪些操作会把图片发送到云模型。
6. AI 供应商配置：本地模型、OpenAI-compatible、自定义 Base URL、Anthropic、Gemini、Ollama。
7. API Key 存入系统安全存储；支持“测试连接”，日志中永不显示完整 Key。
8. 失败处理：无文字时保留图片到剪贴板；低置信度时提示用户选择“视觉模型增强”。
9. 权限检查、快捷键冲突检测、多屏和 Retina/高 DPI 基础兼容。

#### MVP 不建议做

- 完整录屏编辑器。
- 团队云盘、评论和分享分析。
- 自动连续截屏/全时屏幕记忆。
- 复杂图像生成和 Photoshop 式多层编辑。
- 一开始就支持十几个模型供应商。

这些功能会显著放大隐私、性能、兼容性和 UI 复杂度，却不会验证最核心的“截图即得内容”。

### 5.3 第二阶段：让 OCR 结果真正可用

- **代码模式**：保留缩进、符号、行号可选移除，复制 Markdown code block。
- **表格模式**：输出 TSV、Markdown 表格、HTML 表格；粘贴前提供单元格校对。
- **公式模式**：输出 LaTeX，并保留原图对照。
- **翻译模式**：截图后直接把目标语言文本复制到剪贴板，可选“保留原文 + 译文”。
- **清理文本**：合并错误换行、去页眉页脚、修正常见 OCR 错字。
- **智能动作**：检测 URL、邮箱、日期、地址、二维码后提供打开、写邮件、建日程等动作。
- **隐私守门**：识别邮箱、电话、IP、API Key、银行卡号，并在云端分析/分享前要求确认或自动遮挡。

### 5.4 第三阶段：AI 截图工作台

- 对截图提问：解释报错、总结图表、评价设计、生成 Alt Text、提取待办。
- 连续上下文：多张截图组成一个问题，不必反复描述背景。
- 本地历史和语义搜索：按 OCR 文本、应用、时间、视觉语义检索。
- AI 自动命名和归档，但每次批量更改必须可撤销。
- 对比模式：两个截图自动识别视觉差异、文案差异和 UI 回归。
- 智能长截图：识别固定标题、聊天输入框、动态内容，并提供拼接质量检查。

### 5.5 截图美化与 AI 画图：正确的进入顺序

截图美化有需求，但建议按以下顺序进入：

1. **参数化美化**：背景、渐变、边距、圆角、阴影、窗口框、设备框、社交比例。
2. **内容感知布局**：自动裁切、自动留白、主体居中、根据截图主色生成背景。
3. **智能隐私处理**：可恢复的遮挡区域、智能擦除、替换示例数据。
4. **生成式扩图/换背景**：用于海报和社交媒体，而不是默认截图流程。
5. **从截图生成视觉资产**：生成产品功能卡、教程步骤图、对比图或 App Store 截图组。

微软已经把背景模糊、对象擦除、背景移除和表格提取放到屏幕内容动作中；这证明 AI 图像动作是合理扩展，但它们应是上下文动作，不应阻塞截图本身。[Click to Do 能力说明](https://learn.microsoft.com/en-us/windows/ai/cards/click-to-do-application-card)

## 六、UI 与交互设计建议

### 6.1 应该有三个界面，而不是一个“大而全”窗口

#### A. 捕获层：极简、瞬时

- 屏幕冻结，鼠标框选。
- 只显示尺寸、放大镜和 4 个以内常用动作。
- 默认松开鼠标即完成，不要求再点“确认”。
- Space 在区域/窗口捕获间切换，Esc 退出。
- 标注工具放到二级入口，避免遮挡内容。

#### B. 结果条：像 Typeless 一样留在当前上下文

Typeless 的核心不是一个漂亮主窗口，而是“在任何应用中按快捷键，处理后直接进入当前输入位置”，并通过很轻的状态反馈让用户知道系统正在听、正在处理、已经完成。[Typeless 安装与使用流程](https://www.typeless.com/help/installation-and-setup)

可借鉴为：

```text
┌────────────────────────────────────────────────────────┐
│ ✓ 已复制文本  86 字    [编辑] [翻译] [问 AI] [···]   │
└────────────────────────────────────────────────────────┘
```

- 结果条靠近截图区域或屏幕顶部，不抢当前应用焦点。
- 1–2 秒后自动淡出，但鼠标悬停时保留。
- 明确显示结果类型：文本 / 代码 / 表格 / 公式 / 二维码。
- 云端调用时显示供应商图标与“将发送此区域”，让数据流可感知。

#### C. 主工作台：只处理历史、复杂编辑和设置

```text
┌──────────────┬───────────────────────────────────────┐
│ 最近截图     │  预览 / OCR 原文 / AI 对话            │
│ 收藏         │                                       │
│ 智能分类     │  [原图] [文本] [表格] [代码]           │
│              │                                       │
│ 设置         │  右侧仅显示当前工具的参数              │
└──────────────┴───────────────────────────────────────┘
```

### 6.2 设置页信息架构

建议左侧导航：

1. 常规：开机启动、语言、默认行为、保存位置。
2. 快捷键：截图取字、截图图片、截图问 AI、滚动截图、贴图。
3. OCR 与 AI：OCR 引擎、语言、供应商、模型、提示词和回退规则。
4. 剪贴板：默认输出格式、是否同时写入图片/文件/文本、历史保留。
5. 隐私：本地模式、云端发送确认、自动遮挡、排除应用、数据保留。
6. 外观：主题、结果条位置、标注颜色、截图美化预设。
7. 高级：自定义 API Base URL、代理、超时、调试日志、导入/导出配置。

模型配置卡建议包含：

```text
供应商        OpenAI-compatible           [已连接]
Base URL      https://...
API Key       sk-•••••••••••••••          [更新]
视觉模型      [下拉选择]
文本模型      [下拉选择]
用途          ☑ OCR 纠错  ☑ 翻译  ☑ 截图问答
数据提示      仅执行勾选的云端动作时上传选区
                                      [测试连接]
```

不要让用户在第一次启动时先理解模型。首次启动只需：授予截图权限 → 试一次截图取字 → 成功粘贴。API Key 应在用户第一次使用云端能力时再配置。

### 6.3 可借鉴的 UI 设计原则

| 产品 | 值得借鉴 | 不应照搬 |
|---|---|---|
| Typeless | 后台常驻、快捷键触发、在当前上下文完成、轻量状态反馈 | 登录和权限步骤过多会损害首次体验；AI 截图应先展示本地功能 |
| CleanShot X / PixPin | 截图浮层与完整编辑器分离；贴图作为低成本临时工作区 | 不要把所有标注按钮默认堆满选区周围 |
| Screen Studio | “有观点的默认值”；自动完成繁琐美化，同时允许时间线微调。[官方功能](https://screen.studio/) | 截图软件不需要首版复制视频时间线复杂度 |
| Tella | 左工具栏 + 当前工具参数面板，复杂功能按任务分组；自动布局后仍可人工调整。[编辑器说明](https://www.tella.tv/help/editing/edit-a-video) | 不要把云端项目管理放到核心截图路径 |
| Xnapper | 自动平衡、主色背景、社交比例和预设让用户两秒出图 | 美化不能取代准确截图和可靠剪贴板 |
| ShareX | 高级用户工作流和自动化极强 | 不要把任务、动作、上传器和几十项设置直接暴露给新用户 |

## 七、差异化定位

### 7.1 一句话定位

> **一个把屏幕内容瞬间变成可粘贴信息的本地优先 AI 截图工具。**

### 7.2 与竞品的差异

| 维度 | 传统截图工具 | 纯 OCR 工具 | AI 聊天截图工具 | 建议产品 |
|---|---|---|---|---|
| 默认结果 | 图片 | 纯文本 | AI 回答 | 可直接粘贴的正确结构 |
| 默认处理 | 本地 | 本地 | 云端居多 | 本地 OCR，低置信度才上 AI |
| 复杂内容 | 依赖编辑器 | 结构丢失 | 能理解但不可控 | 文本/代码/表格/公式专用输出 |
| 交互 | 工具栏和窗口 | 极简 | 提问框 | 自动完成 + 可召唤动作 |
| 隐私 | 各产品不同 | 通常较好 | 易上传整张图 | 上传前本地检测、裁剪和遮挡 |
| 历史 | 文件列表 | 通常没有 | 对话历史 | 可选、本地、OCR + 语义搜索 |

### 7.3 不要把“支持很多模型”当作主要卖点

用户购买的不是模型下拉框，而是一个可靠结果。多模型应该承担三件事：

- 回退：本地 OCR 不好时自动增强。
- 专长：表格、公式、代码、翻译选择更合适的模型。
- 控制：用户可选择本地、BYOK 或产品托管服务。

主界面只需要显示当前模式，不需要持续暴露供应商、Token、温度等技术参数。

## 八、建议的开发优先级

| 阶段 | 目标 | 功能 | 验收信号 |
|---|---|---|---|
| 第 0 阶段 | 验证核心链路 | 区域截图、本地中英 OCR、自动复制、结果条、权限向导 | 10 名用户在无指导下完成“截图并粘贴”；大多数任务不打开主窗口 |
| 第 1 阶段 | 解决硬内容 | 代码、表格、公式、二维码、翻译、AI 纠错、自定义 API | 用户不再需要把截图转交给第二个 OCR/AI 工具 |
| 第 2 阶段 | 建立日常留存 | 滚动截图、贴图、本地历史、语义搜索、隐私遮挡 | 用户一周内重复使用并能找回旧截图 |
| 第 3 阶段 | 扩展创作价值 | 一键美化、模板、智能擦除、扩图、教程卡片 | 创作者可直接输出可发布素材，不再进额外设计工具 |
| 独立路线 | 专业录屏 | 快速录屏、自动缩放、字幕、剪辑 | 只有当截图用户明确需要时再做，避免拖累核心性能 |

建议的体验性能目标：

- 按下快捷键后，捕获层体感上立即出现。
- 清晰的短文本，本地 OCR 在 1 秒内完成并复制。
- 云端视觉增强给出可见进度，超过 3 秒可取消。
- 常驻内存和安装包体积要持续监控；“轻量”必须是测试指标而不是宣传词。

## 九、下一轮用户验证

### 9.1 先访谈 20 人，而不是先问“你会不会用”

每类至少 5–7 人：开发者、内容创作者/研究者、办公用户。只问过去发生过的真实行为：

1. 你上一次从屏幕里复制无法选择的文字是什么时候？
2. 当时用了哪些软件和步骤？在哪一步最烦？
3. 最近一次长截图为什么失败？最后怎么解决？
4. 你有没有截图后忘记遮挡信息，或者不敢上传 AI 的经历？
5. 你如何寻找一个月前的截图？找不到时会怎么做？
6. 哪些截图必须保留原格式：表格、代码、公式、聊天、票据？
7. 你现在为哪些截图/OCR/录屏工具付费？真正每天使用的功能是哪几个？

### 9.2 可直接执行的可用性测试

给参与者五个真实任务，不讲解产品：

1. 从视频字幕里复制一句中英混排文本。
2. 从报错窗口复制代码，粘到编辑器并保持格式。
3. 从图片表格复制三行数据到 Excel/Numbers。
4. 截一张含邮箱和 API Key 的图，安全发给同事。
5. 找回一周前“蓝色图表”的截图。

记录：完成时间、点击次数、是否切换应用、识别后人工修改次数、是否理解数据去了哪里。

### 9.3 第一批应验证的关键假设

- 用户是否真的愿意让截图工具默认复制“文字”而不是“图片”。
- 一次快捷键是否需要根据不同任务区分：截图图片、截图取字、截图问 AI。
- 本地 OCR 的准确率是否足以覆盖 80% 日常任务。
- 用户是否愿意自己配置 API Key，还是更愿意购买内置额度。
- 历史功能应默认关闭、短期保留，还是默认建立本地索引。
- 截图美化是核心购买理由，还是只对创作者子群体重要。

## 十、最终建议

最适合的切入方式不是“做一个带 AI 的全能截图软件”，而是：

> **先做一把最快的屏幕取字刀，再让它逐渐理解表格、代码、公式、图片和任务。**

首版只需要让用户形成一个条件反射：**屏幕上有拿不走的内容，就按这个快捷键。**

当这个入口稳定后，再增加长截图、隐私处理、语义历史和一键美化。录屏和完整 AI 图像生成应作为后续独立能力，而不是首版包袱。当前市场最大空档，是一款同时具备 TextSniper 的极简、PixPin 的中文/结构化能力、CleanShot X 的完成度，以及 Typeless 式低打扰交互的产品。

## 附录：核心来源索引

### 官方与开源

- [Microsoft：Click to Do 能力与限制](https://learn.microsoft.com/en-us/windows/ai/cards/click-to-do-application-card)
- [Microsoft：Snipping Tool OCR 与快速遮挡](https://support.microsoft.com/en-us/windows/apps/use-snipping-tool-to-capture-screenshots)
- [Apple：Visual Intelligence 对屏幕截图的动作](https://support.apple.com/guide/iphone/use-visual-intelligence-iph12eb1545e/26/ios/26)
- [ShareX GitHub](https://github.com/ShareX/ShareX)
- [Flameshot GitHub](https://github.com/flameshot-org/flameshot)
- [eSearch GitHub](https://github.com/xushengfeng/eSearch)
- [NormCap GitHub](https://github.com/dynobo/normcap)
- [macshot GitHub](https://github.com/sw33tLie/macshot)
- [Yoink GitHub](https://github.com/jasperdevs/yoink)
- [LiveRecall GitHub](https://github.com/VedankPurohit/LiveRecall)
- [ScreenAI GitHub](https://github.com/Nono81/ScreenAI)
- [Cap 开源录屏项目](https://github.com/CapSoftware/Cap)

### 商业与新兴产品

- [TextSniper](https://textsniper.app/)
- [PixPin](https://pixpin.com/)
- [CleanShot X](https://cleanshot.com/)
- [Shottr](https://shottr.cc/)
- [Xnapper](https://xnapper.com/)
- [ScreenAI](https://getscreenai.com/)
- [SnippedAI](https://snippedai.com/)
- [ShotSolve](https://shotsolve.com/)
- [ChillShot AI](https://www.chilltool.com/)
- [Screen Studio](https://screen.studio/)
- [Tella](https://www.tella.com/features)
- [Typeless](https://www.typeless.com/help/installation-and-setup)

### 用户痛点与 Issues

- [ShareX：滚动截图控制与失败条件](https://github.com/ShareX/ShareX/issues/7334)
- [ShareX：多格式剪贴板](https://github.com/ShareX/ShareX/issues/8501)
- [ShareX：HDR 支持](https://github.com/ShareX/ShareX/issues/6688)
- [Flameshot：快捷截图流程被多显示器选择打断](https://github.com/flameshot-org/flameshot/issues/4780)
- [Flameshot：剪贴板复制失败](https://github.com/flameshot-org/flameshot/issues/4118)
- [Flameshot：Wayland 权限与截图失败](https://github.com/flameshot-org/flameshot/issues/4463)
- [NormCap：快捷键启动后无法复制](https://github.com/dynobo/normcap/issues/422)
- [Reddit：ShareX 功能过多与界面复杂](https://www.reddit.com/r/software/comments/1cym5pc/what_you_use_for_screenshot_annotation_tools/)
- [Reddit：OCR 对代码、中文、日文和 LaTeX 的不足](https://www.reddit.com/r/macapps/comments/1nfa1n0/frameocr_a_simple_powerful_ocr_tool_for_macos_30/)
- [Reddit：截图历史与语义搜索需求](https://www.reddit.com/r/apps/comments/1rztpo6/i_got_tired_of_scrolling_through_hundreds_of/)
