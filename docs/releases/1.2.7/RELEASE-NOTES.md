# Release notes for Limen Traditionis 1.2.7 (9)

Prepared 23 October 2026; build 9 was uploaded on 24 October 2026 from commit `934219f` (delivery `a7ac2d18-299d-4a9d-ac1c-af6fe0a16542`). One note per language, in the iPhone's own words for what Android's `docs/listing/release-notes.md` says under versionCode 12; they name no other product and no tester. The rotation sentence of the Android note has no counterpart here, since SwiftUI keeps the pad's ink through a rotation, so its place is taken by the signature that waits for a photograph still being stored. Each block is well under App Store Connect's 4,000-character limit for "What's New" and TestFlight's "What to Test". App Store Connect has no Romansh locale; the Romansh text is kept for the in-app and TestFlight notes should a place for it appear.

Native Romansh review remains pending, as it does for the Android listing.

## en-US

```
Safer backups and clearer checks. A backup that cannot be made names the record at fault and says why, a restore needs less free space, and a wrong password is refused sooner. Finalizing names every value it rejects, and the dossier's ticks follow the same checks. Removed meter readings, documents, parties and kinds of key can be undone. The printed record shows only what applies. A photograph chosen from Photos is kept even if you leave the finding before it arrives, and a signature waits for a photograph still being stored.
```

## fr-FR

```
Sauvegardes plus sûres et contrôles plus clairs. Une sauvegarde impossible nomme le constat en cause et dit pourquoi, une restauration demande moins d’espace libre et un mauvais mot de passe est refusé plus tôt. La finalisation nomme chaque valeur refusée, et les coches du dossier suivent les mêmes contrôles. Les suppressions de relevés de compteurs, documents, parties et types de clés peuvent être annulées. Le constat imprimé n’indique que ce qui s’applique. Une photo choisie dans Photos est conservée même si vous quittez le défaut avant son arrivée, et une signature attend qu’une photo en cours d’enregistrement soit stockée.
```

## de-DE

```
Zuverlässigere Sicherungen, klarere Prüfungen. Eine unmögliche Sicherung nennt das betroffene Protokoll und den Grund, eine Wiederherstellung braucht weniger Speicherplatz, und ein falsches Passwort wird früher abgelehnt. Der Abschluss nennt jeden abgewiesenen Wert, und die Haken im Dossier folgen denselben Prüfungen. Entfernte Zählerstände, Beilagen, Parteien und Schlüsselarten lassen sich rückgängig machen. Das gedruckte Protokoll zeigt nur, was zutrifft. Ein in Fotos gewähltes Bild bleibt erhalten, auch wenn Sie den Mangel verlassen, bevor es angekommen ist, und eine Unterschrift wartet, bis ein Foto fertig gespeichert ist.
```

## it

```
Backup più affidabili e controlli più chiari. Un backup impossibile indica il verbale in causa e il motivo, un ripristino richiede meno spazio libero e una password errata viene rifiutata prima. La finalizzazione indica ogni valore rifiutato, e le spunte del dossier seguono gli stessi controlli. Letture dei contatori, documenti, parti e tipi di chiave rimossi si possono annullare. Il verbale stampato mostra solo ciò che si applica. Una foto scelta da Foto viene conservata anche se lasciate il difetto prima che arrivi, e una firma attende che una foto in corso di salvataggio sia stata memorizzata.
```

## rm

```
Copias da segirezza pli sigiras e controllas pli cleras. Ina copia da segirezza impussibla numna il protocol en dumonda e di pertge, ina restauraziun dovra main spazi liber ed in pled-clav fauss vegn refusà pli baud. La finalisaziun numna mintga valur refusada, ed ils segns dal dossier suondan las medemas controllas. Lecturas dal contatur, documents, partidas e tips da clav stizzads sa laschan revocar. Il protocol stampà mussa be quai che vala. Ina foto tschernida en Fotos vegn tegnida era sche vus bandunais la mancanza avant ch’ella arriva, ed ina suttascripziun spetga fin ch’ina foto en memorisaziun è memorisada.
```

## Where they go

The App Store Connect locales of the app are `en-US`, `fr-FR`, `de-DE` and `it` (not `it-IT`, see the vault's environment note). "What to Test" goes to the `betaBuildLocalizations` of build 9 once it is up. The store version, renamed to 1.2.6 on 21 October with build 8 attached, is the app's first, and Apple refuses "What's New" on a first version; the "What's New" texts above wait for the first update after the app is on sale, where the 1.2.6 and 1.2.7 notes would be folded into one. Build 9 is built in Release here and not uploaded; the owner uploads.

## TestFlight "What to Test" for build 9

The opening and the two asks of the build-8 note stay; the middle paragraph names what changed since build 8, because the backup, the finalization gate and the removals are the three things this build touches and the three things most worth a second phone.

### en-US

```
Third external build. Put it through a real handover if you can, a realistic one if not.

Start a record, pick your side and press Validate. Fill the dossier, add findings with photographs to several rooms, then open RECORD: review, have both parties sign, finalize and export.

What changed: a backup that cannot be made now names the record and the reason, a restore needs less free space, and a wrong password is refused at once; please make a backup with a password and restore it on a second phone. Finalizing names every value it rejects and the dossier's ticks follow the same checks; please type a rent as words, a half date or a time like 25:99 somewhere, and check that the record names exactly that. Removing a meter reading, a document, a party or a kind of key now offers it back for a few seconds, as a finding did; please remove one and undo it. The printed record shows only what still applies, so please read the review step and the document once more and tell us whether they read as the record you made.

Please report anything that reads wrong in your language, any cantonal rule that does not match your practice, and anything the app lets you do that a handover should not allow.
```

### fr-FR

```
Troisième version externe. À passer sur une vraie remise si possible, sinon sur une remise réaliste.

Démarrez un constat, choisissez votre côté et appuyez sur Valider. Remplissez le dossier, ajoutez des défauts avec photos dans plusieurs pièces, puis ouvrez CONSTAT : relisez, faites signer les deux parties, finalisez et exportez.

Ce qui a changé : une sauvegarde impossible nomme désormais le constat et la raison, une restauration demande moins d’espace libre et un mauvais mot de passe est refusé tout de suite ; faites une sauvegarde avec mot de passe et restaurez-la sur un second téléphone. La finalisation nomme chaque valeur refusée et les coches du dossier suivent les mêmes contrôles ; saisissez quelque part un loyer en lettres, une demi-date ou une heure comme 25:99, et vérifiez que le constat nomme exactement cela. Supprimer un relevé de compteur, un document, une partie ou un type de clé le propose de nouveau quelques secondes, comme pour un défaut ; supprimez-en un et annulez. Le constat imprimé n’indique que ce qui s’applique encore : relisez l’étape de relecture et le document une fois de plus, et dites-nous s’ils se lisent comme le constat que vous avez établi.

Signalez tout ce qui se lit mal dans votre langue, toute règle cantonale qui ne correspond pas à votre pratique, et tout ce que l’application vous laisse faire qu’une remise ne devrait pas permettre.
```

### de-DE

```
Dritte externe Version. Wenn möglich bei einer echten Übergabe testen, sonst bei einer realistischen.

Protokoll starten, die eigene Seite wählen und Bestätigen drücken. Dossier ausfüllen, in mehreren Räumen Mängel mit Fotos erfassen, dann PROTOKOLL öffnen: prüfen, beide Parteien unterschreiben lassen, abschliessen und exportieren.

Was sich geändert hat: Eine unmögliche Sicherung nennt jetzt das Protokoll und den Grund, eine Wiederherstellung braucht weniger Speicherplatz, und ein falsches Passwort wird sofort abgelehnt; bitte eine Sicherung mit Passwort erstellen und auf einem zweiten Telefon wiederherstellen. Der Abschluss nennt jeden abgewiesenen Wert, und die Haken im Dossier folgen denselben Prüfungen; bitte irgendwo eine Miete in Worten, ein halbes Datum oder eine Uhrzeit wie 25:99 eintippen und prüfen, ob das Protokoll genau das nennt. Das Entfernen eines Zählerstands, einer Beilage, einer Partei oder einer Schlüsselart bietet es nun einige Sekunden lang zurück an, wie bei einem Mangel; bitte eines entfernen und rückgängig machen. Das gedruckte Protokoll zeigt nur, was noch zutrifft: bitte die Durchsicht und das Dokument noch einmal lesen und uns sagen, ob sie sich wie das erstellte Protokoll lesen.

Bitte alles melden, was in Ihrer Sprache falsch klingt, jede kantonale Regel, die nicht Ihrer Praxis entspricht, und alles, was die App zulässt, obwohl eine Übergabe es nicht erlauben sollte.
```

### it

```
Terza versione esterna. Da provare su una consegna vera se possibile, altrimenti su una realistica.

Avviate un verbale, scegliete la vostra parte e premete Conferma. Compilate il dossier, aggiungete difetti con foto in più locali, poi aprite VERBALE: rileggete, fate firmare entrambe le parti, finalizzate ed esportate.

Cosa è cambiato: un backup impossibile ora indica il verbale e il motivo, un ripristino richiede meno spazio libero e una password errata viene rifiutata subito; create un backup con password e ripristinatelo su un secondo telefono. La finalizzazione indica ogni valore rifiutato e le spunte del dossier seguono gli stessi controlli; digitate da qualche parte un affitto in lettere, una data a metà o un’ora come 25:99 e verificate che il verbale indichi esattamente quello. Rimuovere una lettura del contatore, un documento, una parte o un tipo di chiave ora lo ripropone per qualche secondo, come per un difetto; rimuovetene uno e annullate. Il verbale stampato mostra solo ciò che si applica ancora: rileggete la fase di rilettura e il documento un’altra volta e diteci se si leggono come il verbale che avete redatto.

Segnalate tutto ciò che suona sbagliato nella vostra lingua, ogni regola cantonale che non corrisponde alla vostra pratica e tutto ciò che l’app vi lascia fare ma che una consegna non dovrebbe permettere.
```

### rm

```
Terza versiun externa. Da testar tar ina surdada vaira sche pussaivel, uschiglio tar ina realistica.

Entschaivai in protocol, tscherni vossa vart e smatgai Confermar. Emplenì il dossier, agiunschì mancanzas cun fotos en pliras stanzas, lura avri PROTOCOL: controllai, laschai suttascriver omaduas partidas, finalisai ed exportai.

Quai ch’è sa midà: ina copia da segirezza impussibla numna ussa il protocol ed il motiv, ina restauraziun dovra main spazi liber ed in pled-clav fauss vegn refusà immediat; faschai ina copia da segirezza cun pled-clav e restabili ella sin in segund telefon. La finalisaziun numna mintga valur refusada ed ils segns dal dossier suondan las medemas controllas; scrivì insanua ina tschains en pleds, ina mesa data u in’ura sco 25:99 e controllai ch’il protocol numna exact quai. Allontanar ina lectura dal contatur, in document, ina partida u in tip da clav porscha quai ussa anc ina giada per in pèr secundas, sco tar ina mancanza; allontanai in e revocai. Il protocol stampà mussa be quai che vala anc: legì la fasa da controlla ed il document anc ina giada e di a nus sch’els sa legian sco il protocol che vus avais fatg.

Annunziai tut quai che tuna fauss en vossa lingua, mintga regla chantunala che na correspunda betg a vossa pratica, e tut quai che l’app lascha far che ina surdada na duess betg permetter.
```
