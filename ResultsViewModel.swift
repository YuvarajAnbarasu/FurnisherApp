import Foundation
import SwiftUI
import Combine

@MainActor
class ResultsViewModel: ObservableObject {
    @Published var designs: [GeneratedDesign] = []
    @Published var isLoading = false

    private let storage = StorageManager.shared

    init() {
        loadDesigns()
    }

    func loadDesigns() {
        isLoading = true
        designs = storage.loadAllDesigns()
        isLoading = false
    }

    func deleteDesign(_ design: GeneratedDesign) {
        do {
            try storage.deleteDesign(id: design.id)
            loadDesigns()
        } catch {
            print("❌ Failed to delete design: \(error)")
        }
    }

    func deleteAllDesigns() {
        do {
            try storage.deleteAllDesigns()
            loadDesigns()
        } catch {
            print("❌ Failed to delete all designs: \(error)")
        }
    }
}
