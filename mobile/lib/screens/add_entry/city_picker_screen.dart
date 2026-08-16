import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/world_cities.dart';
import '../../services/geo_city_service.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../services/app_translations.dart';

/// Lets the person set an arbitrary "from" city for the coach route
/// picker — searches live against OpenStreetMap (any real place on
/// Earth, not a fixed shortlist), falling back to the small bundled
/// [worldCities] list if there's no connection. Pushed from the
/// "change" link on journey_select_screen.dart's from/to card; pops
/// with the chosen [GeoCity].
class CityPickerScreen extends StatefulWidget {
  const CityPickerScreen({super.key});

  @override
  State<CityPickerScreen> createState() => _CityPickerScreenState();
}

class _CityPickerScreenState extends State<CityPickerScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<GeoCity> _results = const [];
  bool _searching = false;
  bool _offline = false;

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final live = await GeoCityService.search(q);
    if (!mounted) return;
    if (live.isNotEmpty) {
      setState(() {
        _results = live;
        _searching = false;
        _offline = false;
      });
      return;
    }
    // No network, or nothing came back — fall back to the small
    // bundled list so the picker still works offline.
    final ql = q.toLowerCase();
    final local = worldCities
        .where((c) => c.name.toLowerCase().contains(ql) || c.country.toLowerCase().contains(ql))
        .map((c) => GeoCity(name: c.name, country: c.country, lat: c.lat, lng: c.lng))
        .toList();
    setState(() {
      _results = local;
      _searching = false;
      _offline = true;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text('choose a city'.tr, style: SeenlyText.serif(italic: true, size: 15)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SeenlyPalette.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 16, color: SeenlyPalette.inkFaint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        onChanged: (v) {
                          setState(() {}); // refresh hasQuery for the hint row below
                          _onQueryChanged(v);
                        },
                        style: SeenlyText.bodyText,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'any city in the world'.tr,
                          hintStyle: SeenlyText.bodyText.copyWith(color: SeenlyPalette.placeholder),
                        ),
                      ),
                    ),
                    if (_searching)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: SeenlyPalette.inkFaint),
                      ),
                  ],
                ),
              ),
            ),
            if (_offline && _results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text('offline — showing a shorter local list'.tr,
                    style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
              ),
            Expanded(
              child: !hasQuery
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text('start typing a city name'.tr,
                            textAlign: TextAlign.center,
                            style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
                      ),
                    )
                  : (_results.isEmpty && !_searching)
                      ? Center(
                          child: Text('no matches'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                          itemCount: _results.length,
                          itemBuilder: (context, i) {
                            final city = _results[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(city.name, style: SeenlyText.serif(size: 14, weight: FontWeight.w600)),
                              subtitle: city.country == null
                                  ? null
                                  : Text(city.country!,
                                      style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                              onTap: () => Navigator.of(context).pop(city),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
