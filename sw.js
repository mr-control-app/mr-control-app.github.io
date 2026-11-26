// Mr. Control – funcionamento sem internet.
// Guarda só os arquivos do próprio app (página, ícones e o leitor de Excel). Os dados das fazendas ficam
// no IndexedDB do app e as chamadas ao banco (POST) nunca passam por aqui.
const CACHE = "mrcontrol-v4";
const ARQUIVOS = ["./", "index.html", "config.js", "manifest.webmanifest", "favicon.png", "icone-192.png", "icone-512.png", "apple-touch-icon.png",
  "https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => Promise.all(ARQUIVOS.map(u => c.add(u).catch(() => null)))).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k.startsWith("mrcontrol-") && k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener("fetch", e => {
  const r = e.request;
  if (r.method !== "GET") return;                                   // banco de dados: sempre direto
  const u = new URL(r.url);
  const proprio = u.origin === self.location.origin;
  const lib = u.hostname === "cdnjs.cloudflare.com" || u.hostname.endsWith("fonts.googleapis.com") || u.hostname.endsWith("fonts.gstatic.com");
  if (!proprio && !lib) return;
  // rede primeiro (versão nova quando houver internet); sem internet, a cópia guardada
  e.respondWith(fetch(r).then(resp => {
    if (resp && (resp.ok || resp.type === "opaque")) { const cp = resp.clone(); caches.open(CACHE).then(c => c.put(r, cp)); }
    return resp;
  }).catch(() => caches.match(r).then(m => m || (r.mode === "navigate" ? caches.match("index.html") : Response.error()))));
});
