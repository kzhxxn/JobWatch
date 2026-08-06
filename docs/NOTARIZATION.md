# Notarization (optional)

By default, release DMGs are **ad-hoc signed** — they work, but macOS Gatekeeper warns
on first open. On macOS 15+ the user must go to System Settings → Privacy & Security →
"Open Anyway" (right-click → Open and `xattr` on /Applications no longer work).

To ship a **notarized** DMG that opens with a plain double-click, add the secrets below.
Requires an **Apple Developer Program** membership ($99/yr). The release workflow
(`.github/workflows/release.yml`) automatically signs + notarizes **only when these
secrets are present** — otherwise it falls back to the ad-hoc DMG. No code changes needed.

## One-time setup

1. **Developer ID Application certificate**
   - In Xcode or the Apple Developer portal, create a *Developer ID Application* cert.
   - Export it as `.p12` (with a password), then base64-encode:
     ```bash
     base64 -i DeveloperID.p12 | pbcopy
     ```

2. **App Store Connect API key** (for `notarytool`)
   - App Store Connect → Users and Access → Integrations → App Store Connect API →
     create a key with the **Developer** role. Download the `.p8` (once only).
   - Note the **Key ID** and **Issuer ID**. Base64-encode the key:
     ```bash
     base64 -i AuthKey_XXXX.p8 | pbcopy
     ```

3. **Add repo secrets** (Settings → Secrets and variables → Actions):

   | Secret | Value |
   |---|---|
   | `MACOS_CERT_P12_BASE64` | base64 of the `.p12` |
   | `MACOS_CERT_PASSWORD`   | the `.p12` password |
   | `MACOS_SIGN_IDENTITY`   | `Developer ID Application: Your Name (TEAMID)` |
   | `AC_API_KEY_P8_BASE64`  | base64 of the `.p8` |
   | `AC_API_KEY_ID`         | API Key ID |
   | `AC_API_ISSUER_ID`      | API Issuer ID |

4. Push a tag (`git tag v0.1.1 && git push origin v0.1.1`). The workflow signs with a
   hardened runtime, notarizes via `notarytool --wait`, staples the ticket, and
   publishes the DMG. Users can then open it directly.

## Verify locally

```bash
spctl -a -vvv --type install JobWatch.app     # should say: accepted, source=Notarized Developer ID
xcrun stapler validate JobWatch-*.dmg
```
