// tests/tier3_cross_feature_test.dart
//
// Tier 3: Cross-Feature Combinations (Pairwise Interactions)
// Validates end-to-end subsystem integration:
// - Phase 1: Allocators + FFI Bridge + Editor Controller
// - Phase 2:
//   - PBR + Clustered Forward+ Dynamic Lights + Directional Shadows
//   - BVH Frustum Culling + Dynamic Physics Bodies
//   - BVH Broadphase + Physics Contact Graph
//   - Viewport Camera + Clustered Forward+ Frustum
//   - Entity Inspector + Live Physics & ECS Transform Sync
//   - Zero-Copy Texture Pipeline + PBR Frame Submission

import 'dart:math' as math;
import 'dart:typed_data';
import 'e2e_test_harness.dart';
import 'fluorite_bridge_model.dart';

void registerTier3Tests() {
  TestHarness.group('Tier 3 - Cross-Feature Combinations (Pairwise)', () {
    // -------------------------------------------------------------------------
    // Phase 1 Combinations
    // -------------------------------------------------------------------------

    TestHarness.test('test_t3_allocator_reset_and_frame_swap', () {
      final frameAlloc = DoubleBufferedFrameAllocatorModel(1024 * 64);
      for (int frame = 0; frame < 50; frame++) {
        final slice = frameAlloc.currentArena.allocSlice(512, frame & 0xFF);
        expect(slice.length, equals(512));
        expect(slice[0], equals(frame & 0xFF));

        frameAlloc.swapBuffers();
        expect(frameAlloc.currentArena.allocatedBytes, equals(0));
      }
      expect(frameAlloc.frameIndex, equals(50));
    });

    TestHarness.test('test_t3_arena_allocation_and_ffi_buffer_transfer', () {
      final arena = ArenaAllocatorModel(1024 * 1024 * 2);
      final rawAddr = arena.allocRaw(1024 * 1024, 64);
      expect(rawAddr % 64, equals(0));

      final ffiBuffer = allocateEngineBuffer(1024 * 1024);
      expect(verifyBufferSentinels(ffiBuffer), isTrue);
      expect(ffiBuffer.length, equals(1024 * 1024));
    });

    TestHarness.test('test_t3_dart_call_and_1mb_buffer_readback', () async {
      final controller = EngineControllerModel();
      await controller.startEngine();
      final buf = await controller.allocate1MB();

      expect(buf[0], equals(0xAA));
      expect(buf[1024 * 1024 - 1], equals(0x55));
      expect(verifyBufferSentinels(buf), isTrue);
    });

    TestHarness.test('test_t3_shared_buffer_pointer_and_editor_controller', () async {
      final controller = EngineControllerModel();
      await controller.startEngine();

      final sharedBuf = SharedFrameBufferModel(1024);
      expect(sharedBuf.readByte(0), equals(0xDE));
      expect(sharedBuf.readByte(1), equals(0xAD));

      sharedBuf.writeByte(10, 0xEE);
      expect(sharedBuf.readByte(10), equals(0xEE));
    });

    TestHarness.test('test_t3_ffi_mutation_and_allocator_metrics', () async {
      final controller = EngineControllerModel();
      await controller.startEngine();
      final buf = await controller.allocate1MB();

      writeBufferPattern(buf, 0x33);
      expect(buf[0], equals(0x33));
      expect(buf[1024 * 1024 - 1], equals(0x33));

      expect(controller.status!.arenaAllocatedBytes, equals(1024 * 1024));
    });

    // -------------------------------------------------------------------------
    // Phase 2 Combinations (Wave 1)
    // -------------------------------------------------------------------------

    TestHarness.test('test_t3_pbr_with_dynamic_lights_and_shadows', () {
      const mat = PbrMaterial(
        baseColor: Vec4(1.0, 1.0, 1.0, 1.0),
        metallic: 0.5,
        roughness: 0.3,
      );

      // Unshadowed radiance
      final litRadiance = PbrRenderer.evaluateCookTorrance(
        material: mat,
        normal: const Vec3(0, 1, 0),
        viewDir: const Vec3(0, 1, 1),
        lightDir: const Vec3(0, 1, 1),
        lightColor: const Vec3(1, 1, 1),
        shadowFactor: 1.0,
      );

      // Fully shadowed radiance
      final shadowedRadiance = PbrRenderer.evaluateCookTorrance(
        material: mat,
        normal: const Vec3(0, 1, 0),
        viewDir: const Vec3(0, 1, 1),
        lightDir: const Vec3(0, 1, 1),
        lightColor: const Vec3(1, 1, 1),
        shadowFactor: 0.1, // 90% shadow attenuation
      );

      expect(litRadiance.length, greaterThan(shadowedRadiance.length));
      expect(shadowedRadiance.length, closeTo(litRadiance.length * 0.1, 0.01));
    });

    TestHarness.test('test_t3_bvh_frustum_culling_with_dynamic_physics', () {
      final world = PhysicsWorldModel();
      final body1 = RigidBodyModel(
        id: 1,
        type: RigidBodyType.dynamic,
        position: const Vec3(0, 0, -20), // Inside frustum
      );
      final body2 = RigidBodyModel(
        id: 2,
        type: RigidBodyType.dynamic,
        position: const Vec3(0, 0, 20), // Behind frustum
      );
      world.addBody(body1);
      world.addBody(body2);

      // Step physics
      world.step(1.0 / 60.0);

      // Update BVH from dynamic body positions
      final entities = [
        BvhEntity(body1.id, Aabb(body1.position - const Vec3(1, 1, 1), body1.position + const Vec3(1, 1, 1))),
        BvhEntity(body2.id, Aabb(body2.position - const Vec3(1, 1, 1), body2.position + const Vec3(1, 1, 1))),
      ];
      final bvh = BvhBuilder.build(entities);

      final vp = Mat4.perspective(1.047, 1.77, 0.1, 100.0)
          .multiply(Mat4.lookAt(Vec3.zero, const Vec3(0, 0, -1), Vec3.unitY));
      final frustum = Frustum.fromViewProjection(vp);

      final culled = bvh.cullFrustum(frustum);
      expect(culled.contains(1), isTrue, reason: 'Body 1 in front of camera must be visible');
      expect(culled.contains(2), isFalse, reason: 'Body 2 behind camera must be culled');
    });

    TestHarness.test('test_t3_bvh_broadphase_feeding_physics_contact_graph', () {
      // Two bodies with overlapping AABBs
      final entities = [
        const BvhEntity(1, Aabb(Vec3(0, 0, 0), Vec3(2, 2, 2))),
        const BvhEntity(2, Aabb(Vec3(1, 1, 1), Vec3(3, 3, 3))),
      ];
      final bvh = BvhBuilder.build(entities);
      final pairs = bvh.findBroadphasePairs();

      expect(pairs.length, equals(1));
      expect(pairs[0].$1, equals(1));
      expect(pairs[0].$2, equals(2));
    });

    TestHarness.test('test_t3_viewport_camera_updates_clustered_forward_frustum', () {
      final cam = CameraControllerModel();
      cam.updateOrbit(deltaYaw: 1.57); // Turn 90 degrees

      final grid = ClusteredForwardGrid(nearPlane: 0.1, farPlane: 500.0);
      final light = const DynamicLight(
        id: 1,
        type: LightType.point,
        position: Vec3(50, 0, 0),
        range: 10.0,
      );

      final assigned = grid.assignLights([light]);
      expect(assigned, equals(1));
    });

    TestHarness.test('test_t3_entity_inspector_mutates_live_physics_and_transform_sync', () {
      final shell = EditorShellModel();
      final body = RigidBodyModel(
        id: 1,
        type: RigidBodyType.dynamic,
        position: const Vec3(5.0, 10.0, -15.0),
      );
      final entity = SceneEntityModel(
        id: 1,
        name: 'Physics Box',
        position: const Vec3(5.0, 10.0, -15.0),
        rigidBody: body,
      );
      shell.entities.add(entity);
      shell.selectEntity(1);

      // Verify inspector reflects physics body
      final cards = shell.getInspectorCards();
      expect(cards.any((c) => c.type == PropertyCardType.rapierPhysics), isTrue);

      // Live mutation of transform
      entity.position = const Vec3(20.0, 30.0, -40.0);
      body.position = entity.position;

      // Sync to 16-float ECS buffer
      final ecsBuffer = Float32List(16);
      final world = PhysicsWorldModel();
      world.addBody(body);
      world.syncTransformsToEcs(ecsBuffer, 16);

      expect(ecsBuffer[12], equals(20.0));
      expect(ecsBuffer[13], equals(30.0));
      expect(ecsBuffer[14], equals(-40.0));
    });

    TestHarness.test('test_t3_zero_copy_texture_pipeline_with_pbr_frame_submission', () {
      final pipeline = ZeroCopyTexturePipelineModel(textureId: 100);
      // Simulate rendered PBR 1080p frame packet
      final frameBytes = Uint8List(1920 * 1080 * 4);
      frameBytes.fillRange(0, 100, 0x88);

      final texId = pipeline.submitFrame(frameBytes);
      expect(texId, equals(100));
      expect(pipeline.lastSubmittedSlice, isNotNull);
      expect(pipeline.verifyFrameSentinels(pipeline.lastSubmittedSlice!), isTrue);
    });
  });
}
