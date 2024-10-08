
/*
 * Description : UART controller (receiver with input "RXD" filter) module, no parity bit, 1 stop bit
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module uart_controller
    #(
        parameter CLK_FREQ_HZ = 115200000, // Частота сигнала тактирования
        parameter BAUDRATE    = 921600     // Бодрейт UART
    )
    (
        input  wire       clk_i,           // Сигнал тактирования
        input  wire       rst_i,           // Сигнал сброса

        input  wire       rxd_i,           // Сигнал UART интерфейса — "RXD" вход данных
        input  wire       buffer_ready_i,  // Сигнал готовности к приёму выходных данных
        output wire [7:0] data_o,          // Выходные данные
        output wire       data_valid_o     // Сигнал валидности выходных данных
    );


    // Сигнал входного фильтра
    wire rxd_gated_w;


    // Фильтр входных данных
    input_filter
        #(
            .LENGTH             (3             ),
            .RESET_VALUE        (1             )
        )
        rx_filter
        (
            .clk_i              (clk_i         ),
            .rst_i              (rst_i         ),

            .in_i               (rxd_i         ),
            .en_i               (1'b1          ),
            .out_o              (rxd_gated_w   )
        );


    // Логика UART приёмника
    uart_receiver
        #(
            .CLK_FREQ_HZ        (CLK_FREQ_HZ   ),
            .BAUDRATE           (BAUDRATE      )
        )
        receiver
        (
            .clk_i              (clk_i         ),
            .rst_i              (rst_i         ),

            .rxd_i              (rxd_gated_w   ),
            .buffer_ready_i     (buffer_ready_i),
            .data_o             (data_o        ),
            .data_valid_o       (data_valid_o  )
        );


endmodule
