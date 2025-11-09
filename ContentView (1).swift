import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = FurnishViewModel()
    @State private var showingFilePicker = false
    @State private var showingARView = false
    @State private var roomType = "bedroom"
    @State private var budget = "5000"
    
    let roomTypes = ["bedroom", "living_room", "kitchen", "bathroom", "dining_room", "office"]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.2)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    if viewModel.isLoading {
                        loadingView
                    } else if !viewModel.furnitureItems.isEmpty {
                        resultsView
                    } else {
                        uploadView
                    }
                }
                .padding()
            }
            .navigationTitle("Furnisher AR")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker { url in
                    Task {
                        await viewModel.generateDesign(
                            fromRoomURL: url,
                            roomType: roomType,
                            budget: budget
                        )
                    }
                }
            }
            .fullScreenCover(isPresented: $showingARView) {
                ARPlacementContainer(furnitureItems: viewModel.furnitureItems)
            }
        }
    }
    
    // MARK: - Upload View
    private var uploadView: some View {
        VStack(spacing: 40) {
            // Icon
            Image(systemName: "cube.transparent")
                .font(.system(size: 100))
                .foregroundColor(.purple)
                .shadow(radius: 10)
            
            VStack(spacing: 15) {
                Text("Design Your Space")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Upload a room scan to get AI-powered furniture recommendations")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Settings
            VStack(spacing: 20) {
                // Room Type Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Room Type")
                        .font(.headline)
                    
                    Picker("Room Type", selection: $roomType) {
                        ForEach(roomTypes, id: \.self) { type in
                            Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(12)
                }
                
                // Budget Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Budget ($)")
                        .font(.headline)
                    
                    TextField("5000", text: $budget)
                        .keyboardType(.numberPad)
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            
            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Upload Button
            Button(action: { showingFilePicker = true }) {
                HStack {
                    Image(systemName: "doc.badge.plus")
                        .font(.title2)
                    Text("Select Room Scan")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding(.vertical, 16)
                .padding(.horizontal, 40)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.purple, Color.blue]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(15)
                .shadow(radius: 5)
            }
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 30) {
            ProgressView()
                .scaleEffect(2)
                .tint(.purple)
            
            VStack(spacing: 15) {
                Text("Generating Design...")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("This may take 1-2 minutes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("We're analyzing your room and finding the perfect furniture")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
    
    // MARK: - Results View
    private var resultsView: some View {
        VStack(spacing: 30) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            VStack(spacing: 15) {
                Text("Design Ready!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Found \(viewModel.furnitureItems.count) furniture \(viewModel.furnitureItems.count == 1 ? "item" : "items") for your \(roomType.replacingOccurrences(of: "_", with: " "))")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Furniture list preview
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.furnitureItems) { item in
                        HStack {
                            Image(systemName: "cube.box.fill")
                                .font(.title2)
                                .foregroundColor(.purple)
                                .frame(width: 40)
                            
                            Text(item.name)
                                .font(.body)
                            
                            Spacer()
                            
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 300)
            
            // Action buttons
            VStack(spacing: 15) {
                Button(action: { showingARView = true }) {
                    HStack {
                        Image(systemName: "arkit")
                            .font(.title2)
                        Text("View in AR")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.purple, Color.blue]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(15)
                    .shadow(radius: 5)
                }
                
                Button(action: {
                    viewModel.clearResult()
                }) {
                    Text("Start New Design")
                        .font(.subheadline)
                        .foregroundColor(.purple)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    let onSelect: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "usdz")!])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelect: (URL) -> Void
        
        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Get access to the file
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // Copy to temp directory so we have persistent access
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            
            do {
                // Remove if exists
                try? FileManager.default.removeItem(at: tempURL)
                // Copy file
                try FileManager.default.copyItem(at: url, to: tempURL)
                onSelect(tempURL)
            } catch {
                print("❌ Error copying file: \(error)")
            }
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
