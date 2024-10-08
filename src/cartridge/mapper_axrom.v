
/*
 * Description : AxROM (№7) mapper module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module mapper_axrom
    (
        input  wire        clk_i,                   // Сигнал тактирования
        input  wire        rst_i,                   // Сигнал сброса

        input  wire        mapper_wr_i,             // Сигнал записи в регистры маппера
        input  wire [ 7:0] mapper_wr_data_i,        // Записываемые данные в регистры маппера

        input  wire [14:0] prg_rom_addr_i,          // Адрес обращения к постоянной памяти программы картриджа
        input  wire [12:0] prg_ram_addr_i,          // Адрес обращения к оперативной памяти картриджа
        input  wire [12:0] chr_mem_addr_i,          // Адрес обращения к видеопамяти картриджа

        output wire [18:0] axrom_prg_rom_addr_o,    // Расширенный адрес обращения к постоянной памяти программы картриджа
        output wire [14:0] axrom_prg_ram_addr_o,    // Расширенный адрес обращения к оперативной памяти картриджа
        output wire [17:0] axrom_chr_mem_addr_o,    // Расширенный адрес обращения к видеопамяти картриджа
        output wire [ 2:0] axrom_nametable_layout_o // Используемая организация оперативной видеопамяти
    );


    `include "localparam_nametable_layout.vh"


    reg  [ 3:0] mapper_reg_r;
    wire [ 3:0] mapper_reg_next_w;
    wire [ 2:0] prg_rom_select_w;
    wire        nametable_select_w;

    wire [18:0] axrom_prg_rom_addr_w;
    wire [14:0] axrom_prg_ram_addr_w;
    wire [17:0] axrom_chr_mem_addr_w;
    wire [ 2:0] axrom_nametable_layout_w;


    always @(posedge clk_i)
        if   (rst_i) mapper_reg_r <= 4'h0;
        else         mapper_reg_r <= mapper_reg_next_w;

    assign mapper_reg_next_w        = (mapper_wr_i) ? {mapper_wr_data_i[4], mapper_wr_data_i[2:0]} : mapper_reg_r;

    assign prg_rom_select_w         = mapper_reg_r[2:0];
    assign nametable_select_w       = mapper_reg_r[3];

    assign axrom_prg_rom_addr_w     = {1'h0, prg_rom_select_w, prg_rom_addr_i[14:0]};

    assign axrom_prg_ram_addr_w     = {2'h0, prg_ram_addr_i};

    assign axrom_chr_mem_addr_w     = {5'h0, chr_mem_addr_i};

    assign axrom_nametable_layout_w = {2'h0, nametable_select_w};


    assign axrom_prg_rom_addr_o     = axrom_prg_rom_addr_w;
    assign axrom_prg_ram_addr_o     = axrom_prg_ram_addr_w;
    assign axrom_chr_mem_addr_o     = axrom_chr_mem_addr_w;
    assign axrom_nametable_layout_o = axrom_nametable_layout_w;


endmodule
