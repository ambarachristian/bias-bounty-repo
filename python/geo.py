"""Shared geometry helpers: WKB -> shapely, EPSG:4326 -> EPSG:5070 projection,
and batched row-group iteration over the challenge parquet files.

Memory discipline: nothing here ever materialises a whole layer. Callers pull
one parquet row group at a time and hand the arrays straight back.
"""
import numpy as np
import pyarrow.parquet as pq
import pyproj
import shapely

# always_xy: the layers are lon/lat OGC:CRS84. Verified bit-identical to
# DuckDB's ST_Transform(..., always_xy := true) on sample points.
_TF = pyproj.Transformer.from_crs("EPSG:4326", "EPSG:5070", always_xy=True)


def to_5070(geoms):
    """Project an ndarray of shapely geometries to EPSG:5070, IN PLACE.

    Coordinates are transformed as one flat array, which is what DuckDB does
    too (point-wise, no densification), so the two agree to the bit. The
    geometries are mutated, so pass freshly parsed WKB when you also need the
    lon/lat original.
    """
    geoms = np.asarray(geoms, dtype=object)
    if len(geoms) == 0:
        return geoms
    coords = shapely.get_coordinates(geoms)
    x, y = _TF.transform(coords[:, 0], coords[:, 1])
    coords[:, 0] = x
    coords[:, 1] = y
    return shapely.set_coordinates(geoms, coords)


def row_groups(path, columns, batch_row_groups=1):
    """Yield pyarrow Tables, `batch_row_groups` parquet row groups at a time."""
    f = pq.ParquetFile(path)
    n = f.metadata.num_row_groups
    for i in range(0, n, batch_row_groups):
        idx = list(range(i, min(i + batch_row_groups, n)))
        yield f.read_row_groups(idx, columns=columns)
    f.close()


def wkb_to_geoms(col):
    """pyarrow binary column -> ndarray of shapely geometries."""
    return shapely.from_wkb(np.asarray(col.to_pylist(), dtype=object))
