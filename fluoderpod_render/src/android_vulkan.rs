#![cfg(target_os = "android")]

use jni::objects::JObject;
use jni::sys::{jint, jlong};
use log::{error, info};
use ndk_sys::{
    AHardwareBuffer, AHardwareBuffer_Desc, AHardwareBuffer_allocate, AHardwareBuffer_release,
};
use std::ptr;

// Some constants for usage may not be directly available in older NDK-sys versions as enums,
// using raw values corresponding to AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE and GPU_COLOR_OUTPUT
const AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE: u64 = 1 << 8;
const AHARDWAREBUFFER_USAGE_GPU_COLOR_OUTPUT: u64 = 1 << 9;
const AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM: u32 = 1;

#[no_mangle]
pub extern "system" fn Java_com_fluorescent_vulkan_FluorescentVulkanPlugin_createHardwareBuffer(
    _env: jni::sys::JNIEnv,
    _class: JObject,
    width: jint,
    height: jint,
) -> jlong {
    info!("Rust Vulkan: creating AHardwareBuffer {}x{}", width, height);

    let desc = AHardwareBuffer_Desc {
        width: width as u32,
        height: height as u32,
        layers: 1,
        format: AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM,
        usage: AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE | AHARDWAREBUFFER_USAGE_GPU_COLOR_OUTPUT,
        stride: 0,
        rfu0: 0,
        rfu1: 0,
    };

    let mut buffer: *mut AHardwareBuffer = ptr::null_mut();
    let result = unsafe { AHardwareBuffer_allocate(&desc, &mut buffer) };

    if result != 0 {
        error!("Failed to allocate AHardwareBuffer. Error code: {}", result);
        return 0;
    }

    // Note: Future Vulkan initialization (using ash) to import the AHardwareBuffer
    // memory and render to it directly from Rust goes here, replacing the C++
    // bind_hardware_buffer_to_vulkan and android_render_frame calls.
    info!("AHardwareBuffer created successfully in Rust.");

    buffer as jlong
}

#[no_mangle]
pub extern "system" fn Java_com_fluorescent_vulkan_FluorescentVulkanPlugin_destroyHardwareBuffer(
    _env: jni::sys::JNIEnv,
    _class: JObject,
    buffer_ptr: jlong,
) {
    if buffer_ptr != 0 {
        let buffer = buffer_ptr as *mut AHardwareBuffer;
        unsafe {
            AHardwareBuffer_release(buffer);
        }
        info!("Rust Vulkan: AHardwareBuffer released.");
    }
}

// Just ensuring the JNI export builds nicely and handles the ash stub
