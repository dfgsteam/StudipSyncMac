# Courses API

## Route  
`GET /jsonapi.php/v1/courses`

## Typ  
`GET`

## Parameter

### Query-Parameter

| Name             | Typ    | Pflicht | Beschreibung |
|------------------|--------|--------|-------------|
| page[offset]     | int    | nein   | Startindex |
| page[limit]      | int    | nein   | Anzahl der Datensätze |
| filter[q]        | string | nein   | Suchbegriff (min. 3 Zeichen) |
| filter[fields]   | string | nein   | Suchfelder (z. B. title, lecturer, number) |
| filter[semester] | string | nein   | Semester |

## Beispiel-Antwort

~~~json
{
  "data": [
    {
      "type": "courses",
      "id": "course1",
      "attributes": {
        "title": "Mathematik 1",
        "course-number": "MATH-101"
      }
    }
  ]
}
~~~

---

## Route  
`GET /jsonapi.php/v1/courses/{id}`

## Typ  
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | Kurs-ID |

## Beispiel-Antwort

~~~json
{
  "data": {
    "type": "courses",
    "id": "course1",
    "attributes": {
      "title": "Mathematik 1"
    }
  }
}
~~~

---

## Route  
`GET /jsonapi.php/v1/users/{id}/courses`

## Typ  
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | User-ID |

## Beispiel-Antwort

~~~json
{
  "data": []
}
~~~

---

## Route  
`GET /jsonapi.php/v1/courses/{id}/memberships`

## Typ  
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | Kurs-ID |

### Query-Parameter

| Name               | Typ    | Pflicht | Beschreibung |
|--------------------|--------|--------|-------------|
| filter[permission] | string | nein   | Rolle des Nutzers |

## Beispiel-Antwort

~~~json
{
  "data": []
}
~~~

---

## Route  
`GET /jsonapi.php/v1/courses/{id}/relationships/memberships`

## Typ  
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | Kurs-ID |

## Beispiel-Antwort

~~~json
{
  "data": []
}
~~~

---

## Route  
`GET /jsonapi.php/v1/course-memberships/{id}`

## Typ  
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | Membership-ID |

## Beispiel-Antwort

~~~json
{
  "data": {
    "type": "course-memberships",
    "id": "1",
    "attributes": {
      "permission": "autor"
    }
  }
}
~~~

---

## Route  
`PATCH /jsonapi.php/v1/course-memberships/{id}`

## Typ  
`PATCH`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | Membership-ID |

## Beispiel-Antwort

~~~json
{
  "data": {
    "type": "course-memberships",
    "id": "1",
    "attributes": {
      "visible": "yes"
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

# Dateien

## Route
`GET /terms-of-use`

## Typ
`GET`

## Parameter

keine

## Beispiel-Antwort

{
  "data": [
    {
      "type": "terms-of-use",
      "id": "FREE_LICENSE",
      "attributes": {
        "name": "Free License",
        "description": "Free to use",
        "icon": "icon.png"
      }
    }
  ]
}

---

## Route
`GET /terms-of-use/{id}`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der Lizenz |

## Beispiel-Antwort

{
  "data": {
    "type": "terms-of-use",
    "id": "FREE_LICENSE",
    "attributes": {
      "name": "Free License",
      "description": "Free to use",
      "icon": "icon.png"
    }
  }
}

---

## Route
`GET /courses/{id}/file-refs`
`GET /institutes/{id}/file-refs`
`GET /users/{id}/file-refs`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Bereichs |

### Query-Parameter

| Name         | Typ | Pflicht | Beschreibung |
|--------------|-----|--------|-------------|
| page[offset] | int | nein   | Offset |
| page[limit]  | int | nein   | Limit |

## Beispiel-Antwort

{
  "data": [
    {
      "type": "file-refs",
      "id": "file123",
      "attributes": {
        "name": "file.pdf",
        "description": "Beschreibung",
        "filesize": 12345
      }
    }
  ]
}

---

## Route
`GET /courses/{id}/folders`
`GET /institutes/{id}/folders`
`GET /users/{id}/folders`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Bereichs |

### Query-Parameter

| Name         | Typ | Pflicht | Beschreibung |
|--------------|-----|--------|-------------|
| page[offset] | int | nein   | Offset |
| page[limit]  | int | nein   | Limit |

## Beispiel-Antwort

{
  "data": [
    {
      "type": "folders",
      "id": "folder123",
      "attributes": {
        "name": "Ordner",
        "description": "Beschreibung"
      }
    }
  ]
}

---

## Route
`GET /file-refs/{id}`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der Datei |

## Beispiel-Antwort

{
  "data": {
    "type": "file-refs",
    "id": "file123",
    "attributes": {
      "name": "file.pdf",
      "description": "Beschreibung"
    }
  }
}

---

## Route
`PATCH /file-refs/{id}`

## Typ
`PATCH`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der Datei |

## Beispiel-Antwort

{
  "data": {
    "type": "file-refs",
    "id": "file123",
    "attributes": {
      "name": "neuer-name.pdf"
    }
  }
}

---

## Route
`DELETE /file-refs/{id}`

## Typ
`DELETE`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der Datei |

## Beispiel-Antwort

{}

---

## Route
`GET /folders/{id}`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Ordners |

## Beispiel-Antwort

{
  "data": {
    "type": "folders",
    "id": "folder123",
    "attributes": {
      "name": "Ordner"
    }
  }
}

---

## Route
`PATCH /folders/{id}`

## Typ
`PATCH`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Ordners |

## Beispiel-Antwort

{
  "data": {
    "type": "folders",
    "id": "folder123",
    "attributes": {
      "name": "Neuer Name"
    }
  }
}

---

## Route
`DELETE /folders/{id}`

## Typ
`DELETE`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Ordners |

## Beispiel-Antwort

{}

---

## Route
`GET /folders/{id}/file-refs`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Ordners |

### Query-Parameter

| Name         | Typ | Pflicht | Beschreibung |
|--------------|-----|--------|-------------|
| page[offset] | int | nein   | Offset |
| page[limit]  | int | nein   | Limit |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /folders/{id}/folders`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Ordners |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /file-refs/{id}/content`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der Datei |

## Beispiel-Antwort

(Binary Data)

---

## Route
`HEAD /file-refs/{id}/content`

## Typ
`HEAD`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der Datei |

## Beispiel-Antwort

(Headers mit ETag)

# Planer

## Route
`GET /users/{id}/events`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Nutzers |

### Query-Parameter

| Name              | Typ | Pflicht | Beschreibung |
|-------------------|-----|--------|-------------|
| filter[timestamp] | int | nein   | Startzeitpunkt (Unix-Timestamp) |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /users/{id}/events.ics`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Nutzers |

## Beispiel-Antwort

(iCalendar Data)

---

## Route
`GET /courses/{id}/events`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Kurses |

### Query-Parameter

| Name         | Typ | Pflicht | Beschreibung |
|--------------|-----|--------|-------------|
| page[offset] | int | nein   | Offset |
| page[limit]  | int | nein   | Limit |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /users/{id}/schedule`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Nutzers |

### Query-Parameter

| Name              | Typ | Pflicht | Beschreibung |
|-------------------|-----|--------|-------------|
| filter[timestamp] | int | nein   | Startzeitpunkt des Semesters |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /schedule-entries/{id}`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Eintrags |

## Beispiel-Antwort

{
  "data": {
    "type": "schedule-entries",
    "id": "123",
    "attributes": {
      "title": "Termin",
      "start": "08:00",
      "end": "10:00"
    }
  }
}

---

## Route
`GET /seminar-cycle-dates/{id}`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Termins |

## Beispiel-Antwort

{
  "data": {
    "type": "seminar-cycle-dates",
    "id": "123",
    "attributes": {
      "title": "Vorlesung",
      "start": "10:00",
      "end": "12:00",
      "weekday": 1
    }
  }
}

# Ankündigungen

## Route
`POST /news`

## Typ
`POST`

## Parameter

keine

## Beispiel-Antwort

{
  "data": {
    "type": "news",
    "attributes": {
      "title": "Neue News",
      "content": "Eine neue News sieht das Tageslicht."
    }
  }
}

---

## Route
`POST /courses/{id}/news`

## Typ
`POST`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Kurses |

## Beispiel-Antwort

{
  "data": {
    "type": "news",
    "attributes": {
      "title": "Neue News"
    }
  }
}

---

## Route
`POST /users/{id}/news`

## Typ
`POST`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Nutzers |

## Beispiel-Antwort

{
  "data": {
    "type": "news",
    "attributes": {
      "title": "Neue News"
    }
  }
}

---

## Route
`POST /news/{id}/comments`

## Typ
`POST`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der News |

## Beispiel-Antwort

{
  "data": {
    "type": "comments",
    "attributes": {
      "content": "Kommentar"
    }
  }
}

---

## Route
`PATCH /news/{id}`

## Typ
`PATCH`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der News |

## Beispiel-Antwort

{
  "data": {
    "type": "news",
    "attributes": {
      "title": "Geändert"
    }
  }
}

---

## Route
`GET /news/{id}`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der News |

## Beispiel-Antwort

{
  "data": {
    "type": "news",
    "id": "123",
    "attributes": {
      "title": "Titel",
      "content": "Inhalt",
      "comments-allowed": true
    }
  }
}

---

## Route
`GET /courses/{id}/news`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Kurses |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /users/{id}/news`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Nutzers |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /news/{id}/comments`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der News |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /studip/news`

## Typ
`GET`

## Parameter

keine

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /news`

## Typ
`GET`

## Parameter

keine

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`DELETE /news/{id}`

## Typ
`DELETE`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der News |

## Beispiel-Antwort

{}

---

## Route
`DELETE /comments/{id}`

## Typ
`DELETE`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Kommentars |

## Beispiel-Antwort

{}

---

## Route
`GET /news/{id}/relationships/ranges`

## Typ
`GET`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der News |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`PATCH /news/{id}/relationships/ranges`

## Typ
`PATCH`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der News |

## Beispiel-Antwort

{}

---

## Route
`POST /news/{id}/relationships/ranges`

## Typ
`POST`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der News |

## Beispiel-Antwort

{}

---

## Route
`DELETE /news/{id}/relationships/ranges`

## Typ
`DELETE`

## Parameter

### Path-Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der News |

## Beispiel-Antwort

{}

# Blubber

Blubber ermöglicht Chats zwischen Stud.IP-Teilnehmern (öffentlich, privat oder veranstaltungsbezogen).

## Schema
`blubber-postings`

### Attribute

| Attribut        | Beschreibung |
|----------------|-------------|
| context-type   | Kontext: `course`, `global`, `user` |
| content        | Text (Stud.IP-Markup möglich) |
| content-html   | HTML-formatierter Text |
| mkdate         | Anlegedatum |
| chdate         | Änderungsdatum |
| discussion-time| Letzte Aktivität |
| tags           | Liste von Tags |

### Relationen

| Relation  | Beschreibung |
|----------|-------------|
| author   | Verfasser |
| comments | Kommentare |
| context  | Sichtbarkeit (users, courses, public) |
| mentions | Erwähnungen |
| parent   | Übergeordneter Beitrag |
| resharers| Nutzer, die geteilt haben |

---

## Route
`GET /blubber-postings`

## Typ
`GET`

## Query-Parameter

| Name            | Typ    | Pflicht | Beschreibung |
|-----------------|--------|--------|-------------|
| filter[course]  | string | nein   | Nach Veranstaltung filtern |
| filter[user]    | string | nein   | Nach Nutzer filtern |
| include         | string | nein   | Relationen einbeziehen |
| page[offset]    | int    | nein   | Offset |
| page[limit]     | int    | nein   | Limit |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /blubber-postings/{id}`

## Typ
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Beitrags |

## Beispiel-Antwort

{
  "data": {
    "type": "blubber-postings",
    "id": "123"
  }
}

---

## Route
`POST /blubber-postings`

## Typ
`POST`

## Body (Pflichtfelder)

- content  
- context-type  
- context (abhängig von context-type)

## Beispiel-Request

{
  "data": {
    "type": "blubber-postings",
    "attributes": {
      "context-type": "course",
      "content": "Ein neuer blubberpost"
    },
    "relationships": {
      "context": {
        "data": {
          "type": "courses",
          "id": "<CID>"
        }
      }
    }
  }
}

---

## Route
`PATCH /blubber-postings/{id}`

## Typ
`PATCH`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Beitrags |

---

## Route
`DELETE /blubber-postings/{id}`

## Typ
`DELETE`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Beitrags |

---

## Route
`GET /blubber-postings/{id}/comments`

## Typ
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Beitrags |

---

## Route
`POST /blubber-postings/{id}/comments`

## Typ
`POST`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Beitrags |

## Beispiel-Request

{
  "data": {
    "type": "blubber-postings",
    "attributes": {
      "content": "Ein neuer Kommentar"
    }
  }
}

---

## Route
`GET /blubber-postings/{id}/relationships/author`

## Typ
`GET`

---

## Route
`GET /blubber-postings/{id}/relationships/comments`

## Typ
`GET`

---

## Route
`GET /blubber-postings/{id}/relationships/context`

## Typ
`GET`

---

## Route
`GET /blubber-postings/{id}/mentions`

## Typ
`GET`

---

## Route
`GET /blubber-postings/{id}/relationships/mentions`

## Typ
`GET`

---

## Route
`GET /blubber-postings/{id}/relationships/resharers`

## Typ
`GET`

---

## Route
`GET /blubber-streams/{id}`

## Typ
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Streams |

# Forum

Das Stud.IP-Forum ermöglicht Beiträge, Kommentare und Kategorisierung innerhalb einer Veranstaltung.

## Schema
`forum-categories`

### Attribute

| Attribut | Beschreibung |
|----------|-------------|
| title    | Name der Kategorie |
| position | Reihenfolge |

### Relationen

| Relation | Beschreibung |
|----------|-------------|
| course   | Zugehöriger Kurs |
| entries  | Forum-Einträge |

---

## Schema
`forum-entries`

### Attribute

| Attribut | Beschreibung |
|----------|-------------|
| title    | Titel (nur bei Themen) |
| content  | Inhalt |
| area     | Standard: `0` |

### Relationen

| Relation | Beschreibung |
|----------|-------------|
| category | Zugehörige Kategorie |
| entries  | Untereinträge |

---

## Route
`GET /courses/{id}/forum-categories`

## Typ
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Kurses |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /forum-categories/{id}`

## Typ
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der Kategorie |

## Beispiel-Antwort

{
  "data": {
    "type": "forum-categories",
    "id": "123",
    "attributes": {
      "title": "Allgemein",
      "position": 0
    }
  }
}

---

## Route
`GET /forum-categories/{id}/entries`

## Typ
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der Kategorie |

---

## Route
`POST /courses/{id}/forum-categories`

## Typ
`POST`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Kurses |

## Beispiel-Request

{
  "data": {
    "type": "forum-categories",
    "attributes": {
      "title": "Neue Kategorie"
    }
  }
}

---

## Route
`PATCH /forum-categories/{id}`

## Typ
`PATCH`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der Kategorie |

---

## Route
`DELETE /forum-categories/{id}`

## Typ
`DELETE`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der Kategorie |

---

## Route
`GET /forum-entries/{id}`

## Typ
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Eintrags |

## Beispiel-Antwort

{
  "data": {
    "type": "forum-entries",
    "id": "123",
    "attributes": {
      "title": "Thema",
      "content": "Text",
      "area": 0
    }
  }
}

---

## Route
`GET /forum-entries/{id}/entries`

## Typ
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Eintrags |

---

## Route
`POST /forum-categories/{id}/entries`

## Typ
`POST`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID der Kategorie |

## Beispiel-Request

{
  "data": {
    "type": "forum-entries",
    "attributes": {
      "title": "Neues Thema",
      "content": "Inhalt"
    }
  }
}

---

## Route
`POST /forum-entries/{id}/entries`

## Typ
`POST`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Eintrags |

## Beispiel-Request

{
  "data": {
    "type": "forum-entries",
    "attributes": {
      "title": "Antwort",
      "content": "Text"
    }
  }
}

---

## Route
`PATCH /forum-entries/{id}`

## Typ
`PATCH`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Eintrags |

---

## Route
`DELETE /forum-entries/{id}`

## Typ
`DELETE`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Eintrags |

# Nutzer*innen

Nutzer*innen (`users`) repräsentieren Accounts in Stud.IP.

## Schema
`users`

### Attribute

| Attribut              | Beschreibung |
|-----------------------|-------------|
| username              | Login-Name |
| formatted-name        | Vollständiger Name |
| family-name           | Nachname |
| given-name            | Vorname |
| name-prefix           | Titel (vorangestellt) |
| name-suffix           | Titel (nachgestellt) |
| permission            | Rolle (`root`, `admin`, `dozent`, `tutor`, `autor`) |
| email                 | E-Mail-Adresse |
| auth-plugin           | Authentifizierung |
| locked                | Account gesperrt |
| lock-comment          | Sperrhinweis |
| visible               | Sichtbarkeit |
| matriculation-number  | Matrikelnummer |
| gender                | Geschlecht |
| preferred-language    | Sprache |
| mkdate                | Erstellungsdatum |
| chdate                | Änderungsdatum |
| phone                 | Telefonnummer |
| cellphone             | Mobilnummer |
| address               | Adresse |
| homepage              | Website |
| hobby                 | Hobbies |
| cv                    | Lebenslauf |
| publication           | Publikationen |
| focus                 | Schwerpunkte |
| motto                 | Motto |

### Relationen

| Relation               | Beschreibung |
|------------------------|-------------|
| activitystream         | Aktivitätsstream |
| blubber-postings       | Blubber-Beiträge |
| contacts               | Kontakte |
| courses                | Veranstaltungen (als Dozent) |
| course-memberships     | Kursteilnahmen |
| datafield-entries      | Zusatzfelder |
| events                 | Termine |
| institute-memberships  | Institute |
| schedule               | Stundenplan |

---

## Route
`GET /users`

## Typ
`GET`

## Query-Parameter

| Name             | Typ    | Pflicht | Beschreibung |
|------------------|--------|--------|-------------|
| page[offset]     | int    | nein   | Offset (Default: 0) |
| page[limit]      | int    | nein   | Limit (Default: 30) |
| filter[search]   | string | nein   | Suche (min. 3 Zeichen) |

## Beispiel-Antwort

{
  "data": []
}

---

## Route
`GET /users/me`

## Typ
`GET`

## Beschreibung
Gibt den aktuell authentifizierten Nutzer zurück.

## Beispiel-Antwort

{
  "data": {
    "type": "users",
    "id": "123"
  }
}

---

## Route
`GET /users/{id}`

## Typ
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Nutzers |

## Beispiel-Antwort

{
  "data": {
    "type": "users",
    "id": "123"
  }
}

---

## Route
`DELETE /users/{id}`

## Typ
`DELETE`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Nutzers |

---

## Route
`GET /users/{id}/institute-memberships`

## Typ
`GET`

## Parameter

| Name | Typ    | Pflicht | Beschreibung |
|------|--------|--------|-------------|
| id   | string | ja     | ID des Nutzers |
---

# Ergaenzende Routen (Abgleich 2026-04-04)

## Route
`GET /jsonapi.php/v1/blubber-streams`

## Route
`GET /jsonapi.php/v1/blubber-threads/{id}/comments`

## Route
`GET /jsonapi.php/v1/comments`

## Route
`GET /jsonapi.php/v1/course-memberships`

## Route
`GET /jsonapi.php/v1/file-refs`

## Route
`GET /jsonapi.php/v1/folders`

## Route
`GET /jsonapi.php/v1/forum-categories`

## Route
`GET /jsonapi.php/v1/forum-entries`

## Route
`GET /jsonapi.php/v1/institutes`

## Route
`GET /jsonapi.php/v1/institutes/{id}`

## Route
`GET /jsonapi.php/v1/schedule-entries`

## Route
`GET /jsonapi.php/v1/seminar-cycle-dates`
