var CACHE_NAME = 'mitroo-shell-v1';

// Shell assets to cache on install.
// If flutter build web splits main.dart.js into chunks, add them here.
var SHELL_ASSETS = [
  '/',
  '/index.html',
  '/main.dart.js',
  '/flutter.js',
  '/manifest.json',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
];

self.addEventListener('install', function(event) {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.addAll(SHELL_ASSETS);
    })
  );
});

self.addEventListener('activate', function(event) {
  event.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(
        keys.filter(function(k) { return k !== CACHE_NAME; })
            .map(function(k) { return caches.delete(k); })
      );
    }).then(function() { return self.clients.claim(); })
  );
});

// Push notification → show to user
self.addEventListener('push', function(event) {
  var data = event.data ? event.data.json() : {};
  event.waitUntil(
    self.registration.showNotification(data.title || 'Mitroo', {
      body: data.body || '',
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: data.tag || 'default',
      data: { route: data.route || '/' },
    })
  );
});

// Notification click → focus existing tab or open new window
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  var route = (event.notification.data && event.notification.data.route) || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(list) {
      var existing = list.find(function(c) {
        return c.url.includes(self.location.origin);
      });
      if (existing) {
        existing.focus();
        existing.postMessage({ type: 'navigate', route: route });
      } else {
        clients.openWindow(route);
      }
    })
  );
});

// Navigation requests (HTML) → cache-first with network fallback.
// All other requests pass through unchanged.
self.addEventListener('fetch', function(event) {
  if (event.request.mode === 'navigate') {
    event.respondWith(
      caches.match(event.request).then(function(cached) {
        return cached || fetch(event.request);
      })
    );
  }
});
