import Foundation

public enum AgentFrameError: Error, Equatable, Sendable {
    case frameTooLarge(Int)
    case truncatedHeader
    case truncatedPayload(expected: Int, actual: Int)
    case unexpectedTrailingBytes(Int)
}

public enum AgentFrameCodec {
    public static let headerBytes = MemoryLayout<UInt32>.size
    public static let maximumPayloadBytes = 16 * 1024 * 1024

    public static func frame(_ payload: Data) throws -> Data {
        guard payload.count <= maximumPayloadBytes else {
            throw AgentFrameError.frameTooLarge(payload.count)
        }
        var length = UInt32(payload.count).bigEndian
        var result = withUnsafeBytes(of: &length) { Data($0) }
        result.append(payload)
        return result
    }

    public static func payload(from frame: Data) throws -> Data {
        guard frame.count >= headerBytes else { throw AgentFrameError.truncatedHeader }
        let declaredLength = frame.prefix(headerBytes).withUnsafeBytes {
            Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)))
        }
        guard declaredLength <= maximumPayloadBytes else {
            throw AgentFrameError.frameTooLarge(declaredLength)
        }
        let actualLength = frame.count - headerBytes
        guard actualLength >= declaredLength else {
            throw AgentFrameError.truncatedPayload(expected: declaredLength, actual: actualLength)
        }
        guard actualLength == declaredLength else {
            throw AgentFrameError.unexpectedTrailingBytes(actualLength - declaredLength)
        }
        return frame.dropFirst(headerBytes)
    }

    public static func payloadLength(from header: Data) throws -> Int {
        guard header.count == headerBytes else { throw AgentFrameError.truncatedHeader }
        let length = header.withUnsafeBytes {
            Int(UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)))
        }
        guard length <= maximumPayloadBytes else { throw AgentFrameError.frameTooLarge(length) }
        return length
    }
}

