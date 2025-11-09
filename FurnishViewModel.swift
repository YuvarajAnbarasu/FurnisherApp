import Foundation
import SwiftUI
import Combine

@MainActor
class FurnishViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var furnitureItems: [FurnitureItemForPlacement] = []
    @Published var scanId: String?
    @Published var errorMessage: String?

    private let api = FurnisherAPI.shared

    // Generate design with room type and budget
    func generateDesign(fromRoomURL roomURL: URL, roomType: String = "bedroom", budget: String = "5000") async {
        isLoading = true
        errorMessage = nil
        furnitureItems = []
        scanId = nil

        print("🎨 Starting design generation...")
        print("   Room: \(roomURL.lastPathComponent)")
        print("   Type: \(roomType)")
        print("   Budget: $\(budget)")

        do {
            let response = try await api.sendRoomScan(
                usdzURL: roomURL,
                roomType: roomType,
                budget: budget
            )
            
            // Convert simplified response to placement items
            scanId = response.scanId
            furnitureItems = response.furniture.map { FurnitureItemForPlacement(from: $0) }

            print("✅ Design generated successfully")
            print("   Scan ID: \(response.scanId)")
            print("   Furniture items: \(furnitureItems.count)")
            
            for item in furnitureItems {
                print("   - \(item.name)")
            }

        } catch let error as FurnisherAPIError {
            errorMessage = error.localizedDescription
            print("❌ API Error: \(error)")
        } catch {
            errorMessage = "Unexpected error: \(error.localizedDescription)"
            print("❌ Unexpected Error: \(error)")
        }

        isLoading = false
    }

    func clearResult() {
        furnitureItems = []
        scanId = nil
        errorMessage = nil
    }
}
