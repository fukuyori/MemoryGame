# Memory Game

SwiftUI で作成した神経衰弱ゲームです。  
難易度切り替え、プレイ時間計測、履歴表示、カード裏面デザイン選択に対応しています。

## 機能

- 難易度切り替え
  - 初級: 6ペア
  - 中級: 8ペア
  - 上級: 10ペア
- 手数、経過時間、ペア数の表示
- 手数とタイムの履歴表示
- 最大時間、最小時間、平均時間の集計表示
- 一致時のハイライト演出
- プレイ履歴の保存
- 履歴画面でのレベル別集計表示
- 履歴の全削除
- カード裏面デザインの初回選択

## 動作環境

- Xcode
- SwiftUI
- iPhone / iPad / 対応 Apple プラットフォーム

## 実行方法

1. `Cards.xcodeproj` を Xcode で開く
2. 実行先を選ぶ
3. `Run` でビルド・起動する

## 画面概要

- ゲーム画面
  - 難易度選択
  - カード一覧
  - 手数 / 時間 / ペア数の表示
  - もう一度遊ぶボタン
- 履歴画面
  - レベル別集計
  - 直近10回の履歴
  - 全履歴削除

## 素材について

### カード裏面デザイン

カード裏面デザインの参考元:

- トヨシコー カードデザイン集
  - https://aaatoyo.com/card-design.htm

このアプリでは、上記ページの雰囲気を参考にした裏面デザインを SwiftUI で描画しています。

### カード表面画像

カード表面画像ファイルは以下に配置しています。

- `Cards/Cards/CardImages/`

対象例:

- `card-spades-A.png`
- `card-hearts-K.png`
- `card-diamonds-10.png`
- `card-clubs-2.png`

カード表面画像の出典:

- チコデザ
  - https://chicodeza.com/freeitems/torannpu-illust.html

## プロジェクト構成

- `Cards/Cards/ContentView.swift`
  - メイン画面、ゲームロジック、履歴表示
- `Cards/Cards/CardsApp.swift`
  - アプリ起動エントリ
- `Cards/Cards/CardImages/`
  - カード画像
- `Cards/Cards/Assets.xcassets`
  - アセットカタログ

## 備考

- プレイ履歴は端末内に保存されます
- 前回終了時の難易度を次回起動時に復元します
- `.gitignore` で `DerivedData` や `xcuserdata` などのローカル生成物は除外しています
