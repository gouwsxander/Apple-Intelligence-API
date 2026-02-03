import Foundation
import FoundationModels

extension FunctionTool: DecodableWithConfiguration {

    typealias DecodingConfiguration = Callback

    enum CodingKeys: String, CodingKey {
        case name, description, parameters
    }

    init(
        from decoder: any Decoder,
        configuration callback: @escaping DecodingConfiguration
    ) throws(Self.Error) {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let functionName = try container.decode(String.self, forKey: .name)
            let functionDescription = try container.decode(
                String.self,
                forKey: .description
            )

            guard
                case .object(
                    _,
                    properties: let parameters,
                    required: let requiredProperties
                ) = try container.decode(
                    JSONSchemaProperty.self,
                    forKey: .parameters
                )
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .parameters,
                    in: container,
                    debugDescription: "Expected object for parameters"
                )
            }

            let schemaParameters = parameters.map { parameterName, parameter in
                return DynamicGenerationSchema.Property(
                    name: parameterName,
                    description: parameter.description,
                    schema: Self.createGenerationSchema(
                        from: parameter,
                        named:
                            "\(functionName)_parameter_\(parameterName)_schema"

                    ),
                    isOptional: requiredProperties?.contains(parameterName)
                        == false
                )
            }

            let parametersSchema = try GenerationSchema(
                root:
                    DynamicGenerationSchema(
                        name: "\(functionName)_parameters_schema",
                        properties: schemaParameters
                    ),
                dependencies: []
            )

            self.name = functionName
            self.description = functionDescription
            self.parameters = parametersSchema
            self.callback = callback
        } catch let error as DecodingError {
            throw Self.Error(from: error)
        } catch let error as GenerationSchema.SchemaError {
            throw Self.Error(from: error)
        } catch let error {
            fatalError("Unexpected error: \(error)")
        }
    }

    static func createGenerationSchema(
        from json: JSONSchemaProperty,
        named name: String,
    ) -> DynamicGenerationSchema {
        let schema: DynamicGenerationSchema

        switch json {
        case .array(_, items: let item):
            schema =
                .init(
                    arrayOf: Self.createGenerationSchema(
                        from: item,
                        named: name.replacing(/(_schema)$/) { match in
                            "_items" + match.output.1
                        },

                    )
                )

        case .boolean(_):
            schema = .init(type: Bool.self)
        case .integer(_, let minimum, let maximum):
            schema =
                .init(
                    type: Int.self,
                    guides: [
                        minimum.map(GenerationGuide.minimum),
                        maximum.map(GenerationGuide.maximum),
                    ]
                    .compactMap(\.self)
                )
        case .number(_, let minimum, let maximum):
            schema = .init(
                type: Double.self,
                guides: [
                    minimum.map(GenerationGuide.minimum),
                    maximum.map(GenerationGuide.maximum),
                ]
                .compactMap(\.self)
            )
        case .object(
            _,
            let properties,
            required: let requiredProperties
        ):
            schema =
                .init(
                    name: name,
                    properties: properties.map { key, prop in
                        return DynamicGenerationSchema.Property(
                            name: key,
                            description: prop.description,
                            schema: Self.createGenerationSchema(
                                from: prop,
                                named: name.replacing(/(_schema)$/) { match in
                                    "_property_\(key)" + match.output.1
                                }
                            ),
                            isOptional: requiredProperties?.contains(key)
                                == false
                        )
                    }
                )
        case .string(_, enumValues: let possibleValues):
            schema = .init(
                type: String.self,
                guides: [possibleValues.map(GenerationGuide.anyOf)]
                    .compactMap(\.self)
            )
        }

        return schema
    }
}
