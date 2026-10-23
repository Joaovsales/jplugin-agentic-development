"""Clocks. Anything with now() and sleep(seconds) can stand in for time."""
import time


class SystemClock:
    """Real time: a monotonic reading and a real sleep."""

    def now(self) -> float:
        return time.monotonic()

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)


class ManualClock:
    """A clock that moves only when told to; sleep() advances it without waiting."""

    def __init__(self, start: float = 0.0) -> None:
        self._now = start

    def now(self) -> float:
        return self._now

    def advance(self, seconds: float) -> None:
        self._now += seconds

    def sleep(self, seconds: float) -> None:
        self.advance(seconds)
