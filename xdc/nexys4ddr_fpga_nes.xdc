## This file based on a general .xdc for the Nexys4 DDR Rev. C


## Clock signal
## Команда create_clock автоматически добавляется на уровне ip-блока clk_wiz_main, к которму
## подключается порт sys_100mhz_clk_i, здесь оставлена для наглядности

set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports {sys_100mhz_clk_i}];

##create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports {sys_100mhz_clk_i}];


## Genarated clock signals
## Переименовываем автоматически созданные и использующиеся далее "зависимые" ("generated") сигналы тактирования и
## объявляем сигналы тактирования, полученные на выходах буферов с сигналом управления "BUFGCE"

create_generated_clock -name gclk_uart [get_pins {clock_reset_management/clk_wiz_main/inst/mmcm_adv_inst/CLKOUT0}];

create_generated_clock -name gclk_vga [get_pins {clock_reset_management/clk_wiz_main/inst/mmcm_adv_inst/CLKOUT2}];

create_generated_clock -name gclk_sd_base [get_pins {clock_reset_management/clk_wiz_sd/inst/mmcm_adv_inst/CLKOUT0}];

create_generated_clock -name gclk_ppu [get_pins {clock_reset_management/clk_wiz_ppu/inst/mmcm_adv_inst/CLKOUT0}];

create_generated_clock -name gmclk_ppu [get_pins {clock_reset_management/clk_wiz_ppu/inst/mmcm_adv_inst/CLKOUT0B}];

# gclk_nes_ppu divided by 3
create_generated_clock -name gclk_cpu                        \
    -source [get_pins {clock_reset_management/bufgce_cpu/I}] \
    -edges {1 2 7} [get_pins {clock_reset_management/bufgce_cpu/O}];

# gmclk_nes_ppu divided by 3
create_generated_clock -name gmclk_cpu                           \
    -source [get_pins {clock_reset_management/bufgce_cpu_mem/I}] \
    -edges {1 2 7} [get_pins {clock_reset_management/bufgce_cpu_mem/O}];

# gclk_sd_base without division
create_generated_clock -name gclk_sd_high                   \
    -source [get_pins {clock_reset_management/bufgce_sd/I}] \
    -edges {1 2 3} -add -master_clock gclk_sd_base [get_pins {clock_reset_management/bufgce_sd/O}];

# gclk_sd_base divided by 64
create_generated_clock -name gclk_sd_low                    \
    -source [get_pins {clock_reset_management/bufgce_sd/I}] \
    -edges {1 2 129} -add -master_clock gclk_sd_base [get_pins {clock_reset_management/bufgce_sd/O}];

create_generated_clock -name gclk_ddr2_ui \
    [get_pins {cartridge/ddr2_user_interface/ddr2_controller_interface/ddr2_controller/u_ddr2_controller_mig/u_ddr2_infrastructure/gen_mmcm.mmcm_i/CLKFBOUT}];


## Clock groups
## Объявляем асинхронные и взаимоисключающие группы сигналов тактирования

set_clock_groups -name log_ex_nes_to_sd -logically_exclusive    \
    -group [get_clocks {gclk_cpu gmclk_cpu gclk_ppu gmclk_ppu}] \
    -group [get_clocks {gclk_sd_base gclk_sd_high gclk_sd_low}];

set_clock_groups -name async_nes_to_vga -asynchronous \
    -group [get_clocks {gclk_ppu gmclk_ppu}] -group [get_clocks {gclk_vga}];

set_clock_groups -name phy_ex_sd -physically_exclusive \
    -group [get_clocks {gclk_sd_high}] -group [get_clocks {gclk_sd_low}];


## Async regs
## Объявляем регистры-синхронизаторы в местах пересечения доменов тактирования, параметры ASYNC_REG уже заданы в RTL и
## здесь добавлены для общей наглядности и перепроверки

set_property ASYNC_REG true [get_cells {input_devices/cross_uart_controller/rd_load_r_reg[*]}];

set_property ASYNC_REG true [get_cells {input_devices/cross_uart_controller/use_ack.wd_ack_r_reg[*]}];

set_property ASYNC_REG true [get_cells {cartridge/ddr2_user_interface/cross_read_prg/rd_load_r_reg[*]}];

set_property ASYNC_REG true [get_cells {cartridge/ddr2_user_interface/async_fifo_write_sd/wd_rgray_r_reg[*][*]}];

set_property ASYNC_REG true [get_cells {cartridge/ddr2_user_interface/async_fifo_write_sd/rd_wgray_r_reg[*][*]}];

set_property ASYNC_REG true [get_cells {cartridge/ddr2_user_interface/prg_rom_wr_ready_r_reg[*]}];


## Set max delays - datapaths delays
## Объявляем задержки при пересечении доменов тактирования

set gclk_uart_period [get_property PERIOD [get_clocks {gclk_uart}]];
set gclk_ddr2_ui_period [get_property PERIOD [get_clocks {gclk_ddr2_ui}]];
set prg_rom_rd_data_r_to_nes_delay [expr {$gclk_ddr2_ui_period * 2}];

set_max_delay -datapath_only                                                  \
    -from [get_pins {input_devices/cross_uart_controller/wd_data_r_reg[*]/C}] \
    -to [get_pins {input_devices/cross_uart_controller/rd_data_r_reg[*]/D}]   \
    $gclk_uart_period;

set_max_delay -datapath_only                                                \
    -from [get_pins {input_devices/cross_uart_controller/wd_load_r_reg/C}]  \
    -to [get_pins {input_devices/cross_uart_controller/rd_load_r_reg[0]/D}] \
    $gclk_uart_period;

set_max_delay -datapath_only                                                       \
    -from [get_pins {input_devices/cross_uart_controller/use_ack.rd_ack_r_reg/C}]  \
    -to [get_pins {input_devices/cross_uart_controller/use_ack.wd_ack_r_reg[0]/D}] \
    $gclk_uart_period;

set_max_delay -datapath_only                                                         \
    -from [get_pins {cartridge/ddr2_user_interface/cross_read_prg/wd_load_r_reg/C}]  \
    -to [get_pins {cartridge/ddr2_user_interface/cross_read_prg/rd_load_r_reg[0]/D}] \
    $gclk_ddr2_ui_period;

set_max_delay -datapath_only                                                           \
    -from [get_pins {cartridge/ddr2_user_interface/cross_read_prg/wd_data_r_reg[*]/C}] \
    -to [get_pins {cartridge/ddr2_user_interface/cross_read_prg/rd_data_r_reg[*]/D}]   \
    $gclk_ddr2_ui_period;

set_max_delay -datapath_only                                                    \
    -from [get_pins {cartridge/ddr2_user_interface/prg_rom_rd_data_r_reg[*]/C}] \
    -to [get_clocks {gclk_cpu gmclk_cpu gclk_ppu gmclk_ppu}] \
    $prg_rom_rd_data_r_to_nes_delay;

set_max_delay -datapath_only                                                                    \
    -from [get_pins {cartridge/ddr2_user_interface/async_fifo_write_sd/rd_rgray_r_reg[*]/C}]    \
    -to   [get_pins {cartridge/ddr2_user_interface/async_fifo_write_sd/wd_rgray_r_reg[0][*]/D}] \
    $gclk_ddr2_ui_period;

set_max_delay -datapath_only                                                                    \
    -from [get_pins {cartridge/ddr2_user_interface/async_fifo_write_sd/wd_wgray_r_reg[*]/C}]    \
    -to   [get_pins {cartridge/ddr2_user_interface/async_fifo_write_sd/rd_wgray_r_reg[0][*]/D}] \
    $gclk_ddr2_ui_period;

set_max_delay -datapath_only                                                   \
    -from [get_pins {cartridge/ddr2_user_interface/ui_ddr2_ready_r_reg/C}]     \
    -to [get_pins {cartridge/ddr2_user_interface/prg_rom_wr_ready_r_reg[0]/D}] \
    $gclk_ddr2_ui_period;


## Set false paths

set_false_path -to [get_ports {led_o[*]}];

set_false_path -to [get_ports {aud_sd_o}];

set_false_path -to [get_ports {aud_pwm_o}];

set_false_path -from [get_ports {sw_i[*]}];

set_false_path -from [get_ports {cpu_resetn_i}];

set_false_path -from [get_ports {uart_txd_i}];


## Set 3.3 voltage

set_property CFGBVS VCCO [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];


## Switches

set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {sw_i[0]}];
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports {sw_i[1]}];
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports {sw_i[2]}];
set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS33} [get_ports {sw_i[3]}];
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {sw_i[4]}];
set_property -dict {PACKAGE_PIN T18 IOSTANDARD LVCMOS33} [get_ports {sw_i[5]}];
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports {sw_i[6]}];
set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports {sw_i[7]}];
set_property -dict {PACKAGE_PIN T8  IOSTANDARD LVCMOS18} [get_ports {sw_i[8]}];
set_property -dict {PACKAGE_PIN U8  IOSTANDARD LVCMOS18} [get_ports {sw_i[9]}];
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {sw_i[10]}];
set_property -dict {PACKAGE_PIN T13 IOSTANDARD LVCMOS33} [get_ports {sw_i[11]}];
set_property -dict {PACKAGE_PIN H6  IOSTANDARD LVCMOS33} [get_ports {sw_i[12]}];
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports {sw_i[13]}];
set_property -dict {PACKAGE_PIN U11 IOSTANDARD LVCMOS33} [get_ports {sw_i[14]}];
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports {sw_i[15]}];


## LEDs

set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {led_o[0]}];
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {led_o[1]}];
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {led_o[2]}];
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports {led_o[3]}];
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {led_o[4]}];
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {led_o[5]}];
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {led_o[6]}];
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {led_o[7]}];
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {led_o[8]}];
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {led_o[9]}];
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {led_o[10]}];
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {led_o[11]}];
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {led_o[12]}];
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {led_o[13]}];
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {led_o[14]}];
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {led_o[15]}];


## Buttons

set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports {cpu_resetn_i}];
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {btnc_i}];


## VGA Connector

set_property -dict {PACKAGE_PIN A3 IOSTANDARD LVCMOS33} [get_ports {vga_red_o[0]}];
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS33} [get_ports {vga_red_o[1]}];
set_property -dict {PACKAGE_PIN C5 IOSTANDARD LVCMOS33} [get_ports {vga_red_o[2]}];
set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports {vga_red_o[3]}];

set_property -dict {PACKAGE_PIN C6 IOSTANDARD LVCMOS33} [get_ports {vga_green_o[0]}];
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports {vga_green_o[1]}];
set_property -dict {PACKAGE_PIN B6 IOSTANDARD LVCMOS33} [get_ports {vga_green_o[2]}];
set_property -dict {PACKAGE_PIN A6 IOSTANDARD LVCMOS33} [get_ports {vga_green_o[3]}];

set_property -dict {PACKAGE_PIN B7 IOSTANDARD LVCMOS33} [get_ports {vga_blue_o[0]}];
set_property -dict {PACKAGE_PIN C7 IOSTANDARD LVCMOS33} [get_ports {vga_blue_o[1]}];
set_property -dict {PACKAGE_PIN D7 IOSTANDARD LVCMOS33} [get_ports {vga_blue_o[2]}];
set_property -dict {PACKAGE_PIN D8 IOSTANDARD LVCMOS33} [get_ports {vga_blue_o[3]}];

set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33} [get_ports {vga_hsync_o}];
set_property -dict {PACKAGE_PIN B12 IOSTANDARD LVCMOS33} [get_ports {vga_vsync_o}];


## Micro SD Connector

set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS33} [get_ports {sd_disable_o}];
set_property -dict {PACKAGE_PIN A1 IOSTANDARD LVCMOS33} [get_ports {sd_ncd_i}];
set_property -dict {PACKAGE_PIN B1 IOSTANDARD LVCMOS33} [get_ports {sd_spi_clk_o}];
set_property -dict {PACKAGE_PIN C1 IOSTANDARD LVCMOS33} [get_ports {sd_spi_mosi_o}];
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports {sd_spi_miso_i}];
set_property -dict {PACKAGE_PIN D2 IOSTANDARD LVCMOS33} [get_ports {sd_spi_ncs_o}];


## PWM Audio Amplifier

set_property -dict {PACKAGE_PIN A11 IOSTANDARD LVCMOS33} [get_ports {aud_pwm_o}];
set_property -dict {PACKAGE_PIN D12 IOSTANDARD LVCMOS33} [get_ports {aud_sd_o}];


## USB-RS232 Interface

set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS33} [get_ports {uart_txd_i}];


## USB HID (PS/2)

set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports {ps2_clk_i}];
set_property -dict {PACKAGE_PIN B2 IOSTANDARD LVCMOS33} [get_ports {ps2_data_i}];
