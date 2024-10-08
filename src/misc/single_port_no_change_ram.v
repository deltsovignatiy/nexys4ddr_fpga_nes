
/*
 * Description : Single port "no change" RAM module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module single_port_no_change_ram
    #(
        parameter DATA_WIDTH = 8,                        // Ширина данных
        parameter RAM_DEPTH  = 64,                       // Объём (глубина) памяти
        parameter RAM_STYLE  = "block",                  // Архитектура "block" или "distributed"
        parameter INIT_FILE  = "",                       // Файл инициализации начальных значений
        parameter INIT_VAL   = 1'bx,                     /* Начальные значения битов, если нет файла инициализации,
                                                          * 1'b0 или 1'b1, если 1'bx — не инициализировать память */
        parameter SIMULATION = "FALSE"                   /* Рандомизировать значения в симуляции, если INIT_VAL == 1'bx,
                                                          * "TRUE" или "FALSE" */
    )
    (
        input  wire                             clka_i,  // Сигнал тактирования
        input  wire [__clogb2__(RAM_DEPTH)-1:0] addra_i, // Адрес
        input  wire                             rda_i,   // Чтение
        input  wire                             wra_i,   // Запись
        input  wire [           DATA_WIDTH-1:0] dina_i,  // Входные данные для записи
        output wire [           DATA_WIDTH-1:0] douta_o  // Выходные данные для чтения
    );


    `include "function_clogb2.vh"


    localparam DW = DATA_WIDTH;
    localparam RD = RAM_DEPTH;


    (* ram_style = RAM_STYLE *)
    reg  [DW-1:0] ram_r [RD-1:0];
    wire [DW-1:0] ram_next_w;
    reg  [DW-1:0] ram_data_r;
    wire [DW-1:0] ram_data_next_w;

    wire         write_w;
    wire         read_w;


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


    always @(posedge clka_i) begin
        ram_r[addra_i] <= ram_next_w;
        ram_data_r     <= ram_data_next_w;
    end

    assign write_w         = ~rda_i && wra_i;
    assign read_w          =  rda_i;

    assign ram_next_w      = (write_w) ? dina_i         : ram_r[addra_i];
    assign ram_data_next_w = (read_w ) ? ram_r[addra_i] : ram_data_r;


    assign douta_o = ram_data_r;


endmodule
