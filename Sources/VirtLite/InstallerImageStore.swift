import Foundation

/// Remembers which installer image belongs to which machine, across launches.
///
/// This lives beside the app rather than inside the bundle on purpose. A bundle must survive
/// being copied to another Mac, so it holds no absolute paths and no bookmarks (BND-03) — and an
/// installer image is a file somewhere in the user's home that has nothing to do with the
/// machine's identity.
///
/// Losing this is not cosmetic: a machine whose guest is not installed yet and whose installer
/// has been forgotten cannot boot at all, and gives no hint why.
@MainActor
struct InstallerImageStore {

    private let defaultsKey = "InstallerImages"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Bookmarks rather than paths, so moving or renaming the image does not break the link.
    private var bookmarks: [String: Data] {
        get { defaults.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: defaultsKey) }
    }

    func installer(for machineID: URL) -> URL? {
        guard let data = bookmarks[machineID.absoluteString] else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        // A vanished image is worse than none: it would fail at start with a puzzling error.
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            forget(for: machineID)
            return nil
        }

        return url
    }

    func remember(_ imageURL: URL, for machineID: URL) {
        guard let data = try? imageURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        var current = bookmarks
        current[machineID.absoluteString] = data
        bookmarks = current
    }

    func forget(for machineID: URL) {
        var current = bookmarks
        current.removeValue(forKey: machineID.absoluteString)
        bookmarks = current
    }
}
