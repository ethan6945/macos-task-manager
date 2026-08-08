import AppKit
import SwiftUI

/// 进程图标缓存。`NSWorkspace.icon(forFile:)` 每次都会读磁盘，几百行的表格必须缓存。
@MainActor
final class IconCache {
    static let shared = IconCache()

    private var cache: [String: NSImage] = [:]
    private let fallback = NSWorkspace.shared.icon(for: .unixExecutable)

    func icon(bundlePath: String?, executablePath: String?) -> NSImage {
        let key = bundlePath ?? executablePath
        guard let key else { return fallback }
        if let cached = cache[key] { return cached }

        guard FileManager.default.fileExists(atPath: key) else {
            cache[key] = fallback
            return fallback
        }
        let icon = NSWorkspace.shared.icon(forFile: key)
        icon.size = NSSize(width: 16, height: 16)
        cache[key] = icon
        return icon
    }
}

struct ProcessIcon: View {
    var bundlePath: String?
    var executablePath: String?

    var body: some View {
        Image(nsImage: IconCache.shared.icon(bundlePath: bundlePath, executablePath: executablePath))
            .resizable()
            .frame(width: 16, height: 16)
    }
}
