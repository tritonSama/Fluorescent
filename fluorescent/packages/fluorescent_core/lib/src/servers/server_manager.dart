import 'dart:async';
import 'dart:isolate';
import 'package:vector_math/vector_math.dart';
import '../physics/physics_server.dart';
import '../navigation/navigation_server.dart';

// ===========================================================================
// Isolate Protocol Messages
// ===========================================================================

/// Base message sent across the isolate boundary.
abstract class ServerMessage {}

/// Handshake message sent from background worker isolate to main isolate.
class _ServerHandshakeAck extends ServerMessage {
  final SendPort workerSendPort;
  _ServerHandshakeAck(this.workerSendPort);
}

/// Command dispatched asynchronously (fire-and-forget) from main to worker.
class _ServerCommandMessage extends ServerMessage {
  final String action;
  final Map<String, dynamic> data;

  _ServerCommandMessage(this.action, [this.data = const {}]);
}

/// Query dispatched with a unique request ID awaiting a response from worker.
class _ServerQueryMessage extends ServerMessage {
  final int requestId;
  final String query;
  final Map<String, dynamic> data;

  _ServerQueryMessage(this.requestId, this.query, [this.data = const {}]);
}

/// Response returned from worker to main for a specific query.
class _ServerResponseMessage extends ServerMessage {
  final int requestId;
  final dynamic result;
  final String? error;

  _ServerResponseMessage({
    required this.requestId,
    this.result,
    this.error,
  });
}

/// Periodic state update broadcast from background isolate tick loop to main isolate.
class ServerTickUpdate extends ServerMessage {
  /// Map of bodyId -> [x, y, z, rx, ry, rz, rw]
  final Map<int, List<double>> bodyTransforms;

  /// Map of agentId -> [x, y, z]
  final Map<int, List<double>> agentPositions;

  ServerTickUpdate({
    required this.bodyTransforms,
    required this.agentPositions,
  });
}

/// Helper conversions for sendable primitives over SendPort.
List<double> _v3ToList(Vector3 v) => [v.x, v.y, v.z];
Vector3 _listToV3(List<dynamic> l) =>
    Vector3((l[0] as num).toDouble(), (l[1] as num).toDouble(), (l[2] as num).toDouble());

List<double> _quatToList(Quaternion q) => [q.x, q.y, q.z, q.w];
Quaternion _listToQuat(List<dynamic> l) => Quaternion(
      (l[0] as num).toDouble(),
      (l[1] as num).toDouble(),
      (l[2] as num).toDouble(),
      (l[3] as num).toDouble(),
    );

// ===========================================================================
// Client Proxy: Physics Server
// ===========================================================================

class _ClientPhysicsProxy extends PhysicsServer {
  final ServerManager _manager;

  final Map<int, Vector3> _gravityCache = {};
  final Map<int, PhysicsTransform> _transformCache = {};
  final Map<int, Vector3> _velocityCache = {};

  _ClientPhysicsProxy(this._manager);

  @override
  bool get isInitialized => _manager.isInitialized;

  @override
  Future<void> initialize() async {
    // Handled by ServerManager
  }

  @override
  void step(double dt) {
    _manager.step(dt);
  }

  @override
  Future<void> dispose() async {
    _gravityCache.clear();
    _transformCache.clear();
    _velocityCache.clear();
  }

  void _applyTickUpdate(Map<int, List<double>> rawTransforms) {
    for (final entry in rawTransforms.entries) {
      final arr = entry.value;
      if (arr.length >= 7) {
        _transformCache[entry.key] = PhysicsTransform(
          position: Vector3(arr[0], arr[1], arr[2]),
          rotation: Quaternion(arr[3], arr[4], arr[5], arr[6]),
        );
      }
    }
  }

  // --- Spaces ---

  @override
  int createSpace({int? id}) {
    final actualId = id ?? _manager.allocateHandleId();
    _manager._sendCommand(_ServerCommandMessage('physics_create_space', {'id': actualId}));
    return actualId;
  }

  @override
  void destroySpace(int spaceId) {
    _gravityCache.remove(spaceId);
    _manager._sendCommand(_ServerCommandMessage('physics_destroy_space', {'id': spaceId}));
  }

  @override
  void setGravity(int spaceId, Vector3 gravity) {
    _gravityCache[spaceId] = Vector3.copy(gravity);
    _manager._sendCommand(_ServerCommandMessage(
      'physics_set_gravity',
      {'spaceId': spaceId, 'gravity': _v3ToList(gravity)},
    ));
  }

  @override
  Future<Vector3> getGravity(int spaceId) async {
    final res = await _manager._sendQuery<List<dynamic>>(
      'physics_get_gravity',
      {'spaceId': spaceId},
    );
    final vec = _listToV3(res);
    _gravityCache[spaceId] = Vector3.copy(vec);
    return vec;
  }

  @override
  Vector3? getCachedGravity(int spaceId) {
    final g = _gravityCache[spaceId];
    return g != null ? Vector3.copy(g) : null;
  }

  // --- Shapes ---

  @override
  int createBoxShape(Vector3 halfExtents, {int? id}) {
    final actualId = id ?? _manager.allocateHandleId();
    _manager._sendCommand(_ServerCommandMessage(
      'physics_create_box_shape',
      {'id': actualId, 'halfExtents': _v3ToList(halfExtents)},
    ));
    return actualId;
  }

  @override
  int createSphereShape(double radius, {int? id}) {
    final actualId = id ?? _manager.allocateHandleId();
    _manager._sendCommand(_ServerCommandMessage(
      'physics_create_sphere_shape',
      {'id': actualId, 'radius': radius},
    ));
    return actualId;
  }

  @override
  int createCapsuleShape(double radius, double height, {int? id}) {
    final actualId = id ?? _manager.allocateHandleId();
    _manager._sendCommand(_ServerCommandMessage(
      'physics_create_capsule_shape',
      {'id': actualId, 'radius': radius, 'height': height},
    ));
    return actualId;
  }

  @override
  void destroyShape(int shapeId) {
    _manager._sendCommand(_ServerCommandMessage('physics_destroy_shape', {'id': shapeId}));
  }

  // --- Bodies ---

  @override
  int createBody({
    int? id,
    PhysicsBodyType type = PhysicsBodyType.rigid,
    int? spaceId,
  }) {
    final actualId = id ?? _manager.allocateHandleId();
    _transformCache[actualId] = PhysicsTransform.identity();
    _manager._sendCommand(_ServerCommandMessage(
      'physics_create_body',
      {'id': actualId, 'type': type.index, 'spaceId': spaceId},
    ));
    return actualId;
  }

  @override
  void destroyBody(int bodyId) {
    _transformCache.remove(bodyId);
    _velocityCache.remove(bodyId);
    _manager._sendCommand(_ServerCommandMessage('physics_destroy_body', {'id': bodyId}));
  }

  @override
  void setBodySpace(int bodyId, int spaceId) {
    _manager._sendCommand(_ServerCommandMessage(
      'physics_set_body_space',
      {'bodyId': bodyId, 'spaceId': spaceId},
    ));
  }

  @override
  void addShapeToBody(
    int bodyId,
    int shapeId, {
    Vector3? localPosition,
    Quaternion? localRotation,
  }) {
    _manager._sendCommand(_ServerCommandMessage(
      'physics_add_shape_to_body',
      {
        'bodyId': bodyId,
        'shapeId': shapeId,
        'localPosition': localPosition != null ? _v3ToList(localPosition) : null,
        'localRotation': localRotation != null ? _quatToList(localRotation) : null,
      },
    ));
  }

  @override
  void setBodyTransform(int bodyId, Vector3 position, Quaternion rotation) {
    _transformCache[bodyId] = PhysicsTransform(position: position, rotation: rotation);
    _manager._sendCommand(_ServerCommandMessage(
      'physics_set_body_transform',
      {
        'bodyId': bodyId,
        'position': _v3ToList(position),
        'rotation': _quatToList(rotation),
      },
    ));
  }

  @override
  Future<PhysicsTransform> getBodyTransform(int bodyId) async {
    final res = await _manager._sendQuery<Map<dynamic, dynamic>>(
      'physics_get_body_transform',
      {'bodyId': bodyId},
    );
    final pos = _listToV3(res['position'] as List<dynamic>);
    final rot = _listToQuat(res['rotation'] as List<dynamic>);
    final transform = PhysicsTransform(position: pos, rotation: rot);
    _transformCache[bodyId] = transform;
    return transform;
  }

  @override
  PhysicsTransform? getCachedTransform(int bodyId) {
    return _transformCache[bodyId];
  }

  @override
  void setBodyLinearVelocity(int bodyId, Vector3 velocity) {
    _velocityCache[bodyId] = Vector3.copy(velocity);
    _manager._sendCommand(_ServerCommandMessage(
      'physics_set_body_velocity',
      {'bodyId': bodyId, 'velocity': _v3ToList(velocity)},
    ));
  }

  @override
  Future<Vector3> getBodyLinearVelocity(int bodyId) async {
    final res = await _manager._sendQuery<List<dynamic>>(
      'physics_get_body_velocity',
      {'bodyId': bodyId},
    );
    final vel = _listToV3(res);
    _velocityCache[bodyId] = Vector3.copy(vel);
    return vel;
  }

  @override
  Vector3? getCachedLinearVelocity(int bodyId) {
    final v = _velocityCache[bodyId];
    return v != null ? Vector3.copy(v) : null;
  }

  @override
  void setBodyMass(int bodyId, double mass) {
    _manager._sendCommand(_ServerCommandMessage(
      'physics_set_body_mass',
      {'bodyId': bodyId, 'mass': mass},
    ));
  }

  @override
  void applyForce(int bodyId, Vector3 force) {
    _manager._sendCommand(_ServerCommandMessage(
      'physics_apply_force',
      {'bodyId': bodyId, 'force': _v3ToList(force)},
    ));
  }

  @override
  void applyImpulse(int bodyId, Vector3 impulse) {
    _manager._sendCommand(_ServerCommandMessage(
      'physics_apply_impulse',
      {'bodyId': bodyId, 'impulse': _v3ToList(impulse)},
    ));
  }

  // --- Queries ---

  @override
  Future<PhysicsRaycastHit?> raycast(int spaceId, Vector3 from, Vector3 to) async {
    final res = await _manager._sendQuery<Map<dynamic, dynamic>?>(
      'physics_raycast',
      {
        'spaceId': spaceId,
        'from': _v3ToList(from),
        'to': _v3ToList(to),
      },
    );
    if (res == null) return null;
    return PhysicsRaycastHit(
      bodyId: res['bodyId'] as int,
      position: _listToV3(res['position'] as List<dynamic>),
      normal: _listToV3(res['normal'] as List<dynamic>),
      distance: (res['distance'] as num).toDouble(),
    );
  }
}

// ===========================================================================
// Client Proxy: Navigation Server
// ===========================================================================

class _ClientNavigationProxy extends NavigationServer {
  final ServerManager _manager;

  final Map<int, double> _cellSizeCache = {};
  final Map<int, Vector3> _agentPosCache = {};
  final Map<int, Vector3> _agentTargetCache = {};
  final Map<int, Vector3> _agentVelocityCache = {};

  _ClientNavigationProxy(this._manager);

  @override
  bool get isInitialized => _manager.isInitialized;

  @override
  Future<void> initialize() async {}

  @override
  void step(double dt) {
    _manager.step(dt);
  }

  @override
  Future<void> dispose() async {
    _cellSizeCache.clear();
    _agentPosCache.clear();
    _agentTargetCache.clear();
    _agentVelocityCache.clear();
  }

  void _applyTickUpdate(Map<int, List<double>> rawPositions) {
    for (final entry in rawPositions.entries) {
      final arr = entry.value;
      if (arr.length >= 3) {
        _agentPosCache[entry.key] = Vector3(arr[0], arr[1], arr[2]);
      }
    }
  }

  // --- Maps ---

  @override
  int createMap({int? id}) {
    final actualId = id ?? _manager.allocateHandleId();
    _manager._sendCommand(_ServerCommandMessage('nav_create_map', {'id': actualId}));
    return actualId;
  }

  @override
  void destroyMap(int mapId) {
    _cellSizeCache.remove(mapId);
    _manager._sendCommand(_ServerCommandMessage('nav_destroy_map', {'id': mapId}));
  }

  @override
  void setMapCellSize(int mapId, double cellSize) {
    _cellSizeCache[mapId] = cellSize;
    _manager._sendCommand(_ServerCommandMessage(
      'nav_set_map_cell_size',
      {'mapId': mapId, 'cellSize': cellSize},
    ));
  }

  @override
  Future<double> getMapCellSize(int mapId) async {
    final res = await _manager._sendQuery<num>(
      'nav_get_map_cell_size',
      {'mapId': mapId},
    );
    final val = res.toDouble();
    _cellSizeCache[mapId] = val;
    return val;
  }

  @override
  double? getCachedMapCellSize(int mapId) => _cellSizeCache[mapId];

  // --- Regions ---

  @override
  int createRegion(int mapId, {int? id}) {
    final actualId = id ?? _manager.allocateHandleId();
    _manager._sendCommand(_ServerCommandMessage(
      'nav_create_region',
      {'id': actualId, 'mapId': mapId},
    ));
    return actualId;
  }

  @override
  void destroyRegion(int regionId) {
    _manager._sendCommand(_ServerCommandMessage('nav_destroy_region', {'id': regionId}));
  }

  @override
  void setRegionNavMesh(int regionId, NavigationMesh mesh) {
    final serializedVerts = mesh.vertices.map(_v3ToList).toList();
    _manager._sendCommand(_ServerCommandMessage(
      'nav_set_region_mesh',
      {
        'regionId': regionId,
        'vertices': serializedVerts,
        'polygons': mesh.polygons,
      },
    ));
  }

  @override
  void setRegionTransform(int regionId, Matrix4 transform) {
    _manager._sendCommand(_ServerCommandMessage(
      'nav_set_region_transform',
      {
        'regionId': regionId,
        'transform': transform.storage.toList(),
      },
    ));
  }

  // --- Agents ---

  @override
  int createAgent(int mapId, {int? id}) {
    final actualId = id ?? _manager.allocateHandleId();
    _agentPosCache[actualId] = Vector3.zero();
    _manager._sendCommand(_ServerCommandMessage(
      'nav_create_agent',
      {'id': actualId, 'mapId': mapId},
    ));
    return actualId;
  }

  @override
  void destroyAgent(int agentId) {
    _agentPosCache.remove(agentId);
    _agentTargetCache.remove(agentId);
    _agentVelocityCache.remove(agentId);
    _manager._sendCommand(_ServerCommandMessage('nav_destroy_agent', {'id': agentId}));
  }

  @override
  void setAgentPosition(int agentId, Vector3 position) {
    _agentPosCache[agentId] = Vector3.copy(position);
    _manager._sendCommand(_ServerCommandMessage(
      'nav_set_agent_position',
      {'agentId': agentId, 'position': _v3ToList(position)},
    ));
  }

  @override
  Future<Vector3> getAgentPosition(int agentId) async {
    final res = await _manager._sendQuery<List<dynamic>>(
      'nav_get_agent_position',
      {'agentId': agentId},
    );
    final pos = _listToV3(res);
    _agentPosCache[agentId] = Vector3.copy(pos);
    return pos;
  }

  @override
  Vector3? getCachedAgentPosition(int agentId) {
    final p = _agentPosCache[agentId];
    return p != null ? Vector3.copy(p) : null;
  }

  @override
  void setAgentTarget(int agentId, Vector3 target) {
    _agentTargetCache[agentId] = Vector3.copy(target);
    _manager._sendCommand(_ServerCommandMessage(
      'nav_set_agent_target',
      {'agentId': agentId, 'target': _v3ToList(target)},
    ));
  }

  @override
  Future<Vector3> getAgentTarget(int agentId) async {
    final res = await _manager._sendQuery<List<dynamic>>(
      'nav_get_agent_target',
      {'agentId': agentId},
    );
    final target = _listToV3(res);
    _agentTargetCache[agentId] = Vector3.copy(target);
    return target;
  }

  @override
  Vector3? getCachedAgentTarget(int agentId) {
    final t = _agentTargetCache[agentId];
    return t != null ? Vector3.copy(t) : null;
  }

  @override
  void setAgentMaxSpeed(int agentId, double maxSpeed) {
    _manager._sendCommand(_ServerCommandMessage(
      'nav_set_agent_max_speed',
      {'agentId': agentId, 'maxSpeed': maxSpeed},
    ));
  }

  @override
  Future<double> getAgentMaxSpeed(int agentId) async {
    final res = await _manager._sendQuery<num>(
      'nav_get_agent_max_speed',
      {'agentId': agentId},
    );
    return res.toDouble();
  }

  @override
  void setAgentRadius(int agentId, double radius) {
    _manager._sendCommand(_ServerCommandMessage(
      'nav_set_agent_radius',
      {'agentId': agentId, 'radius': radius},
    ));
  }

  @override
  Future<double> getAgentRadius(int agentId) async {
    final res = await _manager._sendQuery<num>(
      'nav_get_agent_radius',
      {'agentId': agentId},
    );
    return res.toDouble();
  }

  @override
  void setAgentVelocity(int agentId, Vector3 velocity) {
    _agentVelocityCache[agentId] = Vector3.copy(velocity);
    _manager._sendCommand(_ServerCommandMessage(
      'nav_set_agent_velocity',
      {'agentId': agentId, 'velocity': _v3ToList(velocity)},
    ));
  }

  @override
  Future<Vector3> getAgentVelocity(int agentId) async {
    final res = await _manager._sendQuery<List<dynamic>>(
      'nav_get_agent_velocity',
      {'agentId': agentId},
    );
    final vel = _listToV3(res);
    _agentVelocityCache[agentId] = Vector3.copy(vel);
    return vel;
  }

  @override
  Vector3? getCachedAgentVelocity(int agentId) {
    final v = _agentVelocityCache[agentId];
    return v != null ? Vector3.copy(v) : null;
  }

  // --- Pathfinding Queries ---

  @override
  Future<List<Vector3>> findPath(
    int mapId,
    Vector3 start,
    Vector3 end, {
    bool optimize = true,
  }) async {
    final res = await _manager._sendQuery<List<dynamic>>(
      'nav_find_path',
      {
        'mapId': mapId,
        'start': _v3ToList(start),
        'end': _v3ToList(end),
        'optimize': optimize,
      },
    );
    return res.map((item) => _listToV3(item as List<dynamic>)).toList();
  }

  @override
  Future<NavigationPathResult> queryPath(
    int mapId,
    Vector3 start,
    Vector3 end,
  ) async {
    final res = await _manager._sendQuery<Map<dynamic, dynamic>>(
      'nav_query_path',
      {
        'mapId': mapId,
        'start': _v3ToList(start),
        'end': _v3ToList(end),
      },
    );
    final rawPath = res['path'] as List<dynamic>;
    final path = rawPath.map((item) => _listToV3(item as List<dynamic>)).toList();
    return NavigationPathResult(
      path: path,
      isReachable: res['isReachable'] as bool,
      totalDistance: (res['totalDistance'] as num).toDouble(),
    );
  }
}

// ===========================================================================
// Server Manager
// ===========================================================================

/// Orchestrates physics and navigation server simulation concurrently on a background Isolate.
///
/// Dispatches commands asynchronously via SendPort without blocking the main event loop,
/// manages request-response queries via unique request IDs and Completers, and maintains
/// a background simulation tick loop.
class ServerManager {
  Isolate? _isolate;
  ReceivePort? _mainReceivePort;
  SendPort? _workerSendPort;
  StreamSubscription<dynamic>? _portSubscription;

  int _nextHandleId = 1;
  int _nextRequestId = 1;
  final Map<int, Completer<dynamic>> _pendingQueries = {};
  final StreamController<ServerTickUpdate> _tickUpdateController =
      StreamController<ServerTickUpdate>.broadcast();

  late final _ClientPhysicsProxy _physicsProxy;
  late final _ClientNavigationProxy _navigationProxy;

  bool _isInitialized = false;
  bool _isDisposed = false;

  ServerManager() {
    _physicsProxy = _ClientPhysicsProxy(this);
    _navigationProxy = _ClientNavigationProxy(this);
  }

  /// Allocates a globally unique handle ID for resources managed across isolates.
  int allocateHandleId() => _nextHandleId++;

  /// The client proxy for physics simulation running on the background isolate.
  PhysicsServer get physics => _physicsProxy;

  /// The client proxy for navigation queries running on the background isolate.
  NavigationServer get navigation => _navigationProxy;

  /// Stream of periodic simulation tick updates emitted from the background isolate.
  Stream<ServerTickUpdate> get onTickUpdate => _tickUpdateController.stream;

  /// Whether the ServerManager and background isolate are active and ready.
  bool get isInitialized => _isInitialized;

  /// Whether the ServerManager has been disposed.
  bool get isDisposed => _isDisposed;

  /// Number of in-flight queries awaiting response from background isolate.
  int get pendingQueryCount => _pendingQueries.length;

  /// Initializes the ServerManager by spawning the background worker Isolate,
  /// executing the bidirectional port handshake, and optionally launching the simulation tick loop.
  Future<void> initialize({
    double tickRateHz = 60.0,
    bool startTickLoop = true,
  }) async {
    if (_isInitialized) return;
    if (_isDisposed) {
      throw StateError('Cannot initialize a disposed ServerManager.');
    }

    _mainReceivePort = ReceivePort('ServerManager_MainReceivePort');
    final handshakeCompleter = Completer<SendPort>();

    _portSubscription = _mainReceivePort!.listen((message) {
      if (message is _ServerHandshakeAck) {
        if (!handshakeCompleter.isCompleted) {
          handshakeCompleter.complete(message.workerSendPort);
        }
      } else if (message is _ServerResponseMessage) {
        final completer = _pendingQueries.remove(message.requestId);
        if (completer != null && !completer.isCompleted) {
          if (message.error != null) {
            completer.completeError(Exception(message.error));
          } else {
            completer.complete(message.result);
          }
        }
      } else if (message is ServerTickUpdate) {
        _physicsProxy._applyTickUpdate(message.bodyTransforms);
        _navigationProxy._applyTickUpdate(message.agentPositions);
        if (!_tickUpdateController.isClosed) {
          _tickUpdateController.add(message);
        }
      }
    });

    // Spawn background isolate
    _isolate = await Isolate.spawn(
      _serverWorkerEntryPoint,
      _mainReceivePort!.sendPort,
      debugName: 'Fluorescent_ServerWorkerIsolate',
    );

    // Await handshake
    _workerSendPort = await handshakeCompleter.future;
    _isInitialized = true;

    // Configure background tick loop
    if (startTickLoop) {
      _sendCommand(_ServerCommandMessage(
        'config_tick_loop',
        {'enabled': true, 'tickRateHz': tickRateHz},
      ));
    }
  }

  /// Dispatches a manual simulation step of [dt] seconds to the background isolate.
  void step(double dt) {
    if (!_isInitialized || _isDisposed) return;
    _sendCommand(_ServerCommandMessage('step_simulation', {'dt': dt}));
  }

  /// Asynchronously steps simulation by [dt] seconds and awaits its completion on the background isolate.
  Future<void> stepAsync(double dt) async {
    if (!_isInitialized || _isDisposed) return;
    await _sendQuery<void>('step_simulation_sync', {'dt': dt});
  }

  /// Sends a fire-and-forget command to the background isolate.
  void _sendCommand(_ServerCommandMessage message) {
    if (_isDisposed || _workerSendPort == null) return;
    _workerSendPort!.send(message);
  }

  /// Sends a query to the background isolate and returns a Future awaiting the response.
  Future<T> _sendQuery<T>(String query, [Map<String, dynamic> data = const {}]) {
    if (_isDisposed || _workerSendPort == null) {
      return Future.error(StateError('ServerManager is not active.'));
    }

    final requestId = _nextRequestId++;
    final completer = Completer<T>();
    _pendingQueries[requestId] = completer;

    _workerSendPort!.send(_ServerQueryMessage(requestId, query, data));
    return completer.future;
  }

  /// Cleanly shuts down the background Isolate and frees all resources.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _isInitialized = false;

    // Request worker isolate shutdown
    if (_workerSendPort != null) {
      try {
        final shutdownCompleter = Completer<void>();
        final shutdownReqId = _nextRequestId++;
        _pendingQueries[shutdownReqId] = shutdownCompleter;
        _workerSendPort!.send(_ServerQueryMessage(shutdownReqId, 'shutdown'));

        await shutdownCompleter.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      } catch (_) {
        // Ignore shutdown errors during teardown
      }
    }

    // Cancel in-flight queries
    for (final completer in _pendingQueries.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('ServerManager disposed.'));
      }
    }
    _pendingQueries.clear();

    await _portSubscription?.cancel();
    _portSubscription = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerSendPort = null;

    await _physicsProxy.dispose();
    await _navigationProxy.dispose();
    await _tickUpdateController.close();
  }
}

// ===========================================================================
// Background Worker Isolate Entrypoint
// ===========================================================================

void _serverWorkerEntryPoint(SendPort mainSendPort) async {
  final workerReceivePort = ReceivePort('ServerWorker_ReceivePort');

  // Send handshake back to main isolate
  mainSendPort.send(_ServerHandshakeAck(workerReceivePort.sendPort));

  // Initialize concrete servers inside worker isolate
  final physics = LocalPhysicsServer();
  await physics.initialize();

  final navigation = LocalNavigationServer();
  await navigation.initialize();

  Timer? tickTimer;

  void updateTickLoop(bool enabled, double tickRateHz) {
    tickTimer?.cancel();
    tickTimer = null;
    if (enabled && tickRateHz > 0) {
      final intervalUs = (1000000.0 / tickRateHz).round();
      final dt = 1.0 / tickRateHz;
      tickTimer = Timer.periodic(Duration(microseconds: intervalUs), (_) {
        physics.step(dt);
        navigation.step(dt);

        // Emit snapshot to main isolate
        final bodyTransforms = <int, List<double>>{};
        for (final entry in physics.getActiveBodyTransforms().entries) {
          final t = entry.value;
          bodyTransforms[entry.key] = [
            t.position.x,
            t.position.y,
            t.position.z,
            t.rotation.x,
            t.rotation.y,
            t.rotation.z,
            t.rotation.w,
          ];
        }

        final agentPositions = <int, List<double>>{};
        for (final entry in navigation.getActiveAgentPositions().entries) {
          final p = entry.value;
          agentPositions[entry.key] = [p.x, p.y, p.z];
        }

        mainSendPort.send(ServerTickUpdate(
          bodyTransforms: bodyTransforms,
          agentPositions: agentPositions,
        ));
      });
    }
  }

  await for (final message in workerReceivePort) {
    if (message is _ServerCommandMessage) {
      try {
        final d = message.data;
        switch (message.action) {
          case 'config_tick_loop':
            updateTickLoop(
              d['enabled'] as bool? ?? false,
              (d['tickRateHz'] as num?)?.toDouble() ?? 60.0,
            );
            break;

          case 'step_simulation':
            final dt = (d['dt'] as num).toDouble();
            physics.step(dt);
            navigation.step(dt);
            break;

          // --- Physics Commands ---
          case 'physics_create_space':
            physics.createSpace(id: d['id'] as int);
            break;

          case 'physics_destroy_space':
            physics.destroySpace(d['id'] as int);
            break;

          case 'physics_set_gravity':
            physics.setGravity(d['spaceId'] as int, _listToV3(d['gravity'] as List<dynamic>));
            break;

          case 'physics_create_box_shape':
            final id = d['id'] as int;
            final ext = _listToV3(d['halfExtents'] as List<dynamic>);
            physics.createBoxShape(ext, id: id);
            break;

          case 'physics_create_sphere_shape':
            final id = d['id'] as int;
            final r = (d['radius'] as num).toDouble();
            physics.createSphereShape(r, id: id);
            break;

          case 'physics_create_capsule_shape':
            final id = d['id'] as int;
            final r = (d['radius'] as num).toDouble();
            final h = (d['height'] as num).toDouble();
            physics.createCapsuleShape(r, h, id: id);
            break;

          case 'physics_destroy_shape':
            physics.destroyShape(d['id'] as int);
            break;

          case 'physics_create_body':
            final id = d['id'] as int;
            final typeIdx = d['type'] as int;
            final type = PhysicsBodyType.values[typeIdx];
            final spaceId = d['spaceId'] as int?;
            physics.createBody(id: id, type: type, spaceId: spaceId);
            break;

          case 'physics_destroy_body':
            physics.destroyBody(d['id'] as int);
            break;

          case 'physics_set_body_space':
            physics.setBodySpace(d['bodyId'] as int, d['spaceId'] as int);
            break;

          case 'physics_add_shape_to_body':
            final bodyId = d['bodyId'] as int;
            final shapeId = d['shapeId'] as int;
            final localPos =
                d['localPosition'] != null ? _listToV3(d['localPosition'] as List<dynamic>) : null;
            final localRot =
                d['localRotation'] != null ? _listToQuat(d['localRotation'] as List<dynamic>) : null;
            physics.addShapeToBody(
              bodyId,
              shapeId,
              localPosition: localPos,
              localRotation: localRot,
            );
            break;

          case 'physics_set_body_transform':
            final bodyId = d['bodyId'] as int;
            final pos = _listToV3(d['position'] as List<dynamic>);
            final rot = _listToQuat(d['rotation'] as List<dynamic>);
            physics.setBodyTransform(bodyId, pos, rot);
            break;

          case 'physics_set_body_velocity':
            physics.setBodyLinearVelocity(
              d['bodyId'] as int,
              _listToV3(d['velocity'] as List<dynamic>),
            );
            break;

          case 'physics_set_body_mass':
            physics.setBodyMass(d['bodyId'] as int, (d['mass'] as num).toDouble());
            break;

          case 'physics_apply_force':
            physics.applyForce(
              d['bodyId'] as int,
              _listToV3(d['force'] as List<dynamic>),
            );
            break;

          case 'physics_apply_impulse':
            physics.applyImpulse(
              d['bodyId'] as int,
              _listToV3(d['impulse'] as List<dynamic>),
            );
            break;

          // --- Navigation Commands ---
          case 'nav_create_map':
            navigation.createMap(id: d['id'] as int);
            break;

          case 'nav_destroy_map':
            navigation.destroyMap(d['id'] as int);
            break;

          case 'nav_set_map_cell_size':
            navigation.setMapCellSize(d['mapId'] as int, (d['cellSize'] as num).toDouble());
            break;

          case 'nav_create_region':
            navigation.createRegion(d['mapId'] as int, id: d['id'] as int);
            break;

          case 'nav_destroy_region':
            navigation.destroyRegion(d['id'] as int);
            break;

          case 'nav_set_region_mesh':
            final regId = d['regionId'] as int;
            final rawVerts = d['vertices'] as List<dynamic>;
            final rawPolys = d['polygons'] as List<dynamic>;
            final verts = rawVerts.map((v) => _listToV3(v as List<dynamic>)).toList();
            final polys = rawPolys.map((p) => List<int>.from(p as List<dynamic>)).toList();
            navigation.setRegionNavMesh(
              regId,
              NavigationMesh(vertices: verts, polygons: polys),
            );
            break;

          case 'nav_set_region_transform':
            final regId = d['regionId'] as int;
            final rawFloats = (d['transform'] as List<dynamic>).map((e) => (e as num).toDouble()).toList();
            final mat = Matrix4.fromList(rawFloats);
            navigation.setRegionTransform(regId, mat);
            break;

          case 'nav_create_agent':
            navigation.createAgent(d['mapId'] as int, id: d['id'] as int);
            break;

          case 'nav_destroy_agent':
            navigation.destroyAgent(d['id'] as int);
            break;

          case 'nav_set_agent_position':
            navigation.setAgentPosition(
              d['agentId'] as int,
              _listToV3(d['position'] as List<dynamic>),
            );
            break;

          case 'nav_set_agent_target':
            navigation.setAgentTarget(
              d['agentId'] as int,
              _listToV3(d['target'] as List<dynamic>),
            );
            break;

          case 'nav_set_agent_max_speed':
            navigation.setAgentMaxSpeed(
              d['agentId'] as int,
              (d['maxSpeed'] as num).toDouble(),
            );
            break;

          case 'nav_set_agent_radius':
            navigation.setAgentRadius(
              d['agentId'] as int,
              (d['radius'] as num).toDouble(),
            );
            break;

          case 'nav_set_agent_velocity':
            navigation.setAgentVelocity(
              d['agentId'] as int,
              _listToV3(d['velocity'] as List<dynamic>),
            );
            break;
        }
      } catch (e) {
        // Log or handle command execution error in worker
      }
    } else if (message is _ServerQueryMessage) {
      final reqId = message.requestId;
      final d = message.data;

      try {
        switch (message.query) {
          case 'shutdown':
            tickTimer?.cancel();
            await physics.dispose();
            await navigation.dispose();
            mainSendPort.send(_ServerResponseMessage(requestId: reqId, result: true));
            workerReceivePort.close();
            return;

          case 'step_simulation_sync':
            final dt = (d['dt'] as num).toDouble();
            physics.step(dt);
            navigation.step(dt);
            mainSendPort.send(_ServerResponseMessage(requestId: reqId, result: null));
            break;

          case 'physics_get_gravity':
            final g = await physics.getGravity(d['spaceId'] as int);
            mainSendPort.send(_ServerResponseMessage(requestId: reqId, result: _v3ToList(g)));
            break;

          case 'physics_get_body_transform':
            final t = await physics.getBodyTransform(d['bodyId'] as int);
            mainSendPort.send(_ServerResponseMessage(
              requestId: reqId,
              result: {
                'position': _v3ToList(t.position),
                'rotation': _quatToList(t.rotation),
              },
            ));
            break;

          case 'physics_get_body_velocity':
            final v = await physics.getBodyLinearVelocity(d['bodyId'] as int);
            mainSendPort.send(_ServerResponseMessage(requestId: reqId, result: _v3ToList(v)));
            break;

          case 'physics_raycast':
            final hit = await physics.raycast(
              d['spaceId'] as int,
              _listToV3(d['from'] as List<dynamic>),
              _listToV3(d['to'] as List<dynamic>),
            );
            if (hit != null) {
              mainSendPort.send(_ServerResponseMessage(
                requestId: reqId,
                result: {
                  'bodyId': hit.bodyId,
                  'position': _v3ToList(hit.position),
                  'normal': _v3ToList(hit.normal),
                  'distance': hit.distance,
                },
              ));
            } else {
              mainSendPort.send(_ServerResponseMessage(requestId: reqId, result: null));
            }
            break;

          case 'nav_get_map_cell_size':
            final s = await navigation.getMapCellSize(d['mapId'] as int);
            mainSendPort.send(_ServerResponseMessage(requestId: reqId, result: s));
            break;

          case 'nav_get_agent_position':
            final p = await navigation.getAgentPosition(d['agentId'] as int);
            mainSendPort.send(_ServerResponseMessage(requestId: reqId, result: _v3ToList(p)));
            break;

          case 'nav_get_agent_target':
            final t = await navigation.getAgentTarget(d['agentId'] as int);
            mainSendPort.send(_ServerResponseMessage(requestId: reqId, result: _v3ToList(t)));
            break;

          case 'nav_get_agent_max_speed':
            final s = await navigation.getAgentMaxSpeed(d['agentId'] as int);
            mainSendPort.send(_ServerResponseMessage(requestId: reqId, result: s));
            break;

          case 'nav_get_agent_radius':
            final r = await navigation.getAgentRadius(d['agentId'] as int);
            mainSendPort.send(_ServerResponseMessage(requestId: reqId, result: r));
            break;

          case 'nav_get_agent_velocity':
            final v = await navigation.getAgentVelocity(d['agentId'] as int);
            mainSendPort.send(_ServerResponseMessage(requestId: reqId, result: _v3ToList(v)));
            break;

          case 'nav_find_path':
            final path = await navigation.findPath(
              d['mapId'] as int,
              _listToV3(d['start'] as List<dynamic>),
              _listToV3(d['end'] as List<dynamic>),
              optimize: d['optimize'] as bool? ?? true,
            );
            mainSendPort.send(_ServerResponseMessage(
              requestId: reqId,
              result: path.map(_v3ToList).toList(),
            ));
            break;

          case 'nav_query_path':
            final res = await navigation.queryPath(
              d['mapId'] as int,
              _listToV3(d['start'] as List<dynamic>),
              _listToV3(d['end'] as List<dynamic>),
            );
            mainSendPort.send(_ServerResponseMessage(
              requestId: reqId,
              result: {
                'path': res.path.map(_v3ToList).toList(),
                'isReachable': res.isReachable,
                'totalDistance': res.totalDistance,
              },
            ));
            break;

          default:
            mainSendPort.send(_ServerResponseMessage(
              requestId: reqId,
              error: 'Unknown server query: ${message.query}',
            ));
            break;
        }
      } catch (e, st) {
        mainSendPort.send(_ServerResponseMessage(
          requestId: reqId,
          error: 'Error executing query ${message.query}: $e\n$st',
        ));
      }
    }
  }
}
