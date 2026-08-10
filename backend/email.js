// email.js
// A plain (non-router) module for sending transactional email, following the
// same "genuinely new cross-cutting concern gets its own small module"
// precedent as notifications.js/privacy.js/audit.js. The only caller today is
// authRoutes.js's password-reset flow, but this is deliberately not folded
// into that file so a second caller (e.g. a future signup-verification email)
// doesn't have to duplicate the HTTP plumbing.
//
// Uses Resend's plain HTTP API via the built-in fetch — no SDK dependency,
// same "one dependency per genuinely new concern" bar the rest of this
// backend holds to. Requires RESEND_API_KEY and RESEND_FROM_ADDRESS in
// .env, alongside the existing JWT_SECRET/DB settings (see CLAUDE.md);
// sending is a no-op (logged, not thrown) if either is missing, so local
// dev without email creds doesn't crash routes that call this — same
// fail-soft posture as createNotification.

const RESEND_API_KEY = process.env.RESEND_API_KEY;
const RESEND_FROM_ADDRESS = process.env.RESEND_FROM_ADDRESS;

async function sendEmail({ to, subject, html, text }) {
  if (!RESEND_API_KEY || !RESEND_FROM_ADDRESS) {
    console.error(
      'sendEmail called but RESEND_API_KEY/RESEND_FROM_ADDRESS are not configured — email not sent.'
    );
    return false;
  }

  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: RESEND_FROM_ADDRESS,
        to: [to],
        subject,
        html,
        text,
      }),
    });
    if (!response.ok) {
      const body = await response.text();
      console.error('Resend send failed:', response.status, body);
      return false;
    }
    return true;
  } catch (err) {
    console.error('Resend send error:', err);
    return false;
  }
}

async function sendPasswordResetEmail(to, code) {
  return sendEmail({
    to,
    subject: 'Your PlayMySet password reset code',
    text: `Your PlayMySet password reset code is ${code}. It expires in 15 minutes. If you didn't request this, you can ignore this email.`,
    html: `<p>Your PlayMySet password reset code is:</p><p style="font-size:28px;font-weight:bold;letter-spacing:4px;">${code}</p><p>It expires in 15 minutes. If you didn't request this, you can ignore this email.</p>`,
  });
}

module.exports = { sendEmail, sendPasswordResetEmail };
