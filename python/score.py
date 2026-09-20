"""Turn per-tract component counts into gaps. Mirrors sql/06_score.sql.

gap = 1 - min(1, overture / reference), defined iff reference > 0.
Undefined components are excluded from the mean, not zero-filled; the emitted
value for an undefined component is 0 with its *_defined flag FALSE.
"""
import numpy as np

NAN = float("nan")


def _gap(ov, refc):
    """1 - min(1, ov/ref) where ref > 0, else NaN."""
    ov = np.asarray(ov, dtype=float)
    refc = np.asarray(refc, dtype=float)
    out = np.full(ov.shape, NAN)
    d = refc > 0
    with np.errstate(invalid="ignore", divide="ignore"):
        out[d] = 1.0 - np.minimum(1.0, ov[d] / refc[d])
    return out


def _mean_defined(parts):
    """Element-wise mean over the non-NaN members; NaN where all are NaN."""
    stack = np.vstack(parts)
    defined = ~np.isnan(stack)
    n = defined.sum(axis=0)
    total = np.where(defined, stack, 0.0).sum(axis=0)
    out = np.full(stack.shape[1], NAN)
    nz = n > 0
    out[nz] = total[nz] / n[nz]
    return out


def score(c):
    transport = _gap(c["overture_m"], c["tiger_m"])
    building = _gap(c["bldg_ov"], c["bldg_ms"])
    g_fire = _gap(c["ov_fire"], c["hf_fire"])
    g_ems = _gap(c["ov_ems"], c["hf_ems"])
    g_school = _gap(c["ov_school"], c["hf_school"])
    g_cbp = _gap(c["ov_all"], c["cbp_estab"])
    hifld_half = _mean_defined([g_fire, g_ems, g_school])
    poi = _mean_defined([hifld_half, g_cbp])
    coverage = _mean_defined([transport, building, poi])
    return {
        "GEOID": c["GEOID"],
        "coverage_gap_score": coverage,
        "transport_gap": transport,
        "building_gap": building,
        "poi_gap": poi,
        "poi_gap_fire": g_fire,
        "poi_gap_ems": g_ems,
        "poi_gap_schools": g_school,
        "poi_gap_cbp": g_cbp,
        "n_defined": (~np.isnan(np.vstack([transport, building, poi]))).sum(axis=0),
    }
