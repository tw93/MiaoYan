//
//  Created by Adam Rush - OpenAISwift
//

import Foundation

public protocol Payload: Codable { }

public struct OpenAI<T: Payload>: Codable {
    public let object: String
    public let model: String?
    public let choices: [T]
    public let usage: UsageResult
}

public struct TextResult: Payload {
    public let text: String
}

public struct MessageResult: Payload {
    public let message: ChatMessage
}

public struct UsageResult: Codable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
