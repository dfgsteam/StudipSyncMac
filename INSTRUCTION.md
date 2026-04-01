# StudipSync App Instruction

## Ziel
Baue eine native macOS-App (Swift + SwiftUI), die Dateien aus der Stud.IP REST API automatisch in einen lokalen Ordner synchronisiert.

Referenz-API: https://studip.github.io/studip-rest.ip/

## Muss-Anforderungen
1. API-Integration
- Nutze die Stud.IP REST API als einzige Datenquelle.
- Implementiere einen zentralen API-Client mit sauberem Error-Handling (HTTP-Fehler, Timeouts, Offline).
- API-Key-basierte Authentifizierung muss unterstuetzt sein.
- Bilde die komplette relevante Stud.IP API als interne Resource-Schicht nach (1:1 Resource-Mapping mit stabilen lokalen Modellen/DTOs statt ad-hoc Einzelaufrufen).

2. Lokale automatische Synchronisierung
- Nutzer waehlt einen lokalen Root-Ordner.
- Dateien werden automatisch synchronisiert:
  - beim App-Start
  - in einem festen Intervall (z. B. alle 5-15 Minuten, konfigurierbar)
  - optional manuell ueber "Jetzt synchronisieren".
- Synchronisation nur fuer aktive/ausgewaehlte Semester.
- Sync muss inkrementell sein (nur geaenderte/neue Dateien laden, geloeschte Dateien lokal entfernen oder markieren).
- Empfohlene Ordnerstruktur:
  - `<Root>/<Semester>/<Kurs>/<Datei>`

3. Semester aktivieren/deaktivieren
- App zeigt alle verfuegbaren Semester aus der API.
- Jedes Semester hat einen Toggle "Aktiv fuer Sync".
- Auswahl wird lokal persistent gespeichert.
- Nur aktivierte Semester werden im Auto-Sync beruecksichtigt.

4. API-Key in Keychain
- API-Key darf niemals in Klartext in UserDefaults, Dateien oder Logs stehen.
- Speicherung/Lesen/Loeschen nur ueber macOS Keychain (Security Framework oder Wrapper).
- UI fuer "API-Key setzen", "API-Key aktualisieren", "API-Key entfernen".

5. Menu-Bar-Status
- App laeuft als Menu-Bar-App mit Status-Icon.
- Icon/Zustand zeigt laufend den Sync-Status:
  - Idle
  - Sync laeuft
  - Erfolgreich (letzter Sync ok)
  - Fehler
  - Offline
- Menu enthaelt mindestens:
  - Statuszeile (inkl. Zeit des letzten Syncs)
  - "Jetzt synchronisieren"
  - "Einstellungen"
  - "Beenden"

6. Lokales Caching fuer Semester/Kurs-Informationen
- Semester- und Kurs-Metadaten muessen lokal gecacht werden (z. B. in SQLite oder einer stabilen lokalen Cache-Datei).
- App-Start darf zuerst aus Cache rendern und danach im Hintergrund aktualisieren (stale-while-revalidate).
- Cache muss versioniert und invalidierbar sein (z. B. bei API-Aenderungen oder manueller "Cache leeren"-Aktion).
- Bei temporarem Offline-Zustand sollen letzte bekannte Semester/Kurse aus dem Cache verfuegbar bleiben.
- Cache-Schluessel muessen mandantenfaehig sein (mindestens pro Stud.IP-Base-URL getrennt).

7. Stud.IP-URL einstellbar
- Die Stud.IP-Base-URL muss in den Einstellungen frei konfigurierbar sein (z. B. `https://studip.uni-goettingen.de`).
- URL-Eingabe validieren: gueltiges HTTPS, keine Leerzeichen, normalisierte Base-URL.
- Alle API-Aufrufe muessen die aktuell konfigurierte Base-URL verwenden.
- API-Keys muessen eindeutig pro Base-URL gespeichert werden (keine Vermischung von Credentials verschiedener Instanzen).
- Beim Wechsel der Base-URL muessen Cache und Sync-Kontext sauber getrennt oder neu initialisiert werden.

## Architektur (empfohlen)
- `StudIPAPIClient`: alle REST-Aufrufe, DTO-Mapping.
- `StudIPResourceRepository`: vollstaendige Abbildung der Stud.IP-Resources (Semantik/Endpoints) als zentrale Domain-Resource-Schicht.
- `KeychainService`: API-Key-Verwaltung.
- `SyncEngine`: Delta-Berechnung, Download, Dateisystem-Operationen.
- `SemesterSelectionStore`: persistente Aktiv/Deaktiv-Auswahl.
- `SyncScheduler`: Timer + Trigger (Startup, Intervall, manuell).
- `MenuBarStatusController`: Mapping SyncState -> Icon/Text.
- `MetadataCache`: lokales Caching fuer Semester/Kurs-Metadaten inkl. Invalidation.
- `SettingsStore`: persistente Konfiguration fuer Stud.IP-Base-URL und Sync-Optionen.

## Wichtige technische Regeln
- Verwende Swift Concurrency (`async/await`) fuer Netzwerk und Sync-Jobs.
- Verhindere parallele doppelte Sync-Laeufe (Lock/Single-flight).
- Schreibe strukturierte Logs ohne Secrets.
- Behandle Dateinamen/Ordner robust (ungueltige Zeichen, Duplikate, sehr lange Namen).

## Performance & Energieeffizienz (Muss)
- Verwende konsequent Delta-Sync (z. B. `ETag`/`If-None-Match`, `Last-Modified`/`If-Modified-Since`), keine Vollsynchronisation ohne Bedarf.
- Nutze adaptive Sync-Intervalle mit Backoff (haeufiger bei Aenderungen, seltener bei Inaktivitaet/Fehlern).
- Plane Hintergrundsynchronisation energieeffizient (z. B. `NSBackgroundActivityScheduler` + `tolerance`) statt aggressiver Polling-Timer.
- Begrenze parallele Downloads (z. B. max. 2-4), um CPU-, Netzwerk- und IO-Spitzen zu vermeiden.
- Schreibe Dateien nur bei echten Aenderungen und atomar auf Disk.
- Streame Downloads direkt auf Disk; grosse Dateien nicht komplett im RAM puffern.
- Nutze fuer Auto-Sync niedrige Prioritaet (`TaskPriority.utility`/`background`, passende QoS).
- Unterstuetze optionales Pausieren bei Batteriebetrieb oder aktivem Low-Power-Mode (manueller Sync bleibt moeglich).
- Unterstuetze optionales "Nur im WLAN synchronisieren" und respektiere Low-Data-Mode.
- Fuehre keinen aktiven Sync waehrend Sleep aus; robustes Resume nach Wake ist Pflicht.

## Akzeptanzkriterien
- Mit gueltigem API-Key kann die App Semester laden.
- Aktivierte Semester werden korrekt in den lokalen Ordner synchronisiert.
- Deaktivierte Semester werden nicht mehr aktiv synchronisiert.
- API-Key ist nach Neustart aus Keychain verfuegbar.
- Menu-Bar-Icon aktualisiert den Status sichtbar waehrend und nach jedem Sync.
- Bei Netzwerk- oder API-Fehlern bleibt die App stabil und zeigt einen klaren Fehlerstatus.
- Bei unveraenderten Remote-Daten werden keine Dateien erneut geladen.
- Im Leerlauf entstehen keine regelmaessigen CPU-Spitzen durch den Sync-Mechanismus.
- Bei grossen Datei-Mengen bleibt die UI responsiv (Sync laeuft entkoppelt im Hintergrund).
- Nach App-Neustart kann ein laufender/abgebrochener Sync robust fortgesetzt werden, ohne unnoetige Vollsynchronisation.
- Bei fehlender Netzwerkverbindung sind zuletzt bekannte Semester/Kurse weiterhin aus lokalem Cache sichtbar.
- Nach Wechsel der Stud.IP-Base-URL nutzt die App nur noch Endpunkte, Cache und API-Key der neuen URL.
