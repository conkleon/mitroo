// Push notification → show to user
self.addEventListener('push', function(event) {
  const data = event.data ? event.data.json() : {};
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

// Fetch passthrough — offline caching added in a future iteration
self.addEventListener('fetch', function(event) {
  // no-op
});
