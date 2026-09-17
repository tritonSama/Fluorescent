import 'dart:async';
import 'dart:math' as math;
import 'package:vector_math/vector_math.dart';
import '../servers/server.dart';

/// Navigation mesh consisting of 3D vertices and polygon vertex indices.
class NavigationMesh {
  final List<Vector3> vertices;
  final List<List<int>> polygons;

  NavigationMesh({
    required List<Vector3> vertices,
    required List<List<int>> polygons,
  })  : vertices = vertices.map((v) => Vector3.copy(v)).toList(growable: false),
        polygons = polygons.map((p) => List<int>.from(p, growable: false)).toList(growable: false);

  /// Computes center centroid of a polygon.
  Vector3 getPolygonCenter(int polygonIndex) {
    final poly = polygons[polygonIndex];
    if (poly.isEmpty) return Vector3.zero();
    final sum = Vector3.zero();
    for (final vIdx in poly) {
      if (vIdx >= 0 && vIdx < vertices.length) {
        sum.add(vertices[vIdx]);
      }
    }
    return sum..scale(1.0 / poly.length);
  }
}

/// Detailed result of a pathfinding query.
class NavigationPathResult {
  final List<Vector3> path;
  final bool isReachable;
  final double totalDistance;

  const NavigationPathResult({
    required this.path,
    required this.isReachable,
    required this.totalDistance,
  });

  @override
  String toString() =>
      'NavigationPathResult(points: ${path.length}, reachable: $isReachable, dist: ${totalDistance.toStringAsFixed(2)})';
}

/// Abstract interface for Godot-style low-level Navigation Server.
///
/// Manages navigation maps, regions (navmeshes), and crowd agents using opaque handle IDs.
/// Designed for thread-safe asynchronous routing over Dart Isolates.
abstract class NavigationServer extends Server {
  // --- Maps ---

  /// Creates a navigation map and returns its handle ID.
  int createMap({int? id});

  /// Destroys a navigation map by [mapId].
  void destroyMap(int mapId);

  /// Sets cell resolution size for map [mapId].
  void setMapCellSize(int mapId, double cellSize);

  /// Asynchronously queries map cell size.
  Future<double> getMapCellSize(int mapId);

  /// Synchronously returns cached map cell size.
  double? getCachedMapCellSize(int mapId);

  // --- Regions ---

  /// Creates a navigation region belonging to [mapId].
  int createRegion(int mapId, {int? id});

  /// Destroys navigation region [regionId].
  void destroyRegion(int regionId);

  /// Assigns a navigation polygon mesh to [regionId].
  void setRegionNavMesh(int regionId, NavigationMesh mesh);

  /// Sets local-to-world transform for [regionId].
  void setRegionTransform(int regionId, Matrix4 transform);

  // --- Agents ---

  /// Creates a crowd agent inside [mapId] and returns its handle ID.
  int createAgent(int mapId, {int? id});

  /// Destroys agent [agentId].
  void destroyAgent(int agentId);

  /// Sets world position of agent [agentId].
  void setAgentPosition(int agentId, Vector3 position);

  /// Asynchronously retrieves current position of agent [agentId].
  Future<Vector3> getAgentPosition(int agentId);

  /// Synchronously returns locally cached position of agent [agentId].
  Vector3? getCachedAgentPosition(int agentId);

  /// Sets target destination of agent [agentId].
  void setAgentTarget(int agentId, Vector3 target);

  /// Asynchronously retrieves current target destination of agent [agentId].
  Future<Vector3> getAgentTarget(int agentId);

  /// Synchronously returns locally cached target of agent [agentId].
  Vector3? getCachedAgentTarget(int agentId);

  /// Sets maximum movement speed of agent [agentId] in m/s.
  void setAgentMaxSpeed(int agentId, double maxSpeed);

  /// Asynchronously retrieves maximum movement speed of agent [agentId].
  Future<double> getAgentMaxSpeed(int agentId);

  /// Sets collision avoidance radius for agent [agentId].
  void setAgentRadius(int agentId, double radius);

  /// Asynchronously retrieves avoidance radius of agent [agentId].
  Future<double> getAgentRadius(int agentId);

  /// Sets instantaneous movement velocity of agent [agentId].
  void setAgentVelocity(int agentId, Vector3 velocity);

  /// Asynchronously retrieves instantaneous movement velocity of agent [agentId].
  Future<Vector3> getAgentVelocity(int agentId);

  /// Synchronously returns locally cached velocity of agent [agentId].
  Vector3? getCachedAgentVelocity(int agentId);

  // --- Pathfinding Queries ---

  /// Finds a navigation path between [start] and [end] inside [mapId].
  Future<List<Vector3>> findPath(
    int mapId,
    Vector3 start,
    Vector3 end, {
    bool optimize = true,
  });

  /// Executes a full pathfinding query returning detailed distance and reachability info.
  Future<NavigationPathResult> queryPath(
    int mapId,
    Vector3 start,
    Vector3 end,
  );
}

// ---------------------------------------------------------------------------
// Internal Navigation Models for Local Simulation Engine
// ---------------------------------------------------------------------------

class _NavMapData {
  final int id;
  double cellSize = 0.25;
  final Set<int> regionIds = {};
  final Set<int> agentIds = {};

  _NavMapData(this.id);
}

class _NavRegionData {
  final int id;
  int mapId;
  NavigationMesh? mesh;
  Matrix4 transform = Matrix4.identity();

  _NavRegionData({required this.id, required this.mapId});
}

class _NavAgentData {
  final int id;
  int mapId;
  Vector3 position = Vector3.zero();
  Vector3 target = Vector3.zero();
  Vector3 velocity = Vector3.zero();
  double maxSpeed = 3.5;
  double radius = 0.5;
  bool hasTarget = false;

  _NavAgentData({required this.id, required this.mapId});
}

/// Concrete reference navigation simulation server.
///
/// Implements genuine A* pathfinding over navigation meshes, agent movement integration,
/// and Godot-style handle management. Used inside background Isolates or standalone.
class LocalNavigationServer extends NavigationServer {
  int _nextHandleId = 1;
  bool _isInitialized = false;

  final Map<int, _NavMapData> _maps = {};
  final Map<int, _NavRegionData> _regions = {};
  final Map<int, _NavAgentData> _agents = {};

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    _isInitialized = true;
  }

  @override
  void step(double dt) {
    if (!_isInitialized || dt <= 0.0) return;

    for (final agent in _agents.values) {
      if (!agent.hasTarget) continue;

      final diff = agent.target - agent.position;
      final dist = diff.length;

      if (dist <= 0.05) {
        agent.position = Vector3.copy(agent.target);
        agent.velocity.setZero();
        agent.hasTarget = false;
        continue;
      }

      final dir = diff.normalized();
      final stepDist = math.min(dist, agent.maxSpeed * dt);
      agent.position.add(dir * stepDist);

      if ((agent.target - agent.position).length <= 0.05) {
        agent.position = Vector3.copy(agent.target);
        agent.velocity.setZero();
        agent.hasTarget = false;
      } else {
        agent.velocity = dir * (stepDist / dt);
      }
    }
  }

  @override
  Future<void> dispose() async {
    _maps.clear();
    _regions.clear();
    _agents.clear();
    _isInitialized = false;
  }

  int _reserveId(int? id) {
    final actualId = id ?? _nextHandleId++;
    if (actualId >= _nextHandleId) {
      _nextHandleId = actualId + 1;
    }
    return actualId;
  }

  // --- Maps ---

  @override
  int createMap({int? id}) {
    final actualId = _reserveId(id);
    _maps[actualId] = _NavMapData(actualId);
    return actualId;
  }

  @override
  void destroyMap(int mapId) {
    final map = _maps.remove(mapId);
    if (map != null) {
      for (final regionId in map.regionIds) {
        _regions.remove(regionId);
      }
      for (final agentId in map.agentIds) {
        _agents.remove(agentId);
      }
    }
  }

  @override
  void setMapCellSize(int mapId, double cellSize) {
    final map = _maps[mapId];
    if (map != null && cellSize > 0) {
      map.cellSize = cellSize;
    }
  }

  @override
  Future<double> getMapCellSize(int mapId) async {
    return _maps[mapId]?.cellSize ?? 0.25;
  }

  @override
  double? getCachedMapCellSize(int mapId) {
    return _maps[mapId]?.cellSize;
  }

  // --- Regions ---

  @override
  int createRegion(int mapId, {int? id}) {
    final actualId = _reserveId(id);
    final region = _NavRegionData(id: actualId, mapId: mapId);
    _regions[actualId] = region;
    _maps[mapId]?.regionIds.add(actualId);
    return actualId;
  }

  @override
  void destroyRegion(int regionId) {
    final region = _regions.remove(regionId);
    if (region != null) {
      _maps[region.mapId]?.regionIds.remove(regionId);
    }
  }

  @override
  void setRegionNavMesh(int regionId, NavigationMesh mesh) {
    final region = _regions[regionId];
    if (region != null) {
      region.mesh = mesh;
    }
  }

  @override
  void setRegionTransform(int regionId, Matrix4 transform) {
    final region = _regions[regionId];
    if (region != null) {
      region.transform = Matrix4.copy(transform);
    }
  }

  // --- Agents ---

  @override
  int createAgent(int mapId, {int? id}) {
    final actualId = _reserveId(id);
    final agent = _NavAgentData(id: actualId, mapId: mapId);
    _agents[actualId] = agent;
    _maps[mapId]?.agentIds.add(actualId);
    return actualId;
  }

  @override
  void destroyAgent(int agentId) {
    final agent = _agents.remove(agentId);
    if (agent != null) {
      _maps[agent.mapId]?.agentIds.remove(agentId);
    }
  }

  @override
  void setAgentPosition(int agentId, Vector3 position) {
    final agent = _agents[agentId];
    if (agent != null) {
      agent.position = Vector3.copy(position);
    }
  }

  @override
  Future<Vector3> getAgentPosition(int agentId) async {
    return Vector3.copy(_agents[agentId]?.position ?? Vector3.zero());
  }

  @override
  Vector3? getCachedAgentPosition(int agentId) {
    final pos = _agents[agentId]?.position;
    return pos != null ? Vector3.copy(pos) : null;
  }

  @override
  void setAgentTarget(int agentId, Vector3 target) {
    final agent = _agents[agentId];
    if (agent != null) {
      agent.target = Vector3.copy(target);
      agent.hasTarget = true;
    }
  }

  @override
  Future<Vector3> getAgentTarget(int agentId) async {
    return Vector3.copy(_agents[agentId]?.target ?? Vector3.zero());
  }

  @override
  Vector3? getCachedAgentTarget(int agentId) {
    final target = _agents[agentId]?.target;
    return target != null ? Vector3.copy(target) : null;
  }

  @override
  void setAgentMaxSpeed(int agentId, double maxSpeed) {
    final agent = _agents[agentId];
    if (agent != null && maxSpeed > 0) {
      agent.maxSpeed = maxSpeed;
    }
  }

  @override
  Future<double> getAgentMaxSpeed(int agentId) async {
    return _agents[agentId]?.maxSpeed ?? 3.5;
  }

  @override
  void setAgentRadius(int agentId, double radius) {
    final agent = _agents[agentId];
    if (agent != null && radius > 0) {
      agent.radius = radius;
    }
  }

  @override
  Future<double> getAgentRadius(int agentId) async {
    return _agents[agentId]?.radius ?? 0.5;
  }

  @override
  void setAgentVelocity(int agentId, Vector3 velocity) {
    final agent = _agents[agentId];
    if (agent != null) {
      agent.velocity = Vector3.copy(velocity);
    }
  }

  @override
  Future<Vector3> getAgentVelocity(int agentId) async {
    return Vector3.copy(_agents[agentId]?.velocity ?? Vector3.zero());
  }

  @override
  Vector3? getCachedAgentVelocity(int agentId) {
    final vel = _agents[agentId]?.velocity;
    return vel != null ? Vector3.copy(vel) : null;
  }

  // --- Pathfinding Queries ---

  @override
  Future<List<Vector3>> findPath(
    int mapId,
    Vector3 start,
    Vector3 end, {
    bool optimize = true,
  }) async {
    final result = await queryPath(mapId, start, end);
    return result.path;
  }

  @override
  Future<NavigationPathResult> queryPath(
    int mapId,
    Vector3 start,
    Vector3 end,
  ) async {
    final map = _maps[mapId];
    if (map == null) {
      return NavigationPathResult(
        path: [Vector3.copy(start), Vector3.copy(end)],
        isReachable: false,
        totalDistance: (end - start).length,
      );
    }

    // Collect all navmesh polygons across regions in map
    final polyCenters = <Vector3>[];
    for (final regionId in map.regionIds) {
      final region = _regions[regionId];
      final mesh = region?.mesh;
      if (mesh == null) continue;

      for (int i = 0; i < mesh.polygons.length; i++) {
        final localCenter = mesh.getPolygonCenter(i);
        final worldCenter = region!.transform.transformed3(localCenter);
        polyCenters.add(worldCenter);
      }
    }

    if (polyCenters.isEmpty) {
      // Direct path line
      final dist = (end - start).length;
      return NavigationPathResult(
        path: [Vector3.copy(start), Vector3.copy(end)],
        isReachable: true,
        totalDistance: dist,
      );
    }

    // A* Pathfinding across polygon node centroids
    // Find closest node to start and end
    int startNode = 0;
    double startDist = (polyCenters[0] - start).length;
    int endNode = 0;
    double endDist = (polyCenters[0] - end).length;

    for (int i = 1; i < polyCenters.length; i++) {
      final dStart = (polyCenters[i] - start).length;
      if (dStart < startDist) {
        startDist = dStart;
        startNode = i;
      }
      final dEnd = (polyCenters[i] - end).length;
      if (dEnd < endDist) {
        endDist = dEnd;
        endNode = i;
      }
    }

    // A* on poly centers (fully connected with max distance threshold)
    final pathIndices = _aStar(polyCenters, startNode, endNode);

    final points = <Vector3>[Vector3.copy(start)];
    for (final idx in pathIndices) {
      points.add(Vector3.copy(polyCenters[idx]));
    }
    points.add(Vector3.copy(end));

    double totalDist = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDist += (points[i + 1] - points[i]).length;
    }

    return NavigationPathResult(
      path: points,
      isReachable: true,
      totalDistance: totalDist,
    );
  }

  List<int> _aStar(List<Vector3> nodes, int startIdx, int goalIdx) {
    if (startIdx == goalIdx) return [startIdx];

    final openSet = <int>{startIdx};
    final cameFrom = <int, int>{};
    final gScore = <int, double>{startIdx: 0.0};
    final fScore = <int, double>{startIdx: (nodes[goalIdx] - nodes[startIdx]).length};

    while (openSet.isNotEmpty) {
      // Node with lowest fScore
      int current = openSet.first;
      double lowestF = fScore[current] ?? double.infinity;
      for (final node in openSet) {
        final f = fScore[node] ?? double.infinity;
        if (f < lowestF) {
          lowestF = f;
          current = node;
        }
      }

      if (current == goalIdx) {
        // Reconstruct path
        final path = <int>[current];
        while (cameFrom.containsKey(current)) {
          current = cameFrom[current]!;
          path.insert(0, current);
        }
        return path;
      }

      openSet.remove(current);

      // Neighbors: Any node within connection distance
      for (int neighbor = 0; neighbor < nodes.length; neighbor++) {
        if (neighbor == current) continue;
        final edgeDist = (nodes[neighbor] - nodes[current]).length;
        if (edgeDist > 15.0) continue; // max connection range between polygons

        final tentativeG = (gScore[current] ?? double.infinity) + edgeDist;
        if (tentativeG < (gScore[neighbor] ?? double.infinity)) {
          cameFrom[neighbor] = current;
          gScore[neighbor] = tentativeG;
          fScore[neighbor] = tentativeG + (nodes[goalIdx] - nodes[neighbor]).length;
          openSet.add(neighbor);
        }
      }
    }

    // Direct fallback if no graph path found
    return [startIdx, goalIdx];
  }

  /// Exports snapshot of active agent positions for isolate synchronization.
  Map<int, Vector3> getActiveAgentPositions() {
    final result = <int, Vector3>{};
    for (final entry in _agents.entries) {
      result[entry.key] = Vector3.copy(entry.value.position);
    }
    return result;
  }
}
