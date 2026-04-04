# StudipSync Roadmap

Stand: 2026-04-04

## Zielbild
Eine stabile, akkusparende macOS Menu-Bar-App, die Dateien aus konfigurierbaren Stud.IP-Instanzen automatisch in lokale Ordner synchronisiert, inklusive Semester-Auswahl, sicherer Keychain-Auth und robuster Offline-/Cache-Unterstuetzung.

## Status
- Phase 0: abgeschlossen (2026-04-04)
- Phase 1: abgeschlossen (2026-04-04)
- Phase 2: abgeschlossen (2026-04-04)
- Phase 3: abgeschlossen (2026-04-04)
- Phase 4: abgeschlossen (2026-04-04)
- Phase 5: offen

## Phase 0: Fundament (Woche 1)
Zeitraum: 2026-04-01 bis 2026-04-07

Deliverables:
- Projektstruktur fuer Core-Module:
  - `StudIPAPIClient`
  - `KeychainService`
  - `SettingsStore`
  - `MetadataCache`
  - `SyncEngine`
  - `SyncScheduler`
  - `MenuBarStatusController`
- Zentrale Konfigurationsmodelle (Base-URL, Sync-Intervall, Root-Ordner, Semester-Selektion).
- Basis-Logging ohne Secrets.

Abnahme:
- App startet stabil als Menu-Bar-App.
- Base-URL kann gespeichert/geladen werden.
- API-Key kann in Keychain gespeichert/gelesen/geloescht werden.

## Phase 1: API + Metadaten + Einstellungen (Woche 2)
Zeitraum: 2026-04-08 bis 2026-04-14

Deliverables:
- API-Client mit Auth und Error-Handling.
- Vollstaendige Resource-Abbildung der Stud.IP API als interne Schicht (`StudIPResourceRepository`) mit klaren DTOs/Domain-Modellen.
- Semester- und Kurs-Endpunkte integriert.
- Lokaler Metadaten-Cache (stale-while-revalidate, versionierbar, invalidierbar).
- Einstellungsoberflaeche:
  - Stud.IP-Base-URL (validiert)
  - API-Key-Verwaltung
  - lokaler Zielordner

Abnahme:
- Semesterliste laedt online und faellt offline auf Cache zurueck.
- URL-Wechsel trennt Instanzkontext sauber (Keychain + Cache pro Base-URL).
- Die definierten Stud.IP-Resources sind vollstaendig ueber die interne Resource-Schicht adressierbar (ohne ad-hoc API-Zugriffe in UI/Sync-Code).

## Phase 2: Datei-Sync MVP (Woche 3)
Zeitraum: 2026-04-15 bis 2026-04-21

Deliverables:
- Semester aktivieren/deaktivieren mit persistenter Auswahl.
- Manueller Sync-Flow (`Jetzt synchronisieren`).
- Inkrementeller Download fuer aktivierte Semester.
- Lokale Struktur `<Root>/<Semester>/<Kurs>/<Datei>`.
- Single-flight-Schutz gegen parallele Syncs.

Abnahme:
- Nur aktivierte Semester werden synchronisiert.
- Wiederholter Sync laedt unveraenderte Dateien nicht erneut.

## Phase 3: Auto-Sync + Status UX (Woche 4)
Zeitraum: 2026-04-22 bis 2026-04-28

Deliverables:
- Automatischer Sync bei App-Start.
- Hintergrund-Scheduler mit Intervall + Tolerance.
- Status-Icon mit Zustaenden: Idle, Running, Success, Error, Offline.
- Menu-Bar-Eintraege: Status, letzter Sync, Jetzt synchronisieren, Einstellungen, Beenden.

Abnahme:
- Status aktualisiert sich sichtbar waehrend und nach jedem Lauf.
- Fehlerzustaende werden klar angezeigt, App bleibt stabil.

## Phase 4: Performance & Akku (Woche 5)
Zeitraum: 2026-04-29 bis 2026-05-05

Deliverables:
- Delta-Sync per `ETag`/`Last-Modified`.
- Adaptive Intervalle (Backoff bei Inaktivitaet/Fehlern).
- Begrenzte Download-Konkurrenz (2-4 parallel).
- Streaming-Downloads auf Disk + atomare Writes bei Aenderung.
- Optionen:
  - Pause bei Battery/Low Power
  - Nur WLAN

Abnahme:
- Keine auffaelligen CPU-Spitzen im Leerlauf.
- UI bleibt responsiv bei grossen Datenmengen.

## Phase 5: Hardening & Release Candidate (Woche 6)
Zeitraum: 2026-05-06 bis 2026-05-12

Deliverables:
- Retry-Strategien, Resume nach Wake/Sleep, robuste Fehlerklassifikation.
- Cache-Invalidierung und "Cache leeren"-Funktion.
- Tests:
  - Unit-Tests fuer API-Client, Keychain, Cache, Delta-Logik
  - Integrations-Tests fuer Sync-Pipeline
  - UI-Smoke-Tests fuer Settings/Menu-Bar
- Release-Checkliste (Signierung/Notarisierung falls geplant).

Abnahme:
- Alle Muss-Anforderungen aus `INSTRUCTION.md` sind nachweisbar erfuellt.
- Candidate ist fuer Beta-Nutzung stabil.

## Priorisierte Backlog-Items (nach RC)
- Konfliktbehandlung bei lokal geaenderten Dateien.
- Bandbreitenlimit/Throttle.
- Detailliertes Aktivitaetsprotokoll pro Kurs.
- Desktop-Benachrichtigungen fuer Fehler/Erfolg.
- Optionaler One-way vs. Mirror-Mode.

## Risiken und Gegenmassnahmen
- API-Inkonsistenzen je Stud.IP-Instanz:
  - Gegenmassnahme: robuste Decoder, Feature-Flags pro Base-URL.
- Grosse Dateimengen belasten IO:
  - Gegenmassnahme: Queue-Limits, Streaming, Backpressure.
- User-seitige falsche URL/API-Key:
  - Gegenmassnahme: fruehe Validierung + klare Fehlertexte.

## Definition of Done (gesamt)
- Alle Akzeptanzkriterien aus `INSTRUCTION.md` sind getestet.
- Keine Secrets im Log oder in ungesicherten Stores.
- Sync laeuft stabil automatisch ueber mehrere Stunden ohne Memory-Leak-Indikatoren.
- Die komplette relevante Stud.IP API ist als Resource-Schicht nachgebaut und wird zentral verwendet.
