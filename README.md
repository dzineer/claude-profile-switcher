# Claude Profile Switcher

A native macOS app to manage multiple Claude Desktop profiles. Switch between personal and work accounts with a single click.

🟢 **Normal Mode** · 🔵 **Multi Profile** · ⚡ **One-click switch**

## How it works

Claude Desktop stores everything — chats, auth tokens, preferences — in `~/Library/Application Support/Claude/`. This app manages **separate folders** (`Claude-Personal`, `Claude-Work`, etc.) and swaps a symlink to activate the one you want.

**No copying, no logging out.** Each profile keeps its own auth state. Switch instantly.

## Features

- **Detect & convert** — turns your existing Claude folder into a named profile
- **New profile** — create an empty profile to sign in with a different account
- **Duplicate** — clone your current profile (same account, separate history)
- **Switch** — kill Claude, swap symlink, relaunch
- **Reset** — undo profiles, go back to a single folder

## System Requirements

- macOS 12.0+ (Monterey or later)
- Claude Desktop installed

## Download

Grab the latest `.app` from [Releases](https://github.com/dzineer/claude-profile-switcher/releases).

**First run:** right-click → Open (ad-hoc signed, one-time Gatekeeper bypass).

## Quick Start

1. Launch the app — click **Convert** to save your current Claude as a named profile
2. Click **＋ New** to create an empty profile for your second account
3. **Switch** to it, relaunch Claude, and sign in fresh with the other account
4. Switch back and forth anytime

## Build from Source

```bash
git clone https://github.com/dzineer/claude-profile-switcher.git
cd claude-profile-switcher
./build-and-install.sh
```

Requires Xcode 14+ or Swift 5.9+.

## Uninstall

```bash
# Remove the app
rm -rf /Applications/Claude\ Profile\ Switcher.app

# Reset Claude to a normal folder
cd ~/Library/Application\ Support
rm Claude               # remove symlink
mv Claude-Personal Claude  # or whichever profile you want
```

## License

MIT — free to use, modify, and share.

---

by Dzineer
