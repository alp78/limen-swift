import Foundation

/// The arithmetic of the paritaetische Lebensdauertabelle (MV + HEV), the joint lifespan table
/// Swiss conciliation boards compute with. Two iron rules, both encoded here and printed wherever
/// the numbers appear:
///
/// 1. The tenant owes only the remaining value: cost x (lifespan - age) / lifespan. Past the full
///    lifespan the share is zero, however real the damage.
/// 2. Age counts from the LAST RENOVATION of the surface or device, not from the start of the
///    tenancy; a flat taken over unrenovated carries its full age.
///
/// The table itself carries no binding force (its own disclaimer), so the values shipped in
/// `Lifespans` are the publicly cited ones with sources, and every lifespan can be overridden by hand.
public enum Zeitwert {
    /// The unamortized fraction of a thing's value, in 0..1.
    public static func remainingFraction(lifespanYears: Double, ageYears: Double) -> Double {
        if lifespanYears <= 0 { return 0 }
        if ageYears < 0 { return 1 }
        return min(max((lifespanYears - ageYears) / lifespanYears, 0), 1)
    }

    /// The tenant's share of a repair, by remaining value. Zero past the lifespan.
    public static func tenantShare(costChf: Double, lifespanYears: Double, ageYears: Double) -> Double {
        if costChf <= 0 { return 0 }
        return costChf * remainingFraction(lifespanYears: lifespanYears, ageYears: ageYears)
    }
}

/// One row of the shipped table: what, how long it lives, and who says so.
public struct LifeItem: Hashable, Sendable {
    public let key: LifeKey
    public let years: Double
}

/// The publicly cited lifespans. Deliberately NOT the full 80-page table, which is a copyrighted
/// brochure sold by HEV and MV; these are the values their own public pages and the
/// tenant-association literature quote, and the face links to the brochure for the rest. Values
/// as of the 2021 public excerpts; the 2024 edition is checked at release time.
public enum LifeKey: String, CaseIterable, Hashable, Sendable {
    case dispersionPaint = "DispersionPaint", acrylicPaint = "AcrylicPaint", woodchipWallpaper = "WoodchipWallpaper"
    case paintableWallpaper = "PaintableWallpaper", carpet = "Carpet", needleFelt = "NeedleFelt", laminateMid = "LaminateMid"
    case solidParquet = "SolidParquet", multilayerParquet = "MultilayerParquet", parquetSeal = "ParquetSeal", pvc = "Pvc"
    case linoleum = "Linoleum", ceramicTiles = "CeramicTiles", fridge = "Fridge", freezer = "Freezer", stove = "Stove"
    case dishwasher = "Dishwasher", microwave = "Microwave", steamer = "Steamer", extractorHood = "ExtractorHood", taps = "Taps"
    case bathtubAcrylic = "BathtubAcrylic", bathtubSteel = "BathtubSteel", ceramicSink = "CeramicSink", mirrorCabinet = "MirrorCabinet"
    case washingMachine = "WashingMachine", doorSolid = "DoorSolid", lockCylinder = "LockCylinder", rollerShutterWood = "RollerShutterWood"
    case rollerShutterMetal = "RollerShutterMetal", blindStraps = "BlindStraps", sealantJoints = "SealantJoints", radiator = "Radiator"
}

public enum Lifespans {
    public static let table: [LifeItem] = [
        LifeItem(key: .dispersionPaint, years: 8),
        LifeItem(key: .acrylicPaint, years: 15),
        LifeItem(key: .woodchipWallpaper, years: 10),
        LifeItem(key: .paintableWallpaper, years: 24),
        LifeItem(key: .carpet, years: 10),
        LifeItem(key: .needleFelt, years: 8),
        LifeItem(key: .laminateMid, years: 15),
        LifeItem(key: .solidParquet, years: 40),
        LifeItem(key: .multilayerParquet, years: 30),
        LifeItem(key: .parquetSeal, years: 10),
        LifeItem(key: .pvc, years: 10),
        LifeItem(key: .linoleum, years: 20),
        LifeItem(key: .ceramicTiles, years: 30),
        LifeItem(key: .fridge, years: 10),
        LifeItem(key: .freezer, years: 15),
        LifeItem(key: .stove, years: 15),
        LifeItem(key: .dishwasher, years: 15),
        LifeItem(key: .microwave, years: 15),
        LifeItem(key: .steamer, years: 10),
        LifeItem(key: .extractorHood, years: 10),
        LifeItem(key: .taps, years: 20),
        LifeItem(key: .bathtubAcrylic, years: 25),
        LifeItem(key: .bathtubSteel, years: 35),
        LifeItem(key: .ceramicSink, years: 35),
        LifeItem(key: .mirrorCabinet, years: 10),
        LifeItem(key: .washingMachine, years: 15),
        LifeItem(key: .doorSolid, years: 30),
        LifeItem(key: .lockCylinder, years: 20),
        LifeItem(key: .rollerShutterWood, years: 25),
        LifeItem(key: .rollerShutterMetal, years: 30),
        LifeItem(key: .blindStraps, years: 8),
        LifeItem(key: .sealantJoints, years: 9),
        LifeItem(key: .radiator, years: 50),
    ]

    public static func yearsOf(_ key: LifeKey) -> Double {
        table.first { $0.key == key }?.years ?? 0
    }
}
