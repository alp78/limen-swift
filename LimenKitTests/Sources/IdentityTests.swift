import Foundation
import Testing
@testable import LimenKit

@Suite struct InternationalIdentityTests {
    @Test func validatesAndFormatsNumbersForTheirSelectedCountry() {
        #expect(InternationalPhone.isValid("021 729 71 10", regionCode: "CH"))
        #expect(InternationalPhone.isValid("076 264 31 24", regionCode: "CH"))
        #expect(InternationalPhone.isValid("020 7031 3000", regionCode: "GB"))
        #expect(InternationalPhone.isValid("202 456 1111", regionCode: "US"))
        #expect(InternationalPhone.format("076 264 31 24", regionCode: "CH") == "+41762643124")
        #expect(InternationalPhone.format("020 7031 3000", regionCode: "GB") == "+442070313000")
        #expect(InternationalPhone.format("+41 76 264 31 24", regionCode: "GB") == "+41762643124")
        #expect(InternationalPhone.isValid("+41 76 264 31 24", regionCode: "CH"))
        #expect(InternationalPhone.isValid("0041 76 264 31 24", regionCode: "CH"))
    }

    /// libphonenumber's rule, which Android gets from the library itself: a number typed with its own
    /// country code but no plus sign is the international form, not a national number too long to be one.
    @Test func acceptsTheOwnCountryCodeWithoutAPlusSign() {
        #expect(InternationalPhone.isValid("41 76 264 31 24", regionCode: "CH"))
        #expect(InternationalPhone.format("41 76 264 31 24", regionCode: "CH") == "+41762643124")
        #expect(InternationalPhone.format("076 264 31 24", regionCode: "CH") == "+41762643124")
    }

    /// The 38 regions that share a calling code keep no formats of their own in the metadata; the main
    /// country's apply. Canada's example was coming back as bare digits.
    @Test func aRegionSharingItsCallingCodeFormatsWithTheMainCountrysRules() {
        let example = InternationalPhone.example("CA")
        #expect(!example.isEmpty)
        #expect(example.contains { !$0.isNumber }, "unformatted: \(example)")
        #expect(InternationalPhone.example("US").contains { !$0.isNumber })
    }

    @Test func rejectsAValidNumberWhenItDoesNotMatchTheSelectedCountry() {
        #expect(!InternationalPhone.isValid("020 7031 3000", regionCode: "CH"))
        #expect(!InternationalPhone.isValid("020 7031 300", regionCode: "GB"))
        #expect(!InternationalPhone.isValid("+41 76 264 31 24", regionCode: "GB"))
        #expect(!InternationalPhone.isValid("", regionCode: "CH"))
    }

    @Test func theExampleIsWrittenTheLocalWay() {
        #expect(InternationalPhone.example("CH") == "021 234 56 78")
        #expect(InternationalPhone.example("GB") == "0121 234 5678")
        #expect(InternationalPhone.example("US") == "(201) 555-0123")
    }

    @Test func theCountryListCoversTheWorldAndSortsByEnglishName() {
        let countries = InternationalPhone.countries
        #expect(countries.count > 200)
        #expect(countries.contains { $0.regionCode == "CH" && $0.callingCode == 41 })
        let names = countries.map { CountryDirectory.name($0.regionCode, locale: Locale(identifier: "en")) }
        #expect(names == names.sorted())
        #expect(CountryDirectory.flag("CH") == "🇨🇭")
        #expect(CountryDirectory.flag("ZZZ") == "🌐")
        #expect(CountryDirectory.addressRegions.contains("CH"))
        #expect(CountryDirectory.addressRegions.contains("GB"))
        #expect(!CountryDirectory.addressRegions.contains("001"))
    }

    @Test func acceptsACompleteForeignAddress() {
        var identity = SessionIdentity()
        identity.firstName = "Ada"
        identity.lastName = "Lovelace"
        identity.street = "St James's Square"
        identity.flatNumber = "1"
        identity.postalCode = "SW1Y 4JU"
        identity.city = "London"
        identity.addressCountry = "GB"
        identity.usesSwissAddress = false
        identity.phone = "020 7031 3000"
        identity.phoneRegion = "GB"
        #expect(identity.hasRequiredFields())
        var swiss = identity
        swiss.usesSwissAddress = true
        #expect(!swiss.hasRequiredFields())
        swiss.addressCountry = "CH"
        swiss.postalCode = "1003"
        swiss.phone = "021 729 71 10"
        swiss.phoneRegion = "CH"
        #expect(swiss.hasRequiredFields())
    }

    @Test func quickDraftAcceptsShortOnePartNamesWithoutOptionalContacts() {
        for name in ["Li", "A", "李", "Madonna"] {
            var identity = SessionIdentity()
            identity.firstName = name
            #expect(identity.hasRequiredFields())
        }
        #expect(!SessionIdentity().hasRequiredFields())
        var invalidPhone = SessionIdentity()
        invalidPhone.firstName = "A"
        invalidPhone.phone = "invalid"
        #expect(!invalidPhone.hasRequiredFields())
        var foreign = SessionIdentity()
        foreign.lastName = "Ng"
        foreign.usesSwissAddress = false
        foreign.addressCountry = "GB"
        foreign.street = "A named cottage"
        #expect(foreign.hasRequiredFields())
    }

    @Test func parsesOfficialAddressSearchResults() {
        let matches = SwissAddressLookup.parse(
            "{\"results\":[{\"attrs\":{\"origin\":\"address\",\"label\":\"Avenue de la Gare 1 <b>1003 Lausanne</b>\",\"detail\":\"avenue de la gare 1 1003 lausanne ch vd\"}}]}"
        )
        #expect(matches == [SwissAddressCandidate(street: "Avenue de la Gare", flatNumber: "1", postalCode: "1003", city: "Lausanne", canton: .vd)])
    }
}

@Suite struct StringsTests {
    @Test func everyEnumSpeaksEveryLanguage() {
        for lang in Lang.allCases {
            let s = Str(lang)
            for v in RoomKind.allCases { #expect(!s.room(v).isBlank, "\(lang) room \(v)") }
            for v in ItemKey.allCases { #expect(!s.item(v).isBlank, "\(lang) item \(v)") }
            for v in Grade.allCases { #expect(!s.grade(v).isBlank, "\(lang) grade \(v)") }
            for v in Role.allCases { #expect(!s.role(v).isBlank, "\(lang) role \(v)") }
            for v in KeyKind.allCases { #expect(!s.keyKind(v).isBlank, "\(lang) key \(v)") }
            for v in DepositKind.allCases { #expect(!s.depositKind(v).isBlank, "\(lang) deposit \(v)") }
            for v in CautionProvider.allCases { #expect(!s.cautionProvider(v).isBlank, "\(lang) caution \(v)") }
            for v in Appliance.allCases { #expect(!s.appliance(v).isBlank, "\(lang) appliance \(v)") }
            for v in Furniture.allCases { #expect(!s.furniture(v).isBlank, "\(lang) furniture \(v)") }
            for v in ObjectGroup.allCases { #expect(!s.objectGroup(v).isBlank, "\(lang) group \(v)") }
            for v in DossierCard.allCases { #expect(!s.dossierCard(v).isBlank, "\(lang) card \(v)") }
            for v in SwissCanton.allCases { #expect(!s.canton(v).isBlank, "\(lang) canton \(v)") }
            for v in LegalProfile.allCases { #expect(!s.legalProfile(v).isBlank, "\(lang) legal profile \(v)") }
            for v in InitialRentFormRule.allCases { #expect(!s.initialRentFormRule(v).isBlank, "\(lang) rent form \(v)") }
            for v in LegalRequirement.allCases { #expect(!s.legalRequirement(v).isBlank, "\(lang) legal check \(v)") }
            for v in LegalCheckStatus.allCases { #expect(!s.legalCheckStatus(v).isBlank, "\(lang) legal status \(v)") }
            for v in KeyTransferStatus.allCases { #expect(!s.keyTransfer(v).isBlank, "\(lang) key transfer \(v)") }
            for v in UnilateralReason.allCases { #expect(!s.unilateralReason(v).isBlank, "\(lang) unilateral reason \(v)") }
            for v in DeliveryMethod.allCases { #expect(!s.deliveryMethod(v).isBlank, "\(lang) delivery \(v)") }
            for v in FinalizationIssue.allCases { #expect(!s.finalizationIssue(v).isBlank, "\(lang) issue \(v)") }
            for v in ExportIssue.allCases { #expect(!s.exportIssue(v).isBlank, "\(lang) export \(v)") }
            for v in LifeKey.allCases { #expect(!s.life(v).isBlank, "\(lang) life \(v)") }
            for v in TenantResponse.allCases { #expect(!s.tenantResponse(v).isBlank, "\(lang) response \(v)") }
            for v in UndoKind.allCases { #expect(!s.removedForUndo(v).isBlank, "\(lang) undo \(v)") }
        }
    }

    @Test func noEszettAnywhereInGerman() {
        let s = Str(.de)
        var sample = ""
        for v in RoomKind.allCases { sample += s.room(v) }
        for v in ItemKey.allCases { sample += s.item(v) }
        sample += s.emptyCase + s.infoCharged + s.infoOneSided + s.tipOneSided().lead
        #expect(!sample.contains("ß"))
    }

    @Test func theGeneratedStringsFollowTheAndroidOnes() {
        let s = Str(.fr)
        #expect(s.entry == "Entrée")
        #expect(s.countRooms(3) == "PIÈCES 3")
        #expect(s.canton(.zh) == "ZH · Zürich")
        #expect(s.archiveSaved("a.limen") == "Enregistré sous a.limen dans Fichiers, dans le dossier de l’app Limen")
        #expect(s.archiveRestored(ArchiveImportResult(imported: 1, skippedExisting: 2, rejected: 3)) == "Restaurés : 1 ; existants conservés : 2 ; invalides refusés : 3.")
        #expect(s.tipExitNotice().bullets == s.tipClocks().bullets)
        #expect(s.gradeShort(.notChecked) == "· ")
        #expect(Str(.en).privacyParagraphs.count == 5)
        #expect(Str(.en).cautionProvider(.other) == "Other insurer")
        #expect(Str(.rm).dateFormat == "DD/MM/AAAA")
    }

    @Test func theDefaultLanguageFollowsTheHandsetAndSwissGermanReadsGerman() {
        #expect(Lang.default(preferred: ["fr-CH"]) == .fr)
        #expect(Lang.default(preferred: ["gsw-CH"]) == .de)
        #expect(Lang.default(preferred: ["rm-CH"]) == .rm)
        #expect(Lang.default(preferred: ["ja"]) == .en)
        #expect(Lang.from("De") == .de)
        #expect(Lang.allCases.first == .fr)
    }

    @Test func nothingShipsWithAnEmDash() {
        for lang in Lang.allCases {
            let s = Str(lang)
            let sample = s.privacyParagraphs.joined() + s.releaseBank + s.releaseInsurance + s.infoOneSided + s.clockExitBody + s.clockEntryBody
            #expect(!sample.contains("\u{2014}"), "\(lang)")
        }
    }
}
