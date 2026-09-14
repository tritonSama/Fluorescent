cmake_minimum_required(VERSION 3.10.2)
project(fluorescent_vulkan)

set(CMAKE_CXX_STANDARD 17)

add_library(fluorescent_vulkan SHARED
    ../src/fluorescent_vulkan.cpp
    cpp/vulkan_renderer.cpp
)

find_library(log-lib log)
find_library(android-lib android)
find_library(vulkan-lib vulkan)

target_link_libraries(fluorescent_vulkan
    ${log-lib}
    ${android-lib}
    ${vulkan-lib}
)
