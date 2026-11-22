# FinPet iOS integration

Open `FinPet.xcodeproj` using Xcode 16 or newer. The target supports iOS 17 and later. The app entry point in `FinPet/FinPetApp.swift` is a placeholder for the team's frontend.

Teammates can work on separate Git branches and open pull requests targeting `main`. Use the pull requests to review how the frontend, avatar, and other features connect to the iOS target. Keep feature branches focused so each can be merged and tested separately. Xcode is needed on the Mac that builds and runs the app.

## Login
`LoginView.swift` and `AuthService.swift` add username + password login and account creation against the backend (`/api/auth/register`, `/api/auth/login`, `/api/auth/me`), using the same `FinPetBackendURL`. The 7-day token and its expiry are stored in the Keychain. On launch a non-expired token skips login and is checked with `/api/auth/me`; a 401 returns to the login screen. "Log out" is in the Friends tab header. Avatars and animations stay per-device and are not tied to the account. New Swift files in `FinPet/` are picked up automatically (the project uses a synchronized folder), so `project.pbxproj` needs no edits.

## Avatar generation and animations
The app uploads the photo to the FinPet backend (`../backend`), which calls Gemini with the key from `backend/.env`. The app contains no API key. The backend URL is `FinPetBackendURL` in `Info.plist` (set it to the Northflank URL; see `../backend/README.md`. For a local server use `http://localhost:8000`, or your computer's LAN IP on a real device).

After the avatar comes back, the app requests four short animations (idle, wave, dance, sad/crying). Everything is saved in `Documents/FinPetAvatars/` (see `AvatarLibrary.swift`), so switching between avatars never regenerates anything, and "Create missing animations" only requests clips that are not on disk yet. The mascot stage on Home is tinted with the avatar's background color; tap the mascot to wave, long-press to dance. To show the sad animation, pass `mood: .cry` to `Pet` (for example when the user is over budget).
