# 設計: MV カードの整理と、カルチャーに合わせた画面の演出

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-10-13

## 1. 設計方針

フロントエンドだけを変える。カルチャー情報(`CultureReport`)から「演出の設定」(**CultureVibe**: 差し色と背景の動きの種類)を
**純粋な関数で導き出し**、それを画面全体の配色(**AppPalette**)と背景の動き(**VibeBackdrop**)に流す。
新しい状態は持たず、MV の選択・カルチャー情報の有無から毎回導き出すので、「変更」で選択を外せば自然に元へ戻る(AC-16)。

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | `ThemeExtension`(AppPalette)を `HomePage` で `AnimatedTheme` に載せ、差し色を使う部品は `AppPalette.of(context)` で読む | 採用 | Flutter の標準の仕組みだけで済む(依存の追加なし)。ポップアップ(`showModalBottomSheet`)もテーマを引き継ぐ。「考え中」「提案」の段階にもそのまま効く(未決事項 2) |
| B | `AppColors.accent` を書き換えられる変数にする | 却下 | 再描画のきっかけが無く、テストどうしで状態が漏れる |
| C | 演出の判定に Gemini を呼び直す / バックエンドで色を返す | 却下 | 非ゴール(バックエンド・API は変えない) |
| D | 背景の動きを Lottie・パッケージで描く | 却下 | 依存の追加が必要。`CustomPainter` で数十個の粒を描けば足りる |

## 2. 全体フロー

```
MvLookupPanel ── onChanged(MvLookupSnapshot) ──> HomePage
   │                                               │ vibe = CultureVibe.from(snapshot)   … video と identified なカルチャー情報があるときだけ
   │                                               │ palette = AppPalette.fromVibe(vibe) … 無ければ AppPalette.standard
   │                                               ├─ AnimatedTheme(buildTheme(palette))  … 差し色・背景のグラデーション
   │                                               └─ VibeBackdrop(effect: vibe.effect)   … カードの後ろで粒を流し続ける
   │
   └─ カルチャー情報が届いた瞬間に 1 回だけ VibeBurst(選んだ候補の位置から色が広がって消える)
```

状態の変化と見た目:

| 状態 | 配色 | 背景の動き | 切り替わりの演出 |
| --- | --- | --- | --- |
| MV 未選択 / 調べている途中 / 失敗 / 特定できない | 標準 | なし | なし |
| 届いた・色だけ判定できた | MV の色 | なし | あり |
| 届いた・色とスタイルを判定できた | MV の色 | あり | あり |
| 届いた・スタイルだけ判定できた | 演出の既定色(§4.2) | あり | あり |
| どちらも判定できない | 標準 | なし | なし |
| 「変更」・新しい検索で選択が外れた | 標準に戻る | 止まる | なし |
| 動きを減らす設定 | 上と同じ | なし | なし |

## 3. API 設計

変更なし。`MvLookupSnapshot` の中身とコーデ提案に送る内容も変えない(AC-20)。

## 4. データモデル

### 4.1 `CultureVibe`(新規・`features/mv_lookup/culture_vibe.dart`)

```dart
enum VibeEffect { sparkle, sparks, petals, neon }

class CultureVibe {
  final Color? accent;      // よく使う色から判定した差し色(無ければ null)
  final Color? accent2;     // 2 色目(無ければ accent から作る)
  final VibeEffect? effect; // スタイルから判定した背景の動き(無ければ null)
  bool get isNone => accent == null && effect == null;

  /// 動画と、特定できたカルチャー情報があるときだけ判定する。それ以外は null。
  static CultureVibe? from(MvVideo? video, CultureReport? culture);
}
```

- **色**: `fashion.colors` を先頭から見て、色の名前の辞書(日本語・カタカナ・英語。例: 赤 / レッド / red、ピンク、水色、ネイビー、ゴールド …)と
  **部分一致**した最初の 2 色を使う。長い名前から先に照合する(「ショッキングピンク」→ ピンク、「水色」が「色」に負けない)。
  白・生成り・アイボリーなど明るすぎて差し色にならない色は飛ばす。
- **スタイル**: `fashion.styles` を先頭から見て、下表の言葉と部分一致した最初の演出を使う(大文字小文字・全角半角は区別しない)。
  1 つの言葉に複数の演出の言葉が含まれるときは、長く一致したほうを使う(「サイバーパンク」→ ネオン、「ガーリーロック」→ きらめき)。

  | 演出 | 照合する言葉(例) |
  | --- | --- |
  | sparkle(きらめき) | ガーリー / ポップ / キュート / アイドル / かわいい / ロリータ / girly / pop / cute / idol |
  | sparks(火花) | ロック / パンク / ハード / メタル / グランジ / rock / punk / metal / grunge |
  | petals(花びら) | ナチュラル / レトロ / フォーク / 森ガール / ヴィンテージ / 和 / natural / retro / folk / vintage |
  | neon(ネオン) | エレクトロ / クラブ / ダンス / サイバー / テクノ / ストリート / Y2K / electro / club / dance / cyber / techno |

- 判定できない言葉は無視する(例外を出さず「演出なし」に倒す)。

### 4.2 `AppPalette`(新規・`core/theme.dart` の `ThemeExtension`)

`core/` が `features/` に依存しないよう、`AppPalette` は差し色から作る `AppPalette.fromAccents` までを持ち、
演出の設定からの変換(既定色の選択を含む)は `CultureVibe.paletteOf(vibe)` に置く。

| 項目 | 標準(今と同じ) | MV の色のとき |
| --- | --- | --- |
| `accent` | `AppColors.accent` | 判定した色。**白い文字とのコントラストが 4.5:1 以上になるまで明度を下げる** |
| `accent2` | `AppColors.accent2` | 2 色目(無ければ accent の色相を 40° ずらす)。同じく 4.5:1 以上に調整 |
| `selected` | `AppColors.selected` | accent を白に 92% 混ぜた薄い色 |
| `backgroundTop` / `backgroundBottom` | `AppColors.bg` / `AppColors.bg` | 明るい演出: accent を白に 85% / 95% 混ぜた色。暗い演出(sparks・neon): `#1A1420` 前後に accent を 15% 混ぜた色 |
| `onBackground` / `onBackgroundMuted` | `AppColors.text` / `AppColors.muted` | 暗い演出のときは白 / 白 70% |
| `dark` | false | sparks・neon のとき true |

- スタイルだけ判定できたときの既定色: sparkle = `#E0457B`、sparks = `#E03A1E`、petals = `#B5734A`、neon = `#7A3CF0`。
- `lerp` を実装し、`AnimatedTheme`(400ms)で滑らかに切り替える(動きを減らす設定では 0ms)。
- `AppColors` の定数は残す(標準の値と、差し色以外の色 — 文字・枠・ok・ng — は今のまま)。

## 5. フロントエンド設計

### 5.1 変更・追加するファイル

| ファイル | 内容 |
| --- | --- |
| `core/theme.dart` | `AppPalette`(ThemeExtension)と `buildTheme({AppPalette palette})`。ColorScheme の primary / secondary も palette から作る |
| `core/widgets.dart` | `SectionCard` に `done`(番号の丸を緑の ✓ に)を追加。差し色は palette から読む。`MessageBox` は暗い背景でも読めるよう白の下地の上に色を重ねる |
| `core/link.dart` | 開く処理を `openExternalUrl(context, url)` に切り出し(「YouTube で開く」と共用)。リンクの色は palette から読む |
| `core/reduce_motion.dart`(+ `_stub` / `_web`) | **新規**。動きを減らす設定の判定(§8) |
| `app/home_page.dart` | vibe / palette を導き出し、`AnimatedTheme` と背景(グラデーション + `VibeBackdrop`)を敷く。`Scaffold` の背景は透明にする。ヘッダーの文字は `onBackground` |
| `features/mv_lookup/culture_vibe.dart` | **新規**。§4.1 の判定(純粋な関数) |
| `features/mv_lookup/vibe_backdrop.dart` | **新規**。背景の動き(`CustomPainter`)と、切り替わりの演出 `showVibeBurst` |
| `features/mv_lookup/mv_lookup_panel.dart` | 動画の情報のまとめ(A)、候補を畳む(B)、① の ✓ と取得中の理由(E)、届いたときに VibeBurst を出す |
| `features/mv_lookup/culture_section.dart` | 要点のカード(C)。調べている途中・失敗・特定できない の表示は今のまま |
| `features/mv_lookup/culture_detail_sheet.dart` | **新規**。くわしく見るポップアップ(C) |
| `features/mv_lookup/live_section.dart` | ② の ✓ と取得中の理由(E)。差し色を palette から読む |
| `features/wardrobe/wardrobe_section.dart` | ③ の ✓(E) |
| `features/outfit/outfit_progress_view.dart` | 差し色のグラデーションを palette から読む(レイアウトは変えない) |

### 5.2 A. 動画の情報(`_VideoSummary`)

```
[サムネ 120px] 曲名(太字)
               アーティスト名(灰)
               [↗ YouTube で開く]  [詳細 ▾]
(タイトルを分解できなかった注記 … 今どおり)
── 詳細を開いたときだけ(AnimatedSize) ──
動画タイトル / チャンネル / 公開日 / 概要欄
```

- 「詳細」の開閉は `_VideoSummary` の State に持つ(初期は閉)。動画が変わると閉じた状態から始まる(キーに videoId)。
- 「YouTube で開く」は `openExternalUrl` を使う。開けなければ今の `ExternalLink` と同じ SnackBar「リンクを開けませんでした」(AC-3)。

### 5.3 B. 候補を畳む

- `_expandedVideoId` が null でない間は、その候補だけを描く(他は描かない)。見出し「見つかった動画(n 件)」は「選んだ動画」に変える。
- 選んだ候補の右端は「閉じる」→「**変更**」(② と同じ文言・色)。タップの処理は今の `_onCandidateTap` の「閉じる」と同じ
  (`_expandedVideoId` / `_video` / `_culture` / `_cultureError` を消す)ので、一覧に戻り動画の情報とカルチャー情報も消える(AC-5)。
- 取得中は今どおり `onTap: null`(AC-6)。

### 5.4 C. 要点のカードとポップアップ

**要点のカード**(`CultureSection` の「届いた」ときの表示を置き換える)

- 中身: 見出し「カルチャー情報」・アーティスト名 / スタイル(Pill) / よく使う色(Pill の左に色の丸。辞書に無い色は丸なし) /
  この MV の衣装(シーンごとの 1 行要約を最大 2 件 +「ほか n 件」) / 出典と検索候補(`GroundingFooter` をそのまま) /「くわしく見る」ボタン。
- 背景は palette の `selected` → 白 のグラデーション(文字は今の濃い色のまま)。
- 出現: 1 つの `AnimationController`(900ms)で、カード全体を `ScaleTransition`(0.85 → 1、`Curves.elasticOut`)、
  中の項目を `Interval` をずらした `FadeTransition` + `SlideTransition`(下から 8px)。

**ポップアップ**(`showCultureDetailSheet(context, report)`)

- `showModalBottomSheet(isScrollControlled: true, showDragHandle: true, enableDrag: true)`、高さは画面の 85%。
  - 背景のタップ・下へのスワイプ・Esc(ModalRoute の DismissIntent)で閉じる。上部に ✕(`IconButton`, tooltip「閉じる」)。
- 構成: 上部(palette の accent → accent2 のグラデーション、白い文字でアーティスト名)/
  `TabBar`「ファッション」「MV の衣装」「経歴・音楽性」(初期はファッション。下線は accent)/ `TabBarView`(白地・各タブは個別にスクロール)/
  下端に固定の `GroundingFooter`(タブを切り替えても消えない。AC-10)。
- 各タブの中身は今の `_Report` の部品(`_Chips` / `_Paragraph` / `_Bullets` / `_Citations` / `_Outfit`)をそのまま使い、項目を減らさない(AC-9)。
  このため、今の部品は `culture_section.dart` から `culture_parts.dart` に移して両方から使う。
- Web の検索候補(`HtmlElementView`)はカードとポップアップで別の要素になるので、同時に出ても問題ない。

### 5.5 D. 演出

**背景の動き(`VibeBackdrop`)**

- `HomePage` の `Stack` の最背面(グラデーションの上・カードの下)に置く。`IgnorePointer` + `RepaintBoundary`。
- `AnimationController`(10 秒で 1 周を繰り返す)の値から、粒ごとの位置を計算して `CustomPainter` で描く(状態を毎フレーム持たない)。
  粒の初期値は演出ごとに固定の乱数の種で作る。

  | 演出 | 粒の数 | 描き方 |
  | --- | --- | --- |
  | sparkle | 28 | 星(4 つの尖り)とハートが下から上へ、左右に揺れながら上がり、上で消える |
  | sparks | 32 + 照明 2 | 小さな光の点が下から上へ速く上がる。画面上部に大きな放射グラデーション 2 つが明滅 |
  | petals | 22 | 楕円の花びらが回転しながらゆっくり落ちる |
  | neon | 24 | 光る短い線(MaskFilter.blur)が斜めに流れる |

- 粒の色は accent / accent2 と、その明るい色。
- `effect` が null・動きを減らす設定のときは何も描かず、`AnimationController` も止める。

**切り替わりの演出(`showVibeBurst`)**

- `MvLookupPanel` が、カルチャー情報の取得に成功して `CultureVibe.from(...)` が `isNone` でないときに 1 回だけ呼ぶ。
- 始点は選んだ候補のタイル(URL 入力のときは動画の情報)の中心。`GlobalKey` で位置を取る。
- `OverlayEntry` に全画面の円を描き、700ms で 0 → 画面の対角線まで広げながら、後半で透明にして消す。`IgnorePointer`。
- 動きを減らす設定・色が無いときは呼ばない。

**配色が変わる部品**: 背景のグラデーション、ヘッダーのアイコン、段階の Pill、ボタン(ColorScheme.primary)、番号の丸、
選択中の候補の地と枠、タブの下線、リンク、「考え中」の進み具合のグラデーション。**白いカードの地と本文の文字の色は変えない**(AC-14)。
暗い背景のときは、カードの外に出る文字(ヘッダーのアプリ名・説明)を `onBackground` にする。

**動きを減らす設定**: `reduceMotionOf(context)`(§8。Flutter の設定 + Web のブラウザの設定)で判定する。
有効なら、AnimatedTheme 0ms・VibeBurst なし・VibeBackdrop なし・要点のカードは最初から表示済み・
ポップアップは `sheetAnimationStyle: AnimationStyle.noAnimation`。

### 5.6 E. 操作性

- **✓**: `SectionCard(done: …)`。済んだら番号の丸を `AppColors.ok` の丸 + `Icons.check` にする(Semantics のラベル「済み」)。
  - ①: `_video != null`(パネル) / ②: `selectedIndex != null`(LiveSection) / ③: 手持ちの服が 1 点以上(WardrobeSection)。
- **取得中の理由**: カルチャー情報を調べている間(`_cultureLoading`)だけ、① と ② の検索の行の直下に、鍵のアイコン付きの `Hint`
  「カルチャー情報を調べ終わるまで、検索・選び直しはできません」を出す。`LiveSection` には `cultureLoading` を新しく渡す。
  入力を止める条件(`_busy`)は変えない。
- spec 037(入力のチェック)の理由は、今どおり検索の行の下の `ErrorText` に出る。取得中の理由はその上に置き、両方が出ても重ならない
  (実際には取得中は入力できないので、同時に出るのは直前のエラーが残っている場合だけ)。

## 6. バックエンド設計

変更なし(AC-20)。

## 7. Gemini プロンプト設計

変更なし。演出の判定に Gemini は使わない(§4.1 の辞書で判定する)。

## 8. エラーハンドリング / 非機能

- 判定に使う言葉は Gemini の応答なので、空・想定外の言葉・極端に長い一覧でも例外を出さず「演出なし」にする。
- 背景の動きは粒を最大 34 個程度にし、`RepaintBoundary` でカードの再描画と切り離す(Web のスマホで重くしない)。
- 文字の読みやすさ: 差し色は白い文字に対して 4.5:1 以上に調整する。本文は白いカードの上に置くので、配色が変わっても変わらない。
- **動きを減らす設定の判定(実装時に確認・更新)**: Flutter 3.41.9 の Web エンジンのソース(`lib/web_ui`)を確認したところ、
  OS の「視差効果を減らす」(`prefers-reduced-motion`)は `disableAnimations` に**反映されない**。
  そのため `core/reduce_motion.dart` の `reduceMotionOf(context)` で、`MediaQuery.disableAnimationsOf(context)` に加えて
  Web ではブラウザの `matchMedia('(prefers-reduced-motion: reduce)')` を直接読む(条件付き import。Web 以外は false)。
  §5.5 の「動きを減らす設定」の判定はすべてこの関数を使う。

## 9. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| frontend unit | `CultureVibe.from`(色・スタイルの部分一致、優先順、白を飛ばす、判定できない言葉、特定できない / 動画なしで null)、`AppPalette`(コントラスト 4.5:1 以上、暗い演出) | `flutter test`(`culture_vibe_test.dart`) |
| frontend widget | A: 初期は詳細が出ない・「詳細」で開閉・「YouTube で開く」(AC-1〜3) | `mv_lookup_screen_test.dart` を更新(`openUrl` を差し替え) |
| frontend widget | B: 選ぶと他の候補が消える・「変更」で戻る・取得中は無反応(AC-4〜6) | `mv_lookup_screen_test.dart` / `mv_lookup_culture_test.dart` |
| frontend widget | C: 要点のカードの項目、ポップアップのタブ・下端の出典、✕ / 背景 / スワイプで閉じる、失敗・特定できないは今どおり(AC-7〜12) | `mv_lookup_culture_test.dart` を更新(フェイク Repository) |
| frontend widget | D: ガーリー → sparkle + 差し色、ロック → 暗い背景 + sparks + カードの文字色は不変、判定不可 → 標準、「変更」で標準に戻る、動きを減らす設定で配色だけ、「考え中」に配色が引き継がれる(AC-13〜17, 21) | `home_page_test.dart`(`VibeBackdrop.effect` と `AppPalette.of` を検査) |
| frontend widget | E: ①②③ の ✓、取得中の理由の表示と消える(AC-18, 19) | `home_page_test.dart` / `mv_lookup_culture_test.dart` |
| 共通 | `backend/` に差分が無い(AC-20) | `git diff --stat main -- backend/` を PR で確認 |

- 背景の動きは止まらないアニメーションなので、`pumpAndSettle` が終わらない。`home_page_test.dart` の `_pump` は
  既定で `tester.platformDispatcher.accessibilityFeaturesTestValue` により動きを減らす設定を有効にし、
  動きを確かめるテストだけ無効にして `pump(Duration)` で進める。
- 既存のテストのうち、展開した直後に「動画タイトル」「ファッション・ビジュアル」などを探しているものは、
  「詳細」「くわしく見る」を開いてから探すように直す。
