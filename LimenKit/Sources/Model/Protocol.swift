import Foundation

// The protocol on disk, one JSON file per handover, written by this app and read back years
// later when the exit protocol is seeded from the entry one. Every enum is written to the JSON
// by name and every field has a default, so a protocol written by version 1 must open in
// version 20: `schema` is bumped on breaking changes and the store migrates, never rejects.
//
// The model follows the paper canon (the MV mp form's 215 positions, the HEV form's cost
// column, the romand TB/B/M/O grades) rather than inventing its own vocabulary; the field names
// below are the English of those forms' terms. Field order matters here: it is the order the
// canonical JSON writes, and that JSON is what the evidence fingerprint covers. The reader is
// `ProtocolJSON`, which is where the Android `@EncodeDefault(NEVER)` annotations live.

public struct HandoverProtocol: Hashable, Sendable {
    public var schema: Int = 2
    public var id: String
    public var kind: Kind
    /// The person who started this handover; immutable once the session exists.
    public var sessionRole: Role?
    /// The starter's declared name, kept with this record rather than only on the device.
    public var sessionName: String = ""
    /// The starter's verified contact details, retained with this handover rather than on the phone.
    public var sessionIdentity = SessionIdentity()
    /// The responsible organisation printed on this handover's privacy and filing record.
    public var controllerIdentity = ControllerIdentity()
    /// Retained to export historic drafts; new Limen protocols use a simple condition check.
    public var style: GradeStyle = .binary
    /// Street and number.
    public var address: String = ""
    /// Postcode and place.
    public var place: String = ""
    /// Canton of the object, selected independently from every participant address.
    public var objectCanton: SwissCanton?
    /// True only when the lease expressly incorporates the non-binding Romand framework.
    public var romandFrameworkInLease = false
    /// Recorded outcomes for the dated canton overlay; absent from records made before it.
    public var legalOverlay = LegalOverlayRecord()
    /// Floor and position, the way regies write it: "3. OG links".
    public var objectDetail: String = ""
    /// ISO date of the handover itself, and the clock time beside it.
    public var handoverDate: String = ""
    public var handoverTime: String = ""
    /// When the previous protocol was made, from the form header; free text.
    public var lastProtocolDate: String = ""
    public var createdEpochMs: Int64
    public var parties: [Party] = []
    public var deposit = Deposit()
    public var meters = Meters()
    /// Keys that belong to no single room: house door, mailbox, cellar, garage.
    public var keys: [KeyCount] = []
    /// Whether the tenant declared having had copies made, the question everyone forgets.
    public var selfMadeKeys = false
    public var rooms: [Room] = []
    /// A deliberate room selection, including the valid outcome that no room is present.
    public var roomSetupComplete = false
    /// Legacy set-of-toggles inventory, superseded by `objects`; read only to export old records.
    public var extras = FlatExtras()
    /// Supplied appliances and furniture, one row each, so a row can carry its own photo.
    public var objects: [ObjectEntry] = []
    /// The tenancy's money and dates, present only when the handover has the contract to hand.
    public var contract = Contract()
    /// The optional dossier components this handover carries, held sorted by ordinal.
    public var dossier: [DossierCard] = []
    /// True once the operator has picked components by hand, which is the only way to tell an
    /// empty `dossier` that means "every component removed" from one that means "written before
    /// the dossier existed". Without it, removing the last card fell straight back to deriving
    /// the list from content and the card reappeared on the next frame.
    public var dossierChosen = false
    /// The fingerprint of the record this one corrects, captured when the amendment is created.
    /// The store id it used to print identifies nothing to a reader: every exported document
    /// names itself by "LIMEN-" and the first sixteen characters of its fingerprint, and the id
    /// appears on no PDF anywhere. Blank on amendments made before this was carried.
    public var amendedFromFingerprint: String = ""
    public var defects: [Defect] = []
    /// Free remarks, including the reservation lines a party dictates.
    public var remarks: String = ""
    /// "The service-charge statement will be drawn up by DATE", from the form footer.
    public var chargesStatementBy: String = ""
    /// Nobody on the other side of the threshold: the one-sided handover documented alone.
    public var oneSided = false
    /// Why the bilateral handover could not take place. Required for a unilateral record.
    public var unilateralReason: UnilateralReason?
    public var unilateralNote: String = ""
    /// The state of the key transfer, including a deliberate no-physical-keys outcome.
    public var keyTransfer: KeyTransferStatus = .notRecorded
    public var keyTransferNote: String = ""
    /// Reservations are entered before ink and copied into that person's signed outcome.
    public var pendingRecordReservations = OrderedMap<Role, String>()
    public var signatures: [Signature] = []
    /// The id of the entry protocol this exit protocol was seeded from, if any.
    public var seedId: String = ""
    /// The frozen document this draft amends, if it was changed after finalization.
    public var amendedFromId: String = ""
    /// Bumped for every material edit; ink is valid only for the revision it saw.
    public var contentRevision: Int64 = 0
    /// A finalized protocol is never edited in place. An edit becomes a new amendment.
    public var finalizedEpochMs: Int64 = 0
    /// SHA-256 over the finalized record and its original photo and ink files.
    public var evidenceFingerprint: String = ""
    /// A self-declared record that an identical copy was handed to a party.
    public var deliveryReceipts: [DeliveryReceipt] = []
    /// Last delivery-record change, so an updated final copy cannot be forgotten.
    public var deliveryMetadataEpochMs: Int64 = 0
    public var exportedEpochMs: Int64 = 0

    public init(id: String, kind: Kind, createdEpochMs: Int64) {
        self.id = id
        self.kind = kind
        self.createdEpochMs = createdEpochMs
    }

    /// The record plane has current ink from at least one person.
    public func isSigned() -> Bool {
        signatures.contains { $0.plane == .record && !$0.refused && !$0.file.isBlank && $0.contentRevision == contentRevision }
    }
    public func isFinalized() -> Bool { finalizedEpochMs > 0 && !evidenceFingerprint.isBlank }
    public func isExported() -> Bool { exportedEpochMs > 0 }
    public func isCurrent(_ signature: Signature) -> Bool { signature.contentRevision == contentRevision }
    public func copyDeliveredTo(_ role: Role) -> Bool { deliveryReceipts.contains { $0.role == role } }
    public func deliveryComplete() -> Bool { [Role.tenant, .landlord].allSatisfy(copyDeliveredTo) }
}

public enum Kind: String, CaseIterable, Hashable, Sendable {
    case entry = "Entry"
    case exit = "Exit"
}

/// Historic grading scales retained so older saved protocols can still be read and exported.
public enum GradeStyle: String, CaseIterable, Hashable, Sendable {
    /// Deutschschweiz: each item "in Ordnung" or carrying a defect.
    case binary = "Binary"
    /// Romandie: TB / B / M / O on every item, defects on top.
    case grades = "Grades"
}

/// An item's recorded state. `notChecked` is the honest default: an unvisited row prints
/// blank, never as silently fine. Binary style uses `ok` only; the romand style maps
/// TB=veryGood, B=good, M=fair, O=poor.
public enum Grade: String, CaseIterable, Hashable, Sendable {
    case notChecked = "NotChecked"
    case ok = "Ok"
    case veryGood = "VeryGood"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
}

public enum Role: String, CaseIterable, Hashable, Sendable {
    case tenant = "Tenant"
    case landlord = "Landlord"
    case nextTenant = "NextTenant"
    case witness = "Witness"
    case expert = "Expert"
}

public enum UnilateralReason: String, CaseIterable, Hashable, Sendable {
    case otherPartyAbsent = "OtherPartyAbsent"
    case refusedInspection = "RefusedInspection"
    case remoteKeyReturn = "RemoteKeyReturn"
    case other = "Other"
}

public enum KeyTransferStatus: String, CaseIterable, Hashable, Sendable {
    case notRecorded = "NotRecorded"
    case allTransferred = "AllTransferred"
    case noPhysicalKeys = "NoPhysicalKeys"
    case incomplete = "Incomplete"
}

public struct Party: Hashable, Sendable {
    public var role: Role
    public var name: String = ""
    /// The tenant's NEW address at an exit protocol, where the deposit letter will go.
    public var address: String = ""
    /// "vertreten durch": the regie's person, the tenant's proxy.
    public var representedBy: String = ""
    public var phone: String = ""
    public var email: String = ""

    public init(_ role: Role, name: String = "", address: String = "", representedBy: String = "", phone: String = "", email: String = "") {
        self.role = role
        self.name = name
        self.address = address
        self.representedBy = representedBy
        self.phone = phone
        self.email = email
    }
}

/// The person who opened this session and their contact address for this handover.
public struct SessionIdentity: Hashable, Sendable {
    public var firstName: String = ""
    public var lastName: String = ""
    /// The managing agency's firm name, when the landlord side is a Verwaltung/regie rather
    /// than a private person. The names above then belong to the representative present at
    /// the handover. Never encoded when blank, so finalized pre-agency records keep their fingerprint.
    public var company: String = ""
    public var street: String = ""
    /// Building number, with an optional flat supplement supplied by the person.
    public var flatNumber: String = ""
    public var postalCode: String = ""
    public var city: String = ""
    /// ISO 3166-1 alpha-2 country of the contact address.
    public var addressCountry: String = "CH"
    /// Swiss contact addresses are selected from swisstopo; foreign addresses are entered directly.
    public var usesSwissAddress = true
    public var phone: String = ""
    /// ISO 3166-1 alpha-2 region used to validate and format `phone`.
    public var phoneRegion: String = "CH"

    public init() {}

    public var fullName: String { [firstName, lastName].filter { !$0.isBlank }.joined(separator: " ") }
    public var addressLine: String { [street, flatNumber].filter { !$0.isBlank }.joined(separator: " ") }
    public var placeLine: String {
        var parts = [postalCode, city]
        if !usesSwissAddress { parts.append(CountryDirectory.name(addressCountry)) }
        return parts.filter { !$0.isBlank }.joined(separator: " ")
    }
}

/// Responsible controller details configured on this device and frozen into a new record.
public struct ControllerIdentity: Hashable, Sendable {
    public var organisation: String = ""
    public var contactName: String = ""
    public var street: String = ""
    public var postalCode: String = ""
    public var city: String = ""
    public var email: String = ""
    public var phone: String = ""

    public init() {}

    public var isBlank: Bool {
        [organisation, contactName, street, postalCode, city, email, phone].allSatisfy(\.isBlank)
    }
}

/// The deposit, asked once at entry and carried to exit, because the exit protocol ends with
/// the release instruction that matches `kind`. Insurance is SwissCaution and its competitors;
/// the premium world and the blocked-account world release differently.
public struct Deposit: Hashable, Sendable {
    public var kind: DepositKind = .none
    /// Held as typed: an amount is evidence, not arithmetic.
    public var amountChf: String = ""
    /// Insurance: the provider's name.
    public var provider: String = ""
    /// Insurance: certificate or policy number.
    public var policyNo: String = ""
    /// Bank account: the institute.
    public var bank: String = ""
    /// Bank account: IBAN or account number as printed on the deposit confirmation.
    public var account: String = ""

    public init() {}
}

public enum DepositKind: String, CaseIterable, Hashable, Sendable {
    case none = "None"
    case bankAccount = "BankAccount"
    case insurance = "Insurance"
}

/// The recurring Swiss rental-guarantee insurers shown in the setup picker. Only the
/// certificate's printed provider name is stored, so older and uncommon insurers remain intact
/// through `other` rather than being forced into a made-up category.
public enum CautionProvider: CaseIterable, Hashable, Sendable {
    case swissCaution, goCaution, firstcaution, smartCaution, axa, helvetia, zurich, other

    public var storedName: String? {
        switch self {
        case .swissCaution: return "SwissCaution"
        case .goCaution: return "goCaution"
        case .firstcaution: return "Firstcaution"
        case .smartCaution: return "SmartCaution"
        case .axa: return "AXA"
        case .helvetia: return "Helvetia"
        case .zurich: return "Zurich"
        case .other: return nil
        }
    }

    public static func fromStoredName(_ name: String) -> CautionProvider {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { $0.storedName == trimmed } ?? .other
    }
}

/// Meter readings from the form header. Strings, exactly as read off the dial.
public struct Meters: Hashable, Sendable {
    public var electricity1: String = ""
    public var electricity2: String = ""
    public var gas: String = ""
    public var water: String = ""
    public var hotWater: String = ""
    public var heatingOil: String = ""

    public init() {}

    /// Nothing was read off any dial.
    public var isBlank: Bool { [electricity1, electricity2, gas, water, hotWater, heatingOil].allSatisfy(\.isBlank) }
}

/// One kind of key and how many changed hands.
public struct KeyCount: Hashable, Sendable {
    public var kind: KeyKind
    public var label: String = ""
    public var count: Int = 0

    public init(_ kind: KeyKind, label: String = "", count: Int = 0) {
        self.kind = kind
        self.label = label
        self.count = count
    }
}

public enum KeyKind: String, CaseIterable, Hashable, Sendable {
    case apartment = "Apartment"
    case houseDoor = "HouseDoor"
    case mailbox = "Mailbox"
    case cellar = "Cellar"
    case attic = "Attic"
    case garage = "Garage"
    case other = "Other"
}

public struct Room: Hashable, Sendable {
    public var id: String
    public var kind: RoomKind
    /// Overrides the template name: "Chambre 2", "Bastelraum".
    public var name: String = ""
    public var items: [RoomItem] = []
    /// Keys of this room's own door, the way every MV room block ends.
    public var keysCount: Int = 0
    /// Explicit confirmation that this listed room was actually inspected.
    public var inspected = false
    /// Legacy v2 values retained solely to verify finalized v2 records; no longer shown or exported.
    public var freshPaintedWalls = false
    public var freshPaintedWoodwork = false
    public var newFloor = false
    public var fixtures: [RoomFixture] = []

    public init(id: String, kind: RoomKind, name: String = "", items: [RoomItem] = [], keysCount: Int = 0, inspected: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name
        self.items = items
        self.keysCount = keysCount
        self.inspected = inspected
    }

    /// True when this room was recorded with the exhaustive item grid, which the export still
    /// prints so a signed record keeps showing the parties what they signed. New rooms hold no
    /// items at all: a room's record is its defects.
    public var hasLegacyGrid: Bool { !items.isEmpty }
}

public enum RoomFixture: String, CaseIterable, Hashable, Sendable {
    case fridge = "Fridge"
    case freezer = "Freezer"
    case dishwasher = "Dishwasher"
    case washingMachine = "WashingMachine"
    case dryer = "Dryer"
    case furniture = "Furniture"
}

/// One supplied appliance, piece of furniture or anything else handed over with the flat.
///
/// A row, not a toggle, because two identical fridges are two facts and each needs its own
/// photo. `catalogue` names an `Appliance` or `Furniture` entry when the row came from the
/// shipped list, so it stays translatable; `label` carries the rest verbatim.
public struct ObjectEntry: Hashable, Sendable {
    public var id: String
    public var group: ObjectGroup
    /// Names an `ObjectGroup.other` group: "Garden tools", "Cellar shelving".
    public var groupLabel: String = ""
    /// `Appliance` or `Furniture` entry name when the row came from the shipped list.
    public var catalogue: String = ""
    /// Free text name when no shipped entry stands behind the row.
    public var label: String = ""
    /// Which room it stands in. Blank means the object as a whole.
    public var roomId: String = ""
    public var note: String = ""
    /// Explicit confirmation that this supplied item and its condition were checked.
    public var inspected = false
    /// File names under the protocol's photo directory, in the order they were taken.
    public var photos: [String] = []
    public var photoEvidence: [PhotoEvidence] = []

    public init(id: String, group: ObjectGroup, groupLabel: String = "", catalogue: String = "", label: String = "", roomId: String = "", note: String = "", inspected: Bool = false, photos: [String] = [], photoEvidence: [PhotoEvidence] = []) {
        self.id = id
        self.group = group
        self.groupLabel = groupLabel
        self.catalogue = catalogue
        self.label = label
        self.roomId = roomId
        self.note = note
        self.inspected = inspected
        self.photos = photos
        self.photoEvidence = photoEvidence
    }

    /// Every photo file this object points at, from either list, once each.
    public func photoFiles() -> [String] {
        (photos + photoEvidence.map(\.file)).filter { !$0.isBlank }.distinct()
    }
}

public enum ObjectGroup: String, CaseIterable, Hashable, Sendable {
    case appliance = "Appliance"
    case furniture = "Furniture"
    case other = "Other"
}

/// The tenancy itself: what is paid and from when to when. Amounts are held as typed for the
/// same reason `Deposit.amountChf` is, and dates are free text because a contract's dates are
/// copied off paper that does not always agree with ISO.
public struct Contract: Hashable, Sendable {
    public var monthlyRentChf: String = ""
    public var serviceChargesChf: String = ""
    /// ISO date on which the lease was concluded or signed, when known.
    public var conclusionDate: String = ""
    public var startDate: String = ""
    public var endDate: String = ""
    /// When notice was given, the date every deposit argument eventually turns on.
    public var noticeDate: String = ""

    public init() {}
}

/// A dossier component the person adds only when this handover has it. Address, parties and
/// identity are not here: a protocol without them is not a protocol, so they are always shown.
public enum DossierCard: String, CaseIterable, Hashable, Sendable {
    case contract = "Contract"
    case deposit = "Deposit"
    case meters = "Meters"
    case keys = "Keys"
    case notes = "Notes"

    public var ordinal: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// The supplied extras are about the flat, not an artificial attachment to one room.
public struct FlatExtras: Hashable, Sendable {
    public var appliances: [Appliance] = []
    public var furniture: [Furniture] = []
    public var customAppliances: [String] = []
    public var customFurniture: [String] = []

    public init() {}
}

public enum Appliance: String, CaseIterable, Hashable, Sendable {
    case fridge = "Fridge"
    case freezer = "Freezer"
    case oven = "Oven"
    case hob = "Hob"
    case microwave = "Microwave"
    case dishwasher = "Dishwasher"
    case washingMachine = "WashingMachine"
    case dryer = "Dryer"

    public var ordinal: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

public enum Furniture: String, CaseIterable, Hashable, Sendable {
    case bed = "Bed"
    case wardrobe = "Wardrobe"
    case table = "Table"
    case chairs = "Chairs"
    case sofa = "Sofa"
    case desk = "Desk"
    case shelving = "Shelving"
    case bookcase = "Bookcase"

    public var ordinal: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

public struct RoomItem: Hashable, Sendable {
    public var key: ItemKey
    /// Names an `ItemKey.custom` row; empty otherwise.
    public var label: String = ""
    public var grade: Grade = .notChecked
    /// Stable row identity: permits repeated custom rows to carry separate defects.
    public var itemId: String = ""

    public init(_ key: ItemKey, label: String = "", grade: Grade = .notChecked, itemId: String = "") {
        self.key = key
        self.label = label
        self.grade = grade
        self.itemId = itemId
    }
}

/// One defect, itemized the way Art. 267a OR demands: location (room, item), nature (text, in
/// the "3 cm2 water stain under the north window" register), and the explicit charge. Ticino
/// case law voids an exit notice whose defects are not specifically imputed, so
/// `chargedToTenant` is first-class and prints as its own column.
public struct Defect: Hashable, Sendable {
    public var id: String
    /// The room it belongs to, or blank when `objectId` carries the location instead.
    public var roomId: String = ""
    /// The item row it hangs on, or nil for a whole-room finding.
    public var item: ItemKey?
    public var text: String = ""
    /// File names under the protocol's photo directory, in the order they were taken.
    public var photos: [String] = []
    /// Hashes and capture moments for photos added in version 2 or later.
    public var photoEvidence: [PhotoEvidence] = []
    public var chargedToTenant = false
    public var fixBy: FixBy = .open
    /// "by DATE" of the remediation table; free text.
    public var fixDeadline: String = ""
    /// Cost note or estimate reservation, the HEV form's KA column.
    public var costNote: String = ""
    /// The party's dictated reservation on this one finding: "conteste", "already at entry".
    public var reservation: String = ""
    /// The tenant can state a position without the app treating it as an admission.
    public var tenantResponse: TenantResponse = .notStated
    public var tenantComment: String = ""
    /// The exact `RoomItem` this finding belongs to; blank retains historic key-only records.
    public var itemId: String = ""
    /// Names an `ItemKey.custom` finding, where no template row carries the wording.
    public var itemLabel: String = ""
    /// Set instead of `roomId` when the finding is about a supplied `ObjectEntry`.
    public var objectId: String = ""

    public init(id: String, roomId: String = "", item: ItemKey? = nil, text: String = "", photos: [String] = [], photoEvidence: [PhotoEvidence] = [], chargedToTenant: Bool = false, fixBy: FixBy = .open, fixDeadline: String = "", costNote: String = "", reservation: String = "", tenantResponse: TenantResponse = .notStated, tenantComment: String = "", itemId: String = "", itemLabel: String = "", objectId: String = "") {
        self.id = id
        self.roomId = roomId
        self.item = item
        self.text = text
        self.photos = photos
        self.photoEvidence = photoEvidence
        self.chargedToTenant = chargedToTenant
        self.fixBy = fixBy
        self.fixDeadline = fixDeadline
        self.costNote = costNote
        self.reservation = reservation
        self.tenantResponse = tenantResponse
        self.tenantComment = tenantComment
        self.itemId = itemId
        self.itemLabel = itemLabel
        self.objectId = objectId
    }

    /// True while a finding carries nothing but the place it hangs on. Written as a comparison
    /// against a fresh shell rather than a list of blank checks, so a field added later cannot
    /// quietly fall out of the test and take a recorded answer with it.
    public var isUntouched: Bool {
        self == Defect(id: id, roomId: roomId, item: item, itemId: itemId, itemLabel: itemLabel, objectId: objectId)
    }

    /// Every photo file this defect points at, from either list, once each.
    public func photoFiles() -> [String] {
        (photos + photoEvidence.map(\.file)).filter { !$0.isBlank }.distinct()
    }
}

public enum FixBy: String, CaseIterable, Hashable, Sendable {
    case open = "Open"
    case tenant = "Tenant"
    case landlord = "Landlord"
}

public struct PhotoEvidence: Hashable, Sendable {
    public var file: String
    public var sha256: String = ""
    public var capturedEpochMs: Int64 = 0
    public var source: PhotoSource = .unknown

    public init(_ file: String, sha256: String = "", capturedEpochMs: Int64 = 0, source: PhotoSource = .unknown) {
        self.file = file
        self.sha256 = sha256
        self.capturedEpochMs = capturedEpochMs
        self.source = source
    }
}

public enum PhotoSource: String, CaseIterable, Hashable, Sendable {
    case camera = "Camera"
    case gallery = "Gallery"
    case unknown = "Unknown"
}

public enum TenantResponse: String, CaseIterable, Hashable, Sendable {
    case notStated = "NotStated"
    case agrees = "Agrees"
    case disputes = "Disputes"
    case normalWear = "NormalWear"
    case existingAtEntry = "ExistingAtEntry"
}

public struct DeliveryReceipt: Hashable, Sendable {
    public var role: Role
    public var epochMs: Int64 = 0
    public var method: DeliveryMethod = .inPerson
    public var note: String = ""

    public init(_ role: Role, epochMs: Int64 = 0, method: DeliveryMethod = .inPerson, note: String = "") {
        self.role = role
        self.epochMs = epochMs
        self.method = method
        self.note = note
    }
}

public enum DeliveryMethod: String, CaseIterable, Hashable, Sendable {
    case inPerson = "InPerson"
    case electronic = "Electronic"
    case registeredMail = "RegisteredMail"
    case other = "Other"
}

/// One ink signature confirming the handover observations and any written reservation.
public struct Signature: Hashable, Sendable {
    public var role: Role
    public var name: String = ""
    public var plane: Plane
    /// PNG file name under the protocol's signature directory; empty when `refused`.
    public var file: String = ""
    /// Refusal is a recorded outcome, not a failure, and prints as such.
    public var refused = false
    /// The signer's reservation, printed beside the signature: "sous reserve d'un devis".
    public var reservation: String = ""
    public var epochMs: Int64 = 0
    /// The protocol revision shown to the signer.
    public var contentRevision: Int64 = 0

    public init(_ role: Role, name: String = "", plane: Plane, file: String = "", refused: Bool = false, reservation: String = "", epochMs: Int64 = 0, contentRevision: Int64 = 0) {
        self.role = role
        self.name = name
        self.plane = plane
        self.file = file
        self.refused = refused
        self.reservation = reservation
        self.epochMs = epochMs
        self.contentRevision = contentRevision
    }
}

/// `costs` remains only so records created by older Limen versions still deserialize.
public enum Plane: String, CaseIterable, Hashable, Sendable {
    case record = "Record"
    case costs = "Costs"
}

extension HandoverProtocol {
    /// Which dossier components this record carries.
    ///
    /// Records written before the dossier existed answer from their content instead, and the
    /// derived answer is never written back: `schema` cannot identify them (the store omits
    /// defaulted fields, so no file ever carried it), and writing a derived value into a
    /// finalized record would change its canonical JSON and void its fingerprint.
    public func dossierCards() -> [DossierCard] {
        // dossier first, so a record whose components were chosen before the flag existed still
        // answers from its own list rather than from its content.
        if dossierChosen || !dossier.isEmpty { return dossier }
        var cards: [DossierCard] = []
        if contract != Contract() { cards.append(.contract) }
        if deposit.kind != .none { cards.append(.deposit) }
        if !meters.isBlank { cards.append(.meters) }
        if selfMadeKeys || keys.contains(where: { $0.count >= 1 }) || rooms.contains(where: { $0.keysCount > 0 }) {
            cards.append(.keys)
        }
        if !remarks.isBlank || !chargesStatementBy.isBlank || oneSided { cards.append(.notes) }
        return cards
    }

    public func carries(_ card: DossierCard) -> Bool { dossierCards().contains(card) }
}

/// A map that keeps its insertion order, the way Kotlin's default `Map` does, so the canonical
/// JSON writes the entries in the order they were recorded. Equality ignores the order, as
/// Kotlin's `Map` equality does: the fingerprint reads the order, the code never has to.
public struct OrderedMap<Key: Hashable & Sendable, Value: Hashable & Sendable>: Hashable, Sendable {
    public private(set) var entries: [(key: Key, value: Value)] = []

    public init() {}
    public init(_ pairs: [(Key, Value)]) {
        for (key, value) in pairs { self[key] = value }
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var keys: [Key] { entries.map(\.key) }
    public var count: Int { entries.count }

    public subscript(key: Key) -> Value? {
        get { entries.first { $0.key == key }?.value }
        set {
            if let index = entries.firstIndex(where: { $0.key == key }) {
                if let newValue { entries[index].value = newValue } else { entries.remove(at: index) }
            } else if let newValue {
                entries.append((key, newValue))
            }
        }
    }

    public func removing(_ key: Key) -> OrderedMap {
        var copy = self
        copy[key] = nil
        return copy
    }

    public func setting(_ key: Key, _ value: Value) -> OrderedMap {
        var copy = self
        copy[key] = value
        return copy
    }

    private var dictionary: [Key: Value] { Dictionary(entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last }) }

    public static func == (lhs: OrderedMap, rhs: OrderedMap) -> Bool { lhs.dictionary == rhs.dictionary }
    public func hash(into hasher: inout Hasher) { hasher.combine(dictionary) }
}

extension String {
    /// Kotlin's `isBlank`: empty or whitespace only.
    public var isBlank: Bool { allSatisfy(\.isWhitespace) }
    /// Kotlin's `ifBlank`.
    public func ifBlank(_ fallback: () -> String) -> String { isBlank ? fallback() : self }
    public func ifBlank(_ fallback: String) -> String { isBlank ? fallback : self }
}

extension Array where Element: Hashable {
    /// Kotlin's `distinct()`: first occurrence wins, order kept.
    public func distinct() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
