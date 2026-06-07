// ============================================================================
//  Configuración del dashboard · Encuestas de Salida
//  Pega aquí los valores de tu instancia Supabase self-hosted.
//  Los encuentras en GitHub → Settings → Secrets and variables → Actions,
//  o en la config de tu servidor Proxmox.
//
//  ⚠️  Solo va el ANON KEY (público, mismo que usa la app). NUNCA el service key.
// ============================================================================
window.CONFIG = {
  // URL pública de tu API Supabase (a través del Cloudflare Tunnel)
  SUPABASE_URL: "https://encuestas-api.tudominio.com",

  // anon / public key (JWT que empieza con eyJ...)
  SUPABASE_ANON_KEY: "PEGA_AQUI_TU_ANON_KEY",
};
