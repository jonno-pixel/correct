import Foundation

struct JJSFailure: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

enum MessageRole: String, Codable, Sendable, Equatable {
    case user
    case assistant
}

enum MessageState: String, Codable, Sendable, Equatable {
    case queued
    case running
    case complete
    case stopped
    case failed
}

struct ChatSummary: Identifiable, Sendable {
    let id: String
    var title: String
    var updated: Date
}

struct ChatMessage: Identifiable, Codable, Sendable {
    var id: String
    var role: MessageRole
    var content: String
    var state: MessageState
    var created: Date
    var note: String
}

struct ModelEntry: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let bytes: Int64
}

struct GenerationOptions: Codable, Sendable {
    var modelPath: String
    var contextSize: UInt32
    var temperature: Float
    var useMetal: Bool
    var template: String
}

struct EngineTurn: Sendable {
    let role: String
    let content: String
}

enum EngineUpdate: Sendable {
    case status(String)
    case text(String)
}

struct GenerationResult: Sendable {
    let tokenCount: Int
    let contextShifts: Int
}

struct UTF8Stream: Sendable {
    private(set) var pending: [UInt8] = []

    mutating func append(_ bytes: [UInt8]) -> String {
        pending.append(contentsOf: bytes)
        guard !pending.isEmpty else { return "" }

        var start = pending.count - 1
        while start > 0 && pending[start] & 0xC0 == 0x80 {
            start -= 1
        }

        let lead = pending[start]
        let width: Int
        switch lead {
        case 0x00...0x7F: width = 1
        case 0xC2...0xDF: width = 2
        case 0xE0...0xEF: width = 3
        case 0xF0...0xF4: width = 4
        default: width = 1
        }

        let completeCount = pending.count - start < width ? start : pending.count
        let text = String(decoding: pending.prefix(completeCount), as: UTF8.self)
        pending.removeFirst(completeCount)
        return text
    }

    mutating func finish() -> String {
        defer { pending.removeAll(keepingCapacity: false) }
        return String(decoding: pending, as: UTF8.self)
    }
}
