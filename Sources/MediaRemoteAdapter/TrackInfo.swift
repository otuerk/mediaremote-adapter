import AppKit
import Foundation

public struct TrackInfo: Codable {
    public let payload: Payload

    public struct Payload: Codable {
        public let title: String?
        public let artist: String?
        public let album: String?
        public let isPlaying: Bool?
        public let durationMicros: Double?
        public let elapsedTimeMicros: Double?
        public let applicationName: String?
        public let bundleIdentifier: String?
        public let artworkDataBase64: String?
        public let artworkMimeType: String?

        public var artwork: NSImage? {
            guard let base64String = artworkDataBase64,
                  let data = Data(base64Encoded: base64String)
            else {
                return nil
            }
            return NSImage(data: data)
        }
    }
} 