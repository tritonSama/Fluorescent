import 'dart:async';
import 'dart:math' as math;
import 'package:vector_math/vector_math.dart';
import '../servers/server.dart';

/// Type of physics body simulating Godot's BodyMode.
enum PhysicsBodyType {
  /// Immovable body unaffected by forces or collisions.
  staticBody,

  /// User-controlled body moved explicitly via script, affecting rigid bodies.
  kinematic,

  /// Fully dynamic body simulated via mass, forces, impulses, and gravity.
  rigid,
}

/// Geometric shape types for collision detection.
enum PhysicsShapeType {
  box,
  sphere,
  capsule,
}

/// Transform holding position and rotation for physics bodies.
class PhysicsTransform {
  final Vector3 position;
  final Quaternion rotation;

  PhysicsTransform({
    required Vector3 position,
    required Quaternion rotation,
  })  : position = Vector3.copy(position),
        rotation = Quaternion.copy(rotation);

  factory PhysicsTransform.identity() => PhysicsTransform(
        position: Vector3.zero(),
        rotation: Quaternion.identity(),
      );

  PhysicsTransform copyWith({Vector3? position, Quaternion? rotation}) {
    return PhysicsTransform(
      position: position ?? Vector3.copy(this.position),
      rotation: rotation ?? Quaternion.copy(this.rotation),
    );
  }

  @override
  String toString() => 'PhysicsTransform(pos: $position, rot: $rotation)';
}

/// Result of a physics raycast query.
class PhysicsRaycastHit {
  final int bodyId;
  final Vector3 position;
  final Vector3 normal;
  final double distance;

  const PhysicsRaycastHit({
    required this.bodyId,
    required this.position,
    required this.normal,
    required this.distance,
  });

  @override
  String toString() =>
      'PhysicsRaycastHit(body: $bodyId, pos: $position, normal: $normal, dist: $distance)';
}

/// Abstract interface for Godot-style low-level Physics Server.
///
/// Resources (spaces, bodies, shapes) are referenced via opaque integer handle IDs.
/// Operations are thread-safe and designed to be dispatched to a background isolate.
abstract class PhysicsServer extends Server {
  // --- Spaces ---

  /// Creates a new physics simulation space and returns its handle ID.
  int createSpace({int? id});

  /// Destroys a physics simulation space by [spaceId].
  void destroySpace(int spaceId);

  /// Sets the gravitational acceleration vector for [spaceId].
  void setGravity(int spaceId, Vector3 gravity);

  /// Asynchronously queries the gravity vector of [spaceId].
  Future<Vector3> getGravity(int spaceId);

  /// Synchronously returns cached gravity of [spaceId], or null if not yet cached.
  Vector3? getCachedGravity(int spaceId);

  // --- Shapes ---

  /// Creates a box collision shape with given [halfExtents] (x, y, z).
  int createBoxShape(Vector3 halfExtents, {int? id});

  /// Creates a sphere collision shape with given [radius].
  int createSphereShape(double radius, {int? id});

  /// Creates a capsule collision shape with given [radius] and [height].
  int createCapsuleShape(double radius, double height, {int? id});

  /// Destroys the shape identified by [shapeId].
  void destroyShape(int shapeId);

  // --- Bodies ---

  /// Creates a physics body and returns its handle ID.
  int createBody({
    int? id,
    PhysicsBodyType type = PhysicsBodyType.rigid,
    int? spaceId,
  });

  /// Destroys the physics body identified by [bodyId].
  void destroyBody(int bodyId);

  /// Assigns body [bodyId] to simulation space [spaceId].
  void setBodySpace(int bodyId, int spaceId);

  /// Attaches shape [shapeId] to body [bodyId] with optional local offset.
  void addShapeToBody(
    int bodyId,
    int shapeId, {
    Vector3? localPosition,
    Quaternion? localRotation,
  });

  /// Sets world transform (position and rotation) of body [bodyId].
  void setBodyTransform(int bodyId, Vector3 position, Quaternion rotation);

  /// Asynchronously retrieves current world transform of body [bodyId].
  Future<PhysicsTransform> getBodyTransform(int bodyId);

  /// Synchronously returns the locally cached transform of body [bodyId].
  PhysicsTransform? getCachedTransform(int bodyId);

  /// Sets linear velocity vector of body [bodyId].
  void setBodyLinearVelocity(int bodyId, Vector3 velocity);

  /// Asynchronously retrieves current linear velocity of body [bodyId].
  Future<Vector3> getBodyLinearVelocity(int bodyId);

  /// Synchronously returns the locally cached linear velocity of body [bodyId].
  Vector3? getCachedLinearVelocity(int bodyId);

  /// Sets mass of body [bodyId] in kilograms.
  void setBodyMass(int bodyId, double mass);

  /// Applies a continuous force in Newtons to body [bodyId].
  void applyForce(int bodyId, Vector3 force);

  /// Applies an instantaneous impulse in N*s to body [bodyId].
  void applyImpulse(int bodyId, Vector3 impulse);

  // --- Queries ---

  /// Casts a ray from [from] to [to] in [spaceId] and returns the closest hit, or null.
  Future<PhysicsRaycastHit?> raycast(int spaceId, Vector3 from, Vector3 to);
}

// ---------------------------------------------------------------------------
// Internal Shape & Body Models for Local Simulation Engine
// ---------------------------------------------------------------------------

class _PhysicsShapeData {
  final int id;
  final PhysicsShapeType type;
  final Vector3 halfExtents;
  final double radius;
  final double height;

  _PhysicsShapeData.box(this.id, Vector3 halfExtents)
      : type = PhysicsShapeType.box,
        halfExtents = Vector3.copy(halfExtents),
        radius = 0,
        height = 0;

  _PhysicsShapeData.sphere(this.id, this.radius)
      : type = PhysicsShapeType.sphere,
        halfExtents = Vector3.zero(),
        height = 0;

  _PhysicsShapeData.capsule(this.id, this.radius, this.height)
      : type = PhysicsShapeType.capsule,
        halfExtents = Vector3.zero();
}

class _AttachedShape {
  final int shapeId;
  final Vector3 localPosition;
  final Quaternion localRotation;

  _AttachedShape(this.shapeId, Vector3? pos, Quaternion? rot)
      : localPosition = pos != null ? Vector3.copy(pos) : Vector3.zero(),
        localRotation = rot != null ? Quaternion.copy(rot) : Quaternion.identity();
}

class _PhysicsSpaceData {
  final int id;
  Vector3 gravity = Vector3(0, -9.81, 0);
  final Set<int> bodyIds = {};

  _PhysicsSpaceData(this.id);
}

class _PhysicsBodyData {
  final int id;
  PhysicsBodyType type;
  int? spaceId;
  Vector3 position = Vector3.zero();
  Quaternion rotation = Quaternion.identity();
  Vector3 linearVelocity = Vector3.zero();
  Vector3 angularVelocity = Vector3.zero();
  Vector3 accumulatedForce = Vector3.zero();
  double mass = 1.0;
  double linearDamping = 0.02;
  final List<_AttachedShape> shapes = [];

  _PhysicsBodyData({
    required this.id,
    required this.type,
    this.spaceId,
  });
}

/// Concrete reference physics simulation server.
///
/// Implements genuine Newtonian physics integration, spatial queries,
/// raycasting, and Godot-style handle management. Used inside background Isolates
/// or standalone for direct local simulation.
class LocalPhysicsServer extends PhysicsServer {
  int _nextHandleId = 1;
  bool _isInitialized = false;

  final Map<int, _PhysicsSpaceData> _spaces = {};
  final Map<int, _PhysicsShapeData> _shapes = {};
  final Map<int, _PhysicsBodyData> _bodies = {};

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    _isInitialized = true;
  }

  @override
  void step(double dt) {
    if (!_isInitialized || dt <= 0.0) return;

    for (final space in _spaces.values) {
      for (final bodyId in space.bodyIds) {
        final body = _bodies[bodyId];
        if (body == null || body.type != PhysicsBodyType.rigid) continue;

        // Gravity contribution
        final totalForce = Vector3.copy(body.accumulatedForce);
        totalForce.add(space.gravity * body.mass);

        // Linear acceleration = Force / Mass
        final invMass = body.mass > 0 ? (1.0 / body.mass) : 0.0;
        final accel = totalForce * invMass;

        // Semi-implicit Euler integration
        body.linearVelocity.add(accel * dt);

        // Linear damping
        final dampingFactor = math.max(0.0, 1.0 - (body.linearDamping * dt));
        body.linearVelocity.scale(dampingFactor);

        // Update position
        body.position.add(body.linearVelocity * dt);

        // Clear accumulated forces
        body.accumulatedForce.setZero();

        // Ground constraint at y = 0
        if (body.position.y < 0.0) {
          body.position.y = 0.0;
          if (body.linearVelocity.y < 0.0) {
            // Elastic bounce with restitution
            body.linearVelocity.y = -body.linearVelocity.y * 0.2;
            if (body.linearVelocity.y.abs() < 0.1) {
              body.linearVelocity.y = 0.0;
            }
          }
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    _spaces.clear();
    _shapes.clear();
    _bodies.clear();
    _isInitialized = false;
  }

  int _reserveId(int? id) {
    final actualId = id ?? _nextHandleId++;
    if (actualId >= _nextHandleId) {
      _nextHandleId = actualId + 1;
    }
    return actualId;
  }

  // --- Spaces ---

  @override
  int createSpace({int? id}) {
    final actualId = _reserveId(id);
    _spaces[actualId] = _PhysicsSpaceData(actualId);
    return actualId;
  }

  @override
  void destroySpace(int spaceId) {
    final space = _spaces.remove(spaceId);
    if (space != null) {
      for (final bodyId in space.bodyIds) {
        final body = _bodies[bodyId];
        if (body != null && body.spaceId == spaceId) {
          body.spaceId = null;
        }
      }
    }
  }

  @override
  void setGravity(int spaceId, Vector3 gravity) {
    final space = _spaces[spaceId];
    if (space != null) {
      space.gravity = Vector3.copy(gravity);
    }
  }

  @override
  Future<Vector3> getGravity(int spaceId) async {
    return Vector3.copy(_spaces[spaceId]?.gravity ?? Vector3(0, -9.81, 0));
  }

  @override
  Vector3? getCachedGravity(int spaceId) {
    final g = _spaces[spaceId]?.gravity;
    return g != null ? Vector3.copy(g) : null;
  }

  // --- Shapes ---

  @override
  int createBoxShape(Vector3 halfExtents, {int? id}) {
    final actualId = _reserveId(id);
    _shapes[actualId] = _PhysicsShapeData.box(actualId, halfExtents);
    return actualId;
  }

  @override
  int createSphereShape(double radius, {int? id}) {
    final actualId = _reserveId(id);
    _shapes[actualId] = _PhysicsShapeData.sphere(actualId, radius);
    return actualId;
  }

  @override
  int createCapsuleShape(double radius, double height, {int? id}) {
    final actualId = _reserveId(id);
    _shapes[actualId] = _PhysicsShapeData.capsule(actualId, radius, height);
    return actualId;
  }

  @override
  void destroyShape(int shapeId) {
    _shapes.remove(shapeId);
  }

  // --- Bodies ---

  @override
  int createBody({
    int? id,
    PhysicsBodyType type = PhysicsBodyType.rigid,
    int? spaceId,
  }) {
    final actualId = _reserveId(id);
    final body = _PhysicsBodyData(id: actualId, type: type, spaceId: spaceId);
    _bodies[actualId] = body;
    if (spaceId != null && _spaces.containsKey(spaceId)) {
      _spaces[spaceId]!.bodyIds.add(actualId);
    }
    return actualId;
  }

  @override
  void destroyBody(int bodyId) {
    final body = _bodies.remove(bodyId);
    if (body != null && body.spaceId != null) {
      _spaces[body.spaceId]?.bodyIds.remove(bodyId);
    }
  }

  @override
  void setBodySpace(int bodyId, int spaceId) {
    final body = _bodies[bodyId];
    if (body == null) return;
    if (body.spaceId != null) {
      _spaces[body.spaceId]?.bodyIds.remove(bodyId);
    }
    body.spaceId = spaceId;
    if (_spaces.containsKey(spaceId)) {
      _spaces[spaceId]!.bodyIds.add(bodyId);
    }
  }

  @override
  void addShapeToBody(
    int bodyId,
    int shapeId, {
    Vector3? localPosition,
    Quaternion? localRotation,
  }) {
    final body = _bodies[bodyId];
    if (body != null) {
      body.shapes.add(_AttachedShape(shapeId, localPosition, localRotation));
    }
  }

  @override
  void setBodyTransform(int bodyId, Vector3 position, Quaternion rotation) {
    final body = _bodies[bodyId];
    if (body != null) {
      body.position = Vector3.copy(position);
      body.rotation = Quaternion.copy(rotation);
    }
  }

  @override
  Future<PhysicsTransform> getBodyTransform(int bodyId) async {
    final body = _bodies[bodyId];
    if (body != null) {
      return PhysicsTransform(
        position: body.position,
        rotation: body.rotation,
      );
    }
    return PhysicsTransform.identity();
  }

  @override
  PhysicsTransform? getCachedTransform(int bodyId) {
    final body = _bodies[bodyId];
    if (body != null) {
      return PhysicsTransform(
        position: body.position,
        rotation: body.rotation,
      );
    }
    return null;
  }

  @override
  void setBodyLinearVelocity(int bodyId, Vector3 velocity) {
    final body = _bodies[bodyId];
    if (body != null) {
      body.linearVelocity = Vector3.copy(velocity);
    }
  }

  @override
  Future<Vector3> getBodyLinearVelocity(int bodyId) async {
    return Vector3.copy(_bodies[bodyId]?.linearVelocity ?? Vector3.zero());
  }

  @override
  Vector3? getCachedLinearVelocity(int bodyId) {
    final vel = _bodies[bodyId]?.linearVelocity;
    return vel != null ? Vector3.copy(vel) : null;
  }

  @override
  void setBodyMass(int bodyId, double mass) {
    final body = _bodies[bodyId];
    if (body != null && mass > 0) {
      body.mass = mass;
    }
  }

  @override
  void applyForce(int bodyId, Vector3 force) {
    final body = _bodies[bodyId];
    if (body != null) {
      body.accumulatedForce.add(force);
    }
  }

  @override
  void applyImpulse(int bodyId, Vector3 impulse) {
    final body = _bodies[bodyId];
    if (body != null && body.type == PhysicsBodyType.rigid) {
      final invMass = body.mass > 0 ? (1.0 / body.mass) : 0.0;
      body.linearVelocity.add(impulse * invMass);
    }
  }

  // --- Queries ---

  @override
  Future<PhysicsRaycastHit?> raycast(int spaceId, Vector3 from, Vector3 to) async {
    final space = _spaces[spaceId];
    if (space == null) return null;

    final rayVec = to - from;
    final maxDist = rayVec.length;
    if (maxDist <= 0.0) return null;
    final rayDir = rayVec.normalized();

    PhysicsRaycastHit? closestHit;
    double closestDist = maxDist;

    for (final bodyId in space.bodyIds) {
      final body = _bodies[bodyId];
      if (body == null) continue;

      for (final attached in body.shapes) {
        final shape = _shapes[attached.shapeId];
        if (shape == null) continue;

        // Shape center in world space
        final shapeWorldPos = body.position + attached.localPosition;

        if (shape.type == PhysicsShapeType.sphere) {
          // Analytical Ray-Sphere Intersection
          final hit = _raycastSphere(
            bodyId: body.id,
            rayOrigin: from,
            rayDir: rayDir,
            sphereCenter: shapeWorldPos,
            radius: shape.radius > 0 ? shape.radius : 0.5,
            maxDist: closestDist,
          );
          if (hit != null && hit.distance < closestDist) {
            closestDist = hit.distance;
            closestHit = hit;
          }
        } else if (shape.type == PhysicsShapeType.box) {
          // Ray-AABB Slab intersection
          final half = shape.halfExtents;
          final hit = _raycastAabb(
            bodyId: body.id,
            rayOrigin: from,
            rayDir: rayDir,
            min: shapeWorldPos - half,
            max: shapeWorldPos + half,
            maxDist: closestDist,
          );
          if (hit != null && hit.distance < closestDist) {
            closestDist = hit.distance;
            closestHit = hit;
          }
        } else {
          // Capsule fallback (approximated as sphere bounding volume)
          final hit = _raycastSphere(
            bodyId: body.id,
            rayOrigin: from,
            rayDir: rayDir,
            sphereCenter: shapeWorldPos,
            radius: shape.radius + (shape.height * 0.5),
            maxDist: closestDist,
          );
          if (hit != null && hit.distance < closestDist) {
            closestDist = hit.distance;
            closestHit = hit;
          }
        }
      }
    }

    return closestHit;
  }

  PhysicsRaycastHit? _raycastSphere({
    required int bodyId,
    required Vector3 rayOrigin,
    required Vector3 rayDir,
    required Vector3 sphereCenter,
    required double radius,
    required double maxDist,
  }) {
    final oc = rayOrigin - sphereCenter;
    final b = oc.dot(rayDir);
    final c = oc.dot(oc) - (radius * radius);
    final discriminant = (b * b) - c;

    if (discriminant < 0) return null;

    final sqrtD = math.sqrt(discriminant);
    var t = -b - sqrtD;
    if (t < 0) {
      t = -b + sqrtD;
    }

    if (t >= 0 && t <= maxDist) {
      final hitPos = rayOrigin + (rayDir * t);
      final normal = (hitPos - sphereCenter).normalized();
      return PhysicsRaycastHit(
        bodyId: bodyId,
        position: hitPos,
        normal: normal,
        distance: t,
      );
    }
    return null;
  }

  PhysicsRaycastHit? _raycastAabb({
    required int bodyId,
    required Vector3 rayOrigin,
    required Vector3 rayDir,
    required Vector3 min,
    required Vector3 max,
    required double maxDist,
  }) {
    double tmin = 0.0;
    double tmax = maxDist;
    Vector3 hitNormal = Vector3.zero();

    for (int i = 0; i < 3; i++) {
      final dir = rayDir[i];
      final orig = rayOrigin[i];
      final minVal = min[i];
      final maxVal = max[i];

      if (dir.abs() < 1e-8) {
        if (orig < minVal || orig > maxVal) return null;
      } else {
        final invD = 1.0 / dir;
        var t0 = (minVal - orig) * invD;
        var t1 = (maxVal - orig) * invD;
        var sign = -1.0;

        if (invD < 0.0) {
          final tmp = t0;
          t0 = t1;
          t1 = tmp;
          sign = 1.0;
        }

        if (t0 > tmin) {
          tmin = t0;
          hitNormal = Vector3.zero();
          hitNormal[i] = sign;
        }
        tmax = math.min(tmax, t1);
        if (tmax < tmin) return null;
      }
    }

    if (tmin <= maxDist) {
      final hitPos = rayOrigin + (rayDir * tmin);
      return PhysicsRaycastHit(
        bodyId: bodyId,
        position: hitPos,
        normal: hitNormal,
        distance: tmin,
      );
    }
    return null;
  }

  /// Exports snapshot of moving body transforms for isolate synchronization.
  Map<int, PhysicsTransform> getActiveBodyTransforms() {
    final result = <int, PhysicsTransform>{};
    for (final entry in _bodies.entries) {
      result[entry.key] = PhysicsTransform(
        position: entry.value.position,
        rotation: entry.value.rotation,
      );
    }
    return result;
  }
}
