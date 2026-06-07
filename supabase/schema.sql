-- ============================================================================
--  Encuestas de Salida · Patronato Hospital Materno Infantil de Nuevo León
--  Esquema Supabase (Postgres) · v1
--
--  Principios:
--   · ANÓNIMO: cero datos personales del paciente/familiar.
--   · DATA-DRIVEN: las preguntas viven en BD (Dirección puede editar texto
--     sin recompilar la app de la tablet).
--   · OFFLINE-FIRST: la tablet genera UUIDs locales e inserta cuando hay red
--     (idempotente vía PK = uuid del cliente).
-- ============================================================================

-- ---------- Tipos ----------
do $$ begin
  create type departamento as enum ('pediatria', 'ginecologia');
exception when duplicate_object then null; end $$;

do $$ begin
  create type valor_respuesta as enum ('satisfecho', 'neutral', 'insatisfecho');
exception when duplicate_object then null; end $$;

-- ---------- Dispositivos (tablets) ----------
create table if not exists public.dispositivos (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null,                 -- "Tablet Pediatría P5"
  departamento  departamento not null,
  ubicacion     text,                          -- "Oficina Trabajo Social, Piso 5"
  activo        boolean not null default true,
  ultima_conexion timestamptz,
  creado_en     timestamptz not null default now()
);

-- ---------- Preguntas (editables desde el dashboard) ----------
create table if not exists public.preguntas (
  id            uuid primary key default gen_random_uuid(),
  departamento  departamento not null,
  orden         smallint not null,
  texto         text not null,
  activa        boolean not null default true,
  creado_en     timestamptz not null default now(),
  unique (departamento, orden)
);

-- ---------- Encuestas (sesión = un paciente que responde) ----------
-- El id lo genera la TABLET (uuid v4) para idempotencia offline.
create table if not exists public.encuestas (
  id            uuid primary key,
  departamento  departamento not null,
  dispositivo_id uuid references public.dispositivos(id),
  iniciada_en   timestamptz not null,
  completada_en timestamptz,                   -- null = abandonada
  completada    boolean not null default false,
  app_version   text,
  recibida_en   timestamptz not null default now()  -- cuándo llegó al servidor
);
create index if not exists idx_encuestas_depto_fecha
  on public.encuestas (departamento, completada_en desc);

-- ---------- Respuestas (una por pregunta contestada) ----------
create table if not exists public.respuestas (
  id            uuid primary key,              -- también generado en la tablet
  encuesta_id   uuid not null references public.encuestas(id) on delete cascade,
  pregunta_id   uuid not null references public.preguntas(id),
  departamento  departamento not null,         -- desnormalizado para reportes rápidos
  valor         valor_respuesta not null,
  respondida_en timestamptz not null,
  unique (encuesta_id, pregunta_id)
);
create index if not exists idx_respuestas_pregunta on public.respuestas (pregunta_id, valor);
create index if not exists idx_respuestas_depto_fecha on public.respuestas (departamento, respondida_en desc);

-- ============================================================================
--  SEED · Preguntas exactas del documento aprobado
-- ============================================================================
insert into public.preguntas (departamento, orden, texto) values
  ('pediatria', 1, '¿Considera que el motivo de atención de su paciente fue atendido adecuadamente?'),
  ('pediatria', 2, '¿El personal médico resolvió sus dudas de manera clara?'),
  ('pediatria', 3, '¿La atención y calidez del equipo de enfermería fue el adecuado?'),
  ('pediatria', 4, '¿Cómo califica la comodidad de las instalaciones?'),
  ('ginecologia', 1, '¿Te sentiste acompañada y bien atendida durante tu estancia y recuperación?'),
  ('ginecologia', 2, '¿El personal médico resolvió tus dudas sobre tus cuidados y los de tu bebé?'),
  ('ginecologia', 3, '¿La atención y calidez del equipo de enfermería fue el adecuado?'),
  ('ginecologia', 4, '¿Consideras que tus necesidades y las de tu bebé fueron atendidas adecuadamente?'),
  ('ginecologia', 5, '¿Cómo califica la comodidad de las instalaciones?')
on conflict (departamento, orden) do nothing;

-- ============================================================================
--  VISTAS para el dashboard (consultas triviales desde supabase-js)
-- ============================================================================

-- Resumen por departamento (últimos 30 días)
create or replace view public.v_resumen_departamento as
select
  r.departamento,
  count(*)                                                        as total_respuestas,
  round(100.0 * count(*) filter (where valor = 'satisfecho')   / count(*), 0) as pct_satisfecho,
  round(100.0 * count(*) filter (where valor = 'neutral')      / count(*), 0) as pct_neutral,
  round(100.0 * count(*) filter (where valor = 'insatisfecho') / count(*), 0) as pct_insatisfecho
from public.respuestas r
where r.respondida_en >= now() - interval '30 days'
group by r.departamento;

-- Desglose por pregunta (últimos 30 días)
create or replace view public.v_desglose_pregunta as
select
  p.departamento,
  p.orden,
  p.texto,
  count(r.*)                                                          as total,
  count(r.*) filter (where r.valor = 'satisfecho')                   as n_satisfecho,
  count(r.*) filter (where r.valor = 'neutral')                      as n_neutral,
  count(r.*) filter (where r.valor = 'insatisfecho')                 as n_insatisfecho,
  round(100.0 * count(r.*) filter (where r.valor = 'satisfecho') / nullif(count(r.*),0), 0) as pct_satisfecho
from public.preguntas p
left join public.respuestas r
  on r.pregunta_id = p.id and r.respondida_en >= now() - interval '30 days'
where p.activa
group by p.departamento, p.orden, p.texto
order by p.departamento, p.orden;

-- KPIs globales
create or replace view public.v_kpis as
select
  (select count(*) from public.encuestas where completada and completada_en >= now() - interval '30 days') as total_encuestas,
  round(100.0 * (select count(*) from public.respuestas where valor='satisfecho' and respondida_en >= now() - interval '30 days')
              / nullif((select count(*) from public.respuestas where respondida_en >= now() - interval '30 days'),0), 0) as satisfaccion_general,
  round(100.0 * (select count(*) from public.encuestas where completada and iniciada_en >= now() - interval '30 days')
              / nullif((select count(*) from public.encuestas where iniciada_en >= now() - interval '30 days'),0), 0) as tasa_finalizacion;

-- ============================================================================
--  RLS · Seguridad
--   · anon  (tablet): SELECT preguntas activas + INSERT encuestas/respuestas.
--   · authenticated (dashboard): SELECT de todo.
-- ============================================================================
alter table public.preguntas    enable row level security;
alter table public.encuestas    enable row level security;
alter table public.respuestas   enable row level security;
alter table public.dispositivos enable row level security;

-- Preguntas: cualquiera puede leer las activas (la tablet las descarga)
drop policy if exists "preguntas_select_activas" on public.preguntas;
create policy "preguntas_select_activas" on public.preguntas
  for select using (activa = true);

-- Encuestas: la tablet (anon) inserta; el dashboard (auth) lee
drop policy if exists "encuestas_insert_anon" on public.encuestas;
create policy "encuestas_insert_anon" on public.encuestas
  for insert with check (true);
drop policy if exists "encuestas_select_auth" on public.encuestas;
create policy "encuestas_select_auth" on public.encuestas
  for select using (auth.role() = 'authenticated');

-- Respuestas: igual patrón
drop policy if exists "respuestas_insert_anon" on public.respuestas;
create policy "respuestas_insert_anon" on public.respuestas
  for insert with check (true);
drop policy if exists "respuestas_select_auth" on public.respuestas;
create policy "respuestas_select_auth" on public.respuestas
  for select using (auth.role() = 'authenticated');

-- Dispositivos: solo dashboard
drop policy if exists "dispositivos_all_auth" on public.dispositivos;
create policy "dispositivos_all_auth" on public.dispositivos
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- Las vistas se sirven con privilegios del owner; expón solo lectura:
grant select on public.v_resumen_departamento, public.v_desglose_pregunta, public.v_kpis to anon, authenticated;

-- NOTA seguridad: el anon key va embebido en la app. Para v1 es aceptable
-- (solo permite INSERT, no lectura). Endurecer luego con: token por dispositivo,
-- Edge Function de ingesta con rate-limit, o Supabase "Anonymous Sign-ins".
