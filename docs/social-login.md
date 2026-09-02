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

---

## Summary (English)

The mobile login screen offers "Sign in with Google" and "Sign in with
Apple". The app obtains an **ID token** from the provider's SDK on the
device (`mobile/lib/features/auth/data/social_auth_service.dart`) and posts
it to **`POST /auth/oauth`** as `{"provider": "google"|"apple",
"id_token": "..."}`. The backend verifies that token itself —
RS256 signature against the provider's public **JWKS** (cached one hour),
plus issuer, audience and expiry
(`backend/internal/infrastructure/auth/oidc_verifier.go`) — and then opens
a session with the same access/refresh pair as a password login. A forged,
expired, or another-app token gets `401`.

On first sign-in the account is created with the `user` role. When an
existing account carries the same email **and the provider marked it
verified**, the social identity is linked to it (`auth_provider` /
`provider_subject` columns, migration 007); an unverified email yields
`409` instead, because otherwise anyone could create a Google account with
someone else's address and take over the matching StreamPulse account.
Identity is anchored on the stable `sub` claim rather than the email, so
Apple's private relay addresses or an address change never break an
account. A social account has no password, so email-and-password login
stays closed for it.

**No server-side secret is involved**: verification only needs the
providers' public keys, so the configuration is limited to (non-secret)
client IDs — `GOOGLE_OAUTH_CLIENT_IDS` must list the **web** client (which
Android goes through) *and* the **iOS** client, while
`APPLE_OAUTH_CLIENT_IDS` holds the `dev.streampulse.app` bundle id, plus a
Service ID if the web console ever offers Apple. An empty variable disables
that provider and `POST /auth/oauth` answers `503` for it, which is the
default state of the development stack. On the Google side the setup means
three OAuth client IDs in Google Cloud (Web, iOS, and Android with the
signing SHA-1), the `GOOGLE_CLIENT_ID` / `GOOGLE_SERVER_CLIENT_ID`
dart-defines at build time, and the reversed iOS client ID as a URL scheme
in `Info.plist`; without those defines the button simply reports that
Google sign-in is not configured and nothing else breaks. On the Apple side
it means enabling the Sign in with Apple capability on the App ID (a paid
developer account is required) — the entitlement file is already committed
and wired through `CODE_SIGN_ENTITLEMENTS`. Sign in with Apple only works
on iOS and macOS; on Android the button shows an explicit error.
