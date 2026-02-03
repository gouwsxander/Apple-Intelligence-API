import Foundation
import Vapor

enum RequestError: AbortError {
    case nonConformingBody
    case invalidMessageRole
    case invalidModel
    case noPromptOrMessages

    var status: HTTPResponseStatus {
        return .badRequest
    }

    var reason: String? {
        switch self {
        case .nonConformingBody:
            return "Request body does not conform to expected standard."
        case .invalidMessageRole:
            return
                "An invalid message role was given. These must be either 'system', 'user', or 'assistant'."
        case .noPromptOrMessages:
            return "One of `messages` or `prompt` is required."
        case .invalidModel:
            return "The requested model does not exist."
        }
    }
}

enum ResponseError: AbortError {
    // Note: Only in rare cases should errors result in a request being aborted
    case serializationError(_ description: String)
    case moderationError

    var status: HTTPResponseStatus {
        switch self {
        case .serializationError(_):
            return .internalServerError
        case .moderationError:
            return .init(
                statusCode: 402,
                reasonPhrase: ResponseError.moderationError.reason
            )
        }
    }

    var reason: String? {
        switch self {
        case .serializationError(let description):
            return description
        case .moderationError:
            return
                "Your chosen model requires moderation and your input was flagged."
        }
    }
}
