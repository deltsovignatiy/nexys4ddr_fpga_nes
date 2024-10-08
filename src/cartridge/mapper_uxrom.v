
/*
 * Description : UxROM (№2) mapper module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module mapper_uxrom
    (
        input  wire        clk_i,                   // Сигнал тактирования

        input  wire        mapper_wr_i,             // Сигнал записи в регистры маппера
        input  wire [ 7:0] mapper_wr_data_i,        // Записываемые данные в регистры маппера

        input  wire [14:0] prg_rom_addr_i,          // Адрес обращения к постоянной памяти программы картриджа
        input  wire [12:0] prg_ram_addr_i,          // Адрес обращения к оперативной памяти картриджа
        input  wire [12:0] chr_mem_addr_i,          // Адрес обращения к видеопамяти картриджа
        input  wire        hw_nametable_layout_i,   /* Тип "зеркалирования" оперативной видеопамяти,
                                                     * "0" - горизонтальное, "1" - вертикальное */

        output wire [18:0] uxrom_prg_rom_addr_o,    // Расширенный адрес обращения к постоянной памяти программы картриджа
        output wire [14:0] uxrom_prg_ram_addr_o,    // Расширенный адрес обращения к оперативной памяти картриджа
        output wire [17:0] uxrom_chr_mem_addr_o,    // Расширенный адрес обращения к видеопамяти картриджа
        output wire [ 2:0] uxrom_nametable_layout_o // Используемая организация оперативной видеопамяти
    );


    `include "localparam_nametable_layout.vh"


    reg  [ 2:0] mapper_reg_r;
    wire [ 2:0] mapper_reg_next_w;

    wire [18:0] uxrom_prg_rom_addr_w;
    wire [14:0] uxrom_prg_ram_addr_w;
    wire [17:0] uxrom_chr_mem_addr_w;
    wire [ 2:0] uxrom_nametable_layout_w;


    always @(posedge clk_i)
        mapper_reg_r <= mapper_reg_next_w;

    assign mapper_reg_next_w        = (mapper_wr_i) ? mapper_wr_data_i[2:0] : mapper_reg_r;

    assign uxrom_prg_rom_addr_w     = (prg_rom_addr_i[14]) ? {2'h0, 3'h7,         prg_rom_addr_i[13:0]} :
                                                             {2'h0, mapper_reg_r, prg_rom_addr_i[13:0]};

    assign uxrom_prg_ram_addr_w     = {2'h0, prg_ram_addr_i};

    assign uxrom_chr_mem_addr_w     = {5'h0, chr_mem_addr_i};

    assign uxrom_nametable_layout_w = (hw_nametable_layout_i) ? NAMETABLE_LAYOUT_VERTICAL_MIRRORING :
                                                                NAMETABLE_LAYOUT_HORIZONTAL_MIRRORING;


    assign uxrom_prg_rom_addr_o     = uxrom_prg_rom_addr_w;
    assign uxrom_prg_ram_addr_o     = uxrom_prg_ram_addr_w;
    assign uxrom_chr_mem_addr_o     = uxrom_chr_mem_addr_w;
    assign uxrom_nametable_layout_o = uxrom_nametable_layout_w;


endmodule
