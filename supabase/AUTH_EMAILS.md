# Sign-in emails (Supabase Auth)

Supabase sends these, through Resend (custom SMTP — Authentication → Emails →
SMTP Settings: host `smtp.resend.com`, port 465, user `resend`, sender
`no-reply@unhinderedlives.com`). Templates are edited in the dashboard:
**Authentication → Emails → Templates**.

## Reset Password

The app's "Forgot your password?" (lib/screens/reset_password_screen.dart)
asks for a **code**, not a link — a link would have to open the app on the
same phone. The template MUST include `{{ .Token }}`, or the email arrives
with nothing to type in.

**Subject**

```
Your code to reset your Trellis password
```

**Message body** (HTML)

```html
<div style="font-family: Georgia, 'Times New Roman', serif; color: #1E3A2B; max-width: 480px;">
  <h2 style="font-weight: normal;">Reset your password</h2>
  <p>Enter this code in The Trellis, along with your new password:</p>
  <p style="font-size: 28px; letter-spacing: 6px; font-weight: bold; color: #1E3A2B;">{{ .Token }}</p>
  <p>The code works once and expires in an hour.</p>
  <p style="color: #6b6b6b; font-size: 13px;">If you didn't ask to reset your password, you can ignore this email; nothing has changed.</p>
  <p style="color: #B8860B;">The Trellis · Unhindered Lives</p>
</div>
```

Check after saving: tap "Forgot your password?" in the app with your own
email; the email should show a code (6 digits by default — Authentication →
Providers → Email → "Email OTP Length" sets it), from
no-reply@unhinderedlives.com.
