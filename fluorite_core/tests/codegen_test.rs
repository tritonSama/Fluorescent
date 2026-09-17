//! Automated Codegen & API Contract Verification Test Suite for flutter_rust_bridge v2
//!
//! Validates:
//! 1. flutter_rust_bridge.yaml configuration format, keys, and paths
//! 2. Cargo.toml dependency configuration (flutter_rust_bridge = "2.13.0", cdylib/rlib)
//! 3. Rust API contract in `src/api/engine.rs` (`start_engine`, `allocate_engine_buffer`, `get_engine_status`, `verify_buffer_sentinels`, `SharedFrameBuffer`)
//! 4. Generated C-ABI wire functions in `src/frb_generated.rs`
//! 5. Generated Dart FFI bridge bindings in `fluorite_editor/lib/src/rust/`
//! 6. 1MB zero-copy buffer allocation, sentinel verification, and telemetry reporting

use std::fs;
use std::path::{Path, PathBuf};

use fluorite_core::api::{
    allocate_engine_buffer, get_engine_status, start_engine, verify_buffer_sentinels,
    verify_buffer_sentinels_slice, EngineStatus, SharedFrameBuffer,
    DEFAULT_ENGINE_FRAME_CAPACITY,
};
use fluorite_core::allocator::{ONE_MB, SENTINEL_FOOTER, SENTINEL_HEADER};

fn find_workspace_root() -> PathBuf {
    let mut current = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    for _ in 0..5 {
        if current.join("flutter_rust_bridge.yaml").exists() {
            return current;
        }
        if let Some(parent) = current.parent() {
            current = parent.to_path_buf();
        } else {
            break;
        }
    }
    // Fallback to relative parent
    PathBuf::from("..")
}

#[test]
fn test_flutter_rust_bridge_yaml_configuration() {
    let root = find_workspace_root();
    let config_path = root.join("flutter_rust_bridge.yaml");
    assert!(
        config_path.exists(),
        "flutter_rust_bridge.yaml must exist at {}",
        config_path.display()
    );

    let content = fs::read_to_string(&config_path)
        .expect("Failed to read flutter_rust_bridge.yaml");

    assert!(
        content.contains("rust_root: \"fluorite_core\"") || content.contains("rust_root: fluorite_core"),
        "YAML must specify rust_root pointing to fluorite_core"
    );
    assert!(
        content.contains("rust_input: \"src/api\"") || content.contains("rust_input: src/api"),
        "YAML must specify rust_input pointing to src/api"
    );
    assert!(
        content.contains("dart_output: \"fluorite_editor/lib/src/rust\"")
            || content.contains("dart_output: fluorite_editor/lib/src/rust"),
        "YAML must specify dart_output pointing to fluorite_editor/lib/src/rust"
    );
}

#[test]
fn test_cargo_toml_frb_v2_dependency_and_crate_type() {
    let manifest_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
    let content = fs::read_to_string(&manifest_path)
        .expect("Failed to read Cargo.toml");

    assert!(
        content.contains("flutter_rust_bridge = \"2.13.0\""),
        "Cargo.toml must declare flutter_rust_bridge = \"2.13.0\""
    );
    assert!(
        content.contains("\"cdylib\""),
        "Cargo.toml crate-type must include cdylib"
    );
    assert!(
        content.contains("\"rlib\""),
        "Cargo.toml crate-type must include rlib"
    );
}

#[test]
fn test_api_contract_annotations_in_engine_rs() {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let engine_rs_path = manifest_dir.join("src").join("api").join("engine.rs");
    let content = fs::read_to_string(&engine_rs_path)
        .expect("Failed to read src/api/engine.rs");

    assert!(
        content.contains("#[flutter_rust_bridge::frb(sync)]\npub fn start_engine() -> EngineStatus")
            || content.contains("#[flutter_rust_bridge::frb(sync)]") && content.contains("pub fn start_engine()"),
        "start_engine must have #[flutter_rust_bridge::frb(sync)] attribute"
    );
    assert!(
        content.contains("pub fn allocate_engine_buffer(size_bytes: usize) -> Vec<u8>"),
        "allocate_engine_buffer must accept size_bytes: usize and return Vec<u8>"
    );
    assert!(
        content.contains("pub fn get_engine_status() -> EngineStatus"),
        "get_engine_status must return EngineStatus"
    );
    assert!(
        content.contains("pub fn verify_buffer_sentinels(buffer: Vec<u8>) -> bool"),
        "verify_buffer_sentinels must accept Vec<u8> and return bool"
    );
    assert!(
        content.contains("pub struct SharedFrameBuffer"),
        "SharedFrameBuffer struct must be defined"
    );
}

#[test]
fn test_c_abi_wire_exports_in_frb_generated_rs() {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let frb_gen_path = manifest_dir.join("src").join("frb_generated.rs");
    assert!(
        frb_gen_path.exists(),
        "frb_generated.rs must exist at {}",
        frb_gen_path.display()
    );

    let content = fs::read_to_string(&frb_gen_path)
        .expect("Failed to read src/frb_generated.rs");

    let required_symbols = [
        "frb_initialize_rust",
        "wire__crate__api__engine__start_engine",
        "wire__crate__api__engine__start_engine_sync",
        "wire__crate__api__engine__allocate_engine_buffer",
        "wire__crate__api__engine__free_engine_buffer",
        "wire__crate__api__engine__get_engine_status",
        "wire__crate__api__engine__free_engine_status",
        "wire__crate__api__engine__verify_buffer_sentinels",
        "wire__crate__api__engine__shared_frame_buffer_new",
        "wire__crate__api__engine__shared_frame_buffer_free",
        "wire__crate__api__engine__shared_frame_buffer_len",
        "wire__crate__api__engine__shared_frame_buffer_ptr_address",
        "wire__crate__api__engine__shared_frame_buffer_read_byte",
        "wire__crate__api__engine__shared_frame_buffer_write_byte",
    ];

    for &symbol in &required_symbols {
        assert!(
            content.contains(symbol),
            "frb_generated.rs must export C-ABI symbol '{}'",
            symbol
        );
    }
}

#[test]
fn test_dart_bindings_exist_and_conform_to_contract() {
    let root = find_workspace_root();
    let dart_rust_dir = root.join("fluorite_editor").join("lib").join("src").join("rust");

    let frb_dart = dart_rust_dir.join("frb_generated.dart");
    let frb_io_dart = dart_rust_dir.join("frb_generated.io.dart");
    let api_engine_dart = dart_rust_dir.join("api").join("engine.dart");

    assert!(frb_dart.exists(), "frb_generated.dart must exist");
    assert!(frb_io_dart.exists(), "frb_generated.io.dart must exist");
    assert!(api_engine_dart.exists(), "api/engine.dart must exist");

    let frb_dart_content = fs::read_to_string(&frb_dart).unwrap();
    assert!(
        frb_dart_content.contains("class RustLib"),
        "frb_generated.dart must define RustLib"
    );
    assert!(
        frb_dart_content.contains("ExternalLibrary.open"),
        "frb_generated.dart must support ExternalLibrary.open"
    );

    let api_content = fs::read_to_string(&api_engine_dart).unwrap();
    assert!(
        api_content.contains("class EngineStatus"),
        "api/engine.dart must define EngineStatus"
    );
    assert!(
        api_content.contains("startEngine()"),
        "api/engine.dart must expose startEngine()"
    );
    assert!(
        api_content.contains("allocateEngineBuffer"),
        "api/engine.dart must expose allocateEngineBuffer"
    );
    assert!(
        api_content.contains("getEngineStatus()"),
        "api/engine.dart must expose getEngineStatus()"
    );
    assert!(
        api_content.contains("verifyBufferSentinels"),
        "api/engine.dart must expose verifyBufferSentinels"
    );
    assert!(
        api_content.contains("class SharedFrameBuffer"),
        "api/engine.dart must define SharedFrameBuffer"
    );
}

#[test]
fn test_engine_lifecycle_and_1mb_zero_copy_sentinels() {
    // 1. Lifecycle start
    let status = start_engine();
    assert!(status.is_initialized, "Engine must be marked initialized");
    assert_eq!(status.arena_capacity, DEFAULT_ENGINE_FRAME_CAPACITY);
    assert_eq!(status.status_message, "Fluorite Engine Core Initialized");
    assert_eq!(status.core_version, "0.1.0");
    assert_eq!(status.allocator_name, "FluoriteArenaAllocator_v1");

    // 2. 1MB buffer allocation with sentinels
    let buffer = allocate_engine_buffer(ONE_MB);
    assert_eq!(buffer.len(), ONE_MB, "Buffer must be exactly 1MB (1,048,576 bytes)");
    assert_eq!(buffer[0], SENTINEL_HEADER, "Header sentinel must be 0xAA");
    assert_eq!(buffer[ONE_MB - 1], SENTINEL_FOOTER, "Footer sentinel must be 0x55");
    assert_eq!(buffer[1], 0x00, "Interior bytes must be zeroed");
    assert_eq!(buffer[ONE_MB - 2], 0x00, "Interior bytes must be zeroed");

    // 3. Sentinel verification function
    assert!(
        verify_buffer_sentinels(buffer.clone()),
        "Sentinel verification must succeed for fresh 1MB buffer"
    );
    assert!(
        verify_buffer_sentinels_slice(&buffer),
        "Slice sentinel verification must succeed for fresh 1MB buffer"
    );

    // 4. Telemetry query
    let current_status = get_engine_status();
    assert!(current_status.is_initialized);
    assert_eq!(current_status.status_message, "Fluorite Engine Core Running");
    assert!(
        current_status.total_memory_allocated >= ONE_MB,
        "Active arena memory accounting must record 1MB allocation"
    );

    // 5. Corrupted sentinels rejection
    let mut corrupted = buffer.clone();
    corrupted[0] = 0x00;
    assert!(
        !verify_buffer_sentinels(corrupted),
        "Corrupted header sentinel must be rejected"
    );

    let mut corrupted_footer = buffer.clone();
    corrupted_footer[ONE_MB - 1] = 0xFF;
    assert!(
        !verify_buffer_sentinels(corrupted_footer),
        "Corrupted footer sentinel must be rejected"
    );

    // 6. Zero-byte buffer edge case
    let empty_buf = allocate_engine_buffer(0);
    assert_eq!(empty_buf.len(), 0);
    assert!(!verify_buffer_sentinels(empty_buf));
}

#[test]
fn test_shared_frame_buffer_pointer_and_live_view() {
    let mut shared_buf = SharedFrameBuffer::new(1024);
    assert_eq!(shared_buf.len(), 1024);
    assert!(!shared_buf.is_empty());

    // Native pointer address verification
    let ptr_addr = shared_buf.ptr_address();
    assert_ne!(ptr_addr, 0, "Pointer address must be non-zero");

    // Header test sentinels 0xDEADBEEF
    assert_eq!(shared_buf.read_byte(0), 0xDE);
    assert_eq!(shared_buf.read_byte(1), 0xAD);
    assert_eq!(shared_buf.read_byte(2), 0xBE);
    assert_eq!(shared_buf.read_byte(3), 0xEF);

    // Live mutation verification
    shared_buf.write_byte(100, 0x42);
    assert_eq!(shared_buf.read_byte(100), 0x42);

    shared_buf.write_byte(1023, 0x99);
    assert_eq!(shared_buf.read_byte(1023), 0x99);
}
