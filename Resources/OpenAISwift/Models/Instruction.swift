//
//  Created by Adam Rush - OpenAISwift
//

import Foundation

struct Instruction: Encodable {
    let instruction: String
    let model: String
    let input: String
}
