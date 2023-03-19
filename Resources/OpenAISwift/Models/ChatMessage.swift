//
//  File.swift
//
//
//  Created by Bogdan Farca on 02.03.2023.
//

import Foundation

public enum ChatRole: String, Codable {
    case system, user, assistant
}

public struct ChatMessage: Codable {
    public let role: ChatRole
    public let content: String
    
    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct ChatConversation: Encodable {
    let user: String?
    let messages: [ChatMessage]
    let model: String
    let temperature: Double?
    let topProbabilityMass: Double?
    let choices: Int?
    let stop: [String]?
    let maxTokens: Int?
    let presencePenalty: Double?
    let frequencyPenalty: Double?

    enum CodingKeys: String, CodingKey {
        case user
        case messages
        case model
        case temperature
        case topProbabilityMass = "top_p"
        case choices = "n"
        case stop
        case maxTokens = "max_tokens"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
    }

}
