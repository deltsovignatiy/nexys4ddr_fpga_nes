
/*
 * Description : NROM (№0) mapper module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module mapper_nrom
    (
        input  wire [14:0] prg_rom_addr_i,         // Адрес обращения к постоянной памяти программы картриджа
        input  wire [12:0] prg_ram_addr_i,         // Адрес обращения к оперативной памяти картриджа
        input  wire [12:0] chr_mem_addr_i,         // Адрес обращения к видеопамяти картриджа
        input  wire        hw_nametable_layout_i,  /* Тип "зеркалирования" оперативной видеопамяти,
                                                    * "0" - горизонтальное, "1" - вертикальное */

        output wire [18:0] nrom_prg_rom_addr_o,    // Расширенный адрес обращения к постоянной памяти программы картриджа
        output wire [14:0] nrom_prg_ram_addr_o,    // Расширенный адрес обращения к оперативной памяти картриджа
        output wire [17:0] nrom_chr_mem_addr_o,    // Расширенный адрес обращения к видеопамяти картриджа
        output wire [ 2:0] nrom_nametable_layout_o // Используемая организация оперативной видеопамяти
    );


    `include "localparam_nametable_layout.vh"


    wire [18:0] nrom_prg_rom_addr_w;
    wire [14:0] nrom_prg_ram_addr_w;
    wire [17:0] nrom_chr_mem_addr_w;
    wire [ 2:0] nrom_nametable_layout_w;


    assign nrom_prg_rom_addr_w     = {4'h0, prg_rom_addr_i};

    assign nrom_prg_ram_addr_w     = {2'h0, prg_ram_addr_i};

    assign nrom_chr_mem_addr_w     = {5'h0, chr_mem_addr_i};

    assign nrom_nametable_layout_w = (hw_nametable_layout_i) ? NAMETABLE_LAYOUT_VERTICAL_MIRRORING :
                                                               NAMETABLE_LAYOUT_HORIZONTAL_MIRRORING;


    assign nrom_prg_rom_addr_o     = nrom_prg_rom_addr_w;
    assign nrom_prg_ram_addr_o     = nrom_prg_ram_addr_w;
    assign nrom_chr_mem_addr_o     = nrom_chr_mem_addr_w;
    assign nrom_nametable_layout_o = nrom_nametable_layout_w;


endmodule
