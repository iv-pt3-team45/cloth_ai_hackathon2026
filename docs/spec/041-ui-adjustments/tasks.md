# 実装タスク: 画面の調整(解析の画面の配色・文字の見やすさ・アプリ名)

- 対応する設計: `./design.md`
- 進捗: 6 / 6

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 各タスクに「完了条件」と「関連する受け入れ基準(AC-x)」を書く。
- 完了したら `- [ ]` を `- [x]` にする。
- フロントエンドの完了条件は、特記が無ければ `dart format .` / `flutter analyze`(警告なし)/ `flutter test` が通ること。

## タスク一覧

### バックエンド

変更なし(AC-10)。

### フロントエンド

- [x] **T-01: コントラストの調整と配色の作り方(`core/theme.dart`)**
  - 変更対象: `frontend/lib/core/theme.dart`, `frontend/test/culture_vibe_test.dart`
  - 完了条件: `contrast`・`ensureContrast` を足し、`fromAccents` を design §4.2 のとおりにする。
    色の辞書のすべての色と、灰・黒で、明るい配色・暗い配色の比が 4.5:1 以上になるテストが通る。`AppPalette.standard` は変えない
  - 関連 AC: AC-4, AC-8
- [x] **T-02: `pushThemed` と `PaletteBackground`**
  - 変更対象: `core/themed_route.dart`(新規), `core/widgets.dart`, `app/home_page.dart`, `features/auth/login_page.dart`, `features/auth/auth_scaffold.dart`
  - 完了条件: 入力の画面・ログインの画面・新規登録の画面を新しい部品に置き換えても、見た目と動きが変わらない(既存のテストが通る)
  - 関連 AC: AC-8
- [x] **T-03: 解析の画面の配色**
  - 変更対象: `features/wardrobe/wardrobe_section.dart`, `features/wardrobe/wardrobe_review_screen.dart`, テスト
  - 完了条件: MV で配色を変えたあと写真を入れると、解析の画面の配色が入力の画面と同じになる。MV なしなら標準。
    暗い配色でタイトル・「解析中 N / M」が `onBackground` になる。この 3 点のテストが通る
  - 関連 AC: AC-1, AC-2, AC-3
- [x] **T-04: 送信バー・カードの外のボタン・ヘッダの文字の色**
  - 変更対象: `app/home_page.dart`(`_SubmitBar`), `features/outfit/outfit_progress_view.dart`, `features/outfit/outfit_result_view.dart`, `features/auth/login_card.dart`, テスト
  - 完了条件: 描画された文字の色と背景の比が 4.5:1 以上になるテストが通る。対象は次の 3 つ:
    - 送信バーの「そろっていない」ボタン(標準の配色・MV の配色)
    - 暗い配色の「キャンセルして入力に戻る」と「条件を変えてもう一度」
    - 明るい配色のヘッダの「ログイン」
  - 関連 AC: AC-5, AC-6, AC-7
- [x] **T-05: アプリ名**
  - 変更対象: `main.dart`, `app/home_page.dart`, `web/index.html`, `web/manifest.json`, `test/home_page_test.dart`
  - 完了条件: ヘッダ・タイトル・タブ・manifest が「THE FIRST KITAKE」になり、テストが通る
  - 関連 AC: AC-9

### 結合 / 仕上げ

- [x] **T-06: ドキュメント更新**
  - 変更対象: `README.md`(§2.4・§2 の `web/` の説明・§4・§6), `requirements.md`
  - 完了条件: README を更新し、`git diff --stat main -- backend/` が空であることを確かめ、`requirements.md` を `done` にする。
    画面の確認はユーザーが行う
  - 関連 AC: AC-10
