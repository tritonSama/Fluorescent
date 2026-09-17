import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluorescent_ecs/fluorescent_ecs.dart';

void main() {
  group('Entity', () {
    test('creates entity with valid integer id', () {
      const entity = Entity(42);
      expect(entity.id, equals(42));
      expect(entity.isValid, isTrue);
      expect(entity, equals(42)); // Implements int
    });

    test('invalid sentinel has negative id and isValid is false', () {
      expect(Entity.invalid.id, equals(-1));
      expect(Entity.invalid.isValid, isFalse);
    });

    test('can be used in collections and comparison operators', () {
      const e1 = Entity(1);
      const e2 = Entity(2);
      expect(e1 < e2, isTrue);
      expect(e1 == 1, isTrue);

      final map = <Entity, String>{};
      map[e1] = 'First';
      map[e2] = 'Second';
      expect(map[const Entity(1)], equals('First'));
    });
  });

  group('SparseSet', () {
    late SparseSet sparseSet;

    setUp(() {
      sparseSet = SparseSet(stride: 4, initialCapacity: 4, initialSparseCapacity: 8);
    });

    test('initial state is empty', () {
      expect(sparseSet.count, equals(0));
      expect(sparseSet.isEmpty, isTrue);
      expect(sparseSet.isNotEmpty, isFalse);
      expect(sparseSet.stride, equals(4));
      expect(sparseSet.capacity, equals(4));
      expect(sparseSet.sparseCapacity, equals(8));
    });

    test('add and contains', () {
      final offset = sparseSet.add(3);
      expect(offset, equals(0));
      expect(sparseSet.count, equals(1));
      expect(sparseSet.contains(3), isTrue);
      expect(sparseSet.contains(0), isFalse);
      expect(sparseSet.contains(5), isFalse);
      expect(sparseSet.getDenseIndex(3), equals(0));
      expect(sparseSet.getOffset(3), equals(0));
      expect(sparseSet.getEntityAt(0), equals(3));
    });

    test('adding existing entity returns existing offset without duplicating', () {
      final off1 = sparseSet.add(5);
      sparseSet.data[off1] = 99.0;

      final off2 = sparseSet.add(5);
      expect(off2, equals(off1));
      expect(sparseSet.count, equals(1));
      expect(sparseSet.data[off2], equals(99.0));
    });

    test('expands sparse array when entity id exceeds initial sparse capacity', () {
      final off = sparseSet.add(100);
      expect(sparseSet.contains(100), isTrue);
      expect(sparseSet.sparseCapacity, greaterThanOrEqualTo(101));
      expect(sparseSet.getOffset(100), equals(off));
      expect(sparseSet.contains(50), isFalse);
    });

    test('expands dense and data buffers when count exceeds initial capacity', () {
      for (int i = 0; i < 20; i++) {
        final off = sparseSet.add(i);
        sparseSet.data[off] = i * 10.0;
      }
      expect(sparseSet.count, equals(20));
      expect(sparseSet.capacity, greaterThanOrEqualTo(20));

      for (int i = 0; i < 20; i++) {
        expect(sparseSet.contains(i), isTrue);
        final off = sparseSet.getOffset(i);
        expect(sparseSet.data[off], equals(i * 10.0));
      }
    });

    test('swap-and-pop removal preserves dense contiguous packing', () {
      // Add entities 10, 20, 30, 40
      final off10 = sparseSet.add(10);
      sparseSet.data[off10] = 100.0;
      final off20 = sparseSet.add(20);
      sparseSet.data[off20] = 200.0;
      final off30 = sparseSet.add(30);
      sparseSet.data[off30] = 300.0;
      final off40 = sparseSet.add(40);
      sparseSet.data[off40] = 400.0;

      expect(sparseSet.count, equals(4));

      // Remove entity 20 (middle element at dense index 1)
      final removed = sparseSet.remove(20);
      expect(removed, isTrue);
      expect(sparseSet.count, equals(3));
      expect(sparseSet.contains(20), isFalse);
      expect(sparseSet.getOffset(20), equals(-1));

      // Entity 40 should have swapped into dense index 1
      expect(sparseSet.getDenseIndex(40), equals(1));
      expect(sparseSet.getEntityAt(1), equals(40));
      expect(sparseSet.data[sparseSet.getOffset(40)], equals(400.0));

      // Entities 10 and 30 remain intact
      expect(sparseSet.contains(10), isTrue);
      expect(sparseSet.data[sparseSet.getOffset(10)], equals(100.0));
      expect(sparseSet.contains(30), isTrue);
      expect(sparseSet.data[sparseSet.getOffset(30)], equals(300.0));

      // Removing non-existent entity returns false
      expect(sparseSet.remove(999), isFalse);
      expect(sparseSet.remove(-1), isFalse);
    });

    test('clear resets count and membership', () {
      sparseSet.add(1);
      sparseSet.add(2);
      sparseSet.clear();

      expect(sparseSet.count, equals(0));
      expect(sparseSet.isEmpty, isTrue);
      expect(sparseSet.contains(1), isFalse);
      expect(sparseSet.contains(2), isFalse);

      // Can add again after clear
      final off = sparseSet.add(1);
      expect(off, equals(0));
      expect(sparseSet.contains(1), isTrue);
    });

    test('getComponentSlice returns subview', () {
      final off = sparseSet.add(7);
      sparseSet.data[off] = 1.0;
      sparseSet.data[off + 1] = 2.0;
      sparseSet.data[off + 2] = 3.0;
      sparseSet.data[off + 3] = 4.0;

      final slice = sparseSet.getComponentSlice(7);
      expect(slice, isNotNull);
      expect(slice!.length, equals(4));
      expect(slice, equals(Float32List.fromList([1.0, 2.0, 3.0, 4.0])));

      expect(sparseSet.getComponentSlice(999), isNull);
    });

    test('forEach iterates densely without allocations', () {
      sparseSet.add(10);
      sparseSet.add(20);
      sparseSet.add(30);

      final visited = <int>[];
      sparseSet.forEach((entityId, data, offset) {
        visited.add(entityId);
        data[offset] = entityId * 2.0;
      });

      expect(visited, equals([10, 20, 30]));
      expect(sparseSet.data[sparseSet.getOffset(10)], equals(20.0));
      expect(sparseSet.data[sparseSet.getOffset(20)], equals(40.0));
      expect(sparseSet.data[sparseSet.getOffset(30)], equals(60.0));
    });
  });

  group('TypedComponentStorage', () {
    test('manages custom stride component storage with Entity keys', () {
      final storage = TypedComponentStorage(stride: 8, initialCapacity: 16);
      const e1 = Entity(10);
      const e2 = Entity(20);

      expect(storage.has(e1), isFalse);
      final off1 = storage.allocate(e1);
      expect(off1, equals(0));
      expect(storage.has(e1), isTrue);
      expect(storage.count, equals(1));

      final off2 = storage.allocate(e2);
      expect(off2, equals(8));
      expect(storage.count, equals(2));

      storage.rawData[off1] = 123.45;
      storage.rawData[off2] = 678.90;

      final visitedEntities = <Entity>[];
      storage.forEach((entity, data, offset) {
        visitedEntities.add(entity);
      });
      expect(visitedEntities, equals([e1, e2]));

      storage.remove(e1);
      expect(storage.has(e1), isFalse);
      expect(storage.has(e2), isTrue);
      expect(storage.count, equals(1));
    });
  });

  group('TransformStorage & TransformComponent', () {
    late TransformStorage transforms;

    setUp(() {
      transforms = TransformStorage(initialCapacity: 16);
    });

    test('stride is 16 floats (64 bytes)', () {
      expect(transforms.stride, equals(TransformOffsets.stride));
      expect(TransformOffsets.stride, equals(16));
    });

    test('set with custom fields and verify individual getters', () {
      const e = Entity(5);
      transforms.set(
        e,
        x: 10.0,
        y: 20.0,
        z: 30.0,
        flags: TransformFlags.dirty,
        qx: 0.1,
        qy: 0.2,
        qz: 0.3,
        qw: 0.9,
        sx: 2.0,
        sy: 3.0,
        sz: 4.0,
        reserved: 7.0,
        boundsRadius: 15.0,
        boundsCenterX: 1.0,
        boundsCenterY: 2.0,
        boundsCenterZ: 3.0,
      );

      expect(transforms.has(e), isTrue);
      expect(transforms.getX(e), closeTo(10.0, 1e-5));
      expect(transforms.getY(e), closeTo(20.0, 1e-5));
      expect(transforms.getZ(e), closeTo(30.0, 1e-5));
      expect(transforms.getFlags(e), equals(TransformFlags.dirty));
      expect(transforms.isDirty(e), isTrue);
      expect(transforms.getQx(e), closeTo(0.1, 1e-5));
      expect(transforms.getQy(e), closeTo(0.2, 1e-5));
      expect(transforms.getQz(e), closeTo(0.3, 1e-5));
      expect(transforms.getQw(e), closeTo(0.9, 1e-5));
      expect(transforms.getSx(e), closeTo(2.0, 1e-5));
      expect(transforms.getSy(e), closeTo(3.0, 1e-5));
      expect(transforms.getSz(e), closeTo(4.0, 1e-5));
      expect(transforms.getBoundsRadius(e), closeTo(15.0, 1e-5));
    });

    test('default identity transform values', () {
      const e = Entity(1);
      transforms.set(e, x: 5.0, y: 10.0, z: 15.0);

      expect(transforms.getX(e), equals(5.0));
      expect(transforms.getY(e), equals(10.0));
      expect(transforms.getZ(e), equals(15.0));
      expect(transforms.getFlags(e), equals(0));
      expect(transforms.getQx(e), equals(0.0));
      expect(transforms.getQy(e), equals(0.0));
      expect(transforms.getQz(e), equals(0.0));
      expect(transforms.getQw(e), equals(1.0)); // Identity quaternion
      expect(transforms.getSx(e), equals(1.0)); // Identity scale
      expect(transforms.getSy(e), equals(1.0));
      expect(transforms.getSz(e), equals(1.0));
    });

    test('individual setters modify component values in-place', () {
      const e = Entity(2);
      transforms.set(e);

      transforms.setX(e, 100.0);
      transforms.setY(e, 200.0);
      transforms.setZ(e, 300.0);
      expect(transforms.getX(e), equals(100.0));
      expect(transforms.getY(e), equals(200.0));
      expect(transforms.getZ(e), equals(300.0));

      transforms.setTranslation(e, 1.0, 2.0, 3.0);
      expect(transforms.getX(e), equals(1.0));
      expect(transforms.getY(e), equals(2.0));
      expect(transforms.getZ(e), equals(3.0));

      transforms.setRotation(e, 0.0, 0.7071, 0.0, 0.7071);
      expect(transforms.getQy(e), closeTo(0.7071, 1e-4));
      expect(transforms.getQw(e), closeTo(0.7071, 1e-4));

      transforms.setUniformScale(e, 5.0);
      expect(transforms.getSx(e), equals(5.0));
      expect(transforms.getSy(e), equals(5.0));
      expect(transforms.getSz(e), equals(5.0));

      transforms.setDirty(e, true);
      expect(transforms.isDirty(e), isTrue);
      transforms.setDirty(e, false);
      expect(transforms.isDirty(e), isFalse);
    });

    test('TransformComponent object conversion', () {
      const e = Entity(8);
      final comp = TransformComponent(
        x: 11.0,
        y: 22.0,
        z: 33.0,
        sx: 2.0,
        sy: 2.0,
        sz: 2.0,
        boundsRadius: 5.0,
      );

      transforms.setComponent(e, comp);
      final retrieved = transforms.getComponent(e);
      expect(retrieved, isNotNull);
      expect(retrieved!.x, equals(11.0));
      expect(retrieved.y, equals(22.0));
      expect(retrieved.z, equals(33.0));
      expect(retrieved.sx, equals(2.0));
      expect(retrieved.boundsRadius, equals(5.0));

      expect(transforms.getComponent(const Entity(999)), isNull);
    });

    test('TransformView zero-allocation in-place mutations', () {
      const e = Entity(9);
      transforms.set(e, x: 1.0, y: 2.0, z: 3.0);

      final view = transforms.getView(e);
      expect(view, isNotNull);
      expect(view!.x, equals(1.0));

      view.x = 42.0;
      view.y = 84.0;
      view.setScale(3.0, 3.0, 3.0);

      expect(transforms.getX(e), equals(42.0));
      expect(transforms.getY(e), equals(84.0));
      expect(transforms.getSx(e), equals(3.0));
    });
  });

  group('EcsWorld', () {
    late EcsWorld world;

    setUp(() {
      world = EcsWorld(initialCapacity: 16);
    });

    test('entity creation and alive status', () {
      final e1 = world.createEntity();
      final e2 = world.createEntity();

      expect(e1.id, equals(0));
      expect(e2.id, equals(1));
      expect(world.entityCount, equals(2));
      expect(world.isAlive(e1), isTrue);
      expect(world.isAlive(e2), isTrue);
      expect(world.isAlive(const Entity(99)), isFalse);
      expect(world.isAlive(Entity.invalid), isFalse);
    });

    test('entity destruction and component removal', () {
      final e = world.createEntity();
      world.transforms.set(e, x: 10.0, y: 20.0, z: 30.0);

      expect(world.transforms.has(e), isTrue);
      expect(world.entityCount, equals(1));

      final destroyed = world.destroyEntity(e);
      expect(destroyed, isTrue);
      expect(world.isAlive(e), isFalse);
      expect(world.entityCount, equals(0));
      expect(world.transforms.has(e), isFalse);

      // Destroying already destroyed entity returns false
      expect(world.destroyEntity(e), isFalse);
    });

    test('entity ID recycling', () {
      final e0 = world.createEntity();
      final e1 = world.createEntity();
      final e2 = world.createEntity();

      expect(e0.id, equals(0));
      expect(e1.id, equals(1));
      expect(e2.id, equals(2));

      world.destroyEntity(e1);
      expect(world.isAlive(e1), isFalse);

      // Re-creating should reuse recycled ID
      final eReused = world.createEntity();
      expect(eReused.id, equals(1));
      expect(world.isAlive(eReused), isTrue);
    });

    test('custom storage registration and auto-cleanup on entity destroy', () {
      final velocityStorage = TypedComponentStorage(stride: 3, initialCapacity: 16);
      world.registerStorage(velocityStorage);

      final e = world.createEntity();
      world.transforms.set(e, x: 1.0);
      velocityStorage.allocate(e);

      expect(world.transforms.has(e), isTrue);
      expect(velocityStorage.has(e), isTrue);

      world.destroyEntity(e);

      expect(world.transforms.has(e), isFalse);
      expect(velocityStorage.has(e), isFalse);

      world.unregisterStorage(velocityStorage);
    });

    test('batch entity creation with createEntities', () {
      final entities = world.createEntities(50);
      expect(entities.length, equals(50));
      expect(world.entityCount, equals(50));
      for (final e in entities) {
        expect(world.isAlive(e), isTrue);
      }
    });

    test('forEachEntity and entities getter', () {
      final e0 = world.createEntity();
      final e1 = world.createEntity();
      final e2 = world.createEntity();
      world.destroyEntity(e1);

      final allEntities = world.entities;
      expect(allEntities, equals([e0, e2]));
    });

    test('clear resets everything', () {
      final e1 = world.createEntity();
      world.transforms.set(e1, x: 5.0);
      world.createEntity();

      world.clear();
      expect(world.entityCount, equals(0));
      expect(world.isEmpty, isTrue);
      expect(world.transforms.count, equals(0));

      final newE = world.createEntity();
      expect(newE.id, equals(0));
    });
  });
}
