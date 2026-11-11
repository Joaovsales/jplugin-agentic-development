import itertools
import unittest

from retrykit.backoff import delays


class DelaysTest(unittest.TestCase):
    def test_grows_by_factor(self):
        self.assertEqual(list(itertools.islice(delays(0.1, 2.0, 10.0), 3)), [0.1, 0.2, 0.4])

    def test_is_limited_by_cap(self):
        self.assertEqual(list(itertools.islice(delays(1.0, 10.0, 5.0), 3)), [1.0, 5.0, 5.0])


if __name__ == "__main__":
    unittest.main()
