// Offline copy of the simulator. Every request is answered from the cache at once and refreshed
// behind it, so the app opens with no network and a new release shows on the next open.
const CACHE = "sprc-simulator";
const SHELL = ["simulator.html", "manifest.webmanifest", "icon-192.png", "icon-512.png", "icon-maskable.png",
  "https://cdn.jsdelivr.net/npm/fengari-web@0.1.4/dist/fengari-web.js"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));

self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  const fresh = fetch(e.request).then(async r => {
    if (r.ok || r.type === "opaque") await (await caches.open(CACHE)).put(e.request, r.clone());
    return r;
  });
  e.waitUntil(fresh.catch(() => {}));
  e.respondWith(caches.match(e.request, { ignoreVary: true }).then(hit => hit || fresh));
});
