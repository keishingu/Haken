# ADR-0001: MVPの未決事項に関する最小判断

- Status: Accepted
- Date: 2026-08-13

HakenのMVPでは、Chrome Accessibilityツリーから安定したProfile IDを取得する方法は未検証のため、Profile表示名を照合キーとする。同名候補は安全側に倒して実行しない。

通常Applicationは未起動なら起動する。Google Chrome本体をApplication Targetに選ぶ場合はChrome全体をactivateし、特定Profileは選ばない。ProfileのAXPressはChromeが要求を受理した時点を成功とする。

アプリはDockに表示する通常のmacOSアプリとして開始し、Carbon `RegisterEventHotKey`を使用する。未割り当てSlotは登録しない。Carbonが実機で要件を満たさないと確認できるまで、権限範囲が広いイベントタップは導入しない。
