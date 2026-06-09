-- ============================================================================
--  Permitir publicar versiones del APK (OTA) desde el panel de admin del dashboard
--  Aplicar DESPUÉS de releases.sql y usuarios_roles.sql (usa es_admin()).
--
--  El admin (authenticated con rol 'admin') puede:
--    · subir/actualizar el APK en el bucket privado app-releases
--    · insertar/editar filas en app_release
--  La tablet (anon) sigue solo descargando la versión activa (sin cambios).
-- ============================================================================

-- Tabla app_release: el admin ve todas e inserta/edita/borra
drop policy if exists "app_release_admin_all" on public.app_release;
create policy "app_release_admin_all" on public.app_release
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());
-- (la policy anon "app_release_select_anon" de releases.sql se mantiene)

-- Subir el límite de tamaño del bucket (el APK pesa ~50+ MB)
update storage.buckets set file_size_limit = 314572800 where id = 'app-releases'; -- 300 MB
-- ⚠️ Si la subida falla por tamaño, sube también el límite GLOBAL del servicio
--    Storage en tu .env (p. ej. STORAGE_FILE_SIZE_LIMIT) y reinicia el contenedor.
--    Alternativa: publicar el APK arm64 (flutter build apk --split-per-abi) ≈ 20 MB.

-- Storage: el admin sube/actualiza/borra objetos en app-releases
drop policy if exists "releases_admin_write" on storage.objects;
create policy "releases_admin_write" on storage.objects
  for all to authenticated
  using (bucket_id = 'app-releases' and public.es_admin())
  with check (bucket_id = 'app-releases' and public.es_admin());
-- (la policy anon "releases_download" de releases.sql se mantiene para la tablet)
