/// What an account's money cost for tax, as of a day: a brokerage's cost
/// basis, or a Roth's contributions and conversions (what comes back out
/// tax-free before 59½).
class const TaxBasis({required final int cents, required final DateTime asOf});
