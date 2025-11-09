import Foundation
import UIKit

// MARK: - User Preferences
struct UserPreferences: Codable {
    var budget: Int
    var selectedColors: [String]
    var style: String
    var roomType: String

    init(budget: Int = 5000, selectedColors: [String] = [], style: String = "", roomType: String = "") {
        self.budget = budget
        self.selectedColors = selectedColors
        self.style = style
        self.roomType = roomType
    }
}

// MARK: - 3D Placement Data
struct Placement: Codable {
    let position: Position
    let rotation: Rotation
    let scale: Scale

    struct Position: Codable {
        let x: Double
        let y: Double
        let z: Double
    }

    struct Rotation: Codable {
        let x: Double
        let y: Double
        let z: Double
    }

    struct Scale: Codable {
        let x: Double
        let y: Double
        let z: Double
    }
}

// MARK: - Furniture Item
struct FurnitureItem: Codable, Identifiable {
    let id: UUID
    let name: String
    let price: Double
    let url: String
    let imageUrl: String
    let modelUrlUsdz: String?
    let placement: Placement?
    let description: String?

    init(id: UUID = UUID(), name: String, price: Double, url: String, imageUrl: String, modelUrlUsdz: String? = nil, placement: Placement? = nil, description: String? = nil) {
        self.id = id
        self.name = name
        self.price = price
        self.url = url
        self.imageUrl = imageUrl
        self.modelUrlUsdz = modelUrlUsdz
        self.placement = placement
        self.description = description
    }
}

// MARK: - Room Model (NEW!)
struct RoomModel: Codable {
    let roomModelUrlUsdz: String  // 3D model of the room itself
    let dimensions: RoomDimensions?

    struct RoomDimensions: Codable {
        let width: Double
        let height: Double
        let depth: Double
    }
}

// MARK: - Generated Design (UPDATED with room model)
struct GeneratedDesign: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let sceneId: String?
    let roomModel: RoomModel?  // NEW: 3D model of the room
    let furniture: [FurnitureItem]

    init(id: UUID = UUID(), timestamp: Date = Date(), sceneId: String? = nil, roomModel: RoomModel? = nil, furniture: [FurnitureItem]) {
        self.id = id
        self.timestamp = timestamp
        self.sceneId = sceneId
        self.roomModel = roomModel
        self.furniture = furniture
    }

    var totalCost: Double {
        furniture.reduce(0) { $0 + $1.price }
    }
}

// MARK: - Furnished Response (UPDATED)
struct FurnishedResponse {
    let sceneId: String
    let roomModel: RoomModel?  // NEW
    let furniture: [FurnitureItem]
}

// MARK: - API Response Models (UPDATED)
struct APIFurnishedResponse: Codable {
    let sceneId: String
    let roomModel: APIRoomModel?  // NEW
    let furnitureItems: [APIFurnitureItem]

    enum CodingKeys: String, CodingKey {
        case sceneId = "scene_id"
        case roomModel = "room_model"
        case furnitureItems = "furniture_items"
    }
}

// NEW: Room model from API
struct APIRoomModel: Codable {
    let roomModelUrlUsdz: String
    let dimensions: APIDimensions?

    enum CodingKeys: String, CodingKey {
        case roomModelUrlUsdz = "room_model_url_usdz"
        case dimensions
    }

    func toRoomModel() -> RoomModel {
        RoomModel(
            roomModelUrlUsdz: roomModelUrlUsdz,
            dimensions: dimensions?.toDimensions()
        )
    }
}

struct APIDimensions: Codable {
    let width: Double
    let height: Double
    let depth: Double

    func toDimensions() -> RoomModel.RoomDimensions {
        RoomModel.RoomDimensions(width: width, height: height, depth: depth)
    }
}

struct APIFurnitureItem: Codable {
    let itemId: String
    let name: String
    let price: Double
    let shopUrl: String
    let imageUrl: String?
    let modelUrlUsdz: String
    let description: String?
    let placement: APIPlacement

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case name
        case price
        case shopUrl = "shop_url"
        case imageUrl = "image_url"
        case modelUrlUsdz = "model_url_usdz"
        case description
        case placement
    }

    func toFurnitureItem() -> FurnitureItem {
        FurnitureItem(
            name: name,
            price: price,
            url: shopUrl,
            imageUrl: imageUrl ?? "",
            modelUrlUsdz: modelUrlUsdz,
            placement: placement.toPlacement(),
            description: description
        )
    }
}

struct APIPlacement: Codable {
    let position: APIPosition
    let rotation: APIRotation
    let scale: APIScale

    func toPlacement() -> Placement {
        Placement(
            position: Placement.Position(x: position.x, y: position.y, z: position.z),
            rotation: Placement.Rotation(x: rotation.x, y: rotation.y, z: rotation.z),
            scale: Placement.Scale(x: scale.x, y: scale.y, z: scale.z)
        )
    }
}

struct APIPosition: Codable {
    let x: Double
    let y: Double
    let z: Double
}

struct APIRotation: Codable {
    let x: Double
    let y: Double
    let z: Double
}

struct APIScale: Codable {
    let x: Double
    let y: Double
    let z: Double
}
