#!/usr/bin/env bash
# Generate TypeScript types from the local Supabase schema.
# Output is committed to types.ts and copied into mobile + admin.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Generating types from local Supabase..."
supabase gen types typescript --local > types.ts
echo "Wrote types.ts ($(wc -l < types.ts) lines)"

# Optional: propagate to sibling repos if they exist.
for sib in ../mathetes-mobile/src/lib/database.types.ts ../mathetes-admin/src/lib/database.types.ts; do
  dir="$(dirname "$sib")"
  if [ -d "$dir" ]; then
    cp types.ts "$sib"
    echo "Copied -> $sib"
  fi
done
