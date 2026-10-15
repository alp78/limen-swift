import LimenKit

/// iOS control wording; shared record and legal copy stays generated from Android.
/// These translations require the same external language review as the 1.2 additions.
extension Str {
    func uiWords(_ en: String, _ fr: String, _ de: String, _ it: String, _ rm: String) -> String {
        switch lang {
        case .en: en
        case .fr: fr
        case .de: de
        case .it: it
        case .rm: rm
        }
    }
    var invalidInput: String { uiWords("Check this value", "Vérifiez cette valeur", "Wert überprüfen", "Verificare il valore", "Controllar questa valur") }
    // The three inline `s.words` of the Android screens, word for word: the undo keys of the date
    // and time fields and the hub's one key under the missing data.
    var restoreLastValidDate: String { uiWords("Restore last valid date", "Rétablir la dernière date valide", "Letztes gültiges Datum übernehmen", "Ripristina l’ultima data valida", "Restabilir l’ultima data valaivla") }
    var restoreLastValidTime: String { uiWords("Restore last valid time", "Rétablir la dernière heure valide", "Letzte gültige Uhrzeit übernehmen", "Ripristina l’ultima ora valida", "Restabilir l’ultima ura valaivla") }
    var showAll: String { uiWords("Show all", "Tout afficher", "Alle anzeigen", "Mostra tutto", "Mussar tut") }
    var plainArchive: String { uiWords("Create unencrypted archive", "Créer une archive non chiffrée", "Unverschlüsseltes Archiv erstellen", "Crea archivio non cifrato", "Crear archiv betg criptà") }
    var plainArchiveWarning: String { uiWords("Anyone with this file can read every selected record and photograph. Continue only if you intend to share an unencrypted copy.", "Toute personne disposant du fichier peut lire les dossiers et photos sélectionnés. Continuez uniquement si vous souhaitez une copie non chiffrée.", "Wer diese Datei hat, kann alle ausgewählten Protokolle und Fotos lesen. Nur fortfahren, wenn eine unverschlüsselte Kopie beabsichtigt ist.", "Chiunque abbia questo file può leggere tutti i verbali e le foto selezionati. Continuare solo se si desidera una copia non cifrata.", "Mintgin cun questa datoteca po leger ils protocols e las fotografias tschernidas. Cuntinuar mo sch'ina copia betg criptada è intenziunada.") }
    var libraryProtection: String { uiWords("Lock the library and settings; keep the current handover available", "Verrouiller les dossiers et réglages ; garder la remise en cours accessible", "Bibliothek und Einstellungen sperren; aktuelle Übergabe bleibt zugänglich", "Blocca raccolta e impostazioni; la consegna in corso resta accessibile", "Serrar la biblioteca e las configuraziuns; la surdada actuala resta accessibla") }
    var documentTitle: String { uiWords("Document title", "Titre du document", "Dokumenttitel", "Titolo del documento", "Titel dal document") }
    var originalEvidence: String { uiWords("Original evidence", "Preuve originale", "Originalbeleg", "Prova originale", "Cumprova originala") }
    var cameraSettings: String { uiWords("Open Settings", "Ouvrir les réglages", "Einstellungen öffnen", "Apri Impostazioni", "Avrir las configuraziuns") }
    var cameraPermissionDenied: String { uiWords("Camera access is off. Allow it in Settings to take a photo, or choose a picture from Photos.", "L’accès à l’appareil photo est désactivé. Autorisez-le dans les réglages pour prendre une photo, ou choisissez une image dans Photos.", "Der Kamerazugriff ist deaktiviert. Erlauben Sie ihn in den Einstellungen oder wählen Sie ein Bild aus Fotos.", "L’accesso alla fotocamera è disattivato. Consentitelo nelle Impostazioni per scattare una foto oppure scegliete un’immagine da Foto.", "L’access a la camera è deactivà. Permettai el en las configuraziuns per far ina fotografia u tschernì in maletg da Fotos.") }
    var cameraRestricted: String { uiWords("Camera access is restricted on this device. Choose a picture from Photos or ask the device administrator to change the restriction.", "L’accès à l’appareil photo est restreint sur cet appareil. Choisissez une image dans Photos ou demandez à l’administrateur de modifier la restriction.", "Der Kamerazugriff ist auf diesem Gerät eingeschränkt. Wählen Sie ein Bild aus Fotos oder bitten Sie die Geräteverwaltung, die Einschränkung zu ändern.", "L’accesso alla fotocamera è limitato su questo dispositivo. Scegliete un’immagine da Foto o chiedete all’amministratore di modificare la restrizione.", "L’access a la camera è restrenschì sin quest apparat. Tschernì in maletg da Fotos u dumandai l’administratur da midar la restricziun.") }
    var cameraProcessingFailed: String { uiWords("The photo could not be saved. Try taking it again or choose a picture from Photos.", "La photo n’a pas pu être enregistrée. Réessayez ou choisissez une image dans Photos.", "Das Foto konnte nicht gespeichert werden. Nehmen Sie es erneut auf oder wählen Sie ein Bild aus Fotos.", "Non è stato possibile salvare la foto. Riprovate a scattarla oppure scegliete un’immagine da Foto.", "La fotografia na pudeva betg vegnir memorisada. Empruvai anc ina giada u tschernì in maletg da Fotos.") }
    var photoTooLarge: String { uiWords("This photo is too large. Choose a smaller image (up to 32 MiB and 80 megapixels).", "Cette photo est trop grande. Choisissez une image plus petite (32 Mio et 80 mégapixels au maximum).", "Dieses Foto ist zu gross. Wählen Sie ein kleineres Bild (höchstens 32 MiB und 80 Megapixel).", "Questa foto è troppo grande. Scegliete un’immagine più piccola (massimo 32 MiB e 80 megapixel).", "Questa fotografia è memia gronda. Tschernì in maletg pli pitschen (maximal 32 MiB ed 80 megapixels).") }
}

extension Party {
    var uiKey: String { participantKey() }
}
