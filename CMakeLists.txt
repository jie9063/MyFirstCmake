cmake_minimum_required(VERSION 3.22)

project(MyFirstCmake LANGUAGES C ASM)

set(CMAKE_TOOLCHAIN_FILE "${CMAKE_SOURCE_DIR}/cmake/arm-none-eabi-gcc.cmake" CACHE FILEPATH "ARM GCC toolchain file")
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(TARGET MyFirstCmake)
set(LINKER_SCRIPT "${CMAKE_SOURCE_DIR}/STM32F401RETx_FLASH.ld")

set(SOURCES
    Core/Src/main.c
    Core/Src/stm32f4xx_it.c
    Core/Src/stm32f4xx_hal_msp.c
    Core/Src/system_stm32f4xx.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_rcc.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_rcc_ex.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_flash.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_flash_ex.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_flash_ramfunc.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_gpio.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_dma_ex.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_dma.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_pwr.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_pwr_ex.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_cortex.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal.c
    Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_exti.c
    startup_stm32f401xe.s
)

add_executable(${TARGET}.elf ${SOURCES})

target_include_directories(${TARGET}.elf PRIVATE
    Core/Inc
    Drivers/STM32F4xx_HAL_Driver/Inc
    Drivers/STM32F4xx_HAL_Driver/Inc/Legacy
    Drivers/CMSIS/Device/ST/STM32F4xx/Include
    Drivers/CMSIS/Include
)

target_compile_definitions(${TARGET}.elf PRIVATE
    USE_HAL_DRIVER
    STM32F401xE
)

target_compile_options(${TARGET}.elf PRIVATE
    -mcpu=cortex-m4
    -mthumb
    -mfpu=fpv4-sp-d16
    -mfloat-abi=hard
    -fdata-sections
    -ffunction-sections
    -Wall
    -Og
    -g3
)

target_link_options(${TARGET}.elf PRIVATE
    -mcpu=cortex-m4
    -mthumb
    -mfpu=fpv4-sp-d16
    -mfloat-abi=hard
    --specs=nano.specs
    --specs=nosys.specs
    -T${LINKER_SCRIPT}
    -Wl,-Map=${CMAKE_BINARY_DIR}/${TARGET}.map,--cref
    -Wl,--gc-sections
)

target_link_libraries(${TARGET}.elf PRIVATE c m)

add_custom_command(TARGET ${TARGET}.elf POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O ihex $<TARGET_FILE:${TARGET}.elf> ${CMAKE_BINARY_DIR}/${TARGET}.hex
    COMMAND ${CMAKE_OBJCOPY} -O binary -S $<TARGET_FILE:${TARGET}.elf> ${CMAKE_BINARY_DIR}/${TARGET}.bin
    COMMAND ${CMAKE_SIZE} $<TARGET_FILE:${TARGET}.elf>
    COMMENT "Generating .hex/.bin and printing size"
)

add_custom_target(flash
    COMMAND openocd -f ${CMAKE_SOURCE_DIR}/openocd.cfg -c "program ${CMAKE_BINARY_DIR}/${TARGET}.elf verify reset exit"
    DEPENDS ${TARGET}.elf
    USES_TERMINAL
)

add_custom_target(debug
    COMMAND openocd -f ${CMAKE_SOURCE_DIR}/openocd.cfg
    DEPENDS ${TARGET}.elf
    USES_TERMINAL
)