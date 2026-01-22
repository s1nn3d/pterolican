# Wine 11.0 Runtime (Pterodactyl / Pelican)

This is a **Wine 11–pinned runtime image** for Pterodactyl / Pelican game servers.

It exists because **Wine 11 changed its process behavior**, which can cause
Wings to think a server exited when it actually didn’t.

The fix is handled in the **container entrypoint**, not in the egg.

## What this runtime does

- Pins **Wine stable 11.0.x** on Debian Bookworm
- Works around Wine 11 PID hand-off issues
- Prevents restart loops in Wings
- Allows clean, readable egg startup commands
- Can optionally:
  - track the real server process
  - stream a log file into the panel console

## Intended usage

Use this image with **Wine 11–specific eggs**.

Eggs should:
- use `wine` (not `wine64`)
- keep startup commands simple
- optionally set:
  - `WINE_PROCESS_MATCH`
  - `LOG_FILE`

## Notes

- A Wine 10 runtime is kept separately as a fallback.
- This image is pinned for reproducibility.
- Future Wine versions may require a new runtime tag.

## License

MIT
