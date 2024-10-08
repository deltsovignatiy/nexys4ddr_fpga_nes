
/*
 * Description : Video output controller (ppu picture buffer and VGA controller) module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


`include "defines.vh"


module video_output_controller
    (
        input  wire       ppu_clk_i,          // Сигнал тактирования графического процессора

        input  wire       vga_clk_i,          // Сигнал тактирования VGA
        input  wire       vga_rst_i,          // Сигнал сброса VGA

        input  wire [7:0] ppu_output_pixel_i, // Текущий выходной пиксель рендера PPU
        input  wire [8:0] ppu_x_pos_i,        // Текущая горизонтальная координата рендера PPU
        input  wire [8:0] ppu_y_pos_i,        // Текущая вертикальная координата рендера PPU

        output wire       vga_hsync_o,        // Сигнал горизонтальной синхронизации VGA
        output wire       vga_vsync_o,        // Сигнал вертикальной синхронизации VGA
        output wire [3:0] vga_red_o,          // Красная состовляющая цвета текущего отрисовываемого пкселя VGA
        output wire [3:0] vga_green_o,        // Зелёная состовляющая цвета текущего отрисовываемого пкселя VGA
        output wire [3:0] vga_blue_o          // Синяя состовляющая цвета текущего отрисовываемого пкселя VGA
    );


    // Границы и тайминги PPU -> VGA
    localparam ACTIVE_COLUMNS_PER_ROW         = 640;
    localparam ACTIVE_ROWS_PER_SCREEN         = 480;
    localparam PPU_COLUMNS_PER_ROW            = 512; // Простой апскейл x2
    localparam PPU_ROWS_PER_SCREEN            = 480; // Простой апскейл x2
    localparam ACT_CLMNS_RW                   = ACTIVE_COLUMNS_PER_ROW;
    localparam ACT_RWS_SCRN                   = ACTIVE_ROWS_PER_SCREEN;
    localparam PPU_CLMNS_RW                   = PPU_COLUMNS_PER_ROW;
    localparam PPU_RWS_SCRN                   = PPU_ROWS_PER_SCREEN;
    localparam PPU_COLUMNS_BOUNDARIES_PER_ROW = (ACT_CLMNS_RW - PPU_CLMNS_RW) / 2;
    localparam PPU_CLMNS_BOUNDS_RW            = PPU_COLUMNS_BOUNDARIES_PER_ROW;
    localparam BUFFER_TO_DISPLAY_LATENCY      = 3;
    localparam B2DL                           = BUFFER_TO_DISPLAY_LATENCY;
    localparam PPU_TO_BUFFER_LATENCY          = 1;
    localparam PPU2BL                         = PPU_TO_BUFFER_LATENCY;


    wire [9:0] vga_column_counter_w;
    wire [9:0] vga_row_counter_w;

    wire [7:0] pixel_line_w [239:0];
    wire       display_w;

    wire [8:0] ppu_x_coord_w;
    wire [7:0] ppu_x_addr_w;
    wire       ppu_wr_w [239:0];

    reg  [8:0] vga_x_coord_r;
    wire [8:0] vga_x_coord_next_w;
    wire [7:0] vga_x_addr_w;
    wire [7:0] vga_y_addr_w;
    reg        vga_in_en_r;
    reg  [7:0] vga_in_pixel_r;
    wire [7:0] vga_in_pixel_next_w;


    // Контроллер VGA
    vga_controller
        vga
        (
            .clk_i             (vga_clk_i           ),
            .rst_i             (vga_rst_i           ),

            .input_pixel_i     (vga_in_pixel_r      ),

            .column_counter_o  (vga_column_counter_w),
            .row_counter_o     (vga_row_counter_w   ),

            .vga_hsync_o       (vga_hsync_o         ),
            .vga_vsync_o       (vga_vsync_o         ),
            .vga_red_o         (vga_red_o           ),
            .vga_green_o       (vga_green_o         ),
            .vga_blue_o        (vga_blue_o          )
        );


    /* Один такт требуется для извлечения пикселя из буффера, ещё один — на регистр vga_in_pixel_r,
     * и ещё один — на регистры цветовых компонентов видеосигнала, поэтому (B2DL == 3) */
    assign display_w = (vga_column_counter_w > (PPU_CLMNS_BOUNDS_RW - 1'b1 - B2DL))         &&
                       (vga_column_counter_w < (ACT_CLMNS_RW - PPU_CLMNS_BOUNDS_RW - B2DL)) &&
                       (vga_row_counter_w    < (ACT_RWS_SCRN));

    /* Соответственно сигнал включения vga_in_pixel_r должен быть задержан на один такт — до извлечения
     * данных из буффера. Переполнение счётчика vga_x_coord_r автоматически обрабатывает пересечение границы
     * отрисовываемой строки ввиду того, что (PPU_COLUMNS_PER_ROW == 512) */
    always @(posedge vga_clk_i)
        if (vga_rst_i) begin
            vga_x_coord_r  <= 9'h0;
        end else begin
            vga_x_coord_r  <= vga_x_coord_next_w;
        end

    always @(posedge vga_clk_i)
        begin
            vga_in_en_r    <= display_w;
            vga_in_pixel_r <= vga_in_pixel_next_w;
        end

    assign vga_x_addr_w        = vga_x_coord_r    [8:1];
    assign vga_y_addr_w        = vga_row_counter_w[8:1];

    assign vga_x_coord_next_w  = vga_x_coord_r + display_w;
    assign vga_in_pixel_next_w = (vga_in_en_r) ? pixel_line_w[vga_y_addr_w] : 8'h0F;

    /* PPU начинает рендер, когда (ppu_x_pos_i == 1), и использует выходной регистр, на прохождение
     * которого тратится один такт, поэтому 0-ой пиксель приходит в буффер, когда (ppu_x_pos_i == 2),
     * и соответственно (PPU2BL == 1) */
    assign ppu_x_coord_w       = ppu_x_pos_i - 1'b1 - PPU2BL;
    assign ppu_x_addr_w        = ppu_x_coord_w[7:0];

    /* Буфер для преобразования разрешения изображения и таймингов графического процессора
     * в разрешение и тайминги в формате VGA */
    generate
        for (genvar i = 0; i < 240; i = i + 1) begin : ppu_to_vga_buffer

            assign ppu_wr_w[i] = (ppu_x_coord_w < 9'd256) && (ppu_y_pos_i == i);


            // I-ый буфер строки
            simple_dual_port_2_clock_ram
                #(
                    .DATA_WIDTH(8                 ),
                    .RAM_DEPTH (256               ),
                    .RAM_STYLE ("distributed"     ),
                    .INIT_VAL  (`MEM_INIT_VAL     ),
                    .SIMULATION(`MEM_SIM          )
                )
                pixel_line_buffer
                (
                    .clka_i    (ppu_clk_i         ),
                    .addra_i   (ppu_x_addr_w      ),
                    .wra_i     (ppu_wr_w[i]       ),
                    .dina_i    (ppu_output_pixel_i),
                    .clkb_i    (vga_clk_i         ),
                    .addrb_i   (vga_x_addr_w      ),
                    .rdb_i     (display_w         ),
                    .doutb_o   (pixel_line_w[i]   )
                );


        end
    endgenerate


endmodule
