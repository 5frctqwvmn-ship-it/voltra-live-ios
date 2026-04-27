# VOLTRA Live — One-Time Signing Setup (no Mac required)

The release pipeline (`.github/workflows/release.yml`) signs builds using a
Distribution certificate and an App Store provisioning profile that live in
**GitHub Secrets**. This page walks you through setting up those secrets
**without owning a Mac** — everything happens in your browser plus one
manually-triggered GitHub Actions workflow.

You'll do this once. After it's done, every release CI run just decodes the
secrets and signs.

## Why this is the way

We tried programmatic provisioning via the ASC REST API. It works for certs
and profiles, but Apple's API does **not** expose iCloud container management
(every `/v1/{i,c}loudContainers` variant returns `404 NOT_FOUND`). Without
the container association on the bundle ID, auto-issued profiles are missing
entitlements the app declares, and the signed archive fails. So the
container association has to happen in the Apple Developer web UI — but
everything else can be automated.

## What you'll need

- Browser access to <https://developer.apple.com/account>, signed in as
  Account Holder or Admin on the VOLTRA Live team (Team ID `588XUZGNNS`)
- Browser access to GitHub repo `5frctqwvmn-ship-it/voltra-live-ios`
- Maybe 15 minutes

## Step 1 — Make sure iCloud capability is set up correctly on the bundle ID

Your app declares `com.apple.developer.icloud-container-identifiers =
[iCloud.com.voltralive.app]`. The Apple Developer portal needs the iCloud
capability enabled on `com.voltralive.app` AND that specific container
checked. Do this once:

1. Go to <https://developer.apple.com/account/resources/identifiers/list>
2. Click the row for **VOLTRA Live (com.voltralive.app)** to edit it.
3. Scroll the capabilities list. Find **iCloud**.
   - If the checkbox is OFF, turn it ON and pick "Include CloudKit support".
   - Click **Edit** next to iCloud → **Containers**.
4. Make sure `iCloud.com.voltralive.app` is in the list and **checked**.
   - If it doesn't exist yet, click **+** → identifier `iCloud.com.voltralive.app`,
     name "VOLTRA Live iCloud", continue, then come back and check it.
5. Save changes.

Verify the following capabilities are on (with checkboxes ticked):

- ✅ **iCloud** — with `iCloud.com.voltralive.app` container checked
- ✅ **HealthKit**

Other entitlements (`ubiquity-kvstore-identifier`,
`ubiquity-container-identifiers`) flow automatically from iCloud being on
with that container; no separate toggle.

## Step 2 — Run the bootstrap workflow to create the Distribution cert

You don't need to generate a CSR or download a cert manually. CI does it.

1. Go to <https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/workflows/bootstrap-signing.yml>
2. Click **Run workflow**, branch `main`.
3. Type a strong **p12_password** in the input field. This password
   protects the .p12. Avoid `$ " \\` because they fight with shells. 8+
   chars. **Remember it** — you'll paste it into a secret next.
4. Click **Run workflow**, wait ~1 minute.
5. Open the run, expand the
   "Revoke + recreate Distribution cert, output .p12 base64" step.
6. Scroll to the long block titled **`▶ APPLE_DIST_CERT_P12 ◀`**. Copy
   the giant base64 blob between the `BEGIN`/`END` lines (the blob only,
   not the markers).

## Step 3 — Set the cert secrets in GitHub

Go to <https://github.com/5frctqwvmn-ship-it/voltra-live-ios/settings/secrets/actions>
and add:

| Name                       | Value                                                                      |
| -------------------------- | -------------------------------------------------------------------------- |
| `APPLE_DIST_CERT_P12`      | The base64 blob you copied from the workflow log                           |
| `APPLE_DIST_CERT_P12_PASS` | The exact `p12_password` you typed when launching the bootstrap workflow   |

After both are set, **delete the bootstrap run's logs**:
Actions → click the bootstrap run → ⋯ menu → "Delete logs". This avoids
leaving the .p12 base64 sitting in workflow history. The .p12 is encrypted
with `p12_password`, but defense in depth is cheap.

## Step 4 — Create the App Store provisioning profile in the web UI

1. Go to <https://developer.apple.com/account/resources/profiles/list>
2. Click **+** → under "Distribution" pick **App Store Connect** → continue.
3. App ID: pick **VOLTRA Live (com.voltralive.app)**.
4. Certificates: select the Distribution cert that was just created (its
   name starts with "Apple Distribution: Michael Jackson", and the Created
   date is today).
5. Provisioning Profile Name: **`VOLTRA Live App Store (CI)`**.
   You can pick anything, but it has to match `APPLE_PROFILE_NAME` (next
   step) **exactly**, character-for-character.
6. Click **Generate**, then **Download**. You'll get a file like
   `VOLTRA_Live_App_Store__CI_.mobileprovision`.

## Step 5 — Base64-encode the .mobileprovision in your browser

You don't have a Mac, so we'll use the browser console.

1. Open <https://www.base64encode.org/> in any browser.
2. Click the **Encode files to Base64** tab.
3. Click **Choose File**, pick the `.mobileprovision` file you just
   downloaded.
4. Tick **"Live mode"** if not already, click **Encode**.
5. Copy the entire encoded blob. (It's all on one line.)

> Alternative if you prefer not to upload to an external site: open Chrome
> DevTools (F12) → Console tab on any HTTPS page, paste:
>
> ```js
> (async () => {
>   const i = document.createElement('input'); i.type = 'file';
>   i.onchange = async () => {
>     const f = i.files[0];
>     const buf = new Uint8Array(await f.arrayBuffer());
>     let s = ''; for (const b of buf) s += String.fromCharCode(b);
>     console.log(btoa(s));
>   };
>   i.click();
> })();
> ```
>
> Pick the `.mobileprovision`, the base64 prints to the console.

## Step 6 — Set the profile secrets in GitHub

Same secrets page as before. Add:

| Name                       | Value                                                                  |
| -------------------------- | ---------------------------------------------------------------------- |
| `APPLE_PROFILE_MOBILEPROV` | The base64 blob from step 5                                            |
| `APPLE_PROFILE_NAME`       | The exact profile name from step 4 (e.g. `VOLTRA Live App Store (CI)`) |

## Step 7 — Verify by running a release dry-run

Tell the agent "secrets are set" and it will trigger a dry-run, OR do it
yourself:

<https://github.com/5frctqwvmn-ship-it/voltra-live-ios/actions/workflows/release.yml>
→ Run workflow → `dry_run = true`.

A green run produces a signed `.ipa` as a workflow artifact. Tagging
`v0.4.6.2` (no dry run) ships it to TestFlight.

---

## When to repeat parts of this

- **Distribution cert expires** (≈1 year from creation) or you need to rotate
  it: redo steps 2 and 3, then redo step 4 (regenerate the profile so it
  pairs with the new cert) and steps 5 and 6.
- **App's entitlements grow a new capability**: enable that capability in
  the Apple portal on the bundle ID (step 1-style), regenerate the profile
  (step 4), redo steps 5 and 6. No cert change needed.
- **Apple revokes the cert**: same as cert expiry, redo all of 2–6.

## Troubleshooting

**Bootstrap workflow fails at "create cert failed -> HTTP 409"**
You already have a Distribution cert and the API key isn't allowed to
revoke it. Go to <https://developer.apple.com/account/resources/certificates/list>,
manually revoke the existing **iOS Distribution** cert, re-run bootstrap.

**Release workflow fails: "doesn't include the X capability"**
Step 1 wasn't completed for capability X. Go enable it on the bundle ID,
regenerate the profile (step 4), redo 5 + 6.

**Release workflow fails: "Code Signing Error: No matching profiles"**
`APPLE_PROFILE_NAME` doesn't match the profile name set in the Apple
portal. They must be byte-identical, including spaces and parens.

**Release workflow fails at "MAC verification failed" on import**
The bootstrap workflow's openssl call missed `-legacy`. Re-run bootstrap;
the workflow already passes `-legacy`, so this shouldn't happen.

**Release workflow fails: "Missing required GitHub Secrets"**
You skipped a secret. Run `gh secret list` (or check the secrets settings
page) and confirm all four are present.
