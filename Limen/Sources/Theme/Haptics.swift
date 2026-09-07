import UIKit

/// The instrument's touch. Keys in this app visibly sink under the thumb, and a key that looks
/// mechanical should feel mechanical.
///
/// Five weights. `key` is every control. `toggleOn` and `toggleOff` are a switch changing state,
/// the pair Android names TOGGLE_ON and TOGGLE_OFF, and the rule they carry is that changing a
/// toggle should feel less than submitting something. iOS has no such constant, so the pair is
/// built from the soft impact, which is a dull tick rather than the crisp tap `key` uses, at two
/// intensities: the ordering Android gets from a half-strength tick against a low one, with both
/// under the light impact a key plays. `confirm` marks the two moments that end something: a
/// signature kept, a document written. `reject` marks a refusal or a deletion, so a destructive
/// tap never feels the same as an ordinary one.
///
/// The system's feedback generators are the only route on iOS, and they honour the phone's own
/// haptics switch on their own: when the keys feel dead, that setting is off, and it is the
/// phone's answer to give.
enum Tick {
    case key, toggleOn, toggleOff, confirm, reject
}

@MainActor
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notification = UINotificationFeedbackGenerator()

    static func play(_ tick: Tick) {
        switch tick {
        case .key: impact.impactOccurred()
        case .toggleOn: soft.impactOccurred(intensity: 0.7)
        case .toggleOff: soft.impactOccurred(intensity: 0.45)
        case .confirm: notification.notificationOccurred(.success)
        case .reject: notification.notificationOccurred(.error)
        }
    }
}
