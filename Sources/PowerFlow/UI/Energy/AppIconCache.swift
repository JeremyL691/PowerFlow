import AppKit
import Foundation

/// Main-actor bounded cache of 20×20 application icons loaded via `NSWorkspace`.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    static let iconSize = NSSize(width: 20, height: 20)

    private let cache: NSCache<NSString, NSImage>
    private var missingPaths = Set<String>()
    private static let maxMissingPaths = 256

    init(countLimit: Int = 128) {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = max(1, countLimit)
        self.cache = cache
    }

    func icon(forPath path: String?) -> NSImage? {
        guard let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty
        else {
            return nil
        }

        let key = rawPath as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if missingPaths.contains(rawPath) {
            return nil
        }

        guard FileManager.default.fileExists(atPath: rawPath) else {
            if missingPaths.count >= Self.maxMissingPaths {
                missingPaths.removeAll(keepingCapacity: true)
            }
            missingPaths.insert(rawPath)
            return nil
        }

        let workspaceIcon = NSWorkspace.shared.icon(forFile: rawPath)
        let sizedIcon = (workspaceIcon.copy() as? NSImage) ?? workspaceIcon
        sizedIcon.size = Self.iconSize
        cache.setObject(sizedIcon, forKey: key)
        return sizedIcon
    }

    func clear() {
        cache.removeAllObjects()
        missingPaths.removeAll()
    }
}
