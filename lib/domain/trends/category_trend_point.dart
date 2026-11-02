class const CategoryTrendPoint({
  required final DateTime date,

  /// Trailing-year spend ending on [date], scaled up if fewer than 365
  /// observed days exist yet (partial first year).
  required final double rollingCents,

  /// Heavily smoothed version of [rollingCents] for the trendline.
  required final double smoothedCents,
});
