
/*
 * Description : RP2C02 background render logic implementation module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module ppu_RP2C02_background
    (
        input  wire        clk_i,                       // Сигнал тактирования
        input  wire        rst_i,                       // Сигнал сброса

        input  wire [ 8:0] x_pos_i,                     // Горизонтальная координата рендеринга
        input  wire [ 8:0] y_pos_i,                     // Вертикальная координата рендеринга
        input  wire        end_of_line_i,               // Флаг завершения строки рендеринга

        input  wire [ 7:0] pattern_table_data_i,        // Данные из видеопамяти на картридже (тайлы)
        output wire [13:0] bg_pattern_table_addr_o,     // Адрес для видеопамяти на картридже
        output wire        bg_get_pattern_table_data_o, // Сигнал считывания данных из видеопамяти на картридже
        output wire        bg_is_pattern_fetching_o,    // Сигнал для арбитража доступа к видеопамяти на картридже

        input  wire [ 7:0] nametable_data_i,            // Данные из оперативной видеопамяти
        output wire [13:0] bg_nametable_addr_o,         // Адрес для оперативной видеопамяти
        output wire        bg_get_nametable_data_o,     // Сигнал считывания данных из оперативной видеопамяти

        input  wire        ppu_render_enabled_i,        // Общий рендеринг включен
        input  wire        ppu_rendering_lines_i,       // Координаты рендеринга внутри видимой области
        input  wire        ppu_is_rendering_i,          // Рендеринг в процессе (ppu_render_enabled_i && ppu_rendering_lines_i)

        input  wire        bg_render_enabled_i,         // Рендеринг заднего фона включен
        input  wire [ 3:0] bg_x_pos_drawing_start_i,    // Горизонтальная координата начала рендеринга заднего фона
        input  wire        bg_pattern_table_select_i,   // Выбор банка видеопамяти на картридже с тайлами для рендеринга

        input  wire [ 2:0] fine_x_scroll_i,             // Сигнал-указатель на текущий отрисовываемый пиксель в памяти тайлов
        input  wire [ 2:0] fine_y_scroll_i,             // Сигнал-указатель на текущий отрисовываемый пиксель в памяти тайлов
        input  wire [ 4:0] coarse_x_scroll_i,           // Сигнал-указатель на текущую отрисовываемую ячейку в ОЗУ видео
        input  wire [ 4:0] coarse_y_scroll_i,           // Сигнал-указатель на текущую отрисовываемую ячейку в ОЗУ видео
        input  wire        hrz_nametable_i,             // Сигнал выбора активной области оперативной видеопамяти
        input  wire        vrt_nametable_i,             // Сигнал выбора активной области оперативной видеопамяти

        output wire [ 3:0] bg_pixel_index_o             // Выходной пиксель логики рендера заднего фона
    );


    // Состояния конченого автомата
    localparam [3:0] IDLE                             = 0,
                     FETCH_TILE_INDEX_SET_ADDR        = 1,
                     FETCH_TILE_INDEX_GET_DATA        = 2,
                     FETCH_TILE_ATTRIBUTES_SET_ADDR   = 3,
                     FETCH_TILE_ATTRIBUTES_GET_DATA   = 4,
                     FETCH_TILE_PATTERN_LOW_SET_ADDR  = 5,
                     FETCH_TILE_PATTERN_LOW_GET_DATA  = 6,
                     FETCH_TILE_PATTERN_HIGH_SET_ADDR = 7,
                     FETCH_TILE_PATTERN_HIGH_GET_DATA = 8,
                     UNUSED_NT                        = 9;


    // Конечный автомат
    reg  [ 3:0] state_r;
    reg  [ 3:0] state_next_r;

    wire        set_index_addr_sn_w;
    wire        set_attributes_addr_sn_w;
    wire        set_pattern_low_addr_sn_w;
    wire        set_pattern_high_addr_sn_w;
    wire        get_index_data_sn_w;
    wire        get_attributes_data_sn_w;
    wire        get_pattern_low_data_sn_w;
    wire        get_pattern_high_data_sn_w;

    // Доступ к данным и памяти
    reg  [ 7:0] index_data_r;
    wire [ 7:0] index_data_next_w;
    reg  [ 1:0] attributes_data_r;
    reg  [ 1:0] attributes_data_next_r;
    reg  [ 7:0] pattern_low_data_r;
    wire [ 7:0] pattern_low_data_next_w;
    reg  [ 7:0] pattern_high_data_r;
    wire [ 7:0] pattern_high_data_next_w;
    wire        attributes_low_bit_w;
    wire        attributes_high_bit_w;

    wire [13:0] index_addr_w;
    wire [13:0] attributes_addr_w;
    wire [13:0] pattern_low_addr_w;
    wire [13:0] pattern_high_addr_w;

    reg  [13:0] bg_nametable_addr_r;
    reg  [13:0] bg_nametable_addr_next_r;
    reg  [13:0] bg_pattern_table_addr_r;
    reg  [13:0] bg_pattern_table_addr_next_r;
    wire        bg_nametable_access_w;
    wire        bg_pattern_table_access_w;
    wire        bg_get_pattern_table_data_w;
    wire        bg_get_nametable_data_w;

    // Рендер
    wire        shifters_reloading_w;
    wire        shifters_updating_w;

    reg  [15:0] pattern_low_shifter_r;
    reg  [15:0] pattern_low_shifter_next_r;
    wire [15:0] pattern_low_shifted_w;
    wire [15:0] pattern_low_reloaded_w;
    reg  [15:0] pattern_high_shifter_r;
    reg  [15:0] pattern_high_shifter_next_r;
    wire [15:0] pattern_high_shifted_w;
    wire [15:0] pattern_high_reloaded_w;
    reg  [15:0] palette_low_shifter_r;
    reg  [15:0] palette_low_shifter_next_r;
    wire [15:0] palette_low_shifted_w;
    wire [15:0] palette_low_reloaded_w;
    reg  [15:0] palette_high_shifter_r;
    reg  [15:0] palette_high_shifter_next_r;
    wire [15:0] palette_high_shifted_w;
    wire [15:0] palette_high_reloaded_w;

    wire        bg_visible_lines_w;
    wire        bg_visible_dots_w;
    wire        bg_rendering_dots_w;
    wire        bg_pattern_fetching_dots_w;
    wire        bg_is_rendering_w;
    wire        bg_is_visible_w;
    wire        bg_is_pattern_fetching_w;
    wire [ 3:0] fine_x_scroll_effective_w;

    wire        bg_tile_fetch_pos_w;
    wire        fg_tile_fetch_pos_w;
    wire        unused_nt_fetch_pos_w;

    // Выходной пиксель
    reg  [ 1:0] pattern_index_r;
    reg  [ 1:0] palette_index_r;
    wire [ 3:0] bg_pixel_index_w;


    assign bg_visible_lines_w         =  (y_pos_i < 9'd240);
    assign bg_visible_dots_w          =  (x_pos_i < 9'd257) && (x_pos_i > bg_x_pos_drawing_start_i);
    assign bg_rendering_dots_w        = ((x_pos_i < 9'd257) && (x_pos_i > 9'd0  )) ||
                                        ((x_pos_i < 9'd337) && (x_pos_i > 9'd320));
    assign bg_pattern_fetching_dots_w =  (x_pos_i < 9'd257) || (x_pos_i > 9'd320);

    assign bg_is_visible_w            = bg_visible_lines_w && bg_visible_dots_w && bg_render_enabled_i;
    assign bg_is_rendering_w          = ppu_is_rendering_i && bg_rendering_dots_w;
    assign bg_is_pattern_fetching_w   = ppu_is_rendering_i && bg_pattern_fetching_dots_w;


    // Логика конечного автомата
    always @(posedge clk_i)
        if   (rst_i) state_r <= IDLE;
        else         state_r <= state_next_r;

    assign bg_tile_fetch_pos_w   = ((x_pos_i == 9'd320) || (~|x_pos_i)) && ppu_rendering_lines_i;
    assign fg_tile_fetch_pos_w   =  (x_pos_i == 9'd256);
    assign unused_nt_fetch_pos_w =  (x_pos_i == 9'd336);

    wire [1:0] state_next_st_8_case_w = {fg_tile_fetch_pos_w, unused_nt_fetch_pos_w};
    always @(*)
        case (state_r)

            IDLE:                             state_next_r = (bg_tile_fetch_pos_w) ? FETCH_TILE_INDEX_SET_ADDR : IDLE;

            FETCH_TILE_INDEX_SET_ADDR:        state_next_r = FETCH_TILE_INDEX_GET_DATA;

            FETCH_TILE_INDEX_GET_DATA:        state_next_r = FETCH_TILE_ATTRIBUTES_SET_ADDR;

            FETCH_TILE_ATTRIBUTES_SET_ADDR:   state_next_r = FETCH_TILE_ATTRIBUTES_GET_DATA;

            FETCH_TILE_ATTRIBUTES_GET_DATA:   state_next_r = FETCH_TILE_PATTERN_LOW_SET_ADDR;

            FETCH_TILE_PATTERN_LOW_SET_ADDR:  state_next_r = FETCH_TILE_PATTERN_LOW_GET_DATA;

            FETCH_TILE_PATTERN_LOW_GET_DATA:  state_next_r = FETCH_TILE_PATTERN_HIGH_SET_ADDR;

            FETCH_TILE_PATTERN_HIGH_SET_ADDR: state_next_r = FETCH_TILE_PATTERN_HIGH_GET_DATA;

            FETCH_TILE_PATTERN_HIGH_GET_DATA:
                case (state_next_st_8_case_w) // one hot
                    2'b10:                    state_next_r = IDLE;
                    2'b01:                    state_next_r = UNUSED_NT;
                    default:                  state_next_r = FETCH_TILE_INDEX_SET_ADDR;
                endcase

            UNUSED_NT:                        state_next_r = (end_of_line_i) ? IDLE : UNUSED_NT;

            default:                          state_next_r = state_r;

        endcase


    assign set_index_addr_sn_w        = (state_next_r == FETCH_TILE_INDEX_SET_ADDR);
    assign set_attributes_addr_sn_w   = (state_next_r == FETCH_TILE_ATTRIBUTES_SET_ADDR);
    assign set_pattern_low_addr_sn_w  = (state_next_r == FETCH_TILE_PATTERN_LOW_SET_ADDR);
    assign set_pattern_high_addr_sn_w = (state_next_r == FETCH_TILE_PATTERN_HIGH_SET_ADDR);

    assign get_index_data_sn_w        = (state_next_r == FETCH_TILE_INDEX_GET_DATA);
    assign get_attributes_data_sn_w   = (state_next_r == FETCH_TILE_ATTRIBUTES_GET_DATA);
    assign get_pattern_low_data_sn_w  = (state_next_r == FETCH_TILE_PATTERN_LOW_GET_DATA);
    assign get_pattern_high_data_sn_w = (state_next_r == FETCH_TILE_PATTERN_HIGH_GET_DATA);


    // Логика считывания данных из оперативной видеопамяти и памяти тайлов
    always @(posedge clk_i)
        begin
            bg_nametable_addr_r     <= bg_nametable_addr_next_r;
            bg_pattern_table_addr_r <= bg_pattern_table_addr_next_r;
        end

    assign index_addr_w                = {2'b10, vrt_nametable_i, hrz_nametable_i, coarse_y_scroll_i, coarse_x_scroll_i};
    assign attributes_addr_w           = {2'b10, vrt_nametable_i, hrz_nametable_i, 4'b1111,
                                          coarse_y_scroll_i[4:2], coarse_x_scroll_i[4:2]};
    assign pattern_low_addr_w          = {1'b0, bg_pattern_table_select_i, index_data_r, 1'b0, fine_y_scroll_i};
    assign pattern_high_addr_w         = {1'b0, bg_pattern_table_select_i, index_data_r, 1'b1, fine_y_scroll_i};

    assign bg_nametable_access_w       = get_index_data_sn_w       || get_attributes_data_sn_w;
    assign bg_pattern_table_access_w   = get_pattern_low_data_sn_w || get_pattern_high_data_sn_w;

    assign bg_get_nametable_data_w     = ppu_render_enabled_i && bg_nametable_access_w;
    assign bg_get_pattern_table_data_w = ppu_render_enabled_i && bg_pattern_table_access_w;

    wire [1:0] nametable_addr_next_case_w = {set_index_addr_sn_w, set_attributes_addr_sn_w};
    always @(*)
        case (nametable_addr_next_case_w) // one hot
            2'b10:   bg_nametable_addr_next_r     = index_addr_w;
            2'b01:   bg_nametable_addr_next_r     = attributes_addr_w;
            default: bg_nametable_addr_next_r     = bg_nametable_addr_r;
        endcase

    wire [1:0] pattern_table_addr_next_case_w = {set_pattern_low_addr_sn_w, set_pattern_high_addr_sn_w};
    always @(*)
        case (pattern_table_addr_next_case_w) // one hot
            2'b10:   bg_pattern_table_addr_next_r = pattern_low_addr_w;
            2'b01:   bg_pattern_table_addr_next_r = pattern_high_addr_w;
            default: bg_pattern_table_addr_next_r = bg_pattern_table_addr_r;
        endcase


    always @(posedge clk_i)
        begin
            index_data_r        <= index_data_next_w;
            attributes_data_r   <= attributes_data_next_r;
            pattern_low_data_r  <= pattern_low_data_next_w;
            pattern_high_data_r <= pattern_high_data_next_w;
        end

    assign attributes_low_bit_w     = attributes_data_r[0];
    assign attributes_high_bit_w    = attributes_data_r[1];

    assign index_data_next_w        = (get_index_data_sn_w       ) ? nametable_data_i     : index_data_r;
    assign pattern_low_data_next_w  = (get_pattern_low_data_sn_w ) ? pattern_table_data_i : pattern_low_data_r;
    assign pattern_high_data_next_w = (get_pattern_high_data_sn_w) ? pattern_table_data_i : pattern_high_data_r;

    wire [2:0] attributes_data_next_case_w = {get_attributes_data_sn_w, coarse_y_scroll_i[1], coarse_x_scroll_i[1]};
    always @(*)
        case (attributes_data_next_case_w)
                3'b1_00: attributes_data_next_r = nametable_data_i[1:0];
                3'b1_01: attributes_data_next_r = nametable_data_i[3:2];
                3'b1_10: attributes_data_next_r = nametable_data_i[5:4];
                3'b1_11: attributes_data_next_r = nametable_data_i[7:6];
                default: attributes_data_next_r = attributes_data_r;
        endcase


    // Рендер заднего фона
    always @(posedge clk_i)
        begin
            pattern_low_shifter_r  <= pattern_low_shifter_next_r;
            pattern_high_shifter_r <= pattern_high_shifter_next_r;
            palette_low_shifter_r  <= palette_low_shifter_next_r;
            palette_high_shifter_r <= palette_high_shifter_next_r;
        end

    assign shifters_updating_w     = bg_is_rendering_w;
    assign shifters_reloading_w    = bg_is_rendering_w && (|x_pos_i[8:3]) && (~|x_pos_i[2:0]);

    assign pattern_low_shifted_w   = {pattern_low_shifter_r [14:0], 1'b0};
    assign pattern_high_shifted_w  = {pattern_high_shifter_r[14:0], 1'b0};
    assign palette_low_shifted_w   = {palette_low_shifter_r [14:0], 1'b0};
    assign palette_high_shifted_w  = {palette_high_shifter_r[14:0], 1'b0};

    assign pattern_low_reloaded_w  = {pattern_low_shifted_w [15:8], pattern_low_data_r};
    assign pattern_high_reloaded_w = {pattern_high_shifted_w[15:8], pattern_high_data_r};
    assign palette_low_reloaded_w  = {palette_low_shifted_w [15:8], {8{attributes_low_bit_w}}};
    assign palette_high_reloaded_w = {palette_high_shifted_w[15:8], {8{attributes_high_bit_w}}};

    always @(*)
        if (shifters_reloading_w) begin
            pattern_low_shifter_next_r  = pattern_low_reloaded_w;
            pattern_high_shifter_next_r = pattern_high_reloaded_w;
            palette_low_shifter_next_r  = palette_low_reloaded_w;
            palette_high_shifter_next_r = palette_high_reloaded_w;
        end else if (shifters_updating_w) begin
            pattern_low_shifter_next_r  = pattern_low_shifted_w;
            pattern_high_shifter_next_r = pattern_high_shifted_w;
            palette_low_shifter_next_r  = palette_low_shifted_w;
            palette_high_shifter_next_r = palette_high_shifted_w;
        end else begin
            pattern_low_shifter_next_r  = pattern_low_shifter_r;
            pattern_high_shifter_next_r = pattern_high_shifter_r;
            palette_low_shifter_next_r  = palette_low_shifter_r;
            palette_high_shifter_next_r = palette_high_shifter_r;
        end


    assign fine_x_scroll_effective_w = (4'hF - fine_x_scroll_i);
    assign bg_pixel_index_w          = {palette_index_r, pattern_index_r};

    always @(*)
        if (bg_is_visible_w) begin
            pattern_index_r = {pattern_high_shifter_r[fine_x_scroll_effective_w],
                               pattern_low_shifter_r [fine_x_scroll_effective_w]};
            palette_index_r = {palette_high_shifter_r[fine_x_scroll_effective_w],
                               palette_low_shifter_r [fine_x_scroll_effective_w]};
        end else begin
            pattern_index_r = 2'b00;
            palette_index_r = 2'b00;
        end


    // Выходы
    assign bg_pattern_table_addr_o     = bg_pattern_table_addr_r;
    assign bg_get_pattern_table_data_o = bg_get_pattern_table_data_w;
    assign bg_is_pattern_fetching_o    = bg_is_pattern_fetching_w;

    assign bg_nametable_addr_o         = bg_nametable_addr_r;
    assign bg_get_nametable_data_o     = bg_get_nametable_data_w;

    assign bg_pixel_index_o            = bg_pixel_index_w;


endmodule
