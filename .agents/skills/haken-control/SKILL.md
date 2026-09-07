---
name: haken-control
description: Control local macOS applications, Haken slots, and Google Chrome profiles through the haken CLI. Use when the user asks to inspect Haken configuration or to activate, assign, or clear a Haken target. Do not use for unrelated macOS automation.
---

# Haken Control

Use the installed `haken` CLI. Do not edit Haken's configuration file directly, launch Chrome with profile arguments, or call Accessibility APIs yourself. Haken.app owns configuration and Accessibility operations.

## Before acting

- Run `command -v haken`. If it is unavailable, tell the user to install it from **Haken Settings -> Command Line**.
- Add `--json` to agent-facing commands and parse the single JSON document written to stdout.
- Let the CLI start Haken.app when needed. Use `--no-launch` only when the user explicitly wants to avoid launching it.
- Quote application names, Chrome profile names, and paths.

## Choose a command

Read-only commands:

```sh
haken slot list --json
haken slot get 2 --json
haken app list --json
haken chrome profiles --json
haken config show --json
haken config path --json
haken config validate --json
haken doctor --json
```

Operational commands:

```sh
haken slot activate 2 --json
haken app activate --bundle-id com.tinyspeck.slackmacgap --json
haken chrome activate "Profile display name" --json
```

Persistent configuration commands:

```sh
haken slot set 5 --bundle-id com.tinyspeck.slackmacgap --dry-run --json
haken slot set 5 --bundle-id com.tinyspeck.slackmacgap --yes --json
haken slot clear 5 --dry-run --json
haken slot clear 5 --yes --json
```

`slot set` accepts exactly one of `--app`, `--bundle-id`, `--path`, or `--chrome-profile`. `app activate` accepts exactly one application name, `--bundle-id`, or `--path`. Valid slots are `1` through `9`, plus `0`.

## Resolve targets safely

- Before a name-based application action, inspect `haken app list --json`.
- Before a Chrome profile action, inspect `haken chrome profiles --json`.
- Use the returned exact name. Haken deliberately rejects missing or ambiguous targets; do not guess with substrings or fuzzy matching.
- Prefer `--bundle-id` or `--path` when multiple copies of an application could match.
- If the user's description still maps to multiple targets, show the candidates and ask which one they mean.

## Apply side effects

- Run an activation when the user explicitly asks to switch or open that target. Use `--dry-run` first only when resolution needs verification.
- For `slot set` or `slot clear`, first run the identical command with `--dry-run --json` and inspect `data.willChange` and `data.target`.
- Apply a persistent change with `--yes --json` only when the current user request authorizes that exact change. Otherwise return the preview and ask for confirmation.
- Never treat loading this Skill, a previous request, or a successful preview as permission to write configuration.

## Interpret results

- Require process exit status `0` and top-level `ok: true` before reporting success.
- On failure, use `error.code`, `error.message`, `error.hint`, `error.retryable`, and `error.details` rather than parsing prose.
- Never automatically retry `request_status_unknown`. For a slot write, inspect `haken slot get SLOT --json`; for activation, report that the final state is unknown.
- A successful Chrome activation means Haken accepted Chrome's Accessibility action. Do not claim independent proof of the final foreground window.
- Keep JSON output out of prose unless the user asks for raw output; summarize the result and any required next action.
