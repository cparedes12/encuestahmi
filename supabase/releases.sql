-- ============================================================================
--  Distribución PRIVADA del APK (OTA) vía Supabase Storage
--  El APK NO es público: solo se descarga con credencial (la App) o URL firmada.
-- ============================================================================

-- Bucket privado para los APK de actualización
insert into storage.buckets (id, name, public)
values ('app-releases', 'app-releases', false)
on conflict (id) do nothing;

-- Tabla con la versión publicada (la App consulta la más reciente activa)
create table if not exists public.app_release (
  id            bigint generated always as identity primary key,
  version       text not null,            -- ej. "1.0.1"
  build         int,                       -- opcional (build number)
  storage_path  text not null,             -- ej. "encuesta-salida-1.0.1.apk"
  notas         text,
  activo        boolean not null default true,
  publicado_en  timestamptz not null default now()
);
create index if not exists idx_app_release_activo
  on public.app_release (activo, publicado_en desc);

alter table public.app_release enable row level security;

-- La tablet (anon) puede CONSULTAR la versión vigente…
drop policy if exists "app_release_select_anon" on public.app_release;
create policy "app_release_select_anon" on public.app_release
  for select using (activo = true);

-- …y DESCARGAR el APK del bucket privado (no hay URL pública; requiere la llave).
drop policy if exists "releases_download" on storage.objects;
create policy "releases_download" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'app-releases');

-- NOTA: la subida del APK la hace el CI con el service_role key (bypassa RLS).
-- Para endurecer aún más: servir el APK vía Edge Function que valide un token
-- por dispositivo antes de emitir la URL firmada.
