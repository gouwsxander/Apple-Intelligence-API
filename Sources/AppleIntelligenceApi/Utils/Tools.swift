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

// basically `Decodable`, with an extra parameter
extension FunctionTool {
    enum CodingKeys: String, CodingKey {
        case name, description, parameters
    }

    init(
        from decoder: any Decoder,
        _ onCall: @escaping @Sendable (Arguments) async -> Output
    ) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedName = try container.decode(String.self, forKey: .name)
        let decodedDescription = try container.decode(
            String.self,
            forKey: .description
        )

        guard
            case .object(
                let parametersDescription,
                let properties,
                required: let requiredProperties
            ) = try container.decode(
                JSONSchemaProperty.self,
                forKey: .parameters
            )
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .parameters,
                in: container,
                debugDescription: "Expected object"
            )
        }

        let generationSchemaProperties = properties.map { name, prop in
            let description = {
                switch prop {
                case .array(let description, _),
                    .boolean(let description),
                    .integer(let description, _, _),
                    .number(let description, _, _),
                    .object(let description, _, _),
                    .string(let description, _):
                    return description
                }
            }()

            return DynamicGenerationSchema.Property(
                name: name,
                description: description,
                schema: Self.createGenerationSchema(from: prop, with: name),
                isOptional: requiredProperties?.contains(name) == false
            )
        }

        let parametersSchema: GenerationSchema
        do {
            parametersSchema = try GenerationSchema.init(
                root:
                    DynamicGenerationSchema(
                        name: "\(decodedName)_parameters",
                        description: parametersDescription,
                        properties: generationSchemaProperties
                    ),
                dependencies: []
            )
        } catch let error as GenerationSchema.SchemaError {
            fatalError("Unexpected error: \(error)")
        }

        // Assign to self only after all locals are ready
        self.name = decodedName
        self.description = decodedDescription
        self.parameters = parametersSchema
        self.onCall = onCall
    }

    static func createGenerationSchema(
        from json: JSONSchemaProperty,
        with name: String
    ) -> DynamicGenerationSchema {
        switch json {
        case .array(_, items: let item):
            return .init(
                arrayOf: Self.createGenerationSchema(from: item, with: name)
            )
        case .boolean(_):
            return .init(type: Bool.self)
        case .integer(_, let minimum, let maximum):
            return .init(
                type: Int.self,
                guides: [
                    minimum.map(GenerationGuide.minimum),
                    maximum.map(GenerationGuide.maximum),
                ]
                .compactMap(\.self)
            )
        case .number(_, let minimum, let maximum):
            return .init(
                type: Double.self,
                guides: [
                    minimum.map(GenerationGuide.minimum),
                    maximum.map(GenerationGuide.maximum),
                ]
                .compactMap(\.self)
            )
        case .object(
            let description,
            let properties,
            required: let requiredProperties
        ):
            return .init(
                name: name,
                properties: properties.map { key, prop in
                    let description = {
                        switch prop {
                        case .array(let description, _),
                            .boolean(let description),
                            .integer(let description, _, _),
                            .number(let description, _, _),
                            .object(let description, _, _),
                            .string(let description, _):
                            return description
                        }
                    }()

                    return DynamicGenerationSchema.Property(
                        name: key,
                        description: description,
                        schema: Self.createGenerationSchema(
                            from: prop,
                            with: key
                        ),
                        isOptional: requiredProperties?.contains(key) == false
                    )
                }
            )
        case .string(_, enumValues: let possibleValues):
            return .init(
                type: String.self,
                guides: [possibleValues.map(GenerationGuide.anyOf)]
                    .compactMap(\.self)
            )
        }
    }
}
