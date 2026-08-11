# Chrome プロファイル切替 PoC

## 目的

Karabiner-Elements の `Option + 数字` を起点に、Google Chrome の特定プロファイルのウィンドウだけを foreground（前面）にする方法を検証した。

公開用の設定例は次のとおり。プロファイル名は各自の Chrome 環境に合わせて変更する。

| ショートカット | Chrome プロファイル |
| --- | --- |
| `Option + 1` | `Personal` |
| `Option + 2` | `Work` |
| `Option + 3` | `Side Project` |

## 検証の経緯

### 1. `open` コマンドではプロファイル単位に foreground 化できなかった

最初に、Chrome のプロファイルディレクトリを指定して起動・foreground 化する方法を試した。

```bash
open -a 'Google Chrome' --args --profile-directory='Profile 1'
```

この方法では対象プロファイルだけでなく、Chrome 全体に属する全プロファイルのウィンドウが foreground になった。macOS から見ると各プロファイルは独立したアプリではなく、同じ Google Chrome プロセス／アプリとして扱われるため、目的の挙動にはならなかった。

### 2. Chrome UI のプロファイル選択は期待どおりに動いた

一方、Chrome の UI からプロファイルを選択すると、選択したプロファイルのウィンドウだけが foreground になることを確認した。

この挙動をプログラムから再現できれば、目的を達成できると考えた。

### 3. Accessibility ツリーからプロファイル切替要素を発見した

Chrome の Accessibility（AX）ツリーを dump して調査したところ、プロファイルに対応する要素が見つかった。

プロファイルボタン側には、次のような要素があった。

```text
AXButton description: <profile> actions: AXPress
```

さらにメニューバー配下には、プロファイル切替用と思われる次の要素があった。

```text
AXMenuItem title: <profile> identifier: switchToProfileFromMenu: actions: AXPress
```

`identifier` が `switchToProfileFromMenu:` の `AXMenuItem` を押せば、Chrome UI でプロファイルを選択した場合と同じ挙動を再現できそうだと分かった。

### 4. Swift から `AXPress` してプロファイル単位の切替に成功した

[`switch-profile.swift`](./switch-profile.swift) では、起動中の Google Chrome を取得し、Chrome 全体ではなく `AXMenuBar` 配下だけを再帰的に探索する。

探索条件は次の3点。

- role が `AXMenuItem`
- title が引数で渡した対象プロファイル名と一致
- identifier が `switchToProfileFromMenu:`

一致した要素に `AXPress` を実行すると、対象プロファイルのウィンドウだけを foreground にできた。

単体での実行例：

```bash
/usr/bin/swift "/Users/yourname/path/to/Haken/PoC/switch-profile.swift" "Personal"
```

Chrome が起動していない場合や対象プロファイルが見つからない場合はエラーになる。プロファイル名は Chrome UI／Accessibility ツリー上の表記と完全一致させる必要がある。

## Karabiner-Elements からの呼び出し

### Accessibility 権限

ターミナルからは動作したが、Karabiner の `shell_command` から実行した当初は次のエラーになった。

```text
Chrome menu bar not found.
```

原因は、`shell_command` の実行主体である `karabiner_console_user_server` が Chrome の Accessibility ツリーを読み取れなかったことだった。

macOS の「システム設定」→「プライバシーとセキュリティ」→「アクセシビリティ」で `karabiner_console_user_server` に権限を付与したところ、Karabiner からも正常に切り替えられた。

権限変更後に反映されない場合は、Karabiner-Elements または `karabiner_console_user_server` の再起動が必要になることがある。

### Karabiner 設定例

PoC では `$HOME` に依存せず、Swift ファイルの絶対パスを使う。JSON 内の `shell_command` はシングルクォートでパスとプロファイル名を囲むと、括弧や空白を安全に扱えて読みやすい。

以下は `profiles[].complex_modifications.rules[]` に追加するルールの例。

```json
{
  "description": "Haken: Option+1/2/3 → Chrome profiles",
  "manipulators": [
    {
      "type": "basic",
      "from": {
        "key_code": "1",
        "modifiers": {
          "mandatory": ["option"],
          "optional": ["any"]
        }
      },
      "to": [
        {
          "shell_command": "/usr/bin/swift '/Users/yourname/path/to/Haken/PoC/switch-profile.swift' 'Personal'"
        }
      ]
    },
    {
      "type": "basic",
      "from": {
        "key_code": "2",
        "modifiers": {
          "mandatory": ["option"],
          "optional": ["any"]
        }
      },
      "to": [
        {
          "shell_command": "/usr/bin/swift '/Users/yourname/path/to/Haken/PoC/switch-profile.swift' 'Work'"
        }
      ]
    },
    {
      "type": "basic",
      "from": {
        "key_code": "3",
        "modifiers": {
          "mandatory": ["option"],
          "optional": ["any"]
        }
      },
      "to": [
        {
          "shell_command": "/usr/bin/swift '/Users/yourname/path/to/Haken/PoC/switch-profile.swift' 'Side Project'"
        }
      ]
    }
  ]
}
```

ターミナルで動作確認するときは JSON 用のエスケープをそのまま入力せず、通常のシェルコマンドとしてクォートする。

## 技術的な結論

- `open -a 'Google Chrome' --args --profile-directory=...` では Chrome アプリ全体が foreground になり、プロファイル単位の制御はできない。
- Chrome 自身のプロファイル選択 UI は、対象プロファイルだけを foreground にできる。
- Chrome の `AXMenuBar` にある `identifier: switchToProfileFromMenu:` の `AXMenuItem` を `AXPress` することで、その UI 操作を Swift から再現できる。
- Karabiner の `shell_command` から AX API を使う場合、実行主体の `karabiner_console_user_server` に macOS Accessibility 権限が必要になる。
- 今回の PoC により、「ショートカットから特定の Chrome プロファイルだけを前面に出す」ことは技術的に実現可能だと確認できた。

## Haken 製品化への示唆

PoC としては Karabiner JSON と Swift スクリプトの組み合わせで成立したが、一般ユーザーに次の作業を求めるのは難しい。

- Karabiner-Elements の導入と JSON の手動編集
- Swift スクリプトの配置と絶対パスの管理
- Chrome 上の正確なプロファイル名の把握
- macOS Accessibility 権限の設定とトラブルシュート

そのため、Haken として GUI 化する価値がある。たとえば、Chrome プロファイルの検出、ショートカットの割り当て、Accessibility 権限の案内、切替動作のテストまでをアプリ内で完結させれば、今回確認した技術を一般ユーザーにも扱える形で提供できる。

また、製品化時は Swift スクリプトを都度起動する構成ではなく、Accessibility 権限を持つ Haken 本体または専用 helper が切替処理を担う構成を検討すると、配布・権限管理・エラー表示を一元化しやすい。
