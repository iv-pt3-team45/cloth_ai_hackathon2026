"""Agent Development Kit (ADK) を用いた Gemini 呼び出し。

ADK の `LlmAgent` を `Runner` で実行し、最終応答テキストを取り出す。
セッションはリクエストごとに使い捨てにし、会話履歴はクライアントから受け取った
`history` をイベントとして流し込むことで再現する(ステートレス)。
"""

import base64
import logging
from dataclasses import dataclass
from functools import lru_cache

from google.adk.agents import LlmAgent
from google.adk.events import Event
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types

from app.core.config import Settings, get_settings
from app.schemas.chat import Attachment, ChatMessage
from app.services.media import generate_image, generate_video
from app.services.wardrobe import build_wardrobe_tools

logger = logging.getLogger(__name__)

# ツールの使い方に関する固定の指示。利用者が instruction を差し替えても失われないよう、
# 設定値の instruction に必ず追記する。
TOOL_GUIDELINE = (
    "画像や動画の生成を依頼されたら generate_image / generate_video ツールを使うこと。"
    "生成に成功したら、応答に必ず保存されたファイル名(file_name)と保存先パス(path)を含めて伝えること。"
    "失敗した場合(status が error)は、その理由を利用者に分かる言葉で説明すること。"
    "利用者の手持ちの服・コーディネートが話題になったら、"
    "list_wardrobe / search_wardrobe で実際に持っている服を確認してから答えること。"
)

# ADK のセッションはユーザー単位で分かれる。現状は認証が無いため固定値を使う。
_DEFAULT_USER_ID = "local-user"


class AgentError(RuntimeError):
    """エージェント実行に失敗したときの例外。ルータが 502 に変換する。"""


def build_agent(settings: Settings) -> LlmAgent:
    """設定から LlmAgent を組み立てる。

    system instruction は `instruction` として渡す
    (ADK が内部で組み立てるため `GenerateContentConfig` 側には入れない)。
    """
    return LlmAgent(
        name=settings.agent_name,
        model=settings.gemini_model,
        description=settings.agent_description,
        instruction=f"{settings.gemini_system_instruction}\n\n{TOOL_GUIDELINE}",
        # モデルが必要と判断したときに自分で呼ぶ(生成 / 手持ちの服の参照)
        tools=[generate_image, generate_video, *build_wardrobe_tools(settings)],
        generate_content_config=types.GenerateContentConfig(
            temperature=settings.gemini_temperature,
            max_output_tokens=settings.gemini_max_output_tokens,
        ),
    )


@dataclass(frozen=True)
class RunnerBundle:
    """Runner と、セッション操作に必要な周辺オブジェクトをまとめて持つ。"""

    runner: Runner
    session_service: InMemorySessionService
    app_name: str
    agent_name: str


def build_runner(settings: Settings) -> RunnerBundle:
    """設定から Runner 一式を組み立てる。

    設定を差し替えて動かしたい場合(CLI の --model など)に使う。
    既定の設定で使うときは `get_runner()` を呼ぶ(そちらはキャッシュされる)。
    """
    # ADK は接続先を環境変数からしか読まないため、ここで反映する
    settings.export_google_env()

    if settings.google_genai_use_vertexai and not settings.google_cloud_project:
        raise AgentError("GOOGLE_CLOUD_PROJECT が未設定です。backend/.env を確認してください。")
    if not settings.google_genai_use_vertexai and not settings.google_api_key:
        raise AgentError("GOOGLE_API_KEY が未設定です。backend/.env を確認してください。")

    session_service = InMemorySessionService()
    agent = build_agent(settings)
    return RunnerBundle(
        runner=Runner(
            app_name=settings.adk_app_name,
            agent=agent,
            session_service=session_service,
        ),
        session_service=session_service,
        app_name=settings.adk_app_name,
        agent_name=agent.name,
    )


@lru_cache
def get_runner() -> RunnerBundle:
    """既定の設定の Runner をプロセス内で共有する(毎回の生成コストを避けるため)。"""
    return build_runner(get_settings())


def to_event(message: ChatMessage, agent_name: str) -> Event:
    """会話履歴 1 件を ADK のイベントに変換する。

    ADK の author はユーザーなら "user"、応答側はエージェント名になる。
    """
    author = "user" if message.role == "user" else agent_name
    return Event(
        author=author,
        content=types.Content(
            role=message.role,
            parts=[types.Part.from_text(text=message.content)],
        ),
    )


def to_parts(message: str, attachments: list[Attachment] | None = None) -> list[types.Part]:
    """テキストと添付を Gemini に渡す Part のリストに変換する。

    添付を先に並べ、最後に指示文(テキスト)を置く。
    """
    parts: list[types.Part] = []
    for attachment in attachments or []:
        if attachment.uri:
            parts.append(
                types.Part.from_uri(file_uri=attachment.uri, mime_type=attachment.mime_type)
            )
        elif attachment.data:
            parts.append(
                types.Part.from_bytes(
                    data=base64.b64decode(attachment.data),
                    mime_type=attachment.mime_type,
                )
            )
    parts.append(types.Part.from_text(text=message))
    return parts


def extract_reply(event: Event) -> str | None:
    """最終応答イベントからテキストを取り出す。該当しなければ None。"""
    if not event.is_final_response() or event.content is None:
        return None
    parts = event.content.parts or []
    text = "".join(part.text for part in parts if part.text)
    return text or None


class AgentService:
    """チャットのユースケースを担うサービス層。"""

    def __init__(self, settings: Settings | None = None) -> None:
        # None なら既定設定(共有 Runner)を使う。設定を渡した場合は都度組み立てる。
        self._settings = settings

    @property
    def settings(self) -> Settings:
        return self._settings or get_settings()

    def _bundle(self) -> RunnerBundle:
        if self._settings is None:
            return get_runner()
        return build_runner(self._settings)

    async def generate_reply(
        self,
        message: str,
        history: list[ChatMessage],
        attachments: list[Attachment] | None = None,
    ) -> str:
        bundle = self._bundle()

        try:
            session = await bundle.session_service.create_session(
                app_name=bundle.app_name,
                user_id=_DEFAULT_USER_ID,
            )

            # 過去のやり取りをイベントとして積み、文脈を再現する
            for past in history:
                await bundle.session_service.append_event(
                    session, to_event(past, bundle.agent_name)
                )

            new_message = types.Content(role="user", parts=to_parts(message, attachments))

            reply: str | None = None
            async for event in bundle.runner.run_async(
                user_id=_DEFAULT_USER_ID,
                session_id=session.id,
                new_message=new_message,
            ):
                if event.error_message:
                    raise AgentError(event.error_message)
                text = extract_reply(event)
                if text:
                    reply = text
        except AgentError:
            raise
        except Exception as exc:  # ADK / SDK の例外はまとめて業務例外に変換する
            logger.exception("エージェントの実行に失敗しました")
            raise AgentError(str(exc)) from exc

        if not reply:
            raise AgentError("エージェントから空の応答が返りました")
        return reply


def get_agent_service() -> AgentService:
    """FastAPI の Depends 用ファクトリ。テスト時は override して差し替える。"""
    return AgentService()
