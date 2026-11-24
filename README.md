# JJS

Een opnieuw opgebouwde SwiftUI-app voor lokale gesprekken met GGUF-modellen. De appcode staat opgesplitst in gewone Swift-bronbestanden; `JJS.xcodeproj` is het enige Xcode-project. De llama.cpp-iOS-engine en het bestaande JJS-appicoon worden als lokale projectresources gebruikt.

## Gedrag

- Geen inhoudsfilter, extra systeemprompt, chatquota, maximumaantal berichten, antwoordtokenlimiet of generatie-time-out.
- Antwoorden lopen door tot het model-eindtoken, een expliciete stop, een enginefout of een iOS-/hardwareveiligheidspauze.
- Vragen kunnen tijdens een lopend antwoord worden verstuurd en worden duurzaam in volgorde verwerkt.
- Gesprekken worden in SQLite bewaard; import en export gebruiken JSON.
- GGUF-modellen kunnen uit Bestanden worden geïmporteerd. De engine kan alleen modellen uitvoeren die met de meegeleverde llama.cpp-versie compatibel zijn.
- Tekstbestanden, PDF, afbeeldingen en audio kunnen als invoer worden toegevoegd. Afbeeldingen worden lokaal met Vision-OCR verwerkt; audio wordt met lokale Apple-spraakherkenning verwerkt wanneer de gekozen taal en het toestel dit ondersteunen.
- Hoge iOS-thermische belasting pauzeert de inferentie automatisch. iOS blijft verantwoordelijk voor geheugenbeheer, thermische regeling en app-uitvoering.

Een taalmodel heeft altijd een eindige context en vereist geheugen en opslag. Als het contextvenster vol is, schuift de actieve modelcontext door; dit wist geen opgeslagen chatberichten. Een onbeperkte context, universele modelcompatibiliteit of onbeperkte fysieke capaciteit kan een iOS-app niet garanderen.

## Openen en bouwen

1. Open `JJS.xcodeproj` op een Mac met Xcode.
2. Selecteer de JJS-app en stel je Apple Development Team in bij Signing & Capabilities.
3. Kies `JJS` en bouw/archiveer voor een iPhone of iPad.
4. Importeer een GGUF-model vanuit Bestanden en stuur een vraag.

Het framework bevat alleen iOS-arm64. Simulator- en macOS-builds zijn daarom niet beschikbaar. Het minimumdeploymenttarget volgt de appconfiguratie; iOS verzorgt de apparaat- en achtergrondlevenscyclus.

## Codemagic

De workflow staat in de root `codemagic.yaml`. Configureer in Codemagic je Apple Developer-integratie, ontwikkelcertificaat en provisioningprofiel voor `nl.jjs.local`. De workflow voert eerst `scripts/test_core.sh` uit, past daarna signingprofielen toe en archiveert/exporteert de ondertekende IPA.

Lokaal:

```bash
bash scripts/test_core.sh
bash scripts/build_signed.sh DEVELOPMENT_TEAM=JOUW_TEAM
```

Voor IPA-export moet `JJS_EXPORT_OPTIONS` verwijzen naar een geldig `ExportOptions.plist`.
