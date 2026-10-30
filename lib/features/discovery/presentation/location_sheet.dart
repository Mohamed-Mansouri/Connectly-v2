import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../app/connectly_theme.dart';
import '../data/people_repository.dart';
import 'ariana_map.dart';

Future<PeopleLocation> readDeviceLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationProblem(
        'Location is turned off. Enable it or place your pin on the map.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const LocationProblem(
        'Location permission is unavailable. You can still tap the map to place a pin.');
  }
  final fix = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)));
  return PeopleLocation(fix.latitude, fix.longitude);
}

class LocationProblem implements Exception {
  const LocationProblem(this.message);
  final String message;
}

class LocationEdit {
  const LocationEdit(this.location);
  final PeopleLocation? location;
}

class LocationSheet extends StatefulWidget {
  const LocationSheet(
      {this.initial, this.locate = readDeviceLocation, super.key});
  final PeopleLocation? initial;
  final Future<PeopleLocation> Function() locate;
  @override
  State<LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<LocationSheet> {
  late PeopleLocation? _point = widget.initial;
  late bool _visible = widget.initial?.visible ?? true;
  bool _locating = false;
  String? _error;

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final point = await widget.locate();
      if (!mounted) {
        return;
      }
      if (!inAriana(point)) {
        setState(() => _error =
            'Your location is outside this Ariana map. Tap the map to choose a presentation pin.');
      } else {
        setState(() => _point = point);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is LocationProblem
            ? error.message
            : 'Could not get a location fix. Try again or tap the map to place a pin.');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
          child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: ListView(children: [
              Row(children: [
                const Expanded(
                    child: Text('Your map pin',
                        style: TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w700))),
                IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close))
              ]),
              const Text(
                  'Tap the Ariana map to place your pin, or use your current location. Only saved pins are used; there is no live tracking.'),
              const SizedBox(height: 12),
              SizedBox(
                  height:
                      (MediaQuery.sizeOf(context).height * .38).clamp(220, 320),
                  child: ArianaMap(
                      ownLocation: _point,
                      onPlacePin: (point) => setState(() {
                            _point = point;
                            _error = null;
                          }))),
              if (_point != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        '${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)}',
                        textAlign: TextAlign.center)),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: const TextStyle(color: ConnectlyTheme.yellow))),
              SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show my pin to local accounts'),
                  value: _visible,
                  onChanged: (value) => setState(() => _visible = value)),
              Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                TextButton.icon(
                    onPressed: _locating ? null : _locate,
                    icon: _locating
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                    label: Text(
                        _locating ? 'Getting location…' : 'Use my location')),
                if (widget.initial != null)
                  TextButton(
                      onPressed: () =>
                          Navigator.pop(context, const LocationEdit(null)),
                      child: const Text('Remove pin')),
              ]),
              FilledButton(
                  onPressed: _point == null
                      ? null
                      : () => Navigator.pop(
                          context,
                          LocationEdit(PeopleLocation(
                              _point!.latitude, _point!.longitude,
                              visible: _visible))),
                  child: const Text('Save pin')),
            ])),
      ));
}
