cmake_minimum_required(VERSION 3.22.1)
project(chef25_node_spike LANGUAGES CXX)

add_library(native-lib SHARED native-lib.cpp)

find_library(android-log log)
find_package(Threads REQUIRED)

target_link_libraries(
    native-lib
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../libnode/arm64-v8a/libnode.so"
    ${android-log}
    Threads::Threads
)
