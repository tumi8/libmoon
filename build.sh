#!/bin/bash

#FLAGS is filled with arguments for bind-interfaces.sh
FLAGS=""

#OPTIONS is filled with options for cmake
OPTIONS=''
MOON=false
DISABLED_DRIVERS="net/octeontx,net/octeontx2,compress/octeontx,regex/octeontx2,baseband/turbo_sw,baseband/null,baseband/fpga_lte_fec,baseband/fpga_5gnr_fec,baseband/acc100,crypto/bcmfs,crypto/caam_jr,crypto/dpaa_sec,crypto/dpaa2_sec,crypto/nitrox,crypto/octeontx,crypto/octeontx2,event/dlb,event/dlb2,event/opdl,event/skeleton,event/sw,event/dsw,common/octeontx,common/octeontx2,raw/dpaa2_cmdif,raw/dpaa2_qdma,raw/ioat,raw/ntb,raw/octeontx2_dma,raw/octeontx2_ep,raw/skeleton,net/ark,net/atlantic,net/avp,net/axgbe,net/bnxt,net/cxgbe,net/dpaa,net/dpaa2,net/ena,net/enetc,net/enic,net/fm10k,net/hinic,net/hns3,net/kni,net/liquidio,net/netvsc,net/nfp,net/null,net/pfe,net/qede,net/thunderx,net/txgbe,vdpa/ifc,crypto/null,crypto/scheduler,net/ngbe,mempool/dpaa,mempool/dpaa2,bus/dpaa,dma/dpaa,baseband/la12xx,common/cnxk,mempool/cnxk,dma/cnxk,net/cnxk,crypto/cnxk,event/cnxk,raw/cnxk_bphy,dma/hisilicon,net/enetfec,net/octeontx_ep"
NO_BIND=false
DEBUG_FLAGS_DPDK=""
DEBUG_FLAGS_MOONGEN=""
INCREASE_MEMORY_LIMITS_DPDK=false

while :; do
	case $1 in
		-h|--help)
			#echo "Usage: <no option> compile without Mellanox drivers; <-m|--mlx5> compile mlx5; <-n|--mlx4> compile mlx4; <-h|--help> help;"
			echo "Usage: <no option> Mellanox drivers should be automatically compiled, when the dependencies are installed; to compile DPDK with all drivers add the flag -a <-h|--help> help;"
			exit
			;;
		--moongen) #For internal use only
			echo "Build libmoon with MoonGen"
			MOON=true
			;;
		-a)
			echo "Building DPDK with all drivers (except dpaa)"
			DISABLED_DRIVERS="net/dpaa,net/dpaa2"
			;;
		--noBind) #skip binding unused interfaces to the igb_uio driver
			echo "Skip binding unused interfaces to the igb_uio driver"
			NO_BIND=true
			;;
		--debug) #enable build with debug symbols
			echo "Building Moongen with debug symbols"
			DEBUG_FLAGS_DPDK="--buildtype=debugoptimized"
			DEBUG_FLAGS_MOONGEN="-DCMAKE_BUILD_TYPE=RelWithDebInfo"
			;;
		--increaseMemoryLimits) # build DPDK with increase memory limits
			echo "Building Moongen with increased memory limits"
			INCREASE_MEMORY_LIMITS_DPDK=true
			;;
		-?*)
			printf 'WARN: Unknown option (abort): %s\n' "$1" >&2
			exit
			;;
		*)
			break
	esac
	shift
done


# TODO: this should probably be a makefile
(
cd $(dirname "${BASH_SOURCE[0]}")
git submodule update --init --recursive

NUM_CPUS=$(cat /proc/cpuinfo  | grep "processor\\s: " | wc -l)

(
cd deps/luajit
make -j $NUM_CPUS BUILDMODE=static 'CFLAGS=-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT'
make install DESTDIR=$(pwd)
)

(
# Build the DPDK dependencies for igb_uio driver module
cd deps/dpdk-kmods/linux/igb_uio
make -j $NUM_CPUS
)

export PKG_CONFIG_PATH=$(pwd)/deps/dpdk/x86_64-native-linux-gcc/lib/x86_64-linux-gnu/pkgconfig/:$PKG_CONFIG_PATH
(
cd deps/dpdk
if ${INCREASE_MEMORY_LIMITS_DPDK}; then
	grep -q -x -F "#define RTE_MAX_MEMSEG_PER_LIST 16384" ./config/rte_config.h || sed -i 's/RTE_MAX_MEMSEG_PER_LIST 8192/RTE_MAX_MEMSEG_PER_LIST 16384/' ./config/rte_config.h
	grep -q -x -F "#define RTE_MAX_MEM_MB_PER_LIST 524288" ./config/rte_config.h || sed -i 's/RTE_MAX_MEM_MB_PER_LIST 32768/RTE_MAX_MEM_MB_PER_LIST 524288/' ./config/rte_config.h
	grep -q -x -F "#define RTE_MAX_MEMSEG_PER_TYPE 524288" ./config/rte_config.h || sed -i 's/RTE_MAX_MEMSEG_PER_TYPE 32768/RTE_MAX_MEMSEG_PER_TYPE 524288/' ./config/rte_config.h
	grep -q -x -F "#define RTE_MAX_MEM_MB_PER_TYPE 1048576" ./config/rte_config.h || sed -i 's/RTE_MAX_MEM_MB_PER_TYPE 65536/RTE_MAX_MEM_MB_PER_TYPE 1048576/' ./config/rte_config.h
fi
CC=gcc meson setup $DEBUG_FLAGS_DPDK -Dmax_lcores=512 -Dtests=false -Ddisable_drivers=$DISABLED_DRIVERS --prefix=$(pwd)/x86_64-native-linux-gcc x86_64-native-linux-gcc
grep -q -x -F "#define RTE_LIBRTE_IEEE1588 1" ./x86_64-native-linux-gcc/rte_build_config.h || echo "#define RTE_LIBRTE_IEEE1588 1" >> ./x86_64-native-linux-gcc/rte_build_config.h
ninja -C x86_64-native-linux-gcc
ninja -C x86_64-native-linux-gcc install
)

(
cd lua/lib/turbo
make 2> /dev/null
if [[ $? > 0 ]]
then
	echo "Could not compile Turbo with TLS support, disabling TLS"
	echo "Install libssl-dev and OpenSSL to enable TLS support"
	make SSL=none
fi
)

(
if ! ${MOON}; then
	cd build
else	
	cd ../build
fi
PKG_CONFIG_PATH=$PKG_CONFIG_PATH cmake $DEBUG_FLAGS_MOONGEN ${OPTIONS}..
PKG_CONFIG_PATH=$PKG_CONFIG_PATH make -j $NUM_CPUS --always-make
)


if ! ${NO_BIND}; then
	echo Trying to bind interfaces, this will fail if you are not root
	echo Try "sudo ./bind-interfaces.sh" if this step fails
	./bind-interfaces.sh ${FLAGS}
else
	#load igb_uio kernel module
	modprobe uio
	(lsmod | grep igb_uio > /dev/null) || insmod deps/dpdk-kmods/linux/igb_uio/igb_uio.ko
fi
)

