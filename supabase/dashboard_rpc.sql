-- ============================================================================
--  Encuestas de Salida · Funciones RPC para el dashboard (F4)
--  Todas parametrizadas por rango de fechas + departamento opcional, para que
--  el dashboard filtre/agregue en el servidor (no trae filas crudas al navegador).
--
--  Aplicar UNA vez en tu instancia (SQL Editor o psql), DESPUÉS de schema.sql.
--  Solo lectura. security definer + grant exclusivo a 'authenticated'.
--  Zona horaria de agrupación: America/Monterrey.
-- ============================================================================

-- ---------- Métricas ejecutivas (una fila) ----------
-- Sirve para: KPIs, NPS, tasa de finalización, tiempo promedio.
-- NPS de 3 niveles: promotores = satisfecho, detractores = insatisfecho,
-- NPS = %promotores - %detractores.
create or replace function public.dashboard_metrics(
  p_desde timestamptz,
  p_hasta timestamptz,
  p_depto text default null
)
returns table (
  total_respuestas      bigint,
  total_encuestas       bigint,
  satisfaccion_general  numeric,
  tasa_finalizacion     numeric,
  nps                   numeric,
  pct_promotores        numeric,
  pct_detractores       numeric,
  tiempo_promedio_seg   numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with r as (
    select * from public.respuestas
    where respondida_en >= p_desde and respondida_en < p_hasta
      and (p_depto is null or departamento::text = p_depto)
  ),
  e as (
    select * from public.encuestas
    where iniciada_en >= p_desde and iniciada_en < p_hasta
      and (p_depto is null or departamento::text = p_depto)
  )
  select
    (select count(*) from r),
    (select count(*) from e where completada),
    (select round(100.0 * count(*) filter (where valor='satisfecho') / nullif(count(*),0), 0) from r),
    (select round(100.0 * count(*) filter (where completada) / nullif(count(*),0), 0) from e),
    (select round(
        100.0 * count(*) filter (where valor='satisfecho') / nullif(count(*),0)
      - 100.0 * count(*) filter (where valor='insatisfecho') / nullif(count(*),0), 0) from r),
    (select round(100.0 * count(*) filter (where valor='satisfecho')   / nullif(count(*),0), 0) from r),
    (select round(100.0 * count(*) filter (where valor='insatisfecho') / nullif(count(*),0), 0) from r),
    (select round(avg(extract(epoch from (completada_en - iniciada_en)))::numeric, 0)
       from e where completada and completada_en is not null);
$$;

-- ---------- Resumen por departamento ----------
create or replace function public.dashboard_resumen_departamento(
  p_desde timestamptz,
  p_hasta timestamptz
)
returns table (
  departamento      text,
  total_respuestas  bigint,
  total_encuestas   bigint,
  pct_satisfecho    numeric,
  pct_neutral       numeric,
  pct_insatisfecho  numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.departamento::text,
    count(*) as total_respuestas,
    (select count(*) from public.encuestas e
       where e.departamento = r.departamento and e.completada
         and e.completada_en >= p_desde and e.completada_en < p_hasta) as total_encuestas,
    round(100.0 * count(*) filter (where r.valor='satisfecho')   / count(*), 0),
    round(100.0 * count(*) filter (where r.valor='neutral')      / count(*), 0),
    round(100.0 * count(*) filter (where r.valor='insatisfecho') / count(*), 0)
  from public.respuestas r
  where r.respondida_en >= p_desde and r.respondida_en < p_hasta
  group by r.departamento
  order by r.departamento;
$$;

-- ---------- Desglose por pregunta ----------
create or replace function public.dashboard_desglose_pregunta(
  p_desde timestamptz,
  p_hasta timestamptz,
  p_depto text default null
)
returns table (
  departamento    text,
  orden           smallint,
  texto           text,
  total           bigint,
  n_satisfecho    bigint,
  n_neutral       bigint,
  n_insatisfecho  bigint,
  pct_satisfecho  numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.departamento::text, p.orden, p.texto,
    count(r.*) as total,
    count(r.*) filter (where r.valor='satisfecho')   as n_satisfecho,
    count(r.*) filter (where r.valor='neutral')      as n_neutral,
    count(r.*) filter (where r.valor='insatisfecho') as n_insatisfecho,
    round(100.0 * count(r.*) filter (where r.valor='satisfecho') / nullif(count(r.*),0), 0) as pct_satisfecho
  from public.preguntas p
  left join public.respuestas r
    on r.pregunta_id = p.id
   and r.respondida_en >= p_desde and r.respondida_en < p_hasta
  where p.activa and (p_depto is null or p.departamento::text = p_depto)
  group by p.departamento, p.orden, p.texto
  order by p.departamento, p.orden;
$$;

-- ---------- Tendencia diaria por departamento (líneas) ----------
create or replace function public.dashboard_tendencia_dept(
  p_desde timestamptz,
  p_hasta timestamptz
)
returns table (
  dia               date,
  departamento      text,
  total_encuestas   bigint,
  pct_satisfecho    numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (e.iniciada_en at time zone 'America/Monterrey')::date as dia,
    e.departamento::text,
    count(*) filter (where e.completada) as total_encuestas,
    null::numeric
  from public.encuestas e
  where e.iniciada_en >= p_desde and e.iniciada_en < p_hasta
  group by 1, 2
  order by 1, 2;
$$;

-- ---------- Heatmap: respuestas por día de semana × hora ----------
-- dow: 0=domingo … 6=sábado (estándar Postgres). hora: 0-23.
create or replace function public.dashboard_heatmap(
  p_desde timestamptz,
  p_hasta timestamptz,
  p_depto text default null
)
returns table (
  dow   int,
  hora  int,
  n     bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    extract(dow  from (e.iniciada_en at time zone 'America/Monterrey'))::int as dow,
    extract(hour from (e.iniciada_en at time zone 'America/Monterrey'))::int as hora,
    count(*) as n
  from public.encuestas e
  where e.iniciada_en >= p_desde and e.iniciada_en < p_hasta
    and (p_depto is null or e.departamento::text = p_depto)
  group by 1, 2;
$$;

-- ---------- Satisfacción por hora del día ----------
create or replace function public.dashboard_por_hora(
  p_desde timestamptz,
  p_hasta timestamptz,
  p_depto text default null
)
returns table (
  hora            int,
  total           bigint,
  pct_satisfecho  numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    extract(hour from (r.respondida_en at time zone 'America/Monterrey'))::int as hora,
    count(*) as total,
    round(100.0 * count(*) filter (where r.valor='satisfecho') / count(*), 0) as pct_satisfecho
  from public.respuestas r
  where r.respondida_en >= p_desde and r.respondida_en < p_hasta
    and (p_depto is null or r.departamento::text = p_depto)
  group by 1
  order by 1;
$$;

-- ---------- Stream de últimas respuestas (anonimizado) ----------
create or replace function public.dashboard_ultimas(
  p_limit int default 8
)
returns table (
  encuesta_id     uuid,
  departamento    text,
  completada_en   timestamptz,
  n_satisfecho    bigint,
  n_neutral       bigint,
  n_insatisfecho  bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    e.id, e.departamento::text, e.completada_en,
    count(r.*) filter (where r.valor='satisfecho')   as n_satisfecho,
    count(r.*) filter (where r.valor='neutral')      as n_neutral,
    count(r.*) filter (where r.valor='insatisfecho') as n_insatisfecho
  from public.encuestas e
  left join public.respuestas r on r.encuesta_id = e.id
  where e.completada and e.completada_en is not null
  group by e.id, e.departamento, e.completada_en
  order by e.completada_en desc
  limit greatest(p_limit, 1);
$$;

-- ============================================================================
--  Permisos: solo el dashboard logueado ('authenticated')
-- ============================================================================
do $$
declare fn text;
begin
  foreach fn in array array[
    'public.dashboard_metrics(timestamptz, timestamptz, text)',
    'public.dashboard_resumen_departamento(timestamptz, timestamptz)',
    'public.dashboard_desglose_pregunta(timestamptz, timestamptz, text)',
    'public.dashboard_tendencia_dept(timestamptz, timestamptz)',
    'public.dashboard_heatmap(timestamptz, timestamptz, text)',
    'public.dashboard_por_hora(timestamptz, timestamptz, text)',
    'public.dashboard_ultimas(int)'
  ] loop
    execute format('revoke all on function %s from public, anon;', fn);
    execute format('grant execute on function %s to authenticated;', fn);
  end loop;
end $$;
