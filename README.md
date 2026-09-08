# Haken

Haken is a macOS menu-bar utility that assigns one consistent set of number or function-key shortcuts to applications and specific Google Chrome profiles.

```sh
Scripts/verify.sh
open '.build/app/Haken.app'
```

The application writes versioned configuration to `~/Library/Application Support/Haken/configuration.json`. A malformed existing file is never silently overwritten; the Settings screen offers an explicit reset after explaining this.

## Command line

The app bundle includes `Contents/Helpers/haken`. Install a symlink from **Settings → Command Line**, then ensure `~/.local/bin` is in `PATH`.

```sh
haken slot list
haken slot activate 2
haken chrome profiles --json
haken slot set 5 --bundle-id com.tinyspeck.slackmacgap --dry-run --json
haken slot set 5 --bundle-id com.tinyspeck.slackmacgap --yes
haken doctor --json
```

The CLI sends commands to Haken.app over a user-only local socket. It does not edit `configuration.json` or request Accessibility permission itself. Persistent changes require confirmation in a terminal or `--yes` in non-interactive use.

## AI Skill

The repository includes an agent Skill at `.agents/skills/haken-control`, and the app bundles the same Skill at `Contents/Resources/Skills/haken-control`. Codex discovers the repository copy while working in this project. To make an app installed in `/Applications` available user-wide without administrator privileges, link the bundled copy into your agent Skills directory:

```sh
mkdir -p "$HOME/.agents/skills"
ln -s "/Applications/Haken.app/Contents/Resources/Skills/haken-control" "$HOME/.agents/skills/haken-control"
```

## Secure Input

macOS may withhold Option-only global hot keys while another application holds Secure Event Input. In that state, a shortcut such as `⌥3` can reach the foreground text field as `£` instead of reaching Haken. Move focus out of the secure-input application or quit it; `haken slot activate 3` remains available because it does not depend on keyboard event delivery.

## Manual verification

1. Build and open the app, assign Terminal (or another installed app) to `⌥1`, then use **Test** and `⌥1`. Confirm it activates an existing instance or launches it when stopped.
2. Leave `⌥2` unassigned and verify the foreground app still receives its normal `⌥2` behavior.
3. In **Settings**, switch the shortcut pattern and verify assigned slots use `⌥F1`–`⌥F10`, `⌘1`–`⌘0`, `⌘F1`–`⌘F10`, or `F1`–`F10` consistently, without mixing patterns between slots.
4. Start Google Chrome with at least two profiles/windows. Add a Chrome profile target, grant Haken Accessibility permission only when prompted, refresh profiles, assign one, and test it.
5. Restart Chrome, refresh profiles, and retest the assigned profile to validate AX cache invalidation.
6. Temporarily deny Accessibility permission, confirm Application targets still work, and confirm a Chrome profile target presents an actionable permission error.
7. Inspect **Diagnostics** and confirm it contains no profile display names, application paths, URLs, tab titles, or key input history.
8. Set **Switch feedback** to **HUD**, choose an Option- or Command-based pattern, adjust **HUD delay**, and confirm the assigned apps appear after holding that modifier for the selected duration.
9. While waiting for the HUD and again while it is visible, press another key without releasing the modifier. Confirm the pending HUD is canceled or the visible HUD closes and stays closed until the modifier is released.

Chrome profile switching uses the documented PoC selector within Chrome’s `AXMenuBar` only. Haken treats a successful `AXPress` as an accepted request; it cannot independently prove final window placement across Spaces or full-screen windows.
