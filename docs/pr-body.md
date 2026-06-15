## Summary
Two deliverables:

1. **New app icon** — replaces the graduation cap with a "page + amber highlighter"
   mark on the indigo→blue squircle, reflecting the collect/read/annotate identity.
   Regenerated into the asset catalog via a rewritten `scripts/generate_icon.py`.
2. **One-click auto-update** — integrates **Sparkle 2.x** so the installed app
   updates itself (menu item + daily background checks + install-and-relaunch).
   Releases are published to a rolling GitHub Release tagged `updates`. Trust is via
   **EdDSA** signatures, so it works **without an Apple Developer account**.

Design: `docs/superpowers/specs/2026-06-15-logo-and-auto-update-design.md`
Plan: `docs/superpowers/plans/2026-06-15-logo-and-auto-update.md`

## Changes
- `scripts/generate_icon.py` + regenerated `AppIcon.appiconset` + master preview
- `scripts/mac_bootstrap.sh`: Sparkle SPM dep, `SU*` Info.plist keys, env-driven
  versions, new `generate` action, `Update/` added to sources
- `scripts/version.env`, `scripts/release.sh` (build → sign → publish)
- `NimbleScholarCore`: `UpdateFeed` helper + unit tests
- App: `UpdaterController`, "Check for Updates…" menu, Settings → Software updates

## Not yet done (require macOS — see plan Tasks 8 & 11)
- [ ] One-time `generate_keys` and replace `SUPublicEDKey` placeholder (updates are
      refused until this is set)
- [ ] `swift test --filter UpdateFeedTests`
- [ ] First real release via `scripts/release.sh 0.1.1`

## Verified on Linux
Icon rendering (all sizes), shell scripts parse (`bash -n`), version expansion.
Swift compilation / full Xcode build not verified here (no macOS).
