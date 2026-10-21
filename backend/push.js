// push.js
// A plain (non-router) module for sending push notifications via FCM,
// following the same "genuinely new cross-cutting concern gets its own
// small module" precedent as notifications.js/email.js. The only caller is
// notifications.js's createNotification, which covers every notification
// type in the app for free (see that file's header comment).
//
// Unlike email.js, this uses the firebase-admin package rather than a bare
// fetch — FCM's HTTP v1 API needs a signed OAuth2 exchange from service
// account credentials, which firebase-admin handles; a real dependency is
// warranted here, same "one dependency per genuinely new concern" bar the
// rest of this backend holds to.
//
// Requires FCM_SERVICE_ACCOUNT_JSON (the full service account JSON as a
// single-line string) in .env. Sending is a no-op (logged, not thrown) if
// it's missing, or if the target user has no fcm_token — same fail-soft
// posture as email.js/createNotification, so a push failure or missing
// config never blocks the action that triggered the notification.

// firebase-admin v12+ restructured its API into submodules — the old
// namespaced form (admin.credential.cert, admin.messaging(app)) silently
// doesn't exist on the root import anymore, so this uses the modular
// imports instead (see firebase-admin/app and firebase-admin/messaging).
const { initializeApp, cert } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');

let app = null;
const serviceAccountJson = process.env.FCM_SERVICE_ACCOUNT_JSON;

if (serviceAccountJson) {
  try {
    app = initializeApp({
      credential: cert(JSON.parse(serviceAccountJson)),
    });
  } catch (err) {
    console.error('Failed to initialize firebase-admin — push notifications disabled:', err);
  }
} else {
  console.error('FCM_SERVICE_ACCOUNT_JSON is not configured — push notifications disabled.');
}

async function sendPushNotification({ token, title, body, data = {} }) {
  if (!app || !token) return false;

  try {
    await getMessaging(app).send({
      token,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data)
          .filter(([, v]) => v != null)
          .map(([k, v]) => [k, String(v)])
      ),
    });
    return true;
  } catch (err) {
    console.error('FCM send error:', err);
    return false;
  }
}

module.exports = { sendPushNotification };
