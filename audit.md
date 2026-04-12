# Code Audit

Stand: 2026-04-04

## Scope
- Geprueft: Phase-5-Aenderungen in `SyncScheduler`, `SyncEngine`, Cache-Invalidierung (`SettingsView`, `MetadataCache`, `SharedCourseParticipationCache`) sowie Testabdeckung.
- Bezug: Muss-Anforderungen aus `INSTRUCTION.md` (insbesondere lokales Semester/Kurs-Caching, Fehlerrobustheit, Resume, Tests).

## Validierung
- `xcrun swiftc -frontend -parse $(rg --files StudipSync StudipSyncTests StudipSyncUITests -g '*.swift')`: erfolgreich.
- `python3 Scripts/validate_api_coverage.py`: `Missing routes: 0`, aber `Undocumented implemented routes: 12`.
- `xcodebuild ... test`: in aktueller Umgebung nicht ausfuehrbar (nur CommandLineTools, kein volles Xcode).

## Findings (priorisiert)

### 1) High: Persistenter Kurs-Metadaten-Cache fehlt weiterhin
- Evidenz:
  - [MetadataCache.swift:5](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Services/MetadataCache.swift:5)
  - [MetadataCache.swift:39](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Services/MetadataCache.swift:39)
  - [ContentView+StateAndPrefetch.swift:279](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/ContentView+StateAndPrefetch.swift:279)
  - [ContentView+StateAndPrefetch.swift:308](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/ContentView+StateAndPrefetch.swift:308)
- Problem:
  - Kurslisten werden nur im UI-State (`coursesBySemesterID`) gehalten und nicht auf Disk persistiert.
  - `MetadataCache` speichert aktuell ausschließlich `semesters`.
- Risiko:
  - Bei App-Neustart/Offline stehen Kurse nicht lokal zur Verfuegung, obwohl Muss-Anforderung Semester- **und** Kurs-Metadaten-Caching fordert.
- Empfehlung:
  - `MetadataCache.Snapshot` um persistente Kursmetadaten erweitern (z. B. `coursesBySemesterID`) und `loadCoursesForSelectedSemester()` auf stale-while-revalidate mit Disk-Fallback umstellen.

### 2) Medium: Fehlerklassifikation verliert Ursache bei Teilausfaellen pro Semester
- Evidenz:
  - [SyncEngine.swift:315](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Sync/SyncEngine.swift:315)
  - [SyncEngine.swift:334](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Sync/SyncEngine.swift:334)
  - [SyncScheduler.swift:336](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Sync/SyncScheduler.swift:336)
- Problem:
  - `SyncEngine` aggregiert Semesterfehler als `String` (`activeSemesterSyncFailed([String])`), danach klassifiziert `SyncScheduler` pauschal als `serverTemporary`.
  - Permanente Ursachen (z. B. Auth/Config) koennen dadurch als retrybar behandelt werden.
- Risiko:
  - Unnoetige Retries, irrefuehrender Status fuer Nutzer, langsamere Fehlerdiagnose.
- Empfehlung:
  - Strukturierte Fehleraggregation (typed payload statt `String`) und differenzierte Klassifikation im Scheduler.

### 3) Medium: "Cache leeren" invalidiert keine aktiven In-Memory-Listen
- Evidenz:
  - [SettingsView.swift:300](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/UI/SettingsView.swift:300)
  - [ContentView+StateAndPrefetch.swift:308](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/ContentView+StateAndPrefetch.swift:308)
- Problem:
  - Der Settings-Action-Flow entfernt Disk-Caches, aber aktive UI-States (z. B. `coursesBySemesterID`, geladene Semesterliste) bleiben unveraendert.
- Risiko:
  - Nutzer sieht nach "Cache leeren" weiterhin alte Daten bis zum manuellen Reload/Neustart.
- Empfehlung:
  - Globales Cache-Invalidation-Signal (z. B. via `NotificationCenter`/Store-Flag) und unmittelbares Leeren der In-Memory-Caches.

### 4) Medium: UI-Smoke-Tests sind noch sehr schmal und fragil
- Evidenz:
  - [StudipSyncUITests.swift:33](/Users/julius.hunold/Projects/github/StudipSync/StudipSyncUITests/StudipSyncUITests.swift:33)
- Problem:
  - Aktuelle UI-Smokes decken nur Launch + Settings-Shortcut ab; zentrale RC-Pfade (Menu-Bar-Statuswechsel, Cache-leeren-Feedback, Sync-Trigger) sind nicht abgesichert.
  - `Cmd+,` als Navigationspfad ist auf macOS-UI-Tests erfahrungsgemaess fragil.
- Risiko:
  - Regressions in Settings/Menu-Bar bleiben unentdeckt.
- Empfehlung:
  - Smoke-Pfade robust ueber sichtbare UI-Elemente absichern und mindestens einen Statuswechsel (Running/Error/Success) kontrolliert pruefen.

### 5) Low: API-Dokumentation driftet gegen implementierte Routen
- Evidenz:
  - `python3 Scripts/validate_api_coverage.py` meldet 12 implementierte, aber undokumentierte Routen.
- Problem:
  - API-Abdeckung ist funktional vollstaendig, aber interne Doku/Abgleich ist nicht mehr synchron.
- Risiko:
  - Hoehere Wartungskosten bei API-Aenderungen, Fehlinterpretation des echten Umfangs.
- Empfehlung:
  - Skript-Quelle bzw. Doku-Liste auf implementierten Stand aktualisieren.

## Empfohlene Reihenfolge
1. Persistenten Kurs-Cache einfuehren (High).
2. Fehleraggregation/-klassifikation typisiert nachziehen (Medium).
3. In-Memory-Invalidierung bei "Cache leeren" ergaenzen (Medium).
4. UI-Smoke-Abdeckung fuer Settings/Menu-Bar robust machen (Medium).
5. API-Doku/Route-Referenz synchronisieren (Low).
