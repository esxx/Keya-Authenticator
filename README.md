# Keya Authenticator

A privacy-first, open-source two-factor authentication app for iOS. Your secrets never leave your device.

## Features

- **No cloud, no accounts, no tracking** — fully offline, zero network calls
- **Hardware-backed security** — secrets stored in iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **PIN + Biometrics** — Face ID / Touch ID with configurable auto-lock grace period
- **TOTP & HOTP** — SHA-1 / SHA-256 / SHA-512, 6 or 8 digit codes (RFC 6238 / RFC 4226)
- **QR code scanning** — add tokens by camera, photo library, or manual entry
- **Import** — Aegis, 2FAS, andOTP, Raivo, LastPass, Google Authenticator transfer QR, `otpauth://` URI files
- **Export** — plaintext JSON, AES-256-GCM encrypted JSON, or Google Authenticator-compatible migration QR codes
- **AutoFill** — fill one-time codes from the iOS keyboard in Safari and any app; enable in Settings → Passwords
- **Link-based setup** — tap any `otpauth://` link to open the pre-filled Add Token form directly
- **Next-code preview** — upcoming code shown early so you never race the expiry timer
- **Favorites, groups & search** — organise and find codes instantly
- **Auto-lock** — configurable from immediately to 1 minute
- **Privacy overlay** — covers the app switcher snapshot

## Languages

English · French · Japanese · Korean · Portuguese (Brazil) · Spanish (Latin America)

## Requirements

| | |
|---|---|
| Platform | iOS 18.0+ |
| Xcode | 16.0+ |
| Swift | 5.9+ |
| Dependencies | None (Apple frameworks only) |

## Building

```bash
git clone https://github.com/esxx/Keya-Authenticator.git
cd keya-authenticator
open "Keya Authenticator.xcodeproj"
```

1. Select your development team in **Signing & Capabilities**
2. Choose a simulator or connected device
3. **⌘R** to build and run

No CocoaPods, no SPM packages, no third-party code.

## Project Structure

```
CredentialProviderExtension/
├── CredentialProviderViewController.swift  # ASCredentialProviderViewController — AutoFill entry point
├── CredentialProviderExtension.entitlements
└── Info.plist
Keya Authenticator/
├── App/
│   ├── AppEntry.swift               # @main entry point, app-state machine, PIN setup
│   └── AppDelegate.swift
├── Models/
│   ├── Token.swift                  # TOTP/HOTP token model
│   ├── Algorithm.swift              # SHA-1/256/512 enum
│   ├── AppSettings.swift            # UserDefaults-backed preferences
│   └── TokenError.swift
├── ViewModels/
│   ├── AppViewModel.swift           # App coordinator — state machine & lifecycle
│   ├── AuthenticationViewModel.swift
│   ├── MainContentViewModel.swift   # Token list, search, grouping, favorites
│   ├── AddTokenViewModel.swift      # Token creation, QR/gallery/file import
│   ├── EditTokenViewModel.swift
│   ├── ExportImportViewModel.swift  # Backup/restore operations
│   ├── QRExportViewModel.swift      # Single-token QR export
│   └── SettingsViewModel.swift
├── Views/
│   ├── AuthenticationView.swift     # PIN/biometric lock screen
│   ├── MainContentView.swift        # Token list with sections and search
│   ├── AddTokenView.swift           # Live QR scanner + import methods
│   ├── ManualTokenEntryView.swift   # Manual secret entry form
│   ├── EditTokenView.swift
│   ├── SettingsView.swift           # Top-level settings list
│   ├── AppLockSettingsView.swift    # PIN + biometric configuration
│   ├── ExportImportView.swift       # Export (JSON / encrypted / QR)
│   ├── QRExportView.swift           # Single-token QR display
│   └── Components/
│       ├── TokenRowView.swift       # Per-row TOTP/HOTP display with TimelineView
│       ├── QRScannerView.swift
│       ├── PINVerifySheet.swift
│       └── PINSetupSheet.swift      # Set / change PIN flow
├── Services/
│   ├── TokenStore.swift             # In-memory store backed by Keychain
│   ├── KeychainManager.swift        # Shared constants and Keychain helpers
│   ├── KeychainManager+Tokens.swift # Token CRUD
│   ├── KeychainManager+PIN.swift    # PIN hash, PBKDF2, lockout state
│   ├── KeychainManager+Biometric.swift # Biometric baseline + security settings
│   ├── AuthenticationManager.swift  # PIN + biometric auth with rate limiting
│   ├── OTPGenerator.swift           # TOTP/HOTP code generation (RFC 6238/4226)
│   ├── EncryptionService.swift      # AES-256-GCM encrypt/decrypt, PBKDF2 key derivation
│   ├── ExportImportManager.swift    # JSON export, import dispatch, encrypted backup
│   └── TokenImportParser.swift      # One adapter per import format (Aegis, 2FAS, …)
└── Utils/
    ├── Constants.swift              # Shared with the AutoFill extension target
    ├── BrandKeyword.swift           # Host → brand keyword (shared with extension)
    ├── QRCodeGenerator.swift
    ├── ClipboardManager.swift
    ├── ScreenCaptureGuard.swift
    ├── ServiceIconResolver.swift
    └── Extensions/
        ├── String+Base32.swift      # Base32 decode, isValidOTPSecret
        ├── String+OTPAuth.swift     # otpauth:// and migration URI parsing
        └── Data+OTP.swift           # Base32 encode
```

## Architecture

MVVM with a clear boundary rule:

- **Views** — observe state, delegate all actions to ViewModels, never touch services directly
- **ViewModels** — own all business logic, I/O, and state; signal dismiss intent via `shouldDismiss`
- **Models** — plain data structures (Token, AppSettings)
- **Services** — Keychain, OTP generation, import/export; injected into ViewModels

Navigation uses the `shouldDismiss: Bool` pattern — ViewModels set the flag, Views observe it with `.onChange` and call `dismiss()`.

## Security

| Property | Detail |
|---|---|
| Secret storage | iOS Keychain · `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| PIN storage | PBKDF2-HMAC-SHA256 · 100 000 iterations · 32-byte random salt |
| Encrypted backup | AES-256-GCM · PBKDF2-derived key |
| OTP generation | HMAC-SHA1/256/512 · RFC 6238 (TOTP) / RFC 4226 (HOTP) |
| Network access | **None** — no entitlements, no requests |
| Analytics / crash reporting | **None** |
| External dependencies | **None** |

Tokens are stored as individual Keychain items. Locking the app clears them from memory; they reload from Keychain on the next successful unlock.

**AutoFill and the app PIN:** the AutoFill extension is gated by system authentication (Face ID / Touch ID or the device passcode), not by the app PIN — so anyone who can unlock the device can fill codes via AutoFill. This is a deliberate trade-off following Apple's credential-provider pattern; the app PIN protects the in-app vault UI, while the device passcode remains the true security boundary for the secrets themselves.

## Import Compatibility

| Source | Format |
|---|---|
| Google Authenticator | `otpauth-migration://` QR code (protobuf) |
| Aegis Authenticator | JSON export |
| 2FAS | JSON export |
| andOTP | JSON export |
| Raivo OTP | JSON export |
| LastPass Authenticator | JSON export |
| Any app | `otpauth://` URI text file (one per line) |
| Keya Authenticator | JSON backup (plaintext or encrypted) |

## Export Formats

| Format | Detail |
|---|---|
| JSON | Plaintext backup — restore in Keya Authenticator |
| Encrypted JSON | AES-256-GCM — password required |
| Migration QR | `otpauth-migration://` — compatible with Google Authenticator, Aegis, 2FAS |

## License

GPL v3 — see [LICENSE](LICENSE)

© 2026 Eldar SHAIDULLIN

## Links

- [About](https://esxx.github.io/Keya-Authenticator/)
- [Privacy Policy](https://esxx.github.io/Keya-Authenticator/privacy.html)
- [Terms of Service](https://esxx.github.io/Keya-Authenticator/terms.html)
- [FAQ](https://esxx.github.io/Keya-Authenticator/faq.html)

---

*Keya Authenticator never connects to the internet. Your 2FA secrets stay on your device.*
