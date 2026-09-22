#!/usr/bin/env bash
# restore — ripristina un backup di run-backup.sh in un progetto Supabase VUOTO. Vedi BACKUP.md.
#
#   scripts/backup/restore.sh <backup.tar.gz.age> <chiave-privata-age>
#
# Variabili:
#   TARGET_DB_URL              database di destinazione (progetto nuovo, mai quello di produzione)
#   SUPABASE_URL               progetto di destinazione, per lo Storage   } se mancano, lo Storage
#   SUPABASE_SERVICE_ROLE_KEY  chiave service_role della destinazione     } non viene ripristinato
#   PSQL                       comando psql (default: psql; va bene anche un `docker run ... psql`)
#   RESTORE_CRON=1             ricrea anche i job pg_cron (solo su un progetto vero con pg_cron)
#
# Alla fine confronta, tabella per tabella, le righe ripristinate con quelle del backup.
set -euo pipefail

archive="${1:?Uso: restore.sh <backup.tar.gz.age> <chiave-privata-age>}"
identity="${2:?Uso: restore.sh <backup.tar.gz.age> <chiave-privata-age>}"
: "${TARGET_DB_URL:?Serve TARGET_DB_URL}"
psql=(${PSQL:-psql})

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "▸ decifratura"
age -d -i "$identity" "$archive" | tar -xz -C "$work"
jq -r '"  backup del \(.created_at) · \(.supabase_cli)"' "$work/backup-info.json"

echo "▸ database"
{
  cat "$work/db/roles.sql" "$work/db/schema.sql"
  echo 'SET session_replication_role = replica;'
  cat "$work/db/data.sql"
} | "${psql[@]}" --single-transaction -v ON_ERROR_STOP=1 -q -d "$TARGET_DB_URL" -f - > /dev/null

echo "▸ policy dello Storage"
"${psql[@]}" -v ON_ERROR_STOP=1 -q -d "$TARGET_DB_URL" -f - < "$work/db/storage_policies.sql" > /dev/null

if [ "${RESTORE_CRON:-0}" = 1 ]; then
  echo "▸ job pg_cron"
  "${psql[@]}" -v ON_ERROR_STOP=1 -q -d "$TARGET_DB_URL" -f - < "$work/db/cron_jobs.sql" > /dev/null
fi

echo "▸ verifica delle righe"
"${psql[@]}" -At -F '|' -d "$TARGET_DB_URL" -c "
  select table_schema || '.' || table_name,
         (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text::bigint
  from information_schema.tables
  where table_schema in ('public', 'auth') and table_type = 'BASE TABLE'
    and (table_schema, table_name) <> ('auth', 'schema_migrations')" \
  | jq -R 'split("|") | {(.[0]): (.[1] | tonumber)}' | jq -s 'add' > "$work/restored_counts.json"

diffs="$(jq -n --slurpfile a "$work/db/row_counts.json" --slurpfile b "$work/restored_counts.json" '
  $a[0] | to_entries | map(select(.value != ($b[0][.key] // -1))) | map("\(.key): backup \(.value), ripristinate \($b[0][.key] // "tabella mancante")") | .[]' -r)"
if [ -n "$diffs" ]; then
  echo "❌ Righe diverse dal backup:"; echo "$diffs"; exit 1
fi
echo "  ✅ $(jq 'length' "$work/db/row_counts.json") tabelle, $(jq '[.[]] | add' "$work/db/row_counts.json") righe: tutte uguali al backup"

if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
  echo "▸ storage"
  node "$(dirname "$0")/storage-sync.mjs" push "$work/storage"
  node "$(dirname "$0")/storage-sync.mjs" verify "$work/storage"
else
  echo "▸ storage: saltato (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY non impostate)"
fi

echo
echo "Da rifare a mano sul progetto nuovo (non sono nel backup, vedi BACKUP.md):"
echo "  - secret del Vault: $(tr '\n' ' ' < "$work/db/vault_secret_names.txt")"
[ "${RESTORE_CRON:-0}" = 1 ] || echo "  - job pg_cron: RESTORE_CRON=1, oppure db/cron_jobs.sql"
echo "  - secret e deploy delle edge function, impostazioni Auth (URL, email, provider)"
