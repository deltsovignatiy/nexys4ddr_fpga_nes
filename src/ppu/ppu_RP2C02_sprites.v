
/*
 * Description : RP2C02 sprites render logic implementation module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module ppu_RP2C02_sprites
    (
        input  wire        clk_i,                       // Сигнал тактирования
        input  wire        rst_i,                       // Сигнал сброса

        input  wire [ 8:0] x_pos_i,                     // Горизонтальная координата рендеринга
        input  wire [ 8:0] y_pos_i,                     // Вертикальная координата рендеринга

        input  wire [ 7:0] pattern_table_data_i,        // Данные из видеопамяти на картридже (тайлы)
        output wire [13:0] sp_pattern_table_addr_o,     // Адрес для видеопамяти на картридже
        output wire        sp_get_pattern_table_data_o, // Сигнал считывания данных из видеопамяти на картридже
        output wire        sp_is_pattern_fetching_o,    // Сигнал для арбитража доступа к видеопамяти на картридже

        input  wire [ 7:0] sp_oam_data_i,               // Данные из первичной памяти спрайтов переднего фона
        output wire [ 7:0] sp_oam_addr_o,               // Адрес для первичной памяти спрайтов переднего фона
        output wire        sp_evaluation_in_progress_o, // Извлечение данных из первичной памяти спрайтов в процессе

        input  wire        ppu_render_enabled_i,        // Общий рендеринг включен
        input  wire        ppu_rendering_lines_i,       // Координаты рендеринга внутри видимой области
        input  wire        ppu_is_rendering_i,          // Рендеринг в процессе (ppu_render_enabled_i && ppu_rendering_lines_i)

        input  wire        sp_render_enabled_i,         // Рендеринг переднего фона включен
        input  wire [ 3:0] sp_x_pos_drawing_start_i,    // Горизонтальная координата начала рендеринга переднего фона
        input  wire        sp_size_mode_i,              // Выбор размера спрайтов
        input  wire        sp_pattern_table_select_i,   // Выбор банка видеопамяти на картридже с тайлами для рендеринга
        input  wire [ 1:0] bg_pattern_index_i,          // Сигнал, информирующий о непрозрачности текущего пикселя заднего фона

        output wire        sp_priority_o,               // Сигнал приоритета пикселя переднего фона
        output wire        sp0_hit_o,                   // Сигнал-флаг попадания в "нулевой" спрайт
        output wire        sp_overflow_flag_o,          // Сигнал-флаг о переполнении вторичной памяти спрайтов

        output wire [ 3:0] sp_pixel_index_o             // Выходной пиксель логики рендера переднего фона
    );


    // Состояния конечного автомата
    localparam [4:0] IDLE                               = 0,
                     INIT_SOAM_READ                     = 1,
                     INIT_SOAM_WRITE                    = 2,
                     EVALUATION_TILE_Y_COORDINATE_READ  = 3,
                     EVALUATION_TILE_Y_COORDINATE_WRITE = 4,
                     EVALUATION_TILE_INDEX_READ         = 5,
                     EVALUATION_TILE_INDEX_WRITE        = 6,
                     EVALUATION_TILE_ATTRIBUTES_READ    = 7,
                     EVALUATION_TILE_ATTRIBUTES_WRITE   = 8,
                     EVALUATION_TILE_X_COORDINATE_READ  = 9,
                     EVALUATION_TILE_X_COORDINATE_WRITE = 10,
                     WAITING_FOR_HBLANK                 = 11,
                     FETCH_TILE_Y_COORDINATE_GET_DATA   = 12,
                     FETCH_TILE_INDEX_GET_DATA          = 13,
                     FETCH_TILE_ATTRIBUTES_GET_DATA     = 14,
                     FETCH_TILE_X_COORDINATE_GET_DATA   = 15,
                     FETCH_TILE_PATTERN_LOW_SET_ADDR    = 16,
                     FETCH_TILE_PATTERN_LOW_GET_DATA    = 17,
                     FETCH_TILE_PATTERN_HIGH_SET_ADDR   = 18,
                     FETCH_TILE_PATTERN_HIGH_GET_DATA   = 19;


    // Конечный автомат
    reg  [ 4:0] state_r;
    reg  [ 4:0] state_next_r;

    wire        eval_y_coord_write_sn_w;
    wire        eval_index_write_sn_w;
    wire        eval_attributes_write_sn_w;
    wire        eval_x_coord_write_sn_w;
    wire        set_pattern_low_addr_sn_w;
    wire        set_pattern_high_addr_sn_w;
    wire        get_pattern_low_data_sn_w;
    wire        get_pattern_high_data_sn_w;

    wire        init_soam_write_st_w;
    wire        eval_x_coord_write_st_w;
    wire        eval_y_coord_write_st_w;
    wire        get_y_coord_data_st_w;
    wire        get_index_data_st_w;
    wire        get_attributes_data_st_w;
    wire        get_x_coord_data_st_w;
    wire        get_pattern_high_data_st_w;

    // Доступ к данным и памяти
    reg  [ 8:0] oam_addr_r;
    reg  [ 8:0] oam_addr_next_r;
    reg  [ 4:0] soam_addr_r;
    reg  [ 4:0] soam_addr_next_r;
    wire        soam_addr_eval_y_incr_w;
    wire        sp_evaluation_in_progress_w;

    reg  [ 7:0] soam_r[31:0];
    reg  [ 7:0] soam_next_r;
    wire        soam_wr_en_w;
    wire        sp_is_active_w;
    wire [ 7:0] soam_data_w;

    reg  [ 2:0] fetch_counter_r;
    reg  [ 2:0] fetch_counter_next_r;
    reg         fetch_empty_sp_r;
    wire        fetch_empty_sp_next_w;

    reg  [ 3:0] eval_counter_r;
    reg  [ 3:0] eval_counter_next_r;
    reg         overflow_flag_r;
    reg         overflow_flag_next_r;
    wire        overflow_flag_rst_pos_w;
    wire        overflow_flag_set_cond_w;

    wire        start_init_soam_w;
    wire        end_of_oam_w;
    wire        end_of_soam_init_w;
    wire        end_of_evaluation_w;
    wire        last_fetch_w;

    wire [13:0] pattern_low_addr_w;
    wire [13:0] pattern_high_addr_w;
    reg  [13:0] sp_pattern_table_addr_r;
    reg  [13:0] sp_pattern_table_addr_next_r;
    wire        sp_pattern_table_access_w;
    wire        sp_get_pattern_table_data_w;
    wire [ 7:0] pattern_table_data_flipped_w;
    reg  [ 7:0] pattern_data_r;

    // Рендер
    wire        sp_visible_lines_w;
    wire        sp_visible_dots_w;
    wire        sp_rendering_dots_w;
    wire        sp_pattern_fetching_dots_w;
    wire        sp_is_rendering_w;
    wire        sp_is_visible_w;
    wire        sp_is_pattern_fetching_w;

    wire [ 8:0] sp_y_eval_diff_w;
    wire [ 4:0] sp_y_size_w;
    wire        y_coord_in_range_w;
    wire        hblank_is_reached_w;
    wire        flags_clear_pos_w;

    wire        sp0_is_frontmost_w;
    wire        sp0_hit_rst_pos_w;
    wire        sp0_hit_set_cond_w;
    wire        sp0_is_present_rst_pos_w;
    wire        sp0_is_present_set_pos_w;
    wire        sp0_is_found_rst_pos_w;
    wire        sp0_is_found_set_cond_w;
    reg         sp0_hit_r;
    reg         sp0_hit_next_r;
    reg         sp0_is_present_r;
    reg         sp0_is_present_next_r;
    reg         sp0_is_found_r;
    reg         sp0_is_found_next_r;

    wire        pattern_table_sel_w;
    wire [ 8:0] sp_y_diff_w;
    wire        sp_bot_half_w;
    wire        sp_v_flip_w;
    wire        sp_h_flip_w;
    wire [ 7:0] sp_y_coord_w;
    wire [ 7:0] sp_tile_index_w;
    wire [ 7:0] sp_tile_w;
    wire [ 2:0] y_offset_w;

    wire        sp_sel_w                    [7:0];
    wire        get_y_coord_data_w          [7:0];
    wire        get_index_data_w            [7:0];
    wire        get_attributes_data_w       [7:0];
    wire        get_x_coord_data_w          [7:0];
    wire        get_pattern_low_data_w      [7:0];
    wire        get_pattern_high_data_w     [7:0];
    wire        x_coord_updating_w          [7:0];
    wire        shifters_updating_w         [7:0];
    wire [ 7:0] pattern_low_shifted_w       [7:0];
    wire [ 7:0] pattern_high_shifted_w      [7:0];
    reg  [ 7:0] y_coord_data_r              [7:0];
    wire [ 7:0] y_coord_data_next_w         [7:0];
    reg  [ 7:0] index_data_r                [7:0];
    wire [ 7:0] index_data_next_w           [7:0];
    reg  [ 7:0] attributes_data_r           [7:0];
    wire [ 7:0] attributes_data_next_w      [7:0];
    reg  [ 7:0] x_coord_data_r              [7:0];
    reg  [ 7:0] x_coord_data_next_r         [7:0];
    reg  [ 7:0] pattern_low_shifter_r       [7:0];
    reg  [ 7:0] pattern_low_shifter_next_r  [7:0];
    reg  [ 7:0] pattern_high_shifter_r      [7:0];
    reg  [ 7:0] pattern_high_shifter_next_r [7:0];
    wire        v_flip_w                    [7:0];
    wire        h_flip_w                    [7:0];
    wire        priority_w                  [7:0];
    reg  [ 1:0] pattern_index_data_r        [7:0];
    reg  [ 1:0] palette_index_data_r        [7:0];
    wire        is_opaque_w                 [7:0];

    // Выходной пиксель
    reg  [ 3:0] frontmost_index_data_r;
    wire [ 3:0] frontmost_pixel_index_w;
    wire [ 1:0] frontmost_pattern_w;
    wire        frontmost_priority_w;
    wire        is_transperent_w;


    assign sp_y_eval_diff_w           = (y_pos_i - sp_oam_data_i);
    assign sp_y_size_w                = (sp_size_mode_i) ? 5'd16 : 5'd8;
    assign y_coord_in_range_w         = (sp_y_eval_diff_w < sp_y_size_w);

    assign flags_clear_pos_w          = (y_pos_i == 9'd261) && (~|x_pos_i); // (x_pos_i == 9'd0)

    assign hblank_is_reached_w        = (x_pos_i == 9'd256);

    assign sp_visible_lines_w         = (y_pos_i <  9'd240) && (y_pos_i > 9'd0);
    assign sp_visible_dots_w          = (x_pos_i <  9'd257) && (x_pos_i > sp_x_pos_drawing_start_i);
    assign sp_rendering_dots_w        = (x_pos_i <  9'd257) && (x_pos_i > 9'd0);
    assign sp_pattern_fetching_dots_w = (x_pos_i >  9'd256) && (x_pos_i < 9'd321);

    assign sp_is_visible_w            = sp_visible_lines_w && sp_visible_dots_w && sp_render_enabled_i;
    assign sp_is_rendering_w          = ppu_is_rendering_i && sp_rendering_dots_w;
    assign sp_is_pattern_fetching_w   = ppu_is_rendering_i && sp_pattern_fetching_dots_w;


    // Логика конечного автомата
    always @(posedge clk_i)
        if   (rst_i) state_r <= IDLE;
        else         state_r <= state_next_r;

    assign end_of_oam_w        = oam_addr_r[8];
    assign end_of_soam_init_w  = &soam_addr_r;
    assign start_init_soam_w   = ppu_rendering_lines_i && (~|x_pos_i);
    assign end_of_evaluation_w = end_of_oam_w || (eval_counter_r == 4'd9);
    assign last_fetch_w        = &fetch_counter_r;

    always @(*)
        case (state_r)

            IDLE:                               state_next_r = (start_init_soam_w) ? INIT_SOAM_READ : IDLE;

            INIT_SOAM_READ:                     state_next_r = INIT_SOAM_WRITE;

            INIT_SOAM_WRITE:                    state_next_r = (end_of_soam_init_w) ? EVALUATION_TILE_Y_COORDINATE_READ :
                                                                                      INIT_SOAM_READ;

            EVALUATION_TILE_Y_COORDINATE_READ:  state_next_r = (end_of_evaluation_w) ? WAITING_FOR_HBLANK :
                                                                                       EVALUATION_TILE_Y_COORDINATE_WRITE;

            EVALUATION_TILE_Y_COORDINATE_WRITE: state_next_r = (y_coord_in_range_w) ? EVALUATION_TILE_INDEX_READ :
                                                                                      EVALUATION_TILE_Y_COORDINATE_READ;

            EVALUATION_TILE_INDEX_READ:         state_next_r = EVALUATION_TILE_INDEX_WRITE;

            EVALUATION_TILE_INDEX_WRITE:        state_next_r = EVALUATION_TILE_ATTRIBUTES_READ;

            EVALUATION_TILE_ATTRIBUTES_READ:    state_next_r = EVALUATION_TILE_ATTRIBUTES_WRITE;

            EVALUATION_TILE_ATTRIBUTES_WRITE:   state_next_r = EVALUATION_TILE_X_COORDINATE_READ;

            EVALUATION_TILE_X_COORDINATE_READ:  state_next_r = EVALUATION_TILE_X_COORDINATE_WRITE;

            EVALUATION_TILE_X_COORDINATE_WRITE: state_next_r = EVALUATION_TILE_Y_COORDINATE_READ;

            WAITING_FOR_HBLANK:                 state_next_r = (hblank_is_reached_w) ? FETCH_TILE_Y_COORDINATE_GET_DATA :
                                                                                       WAITING_FOR_HBLANK;

            FETCH_TILE_Y_COORDINATE_GET_DATA:   state_next_r = FETCH_TILE_INDEX_GET_DATA;

            FETCH_TILE_INDEX_GET_DATA:          state_next_r = FETCH_TILE_ATTRIBUTES_GET_DATA;

            FETCH_TILE_ATTRIBUTES_GET_DATA:     state_next_r = FETCH_TILE_X_COORDINATE_GET_DATA;

            FETCH_TILE_X_COORDINATE_GET_DATA:   state_next_r = FETCH_TILE_PATTERN_LOW_SET_ADDR;

            FETCH_TILE_PATTERN_LOW_SET_ADDR:    state_next_r = FETCH_TILE_PATTERN_LOW_GET_DATA;

            FETCH_TILE_PATTERN_LOW_GET_DATA:    state_next_r = FETCH_TILE_PATTERN_HIGH_SET_ADDR;

            FETCH_TILE_PATTERN_HIGH_SET_ADDR:   state_next_r = FETCH_TILE_PATTERN_HIGH_GET_DATA;

            FETCH_TILE_PATTERN_HIGH_GET_DATA:   state_next_r = (last_fetch_w) ? IDLE :
                                                                                FETCH_TILE_Y_COORDINATE_GET_DATA;

            default:                            state_next_r = state_r;

        endcase


    assign eval_y_coord_write_sn_w    = (state_next_r == EVALUATION_TILE_Y_COORDINATE_WRITE);
    assign eval_index_write_sn_w      = (state_next_r == EVALUATION_TILE_INDEX_WRITE);
    assign eval_attributes_write_sn_w = (state_next_r == EVALUATION_TILE_ATTRIBUTES_WRITE);
    assign eval_x_coord_write_sn_w    = (state_next_r == EVALUATION_TILE_X_COORDINATE_WRITE);
    assign set_pattern_low_addr_sn_w  = (state_next_r == FETCH_TILE_PATTERN_LOW_SET_ADDR);
    assign set_pattern_high_addr_sn_w = (state_next_r == FETCH_TILE_PATTERN_HIGH_SET_ADDR);
    assign get_pattern_low_data_sn_w  = (state_next_r == FETCH_TILE_PATTERN_LOW_GET_DATA);
    assign get_pattern_high_data_sn_w = (state_next_r == FETCH_TILE_PATTERN_HIGH_GET_DATA);

    assign init_soam_write_st_w       = (state_r      == INIT_SOAM_WRITE);
    assign eval_x_coord_write_st_w    = (state_r      == EVALUATION_TILE_X_COORDINATE_WRITE);
    assign eval_y_coord_write_st_w    = (state_r      == EVALUATION_TILE_Y_COORDINATE_WRITE);
    assign get_y_coord_data_st_w      = (state_r      == FETCH_TILE_Y_COORDINATE_GET_DATA);
    assign get_index_data_st_w        = (state_r      == FETCH_TILE_INDEX_GET_DATA);
    assign get_attributes_data_st_w   = (state_r      == FETCH_TILE_ATTRIBUTES_GET_DATA);
    assign get_x_coord_data_st_w      = (state_r      == FETCH_TILE_X_COORDINATE_GET_DATA);
    assign get_pattern_high_data_st_w = (state_r      == FETCH_TILE_PATTERN_HIGH_GET_DATA);


    // Логика памяти спрайтов отдельной строки (вторичная память спрайтов)
    always @(posedge clk_i)
        if (rst_i) begin
            oam_addr_r          <= 9'h0;
            soam_addr_r         <= 5'h0;
        end else begin
            oam_addr_r          <= oam_addr_next_r;
            soam_addr_r         <= soam_addr_next_r;
        end

    always @(posedge clk_i)
        begin
            soam_r[soam_addr_r] <= soam_next_r;
        end

    assign soam_data_w                 = soam_r[soam_addr_r];

    assign soam_addr_eval_y_incr_w     = eval_x_coord_write_st_w || init_soam_write_st_w;
    assign soam_wr_en_w                = ~eval_counter_r[3];
    assign sp_is_active_w              = y_coord_in_range_w && soam_wr_en_w;

    assign sp_evaluation_in_progress_w = eval_y_coord_write_sn_w || eval_index_write_sn_w ||
                                         eval_x_coord_write_sn_w || eval_attributes_write_sn_w;

    always @(*)
        case (state_next_r)

            IDLE:                                oam_addr_next_r  = 9'h0;

            EVALUATION_TILE_Y_COORDINATE_READ:   oam_addr_next_r  = (eval_y_coord_write_st_w) ?
                                                                    oam_addr_r + 3'b100 :
                                                                    oam_addr_r + eval_x_coord_write_st_w;

            EVALUATION_TILE_INDEX_READ,
            EVALUATION_TILE_ATTRIBUTES_READ,
            EVALUATION_TILE_X_COORDINATE_READ:   oam_addr_next_r  = oam_addr_r + 1'b1;

            default:                             oam_addr_next_r  = oam_addr_r;

        endcase

    always @(*)
        case (state_next_r)

            IDLE, WAITING_FOR_HBLANK:            soam_addr_next_r = 5'h0;

            INIT_SOAM_READ:                      soam_addr_next_r = soam_addr_r + init_soam_write_st_w;

            EVALUATION_TILE_Y_COORDINATE_READ:   soam_addr_next_r = soam_addr_r + soam_addr_eval_y_incr_w;

            EVALUATION_TILE_INDEX_READ,
            EVALUATION_TILE_ATTRIBUTES_READ,
            EVALUATION_TILE_X_COORDINATE_READ:   soam_addr_next_r = soam_addr_r + 1'b1;

            FETCH_TILE_Y_COORDINATE_GET_DATA:    soam_addr_next_r = soam_addr_r + get_pattern_high_data_st_w;

            FETCH_TILE_INDEX_GET_DATA,
            FETCH_TILE_ATTRIBUTES_GET_DATA,
            FETCH_TILE_X_COORDINATE_GET_DATA:    soam_addr_next_r = soam_addr_r + 1'b1;

            default:                             soam_addr_next_r = soam_addr_r;

        endcase

    always @(*)
        case (state_next_r)

            IDLE, INIT_SOAM_WRITE:               soam_next_r      = 8'hFF;

            EVALUATION_TILE_Y_COORDINATE_WRITE:  soam_next_r      = (sp_is_active_w) ? sp_oam_data_i :
                                                                                       soam_r[soam_addr_r];

            EVALUATION_TILE_INDEX_WRITE,
            EVALUATION_TILE_ATTRIBUTES_WRITE,
            EVALUATION_TILE_X_COORDINATE_WRITE:  soam_next_r      = (soam_wr_en_w) ? sp_oam_data_i :
                                                                                     soam_r[soam_addr_r];

            default:                             soam_next_r      = soam_r[soam_addr_r];

        endcase


    // Логика флагов и сигналов управления рендером
    always @(posedge clk_i)
        if (rst_i) begin
            sp0_hit_r        <= 1'b0;
            overflow_flag_r  <= 1'b0;
        end else begin
            sp0_hit_r        <= sp0_hit_next_r;
            overflow_flag_r  <= overflow_flag_next_r;
        end

    always @(posedge clk_i)
        begin
            eval_counter_r   <= eval_counter_next_r;
            fetch_counter_r  <= fetch_counter_next_r;
            fetch_empty_sp_r <= fetch_empty_sp_next_w;
            sp0_is_found_r   <= sp0_is_found_next_r;
            sp0_is_present_r <= sp0_is_present_next_r;
        end

    assign overflow_flag_rst_pos_w  = flags_clear_pos_w;
    assign overflow_flag_set_cond_w = eval_y_coord_write_st_w && y_coord_in_range_w && eval_counter_r[3];

    assign sp0_is_found_rst_pos_w   = (x_pos_i == 9'd256);
    assign sp0_is_found_set_cond_w  = (~|oam_addr_r[7:0]) && eval_y_coord_write_st_w && y_coord_in_range_w;

    assign sp0_is_present_rst_pos_w = (x_pos_i == 9'd255);
    assign sp0_is_present_set_pos_w = (x_pos_i == 9'd256);

    assign sp0_is_frontmost_w       = sp0_is_present_r && (~|frontmost_index_data_r);
    assign sp0_hit_rst_pos_w        = flags_clear_pos_w;
    assign sp0_hit_set_cond_w       = sp0_is_frontmost_w && (|frontmost_pattern_w) && (|bg_pattern_index_i);

    assign fetch_empty_sp_next_w    = (get_y_coord_data_st_w) ? &soam_data_w : fetch_empty_sp_r;

    wire [1:0] overflow_flag_next_case_w = {overflow_flag_rst_pos_w, overflow_flag_set_cond_w};
    always @(*)
        case (overflow_flag_next_case_w) // one hot
            2'b10:   overflow_flag_next_r  = 1'b0;
            2'b01:   overflow_flag_next_r  = 1'b1;
            default: overflow_flag_next_r  = overflow_flag_r;
        endcase

    wire [1:0] sp0_is_found_next_case_w = {sp0_is_found_rst_pos_w, sp0_is_found_set_cond_w};
    always @(*)
        case (sp0_is_found_next_case_w) // one hot
            2'b10:   sp0_is_found_next_r   = 1'b0;
            2'b01:   sp0_is_found_next_r   = 1'b1;
            default: sp0_is_found_next_r   = sp0_is_found_r;
        endcase

    wire [1:0] sp0_is_present_next_case_w = {sp0_is_present_rst_pos_w, sp0_is_present_set_pos_w};
    always @(*)
        case (sp0_is_present_next_case_w) // one hot
            2'b10:   sp0_is_present_next_r = 1'b0;
            2'b01:   sp0_is_present_next_r = sp0_is_found_r;
            default: sp0_is_present_next_r = sp0_is_present_r;
        endcase

    wire [1:0] sp0_hit_next_case_w = {sp0_hit_rst_pos_w, sp0_hit_set_cond_w};
    always @(*)
        case (sp0_hit_next_case_w) // one hot
            2'b10:   sp0_hit_next_r        = 1'b0;
            2'b01:   sp0_hit_next_r        = 1'b1;
            default: sp0_hit_next_r        = sp0_hit_r;
        endcase

    always @(*)
        case (state_next_r)
            IDLE, INIT_SOAM_READ, INIT_SOAM_WRITE: begin
                eval_counter_next_r  = 4'h0;
                fetch_counter_next_r = 3'h0;
            end
            EVALUATION_TILE_Y_COORDINATE_READ: begin
                eval_counter_next_r  = eval_counter_r + eval_x_coord_write_st_w;
                fetch_counter_next_r = fetch_counter_r;
            end
            FETCH_TILE_Y_COORDINATE_GET_DATA: begin
                eval_counter_next_r  = eval_counter_r;
                fetch_counter_next_r = fetch_counter_r + get_pattern_high_data_st_w;
            end
            default: begin
                eval_counter_next_r  = eval_counter_r;
                fetch_counter_next_r = fetch_counter_r;
            end
        endcase


    // Логика считывания данных тайлов из видеопамяти картриджа
    always @(posedge clk_i)
        sp_pattern_table_addr_r <= sp_pattern_table_addr_next_r;

    assign sp_v_flip_w                 = v_flip_w      [fetch_counter_r];
    assign sp_h_flip_w                 = h_flip_w      [fetch_counter_r];
    assign sp_y_coord_w                = y_coord_data_r[fetch_counter_r];
    assign sp_tile_index_w             = index_data_r  [fetch_counter_r];

    assign sp_y_diff_w                 = (y_pos_i - sp_y_coord_w);
    assign sp_bot_half_w               = (sp_v_flip_w   ) ? (sp_y_diff_w < 4'd8) :
                                                            (sp_y_diff_w > 3'd7);
    assign pattern_table_sel_w         = (sp_size_mode_i) ?  sp_tile_index_w[0] : sp_pattern_table_select_i;
    assign sp_tile_w                   = (sp_size_mode_i) ? {sp_tile_index_w[7:1], sp_bot_half_w} : sp_tile_index_w;
    assign y_offset_w                  = (sp_v_flip_w   ) ? (sp_y_coord_w + 3'd7 - y_pos_i) : sp_y_diff_w[2:0];

    assign pattern_low_addr_w          = {1'b0, pattern_table_sel_w, sp_tile_w, 1'b0, y_offset_w};
    assign pattern_high_addr_w         = {1'b0, pattern_table_sel_w, sp_tile_w, 1'b1, y_offset_w};

    assign sp_pattern_table_access_w   = get_pattern_low_data_sn_w || get_pattern_high_data_sn_w;

    assign sp_get_pattern_table_data_w = ppu_render_enabled_i && sp_pattern_table_access_w;

    wire [1:0] pattern_table_addr_next_case_w = {set_pattern_low_addr_sn_w, set_pattern_high_addr_sn_w};
    always @(*)
        case (pattern_table_addr_next_case_w)
            2'b10:   sp_pattern_table_addr_next_r = pattern_low_addr_w;
            2'b01:   sp_pattern_table_addr_next_r = pattern_high_addr_w;
            default: sp_pattern_table_addr_next_r = sp_pattern_table_addr_r;
        endcase


    localparam PDW = 8; // PATTERN_DATA_WIDTH
    generate
        for (genvar f = 0; f < PDW; f = f + 1) begin : pattern_flipper

            assign pattern_table_data_flipped_w [PDW-1-f] = pattern_table_data_i[f];

        end
    endgenerate

    always @(*)
        if      (fetch_empty_sp_r) pattern_data_r = 8'h0;
        else if (sp_h_flip_w     ) pattern_data_r = pattern_table_data_flipped_w;
        else                       pattern_data_r = pattern_table_data_i;


    // Непосредственно рендер переднего плана
    generate
        for (genvar s = 0; s < 8; s = s + 1) begin : sprites

            assign sp_sel_w               [s] = (fetch_counter_r == s) && ppu_render_enabled_i;

            assign get_y_coord_data_w     [s] = get_y_coord_data_st_w      && sp_sel_w[s];
            assign get_index_data_w       [s] = get_index_data_st_w        && sp_sel_w[s];
            assign get_attributes_data_w  [s] = get_attributes_data_st_w   && sp_sel_w[s];
            assign get_x_coord_data_w     [s] = get_x_coord_data_st_w      && sp_sel_w[s];
            assign get_pattern_low_data_w [s] = get_pattern_low_data_sn_w  && sp_sel_w[s];
            assign get_pattern_high_data_w[s] = get_pattern_high_data_sn_w && sp_sel_w[s];

            assign x_coord_updating_w     [s] = sp_is_rendering_w && ( |x_coord_data_r[s]); // x_coord_data_r[s] != 8'd0
            assign shifters_updating_w    [s] = sp_is_rendering_w && (~|x_coord_data_r[s]); // x_coord_data_r[s] == 8'd0

            assign pattern_low_shifted_w  [s] = {pattern_low_shifter_r [s][6:0], 1'b0};
            assign pattern_high_shifted_w [s] = {pattern_high_shifter_r[s][6:0], 1'b0};

            always @(posedge clk_i)
                begin
                    y_coord_data_r        [s] <= y_coord_data_next_w        [s];
                    index_data_r          [s] <= index_data_next_w          [s];
                    attributes_data_r     [s] <= attributes_data_next_w     [s];
                    x_coord_data_r        [s] <= x_coord_data_next_r        [s];
                    pattern_low_shifter_r [s] <= pattern_low_shifter_next_r [s];
                    pattern_high_shifter_r[s] <= pattern_high_shifter_next_r[s];
                end

            assign y_coord_data_next_w   [s] = (get_y_coord_data_w   [s]) ? soam_data_w : y_coord_data_r   [s];
            assign index_data_next_w     [s] = (get_index_data_w     [s]) ? soam_data_w : index_data_r     [s];
            assign attributes_data_next_w[s] = (get_attributes_data_w[s]) ? soam_data_w : attributes_data_r[s];

            wire [1:0] x_coord_data_next_case_w = {get_x_coord_data_w[s], x_coord_updating_w[s]};
            always @(*)
                case (x_coord_data_next_case_w) // one hot
                    2'b10:   x_coord_data_next_r[s]         = soam_data_w;
                    2'b01:   x_coord_data_next_r[s]         = x_coord_data_r[s] - 1'b1;
                    default: x_coord_data_next_r[s]         = x_coord_data_r[s];
                endcase

            wire [1:0] pattern_low_shifter_next_case_w = {get_pattern_low_data_w[s], shifters_updating_w[s]};
            always @(*)
                case (pattern_low_shifter_next_case_w) // one hot
                    2'b10:   pattern_low_shifter_next_r[s]  = pattern_data_r;
                    2'b01:   pattern_low_shifter_next_r[s]  = pattern_low_shifted_w[s];
                    default: pattern_low_shifter_next_r[s]  = pattern_low_shifter_r[s];
                endcase

            wire [1:0] pattern_high_shifter_next_case_w = {get_pattern_high_data_w[s], shifters_updating_w[s]};
            always @(*)
                case (pattern_high_shifter_next_case_w) // one hot
                    2'b10:   pattern_high_shifter_next_r[s] = pattern_data_r;
                    2'b01:   pattern_high_shifter_next_r[s] = pattern_high_shifted_w[s];
                    default: pattern_high_shifter_next_r[s] = pattern_high_shifter_r[s];
                endcase

            assign v_flip_w[s]   = attributes_data_r[s][7];
            assign h_flip_w[s]   = attributes_data_r[s][6];
            assign priority_w[s] = attributes_data_r[s][5];

            always @(*)
                if (sp_is_visible_w) begin
                    pattern_index_data_r[s] = {pattern_high_shifter_r[s][7], pattern_low_shifter_r[s][7]};
                    palette_index_data_r[s] = {attributes_data_r     [s][1], attributes_data_r    [s][0]};
                end else begin
                    pattern_index_data_r[s] = 2'b00;
                    palette_index_data_r[s] = 2'b00;
                end

            assign is_opaque_w[s] = (|pattern_index_data_r[s]) && (~|x_coord_data_r[s]);
            // pattern_index_data_r[s] > 0 && x_coord_data_r[s] == 8'd0

        end
    endgenerate


    integer i;
    localparam ISOW = 8; // IS_OPAQUE_WIDTH
    always @(*) begin
        i = 0;
        while ((i < ISOW) && (~is_opaque_w[i])) i = i + 1;
        frontmost_index_data_r = i;
    end

    assign is_transperent_w        = (frontmost_index_data_r == 4'd8);
    assign frontmost_priority_w    = (is_transperent_w) ? 1'b1 :  priority_w          [frontmost_index_data_r];
    assign frontmost_pixel_index_w = (is_transperent_w) ? 4'h0 : {palette_index_data_r[frontmost_index_data_r],
                                                                  pattern_index_data_r[frontmost_index_data_r]};
    assign frontmost_pattern_w     = frontmost_pixel_index_w[1:0];


    // Выходы
    assign sp_pattern_table_addr_o     = sp_pattern_table_addr_r;
    assign sp_get_pattern_table_data_o = sp_get_pattern_table_data_w;
    assign sp_is_pattern_fetching_o    = sp_is_pattern_fetching_w;

    assign sp_pixel_index_o            = frontmost_pixel_index_w;
    assign sp_priority_o               = frontmost_priority_w;

    assign sp0_hit_o                   = sp0_hit_r;
    assign sp_overflow_flag_o          = overflow_flag_r;

    assign sp_oam_addr_o               = oam_addr_next_r[7:0];
    assign sp_evaluation_in_progress_o = sp_evaluation_in_progress_w;


endmodule
