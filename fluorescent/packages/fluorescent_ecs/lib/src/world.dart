import 'dart:typed_data';

import 'components/transform_component.dart';
import 'entity.dart';
import 'storage/typed_component_storage.dart';

/// The central container and manager for entities and component storages.
///
/// Provides fast O(1) entity creation, destruction with ID recycling,
/// automatic component cleanup, and direct access to contiguous component arrays.
class EcsWorld {
  /// Counter for generating monotonically increasing entity identifiers.
  int _nextEntityId = 0;

  /// Stack of recycled entity IDs available for reuse.
  final List<int> _recycled = <int>[];

  /// Byte flags tracking alive status (`1` = alive, `0` = inactive/destroyed).
  Uint8List _alive;

  /// Number of currently active (alive) entities.
  int _aliveCount = 0;

  /// Dedicated contiguous storage for [TransformComponent]s.
  final TransformStorage _transforms;

  /// Optional custom component storages registered with this world.
  final List<TypedComponentStorage> _customStorages = <TypedComponentStorage>[];

  /// Creates an [EcsWorld] with initial buffer capacities.
  EcsWorld({
    int initialCapacity = 64,
    int initialSparseCapacity = 256,
  })  : _transforms = TransformStorage(
          initialCapacity: initialCapacity,
          initialSparseCapacity: initialSparseCapacity,
        ),
        _alive = Uint8List(initialSparseCapacity);

  /// The contiguous [TransformStorage] holding all entity transforms.
  TransformStorage get transforms => _transforms;

  /// Number of active entities currently alive in the world.
  int get entityCount => _aliveCount;

  /// Whether no entities are currently active in this world.
  bool get isEmpty => _aliveCount == 0;

  /// Whether at least one entity is currently active in this world.
  bool get isNotEmpty => _aliveCount > 0;

  /// Read-only list of custom storages registered with this world.
  List<TypedComponentStorage> get customStorages => List<TypedComponentStorage>.unmodifiable(_customStorages);

  /// Checks whether [entity] is currently alive in this world.
  bool isAlive(Entity entity) {
    final id = entity.id;
    if (id < 0 || id >= _alive.length) return false;
    return _alive[id] == 1;
  }

  /// Spawns a new [Entity], reusing a recycled ID if available.
  Entity createEntity() {
    final int id;
    if (_recycled.isNotEmpty) {
      id = _recycled.removeLast();
    } else {
      id = _nextEntityId++;
    }

    if (id >= _alive.length) {
      int newCap = _alive.length * 2;
      if (newCap <= id) newCap = id + 1;
      if (newCap < 256) newCap = 256;
      final newAlive = Uint8List(newCap);
      newAlive.setRange(0, _alive.length, _alive);
      _alive = newAlive;
    }

    _alive[id] = 1;
    _aliveCount++;
    return Entity(id);
  }

  /// Spawns [count] entities in batch and returns them as a list.
  List<Entity> createEntities(int count) {
    final list = List<Entity>.generate(count, (_) => createEntity(), growable: false);
    return list;
  }

  /// Destroys [entity], detaching all its components and marking its ID for recycling.
  ///
  /// Returns `true` if the entity was alive and successfully destroyed, `false` otherwise.
  bool destroyEntity(Entity entity) {
    final id = entity.id;
    if (id < 0 || id >= _alive.length || _alive[id] == 0) {
      return false;
    }

    _alive[id] = 0;
    _aliveCount--;

    // Clean up core components
    _transforms.remove(entity);

    // Clean up custom component storages
    for (int i = 0; i < _customStorages.length; i++) {
      _customStorages[i].remove(entity);
    }

    _recycled.add(id);
    return true;
  }

  /// Registers a custom [TypedComponentStorage] so entities destroyed in this world
  /// automatically have their components freed from [storage].
  void registerStorage(TypedComponentStorage storage) {
    if (!_customStorages.contains(storage)) {
      _customStorages.add(storage);
    }
  }

  /// Unregisters a previously registered [TypedComponentStorage].
  bool unregisterStorage(TypedComponentStorage storage) {
    return _customStorages.remove(storage);
  }

  /// Resets the world, destroying all entities, clearing all component storages,
  /// and resetting entity ID generation.
  void clear() {
    _transforms.clear();
    for (int i = 0; i < _customStorages.length; i++) {
      _customStorages[i].clear();
    }
    _alive.fillRange(0, _alive.length, 0);
    _aliveCount = 0;
    _recycled.clear();
    _nextEntityId = 0;
  }

  /// Executes [action] for every currently alive entity in the world without heap allocations.
  void forEachEntity(void Function(Entity entity) action) {
    int found = 0;
    for (int i = 0; i < _nextEntityId && found < _aliveCount; i++) {
      if (_alive[i] == 1) {
        action(Entity(i));
        found++;
      }
    }
  }

  /// Returns a snapshot list of all currently alive entities.
  List<Entity> get entities {
    final result = <Entity>[];
    forEachEntity(result.add);
    return result;
  }
}
