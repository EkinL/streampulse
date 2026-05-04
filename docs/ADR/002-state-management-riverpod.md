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
