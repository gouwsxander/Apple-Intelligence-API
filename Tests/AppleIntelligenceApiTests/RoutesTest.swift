import Testing
import VaporTesting

@testable import AppleIntelligenceApi

@Suite("Routes Tests")
struct RoutesTests {
    private func withApp(_ test: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await test(app)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Getting all models")
    func getModels() async throws {
        try await withApp { app in
            try await app.testing().test(
                .GET, "api/v1/models",
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let response = try res.content.decode(ModelsResponse.self)
                    #expect(response.object == "list")
                    #expect(!response.data.isEmpty)
                    #expect(response.data[0].id == "base")
                    #expect(response.data[0].object == "model")
                })
        }
    }
}

extension Model: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.object == rhs.object && lhs.id == rhs.id
    }
}
