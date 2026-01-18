import Foundation
import Vapor


private func jsonify(_ obj: Any) throws(ResponseError) -> String {
    do {
        let jsonData = try JSONSerialization.data(withJSONObject: obj)
        return String(data: jsonData, encoding: .utf8)!
    } catch {
        throw .serializationError("Failed to serialize JSON for response.")
    }
}


protocol ResponseGenerator {
    var session: ResponseSession { get }
    
    init(from session: ResponseSession)
    func generateResponse() async throws(ResponseError) -> Response
}


extension ResponseGenerator {
    fileprivate func makeResponseData(with choices: [[String: Any?]]) -> [String: Any] {
        return [
            "id": "gen-\(UUID().uuidString)",
            "object": self.session.toStream ? "chat.completion.chunk" : "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": self.session.modelName,
            "choices": choices
        ]
    }
}


func createResponseGenerator(from session: ResponseSession) -> any ResponseGenerator {
    if session.toStream {
        return StreamingResponseGenerator(from: session)
    } else {
        return StandardResponseGenerator(from: session)
    }
}


class StandardResponseGenerator: ResponseGenerator {
    let session: ResponseSession
    required init(from session: ResponseSession) {
        self.session = session
    }
    
    func generateResponse() async throws(ResponseError) -> Response {
        let sessionResponse = await session.getResponse()
        
        let choices = [self.makeChoice(from: sessionResponse)]
        let responseData = self.makeResponseData(with: choices)
        
        let response = Response(status: .ok, body: Response.Body(string: try jsonify(responseData)))
        response.headers.contentType = .json
        
        return response
    }
    
    private func makeNonChatChoice(from sessionResponse: SessionResponse) -> [String: Any?] {
        return [
            "finish_reason": sessionResponse.finishReason?.rawValue,
            "text": sessionResponse.content
        ]
    }
    
    private func makeChatChoice(from sessionResponse: SessionResponse) -> [String: Any?] {
        return [
            "finish_reason": sessionResponse.finishReason?.rawValue,
            "native_finish_reason": sessionResponse.finishReason?.rawValue,
            "message": [
                "content": sessionResponse.content,
                "role": "assistant",
            ]
        ]
    }
    
    private func makeChoice(from sessionResponse: SessionResponse) -> [String: Any?] {
        if self.session.isChat {
            return makeChatChoice(from: sessionResponse)
        } else {
            return makeNonChatChoice(from: sessionResponse)
        }
    }
}


class StreamingResponseGenerator: ResponseGenerator, @unchecked Sendable {

    let session: ResponseSession
    required init(from session: ResponseSession) {
        self.session = session
    }
    
    func generateResponse() async throws(ResponseError) -> Response {
        let response = Response()
        response.status = .ok
        response.headers.contentType = .init(type: "text", subType: "event-stream")
        response.headers.cacheControl = .init(noCache: true)
        response.headers.add(name: "Connection", value: "keep-alive")
        response.headers.add(name: "Access-Control-Allow-Origin", value: "*")
        
        let stream = self.session.streamResponses()
        
        response.body = .init(asyncStream: { writer in
            for await streamResponse in stream {
                let choices = [self.makeChoice(from: streamResponse)]
                let responseData = self.makeResponseData(with: choices)
                
                try await writer.write(.buffer(ByteBuffer(string: "data: \(try jsonify(responseData))\n\n")))
            }

            try await writer.write(.buffer(ByteBuffer(string: "data: [DONE]\n\n")))
            try await writer.write(.end)
        })
        
        return response
    }
    
    private func makeChoice(from sessionResponse: SessionResponse) -> [String: Any?] {
        return [
            "finish_reason": sessionResponse.finishReason?.rawValue,
            "native_finish_reason": sessionResponse.finishReason?.rawValue,
            "delta": [
                "content": sessionResponse.content,
                "role": "assistant",
            ]
        ]
    }
}
