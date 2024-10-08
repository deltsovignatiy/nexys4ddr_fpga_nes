
/*
 * Description : Reset synchronizer module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module reset_synchronizer
    (
        input  wire clk_i,        // Сигнал татирования
        input  wire rstn_async_i, // Входной асинхронный сброс
        output wire rst_sync_o    // Выходной синхронный сброс
    );


    (* ASYNC_REG = "TRUE" *)
    reg [1:0] rst_sync_r;
    wire      rst_async_w;


    assign rst_async_w = ~rstn_async_i;

    always @(posedge clk_i or posedge rst_async_w)
        if   (rst_async_w) rst_sync_r <= 2'b11;
        else               rst_sync_r <= {rst_sync_r[0], 1'b0};


    assign rst_sync_o = rst_sync_r[1];


endmodule
