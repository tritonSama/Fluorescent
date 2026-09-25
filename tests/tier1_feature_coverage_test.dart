// tests/tier1_feature_coverage_test.dart
//
// Tier 1: Feature Coverage (>=5 tests per feature)
// Validates each feature in isolation:
// - Phase 1: Allocators, Zero-Copy Buffers, FFI Bridge, Desktop Editor
// - Phase 2: PBR & Shadows, Clustered Forward+, BVH Spatial Partitioning, Rapier3D Physics, Desktop Viewport

import 'dart:math' as math;
import 'dart:typed_data';
import 'e2e_test_harness.dart';
import 'fluorite_bridge_model.dart';

void registerTier1Tests() {
  // ===========================================================================
  // PHASE 1 FEATURES
  // ===========================================================================

  TestHarness.group('Tier 1 - Feature 1: Custom Memory Allocators', () {
    TestHarness.test('test_t1_f1_arena_alloc_slices', () {
      final arena = ArenaAllocatorModel(1024 * 1024);
      final slice1 = arena.allocSlice(256, 0x11);
      final slice2 = arena.allocSlice(512, 0x22);

      expect(slice1.length, equals(256));
      expect(slice2.length, equals(512));
      expect(slice1[0], equals(0x11));
      expect(slice1[255], equals(0x11));
      expect(slice2[0], equals(0x22));
      expect(slice2[511], equals(0x22));
      expect(arena.allocatedBytes, greaterThanOrEqualTo(256 + 512));
      expect(arena.allocationCount, equals(2));
    });

    TestHarness.test('test_t1_f1_arena_bulk_reset', () {
      final arena = ArenaAllocatorModel(1024);
      arena.allocSlice(512, 0xAA);
      expect(arena.allocatedBytes, greaterThanOrEqualTo(512));

      arena.reset();
      expect(arena.allocatedBytes, equals(0));
      expect(arena.allocationCount, equals(0));

      final sliceAfter = arena.allocSlice(256, 0xBB);
      expect(sliceAfter.length, equals(256));
      expect(sliceAfter[0], equals(0xBB));
      expect(arena.allocatedBytes, greaterThanOrEqualTo(256));
    });

    TestHarness.test('test_t1_f1_arena_alignment_padding', () {
      final arena = ArenaAllocatorModel(1024 * 1024);
      final alignments = [1, 2, 4, 8, 16, 32, 64];

      for (final align in alignments) {
        final addr = arena.allocRaw(17, align);
        expect(addr % align, equals(0),
            reason: 'Address 0x${addr.toRadixString(16)} must be aligned to $align bytes');
      }
    });

    TestHarness.test('test_t1_f1_frame_allocator_ping_pong', () {
      final frameAlloc = DoubleBufferedFrameAllocatorModel(64 * 1024);
      expect(frameAlloc.frameIndex, equals(0));

      final frame0Slice = frameAlloc.currentArena.allocSlice(1024, 0x01);
      expect(frame0Slice[0], equals(0x01));

      frameAlloc.swapBuffers();
      expect(frameAlloc.frameIndex, equals(1));
      expect(frameAlloc.currentArena.allocatedBytes, equals(0));
      expect(frameAlloc.previousArena.allocatedBytes, greaterThanOrEqualTo(1024));

      frameAlloc.swapBuffers();
      expect(frameAlloc.frameIndex, equals(2));
      expect(frameAlloc.currentArena.allocatedBytes, equals(0));
    });

    TestHarness.test('test_t1_f1_allocator_metrics_tracking', () {
      final arena = ArenaAllocatorModel(4096);
      expect(arena.capacityBytes, equals(4096));
      expect(arena.allocatedBytes, equals(0));
      expect(arena.remainingBytes, equals(4096));

      arena.allocSlice(1024, 0x00);
      expect(arena.allocatedBytes, greaterThanOrEqualTo(1024));
      expect(arena.remainingBytes, lessThanOrEqualTo(3072));
      expect(arena.peakUsage, equals(arena.allocatedBytes));
    });
  });

  TestHarness.group('Tier 1 - Feature 2: Zero-Copy Continuous Buffers', () {
    TestHarness.test('test_t1_f2_1mb_buffer_allocation', () {
      const size = 1024 * 1024;
      final buf = allocateEngineBuffer(size);
      expect(buf.length, equals(size));
      expect(buf[0], equals(0xAA));
      expect(buf[size - 1], equals(0x55));
    });

    TestHarness.test('test_t1_f2_sentinel_verification', () {
      final validBuf = allocateEngineBuffer(1024);
      expect(verifyBufferSentinels(validBuf), isTrue);

      final invalidBuf = Uint8List(1024);
      expect(verifyBufferSentinels(invalidBuf), isFalse);
    });

    TestHarness.test('test_t1_f2_in_place_mutation', () {
      final buf = allocateEngineBuffer(1024);
      writeBufferPattern(buf, 0x77);
      expect(buf[10], equals(0x77));
      expect(buf[500], equals(0x77));
    });

    TestHarness.test('test_t1_f2_pointer_address_sharing', () {
      final handle = SharedFrameBufferModel(4096, baseAddr: 0x40000000);
      expect(handle.ptrAddress, equals(0x40000000));
      expect(handle.ptrAddress % 64, equals(0));
    });

    TestHarness.test('test_t1_f2_typed_data_view_mapping', () {
      final handle = SharedFrameBufferModel(256);
      final view = Uint8List.view(handle.data.buffer);
      expect(view.length, equals(256));
      view[10] = 0x42;
      expect(handle.readByte(10), equals(0x42));
    });
  });

  TestHarness.group('Tier 1 - Feature 3: Zero-Copy FFI Bridge', () {
    TestHarness.test('test_t1_f3_start_engine_lifecycle', () async {
      final controller = EngineControllerModel();
      expect(controller.state, equals(EngineState.uninitialized));

      await controller.startEngine(config: null);
      expect(controller.state, equals(EngineState.running));
      expect(controller.status, isNotNull);
      expect(controller.status!.isInitialized, isTrue);
      expect(controller.status!.coreVersion, equals('0.1.0'));
      expect(controller.status!.allocatorName, equals('FluoriteArenaAllocator_v1'));
    });

    TestHarness.test('test_t1_f3_allocate_engine_buffer', () {
      const oneMb = 1024 * 1024;
      final buf = allocateEngineBuffer(oneMb);
      expect(buf.length, equals(oneMb));
      expect(verifyBufferSentinels(buf), isTrue);
    });

    TestHarness.test('test_t1_f3_get_engine_status', () async {
      final controller = EngineControllerModel();
      await controller.startEngine(config: null);
      await controller.allocate1MB();

      final status = controller.status!;
      expect(status.arenaAllocatedBytes, equals(1024 * 1024));
      expect(status.arenaCapacityBytes, greaterThan(status.arenaAllocatedBytes));
    });

    TestHarness.test('test_t1_f3_verify_buffer_sentinels', () {
      final validBuf = allocateEngineBuffer(1024);
      expect(verifyBufferSentinels(validBuf), isTrue);

      final corruptHeader = allocateEngineBuffer(1024);
      corruptHeader[0] = 0x00;
      expect(verifyBufferSentinels(corruptHeader), isFalse);

      final corruptFooter = allocateEngineBuffer(1024);
      corruptFooter[1023] = 0x00;
      expect(verifyBufferSentinels(corruptFooter), isFalse);
    });

    TestHarness.test('test_t1_f3_shared_frame_buffer_handle', () {
      final handle = SharedFrameBufferModel(256);
      expect(handle.len, equals(256));
      expect(handle.readByte(0), equals(0xDE));
      expect(handle.readByte(1), equals(0xAD));

      handle.writeByte(100, 0x99);
      expect(handle.readByte(100), equals(0x99));
    });
  });

  TestHarness.group('Tier 1 - Feature 4: Flutter Desktop Editor & Controller', () {
    TestHarness.test('test_t1_f4_editor_controller_initial_state', () {
      final controller = EngineControllerModel();
      expect(controller.state, equals(EngineState.uninitialized));
      expect(controller.activeBuffer, isNull);
      expect(controller.allocationLatencyMicros, equals(0));
      expect(controller.status, isNull);
    });

    TestHarness.test('test_t1_f4_editor_controller_start_engine', () async {
      final controller = EngineControllerModel();
      await controller.startEngine(config: null);
      expect(controller.state, equals(EngineState.running));
      expect(controller.status!.isInitialized, isTrue);
    });

    TestHarness.test('test_t1_f4_editor_controller_allocate_1mb', () async {
      final controller = EngineControllerModel();
      final buf = await controller.allocate1MB();

      expect(controller.state, equals(EngineState.running));
      expect(controller.activeBuffer, isNotNull);
      expect(buf.length, equals(1024 * 1024));
      expect(controller.allocationLatencyMicros, greaterThanOrEqualTo(0));
      expect(verifyBufferSentinels(buf), isTrue);
    });

    TestHarness.test('test_t1_f4_editor_controller_reset', () async {
      final controller = EngineControllerModel();
      await controller.startEngine(config: null);
      await controller.allocate1MB();

      controller.reset();
      expect(controller.state, equals(EngineState.uninitialized));
      expect(controller.activeBuffer, isNull);
      expect(controller.allocationLatencyMicros, equals(0));
    });

    TestHarness.test('test_t1_f4_hex_memory_inspector_formatting', () {
      final buffer = allocateEngineBuffer(64);
      final lines = formatHexInspector(buffer, offset: 0, length: 64);

      expect(lines.length, equals(4));
      expect(lines[0].contains('AA'), isTrue);
    });
  });

  // ===========================================================================
  // PHASE 2 FEATURES (WAVE 1)
  // ===========================================================================

  // Feature 5: PBR Metallic-Roughness BRDF & Directional Shadows
  TestHarness.group('Tier 1 - Feature 5: PBR & Directional Shadows', () {
    TestHarness.test('test_t1_f5_pbr_cook_torrance_brdf_evaluation', () {
      const mat = PbrMaterial(
        baseColor: Vec4(1.0, 0.0, 0.0, 1.0),
        metallic: 0.2,
        roughness: 0.4,
      );
      final radiance = PbrRenderer.evaluateCookTorrance(
        material: mat,
        normal: const Vec3(0, 1, 0),
        viewDir: const Vec3(0, 1, 1),
        lightDir: const Vec3(0, 1, 1),
        lightColor: const Vec3(1, 1, 1),
        lightIntensity: 1.0,
      );

      expect(radiance.x, greaterThan(0.0), reason: 'PBR red component must be illuminated');
      expect(radiance.y, greaterThanOrEqualTo(0.0));
      expect(radiance.z, greaterThanOrEqualTo(0.0));
    });

    TestHarness.test('test_t1_f5_pbr_metallic_vs_dielectric_fresnel', () {
      const dielectric = PbrMaterial(metallic: 0.0, roughness: 0.5, baseColor: Vec4(0.8, 0.8, 0.8, 1.0));
      const metal = PbrMaterial(metallic: 1.0, roughness: 0.5, baseColor: Vec4(0.8, 0.8, 0.8, 1.0));

      final outDielectric = PbrRenderer.evaluateCookTorrance(
        material: dielectric,
        normal: const Vec3(0, 1, 0),
        viewDir: const Vec3(0, 1, 0.5),
        lightDir: const Vec3(0, 1, -0.5),
        lightColor: const Vec3(1, 1, 1),
      );

      final outMetal = PbrRenderer.evaluateCookTorrance(
        material: metal,
        normal: const Vec3(0, 1, 0),
        viewDir: const Vec3(0, 1, 0.5),
        lightDir: const Vec3(0, 1, -0.5),
        lightColor: const Vec3(1, 1, 1),
      );

      expect(outDielectric.length, greaterThan(0.0));
      expect(outMetal.length, greaterThan(0.0));
    });

    TestHarness.test('test_t1_f5_directional_shadow_ortho_projection', () {
      const bounds = Aabb(Vec3(-50, -10, -50), Vec3(50, 40, 50));
      final lightOrtho = Mat4.orthographic(-50, 50, -50, 50, 0.1, 200.0);
      final testPt = bounds.center;
      final projPt = lightOrtho.transformPoint(testPt);

      expect(projPt.x, greaterThanOrEqualTo(-1.0));
      expect(projPt.x, lessThanOrEqualTo(1.0));
      expect(projPt.y, greaterThanOrEqualTo(-1.0));
      expect(projPt.y, lessThanOrEqualTo(1.0));
    });

    TestHarness.test('test_t1_f5_shadow_texel_snapping', () {
      const lightPos = Vec3(12.345, 6.789, 5.0);
      const res = 2048.0;
      const orthoSize = 100.0;
      final snapped = PbrRenderer.snapToTexel(lightPos, res, orthoSize);

      final texelSize = (2.0 * orthoSize) / res;
      final remX = (snapped.x / texelSize) - (snapped.x / texelSize).roundToDouble();
      final remY = (snapped.y / texelSize) - (snapped.y / texelSize).roundToDouble();

      expect(remX.abs(), lessThan(1e-4), reason: 'X coordinate must snap precisely to texel grid');
      expect(remY.abs(), lessThan(1e-4), reason: 'Y coordinate must snap precisely to texel grid');
    });

    TestHarness.test('test_t1_f5_pcf_shadow_depth_filtering_3x3', () {
      final depths = [0.4, 0.4, 0.4, 0.6, 0.6, 0.6, 0.4, 0.4, 0.4];
      final shadow = PbrRenderer.evaluatePcfShadow(
        currentDepth: 0.5,
        depthBias: 0.005,
        shadowMapDepths: depths,
      );

      // 3 of 9 samples pass (depth 0.6 >= 0.495)
      expect(shadow, closeTo(3.0 / 9.0, 0.01));
    });
  });

  // Feature 6: Clustered Forward+ Light Assignment
  TestHarness.group('Tier 1 - Feature 6: Clustered Forward+ Light Assignment', () {
    TestHarness.test('test_t1_f6_cluster_grid_3456_cells_subdivision', () {
      final grid = ClusteredForwardGrid();
      expect(grid.clusterCount, equals(3456));
      expect(ClusteredForwardGrid.clustersX, equals(16));
      expect(ClusteredForwardGrid.clustersY, equals(9));
      expect(ClusteredForwardGrid.clustersZ, equals(24));
    });

    TestHarness.test('test_t1_f6_logarithmic_depth_slicing', () {
      final grid = ClusteredForwardGrid(nearPlane: 0.1, farPlane: 1000.0);
      final z0Near = grid.getDepthSliceNear(0);
      final zLastFar = grid.getDepthSliceFar(23);

      expect(z0Near, closeTo(0.1, 0.01));
      expect(zLastFar, closeTo(1000.0, 0.1));
      expect(grid.getDepthSliceNear(12), greaterThan(grid.getDepthSliceNear(0)));
    });

    TestHarness.test('test_t1_f6_point_light_cluster_sphere_culling', () {
      final grid = ClusteredForwardGrid();
      final lights = [
        const DynamicLight(
          id: 1,
          type: LightType.point,
          position: Vec3(0, 0, -25.0),
          range: 5.0,
        ),
      ];

      final assignedCount = grid.assignLights(lights);
      expect(assignedCount, equals(1));
    });

    TestHarness.test('test_t1_f6_directional_light_global_broadcast', () {
      final grid = ClusteredForwardGrid();
      final lights = [
        const DynamicLight(
          id: 1,
          type: LightType.directional,
          position: Vec3(0, 100, 0),
          direction: Vec3(0, -1, 0),
        ),
      ];

      grid.assignLights(lights);
      final cell0Lights = grid.getLightsForCluster(0, 0, 0);
      final cellEndLights = grid.getLightsForCluster(15, 8, 23);

      expect(cell0Lights.contains(0), isTrue);
      expect(cellEndLights.contains(0), isTrue);
    });

    TestHarness.test('test_t1_f6_dynamic_lights_1024_capacity', () {
      final grid = ClusteredForwardGrid();
      final lights = List.generate(
        1024,
        (i) => DynamicLight(
          id: i,
          type: LightType.point,
          position: Vec3(i % 20 - 10, 0, -50.0),
          range: 10.0,
        ),
      );

      final assigned = grid.assignLights(lights);
      expect(assigned, equals(1024));
    });
  });

  // Feature 7: BVH Spatial Partitioning & Frustum Culling
  TestHarness.group('Tier 1 - Feature 7: BVH Spatial Partitioning & Culling', () {
    TestHarness.test('test_t1_f7_flat_bvh_node_32byte_layout', () {
      const node = FlatBvhNode(
        min: Vec3(-10, -5, -2),
        leftChildOrFirstEntity: 4,
        max: Vec3(10, 5, 2),
        entityCount: 0,
      );
      final bytes = node.toBytes();
      expect(bytes.length, equals(32), reason: 'FlatBvhNode must be exactly 32 bytes');

      final floats = Float32List.view(bytes.buffer);
      final uints = Uint32List.view(bytes.buffer);
      expect(floats[0], closeTo(-10.0, 1e-4));
      expect(uints[3], equals(4));
      expect(floats[4], closeTo(10.0, 1e-4));
      expect(uints[7], equals(0));
    });

    TestHarness.test('test_t1_f7_16bin_sah_bvh_construction', () {
      final entities = List.generate(
        64,
        (i) => BvhEntity(
          i,
          Aabb(Vec3(i * 2.0, 0, 0), Vec3(i * 2.0 + 1.0, 1.0, 1.0)),
        ),
      );

      final bvh = BvhBuilder.build(entities);
      expect(bvh.nodes.isNotEmpty, isTrue);
      expect(bvh.nodes[0].min.x, closeTo(0.0, 1e-3));
      expect(bvh.nodes[0].max.x, closeTo(64 * 2.0 - 1.0, 1e-3));
    });

    TestHarness.test('test_t1_f7_simd_slab_raycasting_hit_and_miss', () {
      final entities = [
        const BvhEntity(10, Aabb(Vec3(-1, -1, -11), Vec3(1, 1, -9))),
      ];
      final bvh = BvhBuilder.build(entities);

      final hitRay = Ray(Vec3.zero, const Vec3(0, 0, -1));
      final hit = bvh.raycast(hitRay);
      expect(hit, isNotNull);
      expect(hit!.entityId, equals(10));
      expect(hit.distance, closeTo(9.0, 1e-3));

      final missRay = Ray(Vec3.zero, const Vec3(0, 1, 0));
      final miss = bvh.raycast(missRay);
      expect(miss, isNull);
    });

    TestHarness.test('test_t1_f7_hierarchical_box_frustum_culling', () {
      final frontEntities = List.generate(
        10,
        (i) => BvhEntity(i, Aabb(Vec3(-5, -5, -20 - i * 2.0), Vec3(5, 5, -18 - i * 2.0))),
      );
      final backEntities = List.generate(
        10,
        (i) => BvhEntity(100 + i, Aabb(Vec3(-5, -5, 10 + i * 2.0), Vec3(5, 5, 12 + i * 2.0))),
      );

      final bvh = BvhBuilder.build([...frontEntities, ...backEntities]);
      final vp = Mat4.perspective(1.047, 1.77, 0.1, 100.0)
          .multiply(Mat4.lookAt(Vec3.zero, const Vec3(0, 0, -1), Vec3.unitY));
      final frustum = Frustum.fromViewProjection(vp);

      final culled = bvh.cullFrustum(frustum);
      expect(culled.any((id) => id >= 100), isFalse, reason: 'Entities behind camera must be culled');
      expect(culled.any((id) => id < 10), isTrue, reason: 'Entities in front must be visible');
    });

    TestHarness.test('test_t1_f7_dual_tree_broadphase_collision_pairs', () {
      final entities = [
        const BvhEntity(1, Aabb(Vec3(0, 0, 0), Vec3(1, 1, 1))),
        const BvhEntity(2, Aabb(Vec3(0.5, 0.5, 0.5), Vec3(1.5, 1.5, 1.5))),
        const BvhEntity(3, Aabb(Vec3(100, 100, 100), Vec3(101, 101, 101))),
        const BvhEntity(4, Aabb(Vec3(100.5, 100.5, 100.5), Vec3(101.5, 101.5, 101.5))),
      ];
      final bvh = BvhBuilder.build(entities);
      final pairs = bvh.findBroadphasePairs();

      expect(pairs.any((p) => p.$1 == 1 && p.$2 == 2), isTrue);
      expect(pairs.any((p) => p.$1 == 3 && p.$2 == 4), isTrue);
      expect(pairs.any((p) => p.$1 == 1 && p.$2 == 3), isFalse);
    });
  });

  // Feature 8: Rapier3D Physics Integration & KCC
  TestHarness.group('Tier 1 - Feature 8: Rapier3D Physics & KCC', () {
    TestHarness.test('test_t1_f8_physics_world_rigidbody_lifecycle', () {
      final world = PhysicsWorldModel();
      final body = RigidBodyModel(
        id: 1,
        type: RigidBodyType.dynamic,
        position: const Vec3(0, 10, 0),
        mass: 2.5,
      );
      world.addBody(body);

      expect(world.bodies.containsKey(1), isTrue);
      expect(world.bodies[1]!.type, equals(RigidBodyType.dynamic));
      expect(world.bodies[1]!.position.y, equals(10.0));
    });

    TestHarness.test('test_t1_f8_fixed_60hz_timestep_accumulator', () {
      final world = PhysicsWorldModel();
      final body = RigidBodyModel(
        id: 1,
        type: RigidBodyType.dynamic,
        position: const Vec3(0, 10, 0),
      );
      world.addBody(body);

      // Step with 0.05s (3 steps of 1/60s)
      final steps = world.step(0.05);
      expect(steps, equals(3));
      expect(world.totalSteps, equals(3));
      expect(body.position.y, lessThan(10.0), reason: 'Gravity should lower Y position');
    });

    TestHarness.test('test_t1_f8_continuous_collision_detection_ccd', () {
      final world = PhysicsWorldModel();
      final projectile = RigidBodyModel(
        id: 1,
        type: RigidBodyType.dynamic,
        position: const Vec3(0, 10, 0),
        linearVelocity: const Vec3(0, -600, 0), // 600 m/s
        ccdEnabled: true,
      );
      world.addBody(projectile);

      world.step(1.0 / 60.0);
      expect(projectile.position.y, greaterThanOrEqualTo(0.0), reason: 'CCD must prevent tunneling past ground');
      expect(projectile.position.y, equals(0.0));
    });

    TestHarness.test('test_t1_f8_kinematic_character_controller_autostep', () {
      final kcc = KinematicCharacterControllerModel(autostepHeight: 0.35);
      final obstacles = [
        const Aabb(Vec3(0.5, 0, -1), Vec3(1.5, 0.25, 1)), // 0.25m stair step
      ];

      final newPos = kcc.move(
        currentPos: const Vec3(0, 0, 0),
        desiredDisplacement: const Vec3(1.0, 0, 0),
        obstacles: obstacles,
      );

      expect(newPos.y, greaterThan(0.24), reason: 'Character should autostep on top of 0.25m stair');
    });

    TestHarness.test('test_t1_f8_zero_copy_transform_sync', () {
      final world = PhysicsWorldModel();
      world.addBody(RigidBodyModel(
        id: 1,
        type: RigidBodyType.dynamic,
        position: const Vec3(12.5, 4.2, -8.7),
      ));

      final ecsBuffer = Float32List(64);
      world.syncTransformsToEcs(ecsBuffer, 16);

      expect(ecsBuffer[0], equals(1.0));
      expect(ecsBuffer[12], equals(12.5));
      expect(ecsBuffer[13], closeTo(4.2, 1e-4));
      expect(ecsBuffer[14], closeTo(-8.7, 1e-4));
    });
  });

  // Feature 9: Flutter Desktop 3D Viewport & Inspector
  TestHarness.group('Tier 1 - Feature 9: Flutter Viewport & Inspector', () {
    TestHarness.test('test_t1_f9_dockable_shell_layout_panels', () {
      final shell = EditorShellModel();
      expect(shell.isToolbarVisible, isTrue);
      expect(shell.isOutlinerVisible, isTrue);
      expect(shell.isViewportVisible, isTrue);
      expect(shell.isInspectorVisible, isTrue);
      expect(shell.isDiagnosticsVisible, isTrue);
    });

    TestHarness.test('test_t1_f9_scene_outliner_selection_and_visibility', () {
      final shell = EditorShellModel();
      shell.entities.addAll([
        SceneEntityModel(id: 1, name: 'Main Camera'),
        SceneEntityModel(id: 2, name: 'Sun Light'),
        SceneEntityModel(id: 3, name: 'PBR Sphere'),
      ]);

      shell.selectEntity(3);
      expect(shell.selectedEntityId, equals(3));
      expect(shell.selectedEntity!.name, equals('PBR Sphere'));

      shell.entities[1].isVisible = false;
      expect(shell.entities[1].isVisible, isFalse);
    });

    TestHarness.test('test_t1_f9_entity_inspector_property_cards', () {
      final shell = EditorShellModel();
      shell.entities.add(SceneEntityModel(
        id: 1,
        name: 'Hero Mesh',
        material: const PbrMaterial(metallic: 0.8, roughness: 0.2),
        light: const DynamicLight(id: 10, type: LightType.point, position: Vec3.zero),
        rigidBody: RigidBodyModel(id: 20, type: RigidBodyType.dynamic, position: Vec3.zero),
      ));

      shell.selectEntity(1);
      final cards = shell.getInspectorCards();
      expect(cards.length, equals(4), reason: 'Transform, Material, Light, Physics cards');
      expect(cards.any((c) => c.type == PropertyCardType.pbrMaterial), isTrue);
      expect(cards.any((c) => c.type == PropertyCardType.forwardPlusLight), isTrue);
      expect(cards.any((c) => c.type == PropertyCardType.rapierPhysics), isTrue);
    });

    TestHarness.test('test_t1_f9_camera_controller_orbit_and_flycam', () {
      final cam = CameraControllerModel();
      cam.updateOrbit(deltaYaw: 0.5, deltaPitch: 0.2, deltaDist: 2.0);

      expect(cam.yaw, equals(0.5));
      expect(cam.distance, equals(12.0));
      expect(cam.pitch, closeTo(0.5, 1e-3));

      final viewMat = cam.getViewMatrix();
      expect(viewMat.elements[15], equals(1.0));
    });

    TestHarness.test('test_t1_f9_zero_copy_texture_sharing_pipeline', () {
      final pipeline = ZeroCopyTexturePipelineModel(textureId: 42);
      final frameData = Uint8List(1024);
      frameData.fillRange(0, 1024, 0x33);

      final texId = pipeline.submitFrame(frameData);
      expect(texId, equals(42));
      expect(pipeline.arena.currentArena.allocatedBytes, equals(1024));
      expect(pipeline.lastSubmittedSlice, isNotNull);
      expect(pipeline.verifyFrameSentinels(pipeline.lastSubmittedSlice!), isTrue);
    });
  });
}
