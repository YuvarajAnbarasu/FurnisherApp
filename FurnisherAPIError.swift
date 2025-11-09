import Foundation
import UIKit
import RealityKit

// MARK: - API Errors
enum FurnisherAPIError: LocalizedError {
    case invalidURL
    case noFileData
    case invalidResponse
    case decodingError(String)
    case serverError(Int, String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .noFileData:
            return "Failed to read USDZ file"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let detail):
            return "Failed to decode response: \(detail)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Furnisher API Client
class FurnisherAPI {
    static let shared = FurnisherAPI()

    // backend url
    private let baseURL = "http://136.116.236.142:5000"

    private init() {}

    // MARK: - Send Room Scan (Simplified for name + USDZ only)
    func sendRoomScan(usdzURL: URL, roomType: String = "bedroom", budget: String = "5000") async throws -> SimplifiedResponse {
        guard let url = URL(string: "\(baseURL)/generate-design") else {
            throw FurnisherAPIError.invalidURL
        }

        guard let fileData = try? Data(contentsOf: usdzURL) else {
            throw FurnisherAPIError.noFileData
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180  // 3 minutes - backend processing takes time

        var body = Data()

        // Add USDZ file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(usdzURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: model/vnd.usdz+zip\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        // Add room_type
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"room_type\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(roomType)\r\n".data(using: .utf8)!)

        // Add budget
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"budget\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(budget)\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        print("📤 Sending to Flask backend:")
        print("   File: \(usdzURL.lastPathComponent) (\(fileData.count) bytes)")
        print("   Room Type: \(roomType)")
        print("   Budget: $\(budget)")

        return try await executeRequest(request)
    }

    // MARK: - Execute Request
    private func executeRequest(_ request: URLRequest) async throws -> SimplifiedResponse {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FurnisherAPIError.invalidResponse
            }

            print("📥 Response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Server error: \(errorMessage)")
                throw FurnisherAPIError.serverError(httpResponse.statusCode, errorMessage)
            }

            // Print raw response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📦 Raw response: \(jsonString.prefix(500))...")
            }

            let decoder = JSONDecoder()
            let serverResponse: SimplifiedResponse

            do {
                serverResponse = try decoder.decode(SimplifiedResponse.self, from: data)
            } catch {
                print("❌ Decoding error: \(error)")
                throw FurnisherAPIError.decodingError(error.localizedDescription)
            }

            print("✅ Decoded response:")
            print("   Scan ID: \(serverResponse.scanId)")
            print("   Furniture items: \(serverResponse.furniture.count)")
            
            for item in serverResponse.furniture {
                print("   - \(item.name): \(item.modelUrlUsdz)")
            }

            return serverResponse

        } catch let error as FurnisherAPIError {
            throw error
        } catch {
            throw FurnisherAPIError.networkError(error)
        }
    }

    // MARK: - Helper Functions
    func constructFullURL(_ path: String) -> String {
        if path.hasPrefix("http") {
            return path
        }
        return baseURL + path
    }
}

// MARK: - Simplified Response Models
struct SimplifiedResponse: Codable {
    let scanId: String
    let furniture: [SimplifiedFurnitureItem]

    enum CodingKeys: String, CodingKey {
        case scanId = "scan_id"
        case furniture
    }
}

struct SimplifiedFurnitureItem: Codable, Identifiable {
    let id: String
    let name: String
    let modelUrlUsdz: String
    
    enum CodingKeys: String, CodingKey {
        case id = "furniture_id"
        case name
        case modelUrlUsdz = "usdz_url"
    }
}

// MARK: - App Models for Manual Placement
struct FurnitureItemForPlacement: Identifiable {
    let id: String
    let name: String
    let modelUrlUsdz: String
    var isPlaced: Bool = false
    var placedEntity: ModelEntity? = nil
    
    init(from simplified: SimplifiedFurnitureItem) {
        self.id = simplified.id
        self.name = simplified.name
        self.modelUrlUsdz = FurnisherAPI.shared.constructFullURL(simplified.modelUrlUsdz)
    }
}
