
import SwiftUI
import RoomPlan
import Combine

@available(iOS 16.0, *)
struct RoomPlanCaptureView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var capturedRoomURL: URL?
    @StateObject private var captureController = RoomCaptureController()

    var body: some View {
        ZStack {
            RoomCaptureViewRepresentable(
                capturedRoomURL: $capturedRoomURL,
                captureController: captureController
            )
            .ignoresSafeArea(.all)

            VStack {
                HStack {
                    Button(action: {
                        print("❌ Cancel button tapped")
                        captureController.stopSession()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding()

                    Spacer()

                    Button(action: {
                        print("✅ Done button tapped")
                        captureController.stopSession()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            dismiss()
                        }
                    }) {
                        Text("Done")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding()
                }

                Spacer()

                VStack(spacing: 15) {
                    if let instruction = captureController.currentInstruction {
                        Text(instruction)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                    } else {
                        Text("Scan Your Room")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                    }

                    Text("Move your device slowly around the room")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            print("🎥 RoomPlan view appeared")
            captureController.startSession()
        }
        .onChange(of: captureController.capturedURL) { oldValue, newValue in
            if let url = newValue {
                print("📥 Captured URL received: \(url.lastPathComponent)")
                capturedRoomURL = url
            }
        }
        .alert("Unsupported Device", isPresented: $captureController.showUnsupportedDeviceAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your device does not support RoomPlan. Please use a device with LiDAR capabilities.")
        }
    }
}

@available(iOS 16.0, *)
class RoomCaptureController: ObservableObject {
    @Published var currentInstruction: String?
    @Published var capturedURL: URL?
    @Published var isRoomPlanSupported: Bool = true
    @Published var showUnsupportedDeviceAlert: Bool = false

    var captureView: RoomPlan.RoomCaptureView?

    init() {
        isRoomPlanSupported = RoomCaptureSession.isSupported
        print("🔍 RoomPlan supported: \(isRoomPlanSupported)")
    }

    func startSession() {
        if !isRoomPlanSupported {
            showUnsupportedDeviceAlert = true
            return
        }
        print("🚀 Session start requested")
    }

    func stopSession() {
        print("🛑 Stop session called")
        captureView?.captureSession.stop()
    }
}

@available(iOS 16.0, *)
struct RoomCaptureViewRepresentable: UIViewRepresentable {
    @Binding var capturedRoomURL: URL?
    @ObservedObject var captureController: RoomCaptureController

    func makeUIView(context: Context) -> RoomPlan.RoomCaptureView {
        let captureView = RoomPlan.RoomCaptureView(frame: .zero)

        // Store reference to the view in the controller
        DispatchQueue.main.async {
            self.captureController.captureView = captureView
        }

        // Set delegate and start the session
        captureView.captureSession.delegate = context.coordinator

        let configuration = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: configuration)
        
        print("✅ RoomCaptureView initialized and session started")

        return captureView
    }

    func updateUIView(_ uiView: RoomPlan.RoomCaptureView, context: Context) {
        // No dynamic updates needed
    }
    
    static func dismantleUIView(_ uiView: RoomPlan.RoomCaptureView, coordinator: Coordinator) {
        print("🧹 Cleaning up RoomCaptureView")
        uiView.captureSession.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(capturedRoomURL: $capturedRoomURL, captureController: captureController)
    }

    class Coordinator: NSObject, RoomCaptureSessionDelegate {
        @Binding var capturedRoomURL: URL?
        var captureController: RoomCaptureController
        var latestCapturedRoom: CapturedRoom?  // NEW: Store the latest room

        init(capturedRoomURL: Binding<URL?>, captureController: RoomCaptureController) {
            self._capturedRoomURL = capturedRoomURL
            self.captureController = captureController
            super.init()
        }

        func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
            // Store the latest room update
            latestCapturedRoom = room
        }

        func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
            if let error = error {
                print("❌ Capture session ended with error: \(error)")
                return
            }

            print("✅ Capture session ended successfully")
            
            // Use the latest captured room if available
            guard let finalRoom = latestCapturedRoom else {
                print("❌ No captured room available")
                return
            }
            
            print("📊 Final room captured, starting export...")

            // Export the room
            Task {
                do {
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let destinationFolderURL = documentsPath.appendingPathComponent("RoomScans")
                    let destinationURL = destinationFolderURL.appendingPathComponent("CapturedRoom_\(UUID().uuidString).usdz")
                    
                    // Ensure the directory exists
                    try FileManager.default.createDirectory(at: destinationFolderURL, withIntermediateDirectories: true, attributes: nil)
                    
                    print("📝 Exporting to: \(destinationURL.path)")
                    
                    // FIXED: Use the correct CapturedRoom.export() method
                    try finalRoom.export(to: destinationURL)
                    
                    // Verify file exists
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                        let fileSize = attributes[.size] as? Int ?? 0
                        
                        await MainActor.run {
                            print("✅ USDZ file created successfully!")
                            print("   Path: \(destinationURL.path)")
                            print("   Size: \(fileSize) bytes")
                            
                            self.capturedRoomURL = destinationURL
                            self.captureController.capturedURL = destinationURL
                        }
                    } else {
                        print("❌ File was not created at expected path")
                    }
                    
                } catch {
                    print("❌ Error exporting room: \(error)")
                    print("   Error details: \(error.localizedDescription)")
                }
            }
        }

        func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {
            print("➕ Room added")
            latestCapturedRoom = room  // Store the room
        }

        func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
            print("🔄 Room changed")
            latestCapturedRoom = room  // Update with latest room
        }

        func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
            Task { @MainActor in
                switch instruction {
                case .moveCloseToWall:
                    captureController.currentInstruction = "Move closer to the wall"
                case .moveAwayFromWall:
                    captureController.currentInstruction = "Move away from the wall"
                case .slowDown:
                    captureController.currentInstruction = "Slow down"
                case .turnOnLight:
                    captureController.currentInstruction = "Turn on more lights"
                case .normal:
                    captureController.currentInstruction = "Keep scanning"
                case .lowTexture:
                    captureController.currentInstruction = "More texture needed"
                @unknown default:
                    captureController.currentInstruction = "Continue scanning"
                }
            }
        }

        func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {
            print("🚀 Capture session started with configuration")
        }

        func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom) {
            print("➖ Room removed")
        }
    }
}
