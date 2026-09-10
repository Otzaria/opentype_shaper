cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "opentype_shaper")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../rust opentype_shaper "")

set(opentype_shaper_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
