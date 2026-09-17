import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluorescent_core/src/resources/resources.dart';

void main() {
  group('Milestone 2 Acceptance Criterion: Mock Texture Lifecycle', () {
    test(
        'Resource manager loads mock texture, increments ref count on re-acquire, and frees it on destroy',
        () async {
      final rm = ResourceManager(maxMemoryBudget: 1024 * 1024);
      bool gpuFreed = false;

      // 1. Load mock texture
      final tex1 = await rm.loadMockTexture(
        'tex/wood.png',
        width: 128,
        height: 128,
        onDispose: (_) => gpuFreed = true,
      );

      // Verify initial state
      expect(tex1.id, 'tex/wood.png');
      expect(tex1.refCount, 1);
      expect(tex1.byteSize, 128 * 128 * 4); // 65536 bytes
      expect(tex1.isDisposed, false);
      expect(gpuFreed, false);
      expect(rm.totalGpuMemoryUsed, 65536);
      expect(rm.isCached('tex/wood.png'), true);
      expect(rm.cachedResourceCount, 1);

      // 2. Re-acquire the same texture
      final tex2 = await rm.loadMockTexture('tex/wood.png');

      // Verify cache hit and refCount increment
      expect(identical(tex1, tex2), true);
      expect(tex1.refCount, 2);
      expect(rm.totalGpuMemoryUsed, 65536); // No duplicate memory allocation

      // 3. Release first reference
      rm.release(tex1);
      expect(tex1.refCount, 1);
      expect(tex1.isDisposed, false);
      expect(gpuFreed, false);
      expect(rm.isCached('tex/wood.png'), true);
      expect(rm.totalGpuMemoryUsed, 65536);

      // 4. Release final reference
      rm.release(tex2);
      expect(tex1.refCount, 0);
      expect(tex1.isDisposed, true);
      expect(gpuFreed, true);
      expect(rm.isCached('tex/wood.png'), false);
      expect(rm.totalGpuMemoryUsed, 0);
      expect(rm.cachedResourceCount, 0);
    });
  });

  group('Resource Base Class & Intrusive Reference Counting', () {
    test('initial reference count defaults to 1 or custom value', () {
      final texA = TextureResource(id: 't1', width: 16, height: 16);
      expect(texA.refCount, 1);

      final texB = TextureResource(
        id: 't2',
        width: 16,
        height: 16,
        initialRefCount: 3,
      );
      expect(texB.refCount, 3);
    });

    test('retain increments and release decrements refCount', () {
      final res = TextureResource(id: 't', width: 8, height: 8);
      res.retain();
      expect(res.refCount, 2);
      res.retain();
      expect(res.refCount, 3);

      res.release();
      expect(res.refCount, 2);
      expect(res.isDisposed, false);

      res.release();
      expect(res.refCount, 1);
      expect(res.isDisposed, false);

      res.release();
      expect(res.refCount, 0);
      expect(res.isDisposed, true);
    });

    test('operations on disposed resource throw StateError', () {
      final res = TextureResource(id: 't_disposed', width: 4, height: 4);
      res.dispose();
      expect(res.isDisposed, true);
      expect(res.refCount, 0);

      expect(() => res.retain(), throwsStateError);
      expect(() => res.release(), throwsStateError);
      expect(() => res.dispose(), throwsStateError);
    });
  });

  group('TextureResource Byte Size & Formats', () {
    test('computes byte size accurately across formats', () {
      final rgba8 = TextureResource(
        id: 'rgba8',
        width: 64,
        height: 64,
        format: 'rgba8unorm',
      );
      expect(rgba8.byteSize, 64 * 64 * 4);

      final r8 = TextureResource(
        id: 'r8',
        width: 64,
        height: 64,
        format: 'r8unorm',
      );
      expect(r8.byteSize, 64 * 64 * 1);

      final rg8 = TextureResource(
        id: 'rg8',
        width: 64,
        height: 64,
        format: 'rg8unorm',
      );
      expect(rg8.byteSize, 64 * 64 * 2);

      final rgba16f = TextureResource(
        id: 'rgba16f',
        width: 64,
        height: 64,
        format: 'rgba16float',
      );
      expect(rgba16f.byteSize, 64 * 64 * 8);

      final rgba32f = TextureResource(
        id: 'rgba32f',
        width: 64,
        height: 64,
        format: 'rgba32float',
      );
      expect(rgba32f.byteSize, 64 * 64 * 16);
    });

    test('custom byte size overrides format calculation', () {
      final custom = TextureResource(
        id: 'custom',
        width: 10,
        height: 10,
        byteSize: 1000,
      );
      expect(custom.byteSize, 1000);
    });

    test('invokes onDispose callback with resource handle', () {
      TextureResource? disposedTarget;
      final tex = TextureResource(
        id: 'tex_hook',
        width: 32,
        height: 32,
        gpuTextureId: 42,
        onDispose: (res) => disposedTarget = res,
      );
      expect(tex.gpuTextureId, 42);
      tex.dispose();
      expect(disposedTarget, isNotNull);
      expect(disposedTarget!.id, 'tex_hook');
      expect(disposedTarget!.gpuTextureId, 42);
    });
  });

  group('MeshResource Byte Size & Buffer Accounting', () {
    test('computes byte size from counts or typed arrays', () {
      // 100 vertices * 32 bytes + 300 indices * 4 bytes = 3200 + 1200 = 4400
      final meshNoData = MeshResource(
        id: 'mesh1',
        vertexCount: 100,
        indexCount: 300,
      );
      expect(meshNoData.byteSize, 4400);
      expect(meshNoData.isIndexed, true);

      // Explicit TypedData buffers
      final vertexData = Float32List(100 * 8); // 800 floats = 3200 bytes
      final indexData = Uint32List(300); // 300 uints = 1200 bytes
      final meshWithData = MeshResource(
        id: 'mesh2',
        vertexCount: 100,
        indexCount: 300,
        vertexData: vertexData,
        indexData: indexData,
        gpuBufferId: 101,
      );
      expect(meshWithData.byteSize, 4400);
      expect(meshWithData.gpuBufferId, 101);

      // Non-indexed mesh
      final nonIndexed = MeshResource(id: 'non_idx', vertexCount: 50);
      expect(nonIndexed.byteSize, 50 * 32);
      expect(nonIndexed.isIndexed, false);
    });

    test('invokes onDispose callback upon disposal', () {
      bool disposed = false;
      final mesh = MeshResource(
        id: 'mesh_hook',
        vertexCount: 10,
        onDispose: (_) => disposed = true,
      );
      mesh.dispose();
      expect(disposed, true);
    });
  });

  group('MaterialResource Cascading Lifecycle', () {
    test('retains attached textures upon material instantiation', () {
      final tex1 = TextureResource(id: 'tex/albedo.png', width: 64, height: 64);
      final tex2 = TextureResource(id: 'tex/normal.png', width: 64, height: 64);

      expect(tex1.refCount, 1);
      expect(tex2.refCount, 1);

      final mat = MaterialResource(
        id: 'mat/standard',
        shaderId: 'pbr.wgsl',
        textures: {'albedo': tex1, 'normal': tex2},
      );

      // Material creation must increment refCount of attachments
      expect(tex1.refCount, 2);
      expect(tex2.refCount, 2);
      expect(mat.refCount, 1);
      expect(mat.textures.length, 2);
    });

    test('cascading release frees attached textures on material disposal', () {
      bool texFreed = false;
      final tex = TextureResource(
        id: 'tex/roughness.png',
        width: 32,
        height: 32,
        onDispose: (_) => texFreed = true,
      );

      final mat = MaterialResource(
        id: 'mat/metal',
        shaderId: 'pbr.wgsl',
        textures: {'roughness': tex},
      );

      expect(tex.refCount, 2);

      // Release initial external reference, leaving material as sole owner
      tex.release();
      expect(tex.refCount, 1);
      expect(tex.isDisposed, false);
      expect(texFreed, false);

      // Disposing material releases texture, dropping refCount to 0 and freeing it
      mat.dispose();
      expect(mat.isDisposed, true);
      expect(tex.refCount, 0);
      expect(tex.isDisposed, true);
      expect(texFreed, true);
    });

    test('setTexture and removeTexture manage texture reference lifecycle', () {
      final oldTex = TextureResource(id: 'old', width: 16, height: 16);
      final newTex = TextureResource(id: 'new', width: 16, height: 16);

      final mat = MaterialResource(
        id: 'mat/dynamic',
        shaderId: 'simple.wgsl',
        textures: {'slot': oldTex},
      );
      expect(oldTex.refCount, 2);
      expect(newTex.refCount, 1);

      // Replace oldTex with newTex
      mat.setTexture('slot', newTex);
      expect(oldTex.refCount, 1); // Decremented
      expect(newTex.refCount, 2); // Incremented
      expect(identical(mat.getTexture('slot'), newTex), true);

      // Remove texture
      final removed = mat.removeTexture('slot');
      expect(identical(removed, newTex), true);
      expect(newTex.refCount, 1); // Decremented back
      expect(mat.getTexture('slot'), isNull);
    });

    test('uniforms management and access', () {
      final mat = MaterialResource(
        id: 'mat/uniforms',
        shaderId: 'phong.wgsl',
        uniforms: {'roughness': 0.5, 'metallic': 0.0},
      );

      expect(mat.getUniform('roughness'), 0.5);
      expect(mat.getUniform('metallic'), 0.0);

      mat.setUniform('roughness', 0.8);
      expect(mat.getUniform('roughness'), 0.8);

      mat.dispose();
      expect(() => mat.setUniform('roughness', 1.0), throwsStateError);
      expect(() => mat.setTexture('tex', TextureResource(id: 't', width: 4, height: 4)),
          throwsStateError);
    });
  });

  group('ResourceManager Memory Budget Accounting & Cache Operations', () {
    test('tracks memory budget usage and ratio accurately', () {
      final rm = ResourceManager(maxMemoryBudget: 1000);
      expect(rm.totalGpuMemoryUsed, 0);
      expect(rm.remainingMemoryBudget, 1000);
      expect(rm.isOverBudget, false);
      expect(rm.memoryUsageRatio, 0.0);

      // Load 400 bytes
      final res1 = rm.acquire(
        'res1',
        () => TextureResource(id: 'res1', width: 10, height: 10, byteSize: 400),
      );
      expect(rm.totalGpuMemoryUsed, 400);
      expect(rm.remainingMemoryBudget, 600);
      expect(rm.isOverBudget, false);
      expect(rm.memoryUsageRatio, closeTo(0.4, 0.001));

      // Load another 400 bytes
      final res2 = rm.acquire(
        'res2',
        () => TextureResource(id: 'res2', width: 10, height: 10, byteSize: 400),
      );
      expect(rm.totalGpuMemoryUsed, 800);
      expect(rm.remainingMemoryBudget, 200);

      // Load 300 bytes (total 1100, exceeding budget)
      final res3 = rm.acquire(
        'res3',
        () => TextureResource(id: 'res3', width: 10, height: 10, byteSize: 300),
      );
      expect(rm.totalGpuMemoryUsed, 1100);
      expect(rm.remainingMemoryBudget, -100);
      expect(rm.isOverBudget, true);

      // Release resources
      rm.release(res1);
      expect(rm.totalGpuMemoryUsed, 700);
      expect(rm.isOverBudget, false);

      rm.release(res2);
      rm.release(res3);
      expect(rm.totalGpuMemoryUsed, 0);
    });

    test('enforces budget when enforceBudget is true', () {
      final rm = ResourceManager(maxMemoryBudget: 500, enforceBudget: true);

      // 400 bytes fits
      rm.acquire(
        'fits',
        () => TextureResource(id: 'fits', width: 10, height: 10, byteSize: 400),
      );

      // 200 bytes exceeds (400 + 200 > 500)
      expect(
        () => rm.acquire(
          'too_big',
          () => TextureResource(
              id: 'too_big', width: 10, height: 10, byteSize: 200),
        ),
        throwsA(isA<GpuMemoryBudgetExceededException>()),
      );

      // Cache and memory count are unaffected by failed allocation
      expect(rm.totalGpuMemoryUsed, 400);
      expect(rm.isCached('too_big'), false);
    });

    test('acquireAsync loads resource asynchronously', () async {
      final rm = ResourceManager();
      final res = await rm.acquireAsync(
        'async_tex',
        () async => TextureResource(id: 'async_tex', width: 16, height: 16),
      );
      expect(res.id, 'async_tex');
      expect(rm.isCached('async_tex'), true);

      // Re-acquire async returns cached instance
      final res2 = await rm.acquireAsync<TextureResource>(
        'async_tex',
        () async => throw StateError('Should not be called'),
      );
      expect(identical(res, res2), true);
      expect(res.refCount, 2);

      rm.release(res);
      rm.release(res2);
      expect(rm.isCached('async_tex'), false);
    });

    test('releaseById releases resource by identifier', () {
      final rm = ResourceManager();
      final tex = rm.loadMockTextureSync('tex_by_id', width: 16, height: 16);
      expect(rm.isCached('tex_by_id'), true);

      rm.releaseById('tex_by_id');
      expect(tex.isDisposed, true);
      expect(rm.isCached('tex_by_id'), false);
    });

    test('manual register adds resource to cache and tracks memory', () {
      final rm = ResourceManager();
      final tex = TextureResource(id: 'manual', width: 10, height: 10, byteSize: 400);

      rm.register(tex);
      expect(rm.isCached('manual'), true);
      expect(rm.totalGpuMemoryUsed, 400);

      // Duplicate registration throws StateError
      expect(() => rm.register(tex), throwsStateError);

      rm.release(tex);
      expect(rm.totalGpuMemoryUsed, 0);
      expect(rm.isCached('manual'), false);
    });

    test('disposeAll disposes all resources and resets memory counter', () {
      final rm = ResourceManager();
      final tex1 = rm.loadMockTextureSync('tex1', width: 16, height: 16);
      final tex2 = rm.loadMockTextureSync('tex2', width: 16, height: 16);
      final mesh = rm.loadMockMesh('mesh1', vertexCount: 10);

      expect(rm.cachedResourceCount, 3);
      expect(rm.totalGpuMemoryUsed, greaterThan(0));

      rm.disposeAll();

      expect(tex1.isDisposed, true);
      expect(tex2.isDisposed, true);
      expect(mesh.isDisposed, true);
      expect(rm.cachedResourceCount, 0);
      expect(rm.totalGpuMemoryUsed, 0);
      expect(rm.isCached('tex1'), false);
    });

    test('cascading material disposal automatically clears texture from ResourceManager', () {
      final rm = ResourceManager();

      // Load texture through ResourceManager
      final tex = rm.loadMockTextureSync('shared_tex', width: 32, height: 32);
      expect(rm.isCached('shared_tex'), true);
      expect(tex.refCount, 1);

      // Create material that takes texture
      final mat = rm.loadMockMaterial(
        'mat_composite',
        shaderId: 'pbr.wgsl',
        textures: {'albedo': tex},
      );
      expect(mat.refCount, 1);
      expect(tex.refCount, 2); // ResourceManager (1) + Material (1)

      // Release initial texture reference in ResourceManager
      rm.release(tex);
      expect(tex.refCount, 1);
      expect(rm.isCached('shared_tex'), true); // Still cached, held by material

      // Now release the material
      rm.release(mat);
      expect(mat.isDisposed, true);
      expect(tex.isDisposed, true);
      // Texture must be cleared from cache and total GPU memory must drop to 0!
      expect(rm.isCached('shared_tex'), false);
      expect(rm.isCached('mat_composite'), false);
      expect(rm.totalGpuMemoryUsed, 0);
    });

    test('type mismatch on acquire throws StateError', () {
      final rm = ResourceManager();
      rm.loadMockTextureSync('item1', width: 16, height: 16);

      // Attempt to acquire texture with MeshResource type
      expect(
        () => rm.acquire<MeshResource>('item1'),
        throwsStateError,
      );
    });

    test('acquire without loader on uncached resource throws ArgumentError', () {
      final rm = ResourceManager();
      expect(
        () => rm.acquire<TextureResource>('non_existent'),
        throwsArgumentError,
      );
    });
  });
}
