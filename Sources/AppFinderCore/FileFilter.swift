/// Which Spotlight file results AppFinder leaves out: anything under `~/Library`, hidden paths,
/// the contents of bundles and packages, and build and dependency folders.
public enum FileFilter {
    static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "appex", "xpc", "photoslibrary",
        "musiclibrary", "tvlibrary", "photolibrary", "xcodeproj", "xcworkspace", "xcarchive",
        "playground", "pages", "numbers", "key", "rtfd", "lproj", "nib", "sparsebundle",
    ]
    static let excludedFolders: Set<String> = [
        "node_modules", "DerivedData", "Pods", "__pycache__", "site-packages", "target", "build", "dist",
    ]

    public static func isExcluded(path: String, home: String) -> Bool {
        let homePrefix = home.hasSuffix("/") ? home : home + "/"
        if path.hasPrefix(homePrefix + "Library/") {
            return true
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        // Every component but the last is a folder the item lies in.
        for component in components.dropLast() {
            if component.hasPrefix(".") || excludedFolders.contains(String(component)) {
                return true
            }
            if let dot = component.lastIndex(of: "."),
               packageExtensions.contains(component[component.index(after: dot)...].lowercased()) {
                return true
            }
        }
        if let last = components.last, last.hasPrefix(".") {
            return true
        }
        return false
    }
}
