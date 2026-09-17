"""エージェントループ: 生成 → 検証 → 未達なら再生成、を繰り返す。

停止条件をアプリ側で制御することで、検証を必ず通し、反復回数を確実に打ち切る。
画面表示は行わず、経過は `on_step` コールバックで呼び出し側に渡す(CLI が表示する)。
"""

import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from pathlib import Path

from app.core.config import Settings, get_settings
from app.schemas.chat import Attachment, ChatMessage
from app.services.agent import AgentError, AgentService
from app.services.verification import Verdict, verify_result

logger = logging.getLogger(__name__)

# 検証関数を差し替えられるようにする(テスト用)
VerifyFn = Callable[[str, str, Path | None], Awaitable[Verdict]]


@dataclass
class LoopStep:
    """1 周回ぶんの記録。"""

    iteration: int
    prompt: str
    reply: str
    artifact: Path | None = None
    verdict: Verdict | None = None
    error: str | None = None


@dataclass
class LoopResult:
    """ループ全体の結果。"""

    requirement: str
    steps: list[LoopStep] = field(default_factory=list)
    satisfied: bool = False

    @property
    def final_artifact(self) -> Path | None:
        """最後に生成された生成物(無ければ None)。"""
        for step in reversed(self.steps):
            if step.artifact:
                return step.artifact
        return None


def snapshot_media_files(settings: Settings | None = None) -> set[Path]:
    """生成物ディレクトリにある既存ファイルの一覧を取る。"""
    settings = settings or get_settings()
    files: set[Path] = set()
    for directory in (settings.created_images_path, settings.created_videos_path):
        if directory.is_dir():
            files.update(p for p in directory.iterdir() if p.is_file())
    return files


def detect_new_artifact(before: set[Path], after: set[Path]) -> Path | None:
    """スナップショットの差分から今回の生成物を特定する。複数あれば最新の 1 件。"""
    created = after - before
    if not created:
        return None
    return max(created, key=lambda p: p.stat().st_mtime)


def build_retry_prompt(requirement: str, verdict: Verdict) -> str:
    """検証の指摘を踏まえた再生成の指示文を作る。"""
    improvements = verdict.improvements.strip() or "指摘された点を踏まえて改善してください。"
    return (
        "前回の結果は要望を満たしていません。以下を踏まえてもう一度作成してください。\n\n"
        f"# 元の要望\n{requirement}\n\n"
        f"# 満たしていない理由\n{verdict.reason}\n\n"
        f"# 改善すべき点\n{improvements}"
    )


async def run_agent_loop(
    requirement: str,
    *,
    max_iterations: int | None = None,
    attachments: list[Attachment] | None = None,
    service: AgentService | None = None,
    verify: VerifyFn | None = None,
    settings: Settings | None = None,
    on_step: Callable[[LoopStep], None] | None = None,
) -> LoopResult:
    """要望を満たすまで生成と検証を繰り返す。

    Args:
        requirement: 利用者の要望(これが毎回の検証基準になる)。
        max_iterations: 繰り返しの上限。省略時は設定値。
        attachments: 初回の生成にだけ渡す添付(参考画像など)。
        service: 生成に使うサービス。省略時は既定の AgentService。
        verify: 検証関数。省略時は `verify_result`。
        on_step: 1 周回終わるごとに呼ばれるコールバック(表示用)。

    Returns:
        各周回の記録と、最終的に要望を満たしたかどうか。
    """
    settings = settings or get_settings()
    service = service or AgentService()
    limit = max_iterations if max_iterations is not None else settings.loop_max_iterations

    async def default_verify(req: str, reply: str, artifact: Path | None) -> Verdict:
        return await verify_result(req, reply, artifact, settings=settings)

    verify_fn = verify or default_verify

    result = LoopResult(requirement=requirement)
    history: list[ChatMessage] = []
    prompt = requirement

    for iteration in range(1, limit + 1):
        step = LoopStep(iteration=iteration, prompt=prompt, reply="")
        before = snapshot_media_files(settings)

        try:
            # 添付は初回の生成にだけ渡す(2 周目以降は履歴で文脈が伝わる)
            step.reply = await service.generate_reply(
                prompt, history, attachments if iteration == 1 else None
            )
        except AgentError as exc:
            # 同じ失敗が続く可能性が高いため、生成の失敗ではループを打ち切る
            step.error = str(exc)
            result.steps.append(step)
            if on_step:
                on_step(step)
            break

        step.artifact = detect_new_artifact(before, snapshot_media_files(settings))
        step.verdict = await verify_fn(requirement, step.reply, step.artifact)

        history.append(ChatMessage(role="user", content=prompt))
        history.append(ChatMessage(role="model", content=step.reply))

        result.steps.append(step)
        if on_step:
            on_step(step)

        if step.verdict.satisfied:
            result.satisfied = True
            break

        prompt = build_retry_prompt(requirement, step.verdict)

    logger.info("ループ終了: %d 周 / satisfied=%s", len(result.steps), result.satisfied)
    return result
