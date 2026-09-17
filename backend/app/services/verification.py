"""生成結果が要望を満たしているかを判定する検証サービス。

エージェントループ(spec 004)から使う。画像・動画は**中身をモデルに見せて**判定する。
判定結果は構造化 JSON で受け取り、未達なら改善点を次の生成に渡す。
"""

import logging
from pathlib import Path

from google import genai
from google.genai import types
from pydantic import BaseModel, Field

from app.core.config import Settings, get_settings
from app.services.media import get_media_client

logger = logging.getLogger(__name__)

# 拡張子 → MIME(生成物を Part にするときに使う)
_MIME_BY_SUFFIX = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".mp4": "video/mp4",
    ".webm": "video/webm",
    ".mov": "video/quicktime",
}

_INSTRUCTION = """\
あなたは生成結果を厳しく評価する検証者です。
利用者の要望と、エージェントの応答(および生成物)を突き合わせ、要望を満たしているか判定してください。

判定の基準:
- 要望に書かれた要素がすべて含まれているか。
- 生成物がある場合は、その内容が要望と一致しているか(ファイルが存在するかどうかではない)。
- 満たしていない場合、improvements には「次の生成で何をどう変えるべきか」を具体的に書くこと。

満たしている場合は satisfied を true にし、improvements は空文字にしてください。
"""


class Verdict(BaseModel):
    """検証結果。モデルの構造化出力スキーマとしてそのまま使う。"""

    satisfied: bool = Field(description="要望を満たしているか")
    reason: str = Field(description="そう判断した理由")
    improvements: str = Field(default="", description="未達の場合に次の生成で直すべき点")


def guess_mime_type(path: Path) -> str | None:
    """生成物のパスから MIME タイプを推定する。分からなければ None。"""
    return _MIME_BY_SUFFIX.get(path.suffix.lower())


def build_verification_parts(
    requirement: str, reply: str, artifact: Path | None
) -> list[types.Part]:
    """検証モデルに渡す Part 列を組み立てる。生成物があれば中身も渡す。"""
    parts: list[types.Part] = []

    mime_type = guess_mime_type(artifact) if artifact else None
    if artifact and mime_type and artifact.is_file():
        parts.append(types.Part.from_bytes(data=artifact.read_bytes(), mime_type=mime_type))

    artifact_note = (
        f"生成物: {artifact.name}(上の添付)" if artifact else "生成物: なし(テキスト応答のみ)"
    )
    summary = f"# 利用者の要望\n{requirement}\n\n# エージェントの応答\n{reply}\n\n# {artifact_note}"
    parts.append(types.Part.from_text(text=summary))
    return parts


async def verify_result(
    requirement: str,
    reply: str,
    artifact: Path | None = None,
    settings: Settings | None = None,
    client: genai.Client | None = None,
) -> Verdict:
    """要望を満たしているか判定する。

    検証自体が失敗した場合は `satisfied=False` として理由に例外内容を入れる
    (検証できないものを「満たした」と扱わないため)。
    """
    settings = settings or get_settings()
    client = client or get_media_client()

    try:
        response = await client.aio.models.generate_content(
            model=settings.verifier_model,
            contents=[
                types.Content(
                    role="user", parts=build_verification_parts(requirement, reply, artifact)
                )
            ],
            config=types.GenerateContentConfig(
                system_instruction=_INSTRUCTION,
                response_mime_type="application/json",
                response_schema=Verdict,
            ),
        )
    except Exception as exc:
        logger.exception("検証に失敗しました")
        return Verdict(satisfied=False, reason=f"検証に失敗しました: {exc}", improvements="")

    verdict = response.parsed
    if not isinstance(verdict, Verdict):
        return Verdict(
            satisfied=False,
            reason="検証モデルの応答を解釈できませんでした。",
            improvements="",
        )
    return verdict
