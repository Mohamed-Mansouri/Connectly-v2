import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../app/connectly_theme.dart';
import '../data/people_repository.dart';

const arianaCenter = LatLng(36.8625, 10.19556);
final arianaBounds =
    LatLngBounds(const LatLng(36.84, 10.15), const LatLng(36.90, 10.21));
bool inAriana(PeopleLocation location) =>
    arianaBounds.contains(LatLng(location.latitude, location.longitude));

class _MapData {
  _MapData(this.roads, this.areas);
  final List<Polyline> roads;
  final List<Polygon> areas;
  static Future<_MapData> load() async {
    final json =
        jsonDecode(await rootBundle.loadString('assets/maps/ariana.json'))
            as Map<String, dynamic>;
    final roads = <Polyline>[];
    final areas = <Polygon>[];
    for (final feature in json['features'] as List) {
      final points = (feature['points'] as List)
          .map(
              (p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList();
      final kind = feature['kind'] as String;
      if (kind == 'water' || kind == 'park') {
        if (points.first == points.last && points.length > 3) {
          areas.add(Polygon(
              points: points,
              color: kind == 'water'
                  ? const Color(0xFF294B68)
                  : const Color(0xFF294B44),
              borderStrokeWidth: 0));
        }
      } else {
        final major =
            ['motorway', 'trunk', 'primary', 'secondary'].contains(kind);
        roads.add(Polyline(
            points: points,
            strokeWidth: major ? 2.1 : 0.8,
            color: major ? const Color(0xFF8092A5) : const Color(0xFF415673)));
      }
    }
    return _MapData(roads, areas);
  }
}

/// Vector geometry is bundled with the APK. No tile provider or HTTP client.
class ArianaMap extends StatefulWidget {
  const ArianaMap(
      {this.ownLocation,
      this.people = const [],
      this.selectedId,
      this.onSelect,
      this.onPlacePin,
      this.radiusKm,
      super.key});
  final PeopleLocation? ownLocation;
  final List<LocatedPerson> people;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final ValueChanged<PeopleLocation>? onPlacePin;
  final double? radiusKm;
  @override
  State<ArianaMap> createState() => _ArianaMapState();
}

class _ArianaMapState extends State<ArianaMap> {
  static _MapData? _cached;
  late Future<_MapData> _data = _load();
  Future<_MapData> _load() async => _cached ??= await _MapData.load();
  final _controller = MapController();
  bool _ready = false;
  LatLng get _center =>
      widget.ownLocation != null && inAriana(widget.ownLocation!)
          ? LatLng(widget.ownLocation!.latitude, widget.ownLocation!.longitude)
          : arianaCenter;

  @override
  void didUpdateWidget(ArianaMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready && oldWidget.ownLocation != widget.ownLocation) {
      _controller.move(_center, _controller.camera.zoom);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: FutureBuilder<_MapData>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Could not open the offline Ariana map.'),
                  TextButton(
                      onPressed: () => setState(() {
                            _cached = null;
                            _data = _load();
                          }),
                      child: const Text('Retry map')),
                ]));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return Stack(children: [
                FlutterMap(
                    mapController: _controller,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 13.3,
                      minZoom: 12,
                      maxZoom: 16,
                      cameraConstraint:
                          CameraConstraint.containCenter(bounds: arianaBounds),
                      backgroundColor: const Color(0xFF1D3048),
                      interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                      onMapReady: () => _ready = true,
                      onTap: (_, point) {
                        if (widget.onPlacePin == null) return;
                        final pin =
                            PeopleLocation(point.latitude, point.longitude);
                        if (inAriana(pin)) widget.onPlacePin!(pin);
                      },
                    ),
                    children: [
                      PolygonLayer(polygons: [
                        ...snapshot.data!.areas,
                        Polygon(
                            points: [
                              const LatLng(36.84, 10.15),
                              const LatLng(36.84, 10.21),
                              const LatLng(36.90, 10.21),
                              const LatLng(36.90, 10.15)
                            ],
                            color: Colors.transparent,
                            borderColor: Colors.white38,
                            borderStrokeWidth: 1),
                      ]),
                      PolylineLayer(polylines: snapshot.data!.roads),
                      if (widget.ownLocation != null &&
                          inAriana(widget.ownLocation!) &&
                          widget.radiusKm != null)
                        CircleLayer(circles: [
                          CircleMarker(
                              point: _center,
                              radius: widget.radiusKm! * 1000,
                              useRadiusInMeter: true,
                              color:
                                  ConnectlyTheme.yellow.withValues(alpha: .08),
                              borderColor:
                                  ConnectlyTheme.yellow.withValues(alpha: .5),
                              borderStrokeWidth: 1)
                        ]),
                      MarkerLayer(markers: [
                        for (final entry in widget.people)
                          if (entry.location != null && inAriana(entry.location!))
                            Marker(
                                point: LatLng(entry.location!.latitude,
                                    entry.location!.longitude),
                                width: 48,
                                height: 48,
                                child: Semantics(
                                    label: 'Select ${entry.person.name}',
                                    button: true,
                                    child: IconButton.filled(
                                        key: ValueKey('pin_${entry.person.id}'),
                                        tooltip: entry.person.name,
                                        style: IconButton.styleFrom(
                                            backgroundColor: widget.selectedId ==
                                                    entry.person.id
                                                ? ConnectlyTheme.yellow
                                                : ConnectlyTheme.surface,
                                            foregroundColor: widget.selectedId ==
                                                    entry.person.id
                                                ? ConnectlyTheme.navy
                                                : Colors.white,
                                            side: const BorderSide(
                                                color: ConnectlyTheme.yellow)),
                                        onPressed: () => widget.onSelect
                                            ?.call(entry.person.id),
                                        icon: const Icon(Icons.person,
                                            size: 24)))),
                        if (widget.ownLocation != null &&
                            inAriana(widget.ownLocation!))
                          Marker(
                              point: _center,
                              width: 30,
                              height: 30,
                              child: const Tooltip(
                                  message: 'Your saved pin',
                                  child: Icon(Icons.my_location,
                                      color: ConnectlyTheme.yellow, size: 28))),
                        Marker(
                            point: arianaCenter,
                            width: 60,
                            height: 20,
                            child: const IgnorePointer(
                                child: Text('ARIANA',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)))),
                      ]),
                    ]),
                Positioned(
                    top: 8,
                    left: 8,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: ConnectlyTheme.navy,
                            borderRadius: BorderRadius.circular(8)),
                        child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            child: Text('Ariana · offline',
                                style: TextStyle(fontSize: 11))))),
                Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                        tooltip: 'Center map',
                        onPressed: () => _controller.move(_center, 13.3),
                        icon: const Icon(Icons.center_focus_strong))),
                Positioned(
                    bottom: 0,
                    right: 0,
                    child: Material(
                        color: ConnectlyTheme.navy,
                        child: InkWell(
                            onTap: () => showDialog<void>(
                                context: context,
                                builder: (_) =>
                                    AlertDialog(
                                        title:
                                            const Text('Offline map credits'),
                                        content: const SelectableText(
                                            '© OpenStreetMap contributors\nData © OpenStreetMap, ODbL 1.0\nhttps://www.openstreetmap.org/copyright\nhttps://opendatacommons.org/licenses/odbl/1-0/\n\nA simplified street map bundled for the Ariana presentation. Coverage: Ariana city, 36.84–36.90°N, 10.15–10.21°E.'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('Close'))
                                        ])),
                            child: const Padding(
                                padding: EdgeInsets.all(5),
                                child: Text(
                                    '© OpenStreetMap contributors · ODbL',
                                    style: TextStyle(fontSize: 10)))))),
              ]);
            }),
      );
}
