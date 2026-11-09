# Owner blockers

Things only Walker can do or buy. Surface them now, not at submission.

| Item | Why needed | Needed by | Status |
|---|---|---|---|
| Apple developer team in Xcode (free personal team at minimum) | Signing the app and its Finder extension so macOS will load them | First build | done — Apple Development identity installed (team 7ZT7J8C9QP; QGPDXDQ9SW is the certificate ID). Signed Debug build verified 2026-11-08. Developer ID only needed for public release |
| Find the hardware security key | V2 hardware-key unlock | Before V2 | open — Walker doesn't know where it is |
| Sign in to Xcode (Xcode ▸ Settings ▸ Accounts, Apple ID for team 7ZT7J8C9QP) | The app group and Keychain group (needed for signed Finder links and Touch ID) require a provisioning profile; Xcode has no account signed in, so signed builds stop at "No Accounts". Unsigned builds compile. | Before first launch | done 2026-11-08 — Walker signed in; Mac registered via -allowProvisioningDeviceRegistration; signed Debug and Release verified |
