# ADR-0002: AI / Automation向けCLIを第一級インターフェースにする

- Status: Accepted
- Date: 2026-09-06

## Context

HakenはGUIとグローバルショートカットから、ApplicationまたはGoogle Chrome Profileへ切り替えるmacOSユーティリティである。Terminal、shell script、Karabiner、Raycast、Shortcuts、AI Agent、将来のMCP Serverからも同じ機能を安定して利用できるようにする。

CLIが設定ファイルやAccessibility APIを独自に扱うと、GUIとの更新競合、異なる名前解決、別プロセスへのAccessibility権限付与、Chrome AXキャッシュの消失が起きる。そのため、設定と操作の正しい実装経路はHaken.app内に一つだけ置く。

## Decision

### Architecture

```text
GUI --------------------+
                        v
                  Haken Command Service
                        |
CLI -- local IPC -------+-- Configuration Store
                        +-- Switch Coordinator
                              +-- Application Adapter
                              +-- Chrome Profile Adapter -- Accessibility -- Chrome

future MCP -- local IPC-+
```

- Haken.appが設定、Application activation、Chrome Profile activationの唯一の実行主体になる。
- GUIはCommand Serviceを直接呼ぶ。
- CLIは同じServiceへUnix Domain Socketで要求する薄いクライアントとする。
- CLI自身は設定ファイルを書かず、Accessibility APIも呼ばない。
- MCPは将来CLI/Coreの上へ載せる薄いAdapterとし、専用ビジネスロジックを持たせない。

### IPC

- v0.1は追加helperやdaemonを作らず、Haken.appがUnix Domain Socketをlistenする。
- TCP/HTTP portは開かない。
- 1 connectionにつき1 request/1 responseのlength-prefixed JSONとする。
- requestにはprotocol version、request ID、method、parametersを含める。
- socketの親directoryは0700、socketは0600とし、serverはpeer UIDを検証する。
- Haken.appが未起動ならCLIが非foregroundで起動して接続を再試行する。
- `--no-launch`指定時は起動せず、明示的に失敗する。

NSXPCConnectionは型安全でmacOS nativeだが、外部CLIから到達可能なnamed Mach serviceには通常LaunchAgent/Daemon等のlaunchd管理serviceが必要になる。追加常駐processを導入するほどの要件はないため、v0.1では採用しない。

### Accessibility

```text
haken CLI -> Haken.app -> AXUIElement / AXPress -> Google Chrome
```

- Accessibility権限を持つのはHaken.appだけとする。
- CLIから権限要求promptを自動表示しない。
- 未許可時はmachine-readable errorと復旧方法を返す。
- AXPress成功は最終画面状態の検証ではなく`request_accepted`とする。

### Command categories

1. Read-only: `slot list/get`, `app list`, `chrome profiles`, `config show/path/validate`, `doctor`
2. Operational action: `slot/app/chrome activate`
3. Persistent write: `slot set/clear`と将来のconfig変更

Persistent writeはTTYでは確認可能とし、非TTYまたは`--json`では`--yes`を必須にする。副作用のあるcommandは`--dry-run`を提供する。

### v0.1 commands

```text
haken slot list
haken slot get <slot>
haken slot activate <slot>
haken slot set <slot> --app <name>
haken slot set <slot> --bundle-id <id>
haken slot set <slot> --path <path-to-app>
haken slot set <slot> --chrome-profile <name>
haken slot clear <slot>

haken app list
haken app activate <name>
haken app activate --bundle-id <id>

haken chrome profiles
haken chrome activate <profile-name>

haken config show
haken config path
haken config validate

haken doctor
haken --version
```

Slotは`1...9, 0`の10個だけを受け付ける。`10`をSlot 0のaliasにはしない。

### Name resolution

- Bundle IDとpathは完全一致で扱う。
- Application表示名とChrome Profile名も完全一致を基本とする。
- fuzzy matchやsubstring matchは行わない。
- 0件はnot found、複数件はambiguousとして失敗する。
- 複数のApplication copyがある場合は`--path`で明示させる。
- `profileDirectory`は現在のHaken内部で使用していないため公開しない。

### JSON contract

`--json`では成功・失敗ともstdoutへJSON documentを一つだけ出力する。永続ConfigのCodable形式を公開APIにせず、CLI専用DTOを使う。

```json
{
  "apiVersion": "haken.cli/v1",
  "ok": true,
  "command": "slot.set",
  "data": {
    "action": "set_slot",
    "slot": 2,
    "target": {
      "type": "application",
      "displayName": "Slack",
      "bundleIdentifier": "com.tinyspeck.slackmacgap"
    },
    "willChange": true,
    "dryRun": true
  },
  "meta": {
    "requestId": "UUID",
    "cliVersion": "0.1.0",
    "appVersion": "0.1.0",
    "durationMs": 7
  }
}
```

Errorは`code`, `message`, `retryable`, `hint`, `details`を持つ。JSON enumはlower snake caseとし、minor versionではfield追加だけを行う。

### stdout / stderr / exit status

- Human-readable successとhelp/versionはstdout。
- Human-readable errorとwarningはstderr。
- `--json`時のprotocol resultは成功・失敗ともstdout。
- OSLog、進捗、debug情報をstdoutへ混ぜない。

Exit statusは`sysexits.h`を基準にする。

| Code | Meaning |
| ---: | --- |
| 0 | Success / no change / dry-run success |
| 64 | Usage、invalid selector、ambiguous target |
| 65 | Invalid input data |
| 69 | Haken/Chrome/Application unavailable |
| 70 | Internal software failure |
| 71 | OS API failure |
| 74 | IPC/config I/O failure |
| 75 | Busy/timeout等のtemporary failure |
| 76 | IPC protocol mismatch |
| 77 | Accessibility等のpermission不足 |
| 78 | Invalid/corrupt configuration |

### Performance

- Haken.app起動中のCLI追加overheadをp95 50ms未満とする。
- warm Application activation totalをp95 150ms未満とする。
- warm Chrome activation totalをp95 200ms未満とする。
- Chrome AX cacheはHaken.app内で再利用する。
- Application catalog scanをactivationのcritical pathへ入れない。
- 初回のHaken.app background launchは別指標として扱う。

### Configuration and concurrency

- Haken.appをConfigのsingle writerにする。
- Config writeとActivation requestはapp内の管理されたexecutorで直列化する。
- persist成功後にGUIとHotkeyを更新し、その後IPC応答を返す。
- CLIはConfig保存場所をハードコードしない。
- iCloud/Dropbox等を実装する時点でStoreを差し替え、v0.1では同期用抽象層を先行実装しない。

### Distribution

- CLI binaryは`Haken.app/Contents/Helpers/haken`へ同梱する。標準のmacOS filesystemでは`Contents/MacOS/Haken`と`Contents/MacOS/haken`が衝突するため、別の標準nested-code位置を使う。
- v0.1は`~/.local/bin/haken`からbundle内binaryへのsymlinkを推奨する。
- shell rcは自動変更しない。
- Homebrew Caskとinstaller packageは延期する。
- CLIを先に、外側のappを後にDeveloper ID署名する。
- Hardened Runtime、secure timestamp、Notarization、staplingをrelease要件にする。

### App Sandbox / Mac App Store

現在のChrome Profile操作は他appをAccessibility APIで操作するため、Mac App Store/Sandbox互換をv0.1の受け入れ条件にしない。CLIをHaken.appへ中継しても、AXを実行するHaken.app自身のSandbox制約は解消しない。

### Deferred

- `haken chrome current`
- `haken chrome resolve`
- `haken app resolve`
- 詳細diagnostics subcommands
- `haken jump`
- shell completion
- Homebrew Cask
- optimistic config ETag / `--if-match`
- MCP Server
- Chrome profile directory
- cloud/sync Store
- QuickDraw/Camelot共通package

`chrome current`は現在のAX情報から確実に判定できることを確認できていないため、別PoCまで実装しない。

## Required refactoring

- GUI状態と設定/Activationユースケースを分離し、GUIとIPCが同じCommand Serviceを呼ぶ。
- SwitchCoordinatorをfire-and-forgetから結果を返せる形にする。
- Application解決時の曖昧候補を拒否する。
- ChromeProfileAdapterへのアクセスとcache invalidationを同じexecutorへ集約する。
- Core matcherと実Adapterのselector条件重複を減らす。
- Config load errorの種類をCLIへ保持して返す。
- app起動時にwindowを必ず表示する処理へbackground launch modeを追加する。
- diagnosticsをtyped resultとして提供し、既存のredaction方針を保つ。

## Consequences

追加常駐processはなく、network portも開かない。Accessibility権限主体とConfig writerはそれぞれ一つに保たれる。一方、CLI commandはHaken.appへ依存し、app起動失敗時には操作できない。これは権限、cache、設定整合性を優先した意図的な制約である。
