import SwiftUI

// MARK: - Main Integration View
struct FurnitureDesignFlow: View {
    @State private var roomScanURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var furnitureItems: [FurnitureItemForPlacement] = []
    @State private var showARPlacement = false
    @State private var scanId: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isLoading {
                    LoadingView()
                } else if !furnitureItems.isEmpty {
                    SuccessView(
                        itemCount: furnitureItems.count,
                        onViewInAR: { showARPlacement = true }
                    )
                } else {
                    InitialView(
                        onSelectRoomScan: selectRoomScan,
                        hasError: errorMessage != nil,
                        errorMessage: errorMessage
                    )
                }
            }
            .navigationTitle("Furniture AR")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showARPlacement) {
                ARPlacementContainer(furnitureItems: furnitureItems)
            }
        }
    }
    
    // MARK: - Select Room Scan
    private func selectRoomScan() {
        // In a real app, you'd use UIDocumentPickerViewController
        // For now, simulate with a test file
        // This would be replaced with actual file picker logic
        
        // Example: If you have a test USDZ file
        // roomScanURL = Bundle.main.url(forResource: "room_scan", withExtension: "usdz")
        // generateDesign()
        
        // For demo purposes, show file picker would go here
        print("📂 Open file picker to select room scan USDZ")
        
        // Simulated selection - replace with actual picker
        simulateFileSelection()
    }
    
    // MARK: - Simulate File Selection (Replace with real picker)
    private func simulateFileSelection() {
        // This is just a placeholder
        // In production, use UIDocumentPickerViewController
        
        let alert = UIAlertController(
            title: "File Picker",
            message: "In production, this would open a file picker to select your room scan USDZ file",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let viewController = windowScene.windows.first?.rootViewController {
            viewController.present(alert, animated: true)
        }
    }
    
    // MARK: - Generate Design
    func generateDesign(roomType: String = "bedroom", budget: String = "5000") {
        guard let url = roomScanURL else {
            errorMessage = "No room scan selected"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                print("🚀 Sending room scan to server...")
                let response = try await FurnisherAPI.shared.sendRoomScan(
                    usdzURL: url,
                    roomType: roomType,
                    budget: budget
                )
                
                await MainActor.run {
                    scanId = response.scanId
                    furnitureItems = response.furniture.map { FurnitureItemForPlacement(from: $0) }
                    isLoading = false
                    
                    print("✅ Received \(furnitureItems.count) furniture items")
                }
                
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    print("❌ Error: \(error)")
                }
            }
        }
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Generating Design...")
                .font(.headline)
            
            Text("This may take a minute")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Initial View
struct InitialView: View {
    let onSelectRoomScan: () -> Void
    let hasError: Bool
    let errorMessage: String?
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "cube.box.fill")
                .font(.system(size: 80))
                .foregroundColor(.purple)
            
            Text("Furniture AR Design")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Upload your room scan to get AI-generated furniture recommendations")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            if hasError, let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Button(action: onSelectRoomScan) {
                HStack {
                    Image(systemName: "doc.badge.plus")
                    Text("Select Room Scan")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: 250)
                .background(Color.purple)
                .cornerRadius(15)
            }
        }
        .padding()
    }
}

// MARK: - Success View
struct SuccessView: View {
    let itemCount: Int
    let onViewInAR: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Design Ready!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("We found \(itemCount) furniture \(itemCount == 1 ? "item" : "items") for your room")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            Button(action: onViewInAR) {
                HStack {
                    Image(systemName: "arkit")
                    Text("View in AR")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: 250)
                .background(Color.purple)
                .cornerRadius(15)
            }
        }
        .padding()
    }
}

// MARK: - Preview
struct FurnitureDesignFlow_Previews: PreviewProvider {
    static var previews: some View {
        FurnitureDesignFlow()
    }
}
