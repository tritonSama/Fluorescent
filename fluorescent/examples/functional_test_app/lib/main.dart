import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// ignore: unused_import
import 'package:fluorescent_core/fluorescent_core.dart'; // Just validating import
import 'engine_bridge.dart';

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
  StreamSubscription<Position>? _positionStreamSubscription;

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
    _initLocationServices();
    _startMockLocationUpdates();
  }

  @override
  void dispose() {
    _mockLocationTimer?.cancel();
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initLocationServices() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permissions are permanently denied.');
      return;
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position? position) {
        if (position != null) {
          setState(() {
            _driver1 = LatLng(position.latitude, position.longitude);
            _updateMarkersAndGeofence();
          });
        }
      },
    );
  }

  void _initTileOverlay() {
    final TileOverlay tileOverlay = TileOverlay(
      tileOverlayId: const TileOverlayId('osm_tiles'),
      tileProvider: _OSMTileProvider(),
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
        // Only move driver 2 randomly, driver 1 is actual location
        _driver2 = LatLng(
            _driver2.latitude + (_random.nextDouble() - 0.5) * 0.001,
            _driver2.longitude + (_random.nextDouble() - 0.5) * 0.001);

        _updateMarkersAndGeofence();
      });
    });
  }

  void _updateMarkersAndGeofence() {
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
      body: Stack(
        children: [
          GoogleMap(
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildSocialFeedOverlay(),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialFeedOverlay() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Social Feed',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Icon(Icons.feed, color: Colors.deepPurple.shade700),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              children: [
                _buildFeedItem(
                  'Driver 2 (Friend)',
                  'Just joined the rally event!',
                  '2 mins ago',
                ),
                _buildFeedItem(
                  'System',
                  _isDriver1InZone
                    ? 'You have entered the Event Zone.'
                    : 'You have exited the Event Zone.',
                  'Just now',
                  isAlert: true,
                ),
                _buildFeedItem(
                  'Rally Club',
                  'New speed trap reported ahead.',
                  '5 mins ago',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedItem(String title, String subtitle, String time, {bool isAlert = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: isAlert ? Colors.red.shade100 : Colors.deepPurple.shade100,
            child: Icon(
              isAlert ? Icons.warning : Icons.person,
              color: isAlert ? Colors.red : Colors.deepPurple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(time, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OSMTileProvider implements TileProvider {
  @override
  Future<Tile> getTile(int x, int y, int? zoom) async {
    // Stub OSM Tile Provider
    return Tile(0, 0, null);
  }
}
