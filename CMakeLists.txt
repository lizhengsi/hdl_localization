cmake_minimum_required(VERSION 2.8.3)
project(hdl_localization)

if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
  add_definitions(-std=c++11)
  set(CMAKE_CXX_FLAGS "-std=c++11")
else()
	# -mavx causes a lot of errors!!
  if("$ENV{ROS_DISTRO}" STRGREATER "noetic")
    add_definitions(-std=c++17 -msse -msse2 -msse3 -msse4 -msse4.1 -msse4.2)
    set(CMAKE_CXX_FLAGS "-std=c++17 -msse -msse2 -msse3 -msse4 -msse4.1 -msse4.2")
  else()
    add_definitions(-std=c++14 -msse -msse2 -msse3 -msse4 -msse4.1 -msse4.2)
    set(CMAKE_CXX_FLAGS "-std=c++14 -msse -msse2 -msse3 -msse4 -msse4.1 -msse4.2")
  endif()
endif()

# pcl 1.7 causes a segfault when it is built with debug mode
set(CMAKE_BUILD_TYPE "Release")

find_package(catkin REQUIRED COMPONENTS
  nodelet
  tf2
  tf2_ros
  tf2_eigen
  tf2_geometry_msgs
  eigen_conversions
  pcl_ros
  roscpp
  rospy
  sensor_msgs
  geometry_msgs
  message_generation
)

find_package(Eigen3 REQUIRED)
find_package(OpenCV REQUIRED)
find_package(PCL REQUIRED)
add_definitions(${PCL_DEFINITIONS})
include_directories(${PCL_INCLUDE_DIRS})
link_directories(${PCL_LIBRARY_DIRS})
add_definitions(${PCL_DEFINITIONS})
message(STATUS "PCL_INCLUDE_DIRS:" ${PCL_INCLUDE_DIRS})
message(STATUS "PCL_LIBRARY_DIRS:" ${PCL_LIBRARY_DIRS})
message(STATUS "PCL_DEFINITIONS:" ${PCL_DEFINITIONS})

find_package(OpenMP)
if (OPENMP_FOUND)
    set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${OpenMP_C_FLAGS}")
    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")
endif()

if(BUILD_VGICP_CUDA)
  find_package(CUDA REQUIRED)
  include_directories(${CUDA_INCLUDE_DIRS})
  link_directories(${CUDA_LIBRARY_DIRS})
endif()

include(ExternalProject)
if(ENABLE_TEASER)
  ExternalProject_Add(teaser
    GIT_REPOSITORY https://github.com/koide3/TEASER-plusplus
    GIT_TAG master
    BUILD_IN_SOURCE
    CMAKE_ARGS -DBUILD_TESTS=OFF -DBUILD_PYTHON_BINDINGS=OFF -DBUILD_DOC=OFF -DBUILD_TEASER_FPFH=ON -DCMAKE_INSTALL_PREFIX=${CATKIN_DEVEL_PREFIX}
    INSTALL_COMMAND make install
  )

  set(TEASER_LIBRARIES
    ${CATKIN_DEVEL_PREFIX}/lib/libpmc.so
    ${CATKIN_DEVEL_PREFIX}/lib/libteaser_registration.so
    ${CATKIN_DEVEL_PREFIX}/lib/libteaser_features.so
  )

  add_definitions(-DTEASER_ENABLED)
endif()

########################
## message generation ##
########################
add_message_files(FILES
  ScanMatchingStatus.msg
)
add_service_files(
  FILES
  SetGlobalLocalizationEngine.srv
  SetGlobalMap.srv
  QueryGlobalLocalization.srv
)
generate_messages(
  DEPENDENCIES std_msgs sensor_msgs geometry_msgs
)

###################################
## catkin specific configuration ##
###################################
catkin_package(
  INCLUDE_DIRS include
#  LIBRARIES hdl_scan_matching_odometry
#  CATKIN_DEPENDS pcl_ros roscpp sensor_msgs
#  DEPENDS system_lib
)

###########
## Build ##
###########
include_directories(
  include
  ${catkin_INCLUDE_DIRS}
  ${OpenCV_INCLUDE_DIRS}
  ${PCL_INCLUDE_DIRS}
)

# hdl_localization
add_library(${PROJECT_NAME} SHARED
  src/fast_gicp/gicp/lsq_registration.cpp
  src/fast_gicp/gicp/fast_gicp.cpp
  src/fast_gicp/gicp/fast_gicp_st.cpp
  src/fast_gicp/gicp/fast_vgicp.cpp
  src/pclomp/voxel_grid_covariance_omp.cpp
  src/pclomp/ndt_omp.cpp
  src/pclomp/gicp_omp.cpp
  src/hdl_global_localization/bbs/bbs_localization.cpp
  src/hdl_global_localization/ransac/voxelset.cpp
  src/hdl_global_localization/ransac/ransac_pose_estimation.cpp
  src/hdl_global_localization/engines/global_localization_bbs.cpp
  src/hdl_global_localization/engines/global_localization_fpfh_ransac.cpp
  src/hdl_localization/pose_estimator.cpp
)
target_link_libraries(${PROJECT_NAME}
  ${PCL_LIBRARIES}
  ${OpenCV_LIBS}
)
if (OPENMP_FOUND)
    if (TARGET OpenMP::OpenMP_CXX)
        target_link_libraries(${PROJECT_NAME} OpenMP::OpenMP_CXX)
    endif ()
endif ()
target_include_directories(${PROJECT_NAME} PUBLIC
  include
  ${PCL_INCLUDE_DIRS}
  ${EIGEN3_INCLUDE_DIR}
  ${OpenCV_LIBS}
)

# nodelets localization
add_library(hdl_localization_nodelet SHARED
  apps/hdl_localization_nodelet.cpp
)
target_link_libraries(hdl_localization_nodelet
  ${catkin_LIBRARIES}
  ${PROJECT_NAME}
  ${PCL_LIBRARIES}
  ${OpenCV_LIBS}
)
add_dependencies(hdl_localization_nodelet ${PROJECT_NAME}_gencpp)

# nodelets globalmap_server
add_library(globalmap_server_nodelet apps/globalmap_server_nodelet.cpp)
target_link_libraries(globalmap_server_nodelet
  ${catkin_LIBRARIES}
  ${PCL_LIBRARIES}
)

# nodelets global_localization
add_library(global_localization_nodelet
  apps/global_localization_nodelet.cpp)
target_link_libraries(global_localization_nodelet
  ${catkin_LIBRARIES}
  ${PROJECT_NAME}
  ${PCL_LIBRARIES}
)
add_dependencies(global_localization_nodelet ${PROJECT_NAME}_gencpp)
