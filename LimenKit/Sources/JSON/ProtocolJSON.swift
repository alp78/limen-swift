import Foundation

/// The record's JSON, in and out, field for field with the Android `Protocol` serializer.
///
/// Two writers share one description of each type: the store's (`encodeDefaults: false`, so a
/// file omits everything left at its default) and the fingerprint's (`encodeDefaults: true`, so
/// the canonical text spells every field out). The `never` marks are the Android
/// `@EncodeDefault(NEVER)` annotations, which keep a field added after a record was signed out
/// of that record's canonical text: the guard `LegacyCompatTests` pins.
public enum ProtocolJSON {
    public static func encode(_ p: HandoverProtocol, encodeDefaults: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: encodeDefaults)
        b.put("schema", p.schema, default: 2) { .int(Int64($0)) }
        b.always("id", .string(p.id))
        b.always("kind", .string(p.kind.rawValue))
        b.put("sessionRole", p.sessionRole, default: nil, never: true) { $0.map { .string($0.rawValue) } ?? .null }
        b.put("sessionName", p.sessionName, default: "", never: true, JSON.string)
        b.put("sessionIdentity", p.sessionIdentity, default: SessionIdentity(), never: true) { sessionIdentity($0, encodeDefaults) }
        b.put("controllerIdentity", p.controllerIdentity, default: ControllerIdentity(), never: true) { controllerIdentity($0, encodeDefaults) }
        b.put("style", p.style, default: .binary) { .string($0.rawValue) }
        b.put("address", p.address, default: "", JSON.string)
        b.put("place", p.place, default: "", JSON.string)
        b.put("objectCanton", p.objectCanton, default: nil, never: true) { $0.map { .string($0.rawValue) } ?? .null }
        b.put("romandFrameworkInLease", p.romandFrameworkInLease, default: false, never: true, JSON.bool)
        b.put("legalOverlay", p.legalOverlay, default: LegalOverlayRecord(), never: true) { legalOverlay($0, encodeDefaults) }
        b.put("objectDetail", p.objectDetail, default: "", JSON.string)
        b.put("handoverDate", p.handoverDate, default: "", JSON.string)
        b.put("handoverTime", p.handoverTime, default: "", JSON.string)
        b.put("lastProtocolDate", p.lastProtocolDate, default: "", JSON.string)
        b.always("createdEpochMs", .int(p.createdEpochMs))
        b.put("parties", p.parties, default: []) { .array($0.map { party($0, encodeDefaults) }) }
        b.put("deposit", p.deposit, default: Deposit()) { deposit($0, encodeDefaults) }
        b.put("meters", p.meters, default: Meters()) { meters($0, encodeDefaults) }
        b.put("keys", p.keys, default: []) { .array($0.map { keyCount($0, encodeDefaults) }) }
        b.put("selfMadeKeys", p.selfMadeKeys, default: false, JSON.bool)
        b.put("rooms", p.rooms, default: []) { .array($0.map { room($0, encodeDefaults) }) }
        b.put("roomSetupComplete", p.roomSetupComplete, default: false, never: true, JSON.bool)
        b.put("extras", p.extras, default: FlatExtras(), never: true) { extras($0, encodeDefaults) }
        b.put("objects", p.objects, default: [], never: true) { .array($0.map { objectEntry($0, encodeDefaults) }) }
        b.put("contract", p.contract, default: Contract(), never: true) { contract($0, encodeDefaults) }
        b.put("dossier", p.dossier, default: [], never: true) { .array($0.map { .string($0.rawValue) }) }
        b.put("dossierChosen", p.dossierChosen, default: false, never: true, JSON.bool)
        b.put("amendedFromFingerprint", p.amendedFromFingerprint, default: "", never: true, JSON.string)
        b.put("defects", p.defects, default: []) { .array($0.map { defect($0, encodeDefaults) }) }
        b.put("remarks", p.remarks, default: "", JSON.string)
        b.put("chargesStatementBy", p.chargesStatementBy, default: "", JSON.string)
        b.put("oneSided", p.oneSided, default: false, JSON.bool)
        b.put("unilateralReason", p.unilateralReason, default: nil, never: true) { $0.map { .string($0.rawValue) } ?? .null }
        b.put("unilateralNote", p.unilateralNote, default: "", never: true, JSON.string)
        b.put("keyTransfer", p.keyTransfer, default: .notRecorded, never: true) { .string($0.rawValue) }
        b.put("keyTransferNote", p.keyTransferNote, default: "", never: true, JSON.string)
        b.put("pendingRecordReservations", p.pendingRecordReservations, default: OrderedMap(), never: true) { map in
            .object(map.entries.map { ($0.key.rawValue, .string($0.value)) })
        }
        b.put("signatures", p.signatures, default: []) { .array($0.map { signature($0, encodeDefaults) }) }
        b.put("seedId", p.seedId, default: "", JSON.string)
        b.put("amendedFromId", p.amendedFromId, default: "", JSON.string)
        b.put("contentRevision", p.contentRevision, default: 0, JSON.int)
        b.put("finalizedEpochMs", p.finalizedEpochMs, default: 0, JSON.int)
        b.put("evidenceFingerprint", p.evidenceFingerprint, default: "", JSON.string)
        b.put("deliveryReceipts", p.deliveryReceipts, default: []) { .array($0.map { deliveryReceipt($0, encodeDefaults) }) }
        b.put("deliveryMetadataEpochMs", p.deliveryMetadataEpochMs, default: 0, never: true, JSON.int)
        b.put("exportedEpochMs", p.exportedEpochMs, default: 0, JSON.int)
        return b.json
    }

    private static func sessionIdentity(_ v: SessionIdentity, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.put("firstName", v.firstName, default: "", JSON.string)
        b.put("lastName", v.lastName, default: "", JSON.string)
        b.put("company", v.company, default: "", never: true, JSON.string)
        b.put("street", v.street, default: "", JSON.string)
        b.put("flatNumber", v.flatNumber, default: "", JSON.string)
        b.put("postalCode", v.postalCode, default: "", JSON.string)
        b.put("city", v.city, default: "", JSON.string)
        b.put("addressCountry", v.addressCountry, default: "CH", JSON.string)
        b.put("usesSwissAddress", v.usesSwissAddress, default: true, JSON.bool)
        b.put("phone", v.phone, default: "", JSON.string)
        b.put("phoneRegion", v.phoneRegion, default: "CH", JSON.string)
        return b.json
    }

    private static func controllerIdentity(_ v: ControllerIdentity, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.put("organisation", v.organisation, default: "", JSON.string)
        b.put("contactName", v.contactName, default: "", JSON.string)
        b.put("street", v.street, default: "", JSON.string)
        b.put("postalCode", v.postalCode, default: "", JSON.string)
        b.put("city", v.city, default: "", JSON.string)
        b.put("email", v.email, default: "", JSON.string)
        b.put("phone", v.phone, default: "", JSON.string)
        return b.json
    }

    private static func legalOverlay(_ v: LegalOverlayRecord, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.put("checks", v.checks, default: OrderedMap()) { map in
            .object(map.entries.map { ($0.key.rawValue, .string($0.value.rawValue)) })
        }
        b.put("note", v.note, default: "", JSON.string)
        b.put("ruleSetId", v.ruleSetId, default: "", JSON.string)
        return b.json
    }

    private static func party(_ v: Party, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.always("role", .string(v.role.rawValue))
        b.put("name", v.name, default: "", JSON.string)
        b.put("address", v.address, default: "", JSON.string)
        b.put("representedBy", v.representedBy, default: "", JSON.string)
        b.put("phone", v.phone, default: "", JSON.string)
        b.put("email", v.email, default: "", JSON.string)
        return b.json
    }

    private static func deposit(_ v: Deposit, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.put("kind", v.kind, default: .none) { .string($0.rawValue) }
        b.put("amountChf", v.amountChf, default: "", JSON.string)
        b.put("provider", v.provider, default: "", JSON.string)
        b.put("policyNo", v.policyNo, default: "", JSON.string)
        b.put("bank", v.bank, default: "", JSON.string)
        b.put("account", v.account, default: "", JSON.string)
        return b.json
    }

    private static func meters(_ v: Meters, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.put("electricity1", v.electricity1, default: "", JSON.string)
        b.put("electricity2", v.electricity2, default: "", JSON.string)
        b.put("gas", v.gas, default: "", JSON.string)
        b.put("water", v.water, default: "", JSON.string)
        b.put("hotWater", v.hotWater, default: "", JSON.string)
        b.put("heatingOil", v.heatingOil, default: "", JSON.string)
        return b.json
    }

    private static func keyCount(_ v: KeyCount, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.always("kind", .string(v.kind.rawValue))
        b.put("label", v.label, default: "", JSON.string)
        b.put("count", v.count, default: 0) { .int(Int64($0)) }
        return b.json
    }

    private static func room(_ v: Room, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.always("id", .string(v.id))
        b.always("kind", .string(v.kind.rawValue))
        b.put("name", v.name, default: "", JSON.string)
        b.put("items", v.items, default: []) { .array($0.map { roomItem($0, d) }) }
        b.put("keysCount", v.keysCount, default: 0) { .int(Int64($0)) }
        b.put("inspected", v.inspected, default: false, never: true, JSON.bool)
        b.put("freshPaintedWalls", v.freshPaintedWalls, default: false, JSON.bool)
        b.put("freshPaintedWoodwork", v.freshPaintedWoodwork, default: false, JSON.bool)
        b.put("newFloor", v.newFloor, default: false, JSON.bool)
        b.put("fixtures", v.fixtures, default: []) { .array($0.map { .string($0.rawValue) }) }
        return b.json
    }

    private static func roomItem(_ v: RoomItem, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.always("key", .string(v.key.rawValue))
        b.put("label", v.label, default: "", JSON.string)
        b.put("grade", v.grade, default: .notChecked) { .string($0.rawValue) }
        b.put("itemId", v.itemId, default: "", never: true, JSON.string)
        return b.json
    }

    private static func objectEntry(_ v: ObjectEntry, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.always("id", .string(v.id))
        b.always("group", .string(v.group.rawValue))
        b.put("groupLabel", v.groupLabel, default: "", JSON.string)
        b.put("catalogue", v.catalogue, default: "", JSON.string)
        b.put("label", v.label, default: "", JSON.string)
        b.put("roomId", v.roomId, default: "", JSON.string)
        b.put("note", v.note, default: "", JSON.string)
        b.put("inspected", v.inspected, default: false, never: true, JSON.bool)
        b.put("photos", v.photos, default: []) { .array($0.map(JSON.string)) }
        b.put("photoEvidence", v.photoEvidence, default: []) { .array($0.map { photoEvidence($0, d) }) }
        return b.json
    }

    private static func contract(_ v: Contract, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.put("monthlyRentChf", v.monthlyRentChf, default: "", JSON.string)
        b.put("serviceChargesChf", v.serviceChargesChf, default: "", JSON.string)
        b.put("conclusionDate", v.conclusionDate, default: "", never: true, JSON.string)
        b.put("startDate", v.startDate, default: "", JSON.string)
        b.put("endDate", v.endDate, default: "", JSON.string)
        b.put("noticeDate", v.noticeDate, default: "", JSON.string)
        return b.json
    }

    private static func extras(_ v: FlatExtras, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.put("appliances", v.appliances, default: []) { .array($0.map { .string($0.rawValue) }) }
        b.put("furniture", v.furniture, default: []) { .array($0.map { .string($0.rawValue) }) }
        b.put("customAppliances", v.customAppliances, default: []) { .array($0.map(JSON.string)) }
        b.put("customFurniture", v.customFurniture, default: []) { .array($0.map(JSON.string)) }
        return b.json
    }

    private static func defect(_ v: Defect, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.always("id", .string(v.id))
        b.put("roomId", v.roomId, default: "", JSON.string)
        b.put("item", v.item, default: nil) { $0.map { .string($0.rawValue) } ?? .null }
        b.put("text", v.text, default: "", JSON.string)
        b.put("photos", v.photos, default: []) { .array($0.map(JSON.string)) }
        b.put("photoEvidence", v.photoEvidence, default: []) { .array($0.map { photoEvidence($0, d) }) }
        b.put("chargedToTenant", v.chargedToTenant, default: false, JSON.bool)
        b.put("fixBy", v.fixBy, default: .open) { .string($0.rawValue) }
        b.put("fixDeadline", v.fixDeadline, default: "", JSON.string)
        b.put("costNote", v.costNote, default: "", JSON.string)
        b.put("reservation", v.reservation, default: "", JSON.string)
        b.put("tenantResponse", v.tenantResponse, default: .notStated) { .string($0.rawValue) }
        b.put("tenantComment", v.tenantComment, default: "", JSON.string)
        b.put("itemId", v.itemId, default: "", never: true, JSON.string)
        b.put("itemLabel", v.itemLabel, default: "", never: true, JSON.string)
        b.put("objectId", v.objectId, default: "", never: true, JSON.string)
        return b.json
    }

    private static func photoEvidence(_ v: PhotoEvidence, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.always("file", .string(v.file))
        b.put("sha256", v.sha256, default: "", JSON.string)
        b.put("capturedEpochMs", v.capturedEpochMs, default: 0, JSON.int)
        b.put("source", v.source, default: .unknown) { .string($0.rawValue) }
        return b.json
    }

    private static func deliveryReceipt(_ v: DeliveryReceipt, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.always("role", .string(v.role.rawValue))
        b.put("epochMs", v.epochMs, default: 0, JSON.int)
        b.put("method", v.method, default: .inPerson) { .string($0.rawValue) }
        b.put("note", v.note, default: "", JSON.string)
        return b.json
    }

    private static func signature(_ v: Signature, _ d: Bool) -> JSON {
        var b = ObjectBuilder(encodeDefaults: d)
        b.always("role", .string(v.role.rawValue))
        b.put("name", v.name, default: "", JSON.string)
        b.always("plane", .string(v.plane.rawValue))
        b.put("file", v.file, default: "", JSON.string)
        b.put("refused", v.refused, default: false, JSON.bool)
        b.put("reservation", v.reservation, default: "", JSON.string)
        b.put("epochMs", v.epochMs, default: 0, JSON.int)
        b.put("contentRevision", v.contentRevision, default: 0, JSON.int)
        return b.json
    }

    // MARK: Reading

    public static func decode(_ data: Data) throws -> HandoverProtocol {
        let any = try JSONSerialization.jsonObject(with: data)
        let root = try ObjectReader(any)
        // The two maps on the record are written in insertion order and read back the same way;
        // JSONSerialization loses that order, so it is recovered from the text itself.
        let order = MapKeyOrder.scan(data)
        let identity = try root.object("sessionIdentity").map(sessionIdentity) ?? SessionIdentity()
        var p = HandoverProtocol(id: try root.requiredString("id"), kind: try root.requiredEnum("kind"), createdEpochMs: try root.requiredInt("createdEpochMs"))
        p.schema = Int(try root.int("schema", default: 2))
        p.sessionRole = try root.optionalEnum("sessionRole")
        p.sessionName = try root.string("sessionName")
        p.sessionIdentity = identity
        p.controllerIdentity = try root.object("controllerIdentity").map(controllerIdentity) ?? ControllerIdentity()
        p.style = try root.enumValue("style", default: .binary)
        p.address = try root.string("address")
        p.place = try root.string("place")
        p.objectCanton = try root.optionalEnum("objectCanton")
        p.romandFrameworkInLease = try root.bool("romandFrameworkInLease")
        p.legalOverlay = try root.object("legalOverlay").map { try legalOverlay($0, order) } ?? LegalOverlayRecord()
        p.objectDetail = try root.string("objectDetail")
        p.handoverDate = try root.string("handoverDate")
        p.handoverTime = try root.string("handoverTime")
        p.lastProtocolDate = try root.string("lastProtocolDate")
        p.parties = try root.objects("parties").map(party)
        p.deposit = try root.object("deposit").map(deposit) ?? Deposit()
        p.meters = try root.object("meters").map(meters) ?? Meters()
        p.keys = try root.objects("keys").map(keyCount)
        p.selfMadeKeys = try root.bool("selfMadeKeys")
        p.rooms = try root.objects("rooms").map(room)
        p.roomSetupComplete = try root.bool("roomSetupComplete")
        p.extras = try root.object("extras").map(extras) ?? FlatExtras()
        p.objects = try root.objects("objects").map(objectEntry)
        p.contract = try root.object("contract").map(contract) ?? Contract()
        p.dossier = try root.enums("dossier")
        p.dossierChosen = try root.bool("dossierChosen")
        p.amendedFromFingerprint = try root.string("amendedFromFingerprint")
        p.defects = try root.objects("defects").map(defect)
        p.remarks = try root.string("remarks")
        p.chargesStatementBy = try root.string("chargesStatementBy")
        p.oneSided = try root.bool("oneSided")
        p.unilateralReason = try root.optionalEnum("unilateralReason")
        p.unilateralNote = try root.string("unilateralNote")
        p.keyTransfer = try root.enumValue("keyTransfer", default: .notRecorded)
        p.keyTransferNote = try root.string("keyTransferNote")
        p.pendingRecordReservations = try root.orderedStringMap("pendingRecordReservations", order: order)
        p.signatures = try root.objects("signatures").map(signature)
        p.seedId = try root.string("seedId")
        p.amendedFromId = try root.string("amendedFromId")
        p.contentRevision = try root.int("contentRevision")
        p.finalizedEpochMs = try root.int("finalizedEpochMs")
        p.evidenceFingerprint = try root.string("evidenceFingerprint")
        p.deliveryReceipts = try root.objects("deliveryReceipts").map(deliveryReceipt)
        p.deliveryMetadataEpochMs = try root.int("deliveryMetadataEpochMs")
        p.exportedEpochMs = try root.int("exportedEpochMs")
        return p
    }

    private static func sessionIdentity(_ r: ObjectReader) throws -> SessionIdentity {
        var v = SessionIdentity()
        v.firstName = try r.string("firstName")
        v.lastName = try r.string("lastName")
        v.company = try r.string("company")
        v.street = try r.string("street")
        v.flatNumber = try r.string("flatNumber")
        v.postalCode = try r.string("postalCode")
        v.city = try r.string("city")
        v.addressCountry = try r.string("addressCountry", default: "CH")
        v.usesSwissAddress = try r.bool("usesSwissAddress", default: true)
        v.phone = try r.string("phone")
        v.phoneRegion = try r.string("phoneRegion", default: "CH")
        return v
    }

    private static func controllerIdentity(_ r: ObjectReader) throws -> ControllerIdentity {
        var v = ControllerIdentity()
        v.organisation = try r.string("organisation")
        v.contactName = try r.string("contactName")
        v.street = try r.string("street")
        v.postalCode = try r.string("postalCode")
        v.city = try r.string("city")
        v.email = try r.string("email")
        v.phone = try r.string("phone")
        return v
    }

    private static func legalOverlay(_ r: ObjectReader, _ order: [String: [String]]) throws -> LegalOverlayRecord {
        var v = LegalOverlayRecord()
        v.checks = try r.orderedEnumMap("checks", order: order)
        v.note = try r.string("note")
        v.ruleSetId = try r.string("ruleSetId")
        return v
    }

    private static func party(_ r: ObjectReader) throws -> Party {
        Party(
            try r.requiredEnum("role"),
            name: try r.string("name"),
            address: try r.string("address"),
            representedBy: try r.string("representedBy"),
            phone: try r.string("phone"),
            email: try r.string("email")
        )
    }

    private static func deposit(_ r: ObjectReader) throws -> Deposit {
        var v = Deposit()
        v.kind = try r.enumValue("kind", default: .none)
        v.amountChf = try r.string("amountChf")
        v.provider = try r.string("provider")
        v.policyNo = try r.string("policyNo")
        v.bank = try r.string("bank")
        v.account = try r.string("account")
        return v
    }

    private static func meters(_ r: ObjectReader) throws -> Meters {
        var v = Meters()
        v.electricity1 = try r.string("electricity1")
        v.electricity2 = try r.string("electricity2")
        v.gas = try r.string("gas")
        v.water = try r.string("water")
        v.hotWater = try r.string("hotWater")
        v.heatingOil = try r.string("heatingOil")
        return v
    }

    private static func keyCount(_ r: ObjectReader) throws -> KeyCount {
        KeyCount(try r.requiredEnum("kind"), label: try r.string("label"), count: Int(try r.int("count")))
    }

    private static func room(_ r: ObjectReader) throws -> Room {
        var v = Room(id: try r.requiredString("id"), kind: try r.requiredEnum("kind"))
        v.name = try r.string("name")
        v.items = try r.objects("items").map(roomItem)
        v.keysCount = Int(try r.int("keysCount"))
        v.inspected = try r.bool("inspected")
        v.freshPaintedWalls = try r.bool("freshPaintedWalls")
        v.freshPaintedWoodwork = try r.bool("freshPaintedWoodwork")
        v.newFloor = try r.bool("newFloor")
        v.fixtures = try r.enums("fixtures")
        return v
    }

    private static func roomItem(_ r: ObjectReader) throws -> RoomItem {
        RoomItem(try r.requiredEnum("key"), label: try r.string("label"), grade: try r.enumValue("grade", default: .notChecked), itemId: try r.string("itemId"))
    }

    private static func objectEntry(_ r: ObjectReader) throws -> ObjectEntry {
        ObjectEntry(
            id: try r.requiredString("id"),
            group: try r.requiredEnum("group"),
            groupLabel: try r.string("groupLabel"),
            catalogue: try r.string("catalogue"),
            label: try r.string("label"),
            roomId: try r.string("roomId"),
            note: try r.string("note"),
            inspected: try r.bool("inspected"),
            photos: try r.strings("photos"),
            photoEvidence: try r.objects("photoEvidence").map(photoEvidence)
        )
    }

    private static func contract(_ r: ObjectReader) throws -> Contract {
        var v = Contract()
        v.monthlyRentChf = try r.string("monthlyRentChf")
        v.serviceChargesChf = try r.string("serviceChargesChf")
        v.conclusionDate = try r.string("conclusionDate")
        v.startDate = try r.string("startDate")
        v.endDate = try r.string("endDate")
        v.noticeDate = try r.string("noticeDate")
        return v
    }

    private static func extras(_ r: ObjectReader) throws -> FlatExtras {
        var v = FlatExtras()
        v.appliances = try r.enums("appliances")
        v.furniture = try r.enums("furniture")
        v.customAppliances = try r.strings("customAppliances")
        v.customFurniture = try r.strings("customFurniture")
        return v
    }

    private static func defect(_ r: ObjectReader) throws -> Defect {
        Defect(
            id: try r.requiredString("id"),
            roomId: try r.string("roomId"),
            item: try r.optionalEnum("item"),
            text: try r.string("text"),
            photos: try r.strings("photos"),
            photoEvidence: try r.objects("photoEvidence").map(photoEvidence),
            chargedToTenant: try r.bool("chargedToTenant"),
            fixBy: try r.enumValue("fixBy", default: .open),
            fixDeadline: try r.string("fixDeadline"),
            costNote: try r.string("costNote"),
            reservation: try r.string("reservation"),
            tenantResponse: try r.enumValue("tenantResponse", default: .notStated),
            tenantComment: try r.string("tenantComment"),
            itemId: try r.string("itemId"),
            itemLabel: try r.string("itemLabel"),
            objectId: try r.string("objectId")
        )
    }

    private static func photoEvidence(_ r: ObjectReader) throws -> PhotoEvidence {
        PhotoEvidence(try r.requiredString("file"), sha256: try r.string("sha256"), capturedEpochMs: try r.int("capturedEpochMs"), source: try r.enumValue("source", default: .unknown))
    }

    private static func deliveryReceipt(_ r: ObjectReader) throws -> DeliveryReceipt {
        DeliveryReceipt(try r.requiredEnum("role"), epochMs: try r.int("epochMs"), method: try r.enumValue("method", default: .inPerson), note: try r.string("note"))
    }

    private static func signature(_ r: ObjectReader) throws -> Signature {
        Signature(
            try r.requiredEnum("role"),
            name: try r.string("name"),
            plane: try r.requiredEnum("plane"),
            file: try r.string("file"),
            refused: try r.bool("refused"),
            reservation: try r.string("reservation"),
            epochMs: try r.int("epochMs"),
            contentRevision: try r.int("contentRevision")
        )
    }
}

/// Recovers the key order of the record's two maps from the JSON text.
///
/// Only `checks` and `pendingRecordReservations` are maps, and both hold enum names as keys, so a
/// scan for `"checks":{` and `"pendingRecordReservations":{` followed by the quoted keys in
/// textual order is enough. Nested string values cannot contain an unescaped brace or quote,
/// which is what lets a scan this small be exact.
enum MapKeyOrder {
    static let names = ["checks", "pendingRecordReservations"]

    static func scan(_ data: Data) -> [String: [String]] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: [String]] = [:]
        for name in names {
            guard let range = text.range(of: "\"\(name)\":{") else { continue }
            var keys: [String] = []
            var index = range.upperBound
            var depth = 1
            var inString = false
            var escaped = false
            var current = ""
            var expectingKey = true
            while index < text.endIndex, depth > 0 {
                let ch = text[index]
                if inString {
                    if escaped {
                        current.append(ch)
                        escaped = false
                    } else if ch == "\\" {
                        escaped = true
                    } else if ch == "\"" {
                        inString = false
                        if expectingKey { keys.append(current) }
                    } else {
                        current.append(ch)
                    }
                } else {
                    switch ch {
                    case "\"":
                        inString = true
                        current = ""
                    case ":": expectingKey = false
                    case ",": expectingKey = true
                    case "{": depth += 1
                    case "}": depth -= 1
                    default: break
                    }
                }
                index = text.index(after: index)
            }
            result[name] = keys
        }
        return result
    }
}
