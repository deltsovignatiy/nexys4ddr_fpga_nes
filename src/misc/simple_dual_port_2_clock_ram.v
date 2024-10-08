
/*
 * Description : Simple dual port RAM with 2 clocks module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module simple_dual_port_2_clock_ram
    #(
        parameter DATA_WIDTH = 8,                        // Ширина данных
        parameter RAM_DEPTH  = 64,                       // Объём (глубина) памяти
        parameter RAM_STYLE  = "block",                  // Архитектура "block" или "distributed"
        parameter INIT_FILE  = "",                       // Файл инициализации начальных значений
        parameter INIT_VAL   = 1'bx,                     /* Начальные значения битов, если нет файла инициализации,
                                                          * 1'b0 или 1'b1, если 1'bx — не инициализировать память */
        parameter SIMULATION = "TRUE"                    /* Рандомизировать значения в симуляции, если INIT_VAL == 1'bx,
                                                          * "TRUE" или "FALSE" */
    )
    (
        input  wire                             clka_i,  // Сигнал тактирования записи
        input  wire [__clogb2__(RAM_DEPTH)-1:0] addra_i, // Адрес для записи
        input  wire                             wra_i,   // Запись
        input  wire [           DATA_WIDTH-1:0] dina_i,  // Входные данные для записи

        input  wire                             clkb_i,  // Сигнал тактирования чтения
        input  wire [__clogb2__(RAM_DEPTH)-1:0] addrb_i, // Адрес для чтения
        input  wire                             rdb_i,   // Чтение
        output wire [           DATA_WIDTH-1:0] doutb_o  // Выходные данные для чтения
    );


    `include "function_clogb2.vh"


    localparam DW = DATA_WIDTH;
    localparam RD = RAM_DEPTH;


    (* ram_style = RAM_STYLE *)
    reg  [DW-1:0] ram_r [RD-1:0];
    wire [DW-1:0] ram_next_w;
    reg  [DW-1:0] ram_data_r;
    wire [DW-1:0] ram_data_next_w;


    generate

        if (INIT_FILE != "") begin: use_init_file

            initial begin
                $readmemh(INIT_FILE, ram_r, 0, (RD-1));
            end

        end else if ((INIT_VAL == 1'b0) || (INIT_VAL == 1'b1)) begin: init_bram_to_val

            integer ram_index;
            initial begin
                for (ram_index = 0; ram_index < RD; ram_index = ram_index + 1) begin
                    ram_r[ram_index] = {DW{INIT_VAL}};
                end
            end

        end else if (SIMULATION == "TRUE") begin: init_bram_to_urandom

            integer ram_index;
            initial begin
                for (ram_index = 0; ram_index < RD; ram_index = ram_index + 1) begin
                    ram_r[ram_index] = $urandom();
                end
            end

        end

    endgenerate


    always @(posedge clka_i)
        ram_r[addra_i] <= ram_next_w;

    always @(posedge clkb_i)
        ram_data_r     <= ram_data_next_w;

    assign ram_next_w      = (wra_i) ? dina_i         : ram_r[addra_i];
    assign ram_data_next_w = (rdb_i) ? ram_r[addrb_i] : ram_data_r;


    assign doutb_o = ram_data_r;


endmodule
