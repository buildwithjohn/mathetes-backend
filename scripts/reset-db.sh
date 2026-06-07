#!/usr/bin/env bash
# Reset the local database: drops, re-runs all migrations, applies seed.
set -euo pipefail

cd "$(dirname "$0")/.."

supabase db reset
