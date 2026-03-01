set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

find_program(ARM_GCC arm-none-eabi-gcc)
find_program(ARM_GXX arm-none-eabi-g++)
find_program(ARM_OBJCOPY arm-none-eabi-objcopy)
find_program(ARM_SIZE arm-none-eabi-size)

if(NOT ARM_GCC)
    message(FATAL_ERROR "arm-none-eabi-gcc not found. Add GNU Arm Toolchain to PATH.")
endif()

if(NOT ARM_OBJCOPY)
    message(FATAL_ERROR "arm-none-eabi-objcopy not found. Add GNU Arm Toolchain to PATH.")
endif()

if(NOT ARM_SIZE)
    message(FATAL_ERROR "arm-none-eabi-size not found. Add GNU Arm Toolchain to PATH.")
endif()

set(CMAKE_C_COMPILER ${ARM_GCC})
set(CMAKE_CXX_COMPILER ${ARM_GXX})
set(CMAKE_ASM_COMPILER ${ARM_GCC})
set(CMAKE_OBJCOPY ${ARM_OBJCOPY} CACHE FILEPATH "objcopy tool")
set(CMAKE_SIZE ${ARM_SIZE} CACHE FILEPATH "size tool")
