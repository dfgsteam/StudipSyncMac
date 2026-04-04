# Release Checklist (StudipSync)

Stand: 2026-04-04

## Build & Signing
- [ ] Target-Version/Build-Nummer aktualisiert.
- [ ] Team/Signing-Identitaet gesetzt.
- [ ] Hardened Runtime aktiv.
- [ ] Entitlements geprueft (`com.apple.security.app-sandbox`, Netzwerk-Client, File Access).

## Notarisierung (falls Distribution ausserhalb App Store)
- [ ] Archiv (`.app`/`.pkg`) erstellt.
- [ ] Notary-Upload erfolgreich.
- [ ] Ticket gestapled.
- [ ] Launch auf sauberem Test-Mac verifiziert (Gatekeeper).

## Functional Smoke
- [ ] Erster Start ohne Crash.
- [ ] API-Key setzen/lesen/entfernen funktioniert.
- [ ] Semesterliste laedt online und aus Cache offline.
- [ ] Manueller Sync, Auto-Sync und Wake-Resume funktionieren.
- [ ] Menu-Bar Status (Idle/Running/Success/Error/Offline) sichtbar korrekt.
- [ ] "Cache leeren" in Settings funktioniert.

## Performance & Stability
- [ ] Keine auffaelligen CPU-Spitzen im Leerlauf.
- [ ] Speicherverbrauch ueber >2h stabil.
- [ ] Sync bei grossen Dateimengen blockiert UI nicht.

## Security & Logging
- [ ] Keine Secrets in Logs.
- [ ] Keine Credentials in UserDefaults/Dateien.
- [ ] Keychain-Storage pro Base-URL verifiziert.

## Test-Gates
- [ ] Unit-Tests (API/Keychain/Cache/Delta) gruen.
- [ ] Sync-Integrationstests gruen.
- [ ] UI-Smoke-Tests (Settings/Menu-Bar-Pfade) gruen.

## Docs & Rollout
- [ ] CHANGELOG/Release Notes aktualisiert.
- [ ] Bekannte Einschraenkungen dokumentiert.
- [ ] Rollback-Plan dokumentiert.
