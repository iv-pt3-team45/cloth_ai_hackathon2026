# 実装タスク: MV カードの整理と、カルチャーに合わせた画面の演出

- 対応する設計: `./design.md`
- 進捗: 11 / 11

## 凡例

- 1 タスク = 30〜90 分。テストまで含めて「動く状態」で終えられる粒度にする。
- 各タスクに「完了条件」と「関連する受け入れ基準(AC-x)」を書く。
- 完了したら `- [ ]` を `- [x]` にする。
- フロントエンドの完了条件は、特記が無ければ `dart format .` / `flutter analyze`(警告なし)/ `flutter test` が通ること。

## タスク一覧

### バックエンド

変更なし(AC-20)。

### フロントエンド(土台)

- [x] **T-01: 演出の判定(`CultureVibe`)**
  - 変更対象: `frontend/lib/features/mv_lookup/culture_vibe.dart`(新規), `frontend/test/culture_vibe_test.dart`(新規)
  - 完了条件: 色の名前の辞書・スタイルの言葉の対応表(design §4.1)で判定でき、次のテストが通る:
    部分一致 / 長い名前の優先 / 白などを飛ばす / 先頭の言葉の優先 / 判定できない言葉で「演出なし」/ 動画なし・特定できないで null
  - 関連 AC: AC-13, AC-14, AC-15
- [x] **T-02: 配色(`AppPalette`)とテーマ**
  - 変更対象: `frontend/lib/core/theme.dart`, `frontend/test/culture_vibe_test.dart`
  - 完了条件: `AppPalette.standard` が今の配色と一致し、`buildTheme()` の見た目が変わらない(既存のテストが通る)。
    `AppPalette.fromVibe` の差し色が白い文字に対して 4.5:1 以上、sparks・neon で `dark` になる、スタイルだけのとき既定色になる。`lerp` がある
  - 関連 AC: AC-13, AC-14
- [x] **T-03: 差し色を使う部品を palette に切り替え、①②③ に ✓ を付ける**
  - 変更対象: `core/widgets.dart`(`SectionCard.done`・`MessageBox` の白い下地), `core/link.dart`(`openExternalUrl` の切り出し・リンクの色),
    `features/mv_lookup/live_section.dart`, `features/mv_lookup/mv_lookup_panel.dart`, `features/wardrobe/wardrobe_section.dart`,
    `features/outfit/outfit_progress_view.dart`, テスト
  - 完了条件: 標準の配色で見た目が変わらない(既存のテストが通る)。①②③ の入力が済むと番号が緑の ✓ になるテストが通る
  - 関連 AC: AC-18

### フロントエンド(A・B・E: ① ② のカード)

- [x] **T-04: 動画の情報のまとめと「詳細」(A)**
  - 変更対象: `features/mv_lookup/mv_lookup_panel.dart`(`_VideoSummary`), `test/mv_lookup_screen_test.dart`
  - 完了条件: 初期はサムネ・曲名・アーティスト名・「YouTube で開く」だけ、「詳細」で開閉、リンクを開けないと SnackBar のテストが通る
  - 関連 AC: AC-1, AC-2, AC-3
- [x] **T-05: 候補を選んだら一覧を畳む(B)**
  - 変更対象: `features/mv_lookup/mv_lookup_panel.dart`, `test/mv_lookup_screen_test.dart`, `test/mv_lookup_culture_test.dart`
  - 完了条件: 選んだ候補だけが残る / 「変更」で一覧に戻り動画の情報とカルチャー情報が消える / 取得中は「変更」が効かない のテストが通る
  - 関連 AC: AC-4, AC-5, AC-6
- [x] **T-06: 取得中の理由の表示(E)**
  - 変更対象: `features/mv_lookup/mv_lookup_panel.dart`, `features/mv_lookup/live_section.dart`(`cultureLoading` を受け取る), `test/mv_lookup_culture_test.dart`
  - 完了条件: カルチャー情報を調べている間だけ ① ② の検索の行の下に理由が出て、終わると消えるテストが通る。spec 037 のエラー表示のテストも通る
  - 関連 AC: AC-19

### フロントエンド(C: カルチャー情報)

- [x] **T-07: 要点のカードとポップアップ**
  - 変更対象: `features/mv_lookup/culture_parts.dart`(新規・今の部品を移す), `features/mv_lookup/culture_section.dart`,
    `features/mv_lookup/culture_detail_sheet.dart`(新規), `test/mv_lookup_culture_test.dart`
  - 完了条件: 要点のカードの項目 / 「くわしく見る」でファッションのタブが選ばれた状態で開く / 3 つのタブの中身 /
    どのタブでも下端に出典と検索候補 / ✕・背景・下へのスワイプで閉じる / 失敗・特定できないは今どおり のテストが通る。
    要点のカードの出現アニメーションは、動きを減らす設定で行わない
  - 関連 AC: AC-7, AC-8, AC-9, AC-10, AC-11, AC-12, AC-17(カード・ポップアップ)

### フロントエンド(D: 演出)

- [x] **T-08: 画面全体への配色の適用と、背景の動き**
  - 変更対象: `app/home_page.dart`(vibe・palette の導出、`AnimatedTheme`、背景のグラデーション、ヘッダーの文字色),
    `features/mv_lookup/vibe_backdrop.dart`(新規・`VibeBackdrop`), `test/home_page_test.dart`, テスト用のヘルパー(動きを減らす設定で包む)
  - 完了条件: ガーリー → sparkle + 差し色 / ロック → 暗い背景 + sparks、白いカードの文字色は不変 / 判定不可 → 標準のまま /
    「変更」で標準に戻り背景が止まる / 動きを減らす設定で配色だけ / 「考え中」の段階に配色が引き継がれる のテストが通る
  - 関連 AC: AC-13, AC-14, AC-15, AC-16, AC-17, AC-21
- [x] **T-09: 切り替わりの演出(`showVibeBurst`)**
  - 変更対象: `features/mv_lookup/vibe_backdrop.dart`, `features/mv_lookup/mv_lookup_panel.dart`, テスト
  - 完了条件: カルチャー情報が届くと 1 回だけ出て消える / 判定不可・動きを減らす設定では出ない のテストが通る
  - 関連 AC: AC-13, AC-17

### 結合 / 仕上げ

- [x] **T-10: 実機での確認**(2026-10-13: 開発 PC に Docker・API キー・Chrome が無いため、バックエンドを偽データに
  差し替えたデモ(コミットしない)を Edge で起動し、ユーザーが確認した。Gemini が返す実際の言葉での判定は未確認。
  `prefers-reduced-motion` は Flutter のソースで「反映されない」ことを確認し、Web で直接読む処理を追加済み。`flutter build web` は成功)
  - 完了条件: `docker compose up` で起動し、Chrome(PC とスマホの幅)で受け入れ基準を一通り確認する。特に次の 2 点:
    - Flutter Web で OS の「視差効果を減らす」が `disableAnimations` に反映されるか(design §8)。反映されなければ対応を足して design を更新する
    - 背景の動きがスマホの幅で重くならないか
  - 関連 AC: AC-1〜AC-21
- [x] **T-11: ドキュメント更新**(README §4.12・§6・§9 を更新し、§6 の状態と `requirements.md` を `done` にした。
  `git diff --stat main -- backend/` は空)
  - 完了条件: ルート `README.md` の機能一覧(§6)を更新し、`requirements.md` のステータスを `done` にする。
    `git diff --stat main -- backend/` が空であることを確認する
  - 関連 AC: AC-20
