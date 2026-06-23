/// doclens — document scanner with native edge detection and
/// perspective warp, paired with 100% Flutter UI.
library;

export 'src/controller.dart';
export 'src/models.dart';
export 'src/ocr.dart';
export 'src/platform_interface.dart' show DoclensPlatform, DetectionEvent;
export 'src/quad.dart';
export 'src/quad_smoother.dart';
export 'src/stability_tracker.dart';
export 'src/status_classifier.dart';
export 'src/large_doc/large_doc_aligner.dart';
export 'src/large_doc/large_doc_canvas.dart';
export 'src/large_doc/large_doc_merger.dart';
export 'src/large_doc/large_doc_session.dart';
export 'src/widgets/large_doc_screen.dart';
export 'src/widgets/doclens_screen.dart';
export 'src/widgets/doclens_view.dart';
export 'src/widgets/edit_corners_screen.dart';
export 'src/widgets/quad_overlay.dart';
