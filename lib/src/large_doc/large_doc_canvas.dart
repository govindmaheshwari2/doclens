import 'dart:math' as math;
import 'dart:ui';

/// One of the four directions a multi-piece scan can grow in.
///
/// The user declares the direction by tapping a `+` on that edge of the
/// current composite, so the next capture's placement is known up front —
/// only a small fine-alignment over the overlap band remains. See
/// [LargeDocCanvas] for how a direction maps to a grid position.
enum LargeDocEdge { left, right, top, bottom }

extension LargeDocEdgeGeometry on LargeDocEdge {
  /// Integer grid step applied to a piece's [LargeDocPiece.col]/[LargeDocPiece.row] when a new
  /// piece is added off this edge. The root piece sits at `(0, 0)`; growing
  /// `right` increments the column, growing `down`/`bottom` the row.
  math.Point<int> get delta => switch (this) {
        LargeDocEdge.left => const math.Point(-1, 0),
        LargeDocEdge.right => const math.Point(1, 0),
        LargeDocEdge.top => const math.Point(0, -1),
        LargeDocEdge.bottom => const math.Point(0, 1),
      };

  /// The opposite edge. When a capture extends the composite [right], the
  /// new piece's *left* edge is what overlaps the anchor, so the alignment
  /// ghost is pinned there. Getting this mapping wrong inverts the overlap
  /// hint, so it lives in one place.
  LargeDocEdge get opposite => switch (this) {
        LargeDocEdge.left => LargeDocEdge.right,
        LargeDocEdge.right => LargeDocEdge.left,
        LargeDocEdge.top => LargeDocEdge.bottom,
        LargeDocEdge.bottom => LargeDocEdge.top,
      };
}

/// A single captured page-fragment placed on the [LargeDocCanvas] grid.
///
/// Position is stored as integer grid coordinates ([col], [row]) — adjacency
/// is therefore pure arithmetic, never inferred from vision. [refinedShift]
/// is the sub-piece pixel correction produced by the aligner relative to the
/// piece's anchor neighbour; it is `Offset.zero` until alignment runs (and
/// stays zero when the user keeps a piece on manual placement alone).
class LargeDocPiece {
  LargeDocPiece({
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

  math.Point<int> get gridPos => math.Point(col, row);

  LargeDocPiece copyWith({String? imagePath, Offset? refinedShift}) => LargeDocPiece(
        id: id,
        imagePath: imagePath ?? this.imagePath,
        col: col,
        row: row,
        refinedShift: refinedShift ?? this.refinedShift,
      );

  @override
  String toString() => 'LargeDocPiece(#$id @($col,$row) shift=$refinedShift)';
}

/// The growing 2-D arrangement of captured pieces.
///
/// The first piece added becomes the root at grid `(0, 0)`; every later piece
/// is positioned relative to an existing one via a [LargeDocEdge]. The composite
/// the user is building is simply the bounding box of all placed pieces, so a
/// long page (a single row/column), an L-shape, or a 2×2 block all fall out
/// of the same model.
///
/// This class is deliberately free of any Flutter, camera, or image-codec
/// dependency so the placement logic can be unit-tested in isolation.
class LargeDocCanvas {
  LargeDocCanvas();

  final List<LargeDocPiece> _tiles = [];
  int _nextId = 0;

  List<LargeDocPiece> get pieces => List.unmodifiable(_tiles);
  bool get isEmpty => _tiles.isEmpty;
  int get length => _tiles.length;
  LargeDocPiece get root => _tiles.first;

  /// Places the first piece at the origin. Throws if a root already exists —
  /// later pieces must go through [addAdjacent] so their position is defined
  /// relative to the existing composite.
  LargeDocPiece addRoot(String imagePath) {
    if (_tiles.isNotEmpty) {
      throw StateError('Canvas already has a root piece.');
    }
    final piece = LargeDocPiece(id: _nextId++, imagePath: imagePath, col: 0, row: 0);
    _tiles.add(piece);
    return piece;
  }

  /// Adds a piece one grid step off [edge] of [anchor]. The target slot must
  /// be empty (the UI only ever offers `+` on the outer boundary, so this
  /// should hold) — overlapping an occupied slot throws.
  LargeDocPiece addAdjacent({
    required LargeDocPiece anchor,
    required LargeDocEdge edge,
    required String imagePath,
    Offset refinedShift = Offset.zero,
  }) {
    final d = edge.delta;
    final col = anchor.col + d.x;
    final row = anchor.row + d.y;
    if (pieceAt(col, row) != null) {
      throw StateError('Grid slot ($col,$row) is already occupied.');
    }
    final piece = LargeDocPiece(
      id: _nextId++,
      imagePath: imagePath,
      col: col,
      row: row,
      refinedShift: refinedShift,
    );
    _tiles.add(piece);
    return piece;
  }

  LargeDocPiece? pieceAt(int col, int row) {
    for (final t in _tiles) {
      if (t.col == col && t.row == row) return t;
    }
    return null;
  }

  /// The piece that a new fragment grown off [edge] of [anchor] would overlap
  /// (i.e. the anchor itself). Exposed for the aligner, which needs the pair.
  LargeDocPiece overlapNeighbour(LargeDocPiece anchor, LargeDocEdge edge) => anchor;

  /// Edges of [piece] that point into an empty slot — the directions in which
  /// the composite can still grow from this piece. The UI renders a `+` for
  /// each, but only on pieces that actually sit on the outer boundary (every
  /// piece with at least one open edge does).
  Set<LargeDocEdge> openEdgesOf(LargeDocPiece piece) {
    final open = <LargeDocEdge>{};
    for (final e in LargeDocEdge.values) {
      final d = e.delta;
      if (pieceAt(piece.col + d.x, piece.row + d.y) == null) open.add(e);
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

  /// Removes a piece (e.g. after a failed/rejected capture the user discards).
  /// Removing the root is only allowed when it is the sole piece, since every
  /// other piece is positioned relative to the existing composite.
  void remove(LargeDocPiece piece) {
    if (piece.id == root.id && _tiles.length > 1) {
      throw StateError('Cannot remove the root while other pieces depend on it.');
    }
    _tiles.removeWhere((t) => t.id == piece.id);
  }
}
