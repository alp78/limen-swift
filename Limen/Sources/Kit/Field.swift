import LimenKit
import SwiftUI

/// The house text field: a stamped label over a plain line of ink on the raised plate.
struct Field: View {
    @Environment(\.limen) private var colors
    @Environment(\.recordLocked) private var recordLocked
    let label: String
    let value: String
    var singleLine = true
    var hint: String?
    var keyboard: UIKeyboardType = .default
    var isError = false
    var editableWhenLocked = false
    var onFocusChanged: ((Bool) -> Void)?
    let onChange: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        // A finalized record is readable everywhere and writable nowhere, and the keyboard
        // never opening says so better than a keystroke that silently does nothing.
        let readOnly = recordLocked && !editableWhenLocked
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(LimenType.labelSmall)
                .foregroundStyle(focused ? colors.actionOutline : colors.inkDim)
                .lineLimit(1)
            if readOnly {
                Text(value.isEmpty ? " " : value)
                    .font(LimenType.bodyMedium)
                    .foregroundStyle(colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(hint ?? "", text: Binding(get: { value }, set: onChange), axis: singleLine ? .horizontal : .vertical)
                    .font(LimenType.bodyMedium)
                    .foregroundStyle(colors.ink)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled(keyboard != .default)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                    .lineLimit(singleLine ? 1...1 : 1...6)
                    .focused($focused)
                    .tint(colors.actionOutline)
                    // The container carries the label, but VoiceOver steps into the field itself
                    // and read only the placeholder: the name has to be on the element it lands on.
                    .accessibilityLabel(label)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.input)
        .clipShape(shape)
        .overlay(shape.strokeBorder(isError ? colors.dangerOutline : colors.actionOutline, lineWidth: 1.5))
        .onChange(of: focused) { _, now in onFocusChanged?(now) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A day the picker returns, counted from the epoch it hands back.
private let dayMs: Int64 = 86_400_000

/// A date, typed or picked, never merely typed at.
///
/// Both roads exist because both are used: a person reading a tenancy agreement aloud types the
/// date faster than they can reach it on a grid, and a person standing in a hallway working out
/// which Tuesday the keys go back wants the grid. What neither road allows any more is a date
/// that is not one. The keyboard is masked to DD/MM/YYYY, the value only reaches the record once
/// it names a real day, and 31/02 is marked rather than stored.
struct DateField: View {
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let label: String
    let stored: String
    let onChange: (String) -> Void
    @State private var text = ""
    @State private var picking = false
    @State private var focused = false
    @State private var picked = Date()

    /// The instant that renders as this day in the picker.
    ///
    /// Android's Material picker both draws and returns UTC milliseconds, so the Kotlin seeds and
    /// reads in UTC. SwiftUI's DatePicker draws in the DEVICE zone, so carrying that convention
    /// across put the two ends in different calendars: seeding UTC midnight highlighted the day
    /// before on any phone set west of UTC, and reading the choice back through a UTC calendar
    /// then stored the day after the one the person tapped. Both ends use the device calendar now,
    /// as TimeField already did, and midday rather than midnight because a few zones have no
    /// midnight on the day they enter summer time.
    private static func middayInDeviceZone(_ day: LocalDate) -> Date? {
        var parts = DateComponents()
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        parts.hour = 12
        return Calendar.current.date(from: parts)
    }

    var body: some View {
        let digits = text.filter(\.isNumber).count
        // A date is wrong when it is complete and impossible, and equally wrong when the field
        // has been left half typed: "31/08/26" masks to a complete-looking Swiss date, stores
        // nothing and used to carry no error mark at all. Only marked once the field is left,
        // so it does not shout at the first digit.
        let impossible = digits == 8 ? SwissDate.toStored(text) == nil : ((1...7).contains(digits) && !focused)
        HStack(spacing: 4) {
            Field(label: label, value: text, hint: s.dateFormat, keyboard: .numberPad, isError: impossible, onFocusChanged: { focused = $0 }) { raw in
                text = SwissDate.mask(raw)
                if let iso = SwissDate.toStored(text) {
                    onChange(iso)
                } else if text.isEmpty {
                    // Emptying the field is an answer too; a half-typed one is not yet.
                    onChange("")
                }
            }
            if !locked {
                IconKey(glyph: .calendar, label: s.pickDate) {
                    picked = SwissDate.parse(stored).flatMap(Self.middayInDeviceZone) ?? Date()
                    picking = true
                }
            }
        }
        // Keyed on the stored value: an accepted date, the picker, and a record opened fresh all
        // arrive through it, while a half-typed date leaves it alone and so survives typing.
        .onChange(of: stored, initial: true) { _, now in text = SwissDate.display(now) }
        .sheet(isPresented: $picking) {
            VStack(spacing: 12) {
                DatePicker("", selection: $picked, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(colors.action)
                    .environment(\.locale, s.lang.locale)
                HStack(spacing: 8) {
                    SmallKey(label: s.cancel, stretch: true) { picking = false }
                    SmallKey(label: s.done, stretch: true) {
                        let parts = Calendar.current.dateComponents([.year, .month, .day], from: picked)
                        if let day = LocalDate.of(parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1) { onChange(day.isoString) }
                        picking = false
                    }
                }
            }
            .padding(20)
            .presentationDetents([.medium, .large])
            .presentationBackground(colors.plateRaised)
        }
    }
}

/// The handover's hour, on the same contract as `DateField`: masked to HH:MM, or dialled.
struct TimeField: View {
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let label: String
    let stored: String
    let onChange: (String) -> Void
    @State private var text = ""
    @State private var picking = false
    @State private var focused = false
    @State private var picked = Date()

    var body: some View {
        let digits = text.filter(\.isNumber).count
        let impossible = digits == 4 ? SwissDate.toStoredTime(text) == nil : ((1...3).contains(digits) && !focused)
        HStack(spacing: 4) {
            Field(label: label, value: text, hint: s.timeFormat, keyboard: .numberPad, isError: impossible, onFocusChanged: { focused = $0 }) { raw in
                text = SwissDate.maskTime(raw)
                if let value = SwissDate.toStoredTime(text) {
                    onChange(value)
                } else if text.isEmpty {
                    onChange("")
                }
            }
            if !locked {
                IconKey(glyph: .clock, label: s.pickTime) {
                    let parts = stored.split(separator: ":").compactMap { Int($0) }
                    var components = DateComponents()
                    components.hour = min(max(parts.first ?? 12, 0), 23)
                    components.minute = min(max(parts.count > 1 ? parts[1] : 0, 0), 59)
                    picked = Calendar.current.date(from: components) ?? Date()
                    picking = true
                }
            }
        }
        .onChange(of: stored, initial: true) { _, now in text = now }
        .sheet(isPresented: $picking) {
            VStack(spacing: 12) {
                DatePicker("", selection: $picked, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    // The 24 hour clock, which is how Swiss forms are printed, whatever the handset.
                    .environment(\.locale, Locale(identifier: "de_CH"))
                HStack(spacing: 8) {
                    SmallKey(label: s.cancel, stretch: true) { picking = false }
                    SmallKey(label: s.done, stretch: true) {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: picked)
                        onChange(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))
                        picking = false
                    }
                }
            }
            .padding(20)
            .presentationDetents([.medium])
            .presentationBackground(colors.plateRaised)
        }
    }
}

/// Two fields that belong side by side wherever a handover states when it happened.
struct DateAndTimeRow: View {
    let dateLabel: String
    let date: String
    let timeLabel: String
    let time: String
    let onDate: (String) -> Void
    let onTime: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            DateField(label: dateLabel, stored: date, onChange: onDate).layoutPriority(1.5)
            TimeField(label: timeLabel, stored: time, onChange: onTime)
        }
    }
}
