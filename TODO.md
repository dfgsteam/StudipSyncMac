# todo

- Zurück/Vor button richtig in den header
- reload button auch in den header mit icon
- sync button in den header
- links in der nav über die volle breite  (inv.)
- avatarbilder laden

## audit follow-ups (2026-04-04)

- [ ] SyncEngine: entfernte Remote-Dateien lokal loeschen oder markieren (inkl. Manifest-/Disk-Cleanup).
- [ ] SyncEngine: `startAccessingSecurityScopedResource()` hart pruefen und bei `false` mit klarer Fehlermeldung abbrechen.
- [ ] SyncScheduler: Tolerance-Strategie ohne systematischen Drift umsetzen (Intervall soll nicht dauerhaft nach hinten wandern).
- [ ] Menu-Bar: doppelte "letzter erfolgreicher Sync"-Ausgabe bei Success bereinigen.
- [ ] Tests: kritische Sync-Pfade ergaenzen (Datei-Loeschung/Markierung, Security-Scoped-Fehlerpfad, Scheduler-Tolerance).
