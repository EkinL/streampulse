# Connexion sociale (Google & Apple)

L'app mobile propose « Se connecter avec Google » et « Sign in with Apple »
sur l'ecran de connexion. Le flux est le suivant :

1. L'app obtient un **ID token** aupres du SDK du fournisseur, sur l'appareil
   (`mobile/lib/features/auth/data/social_auth_service.dart`).
2. Elle l'envoie a **`POST /auth/oauth`** avec `{"provider": "google"|"apple",
   "id_token": "..."}`.
3. Le backend verifie le token — signature contre le **JWKS public** du
   fournisseur, emetteur, audience, expiration
   (`backend/internal/infrastructure/auth/oidc_verifier.go`) — puis ouvre une
   session avec la meme paire access/refresh que le login classique.

Au premier passage le compte est cree avec le role `user`. Si un compte
existant porte le meme email **verifie par le fournisseur**, l'identite
sociale y est reliee (colonnes `auth_provider` / `provider_subject`,
migration 007). Un compte social n'a pas de mot de passe : le login
email + mot de passe reste ferme pour lui.

Aucun secret n'est necessaire cote serveur : la verification n'utilise que
les cles publiques des fournisseurs. Il n'y a que des **client IDs** (non
secrets) a configurer.

## Configuration backend

Dans l'environnement de l'API (voir `backend/.env.example` et
`docker-compose.yml`) :

| Variable | Contenu |
|----------|---------|
| `GOOGLE_OAUTH_CLIENT_IDS` | Client IDs Google acceptes comme audience, separes par des virgules : le client **web** (Android passe par lui) **et** le client **iOS** |
| `APPLE_OAUTH_CLIENT_IDS` | `dev.streampulse.app` (bundle id de l'app) et, si un jour la console web propose Apple, le Service ID |

Variable vide = fournisseur desactive : `POST /auth/oauth` repond `503` pour
lui. C'est l'etat par defaut de la stack de dev.

## Cote Google (console Google Cloud)

1. Creer un projet puis, dans « APIs & Services → Credentials », creer :
   - un **OAuth client ID « Web application »** (le `serverClientId`) ;
   - un **OAuth client ID « iOS »** avec le bundle id `dev.streampulse.app` ;
   - un **OAuth client ID « Android »** avec le package `dev.streampulse.app`
     et l'empreinte SHA-1 de la cle de signature (debug et release).
2. Renseigner `GOOGLE_OAUTH_CLIENT_IDS` avec le client web **et** le client
   iOS.
3. Compiler l'app avec :
   ```sh
   flutter run --dart-define=GOOGLE_CLIENT_ID=<client iOS> \
               --dart-define=GOOGLE_SERVER_CLIENT_ID=<client web>
   ```
4. iOS : dans `mobile/ios/Runner/Info.plist`, remplacer
   `com.googleusercontent.apps.REPLACE-WITH-IOS-CLIENT-ID` par le **client ID
   iOS inverse** (valeur « iOS URL scheme » affichee par la console Google).

Sans ces defines, le bouton Google affiche « Connexion Google non
configuree » : rien ne casse pour le reste de l'app.

## Cote Apple (portail Apple Developer)

1. Sur l'App ID `dev.streampulse.app`, activer la capability
   **Sign in with Apple** (compte payant requis).
2. L'entitlement est deja en place :
   `mobile/ios/Runner/Runner.entitlements`, reference par
   `CODE_SIGN_ENTITLEMENTS` dans le projet Xcode.
3. Renseigner `APPLE_OAUTH_CLIENT_IDS=dev.streampulse.app` cote backend.

Sign in with Apple ne fonctionne que sur iOS/macOS ; sur Android le bouton
affiche une erreur claire.

## Securite

- L'ID token est verifie **cote serveur** : signature RS256 contre le JWKS du
  fournisseur (cache 1 h), `iss`, `aud` (liste des client IDs configures),
  `exp`. Un token forge, expire ou emis pour une autre app repond `401`.
- La reliaison par email n'a lieu que si `email_verified` est vrai : sinon un
  compte Google cree avec l'email d'autrui permettrait de prendre la main sur
  le compte StreamPulse correspondant (`409` dans ce cas).
- L'identite est ancree sur la claim `sub` (stable), pas sur l'email : les
  relais prives Apple ou un changement d'adresse ne cassent pas le compte.
