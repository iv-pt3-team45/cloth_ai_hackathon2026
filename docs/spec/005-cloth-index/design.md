# 設計: 服画像のインデックス作成

- 対応する要件: `./requirements.md`
- ステータス: approved
- 更新日: 2026-09-17

## 1. 設計方針

| 案 | 概要 | 採否 | 理由 |
| --- | --- | --- | --- |
| A | 構造化出力(`response_schema`)で属性を直接受け取る | 採用 | パースが不要で型が保証される。spec 004 の検証と同じ方式で一貫する |
| B | 自由文で書かせて後からパースする | 却下 | 表記揺れの吸収が必要で壊れやすい |
| C | エージェント(ツール)経由で処理する | 却下 | 1 枚ずつ決まった処理を回すだけで、モデルの判断は不要 |

## 2. 全体フロー

```
tests/sample_images/*.{jpg,jpeg,png,webp}
        │  1 枚ずつ
        ▼
  analyze_cloth_image()
        ├─ 画像を Part.from_bytes() で渡す
        └─ response_schema=ClothAnalysis で構造化出力
        ▼
  tests/sample_cloth_indexs/index.json   … 全画像ぶんをまとめた 1 ファイル
```

## 3. データモデル

```python
class ClothItem(BaseModel):
    category: str        # 種類(Tシャツ / パンツ など)
    material: str        # 素材(綿 / ポリエステル / 不明)
    shape: str           # 形・シルエット(半袖クルーネック など)
    colors: list[str]    # 色(主要な順)
    pattern: str         # 柄(無地 / プリント など)
    style: str           # 系統(カジュアル / ストリート など)
    notes: str           # 特徴(プリント内容、装飾など)

class ClothAnalysis(BaseModel):   # モデルの構造化出力
    items: list[ClothItem]
    summary: str

class ClothIndexEntry(BaseModel): # 保存する 1 件
    image: str                    # ファイル名
    items: list[ClothItem]
    summary: str
    model: str
    analyzed_at: str              # ISO8601
```

`index.json` は `{"generated_at", "model", "source_dir", "entries": [ClothIndexEntry, ...]}`。

## 4. バックエンド設計

### `app/services/cloth_index.py`(新規)

| 要素 | 役割 |
| --- | --- |
| `SUPPORTED_SUFFIXES` | 対象とする画像拡張子 |
| `list_images(dir)` | 対象画像の一覧(名前順、非画像は除外) |
| `analyze_cloth_image(path)` | 1 枚を解析して `ClothIndexEntry` を返す |
| `index_path(output_dir)` | インデックスファイル(`index.json`)の場所 |
| `load_index(output_dir)` | 既存インデックスを画像名 → エントリの辞書として読む |
| `save_index(entries, output_dir, source_dir)` | `index.json` を書き出す |
| `build_cloth_index(...)` | ディレクトリ全体を処理する。`on_progress` で経過通知 |

- 表示は行わない(CLI が `on_progress` で出力する)。
- 既存 `index.json` に同じ画像名があればスキップし、その内容を引き継ぐ(`force=True` で再作成)。
- 解析 1 枚ごとに `index.json` を書き出す(途中で中断しても解析済みを失わないため)。
- 解析に失敗した画像はスキップして続行する(1 枚の失敗で全体を止めない)。

### `scripts/build_cloth_index.py`(新規)

```
uv run python scripts/build_cloth_index.py [-i 画像ディレクトリ] [-o 出力先] [--force] [-v]
```

既定は `tests/sample_images` → `tests/sample_cloth_indexs`。

### 設定

| 設定 | 既定値 | 用途 |
| --- | --- | --- |
| `cloth_index_model` | `gemini-2.5-flash` | 解析に使うモデル |

## 5. エラーハンドリング / 非機能

- 画像 1 枚ごとに逐次処理する(クォータの瞬間的な消費を避けるため)。
- モデルが解釈不能な応答を返した場合は `ClothIndexError`。CLI は失敗件数を表示する。
- JSON は UTF-8・`ensure_ascii=False`・インデント 2 で保存する(人が読むため)。

## 6. テスト方針

| 層 | 対象 | 手段 |
| --- | --- | --- |
| unit | `list_images` | 一時ディレクトリに画像 / 非画像を置いて確認 |
| unit | `save_index` / `load_index` | 一時ディレクトリに書き出し、1 ファイルのみになることを検証 |
| unit | `build_cloth_index` のスキップと force | 解析関数をフェイクに差し替え、呼び出し回数を確認 |
| 手動 | 実行 | サンプル画像 5 枚で実際にインデックスを作成 |
