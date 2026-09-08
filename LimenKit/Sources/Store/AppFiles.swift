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

    /// Where an export builds anything that is not yet encrypted. The cache is inside the app's
    /// container and no other app or Files sharing can reach it, which Documents cannot say:
    /// `UIFileSharingEnabled` puts everything under Documents in front of the person and anything
    /// that can read it. A plaintext archive of every record must never sit there, not even for
    /// the seconds an export takes, because a kill mid-export would leave it there for good.
    public static var scratch: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("scratch")
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
