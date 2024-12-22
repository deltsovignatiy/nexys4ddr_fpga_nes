
/*
 * Description : Top module of nexys4ddr_fpga_nes
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module nexys4ddr_fpga_nes_top
    (
        input  wire        sys_100mhz_clk_i,

        input  wire [15:0] sw_i,

        input  wire        cpu_resetn_i,
        input  wire        btnc_i,

        input  wire        ps2_clk_i,
        input  wire        ps2_data_i,

        input  wire        uart_txd_i,

        output wire [ 3:0] vga_red_o,
        output wire [ 3:0] vga_green_o,
        output wire [ 3:0] vga_blue_o,
        output wire        vga_hsync_o,
        output wire        vga_vsync_o,

        output wire        aud_sd_o,
        output wire        aud_pwm_o,

        output wire [15:0] led_o,

        output wire        sd_disable_o,
        input  wire        sd_ncd_i,
        output wire        sd_spi_clk_o,
        output wire        sd_spi_mosi_o,
        input  wire        sd_spi_miso_i,
        output wire        sd_spi_ncs_o,

        inout  wire [15:0] ddr2_dq,
        inout  wire [ 1:0] ddr2_dqs_n,
        inout  wire [ 1:0] ddr2_dqs_p,
        output wire [12:0] ddr2_addr,
        output wire [ 2:0] ddr2_ba,
        output wire        ddr2_ras_n,
        output wire        ddr2_cas_n,
        output wire        ddr2_we_n,
        output wire [ 0:0] ddr2_ck_p,
        output wire [ 0:0] ddr2_ck_n,
        output wire [ 0:0] ddr2_cke,
        output wire [ 0:0] ddr2_cs_n,
        output wire [ 1:0] ddr2_dm,
        output wire [ 0:0] ddr2_odt
    );


    // Параметры для UART
    localparam UART_CLK_FREQ_HZ = 100000000;
    localparam UART_BAUDRATE    = 115200;


    // Входные сигналы сброса и тактирования
    wire        sys_main_arstn_w;
    wire        sys_nes_arstn_w;

    // Сигналы тактирования и синхронных сбросов
    wire        cpu_clk_w;
    wire        cpu_mclk_w;
    wire        cpu_rst_w;
    wire        ppu_clk_w;
    wire        ppu_mclk_w;
    wire        ppu_rst_w;
    wire        uart_clk_w;
    wire        uart_rst_w;
    wire        vga_clk_w;
    wire        vga_rst_w;
    wire        sd_adjust_clk_w;
    wire        sd_full_nobuf_clk_w;
    wire        sd_rst_w;
    wire        ddr2_cntrl_clk_w;
    wire        ddr2_cntrl_rst_w;

    // Сигналы логики считывания данных игры с SD-карты
    wire        sd_clk_full_speed_w;
    wire        nes_boot_complete_w;
    wire [ 7:0] nes_game_index_w;

    // Физический уровень интерфейса SPI для работы с SD-картами
    wire        sd_spi_ncs_val_w;
    wire        sd_spi_ncs_en_w;
    wire        sd_spi_mosi_val_w;
    wire        sd_spi_mosi_en_w;

    // Сигналы и данные аудио
    wire [15:0] apu_output_w;
    wire        dac_output_w;

    // Интерфейс графичесrого процессора NES
    wire        ppu_wr_w;
    wire        ppu_rd_w;
    wire [ 2:0] ppu_addr_w;
    wire [ 7:0] ppu_wr_data_w;
    wire [ 7:0] ppu_rd_data_w;
    wire        ppu_nmi_w;
    wire [ 7:0] ppu_output_pixel_w;
    wire [ 8:0] ppu_x_pos_w;
    wire [ 8:0] ppu_y_pos_w;
    wire [ 2:0] nametable_layout_w;

    // Интерфейс постоянной памяти картриджа (код игры)
    wire        prg_rom_mclk_w;
    wire        prg_rom_rst_w;
    wire        prg_rom_rd_w;
    wire [14:0] prg_rom_addr_w;
    wire [ 7:0] prg_rom_rd_data_w;

    // Интерфейс оперативной памяти картриджа
    wire        prg_ram_mclk_w;
    wire        prg_ram_wr_w;
    wire        prg_ram_rd_w;
    wire [12:0] prg_ram_addr_w;
    wire [ 7:0] prg_ram_wr_data_w;
    wire [ 7:0] prg_ram_rd_data_w;

    // Интерфейс памяти графических знаков (тайлов)
    wire        chr_mem_mclk_w;
    wire        chr_mem_wr_w;
    wire        chr_mem_rd_w;
    wire [12:0] chr_mem_addr_w;
    wire [ 7:0] chr_mem_wr_data_w;
    wire [ 7:0] chr_mem_rd_data_w;

    // Интерфейс мапперов
    wire        mapper_clk_w;
    wire        mapper_rst_w;
    wire        mapper_wr_w;
    wire [14:0] mapper_addr_w;
    wire [ 7:0] mapper_wr_data_w;
    wire        mapper_irq_w;

    // Сигналы и данные с входных контроллеров NES
    wire [ 7:0] device_1_input_w;
    wire [ 7:0] device_2_input_w;
    wire        devices_swap_sel_w;
    wire        devices_led_sel_w;

    // Сигналы статуса и дебага процессора
    wire        new_instruction_w;
    wire        state_invalid_w;


    assign sys_main_arstn_w   = sw_i[0] && ~btnc_i;
    assign aud_sd_o           = sw_i[1];
    assign devices_swap_sel_w = sw_i[2];
    assign devices_led_sel_w  = sw_i[3];
    assign nes_game_index_w   = sw_i[15:8];

    assign sys_nes_arstn_w    = cpu_resetn_i;

    assign led_o[   0]        = sys_main_arstn_w;
    assign led_o[   1]        = ~cpu_rst_w;
    assign led_o[   2]        = new_instruction_w;
    assign led_o[   3]        = ppu_wr_w || ppu_rd_w;
    assign led_o[   4]        = ppu_nmi_w;
    assign led_o[   5]        = ~sd_ncd_i;
    assign led_o[   6]        = ~sd_disable_o;
    assign led_o[   7]        = nes_boot_complete_w;
    assign led_o[15:8]        = (~sys_main_arstn_w) ? nes_game_index_w :
                                (devices_led_sel_w) ? device_2_input_w : device_1_input_w;


    // Буферы с третьим сосоянием для выходов интерфейса SPI
    assign sd_spi_mosi_o = (sd_spi_mosi_en_w) ? sd_spi_mosi_val_w : 1'bZ;
    assign sd_spi_ncs_o  = (sd_spi_ncs_en_w ) ? sd_spi_ncs_val_w  : 1'bZ;

    // Буфер с третьим состоянием для выхода ЦАП
    assign aud_pwm_o     = (dac_output_w) ? 1'bZ : 1'b0;


    // Логика генерации необходимых в системе сигналов тактирования и синхронизация сбросов
    clock_reset_management
        clock_reset_management
        (
            .sys_100mhz_clk_i   (sys_100mhz_clk_i   ),
            .sys_main_arstn_i   (sys_main_arstn_w   ),
            .sys_nes_arstn_i    (sys_nes_arstn_w    ),

            .sd_clk_full_speed_i(sd_clk_full_speed_w),
            .nes_boot_complete_i(nes_boot_complete_w),

            .cpu_clk_o          (cpu_clk_w          ),
            .cpu_mclk_o         (cpu_mclk_w         ),
            .cpu_rst_o          (cpu_rst_w          ),

            .ppu_clk_o          (ppu_clk_w          ),
            .ppu_mclk_o         (ppu_mclk_w         ),
            .ppu_rst_o          (ppu_rst_w          ),

            .uart_clk_o         (uart_clk_w         ),
            .uart_rst_o         (uart_rst_w         ),

            .vga_clk_o          (vga_clk_w          ),
            .vga_rst_o          (vga_rst_w          ),

            .ddr2_cntrl_clk_o   (ddr2_cntrl_clk_w   ),
            .ddr2_cntrl_rst_o   (ddr2_cntrl_rst_w   ),

            .sd_adjust_clk_o    (sd_adjust_clk_w    ),
            .sd_full_nobuf_clk_o(sd_full_nobuf_clk_w),
            .sd_rst_o           (sd_rst_w           )
        );


    /* Логика картриджа для NES. Непосредственно картридж игры содержит:
     * постоянную память программы-игры (PRG),
     * память графических знаков (тайлов) для рендера изображения (CHR)
     * (в зависимости от конкретной игры может использоваться постоянная ROM или перезаписываемая RAM память),
     * опционально (так же в зависимости от конкретной игры) может использоваться дополнительная RAM память для
     * данных игры (в частности использующуюся для сохранений),
     * логику маппера (так же отличающуюся в зависимости от кокретной игры) для расширения доступного адресного
     * пространства для кода игры (PRG) и графических данных (CHR).
     * Помимо логики самого картриджа модуль содержит логику и контроллеры для считывания данных игры с SD-карт и
     * для работы с DDR памятью, в которую записывается и из которой читается и исполняется код игры (PRG) */
    cartridge
        cartridge
        (
            .prg_rom_mclk_i     (prg_rom_mclk_w     ),
            .prg_rom_rst_i      (prg_rom_rst_w      ),
            .prg_rom_rd_i       (prg_rom_rd_w       ),
            .prg_rom_addr_i     (prg_rom_addr_w     ),
            .prg_rom_rd_data_o  (prg_rom_rd_data_w  ),

            .prg_ram_mclk_i     (prg_ram_mclk_w     ),
            .prg_ram_wr_i       (prg_ram_wr_w       ),
            .prg_ram_rd_i       (prg_ram_rd_w       ),
            .prg_ram_addr_i     (prg_ram_addr_w     ),
            .prg_ram_wr_data_i  (prg_ram_wr_data_w  ),
            .prg_ram_rd_data_o  (prg_ram_rd_data_w  ),

            .chr_mem_mclk_i     (chr_mem_mclk_w     ),
            .chr_mem_wr_i       (chr_mem_wr_w       ),
            .chr_mem_rd_i       (chr_mem_rd_w       ),
            .chr_mem_addr_i     (chr_mem_addr_w     ),
            .chr_mem_wr_data_i  (chr_mem_wr_data_w  ),
            .chr_mem_rd_data_o  (chr_mem_rd_data_w  ),

            .mapper_clk_i       (mapper_clk_w       ),
            .mapper_rst_i       (mapper_rst_w       ),
            .mapper_wr_i        (mapper_wr_w        ),
            .mapper_addr_i      (mapper_addr_w      ),
            .mapper_wr_data_i   (mapper_wr_data_w   ),

            .nametable_layout_o (nametable_layout_w ),

            .mapper_irq_o       (mapper_irq_w       ),

            .sd_adjust_clk_i    (sd_adjust_clk_w    ),
            .sd_full_nobuf_clk_i(sd_full_nobuf_clk_w),
            .sd_rst_i           (sd_rst_w           ),
            .sd_disable_o       (sd_disable_o       ),
            .sd_clk_full_speed_o(sd_clk_full_speed_w),
            .nes_boot_complete_o(nes_boot_complete_w),
            .nes_game_index_i   (nes_game_index_w   ),

            .spi_clk_o          (sd_spi_clk_o       ),
            .spi_ncs_o          (sd_spi_ncs_val_w   ),
            .spi_ncs_en_o       (sd_spi_ncs_en_w    ),
            .spi_mosi_o         (sd_spi_mosi_val_w  ),
            .spi_mosi_en_o      (sd_spi_mosi_en_w   ),
            .spi_miso_i         (sd_spi_miso_i      ),

            .ddr2_cntrl_clk_i   (ddr2_cntrl_clk_w   ),
            .ddr2_cntrl_rst_i   (ddr2_cntrl_rst_w   ),
            .ddr2_addr_o        (ddr2_addr          ),
            .ddr2_ba_o          (ddr2_ba            ),
            .ddr2_ras_n_o       (ddr2_ras_n         ),
            .ddr2_cas_n_o       (ddr2_cas_n         ),
            .ddr2_we_n_o        (ddr2_we_n          ),
            .ddr2_ck_p_o        (ddr2_ck_p          ),
            .ddr2_ck_n_o        (ddr2_ck_n          ),
            .ddr2_cke_o         (ddr2_cke           ),
            .ddr2_cs_n_o        (ddr2_cs_n          ),
            .ddr2_dm_o          (ddr2_dm            ),
            .ddr2_odt_o         (ddr2_odt           ),
            .ddr2_dq_io         (ddr2_dq            ),
            .ddr2_dqs_p_io      (ddr2_dqs_p         ),
            .ddr2_dqs_n_io      (ddr2_dqs_n         )
        );


    /* Логика микросхемы RP2A03: центральный процессор, аудиопроцессор,
     * контроллер прямого доступа к процессорной шине */
    cpu_RP2A03
        cpu
        (
            .clk_i              (cpu_clk_w          ),
            .mclk_i             (cpu_mclk_w         ),
            .rst_i              (cpu_rst_w          ),

            .ppu_nmi_i          (ppu_nmi_w          ),
            .mapper_irq_i       (mapper_irq_w       ),

            .prg_rom_mclk_o     (prg_rom_mclk_w     ),
            .prg_rom_rst_o      (prg_rom_rst_w      ),
            .prg_rom_rd_o       (prg_rom_rd_w       ),
            .prg_rom_addr_o     (prg_rom_addr_w     ),
            .prg_rom_rd_data_i  (prg_rom_rd_data_w  ),

            .prg_ram_mclk_o     (prg_ram_mclk_w     ),
            .prg_ram_wr_o       (prg_ram_wr_w       ),
            .prg_ram_rd_o       (prg_ram_rd_w       ),
            .prg_ram_addr_o     (prg_ram_addr_w     ),
            .prg_ram_wr_data_o  (prg_ram_wr_data_w  ),
            .prg_ram_rd_data_i  (prg_ram_rd_data_w  ),

            .ppu_wr_o           (ppu_wr_w           ),
            .ppu_rd_o           (ppu_rd_w           ),
            .ppu_addr_o         (ppu_addr_w         ),
            .ppu_wr_data_o      (ppu_wr_data_w      ),
            .ppu_rd_data_i      (ppu_rd_data_w      ),

            .mapper_clk_o       (mapper_clk_w       ),
            .mapper_rst_o       (mapper_rst_w       ),
            .mapper_wr_o        (mapper_wr_w        ),
            .mapper_addr_o      (mapper_addr_w      ),
            .mapper_wr_data_o   (mapper_wr_data_w   ),

            .device_1_input_i   (device_1_input_w   ),
            .device_2_input_i   (device_2_input_w   ),

            .apu_output_o       (apu_output_w       ),

            .new_instruction_o  (new_instruction_w  ),
            .state_invalid_o    (state_invalid_w    )
        );


    // Логика микросхемы RP2C02 — графический процессор NES
    ppu_RP2C02
        ppu
        (
            .clk_i              (ppu_clk_w          ),
            .mclk_i             (ppu_mclk_w         ),
            .rst_i              (ppu_rst_w          ),

            .chr_mem_mclk_o     (chr_mem_mclk_w     ),
            .chr_mem_rd_o       (chr_mem_rd_w       ),
            .chr_mem_wr_o       (chr_mem_wr_w       ),
            .chr_mem_addr_o     (chr_mem_addr_w     ),
            .chr_mem_wr_data_o  (chr_mem_wr_data_w  ),
            .chr_mem_rd_data_i  (chr_mem_rd_data_w  ),

            .ppu_wr_i           (ppu_wr_w           ),
            .ppu_rd_i           (ppu_rd_w           ),
            .ppu_addr_i         (ppu_addr_w         ),
            .ppu_wr_data_i      (ppu_wr_data_w      ),
            .ppu_rd_data_o      (ppu_rd_data_w      ),

            .nametable_layout_i (nametable_layout_w ),

            .ppu_nmi_o          (ppu_nmi_w          ),

            .ppu_output_pixel_o (ppu_output_pixel_w ),
            .ppu_x_pos_o        (ppu_x_pos_w        ),
            .ppu_y_pos_o        (ppu_y_pos_w        )
        );


    /* Логика вывода изображения: буфер для преобразования разрешения
     * изображения NES -> VGA и контроллер VGA */
    video_output_controller
        video_output_controller
        (
            .ppu_clk_i          (ppu_clk_w          ),

            .vga_clk_i          (vga_clk_w          ),
            .vga_rst_i          (vga_rst_w          ),

            .ppu_output_pixel_i (ppu_output_pixel_w ),
            .ppu_x_pos_i        (ppu_x_pos_w        ),
            .ppu_y_pos_i        (ppu_y_pos_w        ),

            .vga_hsync_o        (vga_hsync_o        ),
            .vga_vsync_o        (vga_vsync_o        ),
            .vga_red_o          (vga_red_o          ),
            .vga_green_o        (vga_green_o        ),
            .vga_blue_o         (vga_blue_o         )
        );


    /* Логика входных устройств NES ("геймпадов"), в этом качестве выступают
     * клавиатуры, подключенные через USB <-> PS/2 мост (контроллер 1) и
     * USB <-> UART мост (контроллер 2) */
    input_devices
        #(
            .UART_CLK_FREQ_HZ   (UART_CLK_FREQ_HZ   ),
            .UART_BAUDRATE      (UART_BAUDRATE      )
        )
        input_devices
        (
            .cpu_clk_i          (cpu_clk_w          ),
            .cpu_rst_i          (cpu_rst_w          ),

            .uart_clk_i         (uart_clk_w         ),
            .uart_rst_i         (uart_rst_w         ),
            .uart_rxd_i         (uart_txd_i         ), // TXD -> RXD

            .ps2_clk_i          (ps2_clk_i          ),
            .ps2_data_i         (ps2_data_i         ),

            .devices_swap_sel_i (devices_swap_sel_w ),
            .device_1_input_o   (device_1_input_w   ),
            .device_2_input_o   (device_2_input_w   )
        );


    // Логика вывода аудио — цифро-аналоговый преобразователь (дельта-сигма модулятор)
    dsm_dac
        #(
            .DATA_WIDTH         (16                 ),
            .DSM_ORDER          (1                  )
        )
        dac
        (
            .clk_i              (cpu_clk_w          ),
            .rst_i              (cpu_rst_w          ),

            .input_i            (apu_output_w       ),
            .output_o           (dac_output_w       )
        );


endmodule
