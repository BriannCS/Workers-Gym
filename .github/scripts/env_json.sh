#!/usr/bin/env bash
# Hecho por Briann$ Workers Corp.
# Crea env.json (ignorado por git) a partir de los secretos del repositorio.
set -euo pipefail

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]; then
  echo "::error::Faltan los secretos SUPABASE_URL y/o SUPABASE_PUBLISHABLE_KEY (Settings > Secrets and variables > Actions)."
  exit 1
fi

jq -n \
  --arg url "$SUPABASE_URL" \
  --arg key "$SUPABASE_PUBLISHABLE_KEY" \
  '{SUPABASE_URL: $url, SUPABASE_PUBLISHABLE_KEY: $key, GYM_NAME: "Workers Gym"}' > env.json
