import unittest

from retrykit.clock import ManualClock


class ManualClockTest(unittest.TestCase):
    def test_starts_where_told_and_only_moves_on_advance(self):
        clock = ManualClock(start=5.0)
        self.assertEqual(clock.now(), 5.0)
        clock.advance(2.5)
        self.assertEqual(clock.now(), 7.5)

    def test_sleep_advances_without_waiting(self):
        clock = ManualClock()
        clock.sleep(3.0)
        self.assertEqual(clock.now(), 3.0)


if __name__ == "__main__":
    unittest.main()
