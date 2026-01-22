# Icarus Pterodactyl Eggs

This directory contains Pterodactyl eggs for running **Icarus Dedicated Server**
using Wine.

There are **two variants**, intentionally kept separate.

## Icarus – Wine 10
- Uses a traditional Wine process model
- Simple foreground execution
- Known-good fallback
- No special runtime handling required

Recommended if you already have a working server and don’t need Wine 11.

## Icarus – Wine 11
- Uses a Wine 11–pinned runtime
- Handles Wine 11 process hand-off safely
- Prevents Wings restart loops
- Keeps egg startup commands clean

### Wine 11–specific variable

The Wine 11 egg uses one additional variable:

- `WINE_PROCESS_MATCH`  
  Process name used to detect the real server PID  
  Default:
```IcarusServer-Win64-Shipping.exe