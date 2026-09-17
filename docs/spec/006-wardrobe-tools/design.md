# 設計: 服インデックスをエージェントから参照する

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-09-17

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | ADK のツールとして提供し、呼ぶ判断はモデルに任せる | 採用 | 「必要に応じて」を自然に満たす。spec 003 のメディア生成ツールと同じ形 |
| B | 毎回インデックス全文を system instruction に載せる | 却下 | 無関係な質問でもトークンを消費し、件数が増えると破綻する |
| C | CLI 側でキーワードを判定して注入 | 却下 | 判定が脆く、言い回しの揺れに対応できない |

## 2. 全体フロー

```
「手持ちの服で今日のコーデを考えて」
  → LlmAgent が search_wardrobe / list_wardrobe を呼ぶ(Function Calling)
      → index.json を読み、属性で絞り込む
      → {"status":"ok","count":n,"items":[...]} を返す
  → モデルが結果を踏まえて回答
```

## 3. ツールの契約

| ツール | 引数 | 戻り値 |
| --- | --- | --- |
| `list_wardrobe` | なし | `{"status":"ok","count":n,"items":[...]}` |
| `search_wardrobe` | `keyword: str` | 同上(キーワードに一致した服のみ) |

- `items` の各要素は `image` / `category` / `material` / `shape` / `colors` / `pattern` / `style` / `notes`。
- インデックスが無い / 空の場合は `{"status":"error","message":...}`(例外は投げない)。
- 検索は全属性を連結した文字列への**大文字小文字を無視した部分一致**。空文字なら全件。

## 4. バックエンド設計

### `app/services/wardrobe.py`(新規)

| 要素 | 役割 |
| --- | --- |
| `load_wardrobe(path)` | `index.json` を読み、`(画像名, ClothItem)` の一覧にする |
| `item_text(image, item)` | 検索対象の文字列(全属性の連結) |
| `search_items(entries, keyword)` | キーワードで絞り込む |
| `build_wardrobe_tools(settings)` | 設定に束縛したツール関数の一覧を返す |

**ツールは設定を閉じ込めたクロージャとして作る。** グローバル設定を直接読むと、
CLI の `--index` による差し替えがツールに反映されないため。

### `app/services/agent.py`(変更)

`build_agent()` のツール一覧に `build_wardrobe_tools(settings)` を加える。
`TOOL_GUIDELINE` に「手持ちの服に関する話題ではインデックスを参照する」旨を追記する。

### CLI(変更)

`run_agent.py` / `run_agent_loop.py` に `--index <パス>` を追加する。
指定時は設定を差し替えて `AgentService` に渡す(既存の `--model` と同じ仕組み)。

### 設定

| 設定 | 既定値 | 用途 |
| --- | --- | --- |
| `cloth_index_path` | `tests/sample_cloth_indexs/index.json` | 参照するインデックス(backend/ からの相対) |

## 5. エラーハンドリング / 非機能

- ファイルが無い / 壊れている場合は `status: error` を返す(ツールで例外を投げるとエージェントが止まるため)。
- インデックスは呼ばれるたびに読み込む(件数が少なく、更新が即反映される利点を取る)。

## 6. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| unit | `load_wardrobe` | 一時ディレクトリの JSON を読む |
| unit | `search_items` | 部分一致・大文字小文字・空キーワード |
| unit | ツールの戻り値 | インデックス有無それぞれで status を確認 |
| unit | `build_agent` | ツールが登録されていることを確認 |
| 手動 | 実行 | CLI で「手持ちの服」を尋ねて参照されることを確認 |
