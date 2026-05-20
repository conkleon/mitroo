var CACHE_VERSION = 'v2';
var CACHE_NAME = 'mitroo-shell-' + CACHE_VERSION;
var IMAGE_CACHE = 'mitroo-images-' + CACHE_VERSION;
var API_CACHE = 'mitroo-api-' + CACHE_VERSION;

var MAX_API_CACHE_ENTRIES = 50;

var SHELL_ASSETS = [
  '/',
  '/index.html',
  '/main.dart.js',
  '/flutter.js',
  '/flutter_bootstrap.js',
  '/flutter_service_worker.js',
  '/manifest.json',
  '/version.json',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
];

// Cache names owned by the Flutter-generated service worker.
// The manual SW must NOT delete these.
var FLUTTER_CACHES = ['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest'];

var PRESERVED_CACHES = FLUTTER_CACHES.concat([CACHE_NAME, IMAGE_CACHE, API_CACHE]);

self.addEventListener('install', function(event) {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.addAll(SHELL_ASSETS).catch(function(err) {
        console.warn('mitroo-shell: some assets could not be cached', err);
      });
    })
  );
});

self.addEventListener('activate', function(event) {
  event.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(
        keys.filter(function(k) {
          return PRESERVED_CACHES.indexOf(k) === -1;
        }).map(function(k) {
          return caches.delete(k);
        })
      );
    }).then(function() { return self.clients.claim(); })
  );
});

// Push notification -> show to user
self.addEventListener('push', function(event) {
  var data = {};
  try { data = event.data ? event.data.json() : {}; } catch(e) {}
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

// Notification click -> focus existing tab or open new window
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

self.addEventListener('fetch', function(event) {
  if (event.request.method !== 'GET') return;

  var url = new URL(event.request.url);

  // Only handle same-origin requests
  if (url.origin !== self.location.origin) return;

  var path = url.pathname;

  // Navigation: cache-first for instant offline startup, network fallback when not cached.
  if (event.request.mode === 'navigate') {
    event.respondWith(
      caches.match('/index.html').then(function(cached) {
        return cached || fetch(event.request).catch(function() {
          return caches.match('/index.html');
        });
      })
    );
    return;
  }

  // Shell assets: stale-while-revalidate — serve from cache immediately for speed,
  // then update the cache entry in the background.
  var assetPath = path.replace(/^\//, '') || '/';
  var isShellAsset = SHELL_ASSETS.some(function(a) {
    return a === '/' + assetPath || a === path;
  });

  if (isShellAsset) {
    event.respondWith(
      caches.open(CACHE_NAME).then(function(cache) {
        return cache.match(event.request).then(function(cached) {
          var networkFetch = fetch(event.request).then(function(response) {
            if (response && response.ok) {
              cache.put(event.request, response.clone());
            }
            return response;
          });
          return cached || networkFetch;
        });
      })
    );
    return;
  }

  // Uploaded images: network-first, cache fallback for offline
  if (path.startsWith('/uploads/')) {
    event.respondWith(
      fetch(event.request).then(function(response) {
        if (response && response.ok) {
          var clone = response.clone();
          caches.open(IMAGE_CACHE).then(function(cache) {
            cache.put(event.request, clone);
          });
        }
        return response;
      }).catch(function() {
        return caches.match(event.request);
      })
    );
    return;
  }

  // API GET: network-first, cache fallback for offline, capped at MAX_API_CACHE_ENTRIES
  if (path.startsWith('/api/')) {
    event.respondWith(
      fetch(event.request).then(function(response) {
        if (response && response.ok) {
          var clone = response.clone();
          caches.open(API_CACHE).then(function(cache) {
            cache.put(event.request, clone);
            cache.keys().then(function(keys) {
              if (keys.length > MAX_API_CACHE_ENTRIES) {
                cache.delete(keys[0]);
              }
            });
          });
        }
        return response;
      }).catch(function() {
        return caches.match(event.request);
      })
    );
    return;
  }
});
