#!/usr/bin/env bash
# run-backup — copia cifrata di database e Storage in un unico file. Vedi BACKUP.md.
#
#   scripts/backup/run-backup.sh <uscita.tar.gz.age>
#
# Variabili:
#   SUPABASE_DB_URL            connessione Postgres (in produzione: session pooler, porta 5432)
#   SUPABASE_URL               URL del progetto, per lo Storage
#   SUPABASE_SERVICE_ROLE_KEY  chiave service_role, per lo Storage
#   BACKUP_AGE_RECIPIENT       chiave PUBBLICA age: basta per cifrare, non per decifrare
#
# Richiede: Node (npm ci), Docker (per `supabase db dump`), jq, age.
# Non stampa dati: i log delle Actions del repo sono pubblici.
set -euo pipefail

out="${1:?Uso: run-backup.sh <uscita.tar.gz.age>}"
: "${SUPABASE_DB_URL:?}" "${SUPABASE_URL:?}" "${SUPABASE_SERVICE_ROLE_KEY:?}" "${BACKUP_AGE_RECIPIENT:?}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/db" "$work/storage"

# Il CLI incapsula le righe in un oggetto quando c'è un terminale interattivo e le restituisce
# come elenco semplice in CI: qui esce sempre un elenco.
query() {
  npx supabase db query --db-url "$SUPABASE_DB_URL" -o json "$1" 2>/dev/null \
    | jq 'if type == "object" and has("rows") then .rows else . end'
}

echo "▸ database"
npx supabase db dump --db-url "$SUPABASE_DB_URL" -f "$work/db/roles.sql" --role-only
npx supabase db dump --db-url "$SUPABASE_DB_URL" -f "$work/db/schema.sql"
# Lo schema storage si ripristina via API (storage-sync): le sue tabelle appartengono al servizio
# Storage e non si scrivono in SQL. I file e i bucket sono nella parte storage/.
storage_tables="$(query "select string_agg(table_schema || '.' || table_name, ',') as t from information_schema.tables where table_schema = 'storage' and table_type = 'BASE TABLE'" | jq -r '.[0].t // empty')"
npx supabase db dump --db-url "$SUPABASE_DB_URL" -f "$work/db/data.sql" --use-copy --data-only ${storage_tables:+-x "$storage_tables"}

# Fuori dal dump: definizione dei job pg_cron e nomi (non valori) dei secret del Vault.
if rows="$(query "select format('select cron.schedule(%L, %L, %L);', jobname, schedule, command) as s from cron.job order by jobname")"; then
  jq -r '.[].s' <<<"$rows" > "$work/db/cron_jobs.sql"
else
  echo "-- pg_cron non presente nel database di origine" > "$work/db/cron_jobs.sql"
fi
query "select name from vault.secrets order by name" | jq -r '.[].name' > "$work/db/vault_secret_names.txt" || true

# Le policy dello Storage non sono nel dump dello schema (storage è uno schema gestito) e in
# produzione sono state create a mano: se ne salva la definizione.
query "select format('DROP POLICY IF EXISTS %I ON %I.%I; CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s%s%s;',
         policyname, schemaname, tablename, policyname, schemaname, tablename, permissive, cmd,
         (select string_agg(quote_ident(r), ', ') from unnest(roles) r),
         case when qual is not null then ' USING (' || qual || ')' else '' end,
         case when with_check is not null then ' WITH CHECK (' || with_check || ')' else '' end) as s
       from pg_policies where schemaname = 'storage' order by tablename, policyname" \
  | jq -r '.[].s' > "$work/db/storage_policies.sql"

# Righe per tabella al momento del backup: servono a verificare il ripristino.
query "select table_schema || '.' || table_name as t,
         (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text::bigint as n
       from information_schema.tables
       where table_schema in ('public', 'auth') and table_type = 'BASE TABLE'
         and (table_schema, table_name) <> ('auth', 'schema_migrations')  -- registro interno di Auth, escluso dal dump
       order by 1" | jq '[.[] | {(.t): .n}] | add' > "$work/db/row_counts.json"

echo "▸ storage"
node "$(dirname "$0")/storage-sync.mjs" pull "$work/storage"

jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cli "$(npx supabase --version 2>/dev/null | head -1)" \
  '{created_at: $at, supabase_cli: $cli, format: 1}' > "$work/backup-info.json"

echo "▸ cifratura"
tar -C "$work" -czf - . | age -r "$BACKUP_AGE_RECIPIENT" -o "$out"
echo "✅ Backup cifrato: $(du -h "$out" | cut -f1) · $(jq 'length' "$work/db/row_counts.json") tabelle · $(wc -l < "$work/db/storage_policies.sql" | tr -d ' ') policy dello Storage"
