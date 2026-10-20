import Foundation

/// Desktop, Documents and Downloads are protected: Spotlight leaves files in them out of an app's
/// results until the user allowed the app to access the folder (System Settings → Privacy &
/// Security → Files & Folders). Reading a folder is what makes the system ask.
public enum FolderAccess {
    public static var folders: [URL] {
        [URL.desktopDirectory, URL.documentsDirectory, URL.downloadsDirectory]
    }

    /// Reads each folder once. The first time, the system asks the user (the call waits for the
    /// answer, so call it off the main thread); afterwards it answers at once. Returns the folders
    /// AppFinder may not read.
    public static func check() -> [URL] {
        folders.filter { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) == nil }
    }

    public static let privacySettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
    )!
}
