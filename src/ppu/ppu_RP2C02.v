
/*
 * Description : RP2C02 implementation (control with background and sprites render logic) module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


`include "defines.vh"


module ppu_RP2C02
    (
        input  wire        clk_i,              // Сигнал тактирования
        input  wire        mclk_i,             // Сигнал тактирования (negedge)
        input  wire        rst_i,              // Сигнал сброса

        output wire        chr_mem_mclk_o,     // Сигнал тактирования для видеопамяти картриджа
        output wire        chr_mem_wr_o,       // Сигнал записи данных видеопамяти картриджа
        output wire        chr_mem_rd_o,       // Сигнал чтения данных видеопамяти картриджа
        output wire [12:0] chr_mem_addr_o,     // Адрес обращения к видеопамяти картриджа
        output wire [ 7:0] chr_mem_wr_data_o,  // Записываемые данные видеопамяти картриджа
        input  wire [ 7:0] chr_mem_rd_data_i,  // Читаемые данные видеопамяти картриджа

        input  wire        ppu_wr_i,           // Сигнал записи данных в регистры
        input  wire        ppu_rd_i,           // Сигнал чтения данных из регистров
        input  wire [ 2:0] ppu_addr_i,         // Адрес обращения к регистрам
        input  wire [ 7:0] ppu_wr_data_i,      // Записываемые данные
        output wire [ 7:0] ppu_rd_data_o,      // Читаемые данные

        input  wire [ 2:0] nametable_layout_i, // Используемая организация оперативной видеопамяти

        output wire        ppu_nmi_o,          // Прерывание VBLANK

        output wire [ 7:0] ppu_output_pixel_o, // Текущий выходной пиксель рендера
        output wire [ 8:0] ppu_x_pos_o,        // Текущая горизонтальная координата рендера
        output wire [ 8:0] ppu_y_pos_o         // Текущая вертикальная координата рендера
);


    `include "localparam_nametable_layout.vh"


    // Регистры графического процессора
    localparam [3:0] PPU_CONTROL_REG_ADDR = 0,
                     PPU_MASK_REG_ADDR    = 1,
                     PPU_STATUS_REG_ADDR  = 2,
                     OAM_ADDR_REG_ADDR    = 3,
                     OAM_DATA_REG_ADDR    = 4,
                     PPU_SCROLL_REG_ADDR  = 5,
                     PPU_ADDR_REG_ADDR    = 6,
                     PPU_DATA_REG_ADDR    = 7,
                     PPU_SCROLLH_REG_ADDR = 8,
                     PPU_ADDR_HB_REG_ADDR = 9,
                     PPU_CURR_VRAM_ADDR   = 10;


    // Сокращение для вариантов организации оперативной видеопамяти
    localparam [2:0] NTL_SSL              = NAMETABLE_LAYOUT_SINGLE_SCREEN_LOWER,
                     NTL_SSU              = NAMETABLE_LAYOUT_SINGLE_SCREEN_UPPER,
                     NTL_VM               = NAMETABLE_LAYOUT_VERTICAL_MIRRORING,
                     NTL_HM               = NAMETABLE_LAYOUT_HORIZONTAL_MIRRORING,
                     NTL_FS               = NAMETABLE_LAYOUT_FOUR_SCREEN;


    // Размер оперативной видеопамяти, памяти палитры, памяти спрайтов
    localparam       NAMETABLE_SIZE       = 4 * 1024;
    localparam       BG_PALETTE_SIZE      = 16;
    localparam       SP_PALETTE_SIZE      = 16;
    localparam       OAM_SIZE             = 256;


    // Сигналы координат рендеринга
    reg  [ 8:0] x_pos_r;
    wire [ 8:0] x_pos_next_w;
    reg  [ 8:0] y_pos_r;
    reg  [ 8:0] y_pos_next_r;
    reg         frame_r;
    wire        frame_next_w;
    reg         bg_enabled_r;
    wire        bg_enabled_next_w;
    wire        short_line_cond_w;
    wire        end_of_line_w;
    wire        bg_enabled_hold_w;
    wire        end_of_frame_w;

    // Сигналы управления рендерингом
    wire [ 7:0] bg_y_scroll_w;
    wire [ 7:0] bg_x_scroll_w;
    wire [ 1:0] bg_nametable_select_w;

    wire [2:0] fine_x_scroll_w;
    wire [2:0] fine_y_scroll_w;
    wire [4:0] coarse_x_scroll_w;
    wire [4:0] coarse_y_scroll_w;
    wire       hrz_nametable_w;
    wire       vrt_nametable_w;

    wire        bg_pattern_table_select_w;
    wire        sp_pattern_table_select_w;
    wire [ 3:0] bg_x_pos_drawing_start_w;
    wire [ 3:0] sp_x_pos_drawing_start_w;

    wire        bg_render_enabled_w;
    wire        sp_render_enabled_w;
    wire        bg_show_leftmost_pixels_w;
    wire        sp_show_leftmost_pixels_w;
    wire        ppu_render_enabled_w;
    wire        is_pre_rendering_line_w;
    wire        is_vblanking_start_line_w;
    wire        is_visible_lines_w;
    wire        ppu_rendering_lines_w;
    wire        ppu_is_rendering_w;
    wire        bg_is_pattern_fetching_w;
    wire        sp_is_pattern_fetching_w;

    wire        sp0_hit_w;
    wire        sp_overflow_flag_w;
    wire        sp_priority_w;
    wire        sp_size_mode_w;

    // Регистры
    reg  [ 7:0] control_reg_r;
    wire [ 7:0] control_reg_next_w;
    reg  [ 7:0] mask_reg_r;
    wire [ 7:0] mask_reg_next_w;
    reg  [ 2:0] status_reg_r;
    wire [ 2:0] status_reg_next_w;
    reg  [ 2:0] scroll_reg_r;
    wire [ 2:0] scroll_reg_next_w;
    reg  [ 7:0] oam_addr_reg_r;
    reg  [ 7:0] oam_addr_reg_next_r;
    reg  [ 7:0] output_buffer_r;
    reg  [ 7:0] output_buffer_next_r;
    reg  [ 7:0] output_data_r;
    reg  [ 7:0] output_data_next_r;
    reg         write_toggle_r;
    reg         write_toggle_next_r;

    // Сигналы управления регистрами
    reg         wr_r;
    wire        wr_next_w;
    reg         wr_prev_r;
    reg         rd_r;
    wire        rd_next_w;
    reg         rd_prev_r;
    wire        rd_posedge_w;
    wire        wr_posedge_w;
    reg  [ 7:0] reg_data_r;
    reg  [ 2:0] reg_addr_r;

    wire        control_reg_wr_w;
    wire        mask_reg_wr_w;
    wire        oam_data_reg_wr_w;
    wire        oam_addr_reg_wr_w;
    wire        scroll_reg_wr_w;
    wire        addr_reg_wr_w;
    wire        data_reg_wr_w;
    wire        data_reg_rd_w;
    wire        status_reg_rd_w;
    wire        oam_data_reg_rd_w;
    wire        data_reg_wr_or_rd_w;

    /* Сигналы регистров доступа к оперативной памяти
     * в процессе рендеринга */
    wire        write_toggling_w;
    wire        _1st_scroll_reg_wr_w;
    wire        _2nd_scroll_reg_wr_w;
    wire        _1st_addr_reg_wr_w;
    wire        _2nd_addr_reg_wr_w;

    wire        pos_incr_hrz_w;
    wire        pos_copy_vrt_w;
    wire        incr_hrz_w;
    wire        incr_vrt_w;
    wire        copy_hrz_w;
    wire        copy_vrt_w;
    wire        rd_wrrd_no_rndr_w;
    wire        rd_wrrd_in_rndr_w;

    wire        switch_hrz_nametable;
    wire        increment_fine_y;
    wire        switch_vrt_nametable;
    wire        zeroing_coarse_y;

    reg  [14:0] curr_vmem_addr_reg_r;
    reg  [14:0] curr_vmem_addr_reg_next_r;
    reg  [14:0] temp_vmem_addr_reg_r;
    reg  [14:0] temp_vmem_addr_reg_next_r;
    reg  [14:0] x_incr_r;
    reg  [14:0] y_incr_r;
    wire        vmem_addr_inc_select_w;
    wire [ 5:0] vmem_addr_inc_value_w;

    // Сигнал VBLANK и прерывание
    reg         vblanking_r;
    reg         vblanking_next_r;
    wire        vblank_start_pos_w;
    wire        vblank_end_pos_w;
    wire        vblank_reset_cond_w;
    reg         nmi_stage_r;
    wire        nmi_stage_next_w;
    reg         ppu_nmi_r;
    wire        ppu_nmi_next_w;
    wire        nmi_enable_w;

    // Сигналы обращения к памяти
    wire        pattern_table_mclk_w;
    wire        pattern_table_access_w;
    wire        pattern_table_rndr_w;
    wire        pattern_table_cpu_wr_w;
    wire        pattern_table_cpu_rd_w;
    wire        pattern_table_wr_w;
    wire        pattern_table_rd_w;
    reg  [12:0] pattern_table_addr_r;
    wire [ 7:0] pattern_table_wr_data_w;
    wire        bg_get_pattern_table_data_w;
    wire        sp_get_pattern_table_data_w;
    wire [13:0] bg_pattern_table_addr_w;
    wire [13:0] sp_pattern_table_addr_w;

    wire        nametable_mclk_w;
    wire        nametable_access_w;
    wire        nametable_rndr_w;
    wire        nametable_cpu_wr_w;
    wire        nametable_cpu_rd_w;
    wire        nametable_wr_w;
    wire        nametable_rd_w;
    wire [11:0] nametable_raw_addr_w;
    reg  [11:0] nametable_addr_r;
    wire [ 7:0] nametable_wr_data_w;
    wire [ 7:0] nametable_rd_data_w;
    wire        bg_get_nametable_data_w;
    wire [13:0] bg_nametable_addr_w;

    wire        use_palette_w;
    wire        use_sp_palette_w;
    wire        use_bg_palette_w;
    wire        use_bd_palette_w;
    wire        sp_bg_palette_cpu_rd_w;

    wire        sp_palette_mclk_w;
    wire        sp_palette_access_w;
    wire        sp_bd_palette_access_w;
    wire        sp_palette_rndr_w;
    wire        sp_palette_cpu_wr_w;
    wire        sp_palette_cpu_rd_w;
    wire        sp_palette_wr_w;
    wire        sp_palette_rd_w;
    reg  [3:0]  sp_palette_addr_r;
    wire [7:0]  sp_palette_wr_data_w;
    wire [7:0]  sp_palette_rd_data_w;

    wire        bg_palette_mclk_w;
    wire        bg_palette_access_w;
    wire        bg_bd_palette_access_w;
    wire        bg_palette_rndr_w;
    wire        bg_palette_cpu_wr_w;
    wire        bg_palette_cpu_rd_w;
    wire        bg_palette_wr_w;
    wire        bg_palette_rd_w;
    reg  [3:0]  bg_palette_addr_r;
    wire [7:0]  bg_palette_wr_data_w;
    wire [7:0]  bg_palette_rd_data_w;

    wire        oam_mclk_w;
    wire        oam_rndr_w;
    wire        oam_cpu_wr_w;
    wire        oam_cpu_rd_w;
    wire        oam_wr_w;
    wire        oam_rd_w;
    wire [ 7:0] oam_addr_w;
    wire [ 7:0] oam_wr_data_w;
    wire [ 7:0] oam_rd_data_w;
    wire [ 7:0] sp_oam_addr_w;
    wire        sp_evaluation_in_progress_w;

    // Сигналы формирования пикселя
    wire [ 3:0] bg_pixel_index_w;
    wire [ 3:0] sp_pixel_index_w;
    wire [ 1:0] bg_pattern_index_w;
    wire [ 1:0] sp_pattern_index_w;
    wire        bg_pixel_is_opaque_w;
    wire        sp_pixel_is_opaque_w;
    wire        bg_pixel_is_transperent_w;
    wire        sp_pixel_is_transperent_w;

    reg  [ 7:0] output_pixel_r;
    reg  [ 7:0] output_pixel_next_r;


    // Логика счётчиков горизонтальной и вертикальной координат рендеринга
    always @(posedge clk_i)
        if (rst_i) begin
            x_pos_r      <= 9'd0;
            y_pos_r      <= 9'd0;
            frame_r      <= 1'b0;
            bg_enabled_r <= 1'b0;
        end else begin
            x_pos_r      <= x_pos_next_w;
            y_pos_r      <= y_pos_next_r;
            frame_r      <= frame_next_w;
            bg_enabled_r <= bg_enabled_next_w;
        end

    assign short_line_cond_w = is_pre_rendering_line_w && bg_enabled_r && frame_r;
    assign bg_enabled_hold_w = is_pre_rendering_line_w && (x_pos_r > 9'd338);
    assign end_of_frame_w    = is_pre_rendering_line_w && end_of_line_w;
    assign end_of_line_w     = (short_line_cond_w) ? (x_pos_r == 9'd339) : (x_pos_r == 9'd340);

    assign x_pos_next_w      = (end_of_line_w    ) ? 9'd0         : x_pos_r + 1'b1;
    assign frame_next_w      = (end_of_frame_w   ) ? ~frame_r     : frame_r;
    assign bg_enabled_next_w = (bg_enabled_hold_w) ? bg_enabled_r : bg_render_enabled_w;

    wire [1:0] y_pos_next_case_w = {end_of_line_w, is_pre_rendering_line_w};
    always @(*)
        case (y_pos_next_case_w)
            2'b11:   y_pos_next_r = 9'd0;
            2'b10:   y_pos_next_r = y_pos_r + 1'b1;
            default: y_pos_next_r = y_pos_r;
        endcase


    // Логика рендера заднего фона
    ppu_RP2C02_background
        background
        (
            .clk_i                      (clk_i                      ),
            .rst_i                      (rst_i                      ),

            .x_pos_i                    (x_pos_r                    ),
            .y_pos_i                    (y_pos_r                    ),
            .end_of_line_i              (end_of_line_w              ),

            .pattern_table_data_i       (chr_mem_rd_data_i          ),
            .bg_pattern_table_addr_o    (bg_pattern_table_addr_w    ),
            .bg_get_pattern_table_data_o(bg_get_pattern_table_data_w),
            .bg_is_pattern_fetching_o   (bg_is_pattern_fetching_w   ),

            .nametable_data_i           (nametable_rd_data_w        ),
            .bg_nametable_addr_o        (bg_nametable_addr_w        ),
            .bg_get_nametable_data_o    (bg_get_nametable_data_w    ),

            .ppu_render_enabled_i       (ppu_render_enabled_w       ),
            .ppu_rendering_lines_i      (ppu_rendering_lines_w      ),
            .ppu_is_rendering_i         (ppu_is_rendering_w         ),

            .bg_render_enabled_i        (bg_render_enabled_w        ),
            .bg_x_pos_drawing_start_i   (bg_x_pos_drawing_start_w   ),
            .bg_pattern_table_select_i  (bg_pattern_table_select_w  ),

            .fine_x_scroll_i            (fine_x_scroll_w            ),
            .fine_y_scroll_i            (fine_y_scroll_w            ),
            .coarse_x_scroll_i          (coarse_x_scroll_w          ),
            .coarse_y_scroll_i          (coarse_y_scroll_w          ),
            .hrz_nametable_i            (hrz_nametable_w            ),
            .vrt_nametable_i            (vrt_nametable_w            ),

            .bg_pixel_index_o           (bg_pixel_index_w           )
        );


    // Логика рендера переднего фона
    ppu_RP2C02_sprites
        sprites
        (
            .clk_i                      (clk_i                      ),
            .rst_i                      (rst_i                      ),

            .x_pos_i                    (x_pos_r                    ),
            .y_pos_i                    (y_pos_r                    ),

            .pattern_table_data_i       (chr_mem_rd_data_i          ),
            .sp_pattern_table_addr_o    (sp_pattern_table_addr_w    ),
            .sp_get_pattern_table_data_o(sp_get_pattern_table_data_w),
            .sp_is_pattern_fetching_o   (sp_is_pattern_fetching_w   ),

            .sp_oam_data_i              (oam_rd_data_w              ),
            .sp_oam_addr_o              (sp_oam_addr_w              ),
            .sp_evaluation_in_progress_o(sp_evaluation_in_progress_w),

            .ppu_render_enabled_i       (ppu_render_enabled_w       ),
            .ppu_rendering_lines_i      (ppu_rendering_lines_w      ),
            .ppu_is_rendering_i         (ppu_is_rendering_w         ),

            .sp_render_enabled_i        (sp_render_enabled_w        ),
            .sp_x_pos_drawing_start_i   (sp_x_pos_drawing_start_w   ),
            .sp_size_mode_i             (sp_size_mode_w             ),
            .sp_pattern_table_select_i  (sp_pattern_table_select_w  ),
            .bg_pattern_index_i         (bg_pattern_index_w         ),

            .sp_priority_o              (sp_priority_w              ),
            .sp0_hit_o                  (sp0_hit_w                  ),
            .sp_overflow_flag_o         (sp_overflow_flag_w         ),

            .sp_pixel_index_o           (sp_pixel_index_w           )
        );


    // Формирование выходного пикселя
    always @(posedge clk_i)
        if   (rst_i) output_pixel_r <= 8'h3F;
        else         output_pixel_r <= output_pixel_next_r;

    assign bg_pattern_index_w        = bg_pixel_index_w[1:0];
    assign sp_pattern_index_w        = sp_pixel_index_w[1:0];
    assign bg_pixel_is_opaque_w      = |bg_pattern_index_w;
    assign sp_pixel_is_opaque_w      = |sp_pattern_index_w;
    assign bg_pixel_is_transperent_w = ~bg_pixel_is_opaque_w;
    assign sp_pixel_is_transperent_w = ~sp_pixel_is_opaque_w;

    wire [3:0] out_pixel_sel_w = {ppu_is_rendering_w, bg_pixel_is_opaque_w, sp_pixel_is_opaque_w, sp_priority_w};
    always @(*)
        casez (out_pixel_sel_w)
            4'b0_??_?: output_pixel_next_r = 8'h3F;
            4'b1_00_?: output_pixel_next_r = bg_palette_rd_data_w;
            4'b1_01_?: output_pixel_next_r = sp_palette_rd_data_w;
            4'b1_10_?: output_pixel_next_r = bg_palette_rd_data_w;
            4'b1_11_0: output_pixel_next_r = sp_palette_rd_data_w;
            4'b1_11_1: output_pixel_next_r = bg_palette_rd_data_w;
        endcase


    // Сигналы управления рендерингом
    assign bg_show_leftmost_pixels_w = mask_reg_next_w   [1];
    assign sp_show_leftmost_pixels_w = mask_reg_next_w   [2];
    assign bg_render_enabled_w       = mask_reg_next_w   [3];
    assign sp_render_enabled_w       = mask_reg_next_w   [4];
    assign vmem_addr_inc_select_w    = control_reg_next_w[2];
    assign sp_pattern_table_select_w = control_reg_next_w[3];
    assign bg_pattern_table_select_w = control_reg_next_w[4];
    assign sp_size_mode_w            = control_reg_next_w[5];
    assign nmi_enable_w              = control_reg_next_w[7];

    assign bg_x_pos_drawing_start_w  = (bg_show_leftmost_pixels_w) ? 4'd0  : 4'd8;
    assign sp_x_pos_drawing_start_w  = (sp_show_leftmost_pixels_w) ? 4'd0  : 4'd8;
    assign vmem_addr_inc_value_w     = (vmem_addr_inc_select_w   ) ? 6'h20 : 6'h1;

    assign bg_nametable_select_w     = {curr_vmem_addr_reg_r[11:10]};
    assign bg_y_scroll_w             = {curr_vmem_addr_reg_r[ 9: 5], curr_vmem_addr_reg_r[14:12]};
    assign bg_x_scroll_w             = {curr_vmem_addr_reg_r[ 4: 0], scroll_reg_r        [ 2: 0]};

    assign fine_x_scroll_w           = scroll_reg_r        [ 2: 0];
    assign fine_y_scroll_w           = curr_vmem_addr_reg_r[14:12];
    assign coarse_x_scroll_w         = curr_vmem_addr_reg_r[ 4: 0];
    assign coarse_y_scroll_w         = curr_vmem_addr_reg_r[ 9: 5];
    assign hrz_nametable_w           = curr_vmem_addr_reg_r[10];
    assign vrt_nametable_w           = curr_vmem_addr_reg_r[11];

    assign is_pre_rendering_line_w   = (y_pos_r == 9'd261);
    assign is_vblanking_start_line_w = (y_pos_r == 9'd241);
    assign is_visible_lines_w        = (y_pos_r <  9'd240);

    assign ppu_rendering_lines_w     = is_visible_lines_w    || is_pre_rendering_line_w;
    assign ppu_render_enabled_w      = bg_render_enabled_w   || sp_render_enabled_w;
    assign ppu_is_rendering_w        = ppu_rendering_lines_w && ppu_render_enabled_w;


    // Логика сигнала VBLANK и прерывания
    always @(posedge clk_i)
        if (rst_i) begin
            vblanking_r <= 1'b0;
            nmi_stage_r <= 1'b0;
            ppu_nmi_r   <= 1'b0;
        end else begin
            vblanking_r <= vblanking_next_r;
            nmi_stage_r <= nmi_stage_next_w;
            ppu_nmi_r   <= ppu_nmi_next_w;
        end

    assign nmi_stage_next_w    = ~status_reg_rd_w && vblanking_r && nmi_enable_w;
    assign ppu_nmi_next_w      = ~status_reg_rd_w && nmi_stage_r;

    assign vblank_start_pos_w  = (~|x_pos_r) && is_vblanking_start_line_w;
    assign vblank_end_pos_w    = (~|x_pos_r) && is_pre_rendering_line_w;
    assign vblank_reset_cond_w = vblank_end_pos_w || status_reg_rd_w;

    always @(*)
        if      (vblank_start_pos_w ) vblanking_next_r = 1'b1;
        else if (vblank_reset_cond_w) vblanking_next_r = 1'b0;
        else                          vblanking_next_r = vblanking_r;


    // Логика сигналов управления памятью и регистрами
    always @(posedge clk_i)
        if (rst_i) begin
            wr_r       <= 1'b0;
            wr_prev_r  <= 1'b0;
            rd_r       <= 1'b0;
            rd_prev_r  <= 1'b0;
        end else begin
            wr_r       <= wr_next_w;
            wr_prev_r  <= wr_r;
            rd_r       <= rd_next_w;
            rd_prev_r  <= rd_r;
        end

    always @(posedge clk_i)
        begin
            reg_data_r <= ppu_wr_data_i;
            reg_addr_r <= ppu_addr_i;
        end

    assign wr_next_w               = ppu_wr_i & ~wr_prev_r & ~wr_posedge_w;
    assign rd_next_w               = ppu_rd_i & ~rd_prev_r & ~rd_posedge_w;

    assign wr_posedge_w            = ~wr_prev_r & wr_r;
    assign rd_posedge_w            = ~rd_prev_r & rd_r;

    assign control_reg_wr_w        = wr_posedge_w && (reg_addr_r == PPU_CONTROL_REG_ADDR);
    assign mask_reg_wr_w           = wr_posedge_w && (reg_addr_r == PPU_MASK_REG_ADDR);
    assign oam_data_reg_wr_w       = wr_posedge_w && (reg_addr_r == OAM_DATA_REG_ADDR);
    assign oam_addr_reg_wr_w       = wr_posedge_w && (reg_addr_r == OAM_ADDR_REG_ADDR);
    assign scroll_reg_wr_w         = wr_posedge_w && (reg_addr_r == PPU_SCROLL_REG_ADDR);
    assign addr_reg_wr_w           = wr_posedge_w && (reg_addr_r == PPU_ADDR_REG_ADDR);
    assign data_reg_wr_w           = wr_posedge_w && (reg_addr_r == PPU_DATA_REG_ADDR);

    assign data_reg_rd_w           = rd_posedge_w && (reg_addr_r == PPU_DATA_REG_ADDR);
    assign status_reg_rd_w         = rd_posedge_w && (reg_addr_r == PPU_STATUS_REG_ADDR);
    assign oam_data_reg_rd_w       = rd_posedge_w && (reg_addr_r == OAM_DATA_REG_ADDR);

    assign data_reg_wr_or_rd_w     = data_reg_rd_w || data_reg_wr_w;

    assign write_toggling_w        = scroll_reg_wr_w ||  addr_reg_wr_w;
    assign _1st_scroll_reg_wr_w    = scroll_reg_wr_w && ~write_toggle_r;
    assign _2nd_scroll_reg_wr_w    = scroll_reg_wr_w &&  write_toggle_r;
    assign _1st_addr_reg_wr_w      = addr_reg_wr_w   && ~write_toggle_r;
    assign _2nd_addr_reg_wr_w      = addr_reg_wr_w   &&  write_toggle_r;

    assign pattern_table_mclk_w    = mclk_i;
    assign nametable_mclk_w        = mclk_i;
    assign sp_palette_mclk_w       = mclk_i;
    assign bg_palette_mclk_w       = mclk_i;
    assign oam_mclk_w              = mclk_i;

    assign pattern_table_access_w  =  ~curr_vmem_addr_reg_r[13];
    assign nametable_access_w      =   curr_vmem_addr_reg_r[13] && ~curr_vmem_addr_reg_r[12];
    assign use_palette_w           =   curr_vmem_addr_reg_r[13] && &curr_vmem_addr_reg_r[12:8];
    assign use_sp_palette_w        =   curr_vmem_addr_reg_r[4];
    assign use_bg_palette_w        =  ~curr_vmem_addr_reg_r[4];
    assign use_bd_palette_w        = ~|curr_vmem_addr_reg_r[1:0];
    assign sp_palette_access_w     = use_palette_w && use_sp_palette_w;
    assign bg_palette_access_w     = use_palette_w && use_bg_palette_w;
    assign sp_bd_palette_access_w  = use_palette_w && (use_sp_palette_w || use_bd_palette_w);
    assign bg_bd_palette_access_w  = use_palette_w && (use_bg_palette_w || use_bd_palette_w);

    assign pattern_table_cpu_wr_w  = data_reg_wr_w && pattern_table_access_w;
    assign nametable_cpu_wr_w      = data_reg_wr_w && nametable_access_w;
    assign sp_palette_cpu_wr_w     = data_reg_wr_w && sp_bd_palette_access_w;
    assign bg_palette_cpu_wr_w     = data_reg_wr_w && bg_bd_palette_access_w;
    assign oam_cpu_wr_w            = oam_data_reg_wr_w;

    assign pattern_table_cpu_rd_w  = data_reg_rd_w && pattern_table_access_w;
    assign nametable_cpu_rd_w      = data_reg_rd_w && nametable_access_w;
    assign sp_palette_cpu_rd_w     = data_reg_rd_w && sp_palette_access_w;
    assign bg_palette_cpu_rd_w     = data_reg_rd_w && bg_palette_access_w;
    assign oam_cpu_rd_w            = oam_data_reg_rd_w;
    assign sp_bg_palette_cpu_rd_w  = sp_palette_cpu_rd_w || bg_palette_cpu_rd_w;

    assign pattern_table_rndr_w    = bg_get_pattern_table_data_w || sp_get_pattern_table_data_w;
    assign nametable_rndr_w        = bg_get_nametable_data_w;
    assign sp_palette_rndr_w       = ppu_is_rendering_w;
    assign bg_palette_rndr_w       = ppu_is_rendering_w;
    assign oam_rndr_w              = sp_evaluation_in_progress_w;

    assign pattern_table_wr_w      = pattern_table_cpu_wr_w;
    assign nametable_wr_w          = nametable_cpu_wr_w;
    assign sp_palette_wr_w         = sp_palette_cpu_wr_w;
    assign bg_palette_wr_w         = bg_palette_cpu_wr_w;
    assign oam_wr_w                = oam_cpu_wr_w;

    assign pattern_table_rd_w      = pattern_table_rndr_w || pattern_table_cpu_rd_w;
    assign nametable_rd_w          = nametable_rndr_w     || nametable_cpu_rd_w || sp_bg_palette_cpu_rd_w;
    assign sp_palette_rd_w         = sp_palette_rndr_w    || sp_palette_cpu_rd_w;
    assign bg_palette_rd_w         = bg_palette_rndr_w    || bg_palette_cpu_rd_w;
    assign oam_rd_w                = oam_rndr_w           || oam_cpu_rd_w;

    assign pattern_table_wr_data_w = reg_data_r;
    assign nametable_wr_data_w     = reg_data_r;
    assign sp_palette_wr_data_w    = reg_data_r;
    assign bg_palette_wr_data_w    = reg_data_r;
    assign oam_wr_data_w           = reg_data_r;

    assign nametable_raw_addr_w    = (nametable_rndr_w) ? bg_nametable_addr_w[11:0] : curr_vmem_addr_reg_r[11:0];
    assign oam_addr_w              = (oam_rndr_w      ) ? sp_oam_addr_w             : oam_addr_reg_r;

    wire [1:0] pattern_table_addr_case_w = {bg_is_pattern_fetching_w, sp_is_pattern_fetching_w};
    always @(*)
        case (pattern_table_addr_case_w)
            2'b10:   pattern_table_addr_r = bg_pattern_table_addr_w[12:0];
            2'b01:   pattern_table_addr_r = sp_pattern_table_addr_w[12:0];
            default: pattern_table_addr_r = curr_vmem_addr_reg_r   [12:0];
        endcase

    always @(*)
        case (nametable_layout_i)
            NTL_SSL: nametable_addr_r     = {1'b0, 1'b0, nametable_raw_addr_w[9:0]};
            NTL_SSU: nametable_addr_r     = {1'b0, 1'b1, nametable_raw_addr_w[9:0]};
            NTL_VM:  nametable_addr_r     = {1'b0, nametable_raw_addr_w[10:0]};
            NTL_HM:  nametable_addr_r     = {1'b0, nametable_raw_addr_w[11], nametable_raw_addr_w[9:0]};
            NTL_FS:  nametable_addr_r     = {nametable_raw_addr_w[11:0]};
            default: nametable_addr_r     = {nametable_raw_addr_w[11:0]};
        endcase

    wire [1:0] bg_palette_addr_case_w = {bg_palette_rndr_w, bg_pixel_is_transperent_w};
    always @(*)
        case (bg_palette_addr_case_w)
            2'b11:   bg_palette_addr_r    = 4'h0;
            2'b10:   bg_palette_addr_r    = bg_pixel_index_w;
            default: bg_palette_addr_r    = curr_vmem_addr_reg_r[3:0];
        endcase

    wire [1:0] sp_palette_addr_case_w = {sp_palette_rndr_w, sp_pixel_is_transperent_w};
    always @(*)
        case (sp_palette_addr_case_w)
            2'b11:   sp_palette_addr_r    = 4'h0;
            2'b10:   sp_palette_addr_r    = sp_pixel_index_w;
            default: sp_palette_addr_r    = curr_vmem_addr_reg_r[3:0];
        endcase


    // Регистры графического процессора
    always @(posedge clk_i)
        if (rst_i) begin
            status_reg_r    <= 3'h4;
            control_reg_r   <= 8'h0;
            mask_reg_r      <= 8'h0;
            scroll_reg_r    <= 3'h0;
            oam_addr_reg_r  <= 8'h0;
            write_toggle_r  <= 1'b0;
            output_buffer_r <= 8'h0;
            output_data_r   <= 8'h0;
        end else begin
            status_reg_r    <= status_reg_next_w;
            control_reg_r   <= control_reg_next_w;
            mask_reg_r      <= mask_reg_next_w;
            scroll_reg_r    <= scroll_reg_next_w;
            oam_addr_reg_r  <= oam_addr_reg_next_r;
            write_toggle_r  <= write_toggle_next_r;
            output_buffer_r <= output_buffer_next_r;
            output_data_r   <= output_data_next_r;
        end

    assign status_reg_next_w  = {vblanking_r, sp0_hit_w, sp_overflow_flag_w};
    assign control_reg_next_w = (control_reg_wr_w    ) ? reg_data_r      : control_reg_r;
    assign mask_reg_next_w    = (mask_reg_wr_w       ) ? reg_data_r      : mask_reg_r;
    assign scroll_reg_next_w  = (_1st_scroll_reg_wr_w) ? reg_data_r[2:0] : scroll_reg_r;

    wire [1:0] oam_addr_reg_next_case_w  = {oam_addr_reg_wr_w, oam_wr_w};
    always @(*)
        case (oam_addr_reg_next_case_w) // one hot
            2'b10:     oam_addr_reg_next_r  = reg_data_r;
            2'b01:     oam_addr_reg_next_r  = oam_addr_reg_r + 1'b1;
            default:   oam_addr_reg_next_r  = oam_addr_reg_r;
        endcase

    wire [2:0] output_buffer_next_case_w = {sp_bg_palette_cpu_rd_w, nametable_cpu_rd_w, pattern_table_cpu_rd_w};
    always @(*)
        case (output_buffer_next_case_w) // one hot
            3'b100:    output_buffer_next_r = nametable_rd_data_w;
            3'b010:    output_buffer_next_r = nametable_rd_data_w;
            3'b001:    output_buffer_next_r = chr_mem_rd_data_i;
            default:   output_buffer_next_r = output_buffer_r;
        endcase

    wire [5:0] output_data_next_case_w = {status_reg_rd_w, oam_cpu_rd_w, bg_palette_cpu_rd_w,
                                          sp_palette_cpu_rd_w, nametable_cpu_rd_w, pattern_table_cpu_rd_w};
    always @(*)
        case (output_data_next_case_w) // one hot
            6'b100000: output_data_next_r   = {status_reg_r[2:0], output_buffer_r[4:0]};
            6'b010000: output_data_next_r   = oam_rd_data_w;
            6'b001000: output_data_next_r   = bg_palette_rd_data_w;
            6'b000100: output_data_next_r   = sp_palette_rd_data_w;
            6'b000010: output_data_next_r   = output_buffer_r;
            6'b000001: output_data_next_r   = output_buffer_r;
            default:   output_data_next_r   = output_data_r;
        endcase

    wire [1:0] write_toggle_next_case_w = {status_reg_rd_w, write_toggling_w};
    always @(*)
        case (write_toggle_next_case_w) // one hot
            2'b10:     write_toggle_next_r  = 1'b0;
            2'b01:     write_toggle_next_r  = ~write_toggle_r;
            default:   write_toggle_next_r  =  write_toggle_r;
        endcase


    // Логика регистров, управляющих доступом к оперативной видеопамяти в процессе рендеринга
    always @(posedge clk_i)
        begin
            temp_vmem_addr_reg_r <= temp_vmem_addr_reg_next_r;
            curr_vmem_addr_reg_r <= curr_vmem_addr_reg_next_r;
        end

    assign pos_incr_hrz_w    = ((x_pos_r < 9'd255) || (x_pos_r > 9'd326)) && (&x_pos_r[2:0]);
    assign pos_copy_vrt_w    =  (x_pos_r > 9'd278) && (x_pos_r < 9'd304)  && is_pre_rendering_line_w;

    assign incr_hrz_w        =  ppu_is_rendering_w   && pos_incr_hrz_w;
    assign incr_vrt_w        =  ppu_is_rendering_w   && (x_pos_r == 9'd255);
    assign copy_hrz_w        =  ppu_is_rendering_w   && (x_pos_r == 9'd256);
    assign copy_vrt_w        =  ppu_render_enabled_w && pos_copy_vrt_w;
    assign rd_wrrd_no_rndr_w = ~ppu_is_rendering_w   && data_reg_wr_or_rd_w;
    assign rd_wrrd_in_rndr_w =  ppu_is_rendering_w   && data_reg_wr_or_rd_w;

    wire [4:0] temp_vmem_addr_reg_next_case_w = {control_reg_wr_w, _1st_scroll_reg_wr_w, _2nd_scroll_reg_wr_w,
                                                 _1st_addr_reg_wr_w, _2nd_addr_reg_wr_w};
    always @(*)
        case (temp_vmem_addr_reg_next_case_w) // one hot

            5'b10000:    temp_vmem_addr_reg_next_r = {temp_vmem_addr_reg_r[14:12], reg_data_r[1:0],
                                                      temp_vmem_addr_reg_r[ 9: 0]};

            5'b01000:    temp_vmem_addr_reg_next_r = {temp_vmem_addr_reg_r[14: 5], reg_data_r[7:3]};

            5'b00100:    temp_vmem_addr_reg_next_r = {reg_data_r[2:0], temp_vmem_addr_reg_r[11:10],
                                                      reg_data_r[7:3], temp_vmem_addr_reg_r[ 4: 0]};

            5'b00010:    temp_vmem_addr_reg_next_r = {1'b0, reg_data_r[5:0], temp_vmem_addr_reg_r[7:0]};

            5'b00001:    temp_vmem_addr_reg_next_r = {temp_vmem_addr_reg_r[14:8], reg_data_r[7:0]};

            default:     temp_vmem_addr_reg_next_r = temp_vmem_addr_reg_r;

        endcase

    wire [2:0] curr_vmem_addr_reg_next_case_wrrd_w = {_2nd_addr_reg_wr_w, rd_wrrd_no_rndr_w, rd_wrrd_in_rndr_w};
    wire [3:0] curr_vmem_addr_reg_next_case_rend_w = {incr_vrt_w, incr_hrz_w, copy_hrz_w, copy_vrt_w};
    wire [6:0] curr_vmem_addr_reg_next_case_w      = {curr_vmem_addr_reg_next_case_wrrd_w,
                                                      curr_vmem_addr_reg_next_case_rend_w};
    always @(*)
        casez (curr_vmem_addr_reg_next_case_w) // one hot _ one hot

            7'b100_????: curr_vmem_addr_reg_next_r = {temp_vmem_addr_reg_r[14:8], reg_data_r[7:0]};

            7'b010_????: curr_vmem_addr_reg_next_r = curr_vmem_addr_reg_r + vmem_addr_inc_value_w;

            7'b001_????: curr_vmem_addr_reg_next_r = {y_incr_r[14:12], y_incr_r[11], x_incr_r[10],
                                                      y_incr_r[ 9: 5], x_incr_r[4:0]};

            7'b000_1000: curr_vmem_addr_reg_next_r = y_incr_r;

            7'b000_0100: curr_vmem_addr_reg_next_r = x_incr_r;

            7'b000_0010: curr_vmem_addr_reg_next_r = {curr_vmem_addr_reg_r[14:11], temp_vmem_addr_reg_r[10],
                                                      curr_vmem_addr_reg_r[ 9: 5], temp_vmem_addr_reg_r[4:0]};

            7'b000_0001: curr_vmem_addr_reg_next_r = {temp_vmem_addr_reg_r[14:11], curr_vmem_addr_reg_r[10],
                                                      temp_vmem_addr_reg_r[ 9: 5], curr_vmem_addr_reg_r[4:0]};

            default:     curr_vmem_addr_reg_next_r = curr_vmem_addr_reg_r;

        endcase

    assign switch_hrz_nametable =  &coarse_x_scroll_w;
    assign switch_vrt_nametable =  (coarse_y_scroll_w == 5'b11101);
    assign zeroing_coarse_y     =  &coarse_y_scroll_w;
    assign increment_fine_y     = ~&fine_y_scroll_w;

    wire [0:0] x_incr_case_w = {switch_hrz_nametable};
    always @(*)
        case (x_incr_case_w)
            1'b1:    x_incr_r = {fine_y_scroll_w, vrt_nametable_w, ~hrz_nametable_w, coarse_y_scroll_w,
                                 5'b00000};
            1'b0:    x_incr_r = {fine_y_scroll_w, vrt_nametable_w,  hrz_nametable_w, coarse_y_scroll_w,
                                 {coarse_x_scroll_w + 1'b1}};
        endcase

    wire [2:0] y_incr_case_w = {increment_fine_y, switch_vrt_nametable, zeroing_coarse_y};
    always @(*)
        casez (y_incr_case_w)
            3'b1_??: y_incr_r = {{fine_y_scroll_w + 1'b1}, vrt_nametable_w, hrz_nametable_w, coarse_y_scroll_w,
                                 coarse_x_scroll_w};
            2'b0_10: y_incr_r = {3'b000, ~vrt_nametable_w, hrz_nametable_w, 5'b00000, coarse_x_scroll_w};
            2'b0_01: y_incr_r = {3'b000,  vrt_nametable_w, hrz_nametable_w, 5'b00000, coarse_x_scroll_w};
            default: y_incr_r = {3'b000,  vrt_nametable_w, hrz_nametable_w, {coarse_y_scroll_w + 1'b1},
                                 coarse_x_scroll_w};
        endcase


    // Оперативная видеопамять
    single_port_no_change_ram
        #(
            .DATA_WIDTH(8                   ),
            .RAM_DEPTH (NAMETABLE_SIZE      ),
            .RAM_STYLE ("block"             ),
            .INIT_VAL  (`MEM_INIT_VAL       ),
            .SIMULATION(`MEM_SIM            )
        )
        nametable
        (
            .clka_i    (nametable_mclk_w    ),
            .addra_i   (nametable_addr_r    ),
            .rda_i     (nametable_rd_w      ),
            .wra_i     (nametable_wr_w      ),
            .dina_i    (nametable_wr_data_w ),
            .douta_o   (nametable_rd_data_w )
        );


    // Память палитры для заднего фона
    single_port_no_change_ram
        #(
            .DATA_WIDTH(8                   ),
            .RAM_DEPTH (BG_PALETTE_SIZE     ),
            .RAM_STYLE ("distributed"       ),
            .INIT_VAL  (`MEM_INIT_VAL       ),
            .SIMULATION(`MEM_SIM            )
        )
        bg_palette
        (
            .clka_i    (bg_palette_mclk_w   ),
            .addra_i   (bg_palette_addr_r   ),
            .rda_i     (bg_palette_rd_w     ),
            .wra_i     (bg_palette_wr_w     ),
            .dina_i    (bg_palette_wr_data_w),
            .douta_o   (bg_palette_rd_data_w)
        );


    // Память палитры для переднего фона
    single_port_no_change_ram
        #(
            .DATA_WIDTH(8                   ),
            .RAM_DEPTH (SP_PALETTE_SIZE     ),
            .RAM_STYLE ("distributed"       ),
            .INIT_VAL  (`MEM_INIT_VAL       ),
            .SIMULATION(`MEM_SIM            )
        )
        sp_palette
        (
            .clka_i    (sp_palette_mclk_w   ),
            .addra_i   (sp_palette_addr_r   ),
            .rda_i     (sp_palette_rd_w     ),
            .wra_i     (sp_palette_wr_w     ),
            .dina_i    (sp_palette_wr_data_w),
            .douta_o   (sp_palette_rd_data_w)
        );


    // Память спрайтов переднего фона
    single_port_no_change_ram
        #(
            .DATA_WIDTH(8                   ),
            .RAM_DEPTH (OAM_SIZE            ),
            .RAM_STYLE ("block"             ),
            .INIT_VAL  (`MEM_INIT_VAL       ),
            .SIMULATION(`MEM_SIM            )
        )
        oam
        (
            .clka_i    (oam_mclk_w          ),
            .addra_i   (oam_addr_w          ),
            .rda_i     (oam_rd_w            ),
            .wra_i     (oam_wr_w            ),
            .dina_i    (oam_wr_data_w       ),
            .douta_o   (oam_rd_data_w       )
        );


    // Выходы
    assign chr_mem_mclk_o     = pattern_table_mclk_w;
    assign chr_mem_wr_o       = pattern_table_wr_w;
    assign chr_mem_rd_o       = pattern_table_rd_w;
    assign chr_mem_addr_o     = pattern_table_addr_r;
    assign chr_mem_wr_data_o  = pattern_table_wr_data_w;

    assign ppu_rd_data_o      = output_data_r;

    assign ppu_nmi_o          = ppu_nmi_r;

    assign ppu_output_pixel_o = output_pixel_r;
    assign ppu_x_pos_o        = x_pos_r;
    assign ppu_y_pos_o        = y_pos_r;


endmodule
