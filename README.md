# Dropit - Local Wi-Fi Two-Way File Transfer for macOS

A native macOS application that lets you seamlessly share files with any device (iPhone, Android, Windows, Mac, Linux) over your local Wi-Fi network.

**The receiver does not need to install any app** — scanning a QR code opens a web dashboard where they can download multiple files shared by your Mac and **upload files/photos directly back to your Mac**!

---

## What's New in Dropit

- 🔄 **Persistent Two-Way Session**: Devices stay connected indefinitely after transfers complete. No server disconnects or re-scanning needed to send more files.
- 📤 **Bidirectional Transfers (Receiver → Mac)**: Connected devices can select photos, videos, and documents and stream them directly into your Mac's `~/Downloads/Dropit/` folder.
- 📦 **Multi-File Transfers**:
  - **Mac → Devices**: Drag & drop multiple files at once or add more files anytime. The receiver's screen updates in real time with an individual download option or a **"Download All"** batch button.
  - **Devices → Mac**: Select multiple files simultaneously on mobile devices and track live upload progress.
- 🔁 **Resumable Transfers**: Interrupted downloads and uploads continue where they stopped instead of starting over. Downloads use HTTP range requests (`206 Partial Content`), and uploads are chunked with the partial file kept on both sides.
- 🗂 **Browse Mac Folders**: Devices get a file browser for the folders you share. They can navigate folders, read files, create folders, rename, delete, and pull files onto themselves. Path traversal outside the shared folders is rejected.
- 📱 **Browse Phone Folders (Android)**: With the companion app, the Mac can browse the phone's storage instead — read, write, create, rename, delete, and copy files in both directions.
- 🔐 **Pairing Codes You Can Revoke**: Every QR code carries a one-time session token. Hit **"Refresh Code"** to issue a new token — old codes stop admitting new devices while devices already connected keep working.
- 🔒 **Optional HTTPS**: Dropit generates its own self-signed CA certificate (RSA 2048, with the Mac's LAN addresses in the certificate) and can serve the whole session over TLS. Plain HTTP remains the default.
- ⚡ **Live Synchronization**: Real-time sync ensures that when the Mac user adds or removes files, the receiver's screen updates automatically without reloading.
- 📊 **Real-Time Progress on Both Screens**: Live speed (`MB/s`), progress percentage, bytes transferred, and remaining time on both your Mac and the connected device.
- 📂 **One-Click Finder Access**: Quick "Downloads" button on the Mac toolbar and per-file "Finder" buttons to locate received files immediately.

---

## A note on HTTPS and phones

HTTPS is **off by default, and that is deliberate.** A self-signed certificate produces a
warning on devices, and iOS Safari will not let you tap past it — so making HTTPS the default
would stop the primary flow (scan a QR code on an iPhone and it just works) from working at all.

How it behaves:

- The QR code and share link use **plain HTTP by default**, so every device connects with no setup.
- Turn on **"Use HTTPS (encrypted)"** in the QR Code sheet to switch the QR code and link to HTTPS.
- To make HTTPS warning-free, save the certificate from the app and install it once as a trusted
  root on the device:
  - **iOS/iPadOS**: Settings → General → VPN & Device Management → install the profile, then
    Settings → General → About → Certificate Trust Settings → enable full trust.
  - **macOS**: double-click the `.crt` file → Keychain Access → set to **Always Trust**.
  - **Android**: Settings → Security → Encryption & credentials → Install a certificate → CA
    certificate.
- If the HTTPS listener cannot start, the app simply does not offer it and keeps serving HTTP.

Regardless of scheme, everything stays on your local network — the server binds to all
interfaces but is only reachable from your LAN.

---

## How to Run

### Quick Launch
To build (if needed) and launch the app directly:
```bash
./run.sh
```

### Build Disk Image (DMG) Installer
To package the app into a compressed macOS DMG installer with an Applications shortcut:
```bash
./make_dmg.sh
```
This generates:
```
Dropit.dmg
```
Double-click `Dropit.dmg` to open the installer and drag **Dropit** directly into your **Applications** folder!

### Manual App Build
To recompile only the standalone macOS `.app` bundle:
```bash
./build.sh
```
The compiled bundle will be located at:
```
Dropit.app
```
You can move `Dropit.app` into `/Applications` or launch it directly with:
```bash
open Dropit.app
```

---

## User Workflow

### 1. Start a Session on Mac
- **Option A**: Drag and drop one or more files directly onto the **Dropit** window.
- **Option B**: Click **"Choose Files..."** to pick multiple files.
- **Option C**: Click **"Start Empty Session"** to create a hub and let your phone upload files to your Mac first.

### 2. Connect Any Device
- The app generates a crisp QR code and local URL (e.g. `http://192.168.x.x:52169/`).
- Scan with your iPhone or Android camera to open the **Dropit** web dashboard.
- Your Mac immediately shows: *"Connected (1 device)"*.

### 3. Transfer Files
- **To Receive on Device**: Tap **"Download"** on any file or tap **"Download All"** to download all shared files in sequence. If a transfer drops, tapping download again resumes it rather than restarting.
- **To Send from Device to Mac**: Switch to the **"Send to Mac"** tab on your phone, pick photos or files, and tap **"Send to Mac"**. Uploads are chunked, so an interrupted upload resumes from the last completed chunk.
- Your Mac saves them to `~/Downloads/Dropit/`, plays a notification chime, and shows them in the **"Received on Mac"** list.

### 4. Browse Mac Folders
- Switch to the **"Browse Mac"** tab on your device to browse the folders the Mac is sharing (your home folder by default).
- Tap a folder to open it, **Get** to save a file to the device, and use **Rename** / **Del** to manage items. **+ Folder** creates a new folder.
- Requests for anything outside the shared folders are rejected.

### 5. Stay Connected
- The session remains open. Drag more files into the Mac app at any time, or send more photos from your phone!
- Hit **"Refresh Code"** on the Mac to revoke previously issued QR codes. Devices already connected are unaffected.
- When you are done, click **"End Session"** on your Mac.

---

## Android app (Dropit Phone)

`DropitPhone.apk` in this folder is a companion app that lets the **Mac browse the phone's
storage**. The web dashboard can only ever read the Mac, so this direction needs a real app.

```bash
./build_apk.sh              # debug APK -> DropitPhone.apk
./build_apk.sh --release    # release APK (reuses the debug keystore)
```

Building needs a JDK 17 and the Android SDK. The script picks these up from
`~/Library/Android/jdk17` and `~/Library/Android/sdk` if present, otherwise from
`JAVA_HOME` / `ANDROID_HOME`.

### How it works

1. Start a session on the Mac.
2. Open **Dropit Phone** and tap **Share a folder...** to pick the folders to expose.
3. The phone finds the Mac by itself — it sends a UDP broadcast probe and the Mac replies
   with its port and session token. No typing, no QR scanning.
4. The phone registers and receives a **random per-device secret**. Every later request
   carries that secret, so another machine on the same Wi-Fi cannot browse the phone even
   though it can reach the phone's port.
5. On the Mac, open **Devices** and press **Storage** on the phone to browse it.

Providers that stop checking in for 90 seconds are dropped automatically.

### Storage access on Android

Two models, both supported:

- **Folder access (default).** Uses the system folder picker, so the app needs no broad
  storage permission. Works on every supported Android version. The Mac can only see the
  folders you chose.
- **All files access (opt-in).** Toggle it in the app and grant the permission in Settings
  to let the Mac reach the rest of internal storage, not just the folders you picked.
  Android 11+ only. Apps using this are restricted on the Play Store, which does not affect
  a sideloaded APK.

The phone serves its own small HTTP server on an OS-assigned port; the Mac talks to it
directly and never proxies arbitrary third parties.

---

By default devices can browse your home folder. Sensitive locations are never exposed, even
inside it: `.ssh`, `.gnupg`, `.aws`, `.azure`, `.kube`, `.docker`, `.config`,
`.password-store`, `Library/Keychains`, and `Library/Application Support`.

Every request path is resolved through symlinks and checked against the allowed roots, so
`..` segments and symlinks cannot be used to escape.

---

## Project Structure

```
file transfer/
├── Dropit.app/                       # Standalone compiled macOS Application bundle
├── Sources/
│   ├── Main/
│   │   └── main.swift                # AppKit bootstrap & SwiftUI window hosting
│   ├── Models/
│   │   └── AppState.swift            # Central state store, session token, URL/TLS wiring
│   ├── Network/
│   │   ├── HTTPServer.swift          # Socket listener, routing, pairing token, device registry
│   │   ├── HTTPServer+Transfers.swift # Range/206 downloads, chunked resumable uploads
│   │   ├── HTTPServer+FileSystem.swift# Folder listing, read/write, mkdir, rename, delete
│   │   ├── ClientConnection.swift    # Per-connection read/write with deadlines
│   │   ├── SecureConnectionBridge.swift # TLS connection bridged to a blocking stream
│   │   ├── TLSCertificateManager.swift  # Self-signed CA generation, keychain storage, export
│   │   ├── DER.swift                 # ASN.1 helpers used to build and sign the certificate
│   │   ├── FileSystemBridge.swift    # Root-confined path resolution and file operations
│   │   ├── DeviceProviderRegistry.swift  # Phones registered as storage providers
│   │   ├── DeviceStorageClient.swift # Client for a phone's own /fs API
│   │   ├── DiscoveryResponder.swift  # UDP responder so phones can find this Mac
│   │   ├── NetworkHelper.swift       # getifaddrs IPv4 interface discovery
│   │   └── FileMIME.swift            # MIME type and SF Symbol resolver
│   ├── QRCode/
│   │   └── QRCodeGenerator.swift     # CoreImage CIQRCodeGenerator with retina scaling
│   ├── Views/
│   │   ├── ContentView.swift         # Root container & navigation
│   │   ├── DropZoneView.swift        # Drag & drop setup & file picker
│   │   ├── SessionHubView.swift      # Persistent two-way hub (shared, received, history, QR)
│   │   └── DeviceStorageView.swift   # Browse a phone's storage from the Mac
│   └── Web/
│       └── ReceiverWebTemplate.swift # Interactive receiver web app
├── Resources/
│   └── Info.plist                    # App bundle property list
├── Tests/
│   └── test_transfer.swift           # Automated end-to-end multi-file and upload tests
├── android/                          # Dropit Phone (Android companion app)
│   └── app/src/main/java/com/dropit/phone/
│       ├── MainActivity.kt           # Folder sharing + all-files access toggle
│       ├── StorageBridge.kt          # SAF + all-files access, opaque path handling
│       ├── StorageHttpServer.kt      # Built-in HTTP server exposing /fs
│       └── MacLink.kt                # UDP discovery, registration, secret storage
├── DropitPhone.apk                   # Prebuilt debug APK
├── build.sh                          # Build script producing Dropit.app
├── build_apk.sh                      # Build script producing the Android APK
├── run.sh                            # Launch helper
└── README.md
```
