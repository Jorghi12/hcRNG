#!/bin/bash -e 
# This script is invoked to build the hcRNG library and test sources

# CHECK FOR COMPILER PATH
if [ ! -z $HCC_HOME ]
then
  if [ -x "$HCC_HOME/bin/clang++" ]
  then
    platform="hcc"
    cmake_c_compiler="$HCC_HOME/bin/clang"
    cmake_cxx_compiler="$HCC_HOME/bin/clang++"
  fi
elif [ -x "/opt/rocm/hcc/bin/clang++" ]
then
  platform="hcc"
  cmake_c_compiler="/opt/rocm/hcc/bin/clang"
  cmake_cxx_compiler="/opt/rocm/hcc/bin/clang++"
elif [ -x "/usr/local/cuda/bin/nvcc" ];
then
  platform="nvcc"
  cmake_c_compiler="/usr/bin/gcc"
  cmake_cxx_compiler="/usr/bin/g++"
else
  echo "Neither clang  or NVCC compiler found"
  echo "Not an AMD or NVCC compatible stack"
  exit 1
fi

if ( [ ! -z $HIP_PATH ] || [ -x "/opt/rocm/hip/bin/hipcc" ] ); then 
  export HIP_SUPPORT=on
elif ( [ "$platform" = "nvcc" ]); then
  echo "HIP not found. Install latest HIP to continue."
  exit 1
fi

# CURRENT_WORK_DIRECTORY
current_work_dir=$PWD

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$current_work_dir/build/lib/src
#TODO:check if export necessary
if [ ! -z $HIP_PATH ]
then
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HIP_PATH/lib
else
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/rocm/hip/lib
fi


red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`
copt="-O3"
verbose=""
install=0

# Help menu
print_help() {
cat <<-HELP
=============================================================================================================================
This script is invoked to build hcRNG library and test sources. Please provide the following arguments:

  ${green}--test${reset}     Test to enable the library testing (on/basic/off) 
  ${green}--debug${reset}    Compile with debug info (-g)
  ${green}--verbose${reset}  Run make with VERBOSE=1
  ${green}--install${reset}  Install the shared library and include the header files under /opt/rocm/hcrng  Requires sudo perms.
  ${green}--examples${reset} To build and run the example files in examples folder (on/off) (ONLY SUPPORTED ON AMD PLATFORM)

=============================================================================================================================
Example: 
(1) ${green}./build.sh --test=on ${reset}
(1) ${green}./build.sh --install ${reset}
(1) ${green}./build.sh --examples=on ${reset}

=============================================================================================================================
HELP
exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --test=*)
      testing="${1#*=}"
      ;;
    --debug)
      copt="-g"
      ;;
    --verbose)
      verbose="VERBOSE=1"
      ;;
    --install)
      install="1"
      ;;
   --examples=*)
      examples="${1#*=}"
      ;;
    --help) print_help;;
    *)
      printf "************************************************************\n"
      printf "* Error: Invalid arguments, run --help for valid arguments.*\n"
      printf "************************************************************\n"
      exit 1
  esac
  shift
done

if [ "$install" = "1" ]; then
    export INSTALL_OPT=on
fi

set +e
# MAKE BUILD DIR
mkdir -p $current_work_dir/build
#mkdir $current_work_dir/build/lib
mkdir -p $current_work_dir/build/packaging 
set -e

# SET BUILD DIR
build_dir=$current_work_dir/build
#change to library build
cd $build_dir


if [ "$platform" = "hcc" ]; then
  # Cmake and make libhcRNG: Install hcRNG
  cmake -DCMAKE_C_COMPILER=$cmake_c_compiler -DCMAKE_CXX_COMPILER=$cmake_cxx_compiler -DCMAKE_CXX_FLAGS=-fPIC -DCMAKE_INSTALL_PREFIX=/opt/rocm/hcrng $current_work_dir
  make -j package $verbose
  make -j $verbose
 
  if [ "$install" = "1" ]; then
    sudo make install
  fi
  cd $build_dir/packaging/ && cmake -DCMAKE_C_COMPILER=$cmake_c_compiler -DCMAKE_CXX_COMPILER=$cmake_cxx_compiler -DCMAKE_CXX_FLAGS=-fPIC -DCMAKE_INSTALL_PREFIX=/opt/rocm/hcrng $current_work_dir/packaging/

  #Test=OFF (Build library)
  if ( [ -z $testing ] ) || ( [ "$testing" = "off" ] ); then
    echo "${green}hcRNG Build Completed!${reset}"
  # Test=ON (Build and test the library)
  elif ( [ "$testing" = "on" ] ) || ( [ "$testing" = "basic" ] ); then
    set +e
    # MAKE BUILD DIR
    mkdir -p $current_work_dir/build/test
    set -e

    # Build Tests
    cd $build_dir/test/ && cmake -DCMAKE_C_COMPILER=$cmake_c_compiler -DCMAKE_CXX_COMPILER=$cmake_cxx_compiler -DCMAKE_CXX_FLAGS=-fPIC $current_work_dir/test/
    make -j

   printf "* UNIT API TESTS *\n"
   printf "******************\n"
   ${current_work_dir}/build/test/unit-api/bin/unittest 

    if [ $HIP_SUPPORT = "on" ]; then
      chmod +x $current_work_dir/test/unit-hip/test.sh
      cd $current_work_dir/test/unit-hip/
      # Invoke hip unit test script
      printf "* UNIT HIP TESTS *\n"
      printf "******************\n"
      ./test.sh
    fi
  fi

#EXAMPLES
#Invoke examples script if --examples=on
  if [ "$examples" = "on" ]; then
    chmod +x $current_work_dir/examples/build.sh
    cd $current_work_dir/examples/
    ./build.sh
  fi
fi

if [ "$platform" = "nvcc" ]; then
  # Cmake and make libhipRNG: Build hipRNG
  cmake -DCMAKE_C_COMPILER=$cmake_c_compiler -DCMAKE_CXX_COMPILER=$cmake_cxx_compiler -DCMAKE_CXX_FLAGS=-fPIC -DCMAKE_INSTALL_PREFIX=/opt/rocm/hcrng $current_work_dir
  make package
  make
  
  if [ "$install" = "1" ]; then
    sudo make install
  fi
  cd $build_dir/packaging/ && cmake -DCMAKE_C_COMPILER=$cmake_c_compiler -DCMAKE_CXX_COMPILER=$cmake_cxx_compiler -DCMAKE_CXX_FLAGS=-fPIC -DCMAKE_INSTALL_PREFIX=/opt/rocm/hcrng $current_work_dir/packaging/
  echo "${green}hipRNG Build Completed!${reset}"
  
  if ( [ "$testing" = "on" ] ); then
    set +e
    # MAKE BUILD DIR
    mkdir $current_work_dir/build/test
    mkdir -p $current_work_dir/build/test/unit-hip/common/bin/
    mkdir -p $current_work_dir/build/test/unit-hip/normal/bin/
    mkdir -p $current_work_dir/build/test/unit-hip/uniform/bin/
    set -e

    # Build Tests
    cd $build_dir/test/ && cmake -DCMAKE_C_COMPILER=$cmake_c_compiler -DCMAKE_CXX_COMPILER=$cmake_cxx_compiler -DCMAKE_CXX_FLAGS=-fPIC $current_work_dir/test/
    make

    chmod +x $current_work_dir/test/unit-hip/test.sh
    cd $current_work_dir/test/unit-hip/
     printf "* UNIT HIP TESTS *\n"
     printf "******************\n"
    # Invoke hip unit test script
    ./test.sh
  fi
fi
# TODO: ADD More options to perform benchmark
