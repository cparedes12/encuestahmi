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
  SUPABASE_URL: "https://encuestas-api.vlx.com.mx",

  // anon / public key (JWT que empieza con eyJ...)
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzgwODEyNzE1LCJleHAiOjIwOTYxNzI3MTV9.TETCzo3xwjmNmx3E8J4XKa42NvnndVu6DOe0KMFCLdU",
};
