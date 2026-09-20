#!/usr/bin/env python3
"""Test the 'the organisers' reference is quantised to 6 decimals' hypothesis
against the two observed leaderboard scores. It fails, by a factor of ~2.

Observed:
    submissions/zindi-submission.csv          (6 dp)  -> RMSE 0.000003406
    submissions/zindi-submission-fullprec.csv (15 dp) -> RMSE 0.00000355

ORACLE.md concludes from "more precision scored worse" that the reference must
itself be quantised to 1e-6. That direction is right but the MAGNITUDE is not
attainable. Let f_i be our full-precision score, r_i = round6(f_i),
rho_i = r_i - f_i, t_i the organisers' value and e_i = f_i - t_i. Then

    SSE_round = SSE_full + 2*sum(e_i*rho_i) + sum(rho_i^2)

Everything except sum(e*rho) is measured, so sum(e*rho) is pinned exactly. If
the reference sits on the 1e-6 grid then for any tract with |e_i| < 5e-7 we get
rho_i = -e_i (rounding lands on the true value) and the tract contributes
-e_i^2, bounded below by -(5e-7)^2; for every other tract the contribution is
-u_i*e_i with u_i the sub-grid residual, which is uncorrelated with e_i and
sums to ~0. So the model's whole budget is 9379*(5e-7)^2 -- and even that
requires every tract to be in the first group, which would force SSE_round = 0.
"""
import csv

import numpy as np

N = 9379
RMSE_ROUND = 3.406e-6   # submission 9iCK3XSC, 6 decimals
RMSE_FULL = 3.550e-6    # submission Ys4Ezyhv, 15 decimals


def main():
    a = list(csv.DictReader(open("submissions/zindi-submission.csv", newline="")))
    b = list(csv.DictReader(open("submissions/zindi-submission-fullprec.csv", newline="")))
    r = np.array([float(x["coverage_gap_score"]) for x in a])
    f = np.array([float(x["coverage_gap_score"]) for x in b])
    rho = r - f
    sse_rho = float((rho ** 2).sum())

    sse_round = N * RMSE_ROUND ** 2
    sse_full = N * RMSE_FULL ** 2
    S = (sse_round - sse_full - sse_rho) / 2.0   # = sum(e_i * rho_i), pinned by observation

    # what the quantised-reference model can supply
    budget_grid = N * (5e-7) ** 2                # every tract in the "rounds to truth" group
    # ...but tracts in that group contribute 0 to SSE_round, so the group cannot
    # be all of them: the rest must carry SSE_round with |e_r| >= 1e-6 each.
    max_group = int(sse_round / (1e-6) ** 2)     # tracts the residual SSE can hide
    budget_real = min(N, max(0, N - 0)) * (5e-7) ** 2

    print("measured   sum(rho^2)            = %.6e" % sse_rho)
    print("observed   SSE(6dp)              = %.6e" % sse_round)
    print("observed   SSE(15dp)             = %.6e" % sse_full)
    print("implied    sum(e*rho)            = %.6e   (must be this negative)" % S)
    print()
    print("quantised-reference model can supply at most")
    print("  |sum(e*rho)| <= n*(5e-7)^2      = %.6e" % budget_grid)
    print("  shortfall factor               = %.2fx" % (abs(S) / budget_grid))
    print()
    print("and that ceiling is unreachable: it needs every tract to round onto the")
    print("true value, which would make SSE(6dp) = 0, not %.3e." % sse_round)
    print("Tracts needed at the per-tract maximum: %d, against %d available."
          % (int(np.ceil(abs(S) / (5e-7) ** 2)), N))
    print()
    print("=> 6-decimal quantisation of the reference does NOT account for the")
    print("   0.000003406 -> 0.00000355 degradation. Emitting 6 decimals is still")
    print("   the empirically better choice, but the stated mechanism is wrong and")
    print("   something about how the 15-decimal file was scored is unexplained.")
    _ = max_group, budget_real


if __name__ == "__main__":
    main()
