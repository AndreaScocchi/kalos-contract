-- Migration: Filter inactive activities from public_site_activities view
--
-- Obiettivo: La view public_site_activities (usata dal sito pubblico) deve
-- mostrare solo le attività con is_active = true. Il flag is_active funge da
-- "pubblica sul sito" gestito dal gestionale. L'app legge invece direttamente
-- la tabella activities e non è influenzata da questo filtro.

CREATE OR REPLACE VIEW public.public_site_activities AS
SELECT
  a.id,
  a.name,
  a.slug,
  a.description,
  a.discipline,
  a.color,
  a.icon_name,
  a.duration_minutes,
  a.image_url,
  a.is_active,
  a.landing_title,
  a.landing_subtitle,
  a.active_months,
  a.target_audience,
  a.program_objectives,
  a.why_participate,
  a.journey_structure,
  a.created_at,
  a.updated_at
FROM public.activities a
WHERE
  a.deleted_at IS NULL
  AND COALESCE(a.is_active, true) = true
ORDER BY a.name ASC;

COMMENT ON VIEW public.public_site_activities IS
  'View pubblica per le attività visibili sul sito. Filtra per deleted_at IS NULL AND is_active = true. Il flag is_active controlla la visibilità pubblica: attività con is_active = false restano disponibili in app/gestionale ma non sul sito.';

GRANT SELECT ON public.public_site_activities TO anon;
GRANT SELECT ON public.public_site_activities TO authenticated;
