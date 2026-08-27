#!/usr/bin/env bash
#
# Construit l'AppBundle iOS (.ipa) de StreamPulse, sans signature.
#
# `flutter build ipa --no-codesign` s'arrete a la .xcarchive et affiche
# "Codesigning disabled with --no-codesign, skipping IPA" : sans certificat,
# xcodebuild -exportArchive refuse d'exporter. On assemble donc le .ipa
# nous-memes a partir du .app de l'archive. Un .ipa n'est rien d'autre qu'un
# zip contenant Payload/<App>.app, c'est le format que le sujet attend comme
# livrable.
#
# CE .IPA N'EST PAS INSTALLABLE TEL QUEL sur un iPhone : il faut le re-signer
# avec un certificat de distribution. C'est un livrable d'archive, pas un
# binaire de distribution.
#
# Usage :
#   scripts/build_ipa.sh [args flutter supplementaires]
#   scripts/build_ipa.sh --dart-define-from-file=dart_define.json
#   SKIP_CLEAN=1 scripts/build_ipa.sh    # iteration rapide, build incremental
#
set -euo pipefail

MOBILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$MOBILE_DIR"

ARCHIVE="build/ios/archive/Runner.xcarchive"
APP="$ARCHIVE/Products/Applications/Runner.app"
OUT_DIR="build/ios/ipa"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mErreur:\033[0m %s\n' "$*" >&2; exit 1; }

command -v flutter >/dev/null || die "flutter introuvable dans le PATH."
command -v xcodebuild >/dev/null || die "xcodebuild introuvable : Xcode est requis pour construire un .ipa."

# Un livrable se construit a froid. Sans ca, l'etat incremental peut mentir :
# un `rm -rf build` qui laisse .dart_tool et le DerivedData Xcode desynchronises
# fait echouer l'archivage sur "native assets ... not found in
# build/native_assets/ios/" (paquet objective_c, tire par
# path_provider_foundation). SKIP_CLEAN=1 pour iterer sur le script lui-meme.
if [ "${SKIP_CLEAN:-0}" = "1" ]; then
  log "flutter clean saute (SKIP_CLEAN=1) — build incremental"
else
  log "flutter clean"
  flutter clean
fi

log "flutter pub get"
flutter pub get

# --release est implicite pour `build ipa`, on le laisse explicite pour que la
# commande soit lisible hors contexte.
log "flutter build ipa --release --no-codesign $*"
flutter build ipa --release --no-codesign "$@"

[ -d "$APP" ] || die "$APP introuvable : l'archive n'a pas ete produite."

# La version vient du binaire construit, pas de pubspec.yaml : c'est celle qui
# est reellement embarquee dans le livrable.
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP/Info.plist")"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
IPA="$OUT_DIR/StreamPulse-$VERSION+$BUILD.ipa"

log "Assemblage de $IPA"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/Payload"
cp -R "$APP" "$STAGING/Payload/"

mkdir -p "$OUT_DIR"
rm -f "$IPA"
# zip est lance depuis $STAGING pour que les chemins de l'archive commencent a
# Payload/, d'ou le chemin absolu de sortie.
IPA_ABS="$MOBILE_DIR/$IPA"
# -y preserve les liens symboliques des frameworks embarques ; sans lui,
# l'archive gonfle et les binaires sont dupliques.
( cd "$STAGING" && zip -qry "$IPA_ABS" Payload )

# --- Verification du livrable -------------------------------------------
[ -f "$IPA" ] || die "le .ipa n'a pas ete produit."

# Le listing est capture une fois puis relu : `unzip -l | grep -q` echouerait
# sous `set -o pipefail`, grep fermant le tube des la premiere correspondance
# et unzip mourant alors sur SIGPIPE (141).
LISTING="$(unzip -l "$IPA")"
for entry in "Payload/Runner.app/Info.plist" "Payload/Runner.app/Runner"; do
  case "$LISTING" in
    *"$entry"*) ;;
    *) die "$IPA ne contient pas $entry : structure invalide." ;;
  esac
done

SIZE="$(du -h "$IPA" | cut -f1)"
cat <<EOF

  IPA          $IPA
  Taille       $SIZE
  Bundle ID    $BUNDLE_ID
  Version      $VERSION ($BUILD)
  Archive      $ARCHIVE
  dSYMs        $ARCHIVE/dSYMs

  Non signe : a re-signer avec un certificat de distribution avant toute
  installation sur un appareil ou tout envoi a TestFlight.

EOF
