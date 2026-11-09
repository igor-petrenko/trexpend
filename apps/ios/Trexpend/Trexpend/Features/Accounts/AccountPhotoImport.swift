import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct AccountPhotoImport: Transferable, Sendable {
    let png: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try await Task.detached(priority: .userInitiated) {
                let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard let size, size <= AccountImageCodec.inputLimit else { throw AccountError.image }
                return Self(png: try AccountImageCodec.normalize(Data(contentsOf: received.file)))
            }.value
        }
    }
}
