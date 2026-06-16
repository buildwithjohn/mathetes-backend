#!/usr/bin/env bash
# Generate the canonical TypeScript types and propagate to mobile + admin.
#
# Canonical output: types/database.types.ts (the single source of truth that
# mobile and admin consume).
#
# Preferred (authoritative) generators, in order:
#   1. Against the cloud project (no Docker; needs `supabase login`):
#        SUPABASE_PROJECT_ID=<ref> ./scripts/generate-types.sh
#   2. Against a local stack (`supabase start`, needs Docker):
#        ./scripts/generate-types.sh
#
# If neither the Supabase CLI nor Docker is available, the file can be produced
# by introspecting a database that has all migrations applied; the committed
# file was bootstrapped that way.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="types/database.types.ts"
PROJECT_ID="${SUPABASE_PROJECT_ID:-}"
mkdir -p types

if command -v supabase >/dev/null 2>&1; then
  if [ -n "$PROJECT_ID" ]; then
    echo "Generating types from project $PROJECT_ID ..."
    supabase gen types typescript --project-id "$PROJECT_ID" > "$OUT"
  else
    echo "Generating types from the local Supabase stack ..."
    supabase gen types typescript --local > "$OUT"
  fi
  echo "Wrote $OUT ($(wc -l < "$OUT") lines)"
else
  echo "Supabase CLI not found; leaving the existing $OUT untouched." >&2
  echo "Install the CLI (and Docker), or set SUPABASE_PROJECT_ID + run 'supabase login'." >&2
fi

# Propagate to sibling repos if present.
for sib in ../mathetes-mobile/src/lib/database.types.ts ../mathetes-admin/src/lib/database.types.ts; do
  dir="$(dirname "$sib")"
  if [ -d "$dir" ]; then
    cp "$OUT" "$sib"
    echo "Copied -> $sib"
  fi
done
