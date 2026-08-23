import SwiftUI

enum ResultBarKind: Equatable {
    case processing
    case success
    case warning
    case failure

    var symbol: String {
        switch self {
        case .processing: return "circle.dotted"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .processing: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        }
    }
}

struct ResultBarState {
    let kind: ResultBarKind
    let title: String
    let detail: String?
}

struct ResultBarView: View {
    let state: ResultBarState
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.kind.symbol)
                .foregroundStyle(state.kind.color)
                .symbolEffect(.pulse, options: .repeating, isActive: state.kind == .processing)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail = state.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)
            Text(TaBrand.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(TaPalette.paper)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(TaPalette.cinnabar, in: Capsule())

            if state.kind != .processing {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .help("关闭提示")
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 390, height: 54)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}
