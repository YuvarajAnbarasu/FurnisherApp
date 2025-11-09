import SwiftUI
import RealityKit
import ARKit
import Combine

struct ARPlacementView: UIViewRepresentable {
    let furnitureItems: [FurnitureItemForPlacement]
    @Binding var selectedItemIndex: Int?
    @Binding var placedItems: [String: ModelEntity]  // furniture ID -> placed entity
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // ARKit Configuration
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        arView.session.run(config)
        
        // Add coaching overlay to help users scan the room
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(coachingOverlay)
        
        // Setup gesture recognizers
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        context.coordinator.arView = arView
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update coordinator with latest data
        context.coordinator.furnitureItems = furnitureItems
        context.coordinator.selectedItemIndex = selectedItemIndex
        context.coordinator.placedItems = placedItems
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(selectedItemIndex: $selectedItemIndex, placedItems: $placedItems)
    }
    
    class Coordinator: NSObject {
        weak var arView: ARView?
        var furnitureItems: [FurnitureItemForPlacement] = []
        var selectedItemIndex: Int?
        var placedItems: [String: ModelEntity] = [:]
        var loadingCache: [String: ModelEntity] = [:]  // Cache loaded models
        var cancellables = Set<AnyCancellable>()
        
        @Binding var selectedItemIndexBinding: Int?
        @Binding var placedItemsBinding: [String: ModelEntity]
        
        init(selectedItemIndex: Binding<Int?>, placedItems: Binding<[String: ModelEntity]>) {
            self._selectedItemIndexBinding = selectedItemIndex
            self._placedItemsBinding = placedItems
        }
        
        // MARK: - Tap Gesture Handler
        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView = arView,
                  let selectedIndex = selectedItemIndex,
                  selectedIndex < furnitureItems.count else {
                print("⚠️ No item selected or invalid index")
                return
            }
            
            let item = furnitureItems[selectedIndex]
            let location = recognizer.location(in: arView)
            
            // Perform raycast to find placement location
            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
            
            guard let firstResult = results.first else {
                print("⚠️ No surface found")
                return
            }
            
            // Place the furniture
            Task { @MainActor in
                await placeFurniture(item: item, at: firstResult.worldTransform)
            }
        }
        
        // MARK: - Place Furniture
        @MainActor
        private func placeFurniture(item: FurnitureItemForPlacement, at transform: simd_float4x4) async {
            print("🪑 Placing: \(item.name)")
            
            // Check if already loaded in cache
            if let cachedEntity = loadingCache[item.id] {
                addEntityToScene(cachedEntity.clone(recursive: true), at: transform, for: item)
                return
            }
            
            // Load the model
            guard let modelURL = URL(string: item.modelUrlUsdz) else {
                print("❌ Invalid URL for \(item.name)")
                return
            }
            
            do {
                print("📦 Loading model from: \(modelURL)")
                
                // Load entity
                let entity = try await ModelEntity.load(contentsOf: modelURL)
                
                // Cache it for future use
                loadingCache[item.id] = entity
                
                // Clone and add to scene
                let clonedEntity = entity.clone(recursive: true) as! ModelEntity
                addEntityToScene(clonedEntity, at: transform, for: item)
                
            } catch {
                print("❌ Failed to load \(item.name): \(error)")
            }
        }
        
        // MARK: - Add Entity to Scene
        @MainActor
        private func addEntityToScene(_ entity: ModelEntity, at transform: simd_float4x4, for item: FurnitureItemForPlacement) {
            guard let arView = arView else { return }
            
            // If item was already placed, remove old entity
            if let oldEntity = placedItems[item.id] {
                oldEntity.removeFromParent()
            }
            
            // Extract position from transform matrix
            let position = SIMD3<Float>(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )
            
            // Create anchor at placement location
            let anchor = AnchorEntity(world: position)
            
            // Set default scale (adjust as needed)
            entity.scale = SIMD3<Float>(repeating: 1.0)
            
            // Enable gestures for manipulation
            entity.generateCollisionShapes(recursive: true)
            arView.installGestures([.translation, .rotation, .scale], for: entity)
            
            // Add to anchor
            anchor.addChild(entity)
            
            // Add anchor to scene
            arView.scene.addAnchor(anchor)
            
            // Update state
            placedItems[item.id] = entity
            placedItemsBinding[item.id] = entity
            
            print("✅ \(item.name) placed successfully")
        }
        
        // MARK: - Remove Item
        @MainActor
        func removeItem(withId id: String) {
            if let entity = placedItems[id] {
                entity.removeFromParent()
                placedItems.removeValue(forKey: id)
                placedItemsBinding.removeValue(forKey: id)
                print("🗑️ Removed item: \(id)")
            }
        }
        
        // MARK: - Clear All
        @MainActor
        func clearAll() {
            for (_, entity) in placedItems {
                entity.removeFromParent()
            }
            placedItems.removeAll()
            placedItemsBinding.removeAll()
            print("🗑️ Cleared all items")
        }
    }
}

// MARK: - SwiftUI Wrapper with UI Controls
struct ARPlacementContainer: View {
    let furnitureItems: [FurnitureItemForPlacement]
    @State private var selectedItemIndex: Int? = nil
    @State private var placedItems: [String: ModelEntity] = [:]
    @State private var showingItemList = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // AR View
            ARPlacementView(
                furnitureItems: furnitureItems,
                selectedItemIndex: $selectedItemIndex,
                placedItems: $placedItems
            )
            .edgesIgnoringSafeArea(.all)
            
            // UI Overlay
            VStack {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                    
                    Spacer()
                    
                    Text(selectedItemIndex != nil ? "Tap to Place" : "Select Item")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    
                    Spacer()
                    
                    Button(action: { showingItemList.toggle() }) {
                        Image(systemName: showingItemList ? "list.bullet.circle.fill" : "list.bullet.circle")
                            .font(.title)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                }
                .padding()
                
                Spacer()
                
                // Bottom furniture selector
                if showingItemList {
                    VStack(spacing: 12) {
                        Text("Select Furniture to Place")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(furnitureItems.enumerated()), id: \.element.id) { index, item in
                                    FurnitureSelectionCard(
                                        item: item,
                                        isSelected: selectedItemIndex == index,
                                        isPlaced: placedItems[item.id] != nil
                                    ) {
                                        selectedItemIndex = index
                                        print("🎯 Selected: \(item.name)")
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.7))
                            .shadow(radius: 10)
                    )
                    .padding()
                }
            }
            
            // Instructions overlay (shows when no item selected)
            if selectedItemIndex == nil && placedItems.isEmpty {
                VStack {
                    Spacer()
                    Text("👆 Select a furniture item below\nthen tap on the floor to place it")
                        .multilineTextAlignment(.center)
                        .font(.headline)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .padding()
                }
            }
        }
    }
}

// MARK: - Furniture Selection Card
struct FurnitureSelectionCard: View {
    let item: FurnitureItemForPlacement
    let isSelected: Bool
    let isPlaced: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Icon or placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.purple : Color.white.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "cube.box.fill")
                        .font(.system(size: 40))
                        .foregroundColor(isSelected ? .white : .gray)
                    
                    if isPlaced {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                            .offset(x: 25, y: -25)
                    }
                }
                
                Text(item.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
