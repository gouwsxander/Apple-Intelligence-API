import Foundation
import FoundationModels

struct FunctionTool: Tool {

    typealias Arguments = GeneratedContent
    typealias Output = GeneratedContent

    typealias Callback =
        @Sendable (Arguments) async throws -> Output

    var callback: Callback

    var name: String
    var description: String
    var parameters: GenerationSchema

    func call(arguments: GeneratedContent) async throws(Self.Error) -> Output {
        do {
            return try await callback(arguments)
        } catch let error {
            throw .callback(error)
        }
    }
}

extension FunctionTool {
    enum Error: Swift.Error {
        case decoding(DecodingError)
        case schema(GenerationSchema.SchemaError)
        case callback(any Swift.Error)

        init(from error: DecodingError) {
            self = .decoding(error)
        }

        init(from error: GenerationSchema.SchemaError) {
            self = .schema(error)
        }

        init<E: Swift.Error>(from error: E) {
            self = .callback(error)
        }
    }
}
