# JARVIS AI

A Flutter chat app with a black-and-blue interface, English/Tamil controls,
microphone input, text-to-speech, a few offline replies, and an optional
Gemini AI connection through a Cloudflare Worker.

## What works offline

- The chat screen opens without internet.
- Ask for `help`, `time`, or `date` for simple on-device replies.
- Text-to-speech uses voices installed on the phone. For Tamil speech without
  internet, install an offline Tamil voice in Android's text-to-speech settings.
- Speech recognition uses the phone's speech service. Whether it works offline
  depends on that service and its installed language packs.

Online AI replies need internet, a deployed Worker, and its URL in the app build.
The Gemini API key is kept as a Cloudflare Worker secret; it is never added to
the Flutter app or APK.

## Build an APK without Android Studio

You do not need Android Studio on your computer. GitHub Actions builds the
Android APK on a GitHub-hosted computer.

1. In GitHub, create a **new empty repository**. Do not select options to add a
   README, license, or `.gitignore` because this project already has files.
2. Open this project folder in VS Code. Open **Terminal → New Terminal**.
3. If this folder has not been connected to Git before, run:

   ```powershell
   git init
   git add .
   git status
   ```

   Check the list before continuing. `android/local.properties` is ignored
   because it contains a path specific to this computer.
4. Save the first version and connect it to your new GitHub repository. Replace
   `<YOUR-USERNAME>` with your GitHub username:

   ```powershell
   git commit -m "Create JARVIS AI app"
   git branch -M main
   git remote add origin https://github.com/<YOUR-USERNAME>/jarvis_ai.git
   git push -u origin main
   ```

   If Git asks who you are, set your commit name and email with
   `git config --global user.name "Your Name"` and
   `git config --global user.email "you@example.com"`. GitHub may ask you to
   sign in in a browser during the push.
5. On GitHub, open the repository's **Actions** tab. The **Build Android APK**
   workflow starts after the push. Wait for the run to finish with a green
   check mark.
6. Open that workflow run, scroll to **Artifacts**, and download
   **jarvis-ai-apk**. Unzip it to get `app-release.apk`.
7. Transfer the APK to your Android phone and open it to install. Android may
   ask you to allow installation from the app you used to open the file. This
   APK is for testing and direct installation; it is not signed for Play Store
   publishing.

The workflow runs Flutter tests and analysis before it builds the APK. Each new
push to `main` builds another downloadable APK.

## Optional: turn on Gemini AI chat

This app never asks for or stores a Gemini API key. A mobile app cannot keep a
provider key secret: someone could extract a key included in an APK. Instead,
the Cloudflare Worker sends requests to Gemini using a secret stored on
Cloudflare's servers.

1. Create a Gemini API key in Google AI Studio.
2. In the Cloudflare dashboard, create and deploy a Worker. Use the code in
   [`cloudflare/src/index.js`](cloudflare/src/index.js).
3. In the Worker settings, add a **secret** named `GEMINI_API_KEY` and paste
   the Gemini key as its value. Do not put the key in Flutter, GitHub source
   files, or a GitHub Actions variable.
4. Copy the Worker URL and add `/chat` to the end. For example:
   `https://your-worker-name.your-account.workers.dev/chat`.
5. In your GitHub repository, open **Settings → Secrets and variables →
   Actions → Variables**, add a repository variable named `AI_PROXY_URL`, and
   set its value to that Worker URL. This URL is not the API key.
6. Push a new commit (or run **Build Android APK** from Actions) to build an
   APK configured to use the Worker.

To try it locally, run this from the project folder, replacing the example URL:

```powershell
flutter run --dart-define=AI_PROXY_URL=https://your-worker-name.your-account.workers.dev/chat
```

The proxy URL is public, not a password. Before sharing the app, set usage
limits or rate limiting for the Worker and set appropriate quotas/budget
notifications for your Gemini project. Otherwise, other people who obtain the
URL could use your Worker and consume your API quota.

## Requirements and troubleshooting

- Flutter and VS Code are enough to edit this project. The Android SDK is not
  installed on this computer right now, so local Android builds are unavailable;
  that does not prevent the GitHub Actions APK build.
- On Windows, Flutter reported that Developer Mode is needed for some plugin
  operations. This is only needed if you want to run the Flutter app locally;
  GitHub's Linux build does not use this Windows setting.
- The microphone asks for permission. Speech recognition can depend on your
  Android speech service and may need internet.
- Tamil speech output depends on an installed Tamil text-to-speech voice.
