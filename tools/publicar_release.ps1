# ============================================================================
#  Publica el APK en Supabase Storage (bucket privado app-releases) y registra
#  la versión en la tabla app_release. Úsalo para publicar OTA manualmente.
#
#  Uso:
#    powershell -ExecutionPolicy Bypass -File tools\publicar_release.ps1 `
#      -ServiceKey "eyJ...service_role..." -Version "1.0.0"
#
#  (El service_role key se encuentra en el .env de tu Supabase, como
#   SERVICE_ROLE_KEY. NO lo compartas ni lo subas a git.)
# ============================================================================
param(
  [Parameter(Mandatory = $true)][string]$ServiceKey,
  [string]$Version = "1.0.0",
  [string]$Url = "https://encuestas-api.vlx.com.mx",
  [string]$Apk = "$PSScriptRoot\..\app\build\app\outputs\flutter-apk\app-release.apk"
)

if (-not (Test-Path $Apk)) { Write-Error "No existe el APK: $Apk"; exit 1 }
$file = "encuesta-salida-$Version.apk"

Write-Host "Subiendo $file a bucket app-releases ..." -ForegroundColor Cyan
curl.exe -s -f -X POST "$Url/storage/v1/object/app-releases/$file" `
  -H "Authorization: Bearer $ServiceKey" -H "apikey: $ServiceKey" `
  -H "x-upsert: true" -H "Content-Type: application/vnd.android.package-archive" `
  --data-binary "@$Apk"
if ($LASTEXITCODE -ne 0) { Write-Error "Falló la subida del APK"; exit 1 }

Write-Host "`nRegistrando versión $Version en app_release ..." -ForegroundColor Cyan
$body = "{""version"":""$Version"",""storage_path"":""$file"",""notas"":""Release manual $Version"",""activo"":true}"
curl.exe -s -f -X POST "$Url/rest/v1/app_release" `
  -H "Authorization: Bearer $ServiceKey" -H "apikey: $ServiceKey" `
  -H "Content-Type: application/json" -H "Prefer: return=minimal" `
  --data $body
if ($LASTEXITCODE -ne 0) { Write-Error "Falló el registro de la versión"; exit 1 }

Write-Host "`n[OK] Publicado: $file (version $Version)" -ForegroundColor Green
