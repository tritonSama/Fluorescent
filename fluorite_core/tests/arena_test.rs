use core::alloc::Layout;
use fluorite_core::allocator::{
    verify_buffer_sentinels, AllocError, ArenaAllocator, ONE_MB, SENTINEL_FOOTER, SENTINEL_HEADER,
};
use std::sync::Arc;
use std::thread;

#[test]
fn test_alignment_ladder() {
    let arena = ArenaAllocator::new(1024 * 1024).expect("Failed to create arena");
    let alignments = [1, 2, 4, 8, 16, 32, 64];

    for &align in &alignments {
        // Use odd, non-aligned sizes (e.g. 13, 27) to guarantee the bump pointer
        // is deliberately misaligned prior to the next allocation request.
        let odd_size = 17;
        let layout = Layout::from_size_align(odd_size, align)
            .unwrap_or_else(|_| panic!("Failed to create layout for align {}", align));

        let ptr = arena
            .alloc_raw(layout)
            .unwrap_or_else(|_| panic!("Allocation failed for alignment {}", align));

        let addr = ptr as usize;
        assert_eq!(
            addr % align,
            0,
            "Pointer {:p} (addr {:#x}) violates power-of-two alignment requirement {}",
            ptr,
            addr,
            align
        );
    }
}

#[test]
fn test_1mb_buffer_allocation_and_read_write_integrity() {
    let arena = ArenaAllocator::new(2 * ONE_MB).expect("Failed to create arena");

    let buffer = arena
        .alloc_1mb_buffer()
        .expect("Failed to allocate 1MB buffer");

    assert_eq!(buffer.len(), ONE_MB, "Buffer length must be exactly 1MB");
    assert_eq!(
        buffer[0], SENTINEL_HEADER,
        "Buffer header sentinel must be 0xAA"
    );
    assert_eq!(
        buffer[ONE_MB - 1],
        SENTINEL_FOOTER,
        "Buffer footer sentinel must be 0x55"
    );
    assert!(
        verify_buffer_sentinels(buffer),
        "Sentinel verification must pass"
    );

    // Read/write integrity check across the entire buffer
    buffer[0] = 0x12;
    buffer[256_000] = 0x34;
    buffer[500_000] = 0x56;
    buffer[750_000] = 0x78;
    buffer[ONE_MB - 1] = 0x9A;

    assert_eq!(buffer[0], 0x12);
    assert_eq!(buffer[256_000], 0x34);
    assert_eq!(buffer[500_000], 0x56);
    assert_eq!(buffer[750_000], 0x78);
    assert_eq!(buffer[ONE_MB - 1], 0x9A);

    // Restore sentinels and re-verify
    buffer[0] = SENTINEL_HEADER;
    buffer[ONE_MB - 1] = SENTINEL_FOOTER;
    assert!(verify_buffer_sentinels(buffer));
}

#[test]
fn test_capacity_limit_and_out_of_memory() {
    let capacity = 512;
    let arena = ArenaAllocator::new(capacity).expect("Failed to create arena");

    // Allocate 400 bytes
    let layout_400 = Layout::from_size_align(400, 8).unwrap();
    let ptr_1 = arena.alloc_raw(layout_400);
    assert!(ptr_1.is_ok(), "400-byte allocation should succeed");

    // Attempting to allocate 200 bytes should fail because 400 + padding + 200 > 512
    let layout_200 = Layout::from_size_align(200, 8).unwrap();
    let ptr_2 = arena.alloc_raw(layout_200);
    assert_eq!(
        ptr_2,
        Err(AllocError::OutOfMemory),
        "Allocation exceeding capacity must return OutOfMemory"
    );

    // Allocating a huge block should also fail cleanly
    let layout_huge = Layout::from_size_align(1024 * 1024, 64).unwrap();
    let ptr_huge = arena.alloc_raw(layout_huge);
    assert_eq!(ptr_huge, Err(AllocError::OutOfMemory));
}

#[test]
fn test_reset_functionality_and_memory_reuse() {
    let capacity = 1024;
    let arena = ArenaAllocator::new(capacity).expect("Failed to create arena");

    let layout = Layout::from_size_align(512, 16).unwrap();

    let ptr_first = arena
        .alloc_raw(layout)
        .expect("First allocation should succeed");
    assert_eq!(arena.allocated_bytes(), 512);
    assert_eq!(arena.allocation_count(), 1);

    // Reset arena in O(1)
    arena.reset();
    assert_eq!(arena.allocated_bytes(), 0);
    assert_eq!(arena.allocation_count(), 0);
    assert_eq!(arena.remaining_bytes(), capacity);

    // Reallocate post-reset: base address should match, zero fragmentation
    let ptr_second = arena
        .alloc_raw(layout)
        .expect("Allocation post-reset should succeed");
    assert_eq!(
        ptr_first, ptr_second,
        "Post-reset allocation must reuse the initial base address"
    );

    // Can allocate second half to reach full capacity
    let ptr_third = arena
        .alloc_raw(layout)
        .expect("Second half allocation post-reset should succeed");
    assert_ne!(ptr_second, ptr_third);
    assert_eq!(arena.allocated_bytes(), 1024);
}

#[test]
fn test_alloc_slice_typed_safety() {
    let arena = ArenaAllocator::new(64 * 1024).expect("Failed to create arena");

    let count = 256;
    let default_val: u32 = 0xDEADBEEF;
    let slice = arena
        .alloc_slice(count, default_val)
        .expect("Slice allocation failed");

    assert_eq!(slice.len(), count);
    for &elem in slice.iter() {
        assert_eq!(elem, default_val);
    }

    // Mutate slice elements
    for (i, elem) in slice.iter_mut().enumerate() {
        *elem = i as u32;
    }

    for (i, &elem) in slice.iter().enumerate() {
        assert_eq!(elem, i as u32);
    }
}

#[test]
fn test_zero_sized_types() {
    let arena = ArenaAllocator::new(1024).expect("Failed to create arena");

    let zst_layout = Layout::new::<()>();
    let ptr = arena
        .alloc_raw(zst_layout)
        .expect("ZST allocation should succeed");
    assert!(!ptr.is_null());

    // ZST should not advance allocated_bytes
    assert_eq!(arena.allocated_bytes(), 0);
}

#[test]
fn test_metrics_invariants() {
    let capacity = 4096;
    let arena = ArenaAllocator::new(capacity).expect("Failed to create arena");

    assert_eq!(arena.capacity_bytes(), capacity);
    assert_eq!(arena.allocated_bytes(), 0);
    assert_eq!(arena.remaining_bytes(), capacity);
    assert_eq!(arena.allocation_count(), 0);

    let layout = Layout::from_size_align(128, 8).unwrap();
    arena.alloc_raw(layout).unwrap();

    assert_eq!(arena.allocated_bytes(), 128);
    assert_eq!(arena.remaining_bytes(), capacity - 128);
    assert_eq!(arena.allocation_count(), 1);
    assert_eq!(arena.peak_usage_bytes(), 128);

    assert_eq!(
        arena.allocated_bytes() + arena.remaining_bytes(),
        arena.capacity_bytes(),
        "Conservation of memory: allocated + remaining must equal capacity"
    );
}

#[test]
fn test_concurrent_multi_threaded_allocations() {
    let arena = Arc::new(ArenaAllocator::new(4 * ONE_MB).expect("Failed to create arena"));
    let num_threads = 8;
    let allocs_per_thread = 50;
    let alloc_size = 1024;

    let mut handles = Vec::new();

    for thread_id in 0..num_threads {
        let arena_clone = Arc::clone(&arena);
        handles.push(thread::spawn(move || {
            let mut intervals = Vec::new();
            for _ in 0..allocs_per_thread {
                let slice = arena_clone
                    .alloc_slice(alloc_size, thread_id as u8)
                    .expect("Concurrent slice alloc failed");
                let start = slice.as_ptr() as usize;
                let end = start + alloc_size;
                intervals.push((start, end));
            }
            intervals
        }));
    }

    let mut all_intervals = Vec::new();
    for handle in handles {
        let thread_intervals = handle.join().expect("Thread panicked");
        all_intervals.extend(thread_intervals);
    }

    assert_eq!(
        all_intervals.len(),
        num_threads * allocs_per_thread,
        "All thread allocations must complete"
    );

    // Verify non-overlapping intervals across all threads
    all_intervals.sort_by_key(|k| k.0);
    for i in 1..all_intervals.len() {
        let prev_end = all_intervals[i - 1].1;
        let curr_start = all_intervals[i].0;
        assert!(
            curr_start >= prev_end,
            "Concurrent allocation memory overlap detected: interval {} ends at {:#x}, interval {} starts at {:#x}",
            i - 1,
            prev_end,
            i,
            curr_start
        );
    }
}
