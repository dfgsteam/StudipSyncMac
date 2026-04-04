# todo

- [x] Zurück/Vor button richtig in den header
- [x] reload button auch in den header mit icon
- [x] sync button in den header
- [x] links in der nav über die volle breite (inv.)
- [x] avatarbilder laden

## audit follow-ups (2026-04-04)

- [x] SyncEngine: entfernte Remote-Dateien lokal loeschen oder markieren (inkl. Manifest-/Disk-Cleanup).
- [x] SyncEngine: `startAccessingSecurityScopedResource()` hart pruefen und bei `false` mit klarer Fehlermeldung abbrechen.
- [x] SyncScheduler: Tolerance-Strategie ohne systematischen Drift umsetzen (Intervall soll nicht dauerhaft nach hinten wandern).
- [x] Menu-Bar: doppelte "letzter erfolgreicher Sync"-Ausgabe bei Success bereinigen.
- [x] Tests: kritische Sync-Pfade ergaenzen (Datei-Loeschung/Markierung, Security-Scoped-Fehlerpfad, Scheduler-Tolerance).

## phase 5 closeout (2026-04-04)

- [x] Retry-Strategie inkl. Fehlerklassifikation im SyncScheduler umgesetzt.
- [x] Resume nach Wake/Sleep im Scheduler umgesetzt.
- [x] "Cache leeren" in Settings implementiert (Metadata + Shared-Courses Cache).
- [x] Unit-/Integrations-/UI-Smoke-Testabdeckung erweitert.
- [x] Release-Checkliste erstellt (`RELEASE_CHECKLIST.md`).
