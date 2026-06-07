-- ============================================================================
--  Encuestas de Salida · Permisos de administración para el dashboard
--  Permite al usuario logueado (authenticated) gestionar PREGUNTAS y TABLETS
--  desde el panel de administración. Aplicar después de schema.sql.
--
--  Recuerda: la tablet (anon) sigue viendo solo preguntas activas; el anon key
--  NO puede editar (estas políticas son exclusivas de 'authenticated').
-- ============================================================================

-- ---------- PREGUNTAS: el dashboard ve todas (activas e inactivas) ----------
drop policy if exists "preguntas_select_auth" on public.preguntas;
create policy "preguntas_select_auth" on public.preguntas
  for select to authenticated using (true);

-- ---------- PREGUNTAS: el dashboard puede crear / editar / borrar ----------
drop policy if exists "preguntas_insert_auth" on public.preguntas;
create policy "preguntas_insert_auth" on public.preguntas
  for insert to authenticated with check (true);

drop policy if exists "preguntas_update_auth" on public.preguntas;
create policy "preguntas_update_auth" on public.preguntas
  for update to authenticated using (true) with check (true);

drop policy if exists "preguntas_delete_auth" on public.preguntas;
create policy "preguntas_delete_auth" on public.preguntas
  for delete to authenticated using (true);

-- ---------- DISPOSITIVOS ----------
-- schema.sql ya concede ALL a authenticated ("dispositivos_all_auth").
-- Lo reafirmamos por si se aplica este archivo de forma independiente.
drop policy if exists "dispositivos_all_auth" on public.dispositivos;
create policy "dispositivos_all_auth" on public.dispositivos
  for all to authenticated using (true) with check (true);
