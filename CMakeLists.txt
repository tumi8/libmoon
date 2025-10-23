CMAKE_MINIMUM_REQUIRED(VERSION 2.8...3.18)
PROJECT(libmoon C CXX)

SET(CMAKE_CXX_FLAGS "-fno-stack-protector -Wall -Wextra -Wno-unused-parameter -g -O3 -std=gnu++11 -march=native -msse4.2")
SET(CMAKE_C_FLAGS "-fno-stack-protector -Wall -Wextra -Wno-unused-parameter -g -O3 -std=gnu11 -march=native -msse4.2")
SET(CMAKE_EXE_LINKER_FLAGS "-rdynamic") # to access functions from luajit

SET(FILES
	src/main.cpp
	src/memory.c
	src/task.cpp
	src/device.c
	src/i40e.c
	src/ice.c
	src/util.c
	src/lifecycle.cpp
	src/barrier.cpp
	src/task-results.cpp
	src/pipe.cpp
	src/lock.cpp
	src/namespaces.cpp
	src/ring.c
	src/filter.c
	src/pcap.cpp
	src/timestamping.c
	src/timestamping_i40e.c
	src/timestamping_ixgbe.c
	src/timestamping_igb.c
	src/tx_scheduler_ice.c
	src/bytesizedring.cpp
	src/pktsizedring.cpp
	src/ice_temp.cpp
)

SET(LUAJIT_LIBS
	luajit-5.1
)

find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
  pkg_check_modules(dpdk IMPORTED_TARGET libdpdk)
endif()

SET(ALL_LIBS
	-Wl,--whole-archive
	${LUAJIT_LIBS}
	-Wl,--no-whole-archive
)

INCLUDE_DIRECTORIES(
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/x86_64-native-linux-gcc/include
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/lib/ethdev
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/lib/eal/include
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/net/bnxt
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/net/ixgbe/base
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/net/ixgbe
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/net/i40e/base
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/net/i40e
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/common/iavf
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/net/iavf
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/net/ice/base
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/net/ice
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/net/e1000
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/net/e1000/base
	${CMAKE_CURRENT_SOURCE_DIR}/deps/dpdk/drivers/bus/pci
	${CMAKE_CURRENT_SOURCE_DIR}/deps/luajit/src
	${CMAKE_CURRENT_SOURCE_DIR}/lib
	${CMAKE_CURRENT_SOURCE_DIR}/src
)

LINK_DIRECTORIES(
	${dpdk_STATIC_LINK_DIRS}
	${CMAKE_CURRENT_SOURCE_DIR}/deps/luajit/usr/local/lib
)

IF(LIBMOON_BUILD_LIBRARY)
	ADD_DEFINITIONS(-DLIBMOON_BUILD_LIB)
	# we want libmoon.a, not liblibmoon.a
	ADD_LIBRARY(moon STATIC ${FILES})
	TARGET_LINK_LIBRARIES(moon ${ALL_LIBS} -Wl,--start-group ${dpdk_STATIC_LINK_LIBRARIES} ${dpdk_STATIC_LDFLAGS} ${dpdk_STATIC_LDFLAGS_OTHER} numa -Wl,--end-group pthread dl rt)
ELSE()
	ADD_EXECUTABLE(libmoon ${FILES})
	TARGET_LINK_LIBRARIES(libmoon ${ALL_LIBS} -Wl,--start-group ${dpdk_STATIC_LINK_LIBRARIES} ${dpdk_STATIC_LDFLAGS} ${dpdk_STATIC_LDFLAGS_OTHER} numa -Wl,--end-group pthread dl rt)
ENDIF()

