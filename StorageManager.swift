import Foundation
import UIKit

class StorageManager {
    static let shared = StorageManager()

    private let fileManager = FileManager.default
    private let designsDirectory: URL

    private init() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        designsDirectory = documentsURL.appendingPathComponent("Designs", isDirectory: true)

        try? fileManager.createDirectory(at: designsDirectory, withIntermediateDirectories: true)
    }

    func saveDesign(_ design: GeneratedDesign) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let designData = try encoder.encode(design)

        let designURL = designsDirectory.appendingPathComponent("\(design.id.uuidString).json")
        try designData.write(to: designURL)
    }

    func loadAllDesigns() -> [GeneratedDesign] {
        guard let files = try? fileManager.contentsOfDirectory(at: designsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let design = try? decoder.decode(GeneratedDesign.self, from: data) else {
                return nil
            }
            return design
        }.sorted { $0.timestamp > $1.timestamp }
    }

    func deleteDesign(id: UUID) throws {
        let designURL = designsDirectory.appendingPathComponent("\(id.uuidString).json")
        try fileManager.removeItem(at: designURL)
    }

    func deleteAllDesigns() throws {
        let designs = loadAllDesigns()
        for design in designs {
            try? deleteDesign(id: design.id)
        }
    }
}
