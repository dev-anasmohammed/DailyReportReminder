# Gmail setup and sending

Daily Report replies directly in a Gmail conversation on Windows and macOS. The app does not ship with a shared Google client or account credentials.

## One-time Google setup

1. Open https://console.cloud.google.com/ and create/select a project.
2. Enable **Gmail API** in APIs & Services → Library.
3. In Google Auth Platform, configure Branding with the application name and your support/developer email.
4. For a personal Gmail account, select an External audience. During testing, add your Gmail address as a test user.
5. Under Data Access, add only:
   - `https://www.googleapis.com/auth/gmail.metadata`
   - `https://www.googleapis.com/auth/gmail.send`
6. Create an OAuth client with application type **Desktop app**, and download its JSON.
7. In Daily Report → Settings → Configure Gmail, import that JSON and click Connect Gmail. Sign in in your system browser and allow both permissions.
8. Choose your report conversation. The picker loads recent conversation headers, supports filtering the loaded subjects/senders, and offers Load more for older conversations. It does not download email bodies or use Gmail search, because the metadata scope does not allow search queries.
9. Enable Reply all by default if your reporting workflow requires everyone on the original conversation.

The OAuth client must be Desktop app, not Web application. The app uses a random loopback port on 127.0.0.1, PKCE, a one-time random state, and a five-minute sign-in timeout. You can cancel sign-in in the app.

Google may show an unverified-app notice for a developer testing their own OAuth project. Public distribution with sensitive/restricted Gmail permissions has additional Google verification requirements. Follow Google's requirements before distributing a shared OAuth client. Workspace administrators may block third-party apps. Google testing-mode credentials can require periodic reconnection.

Official references:
- https://developers.google.com/identity/protocols/oauth2/native-app
- https://developers.google.com/workspace/gmail/api/auth/scopes
- https://developers.google.com/workspace/gmail/api/guides/threads

## Daily use

1. Prepare/edit your report as usual.
2. Click **Preview & send**. If Gmail is not configured, this opens setup; return to the report and click again after configuration.
3. Confirm the conversation subject, From account, To, CC, and the formatted report. Reply/Reply all changes suggested recipients; To and CC remain editable.
4. Click **Send reply**. The subject stays the conversation's subject. The outgoing message includes the Gmail thread ID, In-Reply-To, and References headers, plus both HTML and plain-text versions of the report.
5. Gmail confirmation is recorded locally, the report is marked completed, and today's reminders stop. A second send for the same date is blocked.

When your last message is your own report, recipients are suggested from the most recent received message instead of replying to yourself. If the thread only contains your sent messages, the last message's recipients are used. Always review recipients, especially if you use Gmail aliases.

If the network fails after a send request, the app cannot assume the message failed. It retains a pending attempt, preserves your draft, and does not automatically retry. On the next attempt, it checks the selected conversation for the outgoing Message-ID. If no matching sent message is found, it asks you to check Gmail Sent before explicitly allowing another attempt.

## Storage and verification

OAuth configuration and tokens are stored using Flutter Secure Storage (macOS Keychain and the Windows secure storage implementation). Account/thread selection and send confirmations are stored locally with app settings. Disconnect removes local tokens; revoke Google access separately in your Google Account if desired.

Do not commit downloaded OAuth JSON, tokens, or real email fixtures. No account token, Google client credential, or real email message is included in this repository. Tests use fake accounts and mocked API responses, including a local-only OAuth callback. A real Google sign-in and a test-thread reply still need to be verified with your own OAuth client before relying on the feature for work.

For Windows development, Flutter Secure Storage also requires Visual Studio C++ ATL. macOS needs the included Keychain Sharing entitlement and normal application signing for distribution.
