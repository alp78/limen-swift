import LimenKit
import SwiftUI

/// The three actors of the form. On paper the protocol still has two sides: the agency is the
/// landlord side acting through the representative it sends, so only the role is stored.
private enum Actor: Hashable {
    case tenant, landlord, agency

    var role: Role { self == .tenant ? .tenant : .landlord }
}

/// Identity and handover type are chosen together, immediately before a new session starts.
struct NewSessionScreen: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let entryToSeed: HandoverProtocol?
    let onBack: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var street = ""
    @State private var flatNumber = ""
    @State private var postalCode = ""
    @State private var city = ""
    @State private var phone = ""
    @State private var usesSwissAddress = true
    @State private var addressCountryCode = "CH"
    @State private var phoneRegionCode = "CH"
    @State private var company = ""
    @State private var actor: Actor = .tenant
    @State private var kind: Kind = .entry
    @State private var addressVerified = false
    @State private var addressSearching = false
    @State private var addressMatches: [SwissAddressCandidate] = []
    @State private var focusedAddressFields: Set<String> = []
    @State private var loaded = false

    private var sessionKind: Kind { entryToSeed != nil ? .exit : kind }

    private var identity: SessionIdentity {
        var identity = SessionIdentity()
        identity.firstName = firstName
        identity.lastName = lastName
        identity.company = actor == .agency ? company : ""
        identity.street = street
        identity.flatNumber = flatNumber
        identity.postalCode = postalCode
        identity.city = city
        identity.addressCountry = usesSwissAddress ? "CH" : addressCountryCode
        identity.usesSwissAddress = usesSwissAddress
        identity.phone = phone
        identity.phoneRegion = phoneRegionCode
        return identity
    }

    private var addressQuery: String {
        [street, flatNumber, postalCode, city].filter { !$0.isBlank }.joined(separator: " ")
    }

    private struct LookupKey: Equatable {
        let swiss: Bool
        let query: String
        let verified: Bool
        let focused: Bool
    }

    var body: some View {
        // Not gated on the swisstopo round trip. The lookup returns an empty list for no network,
        // a timeout and an unknown address alike, and an inspector standing in an empty flat with
        // no signal could not start a session at all. The address shape is still checked by
        // hasRequiredFields; the lookup is a confirmation, not a gate.
        let canStart = identity.hasRequiredFields() && (actor != .agency || company.trimmingCharacters(in: .whitespaces).count >= 2)
        let addressFieldsFocused = !focusedAddressFields.isEmpty
        let phoneIsValid = InternationalPhone.isValid(phone, regionCode: phoneRegionCode)
        VStack(spacing: 12) {
            PageMast(title: nil, onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Spacer(); LimenMark(size: 94); Spacer() }
                    Text(s.startNewSession).font(LimenType.titleMedium).foregroundStyle(colors.ink)
                    Panel(label: s.userType) {
                        EqualChoiceRow(options: [(Actor.tenant, s.role(.tenant)), (.landlord, s.actorLandlordPrivate), (.agency, s.actorAgency)], current: actor) { actor = $0 }
                    }
                    Panel(label: s.sessionKind) {
                        VStack(alignment: .leading, spacing: 8) {
                            EqualChoiceRow(options: [(Kind.entry, s.entry), (.exit, s.exit)], current: sessionKind, locked: entryToSeed != nil) { kind = $0 }
                            if let entryToSeed {
                                Text("\(s.exit) · \(entryToSeed.address.ifBlank(s.noAddress))").font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                            }
                        }
                    }
                    Panel(label: s.sessionIdentity) {
                        VStack(alignment: .leading, spacing: 10) {
                            if actor == .agency {
                                Field(label: s.companyName, value: company) { company = $0 }
                                Text(s.agencyRoleExplanation).font(LimenType.bodySmall).foregroundStyle(colors.inkDim)
                            }
                            Field(label: s.firstName, value: firstName) { firstName = $0 }
                            Field(label: s.lastName, value: lastName) { lastName = $0 }
                            Text(s.identityAddress).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            Text(s.addressType).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            EqualChoiceRow(options: [(true, s.swissAddress), (false, s.foreignAddress)], current: usesSwissAddress) { selectAddressMode($0) }
                            if !usesSwissAddress {
                                CountryDropDown(
                                    label: s.addressCountry,
                                    selectedLabel: CountryDirectory.addressCountries.first { $0.regionCode == addressCountryCode }?.label() ?? s.selectCountry,
                                    options: CountryDirectory.addressCountries,
                                    optionKey: { $0.regionCode },
                                    optionLabel: { $0.label() },
                                    emptyLabel: s.countryNoMatches
                                ) { addressCountryCode = $0.regionCode }
                                Text(s.foreignAddressHint).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            }
                            // The suggestions sit ABOVE the fields they fill. Below them they were
                            // the first thing the keyboard covered.
                            if usesSwissAddress, addressFieldsFocused, addressSearching {
                                Text(s.addressSearching).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            }
                            if usesSwissAddress, addressFieldsFocused {
                                AddressMatchList(matches: addressMatches, showFlag: false, onSelect: selectAddress)
                            }
                            if usesSwissAddress, addressVerified {
                                Text(s.addressVerified).font(LimenType.labelSmall).foregroundStyle(colors.seal)
                            }
                            Field(label: s.street, value: street, hint: usesSwissAddress ? s.addressLookupHint : nil, onFocusChanged: { setFocused("street", $0) }) { value in
                                changeAddress { street = value }
                            }
                            Field(label: s.flatNumber, value: flatNumber, onFocusChanged: { setFocused("flat", $0) }) { value in
                                changeAddress { flatNumber = value }
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Field(label: s.postalCode, value: postalCode, keyboard: usesSwissAddress ? .numberPad : .default, onFocusChanged: { setFocused("postal", $0) }) { value in
                                    changeAddress { postalCode = usesSwissAddress ? String(value.filter(\.isNumber).prefix(4)) : value }
                                }
                                .frame(width: 110)
                                Field(label: s.city, value: city, onFocusChanged: { setFocused("city", $0) }) { value in
                                    changeAddress { city = value }
                                }
                            }
                            if actor == .tenant, sessionKind == .exit {
                                Text(s.tenantExitAddressHint).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            }
                            CountryDropDown(
                                label: s.phoneCountry,
                                selectedLabel: (InternationalPhone.countries.first { $0.regionCode == phoneRegionCode } ?? InternationalPhone.countries.first { $0.regionCode == "CH" })?.label() ?? "CH",
                                options: InternationalPhone.countries,
                                optionKey: { $0.regionCode },
                                optionLabel: { $0.label() },
                                emptyLabel: s.countryNoMatches
                            ) { selected in
                                phoneRegionCode = selected.regionCode
                                phone = ""
                            }
                            Field(label: s.phoneNumber, value: phone, hint: s.phoneExample(InternationalPhone.example(phoneRegionCode)), keyboard: .phonePad, isError: !phone.isBlank && !phoneIsValid) { phone = $0 }
                            if !phone.isBlank {
                                Text(phoneIsValid ? s.validPhoneNumber : s.invalidPhoneNumber)
                                    .font(LimenType.labelSmall)
                                    .foregroundStyle(phoneIsValid ? colors.positive : colors.dangerOutline)
                            }
                        }
                    }
                    Spacer().frame(height: 4)
                    BigKey(label: "\(s.startNewSession) · \((sessionKind == .entry ? s.entry : s.exit).uppercased())", enabled: canStart) {
                        if let entryToSeed {
                            model.seedExitFrom(entryToSeed, sessionRole: actor.role, identity: identity)
                        } else {
                            model.startNewSession(role: actor.role, identity: identity, kind: sessionKind)
                        }
                    }
                    Spacer().frame(height: 20)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(colors.plate.ignoresSafeArea())
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let saved = model.profileName.trimmingCharacters(in: .whitespaces)
            let parts = saved.split(separator: " ", maxSplits: 1).map(String.init)
            firstName = parts.first ?? ""
            lastName = parts.count > 1 ? parts[1] : ""
            company = model.profileCompany
            if model.myRole == .landlord, !model.profileCompany.isBlank {
                actor = .agency
            } else if model.myRole == .landlord {
                actor = .landlord
            } else {
                actor = .tenant
            }
            kind = entryToSeed != nil ? .exit : .entry
        }
        .task(id: LookupKey(swiss: usesSwissAddress, query: addressQuery, verified: addressVerified, focused: addressFieldsFocused)) {
            if !usesSwissAddress || !addressFieldsFocused || addressVerified || addressQuery.trimmingCharacters(in: .whitespaces).count < 3 {
                addressMatches = []
                addressSearching = false
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            addressSearching = true
            let matches = await SwissAddressLookup.search(addressQuery)
            if Task.isCancelled { return }
            addressMatches = matches
            addressSearching = false
        }
    }

    private func changeAddress(_ change: () -> Void) {
        addressVerified = false
        addressMatches = []
        addressSearching = false
        change()
    }

    private func setFocused(_ field: String, _ focused: Bool) {
        if focused { focusedAddressFields.insert(field) } else { focusedAddressFields.remove(field) }
    }

    private func selectAddressMode(_ swiss: Bool) {
        usesSwissAddress = swiss
        addressVerified = false
        addressMatches = []
        focusedAddressFields = []
        addressCountryCode = swiss ? "CH" : ""
    }

    private func selectAddress(_ candidate: SwissAddressCandidate) {
        street = candidate.street
        flatNumber = candidate.flatNumber
        postalCode = candidate.postalCode
        city = candidate.city
        addressMatches = []
        addressVerified = true
    }
}

/// The official suggestions, one key each.
struct AddressMatchList: View {
    @Environment(\.limen) private var colors
    let matches: [SwissAddressCandidate]
    var showFlag = true
    let onSelect: (SwissAddressCandidate) -> Void

    var body: some View {
        if !matches.isEmpty {
            VStack(spacing: 6) {
                ForEach(matches) { candidate in
                    KeySurface(radius: 10, onPress: { onSelect(candidate) }) {
                        HStack(spacing: 10) {
                            if showFlag { CantonFlag(canton: candidate.canton, size: 26) }
                            Text(candidate.label)
                                .font(LimenType.bodyMedium)
                                .foregroundStyle(colors.ink)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Searchable dropdown: every supported country is available without a country-code wall of text.
struct CountryDropDown<T: Identifiable>: View {
    @Environment(\.limen) private var colors
    let label: String
    let selectedLabel: String
    let options: [T]
    let optionKey: (T) -> String
    let optionLabel: (T) -> String
    let emptyLabel: String
    let onSelect: (T) -> Void
    @State private var open = false
    @State private var query = ""

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button {
            Haptics.play(.key)
            query = ""
            open = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                HStack {
                    Text(selectedLabel).font(LimenType.bodyMedium).foregroundStyle(colors.ink).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").foregroundStyle(colors.inkDim)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.input)
            .clipShape(shape)
            .overlay(shape.strokeBorder(colors.actionOutline, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(selectedLabel)
        .sheet(isPresented: $open) {
            let visible = query.isBlank ? options : options.filter {
                optionLabel($0).localizedCaseInsensitiveContains(query) || optionKey($0).localizedCaseInsensitiveContains(query)
            }
            NavigationStack {
                List {
                    if visible.isEmpty {
                        Text(emptyLabel).foregroundStyle(colors.inkDim)
                    }
                    ForEach(visible) { option in
                        Button {
                            Haptics.play(.key)
                            onSelect(option)
                            open = false
                        } label: {
                            Text(optionLabel(option)).foregroundStyle(colors.ink).lineLimit(1)
                        }
                    }
                }
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
                .navigationTitle(label)
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.large])
        }
    }
}

struct EqualChoiceRow<T: Hashable>: View {
    let options: [(T, String)]
    let current: T
    var locked = false
    let onSelect: (T) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { value, label in
                Chip(label: label, active: value == current, enabled: !locked && value != current, selectionState: value == current, stretch: true) { onSelect(value) }
            }
        }
    }
}
