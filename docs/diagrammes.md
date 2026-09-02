# Diagrammes UML et BPMN

Ce document rassemble les diagrammes standardises decrivant StreamPulse :
cas d'usage, classes du domaine, sequences, etats, processus metier (BPMN)
et composants techniques. Il repond au critere **Ce3.6.1** du bloc 3
(RNCP 38822), qui exige un langage de visualisation standardise (UML,
BPMN) en complement des [user stories](user-stories.md), du
[schema de base de donnees](base-de-donnees.md) et du
[schema de securite](securite.md). Une synthese en anglais figure en fin
de document.

Tous les diagrammes sont ecrits en [Mermaid](https://mermaid.js.org/), qui
s'affiche nativement sur GitHub sans outil externe. Mermaid n'a pas de
rendu natif pour les notations UML "cas d'usage" ou BPMN avec couloirs :
ces deux diagrammes sont donc approximes avec `flowchart` (acteurs et
sous-graphes en guise de couloirs), en restant fideles a la semantique
(acteurs, activites, decisions, evenements). Les diagrammes de classes,
sequence et etats utilisent en revanche la syntaxe UML native de Mermaid.

## Sommaire

1. [Cas d'usage](#1-cas-dusage)
2. [Classes du domaine](#2-classes-du-domaine)
3. [Sequence — inscription, connexion, rafraichissement](#3-sequence--inscription-connexion-rafraichissement)
4. [Sequence — ecoute d'un flux en direct (SSE)](#4-sequence--ecoute-dun-flux-en-direct-sse)
5. [Etats d'un flux](#5-etats-dun-flux)
6. [BPMN — cycle de vie d'une diffusion](#6-bpmn--cycle-de-vie-dune-diffusion)
7. [BPMN — effacement de compte (RGPD)](#7-bpmn--effacement-de-compte-rgpd)
8. [Composants et deploiement](#8-composants-et-deploiement)

---

## 1. Cas d'usage

Vue synthetique des interactions entre les trois roles et le systeme, plus
le visiteur qui n'a pas encore de compte. **L'application n'offre aucune
consultation sans compte** : `mobile/lib/app/router.dart` redirige toute
route non authentifiee vers l'ecran de connexion, seuls l'inscription et la
connexion sont atteignables avant d'avoir un compte. Chaque role herite
ensuite des cas d'usage du role precedent (`user` < `broadcaster` <
`admin`, [ADR 006](ADR/006-strategie-auth-jwt.md)) ; seuls les cas propres
a chaque role sont rattaches a lui pour la lisibilite.

> **Nuance API.** Le contrat REST expose reellement `GET /streams`,
> `GET /music` et `GET /search` sans jeton ([securite.md](securite.md#4-authentification-et-autorisation)) :
> un client tiers integre directement a l'API pourrait donc parcourir ces
> listes sans compte. Aucun ecran de l'application livree n'emprunte ce
> chemin — ce diagramme decrit le produit tel qu'on l'utilise, pas les
> capacites brutes de l'API.

```mermaid
flowchart LR
    Visitor(("Visiteur\n(sans compte)"))
    User(("Utilisateur"))
    Bcast(("Diffuseur"))
    Admin(("Administrateur"))

    subgraph SYS["StreamPulse"]
        UC1["S'inscrire"]
        UC2["Se connecter"]
        UC3["Parcourir flux et playlists publiques"]
        UC4["Ecouter un flux en direct"]
        UC5["Rechercher"]
        UC6["Gerer ses favoris"]
        UC7["Gerer ses playlists"]
        UC8["Gerer son compte (RGPD)"]
        UC9["Creer / demarrer / arreter un flux"]
        UC10["Diffuser de l'audio"]
        UC11["Deposer un morceau"]
        UC12["Gerer les comptes et roles"]
        UC13["Superviser (metriques, dashboards)"]
        UC14["Supprimer un compte sur demande"]
    end

    Visitor --> UC1
    Visitor --> UC2

    User --> UC3
    User --> UC4
    User --> UC5
    User --> UC6
    User --> UC7
    User --> UC8

    Bcast --> UC9
    Bcast --> UC10
    Bcast --> UC11

    Admin --> UC12
    Admin --> UC13
    Admin --> UC14

    UC10 -. "necessite" .-> UC9
    UC4 -. "cible" .-> UC9
```

Traçabilite vers les [user stories](user-stories.md) : `UC1-UC2` → US-01,
US-02 ; `UC3-UC4` → US-06, US-07 ; `UC5-UC8` → US-07 a US-09, US-04, US-05 ;
`UC9-UC11` → US-10, US-11 ; `UC12-UC14` → US-12 a US-14.

---

## 2. Classes du domaine

Modele des entites metier telles que definies dans `backend/internal/domain/`
(clean architecture, [ADR 001](ADR/001-clean-architecture.md)) : zero
dependance externe, uniquement des structures et des regles. Ce diagramme
est le pendant objet du [modele de donnees](base-de-donnees.md) ; il porte
les comportements (validite d'un role, d'un statut) que le schema
relationnel ne peut pas exprimer.

```mermaid
classDiagram
    class User {
        +UUID ID
        +string Email
        +string Username
        -string PasswordHash
        +Role Role
        +time TermsAcceptedAt
        +time CreatedAt
        +time UpdatedAt
    }

    class Role {
        <<enumeration>>
        anonymous
        user
        broadcaster
        admin
        +AtLeast(min) bool
    }

    class Stream {
        +UUID ID
        +string Title
        +string Description
        +UUID OwnerID
        +StreamStatus Status
        +int ListenerCount
        +string Format
        +time CreatedAt
        +time UpdatedAt
    }

    class StreamStatus {
        <<enumeration>>
        idle
        live
        ended
    }

    class Playlist {
        +UUID ID
        +string Name
        +UUID OwnerID
        +bool IsPublic
        +Track[] Tracks
        +int TrackCount
        +time CreatedAt
        +time UpdatedAt
    }

    class Track {
        +UUID ID
        +string Title
        +string URL
        +int Duration
        +int Position
    }

    class Music {
        +UUID ID
        +string Title
        +string Artist
        +string Album
        +int Duration
        +string URL
        +string CoverURL
        +UUID UploadedBy
        +time CreatedAt
    }

    class RefreshToken {
        +UUID ID
        +UUID UserID
        -string TokenHash
        +time ExpiresAt
        +time CreatedAt
    }

    User "1" --> "0..*" Stream : possede (owner)
    User "1" --> "0..*" Playlist : possede (owner)
    User "1" --> "0..*" Music : depose (uploaded_by)
    User "1" --> "0..*" RefreshToken : detient
    User "0..*" -- "0..*" Stream : favoris
    User "0..*" -- "0..*" Music : favoris
    Playlist "1" *-- "0..*" Track : contient (ordonne)
    Track "0..1" --> "0..1" Music : reference
    User --> Role
    Stream --> StreamStatus
```

---

## 3. Sequence — inscription, connexion, rafraichissement

Flux d'authentification complet, cote sans etat serveur
([ADR 006](ADR/006-strategie-auth-jwt.md)) : le jeton d'acces porte les
claims, le refresh token est opaque et stocke hache.

```mermaid
sequenceDiagram
    actor C as Client (mobile / web)
    participant API as API Go (chi)
    participant AS as AuthService
    participant DB as PostgreSQL

    Note over C,DB: Inscription
    C->>API: POST /auth/register
    API->>AS: Register(email, username, password, acceptedTerms)
    AS->>AS: bcrypt.GenerateFromPassword (cout 12)
    AS->>DB: INSERT INTO users (...)
    AS->>AS: GenerateTokenPair (JWT 15 min + refresh UUID v4)
    AS->>DB: INSERT INTO refresh_tokens (SHA-256(refresh))
    AS-->>API: AuthResult
    API-->>C: 201 {accessToken, refreshToken, user}

    Note over C,DB: Connexion
    C->>API: POST /auth/login
    API->>AS: Login(email, password)
    AS->>DB: SELECT * FROM users WHERE email = ?
    AS->>AS: bcrypt.CompareHashAndPassword
    AS->>DB: DELETE FROM refresh_tokens WHERE user_id = ? (revocation)
    AS->>AS: GenerateTokenPair
    AS->>DB: INSERT INTO refresh_tokens
    AS-->>API: AuthResult
    API-->>C: 200 {accessToken, refreshToken, user}

    Note over C,DB: Requete authentifiee
    C->>API: GET /users/me (Authorization: Bearer <JWT>)
    API->>API: AuthMiddleware.Authenticate : verifie la signature HS256
    API-->>C: 200 (ou 401 si invalide/expire)

    Note over C,DB: Rafraichissement (toutes les 15 min)
    C->>API: POST /auth/refresh {refreshToken}
    API->>AS: RefreshToken(refreshToken)
    AS->>DB: SELECT user_id FROM refresh_tokens WHERE token_hash = SHA-256(...)
    AS->>DB: DELETE FROM refresh_tokens WHERE user_id = ? (rotation)
    AS->>AS: GenerateTokenPair
    AS->>DB: INSERT INTO refresh_tokens (nouveau hash)
    AS-->>API: AuthResult
    API-->>C: 200 {accessToken, refreshToken}
```

---

## 4. Sequence — ecoute d'un flux en direct (SSE)

Diffusion en fan-out via le `Hub` en memoire ([ADR 003](ADR/003-streaming-sse.md)).
Le serveur reste sans etat partage : chaque instance API porte son propre
`Hub`, ce qui borne la scalabilite horizontale a une repartition par flux
(documente dans [scalability.md](scalability.md)).

```mermaid
sequenceDiagram
    actor B as Diffuseur
    actor L as Auditeur
    participant API as API Go
    participant Hub as Hub (fan-out, memoire)

    B->>API: POST /streams/{id}/start
    API->>API: verifie owner_id == claims.user_id
    API-->>B: 200 (status = live)

    L->>API: GET /streams/{id}/listen (SSE)
    API->>API: verifie status == live (sinon STREAM_NOT_LIVE)
    API->>Hub: Register(streamID, client)
    Hub-->>API: OnListenerChange(streamID, +1)
    API-->>L: 200 text/event-stream (connexion ouverte)

    loop tant que le flux est live
        B->>API: POST /streams/{id}/broadcast (chunk audio)
        API->>Hub: Broadcast(streamID, chunk)
        Hub->>L: chunk (evenement SSE)
    end

    alt l'auditeur se deconnecte
        L--xAPI: fermeture de connexion
        API->>Hub: Unregister(streamID, client)
        Hub-->>API: OnListenerChange(streamID, -1)
    end

    B->>API: POST /streams/{id}/stop
    API->>Hub: CloseStream(streamID)
    Hub->>L: fermeture de tous les clients restants
    API-->>B: 200 (status = ended)
```

---

## 5. Etats d'un flux

Cycle de vie de `Stream.Status`, dont les transitions valides sont
imposees par `application/stream_service.go` (pas de retour arriere depuis
`ended`).

```mermaid
stateDiagram-v2
    [*] --> idle : POST /streams (creation)
    idle --> live : POST /streams/{id}/start (owner)
    live --> ended : POST /streams/{id}/stop (owner)
    idle --> ended : POST /streams/{id}/stop (annulation sans diffusion)
    ended --> [*]

    live --> live : POST /streams/{id}/broadcast (chunk)\nGET /streams/{id}/listen (nouvel auditeur)

    note right of live
        listener_count varie en direct
        (Hub.OnListenerChange),
        independamment du statut
    end note
```

---

## 6. BPMN — cycle de vie d'une diffusion

Processus metier de bout en bout, du point de vue du diffuseur et des
auditeurs. Represente en couloirs (`subgraph`) faute de support BPMN natif
dans Mermaid ; les losanges figurent les portes de decision (gateways), les
rectangles arrondis les evenements de debut/fin.

```mermaid
flowchart TB
    subgraph SwimBcast["Diffuseur"]
        direction TB
        A1(["Debut : veut diffuser"]) --> A2["Creer un flux\nPOST /streams"]
        A2 --> A3["Deposer / referencer\nune source audio"]
        A3 --> A4["Demarrer le flux\nPOST /streams/{id}/start"]
        A4 --> A5["Diffuser des chunks\nPOST /streams/{id}/broadcast"]
        A5 --> A6{Fin de la\ndiffusion ?}
        A6 -- non --> A5
        A6 -- oui --> A7["Arreter le flux\nPOST /streams/{id}/stop"]
        A7 --> A8(["Fin"])
    end

    subgraph SwimSys["Systeme (API + Hub)"]
        direction TB
        S1["status = idle"] --> S2["status = live"]
        S2 --> S3["relayer chaque chunk\naux auditeurs connectes"]
        S3 --> S4{Nouvel\nauditeur ?}
        S4 -- oui --> S5["Hub.Register\nlistener_count++"]
        S5 --> S3
        S4 -- non --> S3
        S3 --> S6["status = ended\nfermer les connexions SSE"]
    end

    subgraph SwimListener["Auditeur"]
        direction TB
        L1(["Debut : veut ecouter"]) --> L2{Flux\nlive ?}
        L2 -- non --> L3(["Erreur STREAM_NOT_LIVE"])
        L2 -- oui --> L4["Se connecter\nGET /streams/{id}/listen"]
        L4 --> L5["Recevoir les chunks"]
        L5 --> L6{Se\ndeconnecte ?}
        L6 -- non --> L5
        L6 -- oui --> L7(["Fin, listener_count--"])
    end

    A2 -.-> S1
    A4 -.-> S2
    A5 -.-> S3
    A7 -.-> S6
    L4 -.-> S4
    S6 -.-> L7
```

---

## 7. BPMN — effacement de compte (RGPD)

Processus d'exercice du droit a l'effacement (art. 17 RGPD), initie par la
personne elle-meme ou par un administrateur en son nom
([ADR 007](ADR/007-effacement-compte-rgpd.md)).

```mermaid
flowchart TB
    Debut(["Demande d'effacement"]) --> Who{Qui\ndemande ?}

    Who -- "la personne, dans l'app" --> Self["DELETE /users/me\n(authentifie par son propre jeton)"]
    Who -- "hors application" --> Admin["Un administrateur recoit\nla demande"]
    Admin --> AdminCall["DELETE /admin/users/{id}"]

    Self --> Verify["Verifier l'authentification\n(RBAC : role >= user, proprietaire)"]
    AdminCall --> Verify2["Verifier le role\n(RBAC : admin uniquement)"]

    Verify --> Cascade
    Verify2 --> Cascade

    Cascade["Effacement physique en cascade :\nDELETE FROM users WHERE id = ?\n(ON DELETE CASCADE sur 6 tables)"]
    Cascade --> Files["Supprimer les fichiers audio\nassocies dans uploads/"]
    Files --> Free["Liberer l'email pour\nune future inscription"]
    Free --> Fin(["Effacement termine\n(irreversible, immediat)"])

    Cascade -. "les jetons deja emis" .-> Residual["Jeton d'acces : reste valide\ncryptographiquement 15 min max,\nmais ne designe plus de compte -> 404"]
```

---

## 8. Composants et deploiement

Vue des conteneurs et de leurs communications, en production
(`docker-compose.prod.yml`, `caddy/Caddyfile`). Le detail des zones de
confiance et des controles de securite associes est dans
[securite.md](securite.md#2-cartographie-des-flux-et-zones-de-confiance).

```mermaid
flowchart TB
    subgraph Client["Clients"]
        Mobile["App Flutter\n(iOS / Android)"]
        Web["Console web\n(admin / diffuseur)"]
    end

    Internet(["Internet"])

    subgraph Infra["Infrastructure (reseau Docker interne)"]
        Caddy["Caddy\nreverse proxy, TLS"]
        API["API Go (chi)\nclean architecture"]
        Hub["Hub de streaming\n(fan-out, memoire)"]
        PG[("PostgreSQL 16")]
        OTEL["OTEL Collector"]
        Prom["Prometheus"]
        Graf["Grafana"]
    end

    Mobile -->|HTTPS| Internet
    Web -->|HTTPS| Internet
    Internet --> Caddy
    Caddy -->|reverse_proxy :8080| API
    API <--> Hub
    API -->|SQL parametre, TLS optionnel| PG
    API -->|OTLP gRPC| OTEL
    OTEL --> Prom
    Prom --> Graf
    API -.->|/metrics, role admin| Prom

    style PG fill:#00000000,stroke-width:2px
```

---

## Summary (English)

This document collects the standardised diagrams describing StreamPulse in
Mermaid syntax, satisfying criterion **Ce3.6.1** alongside
[user-stories.md](user-stories.md), [base-de-donnees.md](base-de-donnees.md)
and [securite.md](securite.md): a use-case overview per role, a UML class
diagram of the domain model, two UML sequence diagrams (auth flow, live
listening over SSE), a UML state diagram for a stream's lifecycle, two
BPMN-style process diagrams (broadcast lifecycle, GDPR account erasure —
drawn as swimlane flowcharts since Mermaid has no native BPMN renderer),
and a component/deployment diagram matching the production Docker Compose
topology (Caddy TLS termination, the Go API, the in-memory fan-out Hub,
PostgreSQL, and the OpenTelemetry/Prometheus/Grafana observability stack).
