import Vapor


struct ToolCall: Content {
    var id: String
    var type: String
    var function: FunctionCall
}


struct FunctionCall: Content {
    var name: String
    var arguments: String
}


struct Message: Content {
    var role: String
    var content: String?
    var tool_calls: [ToolCall]?
    var tool_call_id: String?
    var name: String?
}


struct ToolFunction: Content {
    var name: String
    var description: String?
    var parameters: [String: AnyCodable]?
}


struct Tool: Content {
    var type: String
    var function: ToolFunction
}


struct ToolChoice: Content {
    var type: String?
    var function: ToolChoiceFunction?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let stringValue = try? container.decode(String.self) {
            // Handle "auto", "none", or "required"
            self.type = stringValue
            self.function = nil
        } else {
            // Handle object with type and function
            let objectContainer = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try objectContainer.decode(String.self, forKey: .type)
            self.function = try objectContainer.decodeIfPresent(ToolChoiceFunction.self, forKey: .function)
        }
    }

    func encode(to encoder: Encoder) throws {
        if let function = function {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encode(function, forKey: .function)
        } else if let type = type {
            var container = encoder.singleValueContainer()
            try container.encode(type)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case function
    }
}


struct ToolChoiceFunction: Content {
    var name: String
}


// Helper type for arbitrary JSON values
enum AnyCodable: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodable])
    case dictionary([String: AnyCodable])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let bool):
            try container.encode(bool)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .dictionary(let dict):
            try container.encode(dict)
        }
    }
}


struct RequestContent: Content {
    // Either `messages` or `prompt` is required
    var messages: [Message]?
    var prompt: String?

    // If `model` is unspecified, uses the default
    var model: String?

    // Enable streaming
    var stream: Bool?

    // Generation options
    var max_tokens: Int?
    var temperature: Double?

    // Advanced options
    var seed: UInt64?
    var top_p: Double?
    var top_k: Int?

    // Tool/function calling
    var tools: [Tool]?
    var tool_choice: ToolChoice?
}
