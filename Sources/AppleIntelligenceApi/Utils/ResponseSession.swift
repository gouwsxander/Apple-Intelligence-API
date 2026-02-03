import Foundation
import FoundationModels

let languageModels = [
    "base": SystemLanguageModel.default,
    "permissive": SystemLanguageModel(
        guardrails: .permissiveContentTransformations
    ),
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
    var responseFormat: ResponseFormat?

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
            self.session = LanguageModelSession(
                model: model,
                transcript: transcript
            )
        } else if let prompt = content.prompt {
            self.isChat = false
            self.prompt = Prompt(prompt)
            self.session = LanguageModelSession(model: model)
        } else {
            throw RequestError.noPromptOrMessages
        }

        // Get options
        self.toStream = content.stream ?? false
        self.responseFormat = content.response_format

        var samplingMode: GenerationOptions.SamplingMode?
        if let threshold = content.top_p {
            samplingMode = .random(
                probabilityThreshold: threshold,
                seed: content.seed
            )
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
            if let format = responseFormat, format.type == "json_schema",
                let schema = format.json_schema
            {
                if let rootProperty = schema.schema {
                    // Dynamic schema
                    let dynamicSchema = convertToDynamicSchema(
                        name: schema.name,
                        property: rootProperty
                    )
                    let generationSchema = try GenerationSchema(
                        root: dynamicSchema,
                        dependencies: []
                    )
                    let result = try await self.session.respond(
                        to: self.prompt,
                        schema: generationSchema,
                        options: self.options
                    )

                    // GeneratedContent doesn't conform to Encodable easily, so we build a dictionary
                    let dict = try convertGeneratedContentToAny(
                        result.content,
                        schema: rootProperty
                    )
                    let data = try JSONSerialization.data(withJSONObject: dict)
                    response.content = String(data: data, encoding: .utf8)
                } else {
                    response.content =
                        "Error: No schema provided in json_schema."
                    response.finishReason = .error
                    return response
                }
            } else {
                // Standard generation
                response.content = try await self.session.respond(
                    to: self.prompt,
                    options: self.options
                ).content
            }
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
        let responseFormat = self.responseFormat

        return AsyncStream { continuation in
            Task { @Sendable in
                do {
                    if let format = responseFormat,
                        format.type == "json_schema",
                        let schema = format.json_schema,
                        let rootProperty = schema.schema
                    {
                        // Snapshot streaming for dynamic schema
                        let dynamicSchema = convertToDynamicSchema(
                            name: schema.name,
                            property: rootProperty
                        )
                        let generationSchema = try GenerationSchema(
                            root: dynamicSchema,
                            dependencies: []
                        )
                        let stream = session.streamResponse(
                            to: prompt,
                            schema: generationSchema,
                            options: options
                        )

                        for try await snapshot in stream {
                            var response = SessionResponse()
                            // Snapshot for dynamic schema is also GeneratedContent (or similar)
                            let dict = try convertGeneratedContentToAny(
                                snapshot.content,
                                schema: rootProperty
                            )
                            let data = try JSONSerialization.data(
                                withJSONObject: dict
                            )
                            response.content = String(
                                data: data,
                                encoding: .utf8
                            )
                            response.finishReason = nil
                            continuation.yield(response)
                        }
                    } else {
                        // Standard streaming
                        var previousSnapshotContent = ""
                        let stream = session.streamResponse(
                            to: prompt,
                            options: options
                        )
                        for try await snapshot in stream {
                            var response = SessionResponse()
                            response.content = String(
                                snapshot.content.dropFirst(
                                    previousSnapshotContent.count
                                )
                            )
                            response.finishReason = nil

                            previousSnapshotContent = snapshot.content

                            continuation.yield(response)
                        }
                    }

                    // Send final chunk
                    continuation.yield(
                        SessionResponse(content: "", finishReason: .stop)
                    )

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

private func convertToDynamicSchema(name: String, property: JSONSchemaProperty)
    -> DynamicGenerationSchema
{
    switch property {
    case .string(_, _):
        return DynamicGenerationSchema(type: String.self, guides: [])

    case .integer(_, _, _):
        return DynamicGenerationSchema(type: Int.self, guides: [])

    case .number(_, _, _):
        return DynamicGenerationSchema(type: Double.self, guides: [])

    case .boolean(_):
        return DynamicGenerationSchema(type: Bool.self, guides: [])

    case .array(_, let items):
        let itemSchema = convertToDynamicSchema(name: "item", property: items)
        return DynamicGenerationSchema(arrayOf: itemSchema)

    case .object(let description, let properties, _):
        let dynamicProperties = properties.map { (key, value) in
            DynamicGenerationSchema.Property(
                name: key,
                schema: convertToDynamicSchema(name: key, property: value)
            )
        }
        return DynamicGenerationSchema(
            name: name,
            description: description,
            properties: dynamicProperties
        )
    }
}

// Helper to convert GeneratedContent to a JSON-compatible value guided by the schema
private func convertGeneratedContentToAny(
    _ content: GeneratedContent,
    schema: JSONSchemaProperty
) throws -> Any {
    switch schema {
    case .object(_, let properties, _):
        var dict = [String: Any]()
        for (key, propertySchema) in properties {
            if let value = try? content.value(String.self, forProperty: key) {
                dict[key] = value
            } else if let value = try? content.value(Int.self, forProperty: key)
            {
                dict[key] = value
            } else if let value = try? content.value(
                Double.self,
                forProperty: key
            ) {
                dict[key] = value
            } else if let value = try? content.value(
                Bool.self,
                forProperty: key
            ) {
                dict[key] = value
            } else if let value = try? content.value(
                GeneratedContent.self,
                forProperty: key
            ) {
                dict[key] = try convertGeneratedContentToAny(
                    value,
                    schema: propertySchema
                )
            } else if let value = try? content.value(
                [GeneratedContent].self,
                forProperty: key
            ) {
                if case .array(_, let itemSchema) = propertySchema {
                    dict[key] = try value.map {
                        try convertGeneratedContentToAny($0, schema: itemSchema)
                    }
                } else {
                    dict[key] = value.map { "\($0)" }
                }
            } else if let value = try? content.value(
                [String].self,
                forProperty: key
            ) {
                dict[key] = value
            } else if let value = try? content.value(
                [Int].self,
                forProperty: key
            ) {
                dict[key] = value
            } else if let value = try? content.value(
                [Double].self,
                forProperty: key
            ) {
                dict[key] = value
            } else if let value = try? content.value(
                [Bool].self,
                forProperty: key
            ) {
                dict[key] = value
            }
        }
        return dict

    case .array(_, let itemSchema):
        // If the content itself is an array (e.g. from arrayOf)
        if let value = try? content.value([String].self) {
            return value
        } else if let value = try? content.value([Int].self) {
            return value
        } else if let value = try? content.value([Double].self) {
            return value
        } else if let value = try? content.value([Bool].self) {
            return value
        } else if let value = try? content.value([GeneratedContent].self) {
            return try value.map {
                try convertGeneratedContentToAny($0, schema: itemSchema)
            }
        }
        return []

    case .string:
        return (try? content.value(String.self)) ?? ""
    case .integer:
        return (try? content.value(Int.self)) ?? 0
    case .number:
        return (try? content.value(Double.self)) ?? 0.0
    case .boolean:
        return (try? content.value(Bool.self)) ?? false
    }
}

private func handleError(_ error: any Error, _ response: inout SessionResponse)
{
    if let genError = error as? LanguageModelSession.GenerationError {
        switch genError {
        case .exceededContextWindowSize:
            response.finishReason = .length
            response.content = "Error: Exceeded context window size."
        case .guardrailViolation:
            response.finishReason = .contentFilter
            response.content = "Error: Guardrail violation."
        default:
            response.finishReason = .error
            response.content = "Error: Generation error (\(genError))"
        }
    } else {
        response.finishReason = .error
        response.content =
            "Error: \(error.localizedDescription) (\(type(of: error)))"
    }
}

private func getTranscript(from messages: [Message]) throws(RequestError)
    -> Transcript
{
    // Note: We do not support assistant prefill (yet)
    let entries = try messages.dropLast().map { message throws(RequestError) in
        if message.role == "user" {
            return Transcript.Entry.prompt(
                Transcript.Prompt(
                    segments: [
                        .text(Transcript.TextSegment(content: message.content))
                    ]
                )
            )
        } else if message.role == "assistant" {
            return Transcript.Entry.response(
                Transcript.Response(
                    assetIDs: [],
                    segments: [
                        .text(Transcript.TextSegment(content: message.content))
                    ]
                )
            )
        } else if message.role == "system" {
            return Transcript.Entry.instructions(
                Transcript.Instructions(
                    segments: [
                        .text(Transcript.TextSegment(content: message.content))
                    ],
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
