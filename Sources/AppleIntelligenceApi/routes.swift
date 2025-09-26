import Vapor


func routes(_ app: Application) throws {
    app.post("api", "v1", "chat", "completions") { req async throws -> Response in
        if req.headers.contentType == nil {
            req.headers.contentType = .json
        }
        
        let requestContent = try req.content.decode(RequestContent.self)
        let responseSession = try ResponseSession(from: requestContent)
        let responseGenerator = createResponseGenerator(from: responseSession)
        return try await responseGenerator.generateResponse()
    }
}
