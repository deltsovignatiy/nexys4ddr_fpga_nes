
/*
 * Description : PS/2 controller (receiver with input "clk" and "data" filters) module
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


module ps2_controller
    (
        input  wire       clk_i,          // Сигнал тактирования
        input  wire       rst_i,          // Сигнал сброса

        input  wire       ps2_clk_i,      // Сигнал PS/2 интерфейса — тактирование
        input  wire       ps2_data_i,     // Сигнал PS/2 интерфейса — данные

        input  wire       buffer_ready_i, // Сигнал готовности к приёму выходных данных
        output wire [7:0] data_o,         // Выходные данные
        output wire       data_valid_o    // Сигнал валидности выходных данных
    );


    // Сигналы входного фильтра
    wire ps2_clk_gated_w;
    wire ps2_data_gated_w;


    // Входной фильтр для PS/2 clk
    input_filter
        #(
            .LENGTH        (3               ),
            .RESET_VALUE   (1               )
        )
        ps2_clk_filter
        (
            .clk_i         (clk_i           ),
            .rst_i         (rst_i           ),

            .in_i          (ps2_clk_i       ),
            .en_i          (1'b1            ),
            .out_o         (ps2_clk_gated_w )
        );


    // Входной фильтр для PS/2 data
    input_filter
        #(
            .LENGTH        (3               ),
            .RESET_VALUE   (1               )
        )
        ps2_data_filter
        (
            .clk_i         (clk_i           ),
            .rst_i         (rst_i           ),

            .in_i          (ps2_data_i      ),
            .en_i          (1'b1            ),
            .out_o         (ps2_data_gated_w)
        );


    // Логика PS/2 приёмника
    ps2_receiver
        ps2_receiver
        (
            .clk_i         (clk_i           ),
            .rst_i         (rst_i           ),

            .ps2_clk_i     (ps2_clk_gated_w ),
            .ps2_data_i    (ps2_data_gated_w),

            .buffer_ready_i(buffer_ready_i  ),
            .data_o        (data_o          ),
            .data_valid_o  (data_valid_o    )
        );


endmodule
