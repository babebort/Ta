import AppKit
import AIScreenshotCore
import SwiftUI

@MainActor
final class ScrollingSeamReviewWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: ScrollingSeamReviewModel?
    private var stitcher: ScrollingImageStitcher?
    private var cancellationHandler: (() -> Void)?
    private var isClosingProgrammatically = false

    func present(
        stitcher: ScrollingImageStitcher,
        onComplete: @escaping ([CGImage], Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        close()
        self.stitcher = stitcher
        cancellationHandler = onCancel
        let model = ScrollingSeamReviewModel()
        model.segments = stitcher.segments
        model.lowConfidenceCount = lowConfidenceCount(in: stitcher)
        model.onAdjust = { [weak self] id, delta in self?.adjust(id: id, delta: delta) }
        model.onComplete = { [weak self] in
            guard let self, let stitcher = self.stitcher else { return }
            do {
                let images = try stitcher.makeImages(maximumPixelHeight: 30_000)
                let reviewed = self.lowConfidenceCount(in: stitcher)
                self.close()
                onComplete(images, reviewed)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
        model.onCancel = { [weak self] in
            self?.cancelReview()
        }
        self.model = model
        refreshPreview()

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "检查长截图接缝"
        window.minSize = CGSize(width: 820, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentView = NSHostingView(rootView: ScrollingSeamReviewView(model: model))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func close() {
        isClosingProgrammatically = true
        window?.delegate = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        model = nil
        stitcher = nil
        cancellationHandler = nil
        isClosingProgrammatically = false
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosingProgrammatically else { return }
        let handler = cancellationHandler
        window = nil
        model = nil
        stitcher = nil
        cancellationHandler = nil
        handler?()
    }

    private func cancelReview() {
        let handler = cancellationHandler
        close()
        handler?()
    }

    private func adjust(id: UUID, delta: Int) {
        guard let stitcher, stitcher.adjustSegment(id: id, pixelDelta: delta) else { return }
        model?.segments = stitcher.segments
        refreshPreview()
    }

    private func refreshPreview() {
        guard let stitcher, let model else { return }
        do {
            model.previewImages = try stitcher.makeImages(maximumPixelHeight: 8_000).map {
                NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
            }
            model.selectedPart = min(model.selectedPart, max(0, model.previewImages.count - 1))
            model.outputHeight = stitcher.outputPixelHeight
            model.errorMessage = nil
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func lowConfidenceCount(in stitcher: ScrollingImageStitcher) -> Int {
        stitcher.qualityIssues.reduce(into: 0) { count, issue in
            if case .lowConfidence = issue { count += 1 }
        }
    }
}

@MainActor
private final class ScrollingSeamReviewModel: ObservableObject {
    @Published var segments: [ScrollingStitchSegment] = []
    @Published var previewImages: [NSImage] = []
    @Published var selectedPart = 0
    @Published var outputHeight = 0
    @Published var lowConfidenceCount = 0
    @Published var zoom = 0.55
    @Published var errorMessage: String?
    var onAdjust: ((UUID, Int) -> Void)?
    var onComplete: (() -> Void)?
    var onCancel: (() -> Void)?
}

private struct ScrollingSeamReviewView: View {
    @ObservedObject var model: ScrollingSeamReviewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("检查接缝")
                        .font(.title2.bold())
                    Text("红色接缝建议重点查看。负值会移除重复行，正值会补回遗漏行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("总高 \(model.outputHeight) px")
                    .font(.system(.caption, design: .rounded))
                Slider(value: $model.zoom, in: 0.2...1.5)
                    .frame(width: 130)
                Button("丢弃") { model.onCancel?() }
                Button("确认并保存") { model.onComplete?() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            HSplitView {
                VStack(spacing: 10) {
                    if model.previewImages.count > 1 {
                        Picker("预览分段", selection: $model.selectedPart) {
                            ForEach(model.previewImages.indices, id: \.self) { index in
                                Text("第 \(index + 1) / \(model.previewImages.count) 段").tag(index)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    }
                    ScrollView([.horizontal, .vertical]) {
                        if model.previewImages.indices.contains(model.selectedPart) {
                            let image = model.previewImages[model.selectedPart]
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .frame(
                                    width: image.size.width * model.zoom,
                                    height: image.size.height * model.zoom
                                )
                                .shadow(color: .black.opacity(0.18), radius: 8)
                                .padding(24)
                        }
                    }
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
                }
                .frame(minWidth: 500)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("接缝列表")
                            .font(.headline)
                        Spacer()
                        if model.lowConfidenceCount > 0 {
                            Text("\(model.lowConfidenceCount) 个需检查")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(model.segments.enumerated()), id: \.element.id) { index, segment in
                                seamRow(index: index, segment: segment)
                            }
                        }
                        .padding(10)
                    }
                    if let error = model.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(10)
                    }
                }
                .frame(minWidth: 300, idealWidth: 340)
            }
        }
    }

    private func seamRow(index: Int, segment: ScrollingStitchSegment) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Circle()
                    .fill(segment.confidence < 0.58 ? Color.red : Color.green)
                    .frame(width: 8, height: 8)
                Text("接缝 \(index + 1) · \(segment.direction == .up ? "向上" : "向下")")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(Int(segment.confidence * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(segment.confidence < 0.58 ? .red : .secondary)
            }
            Text("新增 \(segment.newPixelHeight) px · 固定顶 \(segment.stableTopHeight) · 固定底 \(segment.stableBottomHeight)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach([-10, -1, 1, 10], id: \.self) { delta in
                    Button(delta > 0 ? "+\(delta)" : "\(delta)") {
                        model.onAdjust?(segment.id, delta)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(
            segment.confidence < 0.58 ? Color.red.opacity(0.08) : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}
