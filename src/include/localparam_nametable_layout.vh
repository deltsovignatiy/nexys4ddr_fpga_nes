
/*
 * Description : Nametable layout localparam
 * Author      : Deltsov Ignatiy
 * License     : MIT, See LICENSE for details
 */


    // Варианты организации оперативной видеопамяти, https://www.nesdev.org/wiki/Mirroring#Nametable_Mirroring
    localparam [2:0] NAMETABLE_LAYOUT_SINGLE_SCREEN_LOWER  = 3'b000,
                     NAMETABLE_LAYOUT_SINGLE_SCREEN_UPPER  = 3'b001,
                     NAMETABLE_LAYOUT_VERTICAL_MIRRORING   = 3'b010,
                     NAMETABLE_LAYOUT_HORIZONTAL_MIRRORING = 3'b011,
                     NAMETABLE_LAYOUT_FOUR_SCREEN          = 3'b100;

