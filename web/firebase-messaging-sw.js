// The Trellis — Firebase Cloud Messaging service worker.
//
// Required for web push specifically: a notification that arrives while no
// tab is focused has to be handled outside the page's own JS context, which
// is what this file (loaded by the browser at /firebase-messaging-sw.js) is
// for. Android/iOS don't need this — only the web target does.
//
// Fill in firebaseConfig below with the *same* values that
// `flutterfire configure` writes into lib/firebase_options.dart's `web`
// FirebaseOptions (apiKey, appId, messagingSenderId, projectId) — these are
// public, client-side identifiers, not secrets; safe to commit alongside
// the rest of this repo, same as lib/firebase_options.dart itself.

importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'REPLACE_ME',
  authDomain: 'REPLACE_ME.firebaseapp.com',
  projectId: 'REPLACE_ME',
  storageBucket: 'REPLACE_ME.appspot.com',
  messagingSenderId: 'REPLACE_ME',
  appId: 'REPLACE_ME',
});

const messaging = firebase.messaging();

// Optional: customize how a background push renders. Without this handler,
// the browser still shows the notification/title/body sent from
// push-notification-engine using its defaults, which is fine as a start.
messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification ?? {};
  if (title) {
    self.registration.showNotification(title, { body, data: payload.data });
  }
});
