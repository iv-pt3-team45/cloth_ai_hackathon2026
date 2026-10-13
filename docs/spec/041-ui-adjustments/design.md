# 設計: 画面の調整(解析の画面の配色・文字の見やすさ・アプリ名)

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-10-13

## 1. 設計方針

3 つとも画面だけの変更で、バックエンドと API は変えない(AC-10)。

| # | 方針 | 理由 |
| --- | --- | --- |
| 1 | 別の画面を開くときに今の `Theme` を包んで渡す処理を、`pushThemed`(`core/themed_route.dart`)にまとめる。解析の画面・ログインの画面・新規登録の画面で使う。背景のグラデーションは部品 `PaletteBackground` にまとめる | ログインの画面(spec 040)と同じ処理が 3 か所に増えるため。入力の画面・ログインの画面と同じ背景を同じ部品で描く |
| 2 | 配色を作るとき(`AppPalette.fromAccents`)に、「白」だけでなく、実際に文字を置く背景(選んだ項目の背景・ページの背景)に対しても 4.5:1 以上になるよう色を調整する。画面の部品は、カードの外に差し色の文字を置かないように直す | 部品ごとに色を直すより、配色の作り方で保証したほうが、今後部品が増えても崩れない |
| 3 | 表示名の文字列を差し替える | — |

却下した案:

| 案 | 理由 |
| --- | --- |
| 暗い配色のときに、背景の上に置く差し色の文字用の色(明るくした差し色)を `AppPalette` に足す | 背景の上の差し色の文字は 2 つのボタンだけで、`onBackground`(白)で足りる。色を増やすと確かめる組み合わせも増える |
| テーマ(`outlinedButtonTheme`)で、暗い配色のときのボタンを白にする | カードの中(白い背景)のボタンまで白になって見えなくなる |

## 2. 全体フロー

```
HomePage の AnimatedTheme(MV の配色)
  ├─ ③ 写真を入れる → pushThemed(context, WardrobeReviewScreen)   … 配色を包んで渡す(AC-1)
  ├─ ログイン        → pushThemed(context, LoginPage)              … 040 と同じ動き
  │                     └─ pushThemed(context, RegisterPage)
  └─ ダイアログ・シート … Flutter が自動で配色を引き継ぐ(変更なし)
```

## 3. API 設計

変更なし。

## 4. データモデル

### 4.1 コントラストの調整(`core/theme.dart`)

```dart
/// 2 色のコントラスト比(WCAG)
static double contrast(Color a, Color b);

/// [fg] を [bg] に対して [min] 以上の比になるまで調整する。
/// bg が明るければ fg の明度を下げ、暗ければ上げる。
static Color ensureContrast(Color fg, Color bg, {double min = 4.5});
```

今の `readableOnWhite(c)` は `ensureContrast(c, Colors.white)` と同じ意味になるので、中身をそれに置き換える。`contrastWithWhite` は残す(既存のテストが使う)。

### 4.2 `AppPalette.fromAccents` の色の決め方

**明るい配色**

1. `accent`: 明度を 0.02 ずつ下げていき、次をすべて満たしたところで止める。
   - 白に対して 4.5:1 以上
   - その accent から作る `selected`(白へ 92%)に対して 4.5:1 以上
   - その accent から作る `backgroundTop`(白へ 85%)に対して 4.5:1 以上

   `selected` と `backgroundTop` は accent から作るので、毎回作り直して確かめる。明度 0(黒)なら必ず満たす。
2. `accent2`: 白・`selected`・`backgroundTop`・`backgroundBottom` に対して 4.5:1 以上になるまで、明度を下げる。リンクがカルチャーのカード(`selected` の地)に載るため。
3. `onBackgroundMuted`: `AppColors.muted` を、`backgroundTop`・`backgroundBottom` に対して 4.5:1 以上になるまで暗くする(`ensureContrast`)。
4. `onBackground`(`AppColors.text`)は、どの背景に対しても十分に濃いので変えない(テストで確かめる)。

**暗い配色**

- `accent` / `accent2`: 今と同じで、白い文字を載せるために白に対して 4.5:1 以上にする。背景の上に差し色の文字は置かない(§5.3)。
- `onBackground`(白)・`onBackgroundMuted`(白 70%)は、暗い背景(輝度 0.1 未満)に対して十分なので変えない(テストで確かめる)。

**標準の配色(`AppPalette.standard`)** は定数のまま変えない(AC-8)。標準の差し色 `#D6334F` は、選んだ項目の背景 `#FDEEF1` に対して約 4.2:1 で少し足りない。ただ今回の範囲では、見た目を変えない(AC-8)ことを優先し、標準の配色はそのままにする。送信バー(§5.2)とカードの外の文字(§5.3)は、部品の側で 4.5:1 以上にする。これらは標準の配色でも見た目が変わる(標準の差し色も背景 `#F6F3EF` に対して約 4.3:1 で足りないため)。

## 5. フロントエンド設計

### 5.1 ファイル

| ファイル | 変更 |
| --- | --- |
| `core/themed_route.dart`(新規) | `pushThemed<T>(context, builder)` |
| `core/widgets.dart` | `PaletteBackground`(背景のグラデーション)を足す |
| `core/theme.dart` | `contrast`・`ensureContrast`、`fromAccents` の調整(§4) |
| `features/wardrobe/wardrobe_section.dart` | 解析の画面を `pushThemed` で開く |
| `features/wardrobe/wardrobe_review_screen.dart` | `PaletteBackground` を敷き、`AppBar` を透明・`onBackground` にする。「解析中 N / M」を `onBackground` にする |
| `features/auth/login_page.dart` / `auth_scaffold.dart` | `pushThemed`・`PaletteBackground` に置き換える(見た目は変えない) |
| `app/home_page.dart` | 背景を `PaletteBackground` に置き換える。送信バーのボタン(§5.2)。アプリ名 |
| `features/outfit/outfit_progress_view.dart` / `outfit_result_view.dart` | カードの外のボタンの色(§5.3) |
| `features/auth/login_card.dart` | `AccountStatus` のボタンの色(§5.3) |
| `main.dart`, `web/index.html`, `web/manifest.json` | アプリ名(§5.4) |

### 5.2 送信バーのボタン(AC-5)

| 状態 | 今 | 変更後 |
| --- | --- | --- |
| そろっている | 差し色の塗り・白い文字 | 変えない |
| そろっていない | 差し色 55% の塗り・白い文字(約 2.6:1) | `selected` の地・差し色の文字と 1.5px の枠。文字の色は `ensureContrast(accent, selected)` |

押すと足りないものを知らせる動きは今のまま(`onPressed` は常に有効)。

### 5.3 カードの外の文字(AC-6, AC-7)

- 「キャンセルして入力に戻る」(progress)・「条件を変えてもう一度」(result): `OutlinedButton` の文字を `palette.onBackground`、枠を `palette.onBackgroundMuted` にする。明るい配色では濃い文字、暗い配色では白になる。
- ヘッダの `AccountStatus` の「ログイン」「ログアウト」: 配色によらず文字を `palette.onBackground` にする(今は暗い配色のときだけ)。
- 解析の画面のタイトル・閉じるボタン・「解析中 N / M」: `palette.onBackground`(AC-3)。

### 5.4 アプリ名(AC-9)

次の 5 か所の「はじめてのライブ服」を「THE FIRST KITAKE」にする。説明文(meta description・ヘッダの説明)は変えない。

- `main.dart` の `MaterialApp.title`
- `home_page.dart` の `_Header`
- `web/index.html` の `<title>`・`apple-mobile-web-app-title`
- `web/manifest.json` の `name`・`short_name`

## 6. バックエンド設計

変更なし。

## 7. Gemini プロンプト設計

使わない。

## 8. エラーハンドリング / 非機能

- 対象外(requirements の非ゴール):
  - **配色が切り替わる途中の色:** `AppPalette.lerp` は、`dark` を t = 0.5 で切り替える。そのため約 0.4 秒の間は、中間の色になる。
  - **背景の動きが文字に重なる見え方。**
- 色の調整は、MV を選んだときに 1 回計算するだけ(明度 0.02 刻みで最大 50 回)なので、性能への影響は無い。

## 9. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| frontend unit | `contrast`・`ensureContrast` | `test/culture_vibe_test.dart`。明るい背景・暗い背景での調整、すでに足りていれば変えないこと |
| frontend unit | `fromAccents` の配色 | 色の辞書のすべての色と、辞書に無い色(灰・黒)で、明るい配色・暗い配色のそれぞれについて §4.2 の比が 4.5:1 以上(AC-4) |
| frontend widget | 解析の画面 | MV で配色を変えたあと写真を入れると、解析の画面の `AppPalette` が入力の画面と同じ。MV なしなら標準(AC-1〜3) |
| frontend widget | 送信バー・カードの外のボタン・ヘッダ | 描画された文字の色と背景の比が 4.5:1 以上(AC-5〜7)。標準の配色の見た目が変わらない既存のテストが通る(AC-8) |
| frontend widget | アプリ名 | ヘッダに「THE FIRST KITAKE」(AC-9) |
