"""Cloud Storage のバケットの偽物(spec 036)。実際の Cloud Storage は呼ばない。

`GcsWardrobeStore` が使うメソッド(`get_blob` / `blob` と、Blob の `download_as_bytes` /
`upload_from_string` / `delete`)だけを、メモリ上の dict と世代番号で再現する。
"""

from collections.abc import Callable
from dataclasses import dataclass, field

from google.api_core.exceptions import NotFound, PreconditionFailed


@dataclass
class StoredObject:
    data: bytes
    content_type: str | None
    generation: int


@dataclass
class FakeBucket:
    """メモリ上のバケット。`objects` で中身を直接確かめられる。"""

    objects: dict[str, StoredObject] = field(default_factory=dict)
    # 呼ばれたら投げる例外(接続できない・権限が無いなどの再現)
    fail_with: Exception | None = None
    # index.json を書き込む直前に 1 回だけ呼ぶ処理(同時書き込みの再現)
    before_upload: Callable[[str], None] | None = None
    _next_generation: int = 1

    def get_blob(self, name: str) -> "FakeBlob | None":
        self._check()
        if name not in self.objects:
            return None
        blob = FakeBlob(self, name)
        blob.generation = self.objects[name].generation
        return blob

    def blob(self, name: str) -> "FakeBlob":
        return FakeBlob(self, name)

    def text(self, name: str) -> str:
        return self.objects[name].data.decode("utf-8")

    def _check(self) -> None:
        if self.fail_with is not None:
            raise self.fail_with

    def _put(self, name: str, data: bytes, content_type: str | None) -> None:
        self.objects[name] = StoredObject(data, content_type, self._next_generation)
        self._next_generation += 1


@dataclass
class FakeBlob:
    bucket: FakeBucket
    name: str
    generation: int | None = None

    def download_as_bytes(self, if_generation_match: int | None = None) -> bytes:
        self.bucket._check()
        stored = self.bucket.objects.get(self.name)
        if stored is None:
            raise NotFound(self.name)
        if if_generation_match is not None and stored.generation != if_generation_match:
            raise PreconditionFailed(self.name)
        return stored.data

    def upload_from_string(
        self,
        data: str | bytes,
        content_type: str | None = None,
        if_generation_match: int | None = None,
    ) -> None:
        self.bucket._check()
        hook = self.bucket.before_upload
        if hook is not None and if_generation_match is not None:
            self.bucket.before_upload = None
            hook(self.name)
        if if_generation_match is not None:
            current = self.bucket.objects.get(self.name)
            current_generation = current.generation if current else 0
            if current_generation != if_generation_match:
                raise PreconditionFailed(self.name)
        payload = data.encode("utf-8") if isinstance(data, str) else data
        self.bucket._put(self.name, payload, content_type)

    def delete(self) -> None:
        self.bucket._check()
        if self.name not in self.bucket.objects:
            raise NotFound(self.name)
        del self.bucket.objects[self.name]
