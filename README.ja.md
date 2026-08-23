<div align="center">

<img src="./Resources/Brand/Ta-AppIcon.png" width="128" alt="Ta ロゴ">

# 拓 · Ta

### 画面上の情報を、そのまま拓き取る。

[![License: MIT](https://img.shields.io/badge/License-MIT-D6402F.svg)](./LICENSE)
[![Platform: macOS 14+](https://img.shields.io/badge/macOS-14%2B-1A1A1A.svg)](https://www.apple.com/macos/)
[![Swift: 6.2](https://img.shields.io/badge/Swift-6.2-F05138.svg)](https://www.swift.org/)
[![Status: Alpha](https://img.shields.io/badge/Status-Alpha-C98B2E.svg)](#現在のステータス)

**キャプチャ、OCR、翻訳、スクロールキャプチャ、ピン留め、注釈を一つにまとめた、macOS ファースト・ローカルファーストの AI スクリーンショットツールです。**

[简体中文](./README.md) · [English](./README.en.md) · [日本語](./README.ja.md)

</div>

![Ta ホーム画面](./docs/brand/Ta-home-preview.png)

## 「拓」という名前について

中国語の「拓」（`tà`）は、石碑や器物に刻まれた情報を紙へ写し取る伝統的な拓本・拓印に由来します。Ta も同じ発想で、画面上の文字・画像・文脈をすばやく“拓き取り”、コピー、翻訳、注釈、ピン留め、保存、再利用へつなげます。

中国語名は「拓」、英語名は **Ta** です。

## なぜ Ta を作るのか

スクリーンショットアプリは数多くありますが、実際の作業は今も分断されています。画像を撮った後に別の OCR ツールを開き、翻訳のためにさらにアプリを切り替え、長いチャットを手作業でつなぎ、公開用の画像を作るために画像エディタを起動する必要があります。

Ta はスクリーンショットを最終成果ではなく、情報処理の入口として扱います。

- 一時ファイルを保存せず、その場で文字抽出や画像コピーができます。
- OCR とマルチモーダル視覚モデルを別々の経路として選択できます。
- ローカル処理を優先し、低信頼度時のアップロードには明示的な確認が必要です。
- 撮影後、そのまま翻訳、ピン留め、注釈、長画像結合、保存へ進めます。
- よく使う操作にはカスタマイズ可能なグローバルショートカットがあります。

## 解決する課題

- **撮影後の二次作業が多い** — OCR、翻訳、コピー、保存、注釈を一つのフローにまとめます。
- **スクロールキャプチャが不安定** — 手動/自動スクロール、重複フレーム除去、固定領域除去、継ぎ目確認、手動補正に対応します。
- **一つの OCR では足りない** — 速度、構造、プライバシーに応じて Apple Vision、PaddleOCR、リモート視覚サービスを切り替えられます。
- **注釈に時間がかかる** — Snipaste に近いその場での注釈、オブジェクトの直接操作、ブラシ型モザイク、画像ピンを提供します。
- **クラウド送信の境界が曖昧** — デフォルトはローカル処理。送信時は明示し、API Key は macOS Keychain に保存します。

## 仕組み

Ta は macOS ネイティブのキャプチャパイプラインを使用します。

```text
グローバルショートカット
    ↓
画面領域を選択
    ↓
ScreenCaptureKit で撮影（Ta 自身のウインドウは除外）
    ↓
┌────────────────┬────────────────────┐
│ ローカル OCR    │ マルチモーダル視覚   │
│ Apple Vision   │ OpenAI-compatible  │
│ PaddleOCR      │ Claude / Gemini    │
└────────────────┴────────────────────┘
    ↓
コピー · 翻訳 · ピン留め · 注釈 · 結合 · 保存
```

認識中にユーザーが別の内容をコピーした場合、Ta は新しいクリップボード内容を上書きしません。文字が見つからない場合は、PNG のコピーへ安全にフォールバックできます。

## 主な機能

### キャプチャとショートカット

- OCR、AI 画像認識、翻訳、コピー、ピン留め、注釈、美化、保存を選べる共通ツールバー。
- 即時 OCR、画像コピー、翻訳、ピン留め、スクロールキャプチャに専用グローバルショートカット。
- 設定画面でショートカットを再記録し、競合を検出して初期値へ戻せます。
- 領域選択中は右クリックまたは `Escape` で中止でき、ファイルやクリップボードを変更しません。
- 撮影時は Ta の画面を自動的に隠し、フォーカスを奪わず、キャプチャにも映り込みません。

### OCR と AI 画像認識

- **Apple Vision** — 中国語、英語、一般的な文字レイアウトに対応する標準のローカル OCR。
- **PaddleOCR 拡張パック** — Apple Silicon 上でオフライン動作し、インストール、更新、検証、ウォームアップ、常駐ワーカーに対応。
- **DeepSeek-OCR-2** — ユーザーが用意した vLLM、SGLang、または互換視覚エンドポイントへ接続。大型モデルを Mac へ無断でダウンロードしません。
- **マルチモーダル Provider** — OpenAI-compatible、Azure OpenAI、Anthropic Claude、Google Gemini の各プロトコル。
- 正確な文字抽出、コード説明、Markdown/CSV 表、LaTeX 数式、一般画像理解のタスクテンプレート。
- OCR のみ、モデルのみ、またはアップロード前に確認するローカル優先スマートルーティング。

### スクリーンショット翻訳

- 翻訳元と翻訳先の言語をカスタマイズ可能。初期値は自動判定から簡体字中国語です。
- キャプチャを翻訳し、結果をクリップボードへ直接コピーします。
- プレーンテキスト、画像内の文字置換、原画像下部への二言語パネル追加に対応します。
- 文字位置の検出と最終画像の合成はローカルで行い、翻訳が必要な文字だけを設定済みモデルへ送信します。

### スクロールキャプチャ

- ブラウザ、チャット、一般的なデスクトップアプリで手動/自動スクロール撮影。
- 隣接フレームの照合、重複除去、スクロール方向の検出。
- 固定ヘッダー、フッター、入力欄の検出と除去。
- 書き出し前に継ぎ目を確認し、`±1` / `±10 px` 単位で補正できます。
- 極端に長い画像を分割し、メモリ使用量と書き出し負荷を抑えます。

### 注釈と画像ピン

- キャプチャ位置を保ったまま、半透明オーバーレイ上で直接注釈できます。
- 四角形、楕円、矢印、ペン、蛍光ペン、文字、番号、モザイク、ぼかし、消しゴム、拡大鏡。
- 注釈オブジェクトを直接選択し、移動、拡大縮小、回転、再編集できます。
- モザイクは矩形選択とフリーハンド描画の両方に対応します。
- 画像ピンは移動、サイズ、透明度、回転、反転、フィルター、切り抜き、クリック透過、グループ、非表示/復元、ダブルクリックで閉じる操作に対応します。
- スクリーンショット、クリップボード画像、文字、HTML、ファイルからピンを作成できます。

## クイックスタート

### 必要環境

- macOS 14 以降
- Apple Silicon または Intel Mac（配布用 PaddleOCR 拡張パックは現在 Apple Silicon 向け）
- Xcode 26、または Swift 6.2 互換ツールチェーン

### ソースからビルド

```bash
git clone https://github.com/kangarooking/Ta.git
cd Ta
swift test
./scripts/build-app.sh
open "artifacts/拓.app"
```

初回起動時に「画面収録とシステムオーディオ録音」の権限を許可してください。「アクセシビリティ」権限は自動スクロールキャプチャを使う場合だけ必要です。

### デフォルトショートカット

| 操作 | ショートカット |
|------|----------------|
| 即時 OCR | `⇧⌥⌘1` |
| 共通キャプチャ | `⇧⌥⌘2` |
| 画像をコピー | `⇧⌥⌘3` |
| キャプチャしてピン留め | `⇧⌥⌘4` |
| スクロールキャプチャ | `⇧⌥⌘5` |
| スクリーンショット翻訳 | `⇧⌥⌘6` |

「設定 → ショートカット」で任意の組み合わせを再登録できます。競合するショートカットは拒否されるか、自動的に元へ戻ります。

## プライバシーとセキュリティ

- 通常のキャプチャと Apple Vision OCR は常に端末内で処理します。
- PaddleOCR 拡張パックはインストール後、オフラインで動作します。
- リモート OCR、マルチモーダル画像認識、翻訳を明示的に選んだ場合だけ、選択領域または文字を設定済みサービスへ送信します。
- 低信頼度スマートルーティングは無断でアップロードせず、必ず確認を求めます。
- API Key は macOS Keychain のみに保存し、設定ファイル、ログ、リポジトリには書き込みません。
- Ta は画面を常時録画せず、ユーザーが選択した領域だけを読み取ります。

## リポジトリ構成

```text
Ta/
├── README.md / README.en.md / README.ja.md
├── Package.swift
├── Resources/                 アイコン、Info.plist、ブランド素材
├── Sources/
│   ├── AIScreenshotCore/      OCR、長画像結合、Provider、Clipboard
│   └── AIScreenshotApp/       撮影、エディタ、ルーティング、システム、UI
├── Tests/                     Core / App テスト
├── ocr-packs/paddleocr/       PaddleOCR 拡張パック定義
├── scripts/                   ビルド、実行、OCR パックスクリプト
└── docs/                      PRD、調査、検証記録、実装計画
```

## 現在のステータス

Ta は現在 **Alpha** です。主要なワークフローは動作しますが、公証済みの正式リリースではありません。

既知の制限：

- 領域選択は現在ポインターがあるディスプレイを中心に動作し、複数画面をまたぐ選択とウインドウ自動スナップは未完成です。
- 動画、アニメーション、半透明オーバーレイ、大きく再配置されるレイアウトでは、スクロールキャプチャの継ぎ目を手動補正する場合があります。
- 画像翻訳はローカルで文字を覆って再描画します。複雑なテクスチャ、グラデーション、影、縦書き、密なレイアウトでは跡が残ることがあります。
- 公開リポジトリには PaddleOCR パックの定義のみを含み、ローカルで生成した大型アーカイブやモデル重みは含めません。
- ローカルビルドは Apple Development 署名を優先します。一般配布には Developer ID 署名と Apple notarization が必要です。

## ドキュメント

- [製品要件（中国語）](./AI截图软件-产品需求文档-PRD-v1.0.md)
- [市場・ユーザー課題調査（中国語）](./AI截图软件市场与用户痛点调研.md)
- [Alpha 検証記録](./docs/alpha-verification.md)
- [スクロールキャプチャ受け入れ基準](./docs/long-capture-acceptance-matrix.md)
- [PaddleOCR 拡張パック仕様](./docs/ocr-enhancement-pack-spec.md)

## Roadmap

- [x] ネイティブキャプチャ、OCR、クリップボード出力、カスタムショートカット
- [x] スクロールキャプチャ、自動スクロール、継ぎ目確認
- [x] その場での注釈、ブラシ型モザイク、画像ピン
- [x] スクリーンショット翻訳と複数 Provider 設定
- [x] オフライン PaddleOCR 拡張パックの仕組み
- [ ] 複数画面をまたぐ領域選択とウインドウスナップ
- [ ] 公開用テンプレートとパラメータ化された画像スタイル
- [ ] 履歴、検索、結果の再コピー
- [ ] Developer ID 署名、公証、一般向けインストーラ

## コントリビューション

Issue、機能提案、Pull Request を歓迎します。変更前に [CONTRIBUTING.md](./CONTRIBUTING.md) を読み、挙動の変更にはテストまたは再現可能な検証手順を添えてください。

## 作者

**Kangarooking（袋鼠帝）** — 中国語メディア「袋鼠帝 AI 客栈」を運営する AI クリエイター、個人開発者。

| プラットフォーム | リンク |
|------------------|--------|
| GitHub | [@kangarooking](https://github.com/kangarooking) |
| X / Twitter | [@aikangarooking](https://x.com/aikangarooking) |
| Cangjie Skill | [kangarooking/cangjie-skill](https://github.com/kangarooking/cangjie-skill) |

## ⭐ Star History

Ta が役に立ったら、ぜひ Star をお願いします。

<a href="https://www.star-history.com/?repos=kangarooking%2FTa&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=kangarooking/Ta&type=date&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=kangarooking/Ta&type=date&legend=top-left" />
   <img alt="Ta Star History Chart" src="https://api.star-history.com/chart?repos=kangarooking/Ta&type=date&legend=top-left" />
 </picture>
</a>

## License

MIT。詳細は [LICENSE](./LICENSE) を参照してください。
