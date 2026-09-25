#!/bin/bash
rustup target add aarch64-linux-android
cd fluoderpod_render
cargo check --target aarch64-linux-android
