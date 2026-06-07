# Dashboard · Encuestas de Salida (F4)

Dashboard web estático (HTML + supabase-js por CDN) para Dirección y Trabajo Social.
Sin build. Se conecta a tu instancia Supabase self-hosted vía login (Supabase Auth).

## Archivos
- `index.html` — estructura (login + dashboard + administración).
- `styles.css` — diseño de marca (idéntico al demo aprobado).
- `app.js` — lógica: auth, carga de datos (RPC), render y CRUD de administración.
- `config.js` — **tú lo llenas** con tu `SUPABASE_URL` y `ANON_KEY`.
- `preview.html` — vista previa con datos de ejemplo (no se conecta a Supabase). Solo para ver el diseño.

## Puesta en marcha (3 pasos)

### 1. Aplicar el SQL en tu instancia (una sola vez)
En el SQL Editor (o `psql`), después de `schema.sql`:
```sql
-- funciones de lectura para el dashboard
\i supabase/dashboard_rpc.sql
-- permisos de administración (editar preguntas / tablets)
\i supabase/dashboard_admin.sql
```

### 2. Configurar credenciales
Edita `config.js` y pega tu URL del túnel y tu **anon key** (de GitHub → Settings →
Secrets and variables → Actions). El anon key es público (el mismo que usa la app);
**nunca** pongas aquí el service key.

### 3. Crear el usuario de Dirección
El login usa Supabase Auth. Crea el/los usuarios en tu instancia
(Authentication → Users → Add user, con email + contraseña). Solo usuarios
`authenticated` pueden ver datos y administrar (lo impone RLS).

## Correr local
Cualquier servidor estático:
```bash
cd dashboard
python -m http.server 8080   # o:  npx serve .
# abrir http://localhost:8080
```

## Desplegar en Vercel
- Root del proyecto: `dashboard/` (o mueve estos archivos a la raíz del deploy).
- Sin build command, sin framework. Vercel sirve los estáticos tal cual.
- `config.js` se sirve con la URL/anon key; si prefieres no commitearlo, súbelo
  como archivo en Vercel o usa variables → genera `config.js` en build.

## Qué muestra
KPIs (total respuestas, satisfacción, % por depto) · NPS (= %satisfecho − %insatisfecho) ·
tasa de finalización · tiempo promedio · heatmap día×hora · donas por departamento ·
satisfacción por hora · insights automáticos · desglose por pregunta · tendencia por
depto · últimas respuestas. Filtros: periodo (hoy/semana/30 días/mes anterior) y departamento.

## Administración
Pestaña **Administración** (solo usuario logueado):
- **Preguntas**: crear, editar texto/orden, activar/desactivar, borrar. La tablet
  descarga solo las activas — editar aquí **no** requiere recompilar la app.
- **Tablets**: registrar/editar/activar/borrar dispositivos.
