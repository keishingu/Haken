# HakenのmacOS直接配布

HakenはDeveloper ID Applicationで署名し、Appleのnotary serviceでAcceptedとなったDMGをGitHub Releaseから配布します。対象はmacOS 15以降のarm64・x86_64 Universal appです。DMGには`Haken.app`とApplicationsへのリンクが入ります。アプリ内のCLIは`Contents/Helpers/haken`に、AI Skillは`Contents/Resources/Skills/haken-control`に同梱します。

## GitHub Actionsの設定

Repository Variablesに次を登録します。

| Name | 内容 |
|---|---|
| `APPLE_TEAM_ID` | Developer ID証明書のTeam ID |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |

Repository Secretsに次を登録します。

| Name | 内容 |
|---|---|
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Developer ID Application証明書と秘密鍵を含むp12のBase64 |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | p12のexport password |
| `APP_STORE_CONNECT_API_KEY_P8_BASE64` | notarization用API keyのp8 Base64 |

証明書と秘密鍵、p12 password、API keyはGitHub Actions Secretsにのみ置き、リポジトリへ追加しません。`Developer ID Installer`証明書は不要です。

2026-10-02時点ではこれらのVariablesとSecretsは未設定です。登録するまではrelease workflowは署名・公証の段階で失敗します。設定だけでは公開されません。

## Release作成

1. GitHub Actionsの`Build notarized Haken DMG`を手動実行し、versionと正の整数build numberを入力します。
2. `publish`は初期値OFFです。OFFなら署名・公証済みDMGとSHA-256 checksumを7日間のActions artifactとして保存します。
3. 初回配布では`main`で実行し、`publish`をONにしてGitHub Releaseを作成します。workflowは`main`以外での公開を拒否します。
4. `https://github.com/keishingu/Haken/releases/latest/download/Haken-macos-universal.dmg`を開き、HTTP 200とDMGのdownloadを確認します。
5. `docs/site/index.html`の「配布準備中」をこのDownload URLへのリンクに差し替えます。FAQ、`support.html`の未公開表示と導入手順、READMEの未公開表示も更新し、サイトを手動公開します。Pages公開はREADMEの手順を参照してください。

GitHub Releaseができる前にLPへDownload URLを載せません。初回Release作成、Download URL確認、LPのリンク更新、Pages公開の順で行います。

WorkflowはアプリとCLIをarm64・x86_64でビルドし、CLIを先にDeveloper ID署名してからアプリを署名します。DMGを公証に提出し、結果が`Accepted`と明示された場合だけstapleし、staple検証、Gatekeeper、署名、DMG検証を通してchecksumを作ります。検証に失敗した場合はartifactとReleaseを作成しません。

## ローカルビルド

Xcode 26.3とDeveloper ID証明書のあるMacで実行します。アプリの最低対応OSはmacOS 15ですが、macOS 26向けHUD APIもコンパイルするため新しいSDKが必要です。CIの検証・配布workflowは両方ともXcode 26.3を明示指定します。

```sh
BUILD_NUMBER=1 \
MARKETING_VERSION=0.1.0 \
SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
Scripts/build-direct-release.sh
```

出力は`build/release/Haken-macos-universal.dmg`です。ローカル実行は公証や公開を行いません。入力検証のsmoke checkは`python3 Scripts/smoke-direct-release.py`で実行でき、Swiftビルド、署名、ネットワーク接続は使いません。

既存の成果物を保護するため、`build/release`が存在する場合は上書きせず停止します。再ビルドには新しいチェックアウトを使うか、必要な成果物を保管してから出力先を整理してください。署名済みアプリが完成していてDMGだけを再作成する場合は、DMGがまだ存在しない状態で、同じ`SIGNING_IDENTITY`を指定して`Scripts/package-direct-release.sh`を実行できます。

初回公開前には、公証済みDMGを別のMacでダウンロードし、Applicationsへのコピー、通常起動、アプリ切り替え、Chromeの許可・プロファイル切り替え、CLIのインストールと実行を確認してください。ローカルの署名検証だけでは、ダウンロード後のGatekeeperや実際の操作を確認したことにはなりません。

GitHub Releaseの各バージョンにはDMGと`.sha256`を添付します。App Store、更新機構、ライセンス発行、サイト公開はこの配布フローの対象外です。

GitHub Pagesの構成は[公式のカスタムワークフロー手順](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)を参照してください。サイトはフレームワークやビルド依存を持たず、`docs/site`をそのまま配信します。

## ローカル確認済みの範囲（2026-10-02）

- Swiftテスト11件、Swift format lint、配布スクリプトの入力拒否・模擬ビルド／署名／DMG生成チェックが成功しました。
- GUIとCLIのarm64・x86_64 Releaseビルド、Universal結合、Developer ID署名に成功しました。`build/release/Haken-macos-universal.dmg`を実際に生成し、マウント内のアプリ・CLI署名とDMG整合性を確認しました。
- LP・サポート・プライバシーの3ページのリンク確認と、320〜1440pxの6幅での表示、デモのクリック・キーボード操作、FAQ、JavaScriptなしの本文表示を確認しました。
- Apple公証、GitHub Actions上での実行、Release／Pages公開、ダウンロード後の別Macでの操作確認は未実施です。今回のローカルDMGは未公証の検証用です。
