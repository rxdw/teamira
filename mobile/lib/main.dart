import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge: without this, Android reserves the status bar as its
  // own opaque strip instead of letting app content (e.g. the poster
  // collage behind Collections' full-screen header) draw underneath it,
  // which is what shows up as a bare cream sliver at the very top of
  // screens with a hero image header. Individual screens still control
  // their own icon color via AnnotatedRegion<SystemUiOverlayStyle>.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  runApp(const SeenlyApp());
}
