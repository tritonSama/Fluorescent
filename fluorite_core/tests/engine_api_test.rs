use fluorite_core::api::{
    allocate_engine_buffer, get_engine_status, start_engine, verify_buffer_sentinels,
    DEFAULT_ENGINE_FRAME_CAPACITY,
};
use fluorite_core::allocator::{ONE_MB, SENTINEL_FOOTER, SENTINEL_HEADER};

#[test]
fn test_engine_api_lifecycle_and_allocation() {
    // Before start_engine, verify status handles uninitialized or initialized state
    let initial_status = get_engine_status();
    // After start_engine, engine must be initialized
    let status = start_engine();
    assert!(status.is_initialized);
    assert_eq!(status.arena_capacity, DEFAULT_ENGINE_FRAME_CAPACITY);
    assert_eq!(status.status_message, "Fluorite Engine Core Initialized");

    // Status query reflects running engine
    let running_status = get_engine_status();
    assert!(running_status.is_initialized);
    assert_eq!(running_status.arena_capacity, DEFAULT_ENGINE_FRAME_CAPACITY);

    // Buffer allocation and sentinel verification
    let buffer = allocate_engine_buffer(ONE_MB);
    assert_eq!(buffer.len(), ONE_MB);
    assert_eq!(buffer[0], SENTINEL_HEADER);
    assert_eq!(buffer[ONE_MB - 1], SENTINEL_FOOTER);
    assert!(verify_buffer_sentinels(buffer.clone()));

    // SharedFrameBuffer verification
    use fluorite_core::api::SharedFrameBuffer;
    let mut shared_buf = SharedFrameBuffer::new(256);
    assert_eq!(shared_buf.len(), 256);
    assert!(!shared_buf.is_empty());
    assert_ne!(shared_buf.ptr_address(), 0);
    assert_eq!(shared_buf.read_byte(0), 0xDE);
    assert_eq!(shared_buf.read_byte(1), 0xAD);
    assert_eq!(shared_buf.read_byte(2), 0xBE);
    assert_eq!(shared_buf.read_byte(3), 0xEF);
    shared_buf.write_byte(42, 0x77);
    assert_eq!(shared_buf.read_byte(42), 0x77);
}
