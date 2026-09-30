"""Google 検索のグラウンディング(Grounding with Google Search)の共通処理(spec 008 / 009)。

検索ありで Gemini に自由文で調べさせ、応答から本文・出典・検索候補を取り出す。
JSON への整理は、呼び出し側が検索なしの別の呼び出しで行う
(検索と JSON 出力を同時に使うと出典(grounding_chunks)が空になる事例があるため)。

グラウンディングの結果は保存しない(利用規約上の問題になるおそれがあるため)。
検索候補(Search Suggestions)は利用条件により画面への表示が必須。
"""

from collections.abc import Sequence
from dataclasses import dataclass, field

from google import genai
from google.genai import errors, types

from app.schemas.culture import Source

# 「情報なし」「不明」とだけ書かれた項目は空として扱う
NO_INFO = {"", "情報なし", "不明", "なし"}

# SDK の自動関数呼び出し(AFC)は使わない。関数ツールを渡さない呼び出しでも、
# 無効にしておかないと使わない機能についての警告が出るため、すべての呼び出しで指定する
NO_AFC = types.AutomaticFunctionCallingConfig(disable=True)


@dataclass
class WebResearch:
    """検索ありで調べた結果。"""

    # 出典番号 [n] を差し込んだ本文
    text: str
    sources: list[Source] = field(default_factory=list)
    search_suggestions_html: str = ""
    web_search_queries: list[str] = field(default_factory=list)


async def grounded_research(client: genai.Client, model: str, prompt: str) -> WebResearch:
    """Google 検索ありで Gemini に調べさせ、本文・出典・検索候補を返す。

    例外は変換せずにそのまま投げる(業務例外への変換は呼び出し側が行う)。
    """
    response = await client.aio.models.generate_content(
        model=model,
        contents=prompt,
        config=types.GenerateContentConfig(
            tools=[types.Tool(google_search=types.GoogleSearch())],
            automatic_function_calling=NO_AFC,
        ),
    )
    return extract_research(response)


def insert_citations(
    text: str,
    supports: Sequence[types.GroundingSupport],
    chunk_to_index: dict[int, int],
) -> str:
    """本文の根拠のある箇所の直後に、出典番号 `[n]` を差し込む。

    `segment.start_index` / `end_index` は位置の数え方(文字 / バイト)に依存するため使わず、
    `segment.text` を本文から探す(日本語の本文でもずれないようにするため)。
    """
    insertions: list[tuple[int, str]] = []
    for support in supports:
        segment = support.segment.text if support.segment else None
        if not segment:
            continue
        position = text.find(segment)
        numbers = sorted(
            {
                chunk_to_index[i]
                for i in support.grounding_chunk_indices or []
                if i in chunk_to_index
            }
        )
        if position < 0 or not numbers:
            continue
        insertions.append((position + len(segment), "".join(f"[{n}]" for n in numbers)))

    # 後ろから差し込めば、前の差し込み位置がずれない
    for end, marker in sorted(insertions, reverse=True):
        text = text[:end] + marker + text[end:]
    return text


def extract_research(response: types.GenerateContentResponse) -> WebResearch:
    """検索ありの応答から、本文・出典・検索候補・検索クエリを取り出す。"""
    text = response.text or ""
    candidates = response.candidates or []
    metadata = candidates[0].grounding_metadata if candidates else None
    if metadata is None:
        return WebResearch(text=text)

    sources: list[Source] = []
    chunk_to_index: dict[int, int] = {}
    for i, chunk in enumerate(metadata.grounding_chunks or []):
        web = chunk.web
        if web is None or not web.uri:
            continue
        number = len(sources) + 1
        chunk_to_index[i] = number
        sources.append(
            Source(
                index=number,
                title=web.title or web.domain or web.uri,
                url=web.uri,
                domain=web.domain or "",
            )
        )

    entry_point = metadata.search_entry_point
    return WebResearch(
        text=insert_citations(text, metadata.grounding_supports or [], chunk_to_index),
        sources=sources,
        search_suggestions_html=(entry_point.rendered_content or "") if entry_point else "",
        web_search_queries=list(metadata.web_search_queries or []),
    )


def valid_indices(indices: Sequence[int], source_count: int) -> list[int]:
    """出典番号のうち、実在する出典(1〜source_count)を指すものだけを重複なく返す。"""
    return sorted({i for i in indices if 1 <= i <= source_count})


def clean_list(values: Sequence[str]) -> list[str]:
    """前後の空白を除き、「情報なし」などの項目を取り除く。"""
    return [v.strip() for v in values if v.strip() not in NO_INFO]


def clean_text(value: str) -> str:
    """前後の空白を除き、「情報なし」などなら空にする。"""
    return "" if value.strip() in NO_INFO else value.strip()


def is_quota_error(exc: BaseException) -> bool:
    """Gemini のクォータ超過(HTTP 429 / RESOURCE_EXHAUSTED)か。"""
    return isinstance(exc, errors.APIError) and (
        exc.code == 429 or exc.status == "RESOURCE_EXHAUSTED"
    )
