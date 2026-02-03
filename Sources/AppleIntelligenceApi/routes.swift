import Vapor

func routes(_ app: Application) throws {
    app.group("api", "v1") { api in
        // Chat completions endpoint
        api.post("chat", "completions") { req async throws -> Response in
            if req.headers.contentType == nil {
                req.headers.contentType = .json
            }

            let requestContent = try req.content.decode(RequestContent.self)
            let responseSession = try ResponseSession(from: requestContent)
            let responseGenerator = createResponseGenerator(
                from: responseSession
            )
            return try await responseGenerator.generateResponse()
        }

        // Models list endpoint
        api.get("models") { req async throws -> ModelsResponse in
            let models = [
                Model(id: "base"),
                Model(id: "permissive"),
            ]
            return ModelsResponse(data: models)
        }
    }
}
