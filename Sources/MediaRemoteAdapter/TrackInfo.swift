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
        public let timestampEpochMicros: Double?

        public var artwork: NSImage? {
            guard let base64String = artworkDataBase64,
                  let data = Data(base64Encoded: base64String)
            else {
                return nil
            }
            return NSImage(data: data)
        }

        public var uniqueIdentifier: String {
            return "\(title ?? "")-\(artist ?? "")-\(album ?? "")"
        }

        enum CodingKeys: String, CodingKey {
            case title, artist, album, isPlaying, durationMicros, elapsedTimeMicros, applicationName, bundleIdentifier, artworkDataBase64, artworkMimeType, timestampEpochMicros
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.title = try container.decodeIfPresent(String.self, forKey: .title)
            self.artist = try container.decodeIfPresent(String.self, forKey: .artist)
            self.album = try container.decodeIfPresent(String.self, forKey: .album)
            self.durationMicros = try container.decodeIfPresent(Double.self, forKey: .durationMicros)
            self.elapsedTimeMicros = try container.decodeIfPresent(Double.self, forKey: .elapsedTimeMicros)
            self.applicationName = try container.decodeIfPresent(String.self, forKey: .applicationName)
            self.bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
            self.artworkDataBase64 = try container.decodeIfPresent(String.self, forKey: .artworkDataBase64)
            self.artworkMimeType = try container.decodeIfPresent(String.self, forKey: .artworkMimeType)
            self.timestampEpochMicros = try container.decodeIfPresent(Double.self, forKey: .timestampEpochMicros)

            if let boolValue = try? container.decode(Bool.self, forKey: .isPlaying) {
                self.isPlaying = boolValue
            } else if let intValue = try? container.decode(Int.self, forKey: .isPlaying) {
                self.isPlaying = (intValue == 1)
            } else {
                self.isPlaying = nil
            }
        }
    }
} 