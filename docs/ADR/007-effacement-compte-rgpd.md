# ADR 007: Effacement physique en cascade pour la suppression de compte

## Statut
Accepted

## Contexte
Le RGPD (art. 17) impose de pouvoir effacer les donnees d'une personne qui le
demande, et le critere Ce3.1.4 du bloc 3 exige que cette contrainte soit
respectee et demontrable. Le projet n'offrait aucune suppression de compte :
la seule issue etait un `DELETE` a la main dans PostgreSQL.

Trois approches etaient possibles :

1. **Effacement physique** : `DELETE FROM users`, les tables liees suivent
   par `ON DELETE CASCADE`.
2. **Suppression logique** : colonne `deleted_at`, les lignes restent mais
   sont filtrees partout.
3. **Anonymisation** : conserver les contenus (flux, morceaux) en remplacant
   l'email et le nom par des valeurs neutres.

## Decision

**Effacement physique en cascade, immediat, expose par `DELETE /users/me`
(la personne) et `DELETE /admin/users/{id}` (un administrateur pour elle).**

- Le schema declarait deja `ON DELETE CASCADE` de chaque table vers
  `users(id)` (migrations 001 a 005) : une seule requete efface tout, sans
  liste de tables a maintenir. `TestCascadeOnUserDelete` et
  `TestUsers_AccessAndErasure` verifient qu'il ne reste rien.
- Le jeton d'acces en cours n'est pas revoque (il est sans etat, ADR 006) mais
  ne designe plus rien : `GET /users/me` repond 404 et le refresh token est
  parti avec le compte. Sa duree de vie residuelle est de 15 minutes au plus.
- L'email est libere tout de suite : une nouvelle inscription avec la meme
  adresse est possible.
- Les refresh tokens expires sont purges periodiquement
  (`REFRESH_TOKEN_PURGE_INTERVAL`) pour que la politique de retention de
  [rgpd.md](../rgpd.md) soit tenue sans intervention.

## Alternatives ecartees

- **Suppression logique** : chaque requete de lecture doit filtrer
  `deleted_at IS NULL`, un oubli reexpose des donnees censees avoir disparu ;
  et les donnees restent en base, ce qui n'est pas un effacement au sens du
  RGPD sans une purge differee supplementaire.
- **Anonymisation** : garderait les flux et morceaux d'un diffuseur parti,
  mais un flux sans diffuseur ne peut plus etre demarre, et les playlists et
  favoris n'ont de sens que pour leur proprietaire. Le gain ne justifiait pas
  la complexite (deux etats de compte a gerer dans l'API et les clients).

## Consequences

- Positif : implementation minimale (une methode de repository, un service,
  deux handlers), comportement demontrable par les tests, aucune donnee
  residuelle en base.
- Negatif : irreversible et immediat. Un delai de grace (compte desactive
  puis purge a J+30) reste possible plus tard en ajoutant `deleted_at` et une
  tache de purge, sans changer le contrat REST.
- Les fichiers audio deposes dans `uploads/` ne sont pas supprimes (meme
  limite que `DELETE /music/{id}`) : ils ne contiennent pas de donnees
  personnelles, un nettoyage des orphelins est a prevoir.
