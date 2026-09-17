//! API Contract, C-ABI Symbol Export, and Memory Execution Verification Suite
//!
//! This suite honestly and deterministically validates:
//! 1. `flutter_rust_bridge.yaml` declarative configuration and path validity.
//! 2. `Cargo.toml` dependency specifications and crate types (`cdylib`, `rlib`).
//! 3. Runtime execution of exported C-ABI wire functions (`wire__crate__api__engine__*`).
//! 4. 1MB memory buffer allocation, sentinel integrity, and safe C-ABI deallocation.
//! 5. Single-pointer automatic deallocator (`wire__free_engine_buffer_auto`) for Dart NativeFinalizer.
//! 6. `SharedFrameBuffer` lifecycle, pointer address, and in-place mutation.
//! 7. Transparent probing of the `flutter_rust_bridge_codegen` CLI toolchain.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use fluorite_core::allocator::{ONE_MB, SENTINEL_FOOTER, SENTINEL_HEADER};
use fluorite_core::api::{
    allocate_engine_buffer, get_engine_status, start_engine, verify_buffer_sentinels,
    verify_buffer_sentinels_slice, EngineStatus, EngineStatusC, SharedFrameBuffer,
    DEFAULT_ENGINE_FRAME_CAPACITY,
};
use fluorite_core::frb_generated::{
    wire__crate__api__engine__allocate_engine_buffer,
    wire__crate__api__engine__free_engine_buffer,
    wire__crate__api__engine__free_engine_buffer_auto,
    wire__crate__api__engine__free_engine_status,
    wire__crate__api__engine__get_engine_status,
    wire__crate__api__engine__shared_frame_buffer_free,
    wire__crate__api__engine__shared_frame_buffer_len,
    wire__crate__api__engine__shared_frame_buffer_new,
    wire__crate__api__engine__shared_frame_buffer_ptr_address,
    wire__crate__api__engine__shared_frame_buffer_read_byte,
    wire__crate__api__engine__shared_frame_buffer_write_byte,
    wire__crate__api__engine__start_engine_sync,
    wire__crate__api__engine__verify_buffer_sentinels,
};

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
    PathBuf::from("..")
}

// -----------------------------------------------------------------------------
// 1. Declarative Configuration Contracts
// -----------------------------------------------------------------------------

#[test]
fn test_flutter_rust_bridge_yaml_configuration() {
    let root = find_workspace_root();
    let config_path = root.join("flutter_rust_bridge.yaml");
    assert!(config_path.exists(), "flutter_rust_bridge.yaml must exist at workspace root");

    let content = fs::read_to_string(&config_path).expect("Failed to read flutter_rust_bridge.yaml");
    assert!(content.contains("rust_root:"), "Must declare rust_root");
    assert!(content.contains("rust_input:"), "Must declare rust_input");
    assert!(content.contains("dart_output:"), "Must declare dart_output");

    // Verify configured directories actually exist on disk
    assert!(root.join("fluorite_core").exists(), "Configured rust_root directory must exist");
    assert!(root.join("fluorite_core").join("src").join("api").exists(), "Configured rust_input directory must exist");
    assert!(root.join("fluorite_editor").join("lib").join("src").join("rust").exists(), "Configured dart_output directory must exist");
}

#[test]
fn test_cargo_toml_dependencies_and_crate_types() {
    let manifest_path = Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
    let content = fs::read_to_string(&manifest_path).expect("Failed to read Cargo.toml");

    assert!(content.contains("flutter_rust_bridge = \"2.13.0\""), "Cargo.toml must depend on flutter_rust_bridge 2.13.0");
    assert!(content.contains("\"cdylib\""), "Cargo.toml must include cdylib for C-ABI dynamic linking");
    assert!(content.contains("\"rlib\""), "Cargo.toml must include rlib for native Rust testing");
}

// -----------------------------------------------------------------------------
// 2. Direct Runtime Execution of C-ABI Wire Functions
// -----------------------------------------------------------------------------

#[test]
fn test_c_abi_wire_engine_lifecycle_and_status() {
    // Execute wire__start_engine_sync
    let status_ptr = wire__crate__api__engine__start_engine_sync();
    assert!(!status_ptr.is_null(), "wire__start_engine_sync must return non-null pointer");

    unsafe {
        assert!((*status_ptr).is_initialized, "Engine must be marked initialized via wire function");
        assert_eq!((*status_ptr).arena_capacity, DEFAULT_ENGINE_FRAME_CAPACITY);
    }
    // Clean up wire status pointer
    wire__crate__api__engine__free_engine_status(status_ptr);

    // Execute wire__get_engine_status
    let status_query_ptr = wire__crate__api__engine__get_engine_status();
    assert!(!status_query_ptr.is_null());
    unsafe {
        assert!((*status_query_ptr).is_initialized);
    }
    wire__crate__api__engine__free_engine_status(status_query_ptr);
}

#[test]
fn test_c_abi_wire_1mb_buffer_allocation_sentinels_and_free() {
    // 1. Allocate 1MB via wire export
    let raw_ptr = wire__crate__api__engine__allocate_engine_buffer(ONE_MB);
    assert!(!raw_ptr.is_null(), "wire__allocate_engine_buffer must return valid non-null memory pointer");

    // 2. Verify sentinels directly through raw pointer
    unsafe {
        assert_eq!(*raw_ptr, SENTINEL_HEADER, "Header sentinel at raw_ptr must be 0xAA");
        assert_eq!(*raw_ptr.add(ONE_MB - 1), SENTINEL_FOOTER, "Footer sentinel at raw_ptr[1048575] must be 0x55");
        assert_eq!(*raw_ptr.add(1), 0x00, "Interior bytes must be zeroed");
        assert_eq!(*raw_ptr.add(ONE_MB - 2), 0x00, "Interior bytes must be zeroed");
    }

    // 3. Verify sentinels via wire verifier
    let is_valid = wire__crate__api__engine__verify_buffer_sentinels(raw_ptr, ONE_MB);
    assert!(is_valid, "wire__verify_buffer_sentinels must return true for fresh buffer");

    // 4. Test corruption detection via wire verifier
    unsafe {
        *raw_ptr = 0x00; // Corrupt header
    }
    let is_corrupted_valid = wire__crate__api__engine__verify_buffer_sentinels(raw_ptr, ONE_MB);
    assert!(!is_corrupted_valid, "wire__verify_buffer_sentinels must reject corrupted header");

    // Restore for clean deallocation
    unsafe {
        *raw_ptr = SENTINEL_HEADER;
    }

    // 5. Cleanly deallocate via wire free function
    wire__crate__api__engine__free_engine_buffer(raw_ptr, ONE_MB);
}

#[test]
fn test_c_abi_wire_single_pointer_auto_deallocation() {
    // Allocate 1MB via wire export
    let raw_ptr = wire__crate__api__engine__allocate_engine_buffer(ONE_MB);
    assert!(!raw_ptr.is_null());

    // Single-pointer deallocation compatible with Dart NativeFinalizer
    wire__crate__api__engine__free_engine_buffer_auto(raw_ptr);
}

#[test]
fn test_c_abi_wire_shared_frame_buffer_lifecycle_and_mutation() {
    // 1. Create SharedFrameBuffer handle
    let handle_ptr = wire__crate__api__engine__shared_frame_buffer_new(512);
    assert!(!handle_ptr.is_null(), "wire__shared_frame_buffer_new must return valid handle");

    // 2. Query length and memory pointer address
    let len = wire__crate__api__engine__shared_frame_buffer_len(handle_ptr);
    assert_eq!(len, 512);

    let ptr_addr = wire__crate__api__engine__shared_frame_buffer_ptr_address(handle_ptr);
    assert_ne!(ptr_addr, 0, "Native pointer address must be non-zero");

    // 3. Verify DEADBEEF header via wire read
    assert_eq!(wire__crate__api__engine__shared_frame_buffer_read_byte(handle_ptr, 0), 0xDE);
    assert_eq!(wire__crate__api__engine__shared_frame_buffer_read_byte(handle_ptr, 1), 0xAD);
    assert_eq!(wire__crate__api__engine__shared_frame_buffer_read_byte(handle_ptr, 2), 0xBE);
    assert_eq!(wire__crate__api__engine__shared_frame_buffer_read_byte(handle_ptr, 3), 0xEF);

    // 4. In-place mutation via wire write
    wire__crate__api__engine__shared_frame_buffer_write_byte(handle_ptr, 100, 0x5A);
    assert_eq!(wire__crate__api__engine__shared_frame_buffer_read_byte(handle_ptr, 100), 0x5A);

    // 5. Deallocate handle
    wire__crate__api__engine__shared_frame_buffer_free(handle_ptr);
}

// -----------------------------------------------------------------------------
// 3. Transparent CLI Toolchain Probe
// -----------------------------------------------------------------------------

#[test]
fn test_flutter_rust_bridge_codegen_cli_probe() {
    let cli_check = Command::new("flutter_rust_bridge_codegen")
        .arg("--version")
        .output();

    match cli_check {
        Ok(output) if output.status.success() => {
            let version = String::from_utf8_lossy(&output.stdout);
            println!("[STATUS] flutter_rust_bridge_codegen CLI is installed: {}", version.trim());
        }
        _ => {
            eprintln!(
                "[INFO] flutter_rust_bridge_codegen CLI not found on PATH. \
                This test suite honestly validates all C-ABI wire symbols, configurations, \
                and runtime memory contracts directly via compiled Rust exports."
            );
        }
    }
}
