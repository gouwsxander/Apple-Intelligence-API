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
    case toolCalls = "tool_calls"
}


struct SessionResponse {
    var content: String?
    var finishReason: FinishReason?
    var toolCalls: [ToolCall]?
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
            let transcript = try getTranscript(from: messages, tools: content.tools)

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
            let result = try await self.session.respond(to: self.prompt, options: self.options)

            // Extract text content and tool invocations from segments
            var textContent = ""
            var toolCalls: [ToolCall] = []

            for segment in result.segments {
                switch segment {
                case .text(let textSegment):
                    textContent += textSegment.content
                case .toolInvocation(let invocation):
                    let toolCall = ToolCall(
                        id: invocation.id,
                        type: "function",
                        function: FunctionCall(
                            name: invocation.name,
                            arguments: invocation.input
                        )
                    )
                    toolCalls.append(toolCall)
                @unknown default:
                    break
                }
            }

            response.content = textContent.isEmpty ? nil : textContent

            if !toolCalls.isEmpty {
                response.toolCalls = toolCalls
                response.finishReason = .toolCalls
            } else {
                response.finishReason = .stop
            }
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
                    var previousTextContent = ""
                    var accumulatedToolCalls: [ToolCall] = []

                    let stream = session.streamResponse(to: prompt, options: options)
                    for try await snapshot in stream {
                        var response = SessionResponse()

                        // Extract text content and tool invocations from segments
                        var currentTextContent = ""
                        var currentToolCalls: [ToolCall] = []

                        for segment in snapshot.segments {
                            switch segment {
                            case .text(let textSegment):
                                currentTextContent += textSegment.content
                            case .toolInvocation(let invocation):
                                let toolCall = ToolCall(
                                    id: invocation.id,
                                    type: "function",
                                    function: FunctionCall(
                                        name: invocation.name,
                                        arguments: invocation.input
                                    )
                                )
                                currentToolCalls.append(toolCall)
                            @unknown default:
                                break
                            }
                        }

                        // Send only the delta of text content
                        let textDelta = String(currentTextContent.dropFirst(previousTextContent.count))
                        if !textDelta.isEmpty {
                            response.content = textDelta
                        }

                        // Check for new tool calls
                        if currentToolCalls.count > accumulatedToolCalls.count {
                            let newToolCalls = Array(currentToolCalls.dropFirst(accumulatedToolCalls.count))
                            response.toolCalls = newToolCalls
                        }

                        previousTextContent = currentTextContent
                        accumulatedToolCalls = currentToolCalls
                        response.finishReason = nil

                        continuation.yield(response)
                    }

                    // Send final chunk with finish reason
                    var finalResponse = SessionResponse()
                    finalResponse.finishReason = accumulatedToolCalls.isEmpty ? .stop : .toolCalls
                    continuation.yield(finalResponse)

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


private func getTranscript(from messages: [Message], tools: [Tool]?) throws(RequestError) -> Transcript {
    // Note: We do not support assistant prefill (yet)
    let entries = try messages.dropLast().map { message throws(RequestError) in
        if message.role == "user" {
            return Transcript.Entry.prompt(
                Transcript.Prompt(
                    segments: [.text(Transcript.TextSegment(content: message.content ?? ""))]
                )
            )
        } else if message.role == "assistant" {
            // Handle assistant messages with or without tool calls
            var segments: [Transcript.Response.Segment] = []

            if let content = message.content, !content.isEmpty {
                segments.append(.text(Transcript.TextSegment(content: content)))
            }

            if let toolCalls = message.tool_calls {
                for toolCall in toolCalls {
                    segments.append(.toolInvocation(
                        Transcript.ToolInvocation(
                            id: toolCall.id,
                            name: toolCall.function.name,
                            input: toolCall.function.arguments
                        )
                    ))
                }
            }

            return Transcript.Entry.response(
                Transcript.Response(
                    assetIDs: [],
                    segments: segments.isEmpty ? [.text(Transcript.TextSegment(content: ""))] : segments
                )
            )
        } else if message.role == "tool" {
            // Handle tool responses
            guard let toolCallId = message.tool_call_id else {
                throw RequestError.invalidMessageRole
            }

            return Transcript.Entry.toolResult(
                Transcript.ToolResult(
                    id: toolCallId,
                    content: message.content ?? ""
                )
            )
        } else if message.role == "system" {
            // Convert tools to ToolDefinition for the transcript
            let toolDefinitions = (tools ?? []).map { tool in
                Transcript.ToolDefinition(
                    name: tool.function.name,
                    description: tool.function.description ?? "",
                    inputSchema: convertAnyCodableToString(tool.function.parameters)
                )
            }

            return Transcript.Entry.instructions(
                Transcript.Instructions(
                    segments: [.text(Transcript.TextSegment(content: message.content ?? ""))],
                    toolDefinitions: toolDefinitions
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


private func convertAnyCodableToString(_ params: [String: AnyCodable]?) -> String {
    guard let params = params else {
        return "{}"
    }

    do {
        let jsonData = try JSONEncoder().encode(params)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    } catch {
        return "{}"
    }
}
