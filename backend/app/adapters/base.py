from abc import ABC, abstractmethod
from typing import List

from app.schemas import MediaItem


class MediaAdapter(ABC):
    """
    Every source (TMDB, or a future games source) implements this
    interface and returns the same MediaItem shape.
    """

    source_name: str

    @abstractmethod
    async def search(self, query: str) -> List[MediaItem]:
        ...
