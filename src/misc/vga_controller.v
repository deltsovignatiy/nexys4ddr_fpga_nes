
/*
 * Description : VGA controller module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module vga_controller
    (
        input  wire       clk_i,            // Сигнал тактирования
        input  wire       rst_i,            // Сигнал сброса

        input  wire [7:0] input_pixel_i,    // Текущий отрисовываемый пиксель

        output wire [9:0] column_counter_o, // Текуще значение счётчика столбцов (горизотальная координата)
        output wire [9:0] row_counter_o,    // Текуще значение счётчика строк (вертикальная координата)

        output wire       vga_hsync_o,      // Сигнал горизонтальной синхронизации
        output wire       vga_vsync_o,      // Сигнал вертикальной синхронизации
        output wire [3:0] vga_red_o,        // Красная состовляющая цвета текущего отрисовываемого пкселя
        output wire [3:0] vga_green_o,      // Зелёная состовляющая цвета текущего отрисовываемого пкселя
        output wire [3:0] vga_blue_o        // Синяя состовляющая цвета текущего отрисовываемого пкселя
    );


    // Границы и тайминги
    localparam TOTAL_COLUMNS_PER_ROW  = 800;
    localparam TOTAL_ROWS_PER_SCREEN  = 525;
    localparam ACTIVE_COLUMNS_PER_ROW = 640;
    localparam ACTIVE_ROWS_PER_SCREEN = 480;
    localparam HSYNC_FRONT_PORCH      = 16;
    localparam HSYNC_BACK_PORCH       = 48;
    localparam VSYNC_FRONT_PORCH      = 10;
    localparam VSYNC_BACK_PORCH       = 33;


    reg         hsync_r;
    reg         hsync_next_r;
    reg         vsync_r;
    reg         vsync_next_r;

    reg  [11:0] rgb_r;
    reg  [11:0] rgb_next_r;

    reg  [ 9:0] column_counter_r;
    wire [ 9:0] column_counter_next_w;
    reg  [ 9:0] row_counter_r;
    reg  [ 9:0] row_counter_next_r;

    wire        hsync_cond_on_w;
    wire        hsync_cond_off_w;
    wire        vsync_cond_on_w;
    wire        vsync_cond_off_w;

    wire        column_counter_edge_w;
    wire        row_counter_edge_w;


    always @(posedge clk_i or posedge rst_i)
        if (rst_i) begin
            hsync_r          <= 1'b1;
            vsync_r          <= 1'b1;
            rgb_r            <= {4'h0, 4'h0, 4'h0};
        end else begin
            hsync_r          <= hsync_next_r;
            vsync_r          <= vsync_next_r;
            rgb_r            <= rgb_next_r;
        end

    always @(posedge clk_i)
        if (rst_i) begin
            column_counter_r <= 10'h0;
            row_counter_r    <= 10'h0;
        end else begin
            column_counter_r <= column_counter_next_w;
            row_counter_r    <= row_counter_next_r;
        end

    assign column_counter_edge_w = (column_counter_r == (TOTAL_COLUMNS_PER_ROW - 1'b1));
    assign row_counter_edge_w    = (row_counter_r    == (TOTAL_ROWS_PER_SCREEN - 1'b1));

    assign hsync_cond_on_w       = (column_counter_r == (ACTIVE_COLUMNS_PER_ROW + HSYNC_FRONT_PORCH - 1'b1));
    assign hsync_cond_off_w      = (column_counter_r == (TOTAL_COLUMNS_PER_ROW  - HSYNC_BACK_PORCH  - 1'b1));

    assign vsync_cond_on_w       = (row_counter_r == (ACTIVE_ROWS_PER_SCREEN + VSYNC_FRONT_PORCH - 1'b1)) &&
                                    column_counter_edge_w;
    assign vsync_cond_off_w      = (row_counter_r == (TOTAL_ROWS_PER_SCREEN  - VSYNC_BACK_PORCH  - 1'b1)) &&
                                    column_counter_edge_w;

    assign column_counter_next_w = (column_counter_edge_w) ? 10'h0 : column_counter_r + 1'b1;

    wire [1:0] row_counter_next_case_w = {column_counter_edge_w, row_counter_edge_w};
    always @(*)
        case (row_counter_next_case_w)
            2'b11:   row_counter_next_r = 10'h0; // frame edge
            2'b10:   row_counter_next_r = row_counter_r + 1'b1;
            default: row_counter_next_r = row_counter_r;
        endcase

    wire [1:0] hsync_next_case_r = {hsync_cond_on_w, hsync_cond_off_w};
    always @(*)
        case (hsync_next_case_r) // one hot
            2'b10:   hsync_next_r       = 1'b0;
            2'b01:   hsync_next_r       = 1'b1;
            default: hsync_next_r       = hsync_r;
        endcase

    wire [1:0] vsync_next_case_r = {vsync_cond_on_w, vsync_cond_off_w};
    always @(*)
        case (vsync_next_case_r) // one hot
            2'b10:   vsync_next_r       = 1'b0;
            2'b01:   vsync_next_r       = 1'b1;
            default: vsync_next_r       = vsync_r;
        endcase

    // LUT преобразования входного пикселя в формат RGB
    always @(*)
        case (input_pixel_i)
            8'h00:   rgb_next_r         = {4'h4, 4'h4, 4'h4};
            8'h01:   rgb_next_r         = {4'h0, 4'h1, 4'h7};
            8'h02:   rgb_next_r         = {4'h0, 4'h1, 4'h9};
            8'h03:   rgb_next_r         = {4'h3, 4'h0, 4'h8};
            8'h04:   rgb_next_r         = {4'h4, 4'h0, 4'h6};
            8'h05:   rgb_next_r         = {4'h5, 4'h0, 4'h3};
            8'h06:   rgb_next_r         = {4'h5, 4'h0, 4'h0};
            8'h07:   rgb_next_r         = {4'h3, 4'h1, 4'h0};
            8'h08:   rgb_next_r         = {4'h2, 4'h2, 4'h0};
            8'h09:   rgb_next_r         = {4'h1, 4'h3, 4'h0};
            8'h0A:   rgb_next_r         = {4'h0, 4'h4, 4'h0};
            8'h0B:   rgb_next_r         = {4'h0, 4'h3, 4'h0};
            8'h0C:   rgb_next_r         = {4'h0, 4'h3, 4'h3};
            8'h0D:   rgb_next_r         = {4'h0, 4'h0, 4'h0};
            8'h0E:   rgb_next_r         = {4'h0, 4'h0, 4'h0};
            8'h0F:   rgb_next_r         = {4'h0, 4'h0, 4'h0};
            8'h10:   rgb_next_r         = {4'h9, 4'h9, 4'h9};
            8'h11:   rgb_next_r         = {4'h0, 4'h4, 4'hC};
            8'h12:   rgb_next_r         = {4'h3, 4'h3, 4'hE};
            8'h13:   rgb_next_r         = {4'h5, 4'h1, 4'hE};
            8'h14:   rgb_next_r         = {4'h8, 4'h1, 4'hB};
            8'h15:   rgb_next_r         = {4'hA, 4'h1, 4'h6};
            8'h16:   rgb_next_r         = {4'h9, 4'h2, 4'h2};
            8'h17:   rgb_next_r         = {4'h7, 4'h3, 4'h0};
            8'h18:   rgb_next_r         = {4'h5, 4'h5, 4'h0};
            8'h19:   rgb_next_r         = {4'h2, 4'h7, 4'h0};
            8'h1A:   rgb_next_r         = {4'h0, 4'h7, 4'h0};
            8'h1B:   rgb_next_r         = {4'h0, 4'h7, 4'h2};
            8'h1C:   rgb_next_r         = {4'h0, 4'h6, 4'h7};
            8'h1D:   rgb_next_r         = {4'h0, 4'h0, 4'h0};
            8'h1E:   rgb_next_r         = {4'h0, 4'h0, 4'h0};
            8'h1F:   rgb_next_r         = {4'h0, 4'h0, 4'h0};
            8'h20:   rgb_next_r         = {4'hE, 4'hE, 4'hE};
            8'h21:   rgb_next_r         = {4'h4, 4'h9, 4'hE};
            8'h22:   rgb_next_r         = {4'h7, 4'h7, 4'hE};
            8'h23:   rgb_next_r         = {4'hB, 4'h6, 4'hE};
            8'h24:   rgb_next_r         = {4'hE, 4'h5, 4'hE};
            8'h25:   rgb_next_r         = {4'hE, 4'h5, 4'hB};
            8'h26:   rgb_next_r         = {4'hE, 4'h6, 4'h6};
            8'h27:   rgb_next_r         = {4'hD, 4'h8, 4'h2};
            8'h28:   rgb_next_r         = {4'hA, 4'hA, 4'h0};
            8'h29:   rgb_next_r         = {4'h7, 4'hC, 4'h0};
            8'h2A:   rgb_next_r         = {4'h4, 4'hD, 4'h2};
            8'h2B:   rgb_next_r         = {4'h3, 4'hC, 4'h6};
            8'h2C:   rgb_next_r         = {4'h3, 4'hB, 4'hC};
            8'h2D:   rgb_next_r         = {4'h3, 4'h3, 4'h3};
            8'h2E:   rgb_next_r         = {4'h0, 4'h0, 4'h0};
            8'h2F:   rgb_next_r         = {4'h0, 4'h0, 4'h0};
            8'h30:   rgb_next_r         = {4'hE, 4'hE, 4'hE};
            8'h31:   rgb_next_r         = {4'hA, 4'hC, 4'hE};
            8'h32:   rgb_next_r         = {4'hB, 4'hB, 4'hE};
            8'h33:   rgb_next_r         = {4'hD, 4'hB, 4'hE};
            8'h34:   rgb_next_r         = {4'hE, 4'hA, 4'hE};
            8'h35:   rgb_next_r         = {4'hE, 4'hA, 4'hD};
            8'h36:   rgb_next_r         = {4'hE, 4'hB, 4'hB};
            8'h37:   rgb_next_r         = {4'hE, 4'hC, 4'h9};
            8'h38:   rgb_next_r         = {4'hC, 4'hD, 4'h7};
            8'h39:   rgb_next_r         = {4'hB, 4'hD, 4'h7};
            8'h3A:   rgb_next_r         = {4'hA, 4'hE, 4'h9};
            8'h3B:   rgb_next_r         = {4'h9, 4'hE, 4'hB};
            8'h3C:   rgb_next_r         = {4'hA, 4'hD, 4'hE};
            8'h3D:   rgb_next_r         = {4'hA, 4'hA, 4'hA};
            8'h3E:   rgb_next_r         = {4'h0, 4'h0, 4'h0};
            8'h3F:   rgb_next_r         = {4'h0, 4'h0, 4'h0};
            default: rgb_next_r         = {4'h0, 4'h0, 4'h0};
        endcase


    assign column_counter_o = column_counter_r;
    assign row_counter_o    = row_counter_r;
    assign vga_hsync_o      = hsync_r;
    assign vga_vsync_o      = vsync_r;
    assign vga_red_o        = rgb_r[11:8];
    assign vga_green_o      = rgb_r[ 7:4];
    assign vga_blue_o       = rgb_r[ 3:0];


endmodule
