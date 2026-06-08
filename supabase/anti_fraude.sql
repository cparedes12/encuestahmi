-- ============================================================================
--  Anti-trampa / calidad de datos
--  Columnas extra en encuestas para detectar respuestas de baja calidad.
--  Aplicar después de schema.sql.
-- ============================================================================

alter table public.encuestas
  add column if not exists sospechosa   boolean not null default false,
  add column if not exists duracion_seg integer;

comment on column public.encuestas.sospechosa is
  'true = respuesta marcada de baja calidad (demasiado rápida o patrón uniforme veloz). No se borra; el dashboard puede filtrarla.';
comment on column public.encuestas.duracion_seg is
  'Segundos entre iniciada_en y completada_en.';

create index if not exists idx_encuestas_sospechosa
  on public.encuestas (sospechosa) where sospechosa;

-- Sugerencia para el dashboard: excluir sospechosas de las métricas, ej.
--   ... where completada and not sospechosa ...
