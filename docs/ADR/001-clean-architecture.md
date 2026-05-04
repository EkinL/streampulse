# ADR 001: Clean Architecture + DDD pour le Backend Go

## Statut
Accepted

## Contexte
StreamPulse est une plateforme de streaming audio avec plusieurs domaines metier (authentification, streaming, playlists). Le backend doit etre testable, maintenable et evolutif.

## Decision
Adopter une architecture Clean Architecture avec des elements de Domain-Driven Design :

- **Domain** : Entites pures, interfaces de repositories, erreurs metier. Zero dependance externe.
- **Application** : Use cases / services metier. Depend uniquement du Domain.
- **Infrastructure** : Implementations concretes (PostgreSQL, JWT, OTEL). Depend du Domain.
- **Transport** : Handlers HTTP, DTOs, middlewares. Depend de Application.

L'injection de dependances est faite manuellement dans `main.go`.

## Consequences

### Positif
- Testabilite elevee : chaque couche testable independamment avec des mocks
- Separation claire des responsabilites
- Le domaine metier est isole des details d'implementation
- Changement de base de donnees ou de framework HTTP sans impact sur le metier

### Negatif
- Plus de fichiers et de boilerplate qu'une architecture simple
- Courbe d'apprentissage pour les nouveaux developpeurs
- La conversion entre DTOs et entites domain ajoute du code

## Alternatives considerees
- **Architecture en couches simple** : Plus rapide a demarrer mais couplage fort
- **Hexagonal Architecture** : Tres similaire, Clean Architecture est plus repandue dans l'ecosysteme Go
