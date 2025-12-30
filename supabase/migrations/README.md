# Migrations

Questa directory contiene le migrations canoniche del database Supabase.

## Formato

Le migrations devono seguire il formato: `YYYYMMDDHHMMSS_description.sql`

Esempio: `20240101120000_create_users_table.sql`

## Note

- Questa è la **source of truth** per le migrations del database
- Le migrations vengono applicate in ordine cronologico (basato sul timestamp nel nome)
- Non modificare migrations esistenti dopo che sono state applicate a produzione
- Per creare una nuova migration, usa `supabase db diff` o crea manualmente un nuovo file

