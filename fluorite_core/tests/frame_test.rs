use fluorite_core::allocator::{
    DoubleBufferedFrameAllocator, ONE_MB, SENTINEL_FOOTER, SENTINEL_HEADER,
    verify_buffer_sentinels,
};

#[test]
fn test_frame_allocator_initialization() {
    let capacity = 2 * ONE_MB;
    let frame_alloc = DoubleBufferedFrameAllocator::new(capacity)
        .expect("Failed to create frame allocator");

    assert_eq!(frame_alloc.frame_index(), 0);
    assert_eq!(frame_alloc.current_index(), 0);
    assert_eq!(frame_alloc.allocated_bytes(), 0);
    assert_eq!(frame_alloc.capacity_bytes(), capacity);
    assert_eq!(frame_alloc.remaining_bytes(), capacity);
}

#[test]
fn test_double_buffering_swap_and_isolation() {
    let capacity = 2 * ONE_MB;
    let frame_alloc = DoubleBufferedFrameAllocator::new(capacity)
        .expect("Failed to create frame allocator");

    // Frame 0: allocate a 1MB buffer with sentinels
    let frame_0_buffer = frame_alloc
        .alloc_1mb_buffer()
        .expect("Frame 0 1MB buffer allocation failed");

    assert_eq!(frame_0_buffer[0], SENTINEL_HEADER);
    assert_eq!(frame_0_buffer[ONE_MB - 1], SENTINEL_FOOTER);
    assert!(verify_buffer_sentinels(frame_0_buffer));

    let frame_0_allocated = frame_alloc.allocated_bytes();
    assert!(frame_0_allocated >= ONE_MB);

    // Swap buffers: Frame 0 -> Frame 1
    frame_alloc.swap_buffers();

    assert_eq!(frame_alloc.frame_index(), 1);
    assert_eq!(frame_alloc.current_index(), 1);

    // Active arena is now Arena 1, which has been reset to 0 bytes
    assert_eq!(
        frame_alloc.allocated_bytes(),
        0,
        "Active arena post-swap must be reset to 0"
    );

    // Frame 0 data in previous_arena() must remain completely intact and unmodified!
    assert_eq!(
        frame_alloc.previous_arena().allocated_bytes(),
        frame_0_allocated
    );

    // Frame 1: allocate data in active arena
    let frame_1_slice = frame_alloc
        .alloc_slice(1024, 0x77u8)
        .expect("Frame 1 allocation failed");
    assert_eq!(frame_1_slice[0], 0x77);
    assert_eq!(frame_1_slice[1023], 0x77);

    // Verify isolation: previous arena still holds frame 0's allocation
    assert_eq!(
        frame_alloc.previous_arena().allocated_bytes(),
        frame_0_allocated
    );

    // Swap buffers again: Frame 1 -> Frame 2
    frame_alloc.swap_buffers();
    assert_eq!(frame_alloc.frame_index(), 2);
    assert_eq!(frame_alloc.current_index(), 0);

    // Arena 0 is now active again and has been cleanly reset for Frame 2
    assert_eq!(frame_alloc.allocated_bytes(), 0);

    // Arena 1 data is preserved in previous_arena()
    assert_eq!(
        frame_alloc.previous_arena().allocated_bytes(),
        1024
    );
}

#[test]
fn test_simulated_game_loop_100_frames() {
    let per_frame_capacity = 4 * ONE_MB;
    let frame_alloc = DoubleBufferedFrameAllocator::new(per_frame_capacity)
        .expect("Failed to initialize game frame allocator");

    for frame in 0..100 {
        assert_eq!(frame_alloc.frame_index(), frame as u64);
        assert_eq!(frame_alloc.allocated_bytes(), 0);

        // Simulate ECS & transform allocations during logic tick
        let transforms = frame_alloc
            .alloc_slice(10_000, frame as u32)
            .expect("Transform allocation failed");
        assert_eq!(transforms.len(), 10_000);
        assert_eq!(transforms[0], frame as u32);

        // Simulate transient render command buffer
        let draw_calls = frame_alloc
            .alloc_slice(1000, 0xAA55_u16)
            .expect("Draw call allocation failed");
        assert_eq!(draw_calls.len(), 1000);

        // Swap buffers at frame boundary
        frame_alloc.swap_buffers();

        // Simulate render pipeline consuming previous frame's transforms
        assert!(frame_alloc.previous_arena().allocated_bytes() > 0);
    }

    assert_eq!(frame_alloc.frame_index(), 100);
}
