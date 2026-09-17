import '../../packages/fluorescent_core/lib/src/resources/resources.dart';
import 'e2e_test_harness.dart';

void defineTests() {
  group('AC 4 & Pillar 4: Resource Manager Reference Counting & GPU VRAM Management', () {
    late ResourceManager resourceManager;

    setUp(() {
      resourceManager = ResourceManager(
        maxMemoryBudget: 64 * 1024 * 1024, // 64 MB
        enforceBudget: true,
      );
    });

    test('E2E-AC4-001: Loads mock texture, increments ref count, and frees on destroy', () async {
      expect(resourceManager.totalGpuMemoryUsed, equals(0));
      expect(resourceManager.cachedResourceCount, equals(0));

      // 1. Load mock texture
      bool onDisposeCallbackFired = false;
      final tex1 = await resourceManager.loadMockTexture(
        'mock_albedo',
        width: 512,
        height: 512,
        format: 'rgba8unorm',
        onDispose: (_) => onDisposeCallbackFired = true,
      );

      // Verify initial ref count and memory tracking (512x512x4 = 1,048,576 bytes)
      expect(tex1.id, equals('mock_albedo'));
      expect(tex1.refCount, equals(1));
      expect(tex1.isDisposed, isFalse);
      expect(tex1.byteSize, equals(1048576));
      expect(resourceManager.totalGpuMemoryUsed, equals(1048576));
      expect(resourceManager.isCached('mock_albedo'), isTrue);

      // 2. Increment reference count via second loadMockTexture / acquire
      final tex2 = await resourceManager.loadMockTexture('mock_albedo');
      expect(identical(tex1, tex2), isTrue);
      expect(tex1.refCount, equals(2));
      // Memory should not double for shared reference
      expect(resourceManager.totalGpuMemoryUsed, equals(1048576));

      // 3. First release decrements refCount without destroying
      resourceManager.release(tex1);
      expect(tex1.refCount, equals(1));
      expect(tex1.isDisposed, isFalse);
      expect(resourceManager.totalGpuMemoryUsed, equals(1048576));
      expect(resourceManager.isCached('mock_albedo'), isTrue);

      // 4. Second release brings refCount to 0 -> destroys and frees GPU memory
      resourceManager.release(tex2);
      expect(tex1.refCount, equals(0));
      expect(tex1.isDisposed, isTrue);
      expect(onDisposeCallbackFired, isTrue);

      // VRAM fully reclaimed
      expect(resourceManager.totalGpuMemoryUsed, equals(0));
      expect(resourceManager.cachedResourceCount, equals(0));
      expect(resourceManager.isCached('mock_albedo'), isFalse);
    });

    test('E2E-AC4-002: Accessing or retaining disposed resources throws StateError', () async {
      final tex = await resourceManager.loadMockTexture('disposable_texture', width: 64, height: 64);
      expect(tex.refCount, equals(1));

      resourceManager.release(tex);
      expect(tex.isDisposed, isTrue);

      // Retain on disposed resource throws StateError
      bool retainThrew = false;
      try {
        tex.retain();
      } catch (e) {
        if (e is StateError) retainThrew = true;
      }
      expect(retainThrew, isTrue);

      // Release on disposed resource throws StateError
      bool releaseThrew = false;
      try {
        tex.release();
      } catch (e) {
        if (e is StateError) releaseThrew = true;
      }
      expect(releaseThrew, isTrue);
    });

    test('E2E-AC4-003: Cascading release clears child texture references when material is destroyed', () async {
      final diffuse = await resourceManager.loadMockTexture('mat_diffuse', width: 256, height: 256);
      final normal = await resourceManager.loadMockTexture('mat_normal', width: 256, height: 256);

      // Both textures initially have refCount = 1
      expect(diffuse.refCount, equals(1));
      expect(normal.refCount, equals(1));

      // Create material and retain textures inside it
      final material = resourceManager.acquire<MaterialResource>('pbr_material', () {
        return MaterialResource(
          id: 'pbr_material',
          shaderId: 'pbr_shader',
          textures: {
            'diffuse': diffuse,
            'normal': normal,
          },
        );
      });

      expect(material.refCount, equals(1));
      expect(diffuse.refCount, equals(2));
      expect(normal.refCount, equals(2));

      // Release top-level references held by caller
      resourceManager.release(diffuse);
      resourceManager.release(normal);
      expect(diffuse.refCount, equals(1));
      expect(normal.refCount, equals(1));
      expect(diffuse.isDisposed, isFalse);
      expect(normal.isDisposed, isFalse);

      // Destroy material -> triggers cascading release on attached textures
      resourceManager.release(material);
      expect(material.isDisposed, isTrue);
      expect(diffuse.isDisposed, isTrue);
      expect(normal.isDisposed, isTrue);

      // All VRAM completely freed
      expect(resourceManager.totalGpuMemoryUsed, equals(0));
      expect(resourceManager.cachedResourceCount, equals(0));
    });

    test('E2E-AC4-004: GPU memory budget enforcement prevents allocation overflow', () {
      final strictManager = ResourceManager(
        maxMemoryBudget: 2 * 1024 * 1024, // 2 MB budget
        enforceBudget: true,
      );

      // Allocate first 1 MB texture (succeeds)
      final tex1 = strictManager.loadMockTextureSync('tex_1mb_a', width: 512, height: 512);
      expect(tex1.byteSize, equals(1048576));
      expect(strictManager.totalGpuMemoryUsed, equals(1048576));

      // Allocate second 1 MB texture (succeeds, total = 2 MB)
      final tex2 = strictManager.loadMockTextureSync('tex_1mb_b', width: 512, height: 512);
      expect(tex2.byteSize, equals(1048576));
      expect(strictManager.totalGpuMemoryUsed, equals(2097152));
      expect(strictManager.remainingMemoryBudget, equals(0));

      // Allocate third 1 MB texture -> exceeds budget -> throws GpuMemoryBudgetExceededException
      bool budgetExceeded = false;
      try {
        strictManager.loadMockTextureSync('tex_1mb_c', width: 512, height: 512);
      } catch (e) {
        if (e is GpuMemoryBudgetExceededException) {
          budgetExceeded = true;
          expect(e.requiredBytes, equals(1048576));
          expect(e.currentUsage, equals(2097152));
          expect(e.maxBudget, equals(2097152));
        }
      }
      expect(budgetExceeded, isTrue);
    });
  });
}

Future<void> main() async {
  await runSuite('AC 4 & Pillar 4: Resource Manager Reference Counting & GPU VRAM Management', defineTests);
}
