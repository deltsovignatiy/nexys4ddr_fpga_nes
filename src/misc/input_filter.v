
/*
 * Description : Input filter module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module input_filter
    #(
        parameter LENGTH      = 3,   // Количество триггеров в цепи фильтра (минимум 2)
        parameter RESET_VALUE = 1'b0 // Выходное значение после сброса — 1'b0 или 1'b1
    )
    (
        input  wire clk_i,           // Сигнал тактирования
        input  wire rst_i,           // Сигнал сброса

        input  wire in_i,            // Вход
        input  wire en_i,            // Сигнал разрешения работы выхода
        output wire out_o            // Выход
    );


    localparam       LN = LENGTH;
    localparam [0:0] RV = RESET_VALUE;


    (* ASYNC_REG = "TRUE" *)
    reg  [LN-1:0] qcf_r;
    reg           out_r;
    wire          out_next_w;
    wire          enable_out_w;
    wire          din_w;


    always @(posedge clk_i)
        if (rst_i) begin
            qcf_r <= {LN{RV}};
            out_r <= RV;
        end else begin
            qcf_r <= {qcf_r[LN-2:0], in_i};
            out_r <= out_next_w;
        end

    assign enable_out_w = en_i && ((&qcf_r) || (~|qcf_r));
    assign din_w        = &qcf_r;

    assign out_next_w   = (enable_out_w) ? din_w : out_r;


    assign out_o = out_r;


endmodule
