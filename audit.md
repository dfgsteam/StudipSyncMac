# Code Audit

Stand: 2026-04-04

## Scope
- Geprueft: Sync-Pipeline (`SyncEngine`, `SyncScheduler`) und Status-UX (`MenuBarStatusController`, `MenuBarRootView`).
- Bezug: Muss-Anforderungen aus `INSTRUCTION.md` (insbesondere inkrementeller Sync, Fehlerrobustheit, Menu-Bar-Status).

## Validierung
- `xcrun swiftc -frontend -parse $(rg --files StudipSync StudipSyncTests -g '*.swift')`: erfolgreich.
- `python3 Scripts/validate_api_coverage.py`: `Missing routes: 0`.
- `xcodebuild ... test`: in aktueller Umgebung nicht ausfuehrbar (nur CommandLineTools, kein volles Xcode).

## Findings (priorisiert)

### 1) High: Entfernte Remote-Dateien werden lokal nicht geloescht oder markiert
- Evidenz:
  - [StudipSync/Sync/SyncEngine.swift:222](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Sync/SyncEngine.swift:222)
  - [StudipSync/Sync/SyncEngine.swift:229](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Sync/SyncEngine.swift:229)
- Problem:
  - Der Sync entfernt nur Manifest-Eintraege, bereinigt aber keine bereits lokal liegenden Dateien fuer nicht mehr vorhandene Remote-IDs.
- Risiko:
  - Drift zwischen Remote- und lokalem Stand, wachsender Datenmuell, Verletzung der Sync-Anforderung aus `INSTRUCTION.md` ("geloeschte Dateien lokal entfernen oder markieren").
- Empfehlung:
  - Beim Manifest-Cleanup geloeschte/obsolet gewordene Dateien auf Disk entfernen oder in definierte Quarantaene verschieben.
  - Optional konfigurierbar machen (hart loeschen vs. markieren).

### 2) Medium: Security-scoped Zugriff wird nicht hart validiert
- Evidenz:
  - [StudipSync/Sync/SyncEngine.swift:170](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Sync/SyncEngine.swift:170)
  - [StudipSync/Sync/SyncEngine.swift:177](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Sync/SyncEngine.swift:177)
- Problem:
  - `startAccessingSecurityScopedResource()` wird aufgerufen, aber ein `false`-Rueckgabewert stoppt den Lauf nicht.
- Risiko:
  - Nicht-deterministisches Verhalten bei Sandbox-/Bookmark-Problemen, spaete File-Fehler ohne klare Ursache.
- Empfehlung:
  - Bei `didAccessScope == false` frueh mit `rootFolderNotAccessible` abbrechen (klarer Status/Error-Pfad).

### 3) Medium: Tolerance-Strategie fuehrt zu systematischem Intervall-Drift
- Evidenz:
  - [StudipSync/Sync/SyncScheduler.swift:31](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Sync/SyncScheduler.swift:31)
  - [StudipSync/Sync/SyncScheduler.swift:84](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Sync/SyncScheduler.swift:84)
- Problem:
  - Jitter wird nur positiv addiert (`base + random(0...tolerance)`), dadurch ist der effektive Intervall immer groesser als konfiguriert.
- Risiko:
  - Zeitliche Drift bei langen Laufzeiten, unerwartete Abweichung vom eingestellten Sync-Intervall.
- Empfehlung:
  - Entweder feste Baseline + systemseitige Tolerance (z. B. `NSBackgroundActivityScheduler`) oder symmetrischer Jitter um den Zielzeitpunkt.

### 4) Low: Doppelte "letzter Sync"-Information in der Menu-Bar bei Success
- Evidenz:
  - [StudipSync/UI/MenuBarRootView.swift:12](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/UI/MenuBarRootView.swift:12)
  - [StudipSync/UI/MenuBarRootView.swift:16](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/UI/MenuBarRootView.swift:16)
  - [StudipSync/Core/SyncState.swift:29](/Users/julius.hunold/Projects/github/StudipSync/StudipSync/Core/SyncState.swift:29)
- Problem:
  - Bei Success wird "letzter erfolgreicher Sync" sowohl als feste Zeile als auch als Status-Detail gezeigt.
- Risiko:
  - UX-Rauschen, unnoetige Redundanz.
- Empfehlung:
  - Erfolgsdetail unterdruecken oder nur fuer Error-Faelle als Detailzeile anzeigen.

### 5) Medium: Testabdeckung fuer kritische Sync-Pfade ist noch lueckenhaft
- Evidenz:
  - Vorhandene Tests fokussieren aktuell primär auf Utility/Status, z. B. [StudipSyncTests/StudipSyncTests.swift:87](/Users/julius.hunold/Projects/github/StudipSync/StudipSyncTests/StudipSyncTests.swift:87)
- Problem:
  - Keine gezielten Tests fuer:
  - Datei-Loesch-/Markierlogik.
  - Scheduler-Tolerance ohne Drift.
  - Fehlerpfad bei nicht verfuegbarem Security-Scoped Zugriff.
- Risiko:
  - Regressionsgefahr bei zentralen Sync-Funktionen.
- Empfehlung:
  - Integration-nahe Tests mit temp-Verzeichnis + stubbed Repository/Settings fuer die obigen Faelle.

## Empfohlene Reihenfolge
1. Entfernte Dateien korrekt behandeln (High).
2. Security-scoped Zugriff hart validieren (Medium).
3. Scheduler-Tolerance ohne Drift umsetzen (Medium).
4. Testabdeckung fuer Sync-Kernpfade ausbauen (Medium).
5. Menu-Bar Redundanz bereinigen (Low).
