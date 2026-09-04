import Foundation

/// The room canon, distilled from the MV mp form's 215 positions, the HEV two-pager and the
/// romand (Lafidu) form. A template is a starting point: rooms and items can be added, renamed or
/// removed on the way through the flat, but the walk begins with what the paper forms have asked
/// about for decades, so nothing routine is forgotten at the door.
public enum RoomKind: String, CaseIterable, Hashable, Sendable {
    case kitchen = "Kitchen"
    case bathroom = "Bathroom"
    case sepWC = "SepWC"
    case hall = "Hall"
    case livingRoom = "LivingRoom"
    case bedroom = "Bedroom"
    case room = "Room"
    case balcony = "Balcony"
    case cellar = "Cellar"
    case attic = "Attic"
    case garage = "Garage"
    case laundryRoom = "LaundryRoom"
    case hobbyRoom = "HobbyRoom"
    case mailbox = "Mailbox"
    case custom = "Custom"
}

/// Every item a template row can carry. The canonical rows render per language from `Str`;
/// `custom` rows carry their own label. Kept flat on purpose: one enum, so the store's JSON
/// stays a list of names.
public enum ItemKey: String, CaseIterable, Hashable, Sendable {
    // The shell of every room.
    case floor = "Floor", walls = "Walls", ceiling = "Ceiling", skirtings = "Skirtings", door = "Door", doorLock = "DoorLock"
    case windows = "Windows", windowSills = "WindowSills", blinds = "Blinds", blindStraps = "BlindStraps", curtainRails = "CurtainRails"
    case radiator = "Radiator", socketsSwitches = "SocketsSwitches", lighting = "Lighting"
    // Kitchen.
    case stove = "Stove", oven = "Oven", ovenAccessories = "OvenAccessories", extractorHood = "ExtractorHood", fridge = "Fridge"
    case freezer = "Freezer", dishwasher = "Dishwasher", sink = "Sink", tap = "Tap", worktop = "Worktop", cupboards = "Cupboards", tiles = "Tiles"
    // Bath and WC.
    case bathtub = "Bathtub", shower = "Shower", showerHose = "ShowerHose", wc = "WC", cistern = "Cistern", wcSeat = "WCSeat"
    case washbasin = "Washbasin", mirrorCabinet = "MirrorCabinet", towelRail = "TowelRail", soapHolder = "SoapHolder", ventilation = "Ventilation"
    // Elsewhere in the building.
    case cellarRack = "CellarRack", washingMachine = "WashingMachine", dryer = "Dryer", mailboxLock = "MailboxLock"
    case custom = "Custom"
}

public enum Templates {
    /// The rooms a fresh protocol proposes, in walking order.
    public static let defaultRooms: [RoomKind] = [.hall, .kitchen, .livingRoom, .bedroom, .bathroom, .balcony, .cellar, .mailbox]

    private static let shell: [ItemKey] = [
        .floor, .walls, .ceiling, .skirtings, .door, .doorLock, .windows, .windowSills,
        .blinds, .blindStraps, .curtainRails, .radiator, .socketsSwitches, .lighting,
    ]

    /// The item rows a room of this kind starts with.
    public static func itemsFor(_ kind: RoomKind) -> [ItemKey] {
        switch kind {
        case .kitchen:
            return shell + [.stove, .oven, .ovenAccessories, .extractorHood, .fridge, .freezer, .dishwasher, .sink, .tap, .worktop, .cupboards, .tiles]
        case .bathroom:
            return shell + [.tiles, .bathtub, .shower, .showerHose, .wc, .cistern, .wcSeat, .washbasin, .mirrorCabinet, .towelRail, .soapHolder, .tap, .ventilation]
        case .sepWC:
            return [.floor, .walls, .ceiling, .door, .tiles, .wc, .cistern, .wcSeat, .washbasin, .tap, .ventilation, .socketsSwitches, .lighting]
        case .balcony:
            return [.floor, .walls, .door, .windows, .lighting]
        case .cellar:
            return [.floor, .walls, .door, .cellarRack, .lighting]
        case .attic, .garage:
            return [.floor, .walls, .door, .lighting]
        case .laundryRoom:
            return [.floor, .walls, .door, .washingMachine, .dryer, .sink, .tap, .lighting]
        case .mailbox:
            return [.mailboxLock]
        // Hall, living room, bedrooms, hobby room, custom: the shell carries them.
        case .hall, .livingRoom, .bedroom, .room, .hobbyRoom, .custom:
            return shell
        }
    }
}
