# ADR 005: PostgreSQL et pgx comme socle de persistance

## Statut
Accepted

## Contexte
StreamPulse persiste des utilisateurs, des flux, des musiques, des playlists
ordonnees et des favoris. Les besoins reels du modele :

- **Integrite referentielle** : supprimer un utilisateur doit emporter ses flux,
  ses playlists et ses favoris. Aucune reference orpheline tolerable.
- **Unicite** : un email par compte, un favori par couple (utilisateur, flux).
- **Ordre** : une playlist est une file d'attente, pas un ensemble. Reordonner
  doit etre atomique.
- **Recherche plein texte** sur titre, artiste et album.
- **Volumetrie modeste** : quelques milliers d'entites, tres loin du sharding.

Le flux audio lui-meme ne touche jamais la base : il transite par le Hub en
memoire (cf. [ADR 003](003-streaming-sse.md)). La base n'est donc **pas** sur le
chemin critique du streaming, ce qui retire la pression de latence qui aurait pu
orienter le choix.

## Decision

**PostgreSQL 16, accede via `pgx/v5` en direct, sans ORM.**

Migrations SQL versionnees dans `internal/infrastructure/postgres/migrations/`,
appliquees au demarrage.

## Justification

### Pourquoi PostgreSQL plutot que MongoDB
Le modele est **relationnel de part en part** : cinq tables, toutes reliees par
des cles etrangeres. Le representer en documents obligerait soit a denormaliser
(et a gerer la coherence a la main), soit a reproduire des jointures dans le
code applicatif.

Trois besoins seraient a reecrire cote applicatif avec un moteur documentaire :

- `ON DELETE CASCADE` sur `user_id`, qui garantit gratuitement l'absence de
  references orphelines ;
- les contraintes `UNIQUE` sur `users.email` et sur les tables de favoris, qui
  rendent le doublon impossible plutot que peu probable ;
- le reordonnancement d'une playlist, qui reecrit toutes les positions **dans
  une seule transaction**. Sans transaction, une interruption laisse la file
  dans un ordre incoherent.

### Pourquoi PostgreSQL plutot que MySQL ou SQLite
- **Contre SQLite** : un seul ecrivain a la fois. Or plusieurs diffuseurs et
  auditeurs ecrivent en parallele (favoris, compteurs, playlists). Et le fichier
  unique s'accorde mal avec un deploiement conteneurise.
- **Contre MySQL** : la recherche plein texte de PostgreSQL (`to_tsvector` +
  index GIN) est integree et suffisante ici. Elle evite d'ajouter Elasticsearch
  pour une fonctionnalite secondaire — un composant de plus a deployer,
  surveiller et synchroniser, pour quelques milliers de titres.
- `uuid-ossp` et `TIMESTAMPTZ` couvrent nativement des besoins qui demandent
  ailleurs des conventions applicatives.

### Pourquoi pgx en direct plutot que GORM ou ent
- **La Clean Architecture rend l'ORM redondant.** Le domaine ne connait que des
  interfaces de repository ([ADR 001](001-clean-architecture.md)) ; le mapping
  entre lignes et entites est deja explicite dans la couche infrastructure. Un
  ORM ajouterait une seconde couche de mapping par-dessus.
- **Le SQL reste lisible et audite.** Une requete de reordonnancement en
  transaction s'ecrit et se relit ; la meme chose derriere un ORM devient un
  comportement a deviner.
- **Anti-injection par construction.** `pgx` envoie des requetes parametrees au
  protocole PostgreSQL : la valeur n'est jamais concatenee dans le texte de la
  requete. Aucune concatenation d'entree utilisateur n'existe dans le code.
- **Performance** : `pgx` parle le protocole binaire natif, sans passer par
  `database/sql`, et fournit son propre pool (`pgxpool`).
- Le cout assume : chaque requete s'ecrit a la main. Sur cinq tables, c'est
  quelques centaines de lignes, largement compensees par la lisibilite.

### Pourquoi des migrations SQL et pas de l'auto-migration
L'auto-migration d'un ORM deduit le schema du code. Cela rend les changements
implicites, difficiles a relire en revue, et pratiquement impossibles a
annuler. Des fichiers `NNN_nom.up.sql` / `.down.sql` versionnes rendent chaque
evolution de schema explicite, revisable dans une PR, et reversible.

## Consequences

### Positif
- L'integrite des donnees est garantie par le moteur, pas par la discipline du
  code applicatif.
- L'injection SQL est structurellement traitee.
- La recherche plein texte fonctionne sans composant supplementaire.
- Le SQL etant ecrit a la main, `EXPLAIN` decrit exactement ce qui s'execute.
- Les migrations sont relisibles en revue de code.

### Negatif
- **Chaque repository doit etre teste contre une vraie base.** Un mock de `pgx`
  ne verifierait que le code de mapping, pas les contraintes, les cascades ni le
  comportement transactionnel — c'est-a-dire precisement ce pour quoi
  PostgreSQL a ete choisi. La couche `postgres` pese 462 instructions, soit
  21 % du backend : elle ne peut pas etre laissee de cote dans l'objectif de
  couverture.
- Ecrire les requetes a la main est repetitif et se prete aux fautes de frappe
  que l'on ne decouvre qu'a l'execution.
- Les migrations sont appliquees au demarrage du serveur. Simple, mais deux
  instances qui demarrent simultanement peuvent entrer en concurrence — a
  reprendre avant tout deploiement multi-replique.
- PostgreSQL est un service de plus a exploiter, sauvegarder et surveiller,
  la ou SQLite n'aurait ete qu'un fichier.

## Voir aussi
- [ADR 001 - Clean Architecture](001-clean-architecture.md) pour les interfaces
  de repository
- [ADR 003 - Streaming SSE](003-streaming-sse.md) : pourquoi la base n'est pas
  sur le chemin du flux audio

---

## Summary (English)

PostgreSQL 16, accessed directly through `pgx/v5` with no ORM, backs a
data model that is relational end to end — five tables linked by foreign
keys, needing cascading deletes, uniqueness constraints, atomic playlist
reordering (a single transaction rewriting every position), and full-text
search. MongoDB was rejected because the relational needs would have to be
reimplemented in application code; MySQL and SQLite were rejected for
concurrent-writer limits (SQLite) and for lacking PostgreSQL's built-in
full-text search (`to_tsvector` + GIN index), which avoids deploying
Elasticsearch for a few thousand titles. Skipping an ORM (GORM, ent) keeps
the mapping in one place — the infrastructure layer already required by
Clean Architecture — keeps SQL readable and auditable, and makes SQL
injection structurally impossible since `pgx` sends parameterized queries
at the protocol level, never string concatenation. Versioned `.up.sql`
/`.down.sql` migration files were chosen over ORM auto-migration to keep
every schema change explicit, reviewable, and reversible. The accepted
cost: every repository must be tested against a real database (a `pgx`
mock couldn't verify constraints, cascades, or transactional behavior —
exactly what PostgreSQL was chosen for), hand-written queries are
repetitive, and migrations running at server startup could race if two
instances start simultaneously — a gap to close before any multi-replica
deployment.
