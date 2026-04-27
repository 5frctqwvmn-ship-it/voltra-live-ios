# VOLTRA Live — One-Time Signing Setup

The release pipeline (`.github/workflows/release.yml`) signs builds using a
Distribution certificate and an App Store provisioning profile that live in
**GitHub Secrets**. This is a one-time setup. After it's done, every CI run
just decodes the secrets and signs — no Apple Developer portal interaction
needed for normal releases.

## Why secrets and not the ASC REST API

We tried programmatic provisioning via the ASC REST API. It works for certs
and profiles, but the API does **not** expose iCloud container management
(every `/v1/{i,c}loudContainers` variant returns `404 NOT_FOUND`). Without the
container association, the auto-issued profile is missing entitlements the
app declares, and the signed archive fails. Stored cert + profile sidesteps
this entirely.

## What you need

- A Mac with Xcode and Keychain Access (one-time use)
- Admin or Account Holder role on the Apple Developer team
  (Team ID `588XUZGNNS` — VOLTRA Live)
- The GitHub `gh` CLI authenticated to push secrets, OR the Settings page
  of `5frctqwvmn-ship-it/voltra-live-ios`

## Steps

### 1. Generate (or fetch) the Distribution certificate

If you don't already have an active **Apple Distribution** cert with the
private key on this Mac:

1. Open **Keychain Access → Certificate Assistant → Request a Certificate
   From a Certificate Authority…**
2. Email = your Apple ID, Common Name = "Apple Distribution: Michael Jackson",
   "Saved to disk", continue → save `.certSigningRequest` somewhere.
3. Go to <https://developer.apple.com/account/resources/certificates/list>,
   click **+**, choose **Apple Distribution**, upload the CSR, download
   the `.cer` file, double-click to install into your login keychain.

### 2. Export the cert as a `.p12`

In **Keychain Access → My Certificates**, right-click the
"Apple Distribution: Michael Jackson" cert → **Export** → File Format
**Personal Information Exchange (.p12)** → save as `voltra-dist.p12` →
choose a strong export password (you'll paste it into a GitHub Secret next).

> Make sure you export the row that has the **disclosure triangle**
> revealing the private key. If you export a row without a private key,
> the `.p12` will be useless on CI.

### 3. Create the App Store provisioning profile

1. Go to <https://developer.apple.com/account/resources/profiles/list>,
   click **+**, choose **App Store Connect** under "Distribution",
   continue.
2. App ID: select **VOLTRA Live (com.voltralive.app)**.
3. Certificates: select the Apple Distribution cert from step 1.
4. Provisioning Profile Name: **`VOLTRA Live App Store (CI)`**
   (or any name you like — you'll paste the exact same string into a
   GitHub Secret).
5. Generate, then **Download** the `.mobileprovision` file.

### 4. Base64-encode the two files

In Terminal:

```bash
cd ~/Downloads     # or wherever you saved them
base64 -i voltra-dist.p12 | pbcopy
# now paste into APPLE_DIST_CERT_P12 in step 5

base64 -i VOLTRA_Live_App_Store__CI_.mobileprovision | pbcopy
# now paste into APPLE_PROFILE_MOBILEPROV in step 5
```

### 5. Set the four GitHub Secrets

Either via the `gh` CLI:

```bash
cd /path/to/voltra-live-ios
gh secret set APPLE_DIST_CERT_P12        --body "$(base64 -i voltra-dist.p12)"
gh secret set APPLE_DIST_CERT_P12_PASS   # paste the .p12 export password
gh secret set APPLE_PROFILE_MOBILEPROV   --body "$(base64 -i VOLTRA_Live_App_Store__CI_.mobileprovision)"
gh secret set APPLE_PROFILE_NAME         --body "VOLTRA Live App Store (CI)"
```

…or via the GitHub web UI: **Settings → Secrets and variables → Actions →
New repository secret**, four times. Names must be exactly:

| Name                        | Value                                                          |
| --------------------------- | -------------------------------------------------------------- |
| `APPLE_DIST_CERT_P12`       | base64 of the `.p12`                                           |
| `APPLE_DIST_CERT_P12_PASS`  | the password you used when exporting the `.p12`                |
| `APPLE_PROFILE_MOBILEPROV`  | base64 of the `.mobileprovision`                               |
| `APPLE_PROFILE_NAME`        | exact profile name from Apple portal — must match step 3       |

### 6. Run a dry-run

```bash
gh workflow run release.yml --ref main -f dry_run=true
gh run watch
```

If green, tag `v0.4.6.2` and push to ship to TestFlight.

## When to repeat any of this

- **Distribution cert expires** (≈1 year): redo steps 1, 2, 4-row-1, 5-row-1.
- **Want a new profile** (new bundle ID, added a capability,
  added a new device for ad-hoc): redo steps 3, 4-row-2, 5-row-2.
- **Apple revokes the cert**: redo everything.

## Troubleshooting

**`security import` fails with "MAC verification failed"**
The `.p12` was exported from openssl 3 with default cipher (AES-256-CBC +
PBKDF2). The macOS `security` CLI can't read that. Re-export from Keychain
Access (which uses legacy ciphers), OR re-pack with
`openssl pkcs12 -export -legacy -in foo.p12 -out bar.p12` and use `bar.p12`.

**Archive fails "doesn't include the X capability"**
The provisioning profile is out of date — the app's entitlements added a
capability since you generated the profile. Regenerate the profile in the
Apple portal (step 3), update `APPLE_PROFILE_MOBILEPROV`.

**Decode step says "Missing required GitHub Secrets"**
You haven't set all four. Run `gh secret list` and confirm.
