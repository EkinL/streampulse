#!/usr/bin/env bash
#
# Seuil de couverture de l'app Flutter, identique en CI et en local.
#
# Lit coverage/lcov.info produit par `flutter test --coverage` et calcule la
# couverture de lignes (LH / LF sur tous les fichiers). Echoue si elle est
# sous COVERAGE_MIN (15 % aujourd'hui, a relever avec les tests du lecteur
# et de l'ecran diffuseur).
#
# Usage :
#   flutter test --coverage && scripts/coverage_check.sh
#   COVERAGE_MIN=20 scripts/coverage_check.sh
#
set -euo pipefail

MOBILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LCOV="$MOBILE_DIR/coverage/lcov.info"
COVERAGE_MIN="${COVERAGE_MIN:-15}"

if [ ! -f "$LCOV" ]; then
  echo "coverage/lcov.info introuvable : lancer d'abord \`flutter test --coverage\`" >&2
  exit 1
fi

total=$(awk -F: '/^LF:/ { lf += $2 } /^LH:/ { lh += $2 } END { printf "%.1f", (lf ? 100 * lh / lf : 0) }' "$LCOV")
echo "couverture totale : ${total} % (minimum ${COVERAGE_MIN} %)"

# Visible dans le resume du job GitHub Actions, sans ouvrir les logs.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "Couverture mobile : **${total} %** (minimum ${COVERAGE_MIN} %)" >> "$GITHUB_STEP_SUMMARY"
fi

awk -v t="$total" -v m="$COVERAGE_MIN" 'BEGIN { exit (t + 0 < m + 0) ? 1 : 0 }'
