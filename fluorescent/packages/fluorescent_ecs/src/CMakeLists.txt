# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(fluorescent_ecs_library VERSION 0.0.1 LANGUAGES C CXX)

add_library(fluorescent_ecs SHARED
  "fluorite_ecs_core.cpp"
)

set_target_properties(fluorescent_ecs PROPERTIES
  PUBLIC_HEADER fluorescent_ecs.h
  OUTPUT_NAME "fluorescent_ecs"
)

target_compile_definitions(fluorescent_ecs PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(fluorescent_ecs PRIVATE "-Wl,-z,max-page-size=16384")
endif()
