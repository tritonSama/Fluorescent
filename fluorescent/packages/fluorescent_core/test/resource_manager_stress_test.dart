import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluorescent_core/src/resources/resources.dart';

void main() {
  group('Adversarial ResourceManager Stress Test', () {
    test('Repeated Acquire/Release Loops: 1,500 mock resources across 5 full cycles (15k ops)', () {
      final rm = ResourceManager(maxMemoryBudget: 100 * 1024 * 1024); // 100 MB
      const resourceCount = 1500;
      final loopWatch = Stopwatch()..start();

      for (int cycle = 0; cycle < 5; cycle++) {
        expect(rm.totalGpuMemoryUsed, equals(0));
        expect(rm.cachedResourceCount, equals(0));

        final resources = <Resource>[];

        // 1. Acquire 1,000 textures + 500 meshes
        for (int i = 0; i < 1000; i++) {
          final tex = rm.loadMockTextureSync(
            'tex_c${cycle}_$i',
            width: 32,
            height: 32, // 32*32*4 = 4096 bytes
          );
          expect(tex.refCount, equals(1));
          resources.add(tex);
        }

        for (int i = 0; i < 500; i++) {
          final mesh = rm.loadMockMesh(
            'mesh_c${cycle}_$i',
            vertexCount: 64, // 64*32 = 2048 bytes
          );
          expect(mesh.refCount, equals(1));
          resources.add(mesh);
        }

        expect(rm.cachedResourceCount, equals(resourceCount));
        const expectedCycleBytes = (1000 * 4096) + (500 * 2048); // 4,096,000 + 1,024,000 = 5,120,000 bytes
        expect(rm.totalGpuMemoryUsed, equals(expectedCycleBytes));

        // 2. Re-acquire all 1,500 resources (Cache Hit verification)
        for (int i = 0; i < 1000; i++) {
          final reTex = rm.acquire<TextureResource>('tex_c${cycle}_$i');
          expect(reTex.refCount, equals(2));
        }
        for (int i = 0; i < 500; i++) {
          final reMesh = rm.acquire<MeshResource>('mesh_c${cycle}_$i');
          expect(reMesh.refCount, equals(2));
        }

        // Memory should not have changed on cache hits
        expect(rm.totalGpuMemoryUsed, equals(expectedCycleBytes));
        expect(rm.cachedResourceCount, equals(resourceCount));

        // 3. First release round on all 1,500 resources
        for (final res in resources) {
          rm.release(res);
          expect(res.refCount, equals(1));
          expect(res.isDisposed, isFalse);
        }
        expect(rm.totalGpuMemoryUsed, equals(expectedCycleBytes));
        expect(rm.cachedResourceCount, equals(resourceCount));

        // 4. Second release round: destroys all resources and clears cache
        for (final res in resources) {
          rm.release(res);
          expect(res.refCount, equals(0));
          expect(res.isDisposed, isTrue);
        }

        // Complete reclamation invariant
        expect(rm.totalGpuMemoryUsed, equals(0));
        expect(rm.cachedResourceCount, equals(0));
      }
      loopWatch.stop();

      // ignore: avoid_print
      print('ResourceManager Lifecycle Stress: 5 cycles of 1,500 resources (15,000 ops) '
          'completed in ${loopWatch.elapsedMilliseconds}ms with zero VRAM leaks');
    });

    test('Cascading Material Trees: 500 materials sharing 100 textures with automated disposal', () {
      final rm = ResourceManager(maxMemoryBudget: 50 * 1024 * 1024);

      // 1. Create a shared pool of 100 base textures
      const textureCount = 100;
      final textures = <TextureResource>[];
      for (int i = 0; i < textureCount; i++) {
        final t = rm.loadMockTextureSync('shared_tex_$i', width: 64, height: 64);
        textures.add(t);
      }
      expect(rm.cachedResourceCount, equals(textureCount));
      const texturePoolBytes = textureCount * (64 * 64 * 4); // 1,638,400 bytes
      expect(rm.totalGpuMemoryUsed, equals(texturePoolBytes));

      // 2. Instantiate 500 materials referencing combinations of textures
      const materialCount = 500;
      final materials = <MaterialResource>[];
      for (int i = 0; i < materialCount; i++) {
        final albedo = textures[i % textureCount];
        final normal = textures[(i + 1) % textureCount];

        final mat = rm.loadMockMaterial(
          'mat_$i',
          shaderId: 'pbr.wgsl',
          textures: {'albedo': albedo, 'normal': normal},
        );
        materials.add(mat);
      }

      expect(rm.cachedResourceCount, equals(textureCount + materialCount)); // 600

      // 3. Release initial direct reference from ResourceManager for all 100 textures
      for (final t in textures) {
        rm.release(t);
        // Textures must NOT be disposed because materials still hold them!
        expect(t.isDisposed, isFalse);
        expect(t.refCount, greaterThanOrEqualTo(1));
        expect(rm.isCached(t.id), isTrue);
      }

      // 4. Release materials in batches and observe cascading cleanup
      for (final mat in materials) {
        rm.release(mat);
        expect(mat.isDisposed, isTrue);
      }

      // Invariant: Once all materials are disposed, all textures must be freed from cache!
      for (final t in textures) {
        expect(t.isDisposed, isTrue);
        expect(t.refCount, equals(0));
        expect(rm.isCached(t.id), isFalse);
      }

      expect(rm.cachedResourceCount, equals(0));
      expect(rm.totalGpuMemoryUsed, equals(0));

      // ignore: avoid_print
      print('Cascading Material Stress: 500 materials and 100 textures cleanly reclaimed to 0 bytes');
    });

    test('Dynamic Texture Swapping on Materials Stress', () {
      final rm = ResourceManager();
      final texA = rm.loadMockTextureSync('tex_slot_a', width: 32, height: 32);
      final texB = rm.loadMockTextureSync('tex_slot_b', width: 32, height: 32);

      final mat = rm.loadMockMaterial('swap_mat', shaderId: 'basic.wgsl', textures: {'main': texA});
      expect(texA.refCount, equals(2));
      expect(texB.refCount, equals(1));

      // Swap textures 200 times
      for (int i = 0; i < 200; i++) {
        final nextTex = (i % 2 == 0) ? texB : texA;
        mat.setTexture('main', nextTex);
      }

      // Clean up material
      rm.release(mat);
      expect(mat.isDisposed, isTrue);

      // Clean up standalone textures
      rm.release(texA);
      rm.release(texB);
      expect(texA.isDisposed, isTrue);
      expect(texB.isDisposed, isTrue);
      expect(rm.cachedResourceCount, equals(0));
      expect(rm.totalGpuMemoryUsed, equals(0));
    });

    test('Memory Budget Overflow Enforcement: Strict boundaries & recovery under allocation storm', () {
      const budget = 10 * 1024 * 1024; // 10 MB
      final rm = ResourceManager(maxMemoryBudget: budget, enforceBudget: true);

      // 1. Fill 9 MB with 9 x 1 MB textures
      const oneMb = 1024 * 1024;
      final allocated = <TextureResource>[];
      for (int i = 0; i < 9; i++) {
        final t = rm.acquire<TextureResource>(
          'block_$i',
          () => TextureResource(id: 'block_$i', width: 512, height: 512, byteSize: oneMb),
        );
        allocated.add(t);
      }

      expect(rm.totalGpuMemoryUsed, equals(9 * oneMb));
      expect(rm.remainingMemoryBudget, equals(1 * oneMb));
      expect(rm.isOverBudget, isFalse);

      // 2. Adversarial allocation: Attempt 2 MB allocation (9 MB + 2 MB = 11 MB > 10 MB)
      expect(
        () => rm.acquire<TextureResource>(
          'oversized',
          () => TextureResource(id: 'oversized', width: 512, height: 512, byteSize: 2 * oneMb),
        ),
        throwsA(isA<GpuMemoryBudgetExceededException>()),
      );

      // Verify state integrity after failed allocation
      expect(rm.totalGpuMemoryUsed, equals(9 * oneMb));
      expect(rm.isCached('oversized'), isFalse);
      expect(rm.cachedResourceCount, equals(9));

      // 3. Allocation storm: 100 consecutive failing allocations
      int failedAttempts = 0;
      for (int i = 0; i < 100; i++) {
        try {
          rm.acquire<TextureResource>(
            'storm_$i',
            () => TextureResource(id: 'storm_$i', width: 256, height: 256, byteSize: (1.5 * oneMb).round()),
          );
        } on GpuMemoryBudgetExceededException {
          failedAttempts++;
        }
      }
      expect(failedAttempts, equals(100));
      // Memory must remain strictly at 9 MB
      expect(rm.totalGpuMemoryUsed, equals(9 * oneMb));
      expect(rm.cachedResourceCount, equals(9));

      // 4. Budget Recovery: Free 3 MB (blocks 0, 1, 2)
      rm.release(allocated[0]);
      rm.release(allocated[1]);
      rm.release(allocated[2]);

      expect(rm.totalGpuMemoryUsed, equals(6 * oneMb));
      expect(rm.remainingMemoryBudget, equals(4 * oneMb));

      // 5. Now an allocation of 2 MB succeeds cleanly!
      final recovered = rm.acquire<TextureResource>(
        'recovered_2mb',
        () => TextureResource(id: 'recovered_2mb', width: 512, height: 512, byteSize: 2 * oneMb),
      );
      expect(recovered.isDisposed, isFalse);
      expect(rm.totalGpuMemoryUsed, equals(8 * oneMb));
      expect(rm.isCached('recovered_2mb'), isTrue);

      // Fill remaining 2 MB to reach exact capacity (10 MB)
      final finalBlock = rm.acquire<TextureResource>(
        'final_2mb',
        () => TextureResource(id: 'final_2mb', width: 512, height: 512, byteSize: 2 * oneMb),
      );
      expect(rm.totalGpuMemoryUsed, equals(10 * oneMb));
      expect(rm.remainingMemoryBudget, equals(0));

      // Even 1 single byte more will now be rejected
      expect(
        () => rm.acquire<TextureResource>(
          'one_byte',
          () => TextureResource(id: 'one_byte', width: 1, height: 1, byteSize: 1),
        ),
        throwsA(isA<GpuMemoryBudgetExceededException>()),
      );

      // Clean disposal of everything
      rm.disposeAll();
      expect(rm.totalGpuMemoryUsed, equals(0));
      expect(rm.cachedResourceCount, equals(0));

      // ignore: avoid_print
      print('Memory Budget Enforcement Stress: Successfully repelled 101 illegal allocations '
          'and verified zero-corruption budget recovery');
    });
  });
}
