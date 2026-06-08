-- ============================================================================
--  Encuestas de Salida · Usuarios y roles del dashboard
--  Dos roles:
--    · 'admin'   → ve estadísticas + Administración (preguntas, tablets, usuarios)
--    · 'lectura' → SOLO ve estadísticas (sin Administración)
--
--  Aplicar DESPUÉS de schema.sql, dashboard_rpc.sql y dashboard_admin.sql.
--  (Este archivo "endurece" las políticas de admin para que escribir requiera rol admin.)
-- ============================================================================

-- ---------- Tabla de perfiles (1 por usuario de Auth) ----------
create table if not exists public.perfil (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  rol        text not null default 'lectura' check (rol in ('admin','lectura')),
  creado_en  timestamptz not null default now()
);
alter table public.perfil enable row level security;

-- ---------- ¿El usuario actual es admin? (helper) ----------
-- security definer → puede leer perfil sin recursión de RLS.
create or replace function public.es_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.perfil where id = auth.uid() and rol = 'admin'
  );
$$;
grant execute on function public.es_admin() to authenticated;

-- ---------- Alta automática de perfil al crear un usuario (rol 'lectura') ----------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.perfil (id, email, rol)
  values (new.id, new.email, 'lectura')
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- RLS de perfil ----------
-- Cada quien ve su propio perfil; un admin ve y gestiona todos.
drop policy if exists "perfil_select" on public.perfil;
create policy "perfil_select" on public.perfil
  for select to authenticated
  using (id = auth.uid() or public.es_admin());

drop policy if exists "perfil_admin_write" on public.perfil;
create policy "perfil_admin_write" on public.perfil
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ============================================================================
--  Endurecer Administración: escribir requiere rol admin (no solo estar logueado)
-- ============================================================================

-- PREGUNTAS: lectura/escritura de la tabla solo para admin (los lectores usan RPC).
drop policy if exists "preguntas_select_auth" on public.preguntas;
create policy "preguntas_admin_select" on public.preguntas
  for select to authenticated using (public.es_admin());

drop policy if exists "preguntas_insert_auth" on public.preguntas;
create policy "preguntas_admin_insert" on public.preguntas
  for insert to authenticated with check (public.es_admin());

drop policy if exists "preguntas_update_auth" on public.preguntas;
create policy "preguntas_admin_update" on public.preguntas
  for update to authenticated using (public.es_admin()) with check (public.es_admin());

drop policy if exists "preguntas_delete_auth" on public.preguntas;
create policy "preguntas_admin_delete" on public.preguntas
  for delete to authenticated using (public.es_admin());
-- (La política anon "preguntas_select_activas" de schema.sql NO se toca:
--  la tablet sigue viendo solo las activas.)

-- DISPOSITIVOS: solo admin.
drop policy if exists "dispositivos_all_auth" on public.dispositivos;
create policy "dispositivos_admin_all" on public.dispositivos
  for all to authenticated using (public.es_admin()) with check (public.es_admin());

-- ============================================================================
--  SEMBRAR EL PRIMER ADMIN  ← EDITA EL CORREO Y EJECUTA ESTA LÍNEA
--  (El primer admin debe sembrarse aquí porque solo un admin puede nombrar otros.)
-- ============================================================================
-- insert into public.perfil (id, email, rol)
-- select id, email, 'admin' from auth.users where email = 'direccion@patronato.org'
-- on conflict (id) do update set rol = 'admin';
