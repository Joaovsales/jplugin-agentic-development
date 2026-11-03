"""Exponential backoff delays."""
from typing import Iterator


def delays(base: float, factor: float, cap: float) -> Iterator[float]:
    """Yield base, base*factor, base*factor**2, ... each limited to cap, forever."""
    delay = base
    while True:
        yield min(delay, cap)
        delay *= factor
