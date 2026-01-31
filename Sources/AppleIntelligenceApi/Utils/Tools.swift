import FoundationModels

struct FunctionTool<T: PromptRepresentable>: Tool {

    typealias Output = T
    typealias Arguments = GeneratedContent

    var name: String
    var description: String
    var parameters: GenerationSchema

    var onCall: @Sendable (Arguments) async -> Output

    func call(arguments: Arguments) async throws -> Output {
        return await self.onCall(arguments)
    }
}
