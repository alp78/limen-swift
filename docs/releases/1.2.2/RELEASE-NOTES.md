# Release notes for Limen Traditionis 1.2.2 (6)

Prepared 15 October 2026, not uploaded. One note per language, written from the Android `docs/listing/release-notes.md` sections for versionCode 6 (1.2.1) and versionCode 7 (1.2.2), because the iPhone build goes from 1.2.0 (5), never uploaded, straight to 1.2.2 and carries both changes. Each block is well under App Store Connect's 4,000-character limit for "What's New" and TestFlight's "What to Test". App Store Connect has no Romansh locale; the Romansh text is kept for the in-app and TestFlight notes should a place for it appear, as the listing work of October already recorded.

The Android notes were written by the owner's Android pass; nothing here was retranslated, only joined. Native Romansh review remains pending, as it does for the Android listing.

## en-US

```
Simpler forms. Buttons are an icon and a word at the bottom of each form, instruction text is gone, and the address lookup runs by itself whenever the phone is online, with free typing when it is offline or nothing matches. The data-controller block and the participant notice no longer appear on the handover form. The handover overview, dossier, inspection and signature screens lose their explanatory sentences, and the record's review, signatures and export open from a door beside the other two instead of a key at the foot of the page.
```

## fr-FR

```
Formulaires simplifiés. Les boutons sont une icône et un mot au bas de chaque formulaire, les textes d’instruction ont disparu, et la recherche d’adresse se lance d’elle-même dès que le téléphone est en ligne, la saisie libre restant possible hors ligne ou sans correspondance. Le bloc du responsable du traitement et l’information aux participants ne figurent plus sur le formulaire d’état des lieux. Les écrans de vue d’ensemble, de dossier, d’inspection et de signature perdent leurs phrases d’explication, et la relecture, les signatures et l’export s’ouvrent depuis une porte à côté des deux autres, au lieu d’un bouton en bas de page.
```

## de-DE

```
Einfachere Formulare. Schaltflächen sind ein Symbol und ein Wort am Ende jedes Formulars, Anleitungstexte sind weg, und die Adresssuche läuft von selbst, sobald das Telefon online ist; offline oder ohne Treffer bleibt die freie Eingabe. Der Block zur verantwortlichen Stelle und der Hinweis für Beteiligte erscheinen nicht mehr im Übergabeformular. Übersicht, Dossier, Begehung und Unterschriften verlieren ihre Erklärungssätze; Durchsicht, Unterschriften und Export öffnen sich über eine Tür neben den beiden anderen statt über eine Taste am Seitenende.
```

## it

```
Moduli più semplici. I pulsanti sono un’icona e una parola in fondo a ogni modulo, i testi di istruzione sono spariti e la ricerca dell’indirizzo parte da sola appena il telefono è online, con inserimento libero se è offline o nulla corrisponde. Il blocco del titolare del trattamento e l’informativa per i partecipanti non compaiono più nel modulo di consegna. Panoramica, dossier, sopralluogo e firme perdono le frasi esplicative; rilettura, firme ed esportazione si aprono da una porta accanto alle altre due, non più da un pulsante in fondo alla pagina.
```

## rm

```
Formulars pli simpels. Ils buttuns èn in simbol ed in pled a la fin da mintga formular, ils texts d’instrucziun èn davent, e la tschertga d’adressas cumenza da sasezza cur che il telefon è online; offline u senza correspundenza resta l’endataziun libra. Il bloc dal post responsabel e l’infurmaziun per participants na cumparan betg pli en il formular da surdada. La survista, il dossier, l’inspecziun e las suttascripziuns perdan lur frasas explicativas; la relectura, las suttascripziuns e l’export s’avran tras ina porta dasper las autras duas, betg pli tras in buttun al pe da la pagina.
```

## Where they go, when the owner decides to upload

The App Store Connect locales of the app are `en-US`, `fr-FR`, `de-DE` and `it` (not `it-IT`, see the vault's environment note). "What's New" is written per `appStoreVersionLocalizations` once a 1.2.2 version exists; "What to Test" per `betaBuildLocalizations` once the build is up. The owner uploaded build 6 on 15 October 2026 (delivery `217c7844-67da-40c7-ac78-68e7bea2f70d`) and Apple processed it as valid; no 1.2.2 App Store version exists yet.

## TestFlight "What to Test" for build 6

Build 4's notes, which never reached an external tester, with the second paragraph renamed for the 1.2.2 screens. Build 6 is the first build the Agencies group will see, so it still opens with "First external build".

### en-US

```
First external build. Put it through a real handover if you can, a realistic one if not.

Start a record, pick your side and press Validate. Fill the dossier (address, parties, contract, deposit, meters, keys), add a defect with photographs to a room, then open RECORD: review, have both parties sign, finalize and export.

The two things I most want tested: the A4 PDF with its photograph annex, and the password-protected backup, including restoring it on a second phone.

Please report anything that reads wrong in your language, any cantonal rule that does not match your practice, and anything the app lets you do that a handover should not allow.
```

### fr-FR

```
Première version externe. À passer sur une vraie remise si possible, sinon sur une remise réaliste.

Commencez un état des lieux, choisissez votre côté et touchez Valider. Remplissez le dossier (adresse, parties, bail, dépôt, compteurs, clés), ajoutez un défaut avec photographies dans une pièce, puis ouvrez CONSTAT : relisez, faites signer les deux parties, finalisez et exportez.

Les deux points que je souhaite le plus voir testés : le PDF A4 avec son annexe photographique, et la sauvegarde protégée par mot de passe, y compris sa restauration sur un second téléphone.

Signalez-moi tout ce qui se lit mal dans votre langue, toute règle cantonale qui ne correspond pas à votre pratique, et tout ce que l’application permet alors qu’une remise ne le devrait pas.
```

### de-DE

```
Erste externe Fassung. Wenn möglich bei einer echten Übergabe einsetzen, sonst bei einer realistischen.

Beginnen Sie ein Protokoll, wählen Sie Ihre Seite und tippen Sie auf Bestätigen. Füllen Sie das Dossier (Adresse, Parteien, Vertrag, Kaution, Zähler, Schlüssel), fügen Sie in einem Raum einen Mangel mit Fotografien hinzu und öffnen Sie dann PROTOKOLL: durchsehen, beide Parteien unterschreiben lassen, abschliessen und exportieren.

Die zwei Punkte, die mich am meisten interessieren: das A4-PDF mit seinem Fotoanhang, und die passwortgeschützte Sicherung, samt Wiederherstellung auf einem zweiten Telefon.

Melden Sie mir alles, was sich in Ihrer Sprache falsch liest, jede kantonale Regel, die Ihrer Praxis nicht entspricht, und alles, was die App zulässt, obwohl eine Übergabe es nicht sollte.
```

### it

```
Prima versione esterna. Se possibile provatela su una consegna reale, altrimenti su una realistica.

Aprite un verbale, scegliete la vostra parte e toccate Conferma. Compilate il dossier (indirizzo, parti, contratto, deposito, contatori, chiavi), aggiungete un difetto con fotografie in un locale, poi aprite VERBALE: rilettura, firma di entrambe le parti, finalizzazione ed esportazione.

I due punti che mi interessano di più: il PDF A4 con il suo allegato fotografico, e il backup protetto da password, compreso il ripristino su un secondo telefono.

Segnalatemi tutto ciò che si legge male nella vostra lingua, ogni regola cantonale che non corrisponde alla vostra pratica, e tutto ciò che l’applicazione permette mentre una consegna non dovrebbe permetterlo.
```
