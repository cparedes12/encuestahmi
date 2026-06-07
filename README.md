# Encuestas de Salida · Patronato Hospital Materno Infantil de N.L.

App de kiosko (Galaxy Tab A11+ 5G) para encuestas de salida anónimas en
**Pediatría** y **Ginecología**, con dashboard web para Dirección y Trabajo Social.

## Stack
| Capa | Tecnología | Por qué |
|------|------------|---------|
| App tablet | **Flutter 3.35** (`supabase_flutter`, `sqflite`, `connectivity_plus`) | Mismo stack que tu app de inventario · offline-first · APK kiosko |
| Backend | **Supabase** (proyecto nuevo, aislado) | Postgres + RLS + Realtime + Auth |
| Dashboard | **HTML estático + supabase-js (CDN)** → Vercel | Reusa el diseño ya aprobado · cero build · entrega ASAP |
| Kiosko | **Samsung Knox** (gratis en tablets Samsung) | Bloquea la tablet a una sola app |

## Estructura
```
encuesta_salida/
├─ supabase/
│  └─ schema.sql          # tablas + RLS + vistas + preguntas (seed)
├─ app/                   # Flutter (por crear)
└─ dashboard/             # HTML + supabase-js (por crear, basado en el demo)
```

## Modelo de datos (resumen)
- `preguntas` — editables desde el dashboard (no requiere recompilar la app).
- `encuestas` — una sesión por paciente; `id` lo genera la tablet (idempotencia offline).
- `respuestas` — una por pregunta (`satisfecho` / `neutral` / `insatisfecho`).
- `dispositivos` — registro de tablets.
- Vistas `v_kpis`, `v_resumen_departamento`, `v_desglose_pregunta` para el dashboard.

## Flujo offline-first
1. Al arrancar, la tablet descarga preguntas activas de su departamento y las cachea en SQLite.
2. Cada respuesta se guarda **primero local** (SQLite) con UUID propio.
3. Un `sync` envía pendientes a Supabase cuando hay red (`connectivity_plus`).
4. PK = UUID del cliente → reenvíos no duplican (idempotente).

## Plan de entrega (MVP ASAP)
- [x] **F0** Esquema Supabase + preguntas seed
- [x] **F2** App Flutter: welcome → preguntas → gracias → auto-reset (fiel al demo)
- [x] **F3** Capa offline (SQLite + sync) + config por dispositivo (`--dart-define`)
- [ ] **F1** Instancia Supabase (Docker en VM Proxmox) + `schema.sql` aplicado + ruta en Cloudflare Tunnel
- [ ] **F4** Dashboard HTML conectado a datos reales + login Supabase Auth
- [ ] **F5** APK release + modo kiosko Samsung Knox + instalación en tablet

## Cómo correr la app (con tu Supabase self-hosted)
```bash
cd app
flutter run \
  --dart-define=SUPABASE_URL=https://encuestas-api.tudominio.com \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=DEPARTAMENTO=pediatria
# Sin --dart-define corre en modo demo (datos locales, sin subir nada).
```

## Archivos clave de la app
- `lib/config.dart` — URL/anon key/departamento por `--dart-define`.
- `lib/models.dart` — Departamento, Valor, Pregunta, EncuestaSesion.
- `lib/db.dart` — SQLite local (cola de envío + cache de preguntas).
- `lib/repository.dart` — orquesta guardar local + sync a Supabase + reintentos.
- `lib/main.dart` — flujo de pantallas (welcome/pregunta/gracias).

## Setup Supabase
```bash
# 1. Crear proyecto en https://supabase.com (región: us-east / closest a MX)
# 2. Aplicar el esquema:
supabase link --project-ref <REF>
supabase db push        # o pegar supabase/schema.sql en el SQL Editor
```
