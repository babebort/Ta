import CoreGraphics
import Foundation
import TaAgentContracts

struct TaAgentAnnotationRenderResult {
    let image: CGImage
    let elementCount: Int
    let canUndo: Bool
    let canRedo: Bool
}

struct TaAgentAnnotationSession {
    private struct State {
        var cropRect: AnnotationRect?
        var elements: [AnnotationOperation]
    }

    private let sourceImage: CGImage
    private let renderer: TaAgentAnnotationRenderer
    private var state = State(cropRect: nil, elements: [])
    private var undoStates: [State] = []
    private var redoStates: [State] = []

    init(sourceImage: CGImage, renderer: TaAgentAnnotationRenderer = .init()) {
        self.sourceImage = sourceImage
        self.renderer = renderer
    }

    mutating func apply(_ recipe: AnnotationRecipe) throws -> TaAgentAnnotationRenderResult {
        let existingIDs = Set(state.elements.compactMap(\.elementID))
        let validated = try recipe.validated(existingElementIDs: existingIDs)
        var next = state

        for operation in validated.operations {
            switch operation {
            case .crop(let crop):
                guard next.cropRect == nil, next.elements.isEmpty else {
                    throw TaAgentAnnotationSessionError.cropMustPrecedeAnnotations
                }
                try validateCrop(crop.rect)
                next.cropRect = crop.rect
            case .eraser(let eraser):
                let removed = Set(eraser.targetIDs)
                next.elements.removeAll { operation in
                    operation.elementID.map(removed.contains) ?? false
                }
            default:
                next.elements.append(operation)
            }
        }

        let image = try renderer.render(
            sourceImage: sourceImage,
            cropRect: next.cropRect,
            elements: next.elements
        )
        undoStates.append(state)
        if undoStates.count > 100 { undoStates.removeFirst() }
        state = next
        redoStates.removeAll()
        return result(image)
    }

    mutating func undo() throws -> TaAgentAnnotationRenderResult {
        guard let previous = undoStates.popLast() else {
            throw TaAgentAnnotationSessionError.nothingToUndo
        }
        let image = try renderer.render(
            sourceImage: sourceImage,
            cropRect: previous.cropRect,
            elements: previous.elements
        )
        redoStates.append(state)
        if redoStates.count > 100 { redoStates.removeFirst() }
        state = previous
        return result(image)
    }

    mutating func redo() throws -> TaAgentAnnotationRenderResult {
        guard let next = redoStates.popLast() else {
            throw TaAgentAnnotationSessionError.nothingToRedo
        }
        let image = try renderer.render(
            sourceImage: sourceImage,
            cropRect: next.cropRect,
            elements: next.elements
        )
        undoStates.append(state)
        if undoStates.count > 100 { undoStates.removeFirst() }
        state = next
        return result(image)
    }

    func renderCurrent() throws -> TaAgentAnnotationRenderResult {
        result(try renderer.render(
            sourceImage: sourceImage,
            cropRect: state.cropRect,
            elements: state.elements
        ))
    }

    private func result(_ image: CGImage) -> TaAgentAnnotationRenderResult {
        TaAgentAnnotationRenderResult(
            image: image,
            elementCount: state.elements.count,
            canUndo: !undoStates.isEmpty,
            canRedo: !redoStates.isEmpty
        )
    }

    private func validateCrop(_ rect: AnnotationRect) throws {
        guard rect.x >= 0, rect.y >= 0,
              rect.x + rect.width <= Double(sourceImage.width),
              rect.y + rect.height <= Double(sourceImage.height) else {
            throw TaAgentAnnotationSessionError.cropOutOfBounds
        }
    }
}

enum TaAgentAnnotationSessionError: Error, Equatable, LocalizedError {
    case cropMustPrecedeAnnotations
    case cropOutOfBounds
    case nothingToUndo
    case nothingToRedo

    var errorDescription: String? {
        switch self {
        case .cropMustPrecedeAnnotations:
            "crop 只能用于尚未添加标注、尚未裁剪的编辑会话。"
        case .cropOutOfBounds:
            "crop.rect 超出源图片边界。"
        case .nothingToUndo:
            "没有可撤销的标注操作。"
        case .nothingToRedo:
            "没有可重做的标注操作。"
        }
    }
}
