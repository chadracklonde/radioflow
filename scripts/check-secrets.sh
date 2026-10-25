#!/usr/bin/env bash
# Garde-fou simple : refuse un commit qui contiendrait un secret courant.
# (La clé « publishable » de Supabase est publique par conception et est autorisée.)
set -euo pipefail
cd "$(dirname "$0")/.."

pattern='sb_secret_|service_role_key\s*[:=]\s*["'"'"'][A-Za-z0-9._-]{20,}|eyJhbGciOi[A-Za-z0-9._-]{30,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|21st_sk_[A-Za-z0-9]{16,}'

# Le script ne s'analyse pas lui-même (ses motifs contiennent les mots recherchés).
if git ls-files -z -- . ':!scripts/check-secrets.sh' | xargs -0 grep -IEn -- "$pattern" 2>/dev/null; then
  echo "ECHEC : un secret semble présent dans les fichiers versionnés (voir ci-dessus)." >&2
  exit 1
fi
echo "Aucun secret détecté."
