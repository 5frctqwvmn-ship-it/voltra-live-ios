# Agent Roles

## GPT-5 Implementation Agent

- Works on its own fork or feature branch.
- Has authority to commit and push to its fork.
- Has authority to open PRs against upstream main.
- Does not have authority to trigger release.yml with dryRun=false.
- Does not have authority to upload to TestFlight.
- Does not have authority to use App Store Connect, altool, signing certs, provisioning profiles, or release secrets.
- Deliverable for each feature is a PR with code, tests or verification, docs, WORK_LOG entry, and clear screenshots when UI behavior is involved.

## Claude Release Agent

- Works on upstream main only when the user explicitly says to ship.
- Has release authority, including version bump, release.yml dryRun=false, altool, signing, and TestFlight upload.
- In this split-role process, Claude is release-only unless the user explicitly asks Claude to implement a feature.
- Claude must not rewrite GPT-5's implementation during release unless CI fails and the user authorizes a forward fix.
- Release deliverable is commit SHA, CI run ID, Delivery UUID, version/build, and TestFlight status.

## User Broker

- Chooses feature scope.
- Reviews GPT-5 PRs.
- Decides whether a PR is ready for Claude to ship.
- Resolves disagreements between agents.
- Has final authority on scope, merge, and release.

## Standard Handoff Sequence

1. User gives GPT-5 a feature prompt.
2. GPT-5 rebases fork on upstream main before coding.
3. GPT-5 implements, verifies, updates docs, and opens PR.
4. User reviews PR and screenshots.
5. User tells Claude: "Ship PR #N as build X."
6. Claude merges, bumps version/build/feature label, triggers release.yml dryRun=false, monitors CI.
7. Claude posts Delivery UUID and TestFlight status.
8. User verifies on device.
9. Any follow-up bug starts as a new GPT-5 PR unless user chooses otherwise.

## WORK_LOG Ownership

- GPT-5 writes detailed feature implementation entries.
- Claude writes short release entries.
- Both agents must avoid overwriting each other's WORK_LOG changes.
- If a WORK_LOG conflict occurs, preserve both entries in chronological order.

## Verification Rule

For UI layout bugs, screenshots from actual SwiftUI rendering are required.
Synthetic math validators are not sufficient unless explicitly approved by the user.
If the required simulator/device environment is unavailable, the agent must stop and ask instead of substituting a weaker test.
