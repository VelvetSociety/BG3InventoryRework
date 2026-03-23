#!/usr/bin/env python3
"""BG3 Script Extender log watcher.

Tails the most recent gold.*.log file in the BG3 bin\ directory.
Filters to lines matching a configurable substring handle, writes
filtered lines to Tools/last_session.log, and prints them to the
terminal with color-coded severity.

Usage:
    python Tools/watch_log.py                          # filter [BG3InventoryRework]
    python Tools/watch_log.py --filter "[Armory]"      # only armory subsystem
    python Tools/watch_log.py --filter "[Inventory]"   # only inventory subsystem
    python Tools/watch_log.py --filter ""              # all SE output (no filter)

Tools/last_session.log is overwritten on each run.
Claude Code can Read this file at any time to see mod output since last launch.
"""

import argparse
import glob
import os
import sys
import time
from pathlib import Path

# ── ANSI color codes ─────────────────────────────────────────────────────────
RED    = "\033[91m"
YELLOW = "\033[93m"
RESET  = "\033[0m"

BG3_BIN = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Baldurs Gate 3\bin")
REPO_ROOT   = Path(__file__).parent.parent
OUTPUT_LOG  = REPO_ROOT / "Tools" / "last_session.log"
POLL_MS     = 200   # milliseconds between read attempts


def find_latest_log(bin_dir: Path) -> Path | None:
    pattern = str(bin_dir / "gold.*.log")
    matches = glob.glob(pattern)
    if not matches:
        return None
    return max(matches, key=os.path.getmtime)


def colorize(line: str) -> str:
    lower = line.lower()
    if "error" in lower or "failed" in lower or "exception" in lower:
        return RED + line + RESET
    if "warn" in lower:
        return YELLOW + line + RESET
    return line


def tail(log_path: Path, handle: str, out_file):
    """Open log_path, seek to end, then poll for new lines."""
    print(f"[watch_log] Watching: {log_path}", flush=True)
    print(f"[watch_log] Filter  : '{handle}' (empty = all)", flush=True)
    print(f"[watch_log] Output  : {OUTPUT_LOG}", flush=True)
    print("[watch_log] Ctrl+C to stop\n", flush=True)

    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        f.seek(0, 2)  # seek to end — only show new lines from this run

        while True:
            line = f.readline()
            if not line:
                time.sleep(POLL_MS / 1000)
                continue

            line = line.rstrip("\n")

            # Apply filter
            if handle and handle not in line:
                continue

            # Timestamp prefix
            ts = time.strftime("%H:%M:%S")
            output_line = f"[{ts}] {line}"

            print(colorize(output_line), flush=True)
            out_file.write(output_line + "\n")
            out_file.flush()


def main():
    parser = argparse.ArgumentParser(description="Tail BG3 SE log filtered to mod output.")
    parser.add_argument(
        "--filter",
        default="[BG3InventoryRework]",
        help="Substring filter (default: '[BG3InventoryRework]', empty string = show all)",
    )
    parser.add_argument(
        "--bin",
        default=str(BG3_BIN),
        help="Path to BG3 bin\\ directory",
    )
    args = parser.parse_args()

    bin_dir = Path(args.bin)
    if not bin_dir.exists():
        print(f"[watch_log] ERROR: BG3 bin dir not found: {bin_dir}", file=sys.stderr)
        sys.exit(1)

    # Find the log — if not found yet, wait until a game session creates it
    log_path = find_latest_log(bin_dir)
    if not log_path:
        print("[watch_log] No gold.*.log found — waiting for game launch...", flush=True)
        while not log_path:
            time.sleep(1)
            log_path = find_latest_log(bin_dir)

    OUTPUT_LOG.parent.mkdir(parents=True, exist_ok=True)

    try:
        with open(OUTPUT_LOG, "w", encoding="utf-8") as out_file:
            tail(Path(log_path), args.filter, out_file)
    except KeyboardInterrupt:
        print("\n[watch_log] Stopped.", flush=True)


if __name__ == "__main__":
    main()
