import Vapor


struct Message: Content {
    var role: String
    var content: String
}


indirect enum JSONSchemaProperty: Content {
    case string(description: String?, enumValues: [String]?)
    case integer(description: String?, minimum: Int?, maximum: Int?)
    case number(description: String?, minimum: Double?, maximum: Double?)
    case boolean(description: String?)
    case array(description: String?, items: JSONSchemaProperty)
    case object(description: String?, properties: [String: JSONSchemaProperty], required: [String]?)

    private enum CodingKeys: String, CodingKey {
        case type, description, `enum`, minimum, maximum, items, properties, required
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let description = try container.decodeIfPresent(String.self, forKey: .description)

        switch type {
        case "string":
            let enumValues = try container.decodeIfPresent([String].self, forKey: .enum)
            self = .string(description: description, enumValues: enumValues)
        case "integer":
            let minimum = try container.decodeIfPresent(Int.self, forKey: .minimum)
            let maximum = try container.decodeIfPresent(Int.self, forKey: .maximum)
            self = .integer(description: description, minimum: minimum, maximum: maximum)
        case "number":
            let minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
            let maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
            self = .number(description: description, minimum: minimum, maximum: maximum)
        case "boolean":
            self = .boolean(description: description)
        case "array":
            let items = try container.decode(JSONSchemaProperty.self, forKey: .items)
            self = .array(description: description, items: items)
        case "object":
            let properties = try container.decode([String: JSONSchemaProperty].self, forKey: .properties)
            let required = try container.decodeIfPresent([String].self, forKey: .required)
            self = .object(description: description, properties: properties, required: required)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported type: \(type)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let description, let enumValues):
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(enumValues, forKey: .enum)
        case .integer(let description, let minimum, let maximum):
            try container.encode("integer", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(minimum, forKey: .minimum)
            try container.encodeIfPresent(maximum, forKey: .maximum)
        case .number(let description, let minimum, let maximum):
            try container.encode("number", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encodeIfPresent(minimum, forKey: .minimum)
            try container.encodeIfPresent(maximum, forKey: .maximum)
        case .boolean(let description):
            try container.encode("boolean", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case .array(let description, let items):
            try container.encode("array", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encode(items, forKey: .items)
        case .object(let description, let properties, let required):
            try container.encode("object", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
            try container.encode(properties, forKey: .properties)
            try container.encodeIfPresent(required, forKey: .required)
        }
    }
}

struct JSONSchema: Content {
    var name: String
    var description: String?
    var schema: JSONSchemaProperty?
    var strict: Bool?
}

struct ResponseFormat: Content {
    var type: String // "json_schema" or "text"
    var json_schema: JSONSchema?
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
    
    // Structured output support
    var response_format: ResponseFormat?
    
    // Note: We do not yet support tool calling
}
