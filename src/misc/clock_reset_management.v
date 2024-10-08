
/*
 * Description : Clock signals generation and reset signals synchronization module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


`include "defines.vh"


module clock_reset_management
    (
        input  wire sys_100mhz_clk_i,    // Входной сигнал тактирования 100 МГц
        input  wire sys_main_arstn_i,    // Входной сброс всей системы
        input  wire sys_nes_arstn_i,     // Входной сброс логики NES

        input  wire sd_clk_full_speed_i, // Переключение частоты тактирования логики работы с SD картой на полную скорость
        input  wire nes_boot_complete_i, // Образ игры загружен с SD-карты и готов к исполнению

        output wire cpu_clk_o,           // Сигнал тактирования центрального процессора NES 1.789 МГц
        output wire cpu_mclk_o,          // Сигнал тактирования памяти центрального процессора NES 1.789 МГц (negedge)
        output wire cpu_rst_o,           // Сигнал синхронизированного сброса центрального процессора NES

        output wire ppu_clk_o,           // Сигнал тактирования графического процессора NES 5.369 МГц
        output wire ppu_mclk_o,          // Сигнал тактирования памяти графического процессора NES 5.369 МГц (negedge)
        output wire ppu_rst_o,           // Сигнал синхронизированного сброса графического процессора NES

        output wire uart_clk_o,          // Сигнал тактирования контроллера UART 115.200 МГц
        output wire uart_rst_o,          // Сигнал синхронизированного сброса контроллера UART

        output wire vga_clk_o,           // Сигнал тактирования контроллера VGA 25.173 МГц
        output wire vga_rst_o,           // Сигнал синхронизированного сброса контроллера VGA

        output wire ddr2_cntrl_clk_o,    // Сигнал тактирования контроллера DDR памяти 200.000 МГц
        output wire ddr2_cntrl_rst_o,    // Сигнал синхронизированного сброса DDR памяти

        output wire sd_adjust_clk_o,     // Регулирумый сигнал тактирования контроллера SD-карт 781.250 КГц -> 50.000 МГц
        output wire sd_full_nobuf_clk_o, // Сигнал тактирования котроллера SD-карт без буфера для мультиплексора
        output wire sd_rst_o             // Сигнал синхронизированного сброса контроллера SD-карт
    );


    wire       _100mhz_clk_w;
    wire       _100mhz_rst_w;

    wire       _200mhz_clk_w;
    wire       _200mhz_rst_w;

    wire       _50mhz_clk_w;
    wire       _50mhz_rst_w;
    wire       _50mhz_no_buf_clk_w;
    wire       clk_wiz_sd_fb_out_w;
    wire       clk_wiz_sd_fb_in_w;

    wire       _25mhz_clk_w;
    wire       _25mhz_rst_w;

    wire       _5mhz369_clk_w;
    wire       _5mhz369_mclk_w;
    wire       _5mhz369_rst_w;

    reg  [1:0] _1mhz789_counter_r;
    wire [1:0] _1mhz789_counter_next_w;
    wire       _1mhz789_clk_period_w;
    reg        _1mhz789_mclk_period_r;
    wire       _1mhz789_clk_w;
    wire       _1mhz789_mclk_w;

    reg        sd_clk_full_speed_r;
    reg  [5:0] _781khz250_counter_r;
    wire [5:0] _781khz250_counter_next_w;
    wire       _781khz250_clk_period_w;
    wire       _781khz250_50mhz_clk_w;

    reg        nes_boot_complete_r;
    wire       nes_arstn_w;
    wire       sd_clk_select_w;
    wire       sd_clk_enable_w;


    /* Генерация сигналов тактирования:
     * clk_out1 — 100.000 МГц для MMCM "clk_wiz_ppu" и контроллера UART,
     * clk_out2 — 200.000 МГц для контроллера DDR памяти,
     * clk_out3 — 25.000  МГц для контроллера VGA */
    clocking_wizard_main
        clk_wiz_main
        (
            .clk_out1    (_100mhz_clk_w         ),
            .clk_out2    (_200mhz_clk_w         ),
            .clk_out3    (_25mhz_clk_w          ),
            .clk_in1     (sys_100mhz_clk_i      )
        );


    /* Генерация базового (полноскоростного) сигнала тактирования 50.000 МГц
     * без выходного буфера. Этот сигнал используется для формирования с помощью BUFGCE
     * буфера регулируемого тактирования контроллера SD-карт и связанной с ним логики
     * (пониженная частота требуется в процессе инициализации SD-карты), а также для
     * использования в мультиплексоре тактирования chr_mem_mclk_mux_ctrl блочной памяти
     * chr_mem в модуле cartridge (тактирование от SD-карты требуется в процессе загрузки данных
     * в блочную память с SD-карты, после завершения загрузки память тактируется сигналом от PPU).
     * Такая усложнённая реализация вызвана необходимостью купировать неоптимальное размещение
     * BUFG-BUFG пары буферов [Place 30-120]. В качестве альтернативного варианта можно было бы
     * отказаться от мультиплексирования тактирования для памяти chr_mem в модуле cartridge
     * в пользу её двухпортовости */
    clocking_wizard_sd
        clk_wiz_sd
        (
            .clk_out1    (_50mhz_no_buf_clk_w   ),
            .clk_in1     (_100mhz_clk_w         ),
            .clkfb_in    (clk_wiz_sd_fb_in_w    ),
            .clkfb_out   (clk_wiz_sd_fb_out_w   )
        );


    /* Буфер BUFG для сигнала тактирования 50.000 МГц для логики синхронизации
     * сброса и логики сигнала разрешения работы буфера BUFGCE (регулируемое
     * тактирование контроллера SD-карт) */
    BUFG
        bufg_sd
        (
            .O           (_50mhz_clk_w          ),
            .I           (_50mhz_no_buf_clk_w   )
        );


    // Буфер BUFG для сигнала обратной связи модуля clk_wiz_sd
    BUFG
        bufg_sdfb
        (
            .O           (clk_wiz_sd_fb_in_w    ),
            .I           (clk_wiz_sd_fb_out_w   )
        );


    /* Генерация сигнала тактирования 5.369 МГц для графического процессора NES,
     * также является базовой частотой для формирования сигнала тактирования
     * для центрального процессора NES */
    clocking_wizard_ppu
        clk_wiz_ppu
        (
            .clk_out1    (_5mhz369_clk_w        ),
            .clk_out2    (_5mhz369_mclk_w       ),
            .clk_in1     (_100mhz_clk_w         )
        );


    // Синхронизация сброса контроллера DDR памяти
    reset_synchronizer
        reset_synchronizer_ddr_cntrl
        (
            .clk_i       (_200mhz_clk_w         ),
            .rstn_async_i(sys_main_arstn_i      ),
            .rst_sync_o  (_200mhz_rst_w         )
        );


    // Синхронизация сброса контроллера SD-карт
    reset_synchronizer
        reset_synchronizer_sd
        (
            .clk_i       (_50mhz_clk_w          ),
            .rstn_async_i(sys_main_arstn_i      ),
            .rst_sync_o  (_50mhz_rst_w          )
        );


    // Синхронизация сброса контроллера UART
    reset_synchronizer
        reset_synchronizer_uart
        (
            .clk_i       (_100mhz_clk_w         ),
            .rstn_async_i(sys_main_arstn_i      ),
            .rst_sync_o  (_100mhz_rst_w         )
        );


    // Синхронизация сброса контроллера VGA
    reset_synchronizer
        reset_synchronizer_vga
        (
            .clk_i       (_25mhz_clk_w          ),
            .rstn_async_i(sys_main_arstn_i      ),
            .rst_sync_o  (_25mhz_rst_w          )
        );


    // Синхронизация сброса NES
    reset_synchronizer
        reset_synchronizer_nes
        (
            .clk_i       (_5mhz369_clk_w        ),
            .rstn_async_i(nes_arstn_w           ),
            .rst_sync_o  (_5mhz369_rst_w        )
        );


    // Логика формирования сигнала тактирования 1.789 МГц для центрального процессора NES
    always @(posedge _5mhz369_clk_w)
        begin
            _1mhz789_counter_r     <= _1mhz789_counter_next_w;
            _1mhz789_mclk_period_r <= _1mhz789_clk_period_w;
        end

    // _1mhz789_counter_r == (5mhz369/1mhz789 - 1) == (3 - 1)
    assign _1mhz789_clk_period_w   = (_1mhz789_counter_r == 2'd2);

    assign _1mhz789_counter_next_w = (_1mhz789_clk_period_w) ? 2'd0 : _1mhz789_counter_r + 1'b1;


    /* Делитель частоты на буфере с сигналом разрешения работы,
     * сигнал тактирования центрального процессора NES */
    BUFGCE
        #(
            .SIM_DEVICE  ("7SERIES"             ),
            .CE_TYPE     ("SYNC"                ) // Значение по умолчанию, для наглядности
        )
        bufgce_cpu
        (
            .O           (_1mhz789_clk_w        ),
            .CE          (_1mhz789_clk_period_w ),
            .I           (_5mhz369_clk_w        )
        );


    /* Делитель частоты на буфере с сигналом разрешения работы,
     * сигнал тактирования памяти центрального процессора NES */
    BUFGCE
        #(
            .SIM_DEVICE  ("7SERIES"             ),
            .CE_TYPE     ("SYNC"                ) // Значение по умолчанию, для наглядности
        )
        bufgce_cpu_mem
        (
            .O           (_1mhz789_mclk_w       ),
            .CE          (_1mhz789_mclk_period_r),
            .I           (_5mhz369_mclk_w       )
        );


    /* Логика формирования регулируемого сигнала тактирования (частота 50.000 МГц или 781.250 КГц)
     * для контроллера SD-карты и связанной с ним логики */
    always @(posedge _50mhz_clk_w)
        if (_50mhz_rst_w) begin
            sd_clk_full_speed_r  <= 1'b0;
            nes_boot_complete_r  <= 1'b0;
        end else begin
            sd_clk_full_speed_r  <= sd_clk_full_speed_i;
            nes_boot_complete_r  <= nes_boot_complete_i;
        end

    always @(posedge _50mhz_clk_w)
        begin
            _781khz250_counter_r <= _781khz250_counter_next_w;
        end

    // _781khz250_counter_r == (50mhz/781khz - 1) == (64 - 1)
    assign _781khz250_clk_period_w   = &_781khz250_counter_r;

    assign _781khz250_counter_next_w = _781khz250_counter_r + 1'b1;

    // sd_clk = (sd_clk_full_speed_r) ? 50 MHz : 781 KHz;
    assign sd_clk_select_w           = sd_clk_full_speed_r || _781khz250_clk_period_w;

    assign sd_clk_enable_w           = (nes_boot_complete_r) ? 1'b0 : sd_clk_select_w;

    // Сброс основной логики NES, зависящий от результата загрузки образа
    assign nes_arstn_w               = nes_boot_complete_r && sys_nes_arstn_i;


    /* Делитель частоты на буфере с сигналом разрешения работы,
     * сигнал тактирования контроллера SD-карт и связанной с ним логики */
    BUFGCE
        #(
            .SIM_DEVICE  ("7SERIES"             ),
            .CE_TYPE     ("SYNC"                ) // Значение по умолчанию, для наглядности
        )
        bufgce_sd
        (
            .O           (_781khz250_50mhz_clk_w),
            .CE          (sd_clk_enable_w       ),
            .I           (_50mhz_no_buf_clk_w   )
        );


    // Выходы
    assign cpu_clk_o           = _1mhz789_clk_w;
    assign cpu_mclk_o          = _1mhz789_mclk_w;
    assign cpu_rst_o           = _5mhz369_rst_w;

    assign ppu_clk_o           = _5mhz369_clk_w;
    assign ppu_mclk_o          = _5mhz369_mclk_w;
    assign ppu_rst_o           = _5mhz369_rst_w;

    assign uart_clk_o          = _100mhz_clk_w;
    assign uart_rst_o          = _100mhz_rst_w;

    assign vga_clk_o           = _25mhz_clk_w;
    assign vga_rst_o           = _25mhz_rst_w;

    assign sd_adjust_clk_o     = _781khz250_50mhz_clk_w;
    assign sd_full_nobuf_clk_o = _50mhz_no_buf_clk_w;
    assign sd_rst_o            = _50mhz_rst_w;

    assign ddr2_cntrl_clk_o    = _200mhz_clk_w;
    assign ddr2_cntrl_rst_o    = _200mhz_rst_w;


    // Для симуляции
`ifdef SIMULATION
    initial begin
        _1mhz789_counter_r     = $urandom();
        _1mhz789_mclk_period_r = $urandom();
        _781khz250_counter_r   = $urandom();
    end
`endif


endmodule
