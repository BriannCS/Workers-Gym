// Hecho por Briann$ Workers Corp.
{{flutter_js}}
{{flutter_build_config}}

// Arranque sin `serviceWorkerSettings`: el worker que genera Flutter 3.47 solo
// se desinstala a sí mismo. El modo sin conexión lo da web/sw.js.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    const splash = document.getElementById('splash');
    if (splash) {
      splash.classList.add('done');
      setTimeout(() => splash.remove(), 450);
    }
  },
});

// Los service workers exigen HTTPS (o localhost). En la red local por IP no
// hay, y la app funciona igual: solo pierde el modo sin conexión.
if ('serviceWorker' in navigator && window.isSecureContext) {
  window.addEventListener('load', async () => {
    try {
      const reg = await navigator.serviceWorker.register('sw.js');
      await navigator.serviceWorker.ready;
      // Espera a que Flutter cargue fuentes y assets perezosos y pide guardar
      // todo lo que usó esta primera carga.
      setTimeout(() => {
        const urls = [location.href.split('#')[0]].concat(
          performance.getEntriesByType('resource')
            .map((e) => e.name)
            .filter((u) => u.startsWith(location.origin)),
        );
        const worker = reg.active || navigator.serviceWorker.controller;
        if (worker) worker.postMessage({ type: 'precache', urls: urls });
      }, 4000);
    } catch (e) {
      console.warn('No se pudo registrar el service worker:', e);
    }
  });
}
