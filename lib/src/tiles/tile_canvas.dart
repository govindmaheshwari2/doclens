import 'dart:math' as math;
import 'dart:ui';

/// One of the four directions a multi-tile scan can grow in.
///
/// The user declares the direction by tapping a `+` on that edge of the
/// current composite, so the next capture's placement is known up front —
/// only a small fine-alignment over the overlap band remains. See
/// [TileCanvas] for how a direction maps to a grid position.
enum TileEdge { left, right, top, bottom }

extension TileEdgeGeometry on TileEdge {
  /// Integer grid step applied to a tile's [Tile.col]/[Tile.row] when a new
  /// tile is added off this edge. The root tile sits at `(0, 0)`; growing
  /// `right` increments the column, growing `down`/`bottom` the row.
  Point<int> get delta => switch (this) {
        TileEdge.left => const Point(-1, 0),
        TileEdge.right => const Point(1, 0),
        TileEdge.top => const Point(0, -1),
        TileEdge.bottom => const Point(0, 1),
      };

  /// The opposite edge. When a capture extends the composite [right], the
  /// new tile's *left* edge is what overlaps the anchor, so the alignment
  /// ghost is pinned there. Getting this mapping wrong inverts the overlap
  /// hint, so it lives in one place.
  TileEdge get opposite => switch (this) {
        TileEdge.left => TileEdge.right,
        TileEdge.right => TileEdge.left,
        TileEdge.top => TileEdge.bottom,
        TileEdge.bottom => TileEdge.top,
      };
}

/// A single captured page-fragment placed on the [TileCanvas] grid.
///
/// Position is stored as integer grid coordinates ([col], [row]) — adjacency
/// is therefore pure arithmetic, never inferred from vision. [refinedShift]
/// is the sub-tile pixel correction produced by the aligner relative to the
/// tile's anchor neighbour; it is `Offset.zero` until alignment runs (and
/// stays zero when the user keeps a tile on manual placement alone).
class Tile {
  Tile({
    required this.id,
    required this.imagePath,
    required this.col,
    required this.row,
    this.refinedShift = Offset.zero,
  });

  final int id;
  final String imagePath;
  final int col;
  final int row;
  Offset refinedShift;

  Point<int> get gridPos => Point(col, row);

  Tile copyWith({String? imagePath, Offset? refinedShift}) => Tile(
        id: id,
        imagePath: imagePath ?? this.imagePath,
        col: col,
        row: row,
        refinedShift: refinedShift ?? this.refinedShift,
      );

  @override
  String toString() => 'Tile(#$id @($col,$row) shift=$refinedShift)';
}

/// The growing 2-D arrangement of captured tiles.
///
/// The first tile added becomes the root at grid `(0, 0)`; every later tile
/// is positioned relative to an existing one via a [TileEdge]. The composite
/// the user is building is simply the bounding box of all placed tiles, so a
/// long page (a single row/column), an L-shape, or a 2×2 block all fall out
/// of the same model.
///
/// This class is deliberately free of any Flutter, camera, or image-codec
/// dependency so the placement logic can be unit-tested in isolation.
class TileCanvas {
  TileCanvas();

  final List<Tile> _tiles = [];
  int _nextId = 0;

  List<Tile> get tiles => List.unmodifiable(_tiles);
  bool get isEmpty => _tiles.isEmpty;
  int get length => _tiles.length;
  Tile get root => _tiles.first;

  /// Places the first tile at the origin. Throws if a root already exists —
  /// later tiles must go through [addAdjacent] so their position is defined
  /// relative to the existing composite.
  Tile addRoot(String imagePath) {
    if (_tiles.isNotEmpty) {
      throw StateError('Canvas already has a root tile.');
    }
    final tile = Tile(id: _nextId++, imagePath: imagePath, col: 0, row: 0);
    _tiles.add(tile);
    return tile;
  }

  /// Adds a tile one grid step off [edge] of [anchor]. The target slot must
  /// be empty (the UI only ever offers `+` on the outer boundary, so this
  /// should hold) — overlapping an occupied slot throws.
  Tile addAdjacent({
    required Tile anchor,
    required TileEdge edge,
    required String imagePath,
    Offset refinedShift = Offset.zero,
  }) {
    final d = edge.delta;
    final col = anchor.col + d.x;
    final row = anchor.row + d.y;
    if (tileAt(col, row) != null) {
      throw StateError('Grid slot ($col,$row) is already occupied.');
    }
    final tile = Tile(
      id: _nextId++,
      imagePath: imagePath,
      col: col,
      row: row,
      refinedShift: refinedShift,
    );
    _tiles.add(tile);
    return tile;
  }

  Tile? tileAt(int col, int row) {
    for (final t in _tiles) {
      if (t.col == col && t.row == row) return t;
    }
    return null;
  }

  /// The tile that a new fragment grown off [edge] of [anchor] would overlap
  /// (i.e. the anchor itself). Exposed for the aligner, which needs the pair.
  Tile overlapNeighbour(Tile anchor, TileEdge edge) => anchor;

  /// Edges of [tile] that point into an empty slot — the directions in which
  /// the composite can still grow from this tile. The UI renders a `+` for
  /// each, but only on tiles that actually sit on the outer boundary (every
  /// tile with at least one open edge does).
  Set<TileEdge> openEdgesOf(Tile tile) {
    final open = <TileEdge>{};
    for (final e in TileEdge.values) {
      final d = e.delta;
      if (tileAt(tile.col + d.x, tile.row + d.y) == null) open.add(e);
    }
    return open;
  }

  /// Inclusive grid bounds of the whole composite as
  /// `(minCol, minRow, maxCol, maxRow)`.
  ({int minCol, int minRow, int maxCol, int maxRow}) gridBounds() {
    var minCol = 0, minRow = 0, maxCol = 0, maxRow = 0;
    for (final t in _tiles) {
      minCol = math.min(minCol, t.col);
      minRow = math.min(minRow, t.row);
      maxCol = math.max(maxCol, t.col);
      maxRow = math.max(maxRow, t.row);
    }
    return (minCol: minCol, minRow: minRow, maxCol: maxCol, maxRow: maxRow);
  }

  /// Number of columns / rows spanned by the composite. Drives the miniview
  /// grid layout.
  ({int cols, int rows}) gridExtent() {
    final b = gridBounds();
    return (cols: b.maxCol - b.minCol + 1, rows: b.maxRow - b.minRow + 1);
  }

  /// Removes a tile (e.g. after a failed/rejected capture the user discards).
  /// Removing the root is only allowed when it is the sole tile, since every
  /// other tile is positioned relative to the existing composite.
  void remove(Tile tile) {
    if (tile.id == root.id && _tiles.length > 1) {
      throw StateError('Cannot remove the root while other tiles depend on it.');
    }
    _tiles.removeWhere((t) => t.id == tile.id);
  }
}
