import Foundation
import FoundationModels


let languageModels = [
    "base": SystemLanguageModel.default,
    "permissive": SystemLanguageModel(guardrails: .permissiveContentTransformations)
]


enum FinishReason: String {
    case stop = "stop"
    case length = "length"
    case contentFilter = "content_filter"
    case error = "error"
    // case toolCalls = "tool_calls"
}


struct SessionResponse {
    var content: String?
    var finishReason: FinishReason?
}


class ResponseSession {
    var model: SystemLanguageModel
    var modelName: String
    
    var isChat: Bool
    var prompt: Prompt
    var session: LanguageModelSession
    
    var toStream: Bool
    var options: GenerationOptions
    
    init(from content: RequestContent) throws(RequestError) {
        // Get model
        self.modelName = content.model ?? "base"
        guard let model = languageModels[modelName] else {
            throw RequestError.invalidModel
        }
        self.model = model
        
        // Get prompt and session
        if let messages = content.messages {
            let transcript = try getTranscript(from: messages)
            
            self.isChat = true
            self.prompt = getPrompt(from: messages)
            self.session = LanguageModelSession(model: model, transcript: transcript)
        } else if let prompt = content.prompt {
            self.isChat = false
            self.prompt = Prompt(prompt)
            self.session = LanguageModelSession(model: model)
        } else {
            throw RequestError.noPromptOrMessages
        }
        
        // Get options
        self.toStream = content.stream ?? false
        
        var samplingMode: GenerationOptions.SamplingMode?
        if let threshold = content.top_p {
            samplingMode = .random(probabilityThreshold: threshold, seed: content.seed)
        } else if let cutoff = content.top_k {
            samplingMode = .random(top: cutoff, seed: content.seed)
        }
        
        self.options = GenerationOptions(
            sampling: samplingMode,
            temperature: content.temperature,
            maximumResponseTokens: content.max_tokens,
        )
    }
    
    func getResponse() async -> SessionResponse {
        var response = SessionResponse()
        
        do {
            response.content = try await self.session.respond(to: self.prompt, options: self.options).content
            response.finishReason = .stop
        } catch {
            handleError(error, &response)
        }
        
        return response
    }
    
    func streamResponses() -> sending AsyncStream<SessionResponse> {
        let session = self.session
        let prompt = self.prompt
        let options = self.options
        
        return AsyncStream { continuation in
            Task { @Sendable in
                do {
                    var previousSnapshotContent = ""
                    
                    let stream = session.streamResponse(to: prompt, options: options)
                    for try await snapshot in stream {
                        var response = SessionResponse()
                        response.content = String(snapshot.content.dropFirst(previousSnapshotContent.count))
                        response.finishReason = nil
                        
                        previousSnapshotContent = snapshot.content
                        
                        continuation.yield(response)
                    }
                    
                    // Send final chunk
                    continuation.yield(SessionResponse(content: "", finishReason: .stop))
                    
                    continuation.finish()
                } catch {
                    var response = SessionResponse()
                    handleError(error, &response)
                    continuation.yield(response)
                    continuation.finish()
                }
            }
        }
    }
}


private func handleError(_ error: any Error, _ response: inout SessionResponse) {
    guard let error = error as? LanguageModelSession.GenerationError else {
        response.finishReason = .error
        return
    }
    
    switch error {
    case .exceededContextWindowSize:
        response.finishReason = .length
    case .guardrailViolation:
        response.finishReason = .contentFilter
    default:
        response.finishReason = .error
    }
}


private func getTranscript(from messages: [Message]) throws(RequestError) -> Transcript {
    // Note: We do not support assistant prefill (yet)
    let entries = try messages.dropLast().map { message throws(RequestError) in
        if message.role == "user" {
            return Transcript.Entry.prompt(
                Transcript.Prompt(
                    segments: [.text(Transcript.TextSegment(content: message.content))]
                )
            )
        } else if message.role == "assistant" {
            return Transcript.Entry.response(
                Transcript.Response(
                    assetIDs: [],
                    segments: [.text(Transcript.TextSegment(content: message.content))]
                )
            )
        } else if message.role == "system" {
            return Transcript.Entry.instructions(
                Transcript.Instructions(
                    segments: [.text(Transcript.TextSegment(content: message.content))],
                    toolDefinitions: []
                )
            )
        }
        
        throw RequestError.invalidMessageRole
    }
    
    return Transcript(entries: entries)
}


private func getPrompt(from messages: [Message]) -> Prompt {
    // Note: We do not support assistant prefill (yet)
    return Prompt(messages.last?.content ?? "")
}
