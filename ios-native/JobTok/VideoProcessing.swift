import Foundation
@preconcurrency import AVFoundation

/// Pre-upload video handling: pass small files through untouched, compress
/// anything over the preferred limit, and refuse files that stay too large
/// even after compression.
enum VideoProcessing {
    static let preferredUploadLimitBytes: Int64 = 45 * 1_024 * 1_024
    static let hardUploadLimitBytes: Int64 = 50 * 1_024 * 1_024

    static func prepareVideoForUpload(_ url: URL) async throws -> URL {
        let originalSize = try fileSize(for: url)
        if originalSize <= preferredUploadLimitBytes {
            return url
        }

        let asset = AVURLAsset(url: url)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw SupabaseServiceError.apiError("This video is too large to upload directly and could not be compressed.")
        }

        let outputURL = URL(filePath: NSTemporaryDirectory())
            .appending(path: "jobtok-video-\(UUID().uuidString).mp4")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        try await exportCompressedVideo(exportSession)

        let compressedSize = try fileSize(for: outputURL)
        guard compressedSize <= hardUploadLimitBytes else {
            throw SupabaseServiceError.apiError("The video is still too large after compression. Keep it under about 50 MB, or raise the Supabase Storage file size limit.")
        }

        return outputURL
    }

    private static func exportCompressedVideo(_ exportSession: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: exportSession.error ?? SupabaseServiceError.invalidResponse)
                case .cancelled:
                    continuation.resume(throwing: SupabaseServiceError.apiError("Video compression was cancelled."))
                default:
                    continuation.resume(throwing: SupabaseServiceError.invalidResponse)
                }
            }
        }
    }

    private static func fileSize(for url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
