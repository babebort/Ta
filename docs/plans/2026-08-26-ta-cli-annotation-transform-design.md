# Ta CLI 标注变换设计

## 目标

让 Agent 能通过 `ta transform` 对截图或本地图片执行确定性的无界面标注，并支持裁剪、矩形、圆形、箭头、画笔、高亮、文字、编号、马赛克、模糊、橡皮、放大镜以及撤销/重做。

## 命令契约

```bash
ta transform last --recipe annotations.json --output marked.png --json
ta transform ./input.png --recipe annotations.json --output marked.png --json
ta transform undo --output previous.png --json
ta transform redo --output restored.png --json
```

`--recipe` 指向 UTF-8 JSON 文件。输入省略或为 `last` 时使用 Bridge 中最近的图片；显式图片路径会开启新的编辑会话。输出是新的 PNG Artifact，`--output` 仍沿用 CLI 的持久化交付流程。

## 配方模型

配方顶层为 `{"version":1,"operations":[...]}`。坐标以当前画布左上角为原点、单位为源图片像素。裁剪最多出现一次，且必须是第一项；裁剪后的操作使用裁剪后画布坐标。

每个可见标注必须有唯一 `id`。支持的 operation：

- `crop`：`rect`。
- `rectangle`、`ellipse`：`rect`、颜色、线宽、虚线。
- `arrow`：起点、终点、颜色、线宽、虚线。
- `pen`、`highlighter`：点数组、颜色、线宽；高亮默认带透明度。
- `text`：原点、文本、颜色、字号。
- `number`：中心、数字、颜色、直径。
- `mosaic`：矩形模式或笔刷点数组。
- `blur`：矩形区域。
- `magnify`：矩形区域和倍率。
- `eraser`：按稳定 ID 删除此前标注；不模拟鼠标命中。

颜色接受 `#RRGGBB` 或 `#RRGGBBAA`。非法类型、空路径、重复 ID、无效尺寸、找不到的擦除目标均返回结构化 `INVALID_REQUEST`。

## 编辑会话和历史

Bridge 保存当前编辑会话：原图、裁剪区域、按顺序排列的矢量标注，以及最多 100 个撤销/重做快照。一次成功的 `transform` 请求形成一个历史步骤；一个配方中的多项操作作为原子事务全部成功或全部不生效。

`undo` 和 `redo` 恢复完整矢量快照并重新渲染图片。新的变换会清空 redo 栈。每次普通截图或显式输入新图片时重置编辑会话。

## 渲染和安全

无界面渲染器复用当前 macOS 标注编辑器的视觉语义：Core Graphics/AppKit 绘制形状和文字，Core Image 生成马赛克与模糊，放大镜裁取原图对应区域。渲染严格本地执行，不调用模型，不上传图片，响应中的 `meta.cloudUploaded` 固定为 `false`。

GUI 编辑器暂不改为调用新渲染器，避免扩大这次变更范围；通过共享测试样例校验两者关键默认值一致。

## 验收

- CLI 解析测试覆盖图片输入、`last`、recipe、undo、redo 和错误参数。
- Recipe 解码与校验测试覆盖每种 operation、裁剪顺序、ID 和颜色。
- 渲染测试用固定图片检查尺寸、像素变化、裁剪、擦除和撤销/重做。
- Capability Service 测试确认 `transform.image` 已暴露、产生 Artifact、不会云上传。
- 运行标注相关测试、CLI 测试和完整 Swift 测试套件。
- 使用真实 `ta transform` 对一张截图添加矩形、箭头和中文文字，检查输出文件与 JSON 响应。
