#!/usr/bin/env bash
# Applique les migrations dans l'ordre sur un PostgreSQL jetable, puis lance les tests de sécurité.
# Utilise les variables PGHOST / PGPORT / PGUSER / PGPASSWORD / PGDATABASE habituelles.
# Le moindre échec (migration ou attente non satisfaite) fait sortir en erreur.
set -euo pipefail
cd "$(dirname "$0")/.."

psql -v ON_ERROR_STOP=1 -q -f tests/stub.sql
for migration in $(ls migrations/*.sql | sort); do
  echo "migration : $migration"
  psql -v ON_ERROR_STOP=1 -q -f "$migration"
done
psql -v ON_ERROR_STOP=1 -f tests/security.sql
