# Authorized lesson reference
For ordered real numbers and low <= high, clamp(x, low, high) returns low when x < low, high when x > high, and x otherwise. Equal bounds return that bound. For this lesson, low > high is an invalid interval and raises ValueError. The goal is to understand clamp(9, 2, 8) = 8, not NaN or incomparable types.
