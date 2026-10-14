// Hecho por Briann$ Workers Corp.
// Service worker propio de la PWA.
//
// Flutter 3.47 ya no genera un worker que guarde en caché (el suyo solo se
// desinstala a sí mismo, ver flutter/flutter#156910), así que este archivo da
// el soporte sin conexión.
//
// Estrategia: RED PRIMERO. Con conexión siempre se sirve la versión publicada
// (la caché HTTP del navegador evita descargas repetidas); sin conexión se
// responde desde la caché. Solo maneja archivos propios de la app: las
// llamadas a Supabase (otro dominio) nunca pasan por aquí, así que los datos
// nunca quedan viejos en caché.

const CACHE = 'workers-shell-v2';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

// En la primera visita la página carga antes de que este worker la controle.
// flutter_bootstrap.js manda la lista de archivos que usó para guardarlos.
self.addEventListener('message', (event) => {
  // Solo páginas de este mismo sitio pueden escribir en la caché.
  if (!event.data || event.data.type !== 'precache' || !Array.isArray(event.data.urls)) return;
  if (event.source && event.source.url && new URL(event.source.url).origin !== self.location.origin) return;
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await Promise.all(event.data.urls.slice(0, 300).map(async (url) => {
      try {
        if (new URL(url).origin !== self.location.origin || await cache.match(url)) return;
        const res = await fetch(url);
        if (res.ok && res.type === 'basic') await cache.put(url, res);
      } catch (_) { /* sin red o URL inválida: se guardará en la próxima visita */ }
    }));
  })().catch(() => {}));
});

// La caché nunca debe impedir cargar la app: si el navegador no deja abrirla
// (modo privado, disco lleno, perfil dañado) se sigue solo con la red.
async function openCache() {
  try { return await caches.open(CACHE); } catch (_) { return null; }
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;

  event.respondWith((async () => {
    try {
      const res = await fetch(req);
      if (res.ok && res.type === 'basic') {
        const copy = res.clone();
        openCache().then((cache) => cache && cache.put(req, copy)).catch(() => {});
      }
      return res;
    } catch (err) {
      const cache = await openCache();
      if (cache) {
        const cached = await cache.match(req, { ignoreSearch: true });
        if (cached) return cached;
        if (req.mode === 'navigate') {
          const shell = (await cache.match('./')) || (await cache.match('index.html'));
          if (shell) return shell;
        }
      }
      throw err;
    }
  })());
});
