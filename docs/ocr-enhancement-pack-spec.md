# OCR 可选增强包协议

AI Screenshot 首装只包含 Apple Vision。RapidOCR / PaddleOCR 以独立目录包安装，避免把 Python、推理运行时和模型强塞进主 App。PaddleOCR 提供软件内一键安装；手动导入仍作为离线分发和故障恢复入口。

## 目录格式

```text
PaddleOCR-Pack-arm64-1.1.0/
├─ manifest.json
├─ bin/
│  └─ paddleocr-adapter
├─ adapter/
│  └─ adapter.py
├─ runtime/
│  └─ ... 独立 Python 运行时与 PaddleOCR/ONNX Runtime
├─ models/
│  ├─ PP-OCRv5_mobile_det_onnx/
│  └─ PP-OCRv5_mobile_rec_onnx/
├─ SBOM-pip-freeze.txt
└─ THIRD-PARTY-INVENTORY.json
```

`manifest.json` 示例：

```json
{
  "engine": "paddleOCR",
  "version": "1.1.0",
  "executable": "bin/paddleocr-adapter",
  "executableSHA256": "小写十六进制 SHA-256",
  "architecture": "arm64",
  "minimumMacOS": "14.0",
  "healthCheckArguments": ["--health-check"],
  "workerArguments": ["--worker"]
}
```

`engine` 只能为 `rapidOCR` 或 `paddleOCR`。安装器会验证操作系统、CPU 架构、压缩包 SHA-256、包内可执行文件 SHA-256，并拒绝绝对路径、`..`、反斜杠或越出增强包目录的可执行路径。新包只有在健康检查通过后才会替换旧版本。

## 一键安装发行清单

当前 App 会先查找 `AI Screenshot.app` 同级的 `ocr-packs/catalog.json`，用于本地 Alpha 分发；正式发布时可以通过 `ocrPackCatalogURL` 指向 HTTPS 清单。相对下载地址相对于清单所在目录解析。

```json
{
  "schemaVersion": 1,
  "packages": [{
    "engine": "paddleOCR",
    "version": "1.1.0",
    "architecture": "arm64",
    "minimumMacOS": "14.0",
    "downloadURL": "PaddleOCR-Pack-arm64-1.1.0.zip",
    "archiveSHA256": "压缩包 SHA-256",
    "archiveSize": 123456789
  }]
}
```

## 进程协议

主 App 使用以下参数启动适配器：

```bash
paddleocr-adapter --input /absolute/path/image.png --output json
```

标准输出必须是单个 JSON 对象，标准错误用于诊断：

```json
{
  "text": "识别结果",
  "confidence": 0.93
}
```

退出码必须为 `0`。非零退出码、无效 JSON、校验失败或未安装都会停止增强路径；未安装增强包时 App 自动回退 Apple Vision。

从 1.1.0 起，声明 `workerArguments` 的增强包支持常驻模式。主 App 启动一次适配器，等待首行 `ready`，之后通过标准输入/输出交换 JSON Lines；每个请求必须带唯一 `id`，适配器必须原样返回。主 App 串行发送请求，因此一个 Worker 同时只执行一次识别。

```bash
paddleocr-adapter --worker
```

启动响应：

```json
{"event":"ready","ok":true,"engine":"paddleOCR","packVersion":"1.1.0"}
```

识别请求与响应：

```json
{"id":"唯一请求 ID","command":"recognize","input":"/absolute/path/image.png","detectionSideLimit":2560}
{"id":"唯一请求 ID","ok":true,"text":"识别结果","confidence":0.93}
```

错误也必须作为同一请求的 JSON 返回：`{"id":"…","ok":false,"error":"原因"}`。Worker 异常退出、超时或返回错误 ID 时，主 App 会结束旧进程并自动重启重试一次。旧版不含 `workerArguments` 的增强包继续使用一次性进程协议。

健康检查协议：

```bash
paddleocr-adapter --health-check
```

```json
{
  "ok": true,
  "engine": "paddleOCR",
  "packVersion": "1.1.0",
  "architecture": "arm64",
  "offline": true
}
```

## PaddleOCR 1.1.0 固定版本与性能策略

- PaddleOCR 3.7.0 / PaddleX 3.7.2。
- ONNX Runtime CPU 1.29.0。
- PP-OCRv5 mobile detection + recognition，中英文、数字与常见截图文本。
- Apple Silicon 独立 CPython 3.12.14 运行时，用户不需要 Python、Homebrew、Docker 或 PaddlePaddle。
- 模型与运行时完全位于增强包内；安装后识别路径不联网。
- 选中 PaddleOCR 后后台预热，普通截图复用已经加载的检测与识别模型。
- 宿主会把最长边超过 2560 像素的图片等比缩小；适配器同时设置检测最长边上限，避免超长图直接放大推理成本。
- Worker 串行处理截图，空闲 5 分钟后退出并释放约 700–800 MB 峰值内存；切换到其他 OCR 引擎或卸载/更新增强包时也会退出。

## 发布要求

- 分别为 Apple Silicon / Intel 构建并签名适配器；只有用户点击安装后才下载，不得在识别时静默下载安装代码。
- 固定 RapidOCR/PaddleOCR、ONNX/Paddle Runtime 和模型版本，生成 SBOM、许可证清单与 SHA-256。
- 在公开中文、英文、表格、公式和低清截图集上记录精度、延迟、峰值内存与包体。
- 主 App 与增强包分开升级；卸载增强包不能影响 Apple Vision 主路径。

## 本项目构建与测试

```bash
scripts/build-paddleocr-pack.sh
scripts/test-paddleocr-pack.sh
```

构建产物位于 `artifacts/ocr-packs/`，包括压缩包和 `catalog.json`。构建脚本固定独立 Python 下载地址与 SHA-256，并为原生 arm64 启动器签名。
