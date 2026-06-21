# AppReset

**Inspect and reset macOS app permissions and data — from a GUI or the command line.**

AppReset is a developer tool for the moment you need a clean slate: testing an app's
first-run experience, re-triggering a permission prompt, or wiping the state an app
left behind. Instead of hunting through `~/Library`, `defaults`, `tccutil`, SQLite, and
`security` by hand, AppReset shows you — per app — **what it declares it needs**, **what
it has actually been granted**, and its **full on-disk footprint**, then resets any of it.

It ships as one project with two front-ends over a shared core:

- **`appreset`** — a scriptable CLI.
- **AppReset.app** — a SwiftUI app (macOS 26+) with a translucent, Loop-inspired interface,
  light / dark / system themes, a searchable and filterable app list, and a per-app detail view.

<!-- Add a screenshot here: docs/screenshot.png -->

---

## Features

- **Discover** every installed app with search and a filter — **Installed** (third-party),
  **All**, or **System** (Apple).
- **Declared permissions** — what an app is built to request ("what it *needs*"), each labeled
  by source: an **Info.plist** `NS…UsageDescription` string, a code-signing **Entitlement**, or
  a private **TCC Allow** declaration.
- **Privacy (TCC) grants** — what the user has actually allowed/denied (Camera, Microphone,
  Contacts, Calendar, Photos, Accessibility, Screen Recording, Full Disk Access, Automation,
  …), read directly from the TCC databases.
- **Data footprint** — preferences, sandbox containers, group containers, caches, application
  support, saved state, HTTP storages, WebKit storage, cookies, logs, and launch agents, each
  with its measured size.
- **Reset** any subset: privacy permissions (via `tccutil`), `UserDefaults` (via `defaults`
  + a `cfprefsd` flush), and on-disk data — **moved to the Trash by default** (or permanently
  deleted), with a dry-run preview. In the app, anything moved to the Trash can be **restored**
  in one click.

---

## Install

> Requires **macOS 26** or later.

### App
Download the latest `AppReset-x.y.z.zip` from [Releases](../../releases), unzip, and move
`AppReset.app` to `/Applications`.

### CLI
The `appreset` binary is embedded in the app bundle; install the command-line tool with:

```bash
ln -sf /Applications/AppReset.app/Contents/MacOS/appreset /usr/local/bin/appreset
```

…or download the standalone `appreset` binary from a release.

### Full Disk Access (recommended)
Reading a third-party app's **per-app privacy grants** (Camera, Microphone, Contacts, …)
requires AppReset to have **Full Disk Access** — those grants live in the user TCC database,
which macOS protects. Everything else (listing apps, declared permissions, data scanning, and
all resets) works without it.

Grant it in **System Settings ▸ Privacy & Security ▸ Full Disk Access** (the app shows a
banner with a button when it's missing). Run `appreset doctor` to check status.

---

## CLI usage

```
appreset <subcommand> [options]
```

| Command | Purpose |
|---|---|
| `appreset list [--all]` | List installed apps (default: third-party; `--all` includes Apple). |
| `appreset info <app>` | Identity + declared permissions + current TCC grants + data footprint. |
| `appreset perms <app>` | Current privacy (TCC) grants only. |
| `appreset scan <app>` | On-disk data locations with sizes. |
| `appreset reset <app> [--what …] [--dry-run] [--yes] [--permanent]` | Reset permissions and/or data. |
| `appreset doctor` | Environment + Full Disk Access check. |
| `appreset completion <bash\|zsh\|fish>` | Shell completion script. |

`<app>` is a **bundle id, app name, or path to a `.app`**.

Global flags: `--json`, `--plain`, `--no-color`, `-q/--quiet`, `-v/--verbose`, `--version`.

### Reset categories (`--what`, comma-separated)
`tcc`, `defaults`, `caches`, `containers`, `groupcontainers`, `appsupport`, `savedstate`,
`httpstorages`, `webkit`, `cookies`, `logs`, `launchagents`, `keychain`, `all`
(`all` = everything except `keychain` and `launchagents` — add those explicitly).

### Examples

```bash
appreset list
appreset info com.apple.Safari
appreset perms com.acme.MyApp --json
appreset scan com.acme.MyApp
appreset reset com.acme.MyApp --dry-run            # preview, no changes
appreset reset com.acme.MyApp --what tcc,defaults,caches --yes
appreset reset com.acme.MyApp --permanent --yes    # delete instead of Trash
```

**Safety:** `reset` moves data to the Trash unless `--permanent` is given, prompts for
confirmation in a terminal, and **requires `-y/--yes` in non-interactive (scripted) use**.
Exit codes: `0` ok · `1` failure · `2` usage · `3` partial · `64` confirmation required.

---

## A note on "enabling" permissions

macOS does **not** let any app programmatically *grant* another app a privacy (TCC)
permission — only you can, via the app's own prompt or System Settings. That's by design.
So AppReset **shows** each permission's state and lets you **reset/revoke** it (so the app
asks again next launch); it does not (and cannot) flip another app's switch on for you.

---

## Build from source

```bash
swift build            # build everything
swift test             # run tests
Scripts/compile_and_run.sh   # build + package + launch the app (ad-hoc signed)
.build/debug/appreset --help # run the CLI
```

The project is a single SwiftPM package:

- `AppResetKit` — shared core (app discovery, TCC reading via SQLite, declared-permission
  extraction, data scanning, the reset engine). Foundation + SQLite3 only.
- `appreset` — the CLI (swift-argument-parser).
- `AppResetApp` — the SwiftUI app (packaged into `AppReset.app`).

### Package / sign / notarize

```bash
Scripts/package_app.sh release      # assemble AppReset.app (ad-hoc by default)
Scripts/sign-and-notarize.sh        # Developer ID sign + notarize + staple + zip
```

`sign-and-notarize.sh` needs a Developer ID Application identity (`APP_IDENTITY`) and
App Store Connect API credentials (`APP_STORE_CONNECT_API_KEY_P8` / `_KEY_ID` / `_ISSUER_ID`),
which it reads from the environment, a git-ignored `notary-creds.env`, or `op run`.

---

## How it works

| Task | Mechanism |
|---|---|
| App discovery | Spotlight (`mdfind`) + standard app directories; metadata from each `Info.plist`. |
| Declared permissions | `NS…UsageDescription` keys + `codesign -d --entitlements` (incl. `com.apple.private.tcc.allow`). |
| Current TCC grants | Read-only SQLite over the user + system `TCC.db` (`access` table). |
| Reset privacy | `tccutil reset <service> <bundle-id>`. |
| Reset preferences | `defaults delete` + `killall cfprefsd`. |
| Delete data | `FileManager.trashItem` (default) or permanent removal. |

---

## License

MIT — see [LICENSE](LICENSE).
