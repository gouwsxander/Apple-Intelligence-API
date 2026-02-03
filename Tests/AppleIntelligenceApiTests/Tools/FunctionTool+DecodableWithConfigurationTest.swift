import Foundation
import FoundationModels
import Testing

@testable import AppleIntelligenceApi

@Suite("Function Tool Decoding")
struct FunctionToolDecodingTests {

    func expect(parameters expected: DynamicGenerationSchema, from json: String)
    {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let actualString = String(
            decoding: try! encoder.encode(
                try! decoder.decode(
                    FunctionTool.self,
                    from: json.data(using: .utf8)!,
                    configuration: { _ in
                        return "you successfully called this tool!"
                            .generatedContent
                    }
                ).parameters
            ),
            as: UTF8.self
        )

        let expectedString = String(
            decoding: try! encoder.encode(
                GenerationSchema(root: expected, dependencies: [])
            ),
            as: UTF8.self
        )

        #expect(expectedString == actualString)
    }

    @Test("parameter: array") func decodeToolArrayParam() {
        expect(
            parameters: DynamicGenerationSchema(
                name: "function1_parameters_schema",
                properties: [
                    DynamicGenerationSchema.Property(
                        name: "param1",
                        description: "integer array",
                        schema: DynamicGenerationSchema(
                            arrayOf: DynamicGenerationSchema(
                                type: Int.self,
                                guides: [.minimum(1), .maximum(5)]
                            ),

                        ),
                        isOptional: false
                    )
                ]
            ),
            from: """
                {
                    "type": "function",
                    "name": "function1",
                    "description": "function1_description",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "param1": {
                                "type": "array",
                                "description": "integer array",
                                "items": {
                                    "type": "integer",
                                    "minimum": 1,
                                    "maximum": 5
                                }
                            }
                        }
                    }
                }
                """
        )
    }
    @Test("parameter: boolean") func decodeToolBoolParam() {
        expect(
            parameters: DynamicGenerationSchema(
                name: "function1_parameters_schema",
                properties: [
                    DynamicGenerationSchema.Property(
                        name: "param1",
                        description: "boolean",
                        schema: DynamicGenerationSchema(type: Bool.self),
                        isOptional: false
                    )
                ]
            ),
            from: """
                {
                    "type": "function",
                    "name": "function1",
                    "description": "function1_description",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "param1": {
                                "type": "boolean",
                                "description": "boolean"
                            }
                        },
                        "required": [
                            "param1"
                        ]
                    }
                }
                """
        )
    }

    @Test("parameter: integer") func decodeToolIntParam() {
        expect(
            parameters: DynamicGenerationSchema(
                name: "function1_parameters_schema",
                properties: [
                    DynamicGenerationSchema.Property(
                        name: "param1",
                        description: "integer",
                        schema: DynamicGenerationSchema(
                            type: Int.self,
                            guides: [.minimum(1), .maximum(5)]
                        ),
                        isOptional: false
                    )
                ]
            ),
            from: """
                {
                    "type": "function",
                    "name": "function1",
                    "description": "function1_description",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "param1": {
                                "type": "integer",
                                "description": "integer",
                                "minimum": 1,
                                "maximum": 5
                            }
                        }
                    }
                }
                """
        )
    }

    @Test("parameter: number") func decodeToolNumberParam() {
        expect(
            parameters: DynamicGenerationSchema(
                name: "function1_parameters_schema",
                properties: [
                    DynamicGenerationSchema.Property(
                        name: "param1",
                        description: "number",
                        schema: DynamicGenerationSchema(
                            type: Double.self,
                            guides: [.minimum(1.0), .maximum(5.0)]
                        ),
                        isOptional: false
                    )
                ]
            ),
            from: """
                {
                    "type": "function",
                    "name": "function1",
                    "description": "function1_description",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "param1": {
                                "type": "number",
                                "description": "number",
                                "minimum": 1.0,
                                "maximum": 5.0
                            }
                        }
                    }
                }
                """
        )
    }

    @Test("parameter: object") func decodeToolObjectParam() {
        expect(
            parameters: DynamicGenerationSchema(
                name: "function1_parameters_schema",
                properties: [
                    DynamicGenerationSchema.Property(
                        name: "param1",
                        description: "object",
                        schema: DynamicGenerationSchema(
                            name: "function1_parameter_param1_schema",
                            properties: [
                                DynamicGenerationSchema.Property(
                                    name: "prop1",
                                    description: "object.string",
                                    schema: DynamicGenerationSchema(
                                        type: String.self,
                                        guides: []
                                    ),
                                    isOptional: false
                                )
                            ]
                        ),
                        isOptional: false
                    )
                ]
            ),
            from: """
                {
                    "type": "function",
                    "name": "function1",
                    "description": "description",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "param1": {
                                "type": "object",
                                "description": "object",
                                "properties": {
                                    "prop1": {
                                        "type": "string",
                                        "description": "object.string"
                                    }
                                },
                                "required": [
                                    "prop1"
                                ]
                            }
                        },
                        "required":[
                            "param1"
                        ]
                    }
                }
                """
        )
    }
}
