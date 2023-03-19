//
//  Created by Adam Rush - OpenAISwift
//

import Foundation

enum Endpoint {
    case completions
    case edits
    case chat
}

extension Endpoint {
    var path: String {
        switch self {
            case .completions:
                return "/v1/completions"
            case .edits:
                return "/v1/edits"
            case .chat:
                return "/v1/chat/completions"
        }
    }
    
    var method: String {
        switch self {
            case .completions, .edits, .chat:
            return "POST"
        }
    }
    
    func baseURL() -> String {
        switch self {
            case .completions, .edits, .chat:
            return "https://api.openai.com"
        }
    }
}
