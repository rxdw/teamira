import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../services/map_style_service.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// A real, pannable OpenStreetMap between the coach theme's origin and
/// destination — the honest upgrade to `journey_progress_screen.dart`'s
/// decorative S-curve, for the one theme that actually has two real
/// places on the globe to show. Same free, keyless OSM stack the app
/// already leans on for city search (Nominatim) and "what's nearby"
/// (Overpass) — this is just the map-tile half of it, via `flutter_map`.
///
/// The line drawn between the two points is a straight line ("as the
/// crow flies"), not a routed road path — Seenly has no routing engine,
/// and pretending otherwise would be the same kind of dishonesty the
/// old decorative curve already avoided in its own doc comment. The
/// marker rides that straight line in step with [progress].
///
/// [vehicle] picks which of the three the marker actually looks like —
/// coach gets a real train pictogram, ticket a plane, garden a walker —
/// since all three themes now have two real places to draw a map
/// between (see journey_select_screen.dart / journey_progress_screen.dart).
enum JourneyVehicle { train, plane, walk }

class JourneyRealMap extends StatefulWidget {
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;
  final String originLabel;
  final String destLabel;
  final double progress; // 0..1
  final Color accent;
  final IconData markerIcon;
  final JourneyVehicle vehicle;
  // 0 for edge-to-edge fullscreen use; the default (18) is for the old
  // small-card placement, kept around in case something else embeds this.
  final double borderRadius;
  // The bottom city-names + attribution strip baked into the map
  // itself — turned off when the screen around this draws its own
  // overlay chip/attribution instead (see journey_progress_screen.dart's
  // fullscreen layout), so the two don't stack on top of each other.
  final bool showLegendBar;
  // Which tile skin to draw — classic OSM by default, so every existing
  // call site (the old small-card placements) keeps looking exactly as
  // it did before this was added. The fullscreen route screen passes
  // whatever MapStyleService currently holds instead (see
  // journey_progress_screen.dart).
  final MapStyle style;

  const JourneyRealMap({
    super.key,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.originLabel,
    required this.destLabel,
    required this.progress,
    required this.accent,
    required this.markerIcon,
    this.vehicle = JourneyVehicle.train,
    this.borderRadius = 18,
    this.showLegendBar = true,
    this.style = MapStyle.classic,
  });

  @override
  State<JourneyRealMap> createState() => _JourneyRealMapState();
}

class _JourneyRealMapState extends State<JourneyRealMap> {
  final MapController _controller = MapController();
  bool _fitted = false;

  ll.LatLng get _origin => ll.LatLng(widget.originLat, widget.originLng);
  ll.LatLng get _dest => ll.LatLng(widget.destLat, widget.destLng);

  ll.LatLng get _markerPos => ll.LatLng(
        widget.originLat + (widget.destLat - widget.originLat) * widget.progress,
        widget.originLng + (widget.destLng - widget.originLng) * widget.progress,
      );

  // Initial compass bearing from origin to destination (standard
  // great-circle formula), used purely to turn the travel marker to
  // face the way it's heading — the same "leaning into the route"
  // look a real map app gives its live position glyph. An
  // approximation over a straight line, same honesty caveat as the
  // polyline itself.
  double get _headingRadians {
    final lat1 = widget.originLat * math.pi / 180;
    final lat2 = widget.destLat * math.pi / 180;
    final dLng = (widget.destLng - widget.originLng) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return math.atan2(y, x);
  }

  void _fitBounds() {
    if (_fitted) return;
    _fitted = true;
    final bounds = LatLngBounds.fromPoints([_origin, _dest]);
    _controller.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(48, 56, 48, 56)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: _origin,
                initialZoom: 8,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom,
                ),
                onMapReady: _fitBounds,
              ),
              children: [
                TileLayer(
                  urlTemplate: MapStyleCatalog.infoFor(widget.style).urlTemplate,
                  subdomains: MapStyleCatalog.infoFor(widget.style).subdomains,
                  userAgentPackageName: 'com.seenly.app',
                  // The "paper"/"night" (CARTO) styles' urlTemplate ends in
                  // {r} — a placeholder for "@2x" sharp tiles on high-density
                  // phone screens. Without retinaMode on, flutter_map fills
                  // {r} with nothing, so every device fetches the same
                  // low-res tile and stretches it to fit — that's exactly
                  // why city labels baked into the tile (London, Rouen,
                  // Amiens...) come out blurry/hard to read on a real phone.
                  // classic/terrain have no {r} in their template, so this
                  // is a no-op for them either way.
                  retinaMode: RetinaMode.isHighDensity(context),
                  // Same OSM tile-usage courtesy as GeoCityService's own
                  // requests — a real identifying User-Agent header.
                  // Applies to every style here, not just plain OSM:
                  // CARTO's and OpenTopoMap's own usage policies ask for
                  // the same courtesy.
                  tileProvider: NetworkTileProvider(
                    // Deliberately not `const` — flutter_map's
                    // NetworkTileProvider mutates this map internally
                    // (adds its own headers on top), so an unmodifiable
                    // const map throws "Cannot modify unmodifiable map"
                    // the moment a tile request goes out.
                    headers: {'User-Agent': 'SeenlyApp/1.0 (evening diary app)'},
                  ),
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_origin, _dest],
                      strokeWidth: 3,
                      color: widget.accent.withOpacity(0.55),
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _origin,
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      child: const _StartMarker(color: SeenlyPalette.sage),
                    ),
                    Marker(
                      point: _dest,
                      width: 40,
                      height: 50,
                      alignment: Alignment.bottomCenter,
                      child: const _DestinationPin(color: SeenlyPalette.coral),
                    ),
                    Marker(
                      point: _markerPos,
                      width: 60,
                      height: 34,
                      alignment: Alignment.center,
                      child: _TravelMarker(
                        color: widget.accent,
                        heading: _headingRadians,
                        vehicle: widget.vehicle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // A soft label strip along the bottom — tile attribution (OSM
          // requires this) plus the origin/destination names, since the
          // map itself doesn't reliably show place labels at every zoom.
          // Only rendered when nothing outside this widget is already
          // showing that same information over the map (see
          // [showLegendBar]).
          if (widget.showLegendBar)
            Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
              color: SeenlyPalette.paper.withOpacity(0.9),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LegendDot(color: SeenlyPalette.sage),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            widget.originLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.ink, weight: FontWeight.w600),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Icon(Icons.arrow_forward, size: 10, color: SeenlyPalette.inkFaint),
                        ),
                        _LegendDot(color: SeenlyPalette.coral),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            widget.destLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.ink, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(MapStyleCatalog.infoFor(widget.style).attribution,
                      style: SeenlyText.mono(size: 7.5, color: SeenlyPalette.inkFaint)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// The "departed from" marker — a small layered dot rather than a full
/// pin, since this point is already behind you: a soft colored halo, a
/// white ring, and a solid center. Anchored dead-center on the
/// coordinate (see its `Marker.alignment`), unlike the destination pin
/// below.
class _StartMarker extends StatelessWidget {
  final Color color;
  const _StartMarker({required this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.16)),
        ),
        Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SeenlyPalette.paper,
            border: Border.all(color: color, width: 2.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 5, offset: const Offset(0, 2))],
          ),
        ),
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      ],
    );
  }
}

/// The "heading to" marker — a proper teardrop map pin (Material's
/// `location_on` glyph, colored and given a soft halo + white "eye" so
/// it reads as a real pin rather than a flat icon), anchored by its
/// point at the exact coordinate — see its `Marker.alignment.bottomCenter`.
class _DestinationPin extends StatelessWidget {
  final Color color;
  const _DestinationPin({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 50,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.22)),
            ),
          ),
          // A soft offset duplicate standing in for a drop shadow —
          // avoids relying on `Icon.shadows`, which isn't present on
          // every Flutter version this project might be built with.
          Positioned(
            top: 2,
            child: Icon(Icons.location_on, size: 40, color: Colors.black.withOpacity(0.22)),
          ),
          Icon(Icons.location_on, size: 40, color: color),
          const Positioned(
            top: 10,
            child: SizedBox(
              width: 12,
              height: 12,
              child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: SeenlyPalette.paper)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tonight's actual position, riding the line — a proper little train
/// drawn from scratch (rounded nose, a row of windows, a rear divider,
/// wheels, and the faint ground line underneath), not a generic Material
/// icon in a badge. White body with a dark line-art outline, same
/// silhouette language as a real train pictogram, turned to face the
/// direction of travel with a soft drop shadow beneath it.
class _TravelMarker extends StatelessWidget {
  final Color color;
  final double heading; // radians, clockwise from north
  final JourneyVehicle vehicle;
  const _TravelMarker({required this.color, this.heading = 0, this.vehicle = JourneyVehicle.train});

  @override
  Widget build(BuildContext context) {
    return switch (vehicle) {
      JourneyVehicle.train => Transform.rotate(
          angle: heading,
          child: CustomPaint(size: const Size(60, 34), painter: _TrainGlyphPainter(accent: color)),
        ),
      JourneyVehicle.plane => Transform.rotate(
          angle: heading,
          child: CustomPaint(size: const Size(52, 34), painter: _PlaneGlyphPainter(accent: color)),
        ),
      // A walker doesn't lean into a heading the way a train or plane
      // does — footprints read fine upright regardless of which way
      // the path bends, so this one skips the rotation.
      JourneyVehicle.walk => CustomPaint(size: const Size(40, 34), painter: _WalkerGlyphPainter(accent: color)),
    };
  }
}

/// A simple stylised top-down airliner silhouette — fuselage, swept
/// wings, a tail fin — nose pointing toward +x the same way the train
/// glyph's nose does, so [heading] rotates it the same honest way.
class _PlaneGlyphPainter extends CustomPainter {
  final Color accent;
  const _PlaneGlyphPainter({required this.accent});

  Path _body() {
    final p = Path();
    // Fuselage.
    p.moveTo(22, 0);
    p.quadraticBezierTo(14, -3, -18, -2.5);
    p.quadraticBezierTo(-22, 0, -18, 2.5);
    p.quadraticBezierTo(14, 3, 22, 0);
    p.close();
    return p;
  }

  Path _wings() {
    final p = Path();
    p.moveTo(2, -1.5);
    p.lineTo(-8, -15);
    p.lineTo(-13, -14);
    p.lineTo(-6, -0.5);
    p.close();
    p.moveTo(2, 1.5);
    p.lineTo(-8, 15);
    p.lineTo(-13, 14);
    p.lineTo(-6, 0.5);
    p.close();
    return p;
  }

  Path _tail() {
    final p = Path();
    p.moveTo(-15, 0);
    p.lineTo(-22, -8);
    p.lineTo(-19, -8);
    p.lineTo(-14, -1.5);
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    final body = _body();
    final wings = _wings();
    final tail = _tail();

    // Soft drop shadow, same trick as the train glyph.
    canvas.save();
    canvas.translate(0, 2.4);
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.2);
    canvas.drawPath(body, shadowPaint);
    canvas.drawPath(wings, shadowPaint);
    canvas.drawPath(tail, shadowPaint);
    canvas.restore();

    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = SeenlyPalette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(wings, Paint()..color = accent);
    canvas.drawPath(wings, stroke);
    canvas.drawPath(tail, Paint()..color = accent);
    canvas.drawPath(tail, stroke);
    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);

    // A little window strip along the nose, same accenting idea as the
    // train's windows.
    canvas.drawCircle(const Offset(10, 0), 1.4, Paint()..color = accent);
    canvas.drawCircle(const Offset(5, 0), 1.4, Paint()..color = accent);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlaneGlyphPainter oldDelegate) => oldDelegate.accent != accent;
}

/// A small pair of footprints, standing in for a walker on the map —
/// simple, upright, and legible at map scale rather than a literal
/// walking figure.
class _WalkerGlyphPainter extends CustomPainter {
  final Color accent;
  const _WalkerGlyphPainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    canvas.drawCircle(const Offset(0, 2), 13, Paint()..color = SeenlyPalette.paper);
    canvas.drawCircle(
      const Offset(0, 2),
      13,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    Path footprint(double x, double y, double rotation) {
      final p = Path()
        ..addOval(Rect.fromCenter(center: const Offset(0, 0), width: 5, height: 8))
        ..addOval(Rect.fromCenter(center: const Offset(0, -5.5), width: 3, height: 3.6));
      final matrix = Matrix4.identity()
        ..translate(x, y)
        ..rotateZ(rotation);
      return p.transform(matrix.storage);
    }

    final footPaint = Paint()..color = accent;
    canvas.drawPath(footprint(-3, 6, -0.25), footPaint);
    canvas.drawPath(footprint(3, -2, 0.2), footPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WalkerGlyphPainter oldDelegate) => oldDelegate.accent != accent;
}

/// Draws the train itself, in a local coordinate space centered on the
/// canvas with the nose pointing toward +x (the direction the marker
/// gets rotated to face). Modeled on a real high-speed-train side
/// profile: a rounded back, a smooth sloped nose, a window band, a
/// divider marking off the rear car, wheels, and a faint ground line —
/// the same reading as a proper train pictogram rather than a stock
/// icon glyph.
class _TrainGlyphPainter extends CustomPainter {
  final Color accent;
  const _TrainGlyphPainter({required this.accent});

  Path _body() {
    final p = Path();
    p.moveTo(-24, -8);
    p.lineTo(2, -8);
    p.cubicTo(14, -8, 22, -5, 26, 0);
    p.cubicTo(22, 5, 14, 8, 8, 8);
    p.lineTo(-24, 8);
    p.quadraticBezierTo(-27, 8, -27, 5);
    p.lineTo(-27, -5);
    p.quadraticBezierTo(-27, -8, -24, -8);
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    final body = _body();

    // The faint ground line the wheels sit on — the same baseline a
    // real train pictogram draws underneath itself.
    canvas.drawLine(
      const Offset(-30, 11),
      const Offset(28, 11),
      Paint()
        ..color = SeenlyPalette.ink.withOpacity(0.22)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );

    // Soft drop shadow: the same silhouette again, offset down and
    // faded, the trick used by the other markers in this file.
    canvas.save();
    canvas.translate(0, 2.6);
    canvas.drawPath(body, Paint()..color = Colors.black.withOpacity(0.22));
    canvas.restore();

    // The body: white fill, dark line-art outline.
    canvas.drawPath(body, Paint()..color = Colors.white);
    canvas.drawPath(
      body,
      Paint()
        ..color = SeenlyPalette.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // A rear divider marking off the little coupler section, the way
    // the reference icon separates its own front car from the body.
    canvas.drawLine(
      const Offset(-16, -8),
      const Offset(-16, 8),
      Paint()
        ..color = SeenlyPalette.ink
        ..strokeWidth = 1.6,
    );

    // Windows, in the theme's own accent color so each journey still
    // carries its color at a glance even without the old puck.
    final windowPaint = Paint()..color = accent;
    for (final x in [-21.0, -13.0, -5.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, -5.5, 6, 5.5), const Radius.circular(1.6)),
        windowPaint,
      );
    }

    // Wheels.
    final wheelPaint = Paint()..color = SeenlyPalette.ink;
    for (final x in [-16.0, -2.0, 12.0]) {
      canvas.drawCircle(Offset(x, 8), 2.6, wheelPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TrainGlyphPainter oldDelegate) => oldDelegate.accent != accent;
}
