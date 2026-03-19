import Foundation

struct BezelTrackItem: Sendable, Identifiable {
    let id: Int64
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let durationSeconds: Double?
    let startedAt: Date
    let appName: String
    let appBundleId: String
    let outputDeviceName: String?
}
