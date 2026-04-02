# Courses API

## Route
`GET /jsonapi.php/v1/courses`

## Typ
`GET`

## Parameter

### Query-Parameter

| Name             | Typ    | Pflicht | Beschreibung |
|------------------|--------|--------|-------------|
| filter[semester] | string | nein   | Filter nach Semester-ID |
| filter[user]     | string | nein   | Filter nach Benutzer-ID |
| page[offset]           | int    | nein   | Startindex der Rückgabe |
| page[limit]            | int    | nein   | Maximale Anzahl an Datensätzen |

## Beispiel-Antwort

{
  "data": [
    {
      "type": "courses",
      "id": "course123",
      "attributes": {
        "title": "Mathematik 1",
        "subtitle": "Einführung",
        "description": "Grundlagen der Mathematik",
        "location": "Raum 101",
        "type": "lecture",
        "start-date": "2025-10-15T10:00:00+00:00",
        "end-date": "2026-02-15T12:00:00+00:00"
      }
    }
  ],
  "meta": {
    "total": 25
  }
}

---

## Route
`GET /jsonapi.php/v1/courses/{id}`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Kurses |

## Beispiel-Antwort

{
  "data": {
    "type": "courses",
    "id": "course123",
    "attributes": {
      "title": "Mathematik 1",
      "subtitle": "Einführung",
      "description": "Grundlagen der Mathematik",
      "location": "Raum 101",
      "type": "lecture",
      "start-date": "2025-10-15T10:00:00+00:00",
      "end-date": "2026-02-15T12:00:00+00:00"
    }
  }
}

# Semesters API

## Route
`GET /jsonapi.php/v1/semesters`

## Typ
`GET`

## Parameter

### Query-Parameter

| Name   | Typ | Pflicht | Beschreibung |
|--------|-----|--------|-------------|
| page[offset] | int | nein   | Startindex der Rückgabe |
| page[limit]  | int | nein   | Maximale Anzahl an Datensätzen |

## Beispiel-Antwort

{
  "data": [
    {
      "type": "semesters",
      "id": "abc123",
      "attributes": {
        "title": "WS 2025/26",
        "token": "WS2025",
        "start": "2025-10-01T00:00:00+00:00",
        "end": "2026-03-31T00:00:00+00:00",
        "start-of-lectures": "2025-10-15T00:00:00+00:00",
        "end-of-lectures": "2026-02-15T00:00:00+00:00",
        "visible": true,
        "is-current": false
      }
    }
  ],
  "meta": {
    "total": 12
  }
}

---

## Route
`GET /jsonapi.php/v1/semesters/{id}`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Semesters |

## Beispiel-Antwort

{
  "data": {
    "type": "semesters",
    "id": "abc123",
    "attributes": {
      "title": "WS 2025/26",
      "token": "WS2025",
      "start": "2025-10-01T00:00:00+00:00",
      "end": "2026-03-31T00:00:00+00:00",
      "start-of-lectures": "2025-10-15T00:00:00+00:00",
      "end-of-lectures": "2026-02-15T00:00:00+00:00",
      "visible": true,
      "is-current": false
    }
  }
}