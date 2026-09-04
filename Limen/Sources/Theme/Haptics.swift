import UIKit

/// The instrument's touch. Keys in this app visibly sink under the thumb, and a key that looks
/// mechanical should feel mechanical.
///
/// Three weights only. `key` is every control. `confirm` marks the two moments that end
/// something: a signature kept, a document written. `reject` marks a refusal or a deletion, so a
/// destructive tap never feels the same as an ordinary one.
///
/// The system's feedback generators are the only route on iOS, and they honour the phone's own
/// haptics switch on their own: when the keys feel dead, that setting is off, and it is the
/// phone's answer to give.
enum Tick {
    case key, confirm, reject
}

@MainActor
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let notification = UINotificationFeedbackGenerator()

    static func play(_ tick: Tick) {
        switch tick {
        case .key: impact.impactOccurred()
        case .confirm: notification.notificationOccurred(.success)
        case .reject: notification.notificationOccurred(.error)
        }
    }
}
