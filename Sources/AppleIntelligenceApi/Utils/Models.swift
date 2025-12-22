import Vapor

struct Model: Content {
    var object: String = "model"
    var id: String
}

struct ModelsResponse: Content {
    var object: String = "list"
    var data: [Model]
}
