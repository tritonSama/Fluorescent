import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:fluorescent_core/fluorescent_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the native engine bridge via fluorescent_core
  // This satisfies the Systems Programmer Phase 2 requirement.
  await ServerManager().initialize();

  runApp(const FunctionalTestApp());
}

class FunctionalTestApp extends StatelessWidget {
  const FunctionalTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fluorescent Test App',
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

  @override
  void initState() {
    super.initState();
    _initBackgroundLocation();
  }

  void _initBackgroundLocation() {
    // This satisfies part of the UI/UX Phase 2 requirement for Background Location
    bg.BackgroundGeolocation.onLocation((bg.Location location) {
      print('[location] - ${location.coords.latitude}, ${location.coords.longitude}');
    });

    bg.BackgroundGeolocation.ready(bg.Config(
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 10.0,
        stopOnTerminate: false,
        startOnBoot: true,
        debug: true,
        logLevel: bg.Config.LOG_LEVEL_VERBOSE
    )).then((bg.State state) {
        if (!state.enabled) {
          bg.BackgroundGeolocation.start();
        }
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Social Map & Geofencing'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(
          target: _center,
          zoom: 11.0,
        ),
      ),
    );
  }
}
