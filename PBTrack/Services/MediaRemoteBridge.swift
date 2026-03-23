import Foundation

final class MediaRemoteBridge: Sendable {

    private nonisolated(unsafe) static let bundle: CFBundle? = {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let url = CFURLCreateWithFileSystemPath(
            kCFAllocatorDefault, path as CFString, .cfurlposixPathStyle, true
        ) else { return nil }
        return CFBundleCreate(kCFAllocatorDefault, url)
    }()

    /// Whether the MediaRemote framework was loaded successfully
    static var isAvailable: Bool { bundle != nil }

    // MARK: - Function type aliases

    typealias MRMediaRemoteRegisterForNowPlayingNotifications = @convention(c) (DispatchQueue) -> Void
    typealias MRMediaRemoteGetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping @Sendable ([String: Any]) -> Void) -> Void
    typealias MRMediaRemoteGetNowPlayingApplicationPID = @convention(c) (DispatchQueue, @escaping @Sendable (Int32) -> Void) -> Void

    // MARK: - Resolved functions

    static let registerForNowPlayingNotifications: MRMediaRemoteRegisterForNowPlayingNotifications? = {
        guard let bundle else { return nil }
        guard let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) else { return nil }
        return unsafeBitCast(ptr, to: MRMediaRemoteRegisterForNowPlayingNotifications.self)
    }()

    static let getNowPlayingInfo: MRMediaRemoteGetNowPlayingInfo? = {
        guard let bundle else { return nil }
        guard let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) else { return nil }
        return unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingInfo.self)
    }()

    static let getNowPlayingApplicationPID: MRMediaRemoteGetNowPlayingApplicationPID? = {
        guard let bundle else { return nil }
        guard let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationPID" as CFString) else { return nil }
        return unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingApplicationPID.self)
    }()

    // MARK: - Notification names
    // Discovered at runtime via CFBundleGetDataPointerForName, with hardcoded fallbacks.

    static let nowPlayingInfoDidChange: NSNotification.Name = {
        resolveNotificationName("kMRMediaRemoteNowPlayingInfoDidChangeNotification")
    }()
    static let nowPlayingApplicationDidChange: NSNotification.Name = {
        resolveNotificationName("kMRMediaRemoteNowPlayingApplicationDidChangeNotification")
    }()
    static let nowPlayingApplicationIsPlayingDidChange: NSNotification.Name = {
        resolveNotificationName("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")
    }()

    private static func resolveNotificationName(_ symbolName: String) -> NSNotification.Name {
        guard let bundle else {
            debugLog("[MediaRemoteBridge] Bundle not loaded, using fallback name: \(symbolName)")
            return NSNotification.Name(symbolName)
        }
        guard let ptr = CFBundleGetDataPointerForName(bundle, symbolName as CFString) else {
            debugLog("[MediaRemoteBridge] Could not resolve symbol \(symbolName), using as literal")
            return NSNotification.Name(symbolName)
        }
        let name = ptr.assumingMemoryBound(to: NSString.self).pointee as String
        debugLog("[MediaRemoteBridge] Resolved \(symbolName) -> \(name)")
        return NSNotification.Name(name)
    }

    // MARK: - Info dictionary keys

    static let infoTitle = "kMRMediaRemoteNowPlayingInfoTitle"
    static let infoArtist = "kMRMediaRemoteNowPlayingInfoArtist"
    static let infoAlbum = "kMRMediaRemoteNowPlayingInfoAlbum"
    static let infoDuration = "kMRMediaRemoteNowPlayingInfoDuration"
    static let infoElapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
    static let infoArtworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
    static let infoPlaybackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    // Playback rate: 0.0 = paused, 1.0 = playing
}
