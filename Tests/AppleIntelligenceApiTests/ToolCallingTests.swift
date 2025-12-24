import Testing
import VaporTesting
import Foundation

@testable import AppleIntelligenceApi

@Suite("Tool Calling Tests")
struct ToolCallingTests {

    @Test("Decoding RequestContent with tools")
    func decodeRequestWithTools() async throws {
        let json = """
        {
            "model": "base",
            "messages": [
                {"role": "user", "content": "What's the weather?"}
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_weather",
                        "description": "Get the current weather",
                        "parameters": {
                            "type": "string",
                            "location": "string"
                        }
                    }
                }
            ],
            "tool_choice": "auto"
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let request = try decoder.decode(RequestContent.self, from: data)

        #expect(request.tools != nil)
        #expect(request.tools?.count == 1)
        #expect(request.tools?[0].type == "function")
        #expect(request.tools?[0].function.name == "get_weather")
        #expect(request.tools?[0].function.description == "Get the current weather")
        #expect(request.tool_choice?.type == "auto")
    }

    @Test("Decoding tool_choice as string")
    func decodeToolChoiceString() async throws {
        let json = """
        {
            "model": "base",
            "messages": [{"role": "user", "content": "test"}],
            "tool_choice": "auto"
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let request = try decoder.decode(RequestContent.self, from: data)

        #expect(request.tool_choice?.type == "auto")
        #expect(request.tool_choice?.function == nil)
    }

    @Test("Decoding tool_choice as object")
    func decodeToolChoiceObject() async throws {
        let json = """
        {
            "model": "base",
            "messages": [{"role": "user", "content": "test"}],
            "tool_choice": {
                "type": "function",
                "function": {"name": "get_weather"}
            }
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let request = try decoder.decode(RequestContent.self, from: data)

        #expect(request.tool_choice?.type == "function")
        #expect(request.tool_choice?.function?.name == "get_weather")
    }

    @Test("Decoding Message with tool_calls")
    func decodeMessageWithToolCalls() async throws {
        let json = """
        {
            "role": "assistant",
            "content": null,
            "tool_calls": [
                {
                    "id": "call_123",
                    "type": "function",
                    "function": {
                        "name": "get_weather",
                        "arguments": "{\\"location\\":\\"San Francisco\\"}"
                    }
                }
            ]
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let message = try decoder.decode(Message.self, from: data)

        #expect(message.role == "assistant")
        #expect(message.content == nil)
        #expect(message.tool_calls != nil)
        #expect(message.tool_calls?.count == 1)
        #expect(message.tool_calls?[0].id == "call_123")
        #expect(message.tool_calls?[0].type == "function")
        #expect(message.tool_calls?[0].function.name == "get_weather")
    }

    @Test("Decoding Message with tool response")
    func decodeMessageWithToolResponse() async throws {
        let json = """
        {
            "role": "tool",
            "content": "{\\"temperature\\": 72}",
            "tool_call_id": "call_123"
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let message = try decoder.decode(Message.self, from: data)

        #expect(message.role == "tool")
        #expect(message.content == "{\"temperature\": 72}")
        #expect(message.tool_call_id == "call_123")
    }

    @Test("Encoding ToolCall")
    func encodeToolCall() async throws {
        let toolCall = ToolCall(
            id: "call_456",
            type: "function",
            function: FunctionCall(
                name: "get_weather",
                arguments: "{\"location\":\"Boston\"}"
            )
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(toolCall)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("call_456"))
        #expect(jsonString.contains("get_weather"))
        #expect(jsonString.contains("Boston"))
    }

    @Test("AnyCodable encoding and decoding")
    func anyCodableTest() async throws {
        let json = """
        {
            "string": "test",
            "int": 42,
            "double": 3.14,
            "bool": true,
            "null": null,
            "array": [1, 2, 3],
            "object": {"nested": "value"}
        }
        """

        let decoder = JSONDecoder()
        let data = json.data(using: .utf8)!
        let decoded = try decoder.decode([String: AnyCodable].self, from: data)

        #expect(decoded["string"] != nil)
        #expect(decoded["int"] != nil)
        #expect(decoded["double"] != nil)
        #expect(decoded["bool"] != nil)
        #expect(decoded["null"] != nil)
        #expect(decoded["array"] != nil)
        #expect(decoded["object"] != nil)

        // Test encoding
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(decoded)
        let decodedAgain = try decoder.decode([String: AnyCodable].self, from: encodedData)

        #expect(decodedAgain.count == decoded.count)
    }

    @Test("SessionResponse with tool_calls")
    func sessionResponseWithToolCalls() async throws {
        let toolCalls = [
            ToolCall(
                id: "call_789",
                type: "function",
                function: FunctionCall(
                    name: "get_current_time",
                    arguments: "{}"
                )
            )
        ]

        let response = SessionResponse(
            content: nil,
            finishReason: .toolCalls,
            toolCalls: toolCalls
        )

        #expect(response.finishReason == .toolCalls)
        #expect(response.toolCalls != nil)
        #expect(response.toolCalls?.count == 1)
        #expect(response.toolCalls?[0].function.name == "get_current_time")
    }

    @Test("FinishReason tool_calls")
    func finishReasonToolCalls() async throws {
        let reason = FinishReason.toolCalls
        #expect(reason.rawValue == "tool_calls")
    }
}
