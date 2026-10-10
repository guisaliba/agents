import unittest

from clamp import clamp


class ClampTests(unittest.TestCase):
    def test_values_below_low_return_low(self):
        self.assertEqual(clamp(-3, 0, 10), 0)

    def test_values_above_high_return_high(self):
        self.assertEqual(clamp(13, 0, 10), 10)

    def test_values_inside_interval_are_unchanged(self):
        self.assertEqual(clamp(4, 0, 10), 4)

    def test_values_on_bounds_are_unchanged(self):
        self.assertEqual(clamp(0, 0, 10), 0)
        self.assertEqual(clamp(10, 0, 10), 10)

    def test_low_greater_than_high_raises_value_error(self):
        with self.assertRaises(ValueError):
            clamp(5, 10, 0)

    def test_equal_bounds_clamp_values_below_at_and_above(self):
        self.assertEqual(clamp(3, 4, 4), 4)
        self.assertEqual(clamp(4, 4, 4), 4)
        self.assertEqual(clamp(5, 4, 4), 4)

    def test_finite_fractional_values_are_clamped(self):
        self.assertEqual(clamp(-0.25, 0.5, 2.75), 0.5)
        self.assertEqual(clamp(1.25, 0.5, 2.75), 1.25)
        self.assertEqual(clamp(3.5, 0.5, 2.75), 2.75)

    def test_reversed_bounds_raise_below_between_and_above_pair(self):
        for position, value in (("below", 1), ("between", 3), ("above", 5)):
            with self.subTest(position=position):
                with self.assertRaises(ValueError):
                    clamp(value, 4, 2)


if __name__ == "__main__":
    unittest.main()
