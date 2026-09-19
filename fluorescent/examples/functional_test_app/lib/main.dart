import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// ignore: unused_import
import 'package:fluorescent_core/fluorescent_core.dart'; // Just validating import
import 'engine_bridge.dart';
import 'slippy_map_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FluoriteEngineBridge().startEngine();
  runApp(const FunctionalTestApp());
}

class FunctionalTestApp extends StatelessWidget {
  const FunctionalTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluorescent Functional Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;

  final LatLng _center = const LatLng(37.7749, -122.4194); // SF
  final Random _random = Random();

  final Set<TileOverlay> _tileOverlays = {};
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  Timer? _mockLocationTimer;

  // Driver Locations
  LatLng _driver1 = const LatLng(37.7749, -122.4194);
  LatLng _driver2 = const LatLng(37.7800, -122.4200);

  // Geofence (Event Zone)
  final LatLng _eventZone = const LatLng(37.7750, -122.4190);
  final double _eventZoneRadiusDegrees = 0.002;

  bool _isDriver1InZone = false;

  @override
  void initState() {
    super.initState();
    _initTileOverlay();
    _initGeofence();
    _startMockLocationUpdates();
  }

  @override
  void dispose() {
    _mockLocationTimer?.cancel();
    super.dispose();
  }

  void _initTileOverlay() {
    final TileOverlay tileOverlay = TileOverlay(
      tileOverlayId: const TileOverlayId('osm_tiles'),
      tileProvider: SlippyMapTileProvider(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
      zIndex: 1,
    );
    setState(() {
      _tileOverlays.add(tileOverlay);
    });
  }

  void _initGeofence() {
    _circles = {
      Circle(
        circleId: const CircleId('event_zone_1'),
        center: _eventZone,
        radius: 200, // meters roughly
        fillColor: Colors.red.withValues(alpha: 0.3),
        strokeColor: Colors.red,
        strokeWidth: 2,
      ),
    };
  }

  void _startMockLocationUpdates() {
    // Simulate incoming location updates at 2 Hz
    _mockLocationTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      setState(() {
        // Move drivers randomly
        _driver1 = LatLng(
            _driver1.latitude + (_random.nextDouble() - 0.5) * 0.001,
            _driver1.longitude + (_random.nextDouble() - 0.5) * 0.001);

        _driver2 = LatLng(
            _driver2.latitude + (_random.nextDouble() - 0.5) * 0.001,
            _driver2.longitude + (_random.nextDouble() - 0.5) * 0.001);

        _markers = {
          Marker(
            markerId: const MarkerId('driver_1'),
            position: _driver1,
            infoWindow: const InfoWindow(title: 'Driver 1 (Me)'),
          ),
          Marker(
            markerId: const MarkerId('driver_2'),
            position: _driver2,
            infoWindow: const InfoWindow(title: 'Driver 2 (Friend)'),
          ),
        };

        // FFI Bridge Check
        final engine = FluoriteEngineBridge();
        final currentlyInZone = engine.checkGeofenceIntersection(
            _driver1.latitude, _driver1.longitude, _eventZone.latitude, _eventZone.longitude, _eventZoneRadiusDegrees);

        if (currentlyInZone && !_isDriver1InZone) {
          _isDriver1InZone = true;
          debugPrint("Rust Engine (FFI): Driver 1 ENTERED Geofence");
        } else if (!currentlyInZone && _isDriver1InZone) {
          _isDriver1InZone = false;
          debugPrint("Rust Engine (FFI): Driver 1 EXITED Geofence");
        }
      });
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community & Rally Map'),
      ),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(
          target: _center,
          zoom: 14.0,
        ),
        mapType: MapType.none, // Hide default base map to show OSM
        tileOverlays: _tileOverlays,
        markers: _markers,
        circles: _circles,
      ),
    );
  }
}

