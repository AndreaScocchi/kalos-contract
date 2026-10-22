-- Migration 20261022110000: `public_site_events` dice chi tiene l'evento
--
-- Il 22/10/2026 Search Console ha segnalato i dati strutturati degli eventi del sito senza
-- `performer` (e senza prezzo e `validFrom` nell'offerta, che il sito ricava da colonne già
-- presenti). Chi tiene un evento sta in `event_operators` («Chi lo tiene» nel gestionale), chiusa ad
-- anon perché porta anche il modello di compenso.
--
-- In fondo alla view, senza toccare le colonne esistenti: i nomi di chi tiene l'evento, in ordine
-- alfabetico, solo per le persone che il sito mostra già (stessa regola di `public_site_operators`:
-- attive, visibili sul sito, non cancellate). Chi non è visibile sul sito non compare. Array vuoto
-- quando non c'è nessunə.

CREATE OR REPLACE VIEW "public"."public_site_events" AS
SELECT e.id, e.name AS title, e.description, e.image_url,
       e.starts_at AS start_date, e.ends_at AS end_date,
       e.link AS registration_url, e.link AS link_url,
       e.created_at, e.updated_at,
       e.event_type,
       e.location_id,
       loc.slug AS location_slug,
       loc.name AS location_name,
       loc.city AS location_city,
       loc.map_url AS location_map_url,
       loc.address_street AS location_address,
       loc.address_zip AS location_zip,
       loc.province AS location_province,
       e.price_cents,
       e.currency,
       ARRAY(
           SELECT o.name
             FROM public.event_operators eo
             JOIN public.operators o ON o.id = eo.operator_id
            WHERE eo.event_id = e.id
              AND o.is_active = true AND o.is_visible_on_site = true AND o.deleted_at IS NULL
            ORDER BY o.name
       ) AS performer_names
  FROM public.events e
  LEFT JOIN public.locations loc ON loc.id = e.location_id AND loc.show_on_site = true AND loc.is_active = true
 WHERE e.deleted_at IS NULL AND COALESCE(e.is_active, true) = true
 ORDER BY e.starts_at DESC;

COMMENT ON COLUMN "public"."public_site_events"."performer_names" IS
    'Chi tiene l''evento (event_operators), solo le persone visibili sul sito come in public_site_operators. Per il `performer` dei dati strutturati.';
