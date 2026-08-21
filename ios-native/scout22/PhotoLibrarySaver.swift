import Photos
import UIKit

// Saves rendered social cards to the device photo library, in slide order.
//
// This is the path that needs nothing from Meta: render a batch, save the
// cards to Photos, then post from Instagram by hand — picking the images in
// order and pasting the caption. Instagram's API has no draft state (it can
// only create-and-publish), so posting from the app is the only way to review
// a post inside Instagram before it goes live.
//
// Requests add-only access, which is the narrowest permission that works:
// it grants writing new assets and never reading the user's existing photos.

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case permissionDenied
        case downloadFailed(Int)
        case notAnImage(Int)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Photos access denied — enable it in Settings › scout22 › Photos."
            case .downloadFailed(let index):
                return "Card \(index + 1) could not be downloaded."
            case .notAnImage(let index):
                return "Card \(index + 1) was not a valid image."
            }
        }
    }

    /// Downloads each card and writes it to the library. Ordering matters —
    /// Instagram's picker follows the order photos were added, so saving
    /// sequentially (not concurrently) is what keeps cover-first intact.
    static func save(imageURLs: [URL]) async throws {
        try await requestAddOnlyAccess()

        for (index, url) in imageURLs.enumerated() {
            let data: Data
            do {
                (data, _) = try await URLSession.shared.data(from: url)
            } catch {
                throw SaveError.downloadFailed(index)
            }
            guard UIImage(data: data) != nil else { throw SaveError.notAnImage(index) }

            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
        }
    }

    private static func requestAddOnlyAccess() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch current {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard granted == .authorized || granted == .limited else {
                throw SaveError.permissionDenied
            }
        default:
            throw SaveError.permissionDenied
        }
    }
}
