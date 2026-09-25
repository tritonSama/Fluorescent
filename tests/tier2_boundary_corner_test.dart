// tests/tier2_boundary_corner_test.dart
//
// Tier 2: Boundary & Corner Cases (>=5 tests per feature)
// Validates extreme edge cases:
// - Phase 1: 0 bytes, 1 byte, exact 1MB, power-of-two boundaries, alignment boundaries 1..64, capacity saturation.
// - Phase 2: 1024+ lights, empty scenes, degenerate bounds, extreme timesteps, gimbal lock, grazing angles.

import 'dart:math' as math;
import 'dart:typed_data';
import 'e2e_test_harness.dart';
import 'fluorite_bridge_model.dart';

void registerTier2Tests() {
  // ===========================================================================
  // PHASE 1 BOUNDARIES
  // ===========================================================================

  TestHarness.group('Tier 2 - Feature 1: Allocator Boundaries', () {
    TestHarness.test('test_t2_f1_alloc_zero_bytes', () {
      final arena = ArenaAllocatorModel(1024);
      final slice = arena.allocSlice(0, 0);
      expect(slice.length, equals(0));
      expect(arena.allocatedBytes, equals(0));

      final addr = arena.allocRaw(0, 8);
      expect(addr, greaterThan(0));
      expect(arena.allocatedBytes, equals(0));
    });

    TestHarness.test('test_t2_f1_alloc_single_byte', () {
      final arena = ArenaAllocatorModel(1024);
      final slice = arena.allocSlice(1, 0xFF);
      expect(slice.length, equals(1));
      expect(slice[0], equals(0xFF));
      expect(arena.allocatedBytes, greaterThanOrEqualTo(1));
    });

    TestHarness.test('test_t2_f1_alloc_exact_capacity', () {
      const cap = 256;
      final arena = ArenaAllocatorModel(cap);
      final addr = arena.allocRaw(cap, 1);
      expect(addr, equals(arena.baseAddress));
      expect(arena.allocatedBytes, equals(cap));
      expect(arena.remainingBytes, equals(0));

      expect(() => arena.allocRaw(1, 1), throwsA());
    });

    TestHarness.test('test_t2_f1_alloc_capacity_overflow', () {
      const cap = 128;
      final arena = ArenaAllocatorModel(cap);
      expect(() => arena.allocRaw(cap + 1, 1), throwsA());
      expect(arena.allocatedBytes, equals(0), reason: 'Failed allocation must not advance offset');
    });

    TestHarness.test('test_t2_f1_alignment_ladder_extremes', () {
      final arena = ArenaAllocatorModel(1024 * 1024);
      final alignments = [1, 2, 4, 8, 16, 32, 64];
      final oddSizes = [3, 7, 13, 19, 31, 47, 63];

      for (int i = 0; i < alignments.length; i++) {
        final align = alignments[i];
        final size = oddSizes[i];
        final addr = arena.allocRaw(size, align);
        expect(addr % align, equals(0),
            reason: 'Address 0x${addr.toRadixString(16)} must align to $align for size $size');
      }
    });

    TestHarness.test('test_t2_f1_repeated_empty_resets', () {
      final frameAlloc = DoubleBufferedFrameAllocatorModel(1024);
      for (int i = 0; i < 20; i++) {
        frameAlloc.swapBuffers();
        expect(frameAlloc.currentArena.allocatedBytes, equals(0));
      }
    });
  });

  TestHarness.group('Tier 2 - Feature 2: Zero-Copy Buffer Boundaries', () {
    TestHarness.test('test_t2_f2_zero_byte_buffer', () {
      final buf = allocateEngineBuffer(0);
      expect(buf.length, equals(0));
      expect(verifyBufferSentinels(buf), isFalse);
    });

    TestHarness.test('test_t2_f2_single_byte_buffer', () {
      final buf = allocateEngineBuffer(1);
      expect(buf.length, equals(1));
      expect(buf[0], equals(0x55));
    });

    TestHarness.test('test_t2_f2_exact_1mb_boundary', () {
      const oneMb = 1024 * 1024;
      final buf = allocateEngineBuffer(oneMb);
      expect(buf.length, equals(oneMb));
      expect(buf[0], equals(0xAA));
      expect(buf[oneMb - 1], equals(0x55));
      expect(buf[oneMb ~/ 2], equals(0));
    });

    TestHarness.test('test_t2_f2_power_of_two_sizes', () {
      for (int power = 1; power <= 20; power++) {
        final size = 1 << power;
        final buf = allocateEngineBuffer(size);
        expect(buf.length, equals(size));
        expect(verifyBufferSentinels(buf), isTrue);
      }
    });

    TestHarness.test('test_t2_f2_alignment_boundary_at_64', () {
      final handle = SharedFrameBufferModel(1024, baseAddr: 0x50000000);
      expect(handle.ptrAddress % 64, equals(0));
    });
  });

  TestHarness.group('Tier 2 - Feature 3: FFI Bridge Boundaries', () {
    TestHarness.test('test_t2_f3_buffer_size_zero', () {
      final buf = allocateEngineBuffer(0);
      expect(buf.isEmpty, isTrue);
    });

    TestHarness.test('test_t2_f3_buffer_size_one', () {
      final buf = allocateEngineBuffer(1);
      expect(buf.length, equals(1));
    });

    TestHarness.test('test_t2_f3_buffer_large_stress', () {
      const size16Mb = 16 * 1024 * 1024;
      final buf = allocateEngineBuffer(size16Mb);
      expect(buf.length, equals(size16Mb));
      expect(verifyBufferSentinels(buf), isTrue);
    });

    TestHarness.test('test_t2_f3_repeated_start_engine', () async {
      final controller = EngineControllerModel();
      await controller.startEngine();
      final status1 = controller.status;

      await controller.startEngine();
      final status2 = controller.status;

      expect(status1!.isInitialized, isTrue);
      expect(status2!.isInitialized, isTrue);
      expect(controller.state, equals(EngineState.running));
    });

    TestHarness.test('test_t2_f3_corrupted_sentinel_rejection', () {
      final buf = allocateEngineBuffer(1024);
      expect(verifyBufferSentinels(buf), isTrue);

      buf[0] = 0xBB;
      expect(verifyBufferSentinels(buf), isFalse);

      buf[0] = 0xAA;
      buf[1023] = 0x66;
      expect(verifyBufferSentinels(buf), isFalse);
    });
  });

  TestHarness.group('Tier 2 - Feature 4: Desktop Editor Boundaries', () {
    TestHarness.test('test_t2_f4_allocate_before_start', () async {
      final controller = EngineControllerModel();
      final buf = await controller.allocate1MB();
      expect(controller.state, equals(EngineState.running));
      expect(buf.length, equals(1024 * 1024));
    });

    TestHarness.test('test_t2_f4_repeated_allocations', () async {
      final controller = EngineControllerModel();
      await controller.startEngine();

      for (int i = 0; i < 5; i++) {
        final buf = await controller.allocate1MB();
        expect(buf.length, equals(1024 * 1024));
      }
    });

    TestHarness.test('test_t2_f4_latency_budget_threshold', () async {
      final controller = EngineControllerModel();
      await controller.startEngine();
      await controller.allocate1MB();

      expect(controller.allocationLatencyMicros, lessThan(500000));
    });

    TestHarness.test('test_t2_f4_hex_viewer_offset_clamping', () {
      final buf = allocateEngineBuffer(64);
      final lines = formatHexInspector(buf, offset: 100, length: 16);
      expect(lines.isEmpty, isTrue);
    });

    TestHarness.test('test_t2_f4_hex_viewer_empty_buffer', () {
      final lines = formatHexInspector(Uint8List(0));
      expect(lines.length, equals(1));
      expect(lines[0], equals('<Empty Buffer>'));
    });
  });

  // ===========================================================================
  // PHASE 2 BOUNDARIES (WAVE 1)
  // ===========================================================================

  // Feature 5: PBR & Shadows Boundaries
  TestHarness.group('Tier 2 - Feature 5: PBR & Shadows Boundaries', () {
    TestHarness.test('test_t2_f5_pbr_roughness_extremes_zero_and_one', () {
      const mirrorMat = PbrMaterial(roughness: 0.0); // Perfect mirror
      const diffuseMat = PbrMaterial(roughness: 1.0); // Rough matte

      final mirrorOut = PbrRenderer.evaluateCookTorrance(
        material: mirrorMat,
        normal: const Vec3(0, 1, 0),
        viewDir: const Vec3(0, 1, 1),
        lightDir: const Vec3(0, 1, 1),
        lightColor: const Vec3(1, 1, 1),
      );

      final diffuseOut = PbrRenderer.evaluateCookTorrance(
        material: diffuseMat,
        normal: const Vec3(0, 1, 0),
        viewDir: const Vec3(0, 1, 1),
        lightDir: const Vec3(0, 1, 1),
        lightColor: const Vec3(1, 1, 1),
      );

      expect(mirrorOut.x.isNaN, isFalse);
      expect(mirrorOut.x.isInfinite, isFalse);
      expect(diffuseOut.x.isNaN, isFalse);
      expect(diffuseOut.x.isInfinite, isFalse);
      expect(mirrorOut.length, greaterThan(0.0));
      expect(diffuseOut.length, greaterThan(0.0));
    });

    TestHarness.test('test_t2_f5_pbr_metallic_extremes_dielectric_and_metal', () {
      const dielectric = PbrMaterial(metallic: 0.0);
      const pureMetal = PbrMaterial(metallic: 1.0);

      final outDielectric = PbrRenderer.evaluateCookTorrance(
        material: dielectric,
        normal: const Vec3(0, 1, 0),
        viewDir: const Vec3(0, 1, 0),
        lightDir: const Vec3(0, 1, 0),
        lightColor: const Vec3(1, 1, 1),
      );

      final outMetal = PbrRenderer.evaluateCookTorrance(
        material: pureMetal,
        normal: const Vec3(0, 1, 0),
        viewDir: const Vec3(0, 1, 0),
        lightDir: const Vec3(0, 1, 0),
        lightColor: const Vec3(1, 1, 1),
      );

      expect(outDielectric.length, greaterThan(0.0));
      expect(outMetal.length, greaterThan(0.0));
    });

    TestHarness.test('test_t2_f5_grazing_angle_ndotv_near_zero', () {
      const mat = PbrMaterial(roughness: 0.5);
      // View direction nearly orthogonal to surface normal (grazing angle)
      final radiance = PbrRenderer.evaluateCookTorrance(
        material: mat,
        normal: const Vec3(0, 1, 0),
        viewDir: const Vec3(1.0, 1e-5, 0.0), // N dot V ~ 1e-5
        lightDir: const Vec3(0, 1, 0),
        lightColor: const Vec3(1, 1, 1),
      );

      expect(radiance.x.isNaN, isFalse, reason: 'Division by zero at grazing angle must be prevented');
      expect(radiance.x.isInfinite, isFalse);
    });

    TestHarness.test('test_t2_f5_light_behind_surface_ndotl_negative', () {
      const mat = PbrMaterial();
      // Light is behind surface: N dot L < 0
      final radiance = PbrRenderer.evaluateCookTorrance(
        material: mat,
        normal: const Vec3(0, 1, 0),
        viewDir: const Vec3(0, 1, 0),
        lightDir: const Vec3(0, -1, 0), // Directly underneath
        lightColor: const Vec3(1, 1, 1),
      );

      expect(radiance.x, equals(0.0), reason: 'Back-facing light must produce zero radiance');
      expect(radiance.y, equals(0.0));
      expect(radiance.z, equals(0.0));
    });

    TestHarness.test('test_t2_f5_shadow_extreme_bias_and_ortho_depth_bounds', () {
      // Huge bias: everything considered in shadow or lit
      final shadow = PbrRenderer.evaluatePcfShadow(
        currentDepth: 0.5,
        depthBias: 10.0,
        shadowMapDepths: [0.1, 0.2, 0.3],
      );
      expect(shadow, equals(1.0), reason: 'Extreme bias causes all samples to pass depth test');
    });
  });

  // Feature 6: Clustered Forward+ Boundaries
  TestHarness.group('Tier 2 - Feature 6: Clustered Forward+ Boundaries', () {
    TestHarness.test('test_t2_f6_empty_scene_zero_lights', () {
      final grid = ClusteredForwardGrid();
      final count = grid.assignLights([]);
      expect(count, equals(0));

      final cellLights = grid.getLightsForCluster(0, 0, 0);
      expect(cellLights.isEmpty, isTrue);
    });

    TestHarness.test('test_t2_f6_exact_1024_lights_saturation', () {
      final grid = ClusteredForwardGrid();
      final lights = List.generate(
        1024,
        (i) => DynamicLight(id: i, type: LightType.point, position: Vec3(0, 0, -10.0 - i * 0.1)),
      );

      final assigned = grid.assignLights(lights);
      expect(assigned, equals(1024));
    });

    TestHarness.test('test_t2_f6_overflow_beyond_1024_lights_graceful_clamping', () {
      final grid = ClusteredForwardGrid();
      final lights = List.generate(
        1200,
        (i) => DynamicLight(id: i, type: LightType.point, position: Vec3(0, 0, -50.0)),
      );

      final assigned = grid.assignLights(lights);
      expect(assigned, equals(1024), reason: 'Light assignments must gracefully clamp to maxDynamicLights (1024)');
    });

    TestHarness.test('test_t2_f6_single_cluster_cell_light_clustering', () {
      final grid = ClusteredForwardGrid();
      // 50 lights all at identical position in world
      final lights = List.generate(
        50,
        (i) => DynamicLight(id: i, type: LightType.point, position: const Vec3(0, 0, -25.0), range: 1.0),
      );

      grid.assignLights(lights);
      // Verify light index array contains the lights
      bool foundClusterWithAll = false;
      for (int z = 0; z < 24; z++) {
        final lightsInCell = grid.getLightsForCluster(8, 4, z);
        if (lightsInCell.length == 50) {
          foundClusterWithAll = true;
          break;
        }
      }
      expect(foundClusterWithAll, isTrue);
    });

    TestHarness.test('test_t2_f6_lights_outside_depth_range_culled', () {
      final grid = ClusteredForwardGrid(nearPlane: 0.1, farPlane: 1000.0);
      final lights = [
        // Behind near plane (z > -0.1)
        const DynamicLight(id: 1, type: LightType.point, position: Vec3(0, 0, 50.0), range: 1.0),
        // Way beyond far plane (z < -1000.0)
        const DynamicLight(id: 2, type: LightType.point, position: Vec3(0, 0, -5000.0), range: 1.0),
      ];

      grid.assignLights(lights);
      final cell0 = grid.getLightsForCluster(0, 0, 0);
      final cellEnd = grid.getLightsForCluster(15, 8, 23);

      expect(cell0.contains(0), isFalse);
      expect(cellEnd.contains(1), isFalse);
    });
  });

  // Feature 7: BVH Spatial Boundaries
  TestHarness.group('Tier 2 - Feature 7: BVH Spatial Boundaries', () {
    TestHarness.test('test_t2_f7_empty_scene_bvh', () {
      final bvh = BvhBuilder.build([]);
      expect(bvh.nodes.length, equals(1));
      expect(bvh.nodes[0].entityCount, equals(0));

      final hit = bvh.raycast(Ray(Vec3.zero, const Vec3(0, 0, -1)));
      expect(hit, isNull);
    });

    TestHarness.test('test_t2_f7_single_entity_bvh', () {
      final bvh = BvhBuilder.build([
        const BvhEntity(42, Aabb(Vec3(-1, -1, -5), Vec3(1, 1, -3))),
      ]);
      expect(bvh.nodes.length, equals(1));
      expect(bvh.nodes[0].isLeaf, isTrue);
      expect(bvh.nodes[0].entityCount, equals(1));

      final hit = bvh.raycast(Ray(Vec3.zero, const Vec3(0, 0, -1)));
      expect(hit, isNotNull);
      expect(hit!.entityId, equals(42));
    });

    TestHarness.test('test_t2_f7_degenerate_zero_volume_aabb', () {
      // Degenerate point entity (min == max)
      const ptBox = Aabb(Vec3(0, 0, -5), Vec3(0, 0, -5));
      expect(ptBox.surfaceArea, equals(0.0));

      final bvh = BvhBuilder.build([const BvhEntity(1, ptBox)]);
      expect(bvh.nodes.isNotEmpty, isTrue);

      final ray = Ray(const Vec3(0, 0, 0), const Vec3(0, 0, -1));
      final hit = bvh.raycast(ray);
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(5.0, 1e-4));
    });

    TestHarness.test('test_t2_f7_coincident_entities_identical_bounds', () {
      final entities = List.generate(
        16,
        (i) => const BvhEntity(100, Aabb(Vec3(0, 0, -10), Vec3(1, 1, -9))),
      );

      final bvh = BvhBuilder.build(entities);
      expect(bvh.nodes.isNotEmpty, isTrue);

      final hit = bvh.raycast(Ray(Vec3.zero, const Vec3(0.5, 0.5, -9.5)));
      expect(hit, isNotNull);
    });

    TestHarness.test('test_t2_f7_raycast_parallel_to_slabs_and_division_by_zero', () {
      const box = Aabb(Vec3(-1, -1, -5), Vec3(1, 1, -3));
      // Ray direction has 0 in X and Y (strictly parallel to X and Y slabs)
      final ray = Ray(const Vec3(0, 0, 0), const Vec3(0, 0, -1));
      final t = ray.intersectAabb(box);

      expect(t, isNotNull);
      expect(t!, closeTo(3.0, 1e-3));

      // Ray origin outside slab on X axis, direction parallel to X
      final missRay = Ray(const Vec3(5.0, 0, 0), const Vec3(0, 0, -1));
      expect(missRay.intersectAabb(box), isNull);
    });
  });

  // Feature 8: Rapier3D Physics Boundaries
  TestHarness.group('Tier 2 - Feature 8: Rapier3D Physics Boundaries', () {
    TestHarness.test('test_t2_f8_zero_timestep_stepping', () {
      final world = PhysicsWorldModel();
      world.addBody(RigidBodyModel(
        id: 1,
        type: RigidBodyType.dynamic,
        position: const Vec3(0, 10, 0),
      ));

      final steps = world.step(0.0);
      expect(steps, equals(0));
      expect(world.bodies[1]!.position.y, equals(10.0));
    });

    TestHarness.test('test_t2_f8_extreme_large_timestep_spiral_prevention', () {
      final world = PhysicsWorldModel();
      world.addBody(RigidBodyModel(
        id: 1,
        type: RigidBodyType.dynamic,
        position: const Vec3(0, 100, 0),
      ));

      // 5.0 seconds timestep: spiral of death prevention should cap at maxSubsteps (4)
      final steps = world.step(5.0);
      expect(steps, equals(PhysicsWorldModel.maxSubsteps));
    });

    TestHarness.test('test_t2_f8_extreme_gravity_and_zero_gravity', () {
      final zeroGWorld = PhysicsWorldModel(gravity: Vec3.zero);
      zeroGWorld.addBody(RigidBodyModel(id: 1, type: RigidBodyType.dynamic, position: const Vec3(0, 10, 0)));
      zeroGWorld.step(1.0 / 60.0);
      expect(zeroGWorld.bodies[1]!.position.y, equals(10.0), reason: 'Zero gravity preserves vertical position');

      final highGWorld = PhysicsWorldModel(gravity: const Vec3(0, -1000.0, 0));
      highGWorld.addBody(RigidBodyModel(id: 1, type: RigidBodyType.dynamic, position: const Vec3(0, 10, 0)));
      highGWorld.step(1.0 / 60.0);
      expect(highGWorld.bodies[1]!.position.y, lessThan(10.0));
    });

    TestHarness.test('test_t2_f8_hypervelocity_projectile_ccd_no_tunneling', () {
      final world = PhysicsWorldModel();
      final bullet = RigidBodyModel(
        id: 1,
        type: RigidBodyType.dynamic,
        position: const Vec3(0, 5, 0),
        linearVelocity: const Vec3(0, -5000.0, 0), // 5,000 m/s
        ccdEnabled: true,
      );
      world.addBody(bullet);

      world.step(1.0 / 60.0);
      expect(bullet.position.y, equals(0.0), reason: 'Hypervelocity projectile clamped at ground by CCD');
    });

    TestHarness.test('test_t2_f8_kcc_steep_slope_unclimbable_sliding', () {
      final kcc = KinematicCharacterControllerModel(autostepHeight: 0.35);
      final highObstacle = [
        const Aabb(Vec3(0.5, 0, -1), Vec3(1.5, 2.0, 1)), // 2.0m wall (> 0.35m)
      ];

      final pos = kcc.move(
        currentPos: const Vec3(0, 0, 0),
        desiredDisplacement: const Vec3(1.0, 0, 0),
        obstacles: highObstacle,
      );

      expect(pos.y, equals(0.0), reason: 'KCC must not autostep walls higher than step height limit');
    });
  });

  // Feature 9: Viewport & Inspector Boundaries
  TestHarness.group('Tier 2 - Feature 9: Viewport & Inspector Boundaries', () {
    TestHarness.test('test_t2_f9_zero_size_viewport_resize', () {
      final cam = CameraControllerModel();
      final proj = cam.getProjectionMatrix(0.0); // Zero aspect
      expect(proj.elements[0].isNaN, isFalse);
    });

    TestHarness.test('test_t2_f9_extreme_aspect_ratios_ultrawide_and_tall', () {
      final cam = CameraControllerModel();
      final ultrawideProj = cam.getProjectionMatrix(32.0 / 9.0);
      final tallProj = cam.getProjectionMatrix(1.0 / 50.0);

      expect(ultrawideProj.elements[0], greaterThan(0.0));
      expect(tallProj.elements[0], greaterThan(0.0));
    });

    TestHarness.test('test_t2_f9_camera_gimbal_lock_pitch_clamping', () {
      final cam = CameraControllerModel();
      // Attempt extreme pitch upwards
      cam.updateOrbit(deltaPitch: 10.0);
      expect(cam.pitch, lessThanOrEqualTo(1.56), reason: 'Pitch must be clamped below 90 degrees to avoid gimbal lock');

      // Attempt extreme pitch downwards
      cam.updateOrbit(deltaPitch: -20.0);
      expect(cam.pitch, greaterThanOrEqualTo(-1.56));
    });

    TestHarness.test('test_t2_f9_inspector_null_or_invalid_entity_selection', () {
      final shell = EditorShellModel();
      shell.selectEntity(null);
      expect(shell.getInspectorCards().isEmpty, isTrue);

      shell.selectEntity(9999);
      expect(shell.getInspectorCards().isEmpty, isTrue);
    });

    TestHarness.test('test_t2_f9_zero_copy_pipeline_oversized_frame_rejection', () {
      final pipeline = ZeroCopyTexturePipelineModel(arenaSize: 1024);
      final hugeData = Uint8List(2048);
      expect(() => pipeline.submitFrame(hugeData), throwsA());
    });
  });
}
