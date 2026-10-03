import 'reading_locator.dart';

/// Called when the place a reader is showing changes: where, how far through
/// the whole book (0..1), and whether a person did it (a swipe, a scroll) as
/// opposed to the room moving the page for them. Only a person's own turn is
/// allowed to move the shared place in "together" mode — which is what stops
/// two phones passing the same page back and forth.
typedef ReaderMoved = void Function(ReadLocator at, double fraction, {required bool byUser});

/// Lets the room screen drive whichever reader is showing without knowing
/// which one it is.
class ReaderHandle {
  void Function(ReadLocator at)? _go;
  String? Function()? _quote;

  /// Takes the reader to a place (a follow, or "go to where she is").
  void goTo(ReadLocator at) => _go?.call(at);

  /// A line from the page you're on, for pinning a note to — null when the
  /// reader has none (a comic, a chapter counter).
  String? quoteNow() => _quote?.call();

  void attach({required void Function(ReadLocator at) go, String? Function()? quote}) {
    _go = go;
    _quote = quote;
  }

  void detach() {
    _go = null;
    _quote = null;
  }
}
