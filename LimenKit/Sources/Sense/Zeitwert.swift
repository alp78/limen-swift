import Foundation

/// Indicative remaining replacement value. This arithmetic establishes neither liability nor
/// a debt, and must not be used as an automatic repair, cleaning or loss-of-value allocation.
public enum Zeitwert {
    public static func remainingFraction(lifespanYears: Double, ageYears: Double) -> Double {
        guard lifespanYears.isFinite, ageYears.isFinite, lifespanYears > 0, ageYears >= 0 else { return 0 }
        return min(max((lifespanYears - ageYears) / lifespanYears, 0), 1)
    }

    /// Nil means invalid input, so the caller cannot display it as a legitimate zero estimate.
    public static func replacementResidualValue(costChf: Double, lifespanYears: Double, ageYears: Double) -> Double? {
        guard costChf.isFinite, lifespanYears.isFinite, ageYears.isFinite,
              costChf >= 0, lifespanYears > 0, ageYears >= 0 else { return nil }
        return costChf * remainingFraction(lifespanYears: lifespanYears, ageYears: ageYears)
    }

    /// Source compatibility for historic callers. New UI uses replacementResidualValue and
    /// distinguishes invalid inputs from a valid fully amortized replacement value.
    public static func tenantShare(costChf: Double, lifespanYears: Double, ageYears: Double) -> Double {
        replacementResidualValue(costChf: costChf, lifespanYears: lifespanYears, ageYears: ageYears) ?? 0
    }
}

extension ReplacementEstimate {
    public var residualValue: Double? {
        guard let cost = NumberValidation.nonNegativeNumber(replacementChf),
              let age = NumberValidation.nonNegativeNumber(ageYears),
              let life = NumberValidation.nonNegativeNumber(lifeYears) else { return nil }
        return Zeitwert.replacementResidualValue(costChf: cost, lifespanYears: life, ageYears: age)
    }
    public var isValid: Bool { residualValue != nil && !RecordInputValidation.invalidOptionalDate(date) }
}

/// One row of the shipped table: what, how long it lives, and who says so.
public struct LifeItem: Hashable, Sendable {
    public let key: LifeKey
    public let years: Double
}

/// The publicly cited lifespans. Deliberately NOT the full 80-page table, which is a copyrighted
/// brochure sold by HEV and MV; these are the values their own public pages and the
/// tenant-association literature quote, and the face links to the brochure for the rest. Values
/// inherited from the Android reference; the operator records a source and may override them.
/// No professional or current-edition validation is implied.
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
