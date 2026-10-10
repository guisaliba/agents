def clamp(value, low, high):
    """Return value bounded by low and high, inclusive."""
    if low > high:
        raise ValueError("low must be less than or equal to high")
    if value < low:
        return low
    if value > high:
        return high
    return value
