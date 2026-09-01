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
- ~~Les fichiers audio deposes dans `uploads/` ne sont pas supprimes (meme
  limite que `DELETE /music/{id}`)~~. Resolu : `DELETE /music/{id}` et la
  suppression de compte effacent desormais aussi le fichier sous-jacent
  dans `uploads/` (`FileStore.DeleteFile`), pas seulement la ligne en base
  ([rgpd.md](../rgpd.md#6-limites-connues-et-suite)).

---

## Summary (English)

Account deletion is **immediate, physical, and cascading**: `DELETE
/users/me` (self-service) or `DELETE /admin/users/{id}` (admin, on behalf
of someone else) removes the row from `users`, and `ON DELETE CASCADE` —
already declared on every foreign key back to `users(id)` since migrations
001-005 — takes every related row (refresh tokens, streams, playlists,
tracks, favorites, uploaded music) with it in one statement, verified by
`TestCascadeOnUserDelete` and `TestUsers_AccessAndErasure`. A still-valid
access token survives cryptographically for up to 15 minutes but no
longer resolves to an account (`GET /users/me` returns 404), the refresh
token is gone with the account, and the email address is immediately
reusable. Soft deletion was rejected because every read path would have
to remember to filter `deleted_at IS NULL` — one omission re-exposes
supposedly erased data — and anonymization was rejected because an
orphaned stream can no longer start and an orphaned playlist has no owner
to make sense for, so the added complexity of two account states wasn't
worth it. The accepted trade-off is that erasure is irreversible with no
grace period — deferred until the project has a way to email the affected
person, since a silent grace period would just be a bug waiting to
surprise someone.
