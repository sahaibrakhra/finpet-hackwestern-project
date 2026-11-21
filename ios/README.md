# FinPet iOS integration

Open `FinPet.xcodeproj` using Xcode 16 or newer. The target supports iOS 17 and later. The app entry point in `FinPet/FinPetApp.swift` is a placeholder for the team's frontend.

Teammates can work on separate Git branches and open pull requests targeting `main`. Use the pull requests to review how the frontend, avatar, and other features connect to the iOS target. Keep feature branches focused so each can be merged and tested separately. Xcode is needed on the Mac that builds and runs the app.

## Avatar generation
The app uploads the photo to the FinPet backend (`../backend`), which calls Gemini with the key from `backend/.env` and returns the avatar. The backend URL is `FinPetBackendURL` in `Info.plist` (default `http://localhost:8000`; use your computer's LAN IP on a real device). The app contains no API key.
