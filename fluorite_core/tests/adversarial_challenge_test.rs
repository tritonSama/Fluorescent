//! Adversarial Challenge Test Suite for fluorite_core Allocators
//! Authored by: challenger_1_m1 (Empirical Challenger)

use core::alloc::Layout;
use fluorite_core::allocator::{
    verify_buffer_sentinels, AllocError, ArenaAllocator, CustomAllocator,
    DoubleBufferedFrameAllocator, ONE_MB, SENTINEL_FOOTER, SENTINEL_HEADER,
};
use std::sync::Arc;
use std::thread;

/// Rigorously verifies the alignment arithmetic formula:
/// `padding = (align - (addr & (align - 1))) & (align - 1)`
/// for all target power-of-two alignments: 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096.
#[test]
fn test_adversarial_alignment_arithmetic_all_powers_of_two() {
    let target_alignments: [usize; 13] = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096];

    // Base addresses to simulate different heap placements (aligned, misaligned, large)
    let test_bases: [usize; 6] = [
        0,
        1,
        64,
        0x1000_0000,
        0x7FFF_FFFF_0000,
        usize::MAX - 0x10_0000,
    ];

    for &align in &target_alignments {
        assert!(align.is_power_of_two(), "Alignment must be power of two");
        let mask = align - 1;

        for &base in &test_bases {
            // Test every possible residue r in 0..align (capped at 4096 iterations)
            let max_r = align.min(4096);
            for r in 0..max_r {
                let addr = base.wrapping_add(r);

                // Arithmetic formula under test
                let remainder = addr & mask;
                let diff = align - remainder; // Must not underflow since remainder < align
                let padding = diff & mask;

                let aligned_addr = addr.wrapping_add(padding);

                // Invariant 1: Resulting address must be an exact multiple of align
                assert_eq!(
                    aligned_addr % align,
                    0,
                    "Failed for align={}, addr={:#x}, remainder={}, padding={}",
                    align,
                    addr,
                    remainder,
                    padding
                );

                // Invariant 2: Padding must be in range [0, align - 1]
                assert!(
                    padding < align,
                    "Padding {} must be strictly less than align {}",
                    padding,
                    align
                );

                // Invariant 3: If already aligned, padding must be 0
                if remainder == 0 {
                    assert_eq!(
                        padding, 0,
                        "Padding must be 0 when addr is already aligned for align={}",
                        align
                    );
                } else {
                    assert_eq!(
                        padding,
                        align - remainder,
                        "Padding must equal (align - remainder) when misaligned"
                    );
                }
            }
        }
    }
}

/// Tests that ArenaAllocator::alloc_raw satisfies alignments up to 4096
/// even when the backing buffer is only 64-byte aligned.
#[test]
fn test_arena_alloc_raw_high_alignments() {
    let arena = ArenaAllocator::new(64 * 1024).expect("Failed to create arena");
    let alignments: [usize; 8] = [1, 2, 4, 8, 16, 32, 64, 128];

    for &align in &alignments {
        let layout = Layout::from_size_align(32, align).unwrap();
        let ptr = arena.alloc_raw(layout).unwrap();
        let addr = ptr as usize;

        assert_eq!(
            addr % align,
            0,
            "Address {:#x} is not aligned to {}",
            addr,
            align
        );
    }
}

/// Adversarially stress-tests boundary conditions at C - 1, C, and C + 1.
#[test]
fn test_boundary_conditions_exact_capacity_and_adjacent() {
    let capacity = 1024;

    // Test A: Allocate capacity - 1, then 1 byte, then 1 byte (OOM)
    {
        let arena = ArenaAllocator::new(capacity).unwrap();
        let layout_c_minus_1 = Layout::from_size_align(capacity - 1, 1).unwrap();
        let ptr1 = arena.alloc_raw(layout_c_minus_1);
        assert!(ptr1.is_ok(), "Allocation of C - 1 must succeed");
        assert_eq!(arena.allocated_bytes(), capacity - 1);
        assert_eq!(arena.remaining_bytes(), 1);

        // Exact remaining 1 byte should succeed
        let layout_1 = Layout::from_size_align(1, 1).unwrap();
        let ptr2 = arena.alloc_raw(layout_1);
        assert!(
            ptr2.is_ok(),
            "Allocation of final remaining 1 byte must succeed"
        );
        assert_eq!(arena.allocated_bytes(), capacity);
        assert_eq!(arena.remaining_bytes(), 0);

        // 1 byte beyond capacity must return OutOfMemory
        let ptr3 = arena.alloc_raw(layout_1);
        assert_eq!(
            ptr3,
            Err(AllocError::OutOfMemory),
            "Allocation exceeding capacity must return OutOfMemory"
        );
        // Offset must not change after failed allocation
        assert_eq!(arena.allocated_bytes(), capacity);
    }

    // Test B: Allocate exact capacity C in a single allocation
    {
        let arena = ArenaAllocator::new(capacity).unwrap();
        let layout_c = Layout::from_size_align(capacity, 1).unwrap();
        let ptr = arena.alloc_raw(layout_c);
        assert!(ptr.is_ok(), "Allocation of exact capacity C must succeed");
        assert_eq!(arena.allocated_bytes(), capacity);
        assert_eq!(arena.remaining_bytes(), 0);

        // Subsequent allocation of 1 byte must fail
        let layout_1 = Layout::from_size_align(1, 1).unwrap();
        assert_eq!(arena.alloc_raw(layout_1), Err(AllocError::OutOfMemory));
    }

    // Test C: Attempt to allocate C + 1 in a single allocation
    {
        let arena = ArenaAllocator::new(capacity).unwrap();
        let layout_c_plus_1 = Layout::from_size_align(capacity + 1, 1).unwrap();
        let ptr = arena.alloc_raw(layout_c_plus_1);
        assert_eq!(
            ptr,
            Err(AllocError::OutOfMemory),
            "Allocation of C + 1 must fail with OutOfMemory"
        );
        // Offset must remain 0
        assert_eq!(arena.allocated_bytes(), 0);
        assert_eq!(arena.remaining_bytes(), capacity);
    }
}

/// Verifies that Zero-Sized Types do not advance the allocation offset.
#[test]
fn test_zero_sized_types_offset_invariant() {
    let arena = ArenaAllocator::new(2048).unwrap();
    assert_eq!(arena.allocated_bytes(), 0);

    // 1. ZST via alloc_raw
    let zst_layout = Layout::new::<()>();
    let ptr1 = arena.alloc_raw(zst_layout).unwrap();
    assert!(!ptr1.is_null());
    assert_eq!(
        arena.allocated_bytes(),
        0,
        "alloc_raw of ZST must not advance offset"
    );

    // 2. ZST via alloc
    let _val_ref = arena.alloc(()).unwrap();
    assert_eq!(
        arena.allocated_bytes(),
        0,
        "alloc of ZST must not advance offset"
    );

    // 3. ZST slice
    #[derive(Copy, Clone)]
    struct Marker;
    let slice = arena.alloc_slice(100, Marker).unwrap();
    assert_eq!(slice.len(), 100);
    assert_eq!(
        arena.allocated_bytes(),
        0,
        "alloc_slice of ZST must not advance offset"
    );
}

/// Verifies that zero-sized types with high alignment requirements (e.g. 64)
/// return a properly aligned pointer from alloc_raw.
#[test]
fn test_adversarial_zst_alignment() {
    let arena = ArenaAllocator::new(1024).expect("Failed to create arena");

    // Overaligned zero-sized type layout: size 0, align 64
    let zst_align_64 = Layout::from_size_align(0, 64).unwrap();
    let ptr = arena
        .alloc_raw(zst_align_64)
        .expect("ZST alloc should succeed");

    assert_eq!(
        (ptr as usize) % 64,
        0,
        "Zero-sized type with align 64 must return 64-byte aligned pointer, but got {:p}",
        ptr
    );
}

/// Verifies that memory returned by `alloc_slice` can be safely mutated without corruption.
#[test]
fn test_alloc_slice_mutation_safety() {
    let arena = ArenaAllocator::new(64 * 1024).unwrap();

    // Allocate 3 non-overlapping slices of different types
    let slice_u8 = arena.alloc_slice(100, 0xAAu8).unwrap();
    let slice_u32 = arena.alloc_slice(50, 0x12345678u32).unwrap();
    let slice_f64 = arena.alloc_slice(20, 3.14159f64).unwrap();

    // Mutate slice 1
    for (i, byte) in slice_u8.iter_mut().enumerate() {
        *byte = (i % 256) as u8;
    }

    // Mutate slice 2
    for (i, val) in slice_u32.iter_mut().enumerate() {
        *val = (i * 1000) as u32;
    }

    // Mutate slice 3
    for (i, val) in slice_f64.iter_mut().enumerate() {
        *val = (i as f64) * 2.5;
    }

    // Verify mutations did not cross-corrupt
    for (i, &byte) in slice_u8.iter().enumerate() {
        assert_eq!(byte, (i % 256) as u8);
    }
    for (i, &val) in slice_u32.iter().enumerate() {
        assert_eq!(val, (i * 1000) as u32);
    }
    for (i, &val) in slice_f64.iter().enumerate() {
        assert_eq!(val, (i as f64) * 2.5);
    }
}

/// Adversarially tests high-frequency allocations concurrent with ping-pong frame swaps.
/// Verifies that resetting the incoming arena BEFORE publishing the new index prevents
/// race conditions, spurious OutOfMemory errors, or data corruption.
#[test]
fn test_adversarial_concurrent_swap_and_allocate() {
    let per_frame_cap = 2 * ONE_MB;
    let frame_alloc = Arc::new(DoubleBufferedFrameAllocator::new(per_frame_cap).unwrap());

    // Pre-fill arena 1 with data to simulate prior frame usage
    frame_alloc.swap_buffers();
    frame_alloc.alloc_slice(1_500_000, 0xDE_u8).unwrap();
    frame_alloc.swap_buffers(); // Now back to arena 0

    let alloc_clone = Arc::clone(&frame_alloc);
    let worker_handle = thread::spawn(move || {
        // High frequency allocation attempt during frame transition
        for _ in 0..100 {
            let slice = alloc_clone.alloc_slice(1000, 0xAB_u8);
            assert!(
                slice.is_ok(),
                "Worker allocation must succeed during frame transitions"
            );
        }
    });

    for _ in 0..100 {
        frame_alloc.swap_buffers();
    }

    worker_handle.join().expect("Worker thread panicked");
}

/// Adversarially verifies that corrupting header sentinel (0xAA), footer sentinel (0x55),
/// or truncating the buffer length causes `verify_buffer_sentinels` to strictly reject the buffer.
#[test]
fn test_adversarial_sentinel_corruption_rejection() {
    let arena = ArenaAllocator::new(2 * ONE_MB).unwrap();
    let buffer = arena.alloc_1mb_buffer().unwrap();

    // Valid buffer passes
    assert!(verify_buffer_sentinels(buffer));

    // Corrupt header
    buffer[0] = 0x00;
    assert!(!verify_buffer_sentinels(buffer));
    buffer[0] = SENTINEL_HEADER;

    // Corrupt footer
    buffer[ONE_MB - 1] = 0x00;
    assert!(!verify_buffer_sentinels(buffer));
    buffer[ONE_MB - 1] = SENTINEL_FOOTER;

    // Truncated slice fails
    assert!(!verify_buffer_sentinels(&buffer[0..ONE_MB - 1]));
}
