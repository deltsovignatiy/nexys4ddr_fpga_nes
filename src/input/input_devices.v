
/*
 * Description : NES input devices (PS/2 controller and UART controller) module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 *
 * NES gamepad "A"      — keyboard "Q"
 * NES gamepad "B"      — keyboard "W"
 * NES gamepad "SELECT" — keyboard "SPACE"
 * NES gamepad "START"  — keyboard "ENTER"
 * NES gamepad "UP"     — keyboard "UP ARROW"    or "8 NUMPAD"
 * NES gamepad "DOWN"   — keyboard "DOWN ARROW"  or "2 NUMPAD"
 * NES gamepad "LEFT"   — keyboard "LEFT ARROW"  or "4 NUMPAD"
 * NES gamepad "RIGHT"  — keyboard "RIGHT ARROW" or "6 NUMPAD"
 */


module input_devices
    #(
        parameter UART_CLK_FREQ_HZ = 115200000, // Частота сигнала тактирования
        parameter UART_BAUDRATE    = 921600     // Бодрейт UART
    )
    (
        input  wire       cpu_clk_i,            // Сигнал тактирования центрального процессора
        input  wire       cpu_rst_i,            // Сигнал сброса центрального процессора

        input  wire       uart_clk_i,           // Сигнал тактирования контроллера UART
        input  wire       uart_rst_i,           // Сигнал сброса контроллера UART
        input  wire       uart_rxd_i,           // Сигнал UART интерфейса — "RXD" вход данных

        input  wire       ps2_clk_i,            // Сигнал PS/2 интерфейса — тактирование
        input  wire       ps2_data_i,           // Сигнал PS/2 интерфейса — данные

        input  wire       devices_swap_sel_i,   // Поменять местами данные устройств ввода
        output wire [7:0] device_1_input_o,     // Данные 1-го устройства ввода
        output wire [7:0] device_2_input_o      // Данные 2-го устройства ввода
    );


    wire [7:0] uart_data_w;
    wire       uart_data_valid_w;

    wire       cross_uart_ready_w;
    wire [7:0] cross_uart_data_w;
    wire       cross_uart_data_valid_w;

    wire [7:0] ps2_data_w;
    wire       ps2_data_valid_w;

    wire       swap_sel_gated_w;

    reg  [7:0] device_1_data_r;
    reg  [7:0] device_1_data_next_r;
    reg  [7:0] device_2_data_r;
    reg  [7:0] device_2_data_next_r;


    // Защёлкиваем данные с входных устройств
    always @(posedge cpu_clk_i)
        if (cpu_rst_i) begin
            device_1_data_r <= 8'h0;
            device_2_data_r <= 8'h0;
        end else begin
            device_1_data_r <= device_1_data_next_r;
            device_2_data_r <= device_2_data_next_r;
        end

    always @(*)
        if (swap_sel_gated_w) begin
            device_1_data_next_r = (cross_uart_data_valid_w) ? cross_uart_data_w : device_1_data_r;
            device_2_data_next_r = (ps2_data_valid_w       ) ? ps2_data_w        : device_2_data_r;
        end else begin
            device_1_data_next_r = (ps2_data_valid_w       ) ? ps2_data_w        : device_1_data_r;
            device_2_data_next_r = (cross_uart_data_valid_w) ? cross_uart_data_w : device_2_data_r;
        end


    // Фильтр сигнала devices_swap_sel_i
    input_filter
        #(
            .LENGTH             (3                   ),
            .RESET_VALUE        (1                   )
        )
        swap_sel_filter
        (
            .clk_i              (cpu_clk_i           ),
            .rst_i              (cpu_rst_i           ),

            .in_i               (devices_swap_sel_i  ),
            .en_i               (1'b1                ),
            .out_o              (swap_sel_gated_w    )
        );


    // Контроллер UART приёмника (No parity bit, 1 stop bit)
    uart_controller
        #(
            .CLK_FREQ_HZ        (UART_CLK_FREQ_HZ    ),
            .BAUDRATE           (UART_BAUDRATE       )
        )
        uart_controller
        (
            .clk_i              (uart_clk_i          ),
            .rst_i              (uart_rst_i          ),

            .rxd_i              (uart_rxd_i          ),

            .buffer_ready_i     (cross_uart_ready_w  ),
            .data_o             (uart_data_w         ),
            .data_valid_o       (uart_data_valid_w   )
        );


    /* Логика пересечения тактовых доменов для перевода принятых
     * по UART данных в домен центрального процессора */
    cross_clock_path
        #(
            .DATA_WIDTH         (8                      ),
            .USE_ACKNOWLEDGEMENT("TRUE"                 )
        )
        cross_uart_controller
        (
            .wd_clk_i           (uart_clk_i             ),
            .wd_rst_i           (uart_rst_i             ),
            .wd_valid_i         (uart_data_valid_w      ),
            .wd_data_i          (uart_data_w            ),
            .wd_ready_o         (cross_uart_ready_w     ),

            .rd_clk_i           (cpu_clk_i              ),
            .rd_rst_i           (cpu_rst_i              ),
            .rd_ready_i         (1'b1                   ),
            .rd_data_o          (cross_uart_data_w      ),
            .rd_valid_o         (cross_uart_data_valid_w)
        );


    // Контроллер PS/2 приёмника
    ps2_controller
        ps2_controller
        (
            .clk_i              (cpu_clk_i              ),
            .rst_i              (cpu_rst_i              ),

            .ps2_clk_i          (ps2_clk_i              ),
            .ps2_data_i         (ps2_data_i             ),

            .buffer_ready_i     (1'b1                   ),
            .data_o             (ps2_data_w             ),
            .data_valid_o       (ps2_data_valid_w       )
        );


    assign device_1_input_o = device_1_data_r;
    assign device_2_input_o = device_2_data_r;


endmodule
