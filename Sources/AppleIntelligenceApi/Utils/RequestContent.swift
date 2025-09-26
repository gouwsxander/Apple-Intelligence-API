import Vapor


struct Message: Content {
    var role: String
    var content: String
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
    
    // Note: We do not yet support response format (guided generation), or tool calling
}
