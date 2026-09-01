# ADR 002: Riverpod pour le State Management Flutter

## Statut
Accepted

## Contexte
L'app Flutter necessite un state management robuste pour gerer l'authentification, la liste des streams en temps reel, les playlists et les favoris.

## Decision
Utiliser **flutter_riverpod** comme solution de state management.

## Justification

### Pourquoi Riverpod plutot que Bloc
- **Moins de boilerplate** : Pas besoin de creer Event/State/Bloc pour chaque fonctionnalite
- **Testabilite native** : Les providers sont facilement overridables dans les tests
- **Gestion async native** : AsyncValue integre gere loading/error/data sans code supplementaire
- **Compile-time safety** : Detection des erreurs a la compilation plutot qu'au runtime
- **Pas de BuildContext** : Les providers sont accessibles sans context, ideal pour la logique metier

### Pourquoi pas Provider (package)
- Provider est le predecesseur de Riverpod avec des limitations connues
- Riverpod resout les problemes de Provider (ProviderNotFoundException, dependances circulaires)

## Consequences

### Positif
- Code concis et lisible
- Tests unitaires simples avec ProviderContainer
- Performance optimale (rebuild granulaire)

### Negatif
- Syntaxe specifique a apprendre
- Moins de ressources communautaires que Bloc
- La generation de code (riverpod_generator) ajoute une etape de build

---

## Summary (English)

The Flutter app uses **flutter_riverpod** for state management (auth,
real-time stream list, playlists, favorites), chosen over Bloc for less
boilerplate (no Event/State/Bloc triad per feature), natively overridable
providers for testing, built-in async handling via `AsyncValue`,
compile-time safety, and no `BuildContext` dependency for business logic.
It was also chosen over the legacy `provider` package, which Riverpod
succeeds and whose known issues (`ProviderNotFoundException`, circular
dependencies) it resolves. The trade-off: a Riverpod-specific syntax to
learn, a smaller community than Bloc's, and an extra build step for code
generation (`riverpod_generator`) — offset by concise, unit-testable code
(via `ProviderContainer`) and granular rebuild performance.
