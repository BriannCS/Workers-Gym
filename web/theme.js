// Hecho por Briann$ Workers Corp.
// Mismo modo que la app: la preferencia guardada (shared_preferences
// escribe "flutter.theme_dark") o, la primera vez, el del sistema.
// Va en un archivo aparte (no en línea) para que la CSP no necesite
// 'unsafe-inline' en scripts.
(function () {
  // Nadie puede meter la app dentro de otra página (clickjacking). En hosting
  // con encabezados lo hace también X-Frame-Options; GitHub Pages no los admite.
  if (window.top !== window.self) {
    document.documentElement.style.display = 'none';
    try { window.top.location = window.self.location.href; } catch (e) {}
    return;
  }
  var saved = null;
  try { saved = localStorage.getItem('flutter.theme_dark'); } catch (e) {}
  var dark = saved === null ? window.matchMedia('(prefers-color-scheme: dark)').matches : saved === 'true';
  if (dark) document.documentElement.classList.add('dark');
})();
