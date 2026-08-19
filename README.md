# Haken

Haken is a macOS menu-bar utility that assigns one consistent set of number or function-key shortcuts to applications and specific Google Chrome profiles.

```sh
Scripts/verify.sh
open '.build/app/Haken.app'
```

The application writes versioned configuration to `~/Library/Application Support/Haken/configuration.json`. A malformed existing file is never silently overwritten; the Settings screen offers an explicit reset after explaining this.

## Manual verification

1. Build and open the app, assign Terminal (or another installed app) to `⌥1`, then use **Test** and `⌥1`. Confirm it activates an existing instance or launches it when stopped.
2. Leave `⌥2` unassigned and verify the foreground app still receives its normal `⌥2` behavior.
3. In **Settings**, switch the shortcut pattern and verify assigned slots use `⌥F1`–`⌥F10`, `⌘1`–`⌘0`, `⌘F1`–`⌘F10`, or `F1`–`F10` consistently, without mixing patterns between slots.
4. Start Google Chrome with at least two profiles/windows. Add a Chrome profile target, grant Haken Accessibility permission only when prompted, refresh profiles, assign one, and test it.
5. Restart Chrome, refresh profiles, and retest the assigned profile to validate AX cache invalidation.
6. Temporarily deny Accessibility permission, confirm Application targets still work, and confirm a Chrome profile target presents an actionable permission error.
7. Inspect **Diagnostics** and confirm it contains no profile display names, application paths, URLs, tab titles, or key input history.
8. Set **Switch feedback** to **HUD**, choose an Option- or Command-based pattern, hold that modifier for a moment, and confirm every assigned app appears with the selected shortcut hints. Release it and confirm the HUD disappears. A successful switch should not show a confirmation HUD.

Chrome profile switching uses the documented PoC selector within Chrome’s `AXMenuBar` only. Haken treats a successful `AXPress` as an accepted request; it cannot independently prove final window placement across Spaces or full-screen windows.
