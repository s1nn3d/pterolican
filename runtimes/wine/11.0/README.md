# Wine 11.0 Pterodactyl Runtime

This is a **Wine 11–pinned runtime image** intended for use with **Pterodactyl / Pelican** game servers.

It exists because **Wine 11 changed its process model**, which breaks the traditional
“run `wine` in the foreground” assumption used by many existing eggs and runtimes.

This runtime fixes that at the **image level**, so eggs can remain clean and readable.

---

## What this image does

- Pins **Wine stable 11.0.x** (Debian Bookworm)
- Handles Wine 11’s **PID hand-off behavior**
- Prevents Wings restart loops caused by early launcher exit
- Optionally:
  - tracks the *real* server process via `pgrep`
  - tails a server log file into the Pterodactyl console

All lifecycle logic lives in the **entrypoint**, not in the egg startup command.

---

## Intended usage

This image is meant to be used with **Wine-11-specific eggs**.

The egg should:
- use `wine` (not `wine64`)
- provide a normal startup command (no bash logic)
- optionally set:
  - `WINE_PROCESS_MATCH` – process matcher for the real server
  - `LOG_FILE` – log file to stream into the console

Example startup (egg):
```bash
wine ./Server.exe -log
