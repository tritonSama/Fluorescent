// tests/tier4_real_world_scenarios_test.dart
//
// Tier 4: Real-World Application Scenarios
// Validates end-to-end engine performance, memory stability, and stress:
// - Phase 1: 60 FPS Loop, 1000 Frames Allocator, 1MB Asset Stream, Memory Pressure, Editor Lifecycle
// - Phase 2: Complete AAA Scene, 1000-Frame Stress Stability, 10k Entities BVH Culling <2ms, 1024 Dynamic Lights, KCC Navigation

import 'dart:math' as math;
import 'dart:typed_data';
import 'e2e_test_harness.dart';
import 'fluorite_bridge_model.dart';

void registerTier4Tests() {
  TestHarness.group('Tier 4 - Real-World Application Scenarios', () {
    // -------------------------------------------------------------------------
    // Phase 1 Scenarios
    // -------------------------------------------------------------------------

    TestHarness.test('test_t4_scenario1_game_loop_60fps_simulation', () {
      final frameAlloc = DoubleBufferedFrameAllocatorModel(1024 * 1024 * 4); // 4MB per frame
      for (int f = 0; f < 60; f++) {
        final transforms = frameAlloc.currentArena.allocSlice(16 * 100, 0);
        final drawCommands = frameAlloc.currentArena.allocSlice(64 * 50, 0);
        expect(transforms.length, equals(1600));
        expect(drawCommands.length, equals(3200));

        frameAlloc.swapBuffers();
        expect(frameAlloc.currentArena.allocatedBytes, equals(0));
      }
      expect(frameAlloc.frameIndex, equals(60));
    });

    TestHarness.test('test_t4_scenario2_1000_consecutive_frame_allocations', () {
      final frameAlloc = DoubleBufferedFrameAllocatorModel(1024 * 1024 * 2);
      for (int f = 0; f < 1000; f++) {
        frameAlloc.currentArena.allocSlice(1024, f & 0xFF);
        frameAlloc.swapBuffers();
      }
      expect(frameAlloc.frameIndex, equals(1000));
      expect(frameAlloc.currentArena.allocatedBytes, equals(0));
    });

    TestHarness.test('test_t4_scenario3_1mb_asset_buffer_streaming', () {
      const oneMb = 1024 * 1024;
      final assetData = Uint8List(oneMb);
      for (int i = 0; i < 1000; i++) {
        assetData[i] = (i * 7) & 0xFF;
      }

      final ffiBuf = allocateEngineBuffer(oneMb);
      ffiBuf.setRange(1, oneMb - 1, assetData.sublist(1, oneMb - 1));

      expect(verifyBufferSentinels(ffiBuf), isTrue);
      expect(ffiBuf[10], equals(assetData[10]));
    });

    TestHarness.test('test_t4_scenario4_dynamic_memory_pressure_recovery', () {
      final arena = ArenaAllocatorModel(1024 * 64);
      arena.allocSlice(1024 * 60, 0x11);
      expect(arena.remainingBytes, lessThan(1024 * 5));

      expect(() => arena.allocSlice(1024 * 10, 0x22), throwsA());

      arena.reset();
      expect(arena.allocatedBytes, equals(0));
      final slice = arena.allocSlice(1024 * 10, 0x33);
      expect(slice.length, equals(1024 * 10));
    });

    TestHarness.test('test_t4_scenario5_multi_turn_editor_lifecycle', () async {
      final controller = EngineControllerModel();
      await controller.startEngine();
      expect(controller.state, equals(EngineState.running));

      final buf1 = await controller.allocate1MB();
      expect(buf1.length, equals(1024 * 1024));

      controller.reset();
      expect(controller.state, equals(EngineState.uninitialized));

      await controller.startEngine();
      final buf2 = await controller.allocate1MB();
      expect(buf2.length, equals(1024 * 1024));
    });

    // -------------------------------------------------------------------------
    // Phase 2 Scenarios (Wave 1)
    // -------------------------------------------------------------------------

    TestHarness.test('test_t4_scenario6_complete_aaa_scene_simulation', () {
      // 1. Setup Clustered Forward+ Grid with 128 dynamic lights
      final grid = ClusteredForwardGrid();
      final lights = List.generate(
        128,
        (i) => DynamicLight(
          id: i,
          type: LightType.point,
          position: Vec3((i % 16) * 10.0 - 80.0, 5.0, -((i ~/ 16) * 10.0 + 10.0)),
          color: const Vec3(1, 0.9, 0.8),
          intensity: 2.0,
          range: 15.0,
        ),
      );
      grid.assignLights(lights);

      // 2. Setup Rapier3D PhysicsWorld with 50 rigid bodies
      final world = PhysicsWorldModel();
      for (int i = 0; i < 50; i++) {
        world.addBody(RigidBodyModel(
          id: i + 1,
          type: RigidBodyType.dynamic,
          position: Vec3((i % 10) * 2.0 - 10.0, 10.0 + (i ~/ 10) * 1.0, -20.0),
        ));
      }

      // Step physics for 60 frames (1 second)
      for (int f = 0; f < 60; f++) {
        world.step(1.0 / 60.0);
      }

      // Verify bodies fell under gravity
      expect(world.bodies[1]!.position.y, lessThan(10.0));

      // 3. Build Flat BVH of physics entities
      final bvhEntities = world.bodies.values.map((b) =>
        BvhEntity(b.id, Aabb(b.position - const Vec3(0.5, 0.5, 0.5), b.position + const Vec3(0.5, 0.5, 0.5)))
      ).toList();
      final bvh = BvhBuilder.build(bvhEntities);

      // 4. Frustum culling from camera
      final cam = CameraControllerModel();
      cam.target = const Vec3(0, 0, -20.0);
      cam.distance = 30.0;
      final vp = cam.getProjectionMatrix(16.0 / 9.0).multiply(cam.getViewMatrix());
      final frustum = Frustum.fromViewProjection(vp);
      final visibleEntities = bvh.cullFrustum(frustum);

      expect(visibleEntities.isNotEmpty, isTrue);

      // 5. Submit frame through zero-copy texture pipeline
      final pipeline = ZeroCopyTexturePipelineModel(textureId: 777);
      final framePacket = Uint8List(1920 * 1080 * 4);
      final texId = pipeline.submitFrame(framePacket);

      expect(texId, equals(777));
      expect(pipeline.lastSubmittedSlice, isNotNull);
      expect(pipeline.verifyFrameSentinels(pipeline.lastSubmittedSlice!), isTrue);
    });

    TestHarness.test('test_t4_scenario7_1000_frames_stress_stability', () {
      final world = PhysicsWorldModel();
      for (int i = 0; i < 20; i++) {
        world.addBody(RigidBodyModel(
          id: i + 1,
          type: RigidBodyType.dynamic,
          position: Vec3(i * 2.0 - 20.0, 10.0, -15.0),
        ));
      }

      final pipeline = ZeroCopyTexturePipelineModel(textureId: 101);
      final frameBytes = Uint8List(1024 * 256); // 256KB frame buffer

      // Simulate 1,000 continuous frames
      for (int f = 0; f < 1000; f++) {
        // Step physics
        world.step(1.0 / 60.0);

        // Submit rendered frame
        pipeline.submitFrame(frameBytes);

        // Verify sentinels every 100 frames
        if (f % 100 == 0) {
          expect(pipeline.verifyFrameSentinels(pipeline.lastSubmittedSlice!), isTrue);
        }
      }

      expect(world.totalSteps, equals(1000));
      expect(pipeline.arena.frameIndex, equals(1000));
    });

    TestHarness.test('test_t4_scenario8_bvh_10000_entities_culling_under_2ms', () {
      // Generate 10,000 entities distributed in open world
      final rng = math.Random(1337);
      final entities = List.generate(10000, (i) {
        final x = (rng.nextDouble() - 0.5) * 1000.0;
        final y = (rng.nextDouble() - 0.5) * 100.0;
        final z = (rng.nextDouble() - 0.5) * 1000.0;
        return BvhEntity(
          i,
          Aabb(Vec3(x - 0.5, y - 0.5, z - 0.5), Vec3(x + 0.5, y + 0.5, z + 0.5)),
        );
      });

      // Build 16-bin SAH BVH
      final bvh = BvhBuilder.build(entities);
      expect(bvh.nodes.isNotEmpty, isTrue);

      // Prepare 10 distinct camera viewpoints
      final frustums = List.generate(10, (c) {
        final camPos = Vec3(math.sin(c) * 100.0, 10.0, math.cos(c) * 100.0);
        final vp = Mat4.perspective(1.047, 1.77, 0.1, 500.0)
            .multiply(Mat4.lookAt(camPos, Vec3.zero, Vec3.unitY));
        return Frustum.fromViewProjection(vp);
      });

      // Warmup JIT compiler
      bvh.cullFrustum(frustums[0]);

      // Benchmark hierarchical frustum culling
      final sw = Stopwatch()..start();
      for (final f in frustums) {
        final visible = bvh.cullFrustum(f);
        expect(visible.length, greaterThan(0));
      }
      sw.stop();

      final avgCullTimeMicros = sw.elapsedMicroseconds / frustums.length;
      final avgCullTimeMs = avgCullTimeMicros / 1000.0;

      // Project requirement: BVH frustum culling 10,000 entities in <2ms
      expect(avgCullTimeMs, lessThan(2.0),
          reason: 'BVH frustum culling of 10,000 entities must complete in <2ms, actual: ${avgCullTimeMs.toStringAsFixed(3)}ms');
    });

    TestHarness.test('test_t4_scenario9_1024_dynamic_lights_stress', () {
      final grid = ClusteredForwardGrid();
      // Generate 1,024 dynamic point lights
      final lights = List.generate(
        1024,
        (i) => DynamicLight(
          id: i,
          type: LightType.point,
          position: Vec3(
            (i % 32) * 5.0 - 80.0,
            ((i ~/ 32) % 4) * 3.0,
            -((i ~/ 128) * 10.0 + 1.0),
          ),
          color: const Vec3(1, 1, 1),
          intensity: 1.0,
          range: 8.0,
        ),
      );

      final assigned = grid.assignLights(lights);
      expect(assigned, equals(1024));

      // Evaluate PBR shading with clustered light assignment
      const mat = PbrMaterial(roughness: 0.4, metallic: 0.2);
      final cellLights = grid.getLightsForCluster(8, 4, 10);

      Vec3 accumulatedRadiance = Vec3.zero;
      for (final lightIdx in cellLights.take(16)) {
        final l = lights[lightIdx];
        final rad = PbrRenderer.evaluateCookTorrance(
          material: mat,
          normal: const Vec3(0, 1, 0),
          viewDir: const Vec3(0, 1, 1),
          lightDir: (l.position - const Vec3(0, 0, -20.0)).normalize(),
          lightColor: l.color,
          lightIntensity: l.intensity,
        );
        accumulatedRadiance = accumulatedRadiance + rad;
      }

      expect(accumulatedRadiance.x.isNaN, isFalse);
      expect(accumulatedRadiance.x.isInfinite, isFalse);
    });

    TestHarness.test('test_t4_scenario10_kcc_navigation_dynamic_environment', () {
      final kcc = KinematicCharacterControllerModel(
        autostepHeight: 0.35,
        maxSlopeAngleDegrees: 45.0,
      );

      // Complex obstacle course: stairs + wall
      final courseObstacles = [
        const Aabb(Vec3(0.5, 0.0, -1.0), Vec3(1.5, 0.25, 1.0)), // Step 1: 0.25m (climbable)
        const Aabb(Vec3(1.5, 0.25, -1.0), Vec3(2.5, 0.50, 1.0)), // Step 2: 0.25m step (climbable from step 1)
        const Aabb(Vec3(3.5, 0.0, -1.0), Vec3(4.5, 3.0, 1.0)),  // High wall: 3.0m (unclimbable)
      ];

      // Navigate onto Step 1
      var pos = const Vec3(0, 0, 0);
      pos = kcc.move(currentPos: pos, desiredDisplacement: const Vec3(1.0, 0, 0), obstacles: courseObstacles);
      expect(pos.y, greaterThan(0.24));

      // Navigate onto Step 2
      pos = kcc.move(currentPos: pos, desiredDisplacement: const Vec3(1.0, 0, 0), obstacles: courseObstacles);
      expect(pos.y, greaterThan(0.49));

      // Attempt to walk through 3.0m wall -> blocked / slide
      pos = kcc.move(currentPos: pos, desiredDisplacement: const Vec3(2.0, 0, 0), obstacles: courseObstacles);
      expect(pos.y, lessThan(2.0), reason: '3.0m wall must not be autostepped');

      // Verify Editor Outliner tracks KCC entity
      final shell = EditorShellModel();
      shell.entities.add(SceneEntityModel(
        id: 99,
        name: 'Hero Character',
        position: pos,
      ));
      shell.selectEntity(99);
      expect(shell.selectedEntity!.name, equals('Hero Character'));
      expect(shell.selectedEntity!.position, equals(pos));
    });
  });
}
