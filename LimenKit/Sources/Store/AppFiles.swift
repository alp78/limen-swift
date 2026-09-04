import Foundation

/// Where the records live: Application Support inside the app's container, the iOS shape of
/// Android's filesDir. Readable by nothing else, and excluded from the phone's backups the way
/// the Android manifest's allowBackup=false excluded everything: a handover leaves this phone
/// only as the PDF or the password-protected archive the person exports.
public enum AppFiles {
    public static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var url = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    /// Documents, which Files shows as On My iPhone / Limen: where the finished PDF and the
    /// backup are written, the iOS shape of Download/Limen.
    public static var documents: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// The camera and the picker hand their bytes over here, in the cache, to be moved beside a
    /// record or deleted.
    public static var captures: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("captures")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
