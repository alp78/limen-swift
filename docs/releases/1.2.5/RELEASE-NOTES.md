# Release notes for Limen Traditionis 1.2.5 (7)

Prepared 21 October 2026, not uploaded. One note per language, written from the Android `docs/listing/release-notes.md` sections for versionCode 8 (1.2.3), versionCode 9 (1.2.4) and versionCode 10 (1.2.5), because the iPhone build goes from 1.2.2 (6) straight to 1.2.5 and carries all three changes. The 1.2.3 sentence promising lossless print quality is left out: 1.2.4 replaced it with JPEG at the printed size on both platforms. Each block is well under App Store Connect's 4,000-character limit for "What's New" and TestFlight's "What to Test". App Store Connect has no Romansh locale; the Romansh text is kept for the in-app and TestFlight notes should a place for it appear.

The Android notes were written by the owner's Android pass; nothing here was retranslated, only joined. Native Romansh review remains pending, as it does for the Android listing. The "about 8 MB" figure is Android's measurement over thirty camera originals; the iPhone's own figure over the same count is in [the handoff](HANDOFF.md).

## en-US

```
The photo annex of the PDF is now organised by room: each room opens its own section under its name, and every photograph is shown large, in a frame, with its room, the finding it documents, who is held responsible and when it was taken. Photographs are stored at the resolution their printed size needs, so a handover with 30 photographs makes a PDF of about 8 MB, exported more than twice as fast. Backups, photographs and documents no longer have a size limit, and backups of any size save and restore reliably. Backups are also about a fifth smaller: photographs are repacked losslessly as JPEG XL and restored byte for byte, so every evidence check still holds. A backup made with this version restores in Limen 1.2.5 or later; older backups restore as before.
```

## fr-FR

```
L’annexe photos du PDF est désormais organisée par pièce : chaque pièce ouvre sa propre section sous son nom, et chaque photo est présentée en grand, dans un cadre, avec sa pièce, le défaut qu’elle documente, la personne tenue pour responsable et le moment de la prise de vue. Les photos sont enregistrées à la résolution qu’exige leur taille d’impression, si bien qu’un état des lieux de 30 photos donne un PDF d’environ 8 Mo, exporté plus de deux fois plus vite. Les sauvegardes, les photos et les documents n’ont plus de limite de taille, et les sauvegardes de toute taille s’enregistrent et se restaurent de manière fiable. Les sauvegardes sont aussi environ un cinquième plus légères : les photos y sont recompressées sans perte au format JPEG XL et restaurées à l’octet près, si bien que chaque contrôle des preuves reste valable. Une sauvegarde faite avec cette version se restaure avec Limen 1.2.5 ou plus récent ; les anciennes sauvegardes se restaurent comme avant.
```

## de-DE

```
Der Fotoanhang des PDF ist jetzt nach Räumen geordnet: Jeder Raum beginnt einen eigenen Abschnitt unter seinem Namen, und jedes Foto erscheint gross, in einem Rahmen, mit seinem Raum, dem dokumentierten Mangel, der verantwortlichen Partei und dem Aufnahmezeitpunkt. Die Fotos werden in der Auflösung gespeichert, die ihre Druckgrösse braucht: Ein Protokoll mit 30 Fotos ergibt so ein PDF von etwa 8 MB und wird mehr als doppelt so schnell exportiert. Sicherungen, Fotos und Dokumente haben keine Grössenbeschränkung mehr, und Sicherungen jeder Grösse werden zuverlässig gespeichert und wiederhergestellt. Sicherungen sind zudem rund ein Fünftel kleiner: Die Fotos werden verlustfrei als JPEG XL neu verpackt und beim Wiederherstellen Byte für Byte zurückgewonnen, sodass jede Beweisprüfung gültig bleibt. Eine mit dieser Version erstellte Sicherung lässt sich mit Limen 1.2.5 oder neuer wiederherstellen; ältere Sicherungen wie bisher.
```

## it

```
L’allegato foto del PDF è ora organizzato per locale: ogni locale apre una propria sezione con il suo nome, e ogni foto è presentata in grande, in una cornice, con il suo locale, il difetto che documenta, chi ne è ritenuto responsabile e quando è stata scattata. Le foto sono salvate alla risoluzione richiesta dalla loro dimensione di stampa, così un verbale con 30 foto produce un PDF di circa 8 MB, esportato più di due volte più velocemente. Backup, foto e documenti non hanno più limiti di dimensione, e i backup di qualsiasi dimensione si salvano e si ripristinano in modo affidabile. I backup sono inoltre più leggeri di circa un quinto: le foto vengono ricompresse senza perdita in JPEG XL e ripristinate byte per byte, così ogni verifica delle prove resta valida. Un backup creato con questa versione si ripristina con Limen 1.2.5 o successivo; i backup precedenti si ripristinano come prima.
```

## rm

```
L’agiunta da fotos dal PDF è ussa ordinada tenor local: mintga local avra ina atgna secziun sut ses num, e mintga foto vegn mussada grond, en in rom, cun ses local, la mancanza ch’ella documentescha, tgi ch’è responsabel e cura ch’ella è vegnida fatga. Las fotos vegnan memorisadas en la resoluziun che lur grondezza da stampa dumonda, uschia dat in protocol cun 30 fotos in PDF da var 8 MB, exportà pli che dubel uschè svelt. Las copias da segirezza, las fotos e la documents n’han betg pli in limit da grondezza, e copias da segirezza da mintga grondezza vegnan memorisadas e restabilidas a moda fidabla. Las copias da segirezza èn er var in tschintgavel pli pitschnas: las fotos vegnan cumprimidas senza perdita en il format JPEG XL e restabilidas byte per byte, uschia resta valaivla mintga controlla da las cumprovas. Ina copia da segirezza fatga cun questa versiun sa lascha restabilir cun Limen 1.2.5 u pli nov; copias pli veglias vegnan restabilidas sco fin ussa.
```

## Where they go, when the owner decides to upload

The App Store Connect locales of the app are `en-US`, `fr-FR`, `de-DE` and `it` (not `it-IT`, see the vault's environment note). "What's New" is written per `appStoreVersionLocalizations` once a 1.2.5 version exists; "What to Test" per `betaBuildLocalizations` once build 7 is up. Build 6 (1.2.2) was uploaded on 15 October 2026 and submitted to Beta App Review on 16 October; build 7 is archived here and not uploaded, and the owner uploads.

## TestFlight "What to Test" for build 7

The build-6 note's opening and its two asks stay; the second paragraph names what changed, because the annex and the backup are the two things this build touches and the two things most worth a second phone.

### en-US

```
Second external build. Put it through a real handover if you can, a realistic one if not.

Start a record, pick your side and press Validate. Fill the dossier, add findings with photographs to several rooms, then open RECORD: review, have both parties sign, finalize and export.

What changed: the PDF's photo annex is organised by room, with each photograph large in a frame and its context beside it, and a record with thirty photographs makes a PDF of a few megabytes. Backups have no size limit any more and come out about a fifth smaller; please make one with a password and restore it on a second phone, Android 1.2.5 included if you have one, and check that every photograph is back.

Please report anything that reads wrong in your language, any cantonal rule that does not match your practice, and anything the app lets you do that a handover should not allow.
```

### fr-FR

```
Deuxième version externe. À passer sur une vraie remise si possible, sinon sur une remise réaliste.

Commencez un état des lieux, choisissez votre côté et touchez Valider. Remplissez le dossier, ajoutez des défauts avec photographies dans plusieurs pièces, puis ouvrez CONSTAT : relisez, faites signer les deux parties, finalisez et exportez.

Ce qui change : l’annexe photos du PDF est organisée par pièce, chaque photo en grand dans un cadre avec son contexte à côté, et un état des lieux de trente photos donne un PDF de quelques mégaoctets. Les sauvegardes n’ont plus de limite de taille et sont environ un cinquième plus légères ; faites-en une avec mot de passe et restaurez-la sur un second téléphone, Android 1.2.5 compris si vous en avez un, puis vérifiez que chaque photo est revenue.

Signalez-moi tout ce qui se lit mal dans votre langue, toute règle cantonale qui ne correspond pas à votre pratique, et tout ce que l’application permet alors qu’une remise ne le devrait pas.
```

### de-DE

```
Zweite externe Fassung. Wenn möglich bei einer echten Übergabe einsetzen, sonst bei einer realistischen.

Beginnen Sie ein Protokoll, wählen Sie Ihre Seite und tippen Sie auf Bestätigen. Füllen Sie das Dossier, fügen Sie in mehreren Räumen Mängel mit Fotografien hinzu und öffnen Sie dann PROTOKOLL: durchsehen, beide Parteien unterschreiben lassen, abschliessen und exportieren.

Was sich geändert hat: Der Fotoanhang des PDF ist nach Räumen geordnet, jedes Foto gross in einem Rahmen mit seinem Kontext daneben, und ein Protokoll mit dreissig Fotos ergibt ein PDF von wenigen Megabyte. Sicherungen haben keine Grössenbeschränkung mehr und sind rund ein Fünftel kleiner; bitte erstellen Sie eine mit Passwort, stellen Sie sie auf einem zweiten Telefon wieder her, Android 1.2.5 eingeschlossen, falls vorhanden, und prüfen Sie, ob jedes Foto zurück ist.

Melden Sie mir alles, was sich in Ihrer Sprache falsch liest, jede kantonale Regel, die Ihrer Praxis nicht entspricht, und alles, was die App zulässt, obwohl eine Übergabe es nicht sollte.
```

### it

```
Seconda versione esterna. Se possibile provatela su una consegna reale, altrimenti su una realistica.

Aprite un verbale, scegliete la vostra parte e toccate Conferma. Compilate il dossier, aggiungete difetti con fotografie in più locali, poi aprite VERBALE: rilettura, firma di entrambe le parti, finalizzazione ed esportazione.

Che cosa cambia: l’allegato foto del PDF è organizzato per locale, ogni foto in grande in una cornice con il suo contesto accanto, e un verbale con trenta foto produce un PDF di pochi megabyte. I backup non hanno più limiti di dimensione e sono più leggeri di circa un quinto; createne uno con password e ripristinatelo su un secondo telefono, Android 1.2.5 compreso se ne avete uno, poi verificate che ogni foto sia tornata.

Segnalatemi tutto ciò che si legge male nella vostra lingua, ogni regola cantonale che non corrisponde alla vostra pratica, e tutto ciò che l’applicazione permette mentre una consegna non dovrebbe permetterlo.
```
