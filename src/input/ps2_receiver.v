
/*
 * Description : PS/2 receiver module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 *
 * NES gamepad "A"      — keyboard "Q"
 * NES gamepad "B"      — keyboard "W"
 * NES gamepad "SELECT" — keyboard "SPACE"
 * NES gamepad "START"  — keyboard "ENTER"
 * NES gamepad "UP"     — keyboard "UP ARROW"    or "8 NUMPAD"
 * NES gamepad "DOWN"   — keyboard "DOWN ARROW"  or "2 NUMPAD"
 * NES gamepad "LEFT"   — keyboard "LEFT ARROW"  or "4 NUMPAD"
 * NES gamepad "RIGHT"  — keyboard "RIGHT ARROW" or "6 NUMPAD"
 */


module ps2_receiver
    (
        input  wire       clk_i,          // Сигнал тактирования
        input  wire       rst_i,          // Сигнал сброса

        input  wire       ps2_clk_i,      // Сигнал PS/2 интерфейса — тактирование
        input  wire       ps2_data_i,     // Сигнал PS/2 интерфейса — данные

        input  wire       buffer_ready_i, // Сигнал готовности к приёму выходных данных
        output wire [7:0] data_o,         // Выходные данные
        output wire       data_valid_o    // Сигнал валидности выходных данных
    );


    // Make и break коды клавиш в интерфейсе PS/2
    localparam [23:0] Q_MAKE          = 24'h00_00_15,
                      Q_BREAK         = 24'h00_F0_15,
                      W_MAKE          = 24'h00_00_1D,
                      W_BREAK         = 24'h00_F0_1D,
                      SPACE_MAKE      = 24'h00_00_29,
                      SPACE_BREAK     = 24'h00_F0_29,
                      ENTER_MAKE      = 24'h00_00_5A,
                      ENTER_BREAK     = 24'h00_F0_5A,
                      U_ARROW_MAKE    = 24'h00_E0_75,
                      U_ARROW_BREAK   = 24'hE0_F0_75,
                      D_ARROW_MAKE    = 24'h00_E0_72,
                      D_ARROW_BREAK   = 24'hE0_F0_72,
                      L_ARROW_MAKE    = 24'h00_E0_6B,
                      L_ARROW_BREAK   = 24'hE0_F0_6B,
                      R_ARROW_MAKE    = 24'h00_E0_74,
                      R_ARROW_BREAK   = 24'hE0_F0_74,
                      U8_NUMPAD_MAKE  = 24'h00_00_75,
                      U8_NUMPAD_BREAK = 24'h00_F0_75,
                      D2_NUMPAD_MAKE  = 24'h00_00_72,
                      D2_NUMPAD_BREAK = 24'h00_F0_72,
                      L4_NUMPAD_MAKE  = 24'h00_00_6B,
                      L4_NUMPAD_BREAK = 24'h00_F0_6B,
                      R6_NUMPAD_MAKE  = 24'h00_00_74,
                      R6_NUMPAD_BREAK = 24'h00_F0_74;


    // Порядковый номер кнопки в выходном байте
    localparam A_BUTTON_POS      = 0,
               B_BUTTON_POS      = 1,
               SELECT_BUTTON_POS = 2,
               START_BUTTON_POS  = 3,
               UP_BUTTON_POS     = 4,
               DOWN_BUTTON_POS   = 5,
               LEFT_BUTTON_POS   = 6,
               RIGHT_BUTTON_POS  = 7;


    // Сигналы интерфейса
    reg         ps2_clk_r;
    reg         ps2_clk_prev_r;
    reg         ps2_data_r;
    wire        clk_negedge_w;

    // Приём данных по интерфейсу PS/2
    reg  [ 3:0] edge_counter_r;
    reg  [ 3:0] edge_counter_next_r;
    reg  [ 7:0] received_data_r;
    wire [ 7:0] received_data_next_w;
    wire        stop_negedge_w;
    wire        data_negedges_w;
    wire        byte_received_w;
    wire        receiving_data_w;

    reg  [23:0] shifter_r;
    reg  [23:0] shifter_next_r;
    wire [23:0] sequence_w;
    wire        no_ext_key_code_w;
    wire        sequence_completed_w;

    // Сигналы декодирования принятых кодов
    reg  [ 7:0] keys_new_data_r;
    reg  [ 7:0] keys_new_data_next_r;
    reg         keys_new_data_valid_r;
    reg  [ 7:0] keys_out_data_r;
    wire [ 7:0] keys_out_data_next_w;
    reg         keys_out_data_valid_r;
    reg         keys_out_data_valid_next_r;

    wire        up_is_pressed_w;
    wire        down_is_pressed_w;
    wire        left_is_pressed_w;
    wire        right_is_pressed_w;
    wire        up_new_val_w;
    wire        down_new_val_w;
    wire        left_new_val_w;
    wire        right_new_val_w;
    wire [ 3:0] direction_new_vals_w;
    wire [ 7:0] keys_new_vals_w;


    // Приём скан-кодов клавиш по интерфейсу PS/2
    always @(posedge clk_i)
        if (rst_i) begin
            ps2_clk_prev_r  <= 1'b1;
            ps2_clk_r       <= 1'b1;
            ps2_data_r      <= 1'b1;
            edge_counter_r  <= 4'h0;
            shifter_r       <= 24'h0;
        end else begin
            ps2_clk_prev_r  <= ps2_clk_r;
            ps2_clk_r       <= ps2_clk_i;
            ps2_data_r      <= ps2_data_i;
            edge_counter_r  <= edge_counter_next_r;
            shifter_r       <= shifter_next_r;
        end

    always @(posedge clk_i)
        begin
            received_data_r <= received_data_next_w;
        end

    assign clk_negedge_w        = ~ps2_clk_r & ps2_clk_prev_r;

    assign stop_negedge_w       = (edge_counter_r == 4'd10);
    assign data_negedges_w      = (edge_counter_r >  4'd0 ) && (edge_counter_r < 4'd9);

    assign byte_received_w      = clk_negedge_w && stop_negedge_w;
    assign receiving_data_w     = clk_negedge_w && data_negedges_w;

    assign no_ext_key_code_w    = ~&received_data_r[7:5];

    assign sequence_completed_w = byte_received_w && no_ext_key_code_w;
    assign sequence_w           = {shifter_r[15:0], received_data_r};

    assign received_data_next_w = (receiving_data_w) ? {ps2_data_r, received_data_r[7:1]} : received_data_r;

    wire [1:0] edge_counter_next_case_w = {clk_negedge_w, stop_negedge_w};
    always @(*)
        case (edge_counter_next_case_w)
            2'b11:   edge_counter_next_r = 4'h0;
            2'b10:   edge_counter_next_r = edge_counter_r + 1'b1;
            default: edge_counter_next_r = edge_counter_r;
        endcase

    wire [1:0] shifter_next_case_w = {byte_received_w, no_ext_key_code_w};
    always @(*)
        case (shifter_next_case_w)
            2'b11:   shifter_next_r      = 24'h0;
            2'b10:   shifter_next_r      = sequence_w;
            default: shifter_next_r      = shifter_r;
        endcase


    // Декодирование скан-кодов и формирование выходного байта
    always @(posedge clk_i)
        if (rst_i) begin
            keys_new_data_valid_r <= 1'b0;
            keys_out_data_valid_r <= 1'b0;
            keys_new_data_r       <= 8'b0;
        end else begin
            keys_new_data_valid_r <= sequence_completed_w;
            keys_out_data_valid_r <= keys_out_data_valid_next_r;
            keys_new_data_r       <= keys_new_data_next_r;
        end

    always @(posedge clk_i)
        begin
            keys_out_data_r       <= keys_out_data_next_w;
        end

    assign up_is_pressed_w      = keys_new_data_r[UP_BUTTON_POS   ];
    assign down_is_pressed_w    = keys_new_data_r[DOWN_BUTTON_POS ];
    assign left_is_pressed_w    = keys_new_data_r[LEFT_BUTTON_POS ];
    assign right_is_pressed_w   = keys_new_data_r[RIGHT_BUTTON_POS];

    assign up_new_val_w         = keys_new_data_r[UP_BUTTON_POS   ] && ~down_is_pressed_w;
    assign down_new_val_w       = keys_new_data_r[DOWN_BUTTON_POS ] && ~up_is_pressed_w;
    assign left_new_val_w       = keys_new_data_r[LEFT_BUTTON_POS ] && ~right_is_pressed_w;
    assign right_new_val_w      = keys_new_data_r[RIGHT_BUTTON_POS] && ~left_is_pressed_w;

    assign direction_new_vals_w = {right_new_val_w, left_new_val_w, down_new_val_w, up_new_val_w};
    assign keys_new_vals_w      = {direction_new_vals_w, keys_new_data_r[3:0]};

    assign keys_out_data_next_w = (keys_new_data_valid_r) ? keys_new_vals_w : keys_out_data_r;

    wire [1:0] keys_out_data_valid_next_case_w = {keys_new_data_valid_r, buffer_ready_i};
    always @(*)
        casez (keys_out_data_valid_next_case_w)
            2'b1_?:  keys_out_data_valid_next_r = 1'b1;
            2'b0_1:  keys_out_data_valid_next_r = 1'b0;
            default: keys_out_data_valid_next_r = keys_out_data_valid_r;
        endcase

    wire [24:0] keys_data_next_case_w = {sequence_completed_w, sequence_w};
    always @(*)
        case (keys_data_next_case_w)

            {1'b1, Q_MAKE         }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, A_BUTTON_POS);
            {1'b1, Q_BREAK        }: keys_new_data_next_r = __reset_bit__(keys_new_data_r, A_BUTTON_POS);

            {1'b1, W_MAKE         }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, B_BUTTON_POS);
            {1'b1, W_BREAK        }: keys_new_data_next_r = __reset_bit__(keys_new_data_r, B_BUTTON_POS);

            {1'b1, SPACE_MAKE     }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, SELECT_BUTTON_POS);
            {1'b1, SPACE_BREAK    }: keys_new_data_next_r = __reset_bit__(keys_new_data_r, SELECT_BUTTON_POS);

            {1'b1, ENTER_MAKE     }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, START_BUTTON_POS);
            {1'b1, ENTER_BREAK    }: keys_new_data_next_r = __reset_bit__(keys_new_data_r, START_BUTTON_POS);

            {1'b1, U_ARROW_MAKE   }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, UP_BUTTON_POS);
            {1'b1, U_ARROW_BREAK  }: keys_new_data_next_r = __reset_bit__(keys_new_data_r, UP_BUTTON_POS);

            {1'b1, D_ARROW_MAKE   }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, DOWN_BUTTON_POS);
            {1'b1, D_ARROW_BREAK  }: keys_new_data_next_r = __reset_bit__(keys_new_data_r, DOWN_BUTTON_POS);

            {1'b1, L_ARROW_MAKE   }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, LEFT_BUTTON_POS);
            {1'b1, L_ARROW_BREAK  }: keys_new_data_next_r = __reset_bit__(keys_new_data_r, LEFT_BUTTON_POS);

            {1'b1, R_ARROW_MAKE   }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, RIGHT_BUTTON_POS);
            {1'b1, R_ARROW_BREAK  }: keys_new_data_next_r = __reset_bit__(keys_new_data_r, RIGHT_BUTTON_POS);

            {1'b1, U8_NUMPAD_MAKE }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, UP_BUTTON_POS);
            {1'b1, U8_NUMPAD_BREAK}: keys_new_data_next_r = __reset_bit__(keys_new_data_r, UP_BUTTON_POS);

            {1'b1, D2_NUMPAD_MAKE }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, DOWN_BUTTON_POS);
            {1'b1, D2_NUMPAD_BREAK}: keys_new_data_next_r = __reset_bit__(keys_new_data_r, DOWN_BUTTON_POS);

            {1'b1, L4_NUMPAD_MAKE }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, LEFT_BUTTON_POS);
            {1'b1, L4_NUMPAD_BREAK}: keys_new_data_next_r = __reset_bit__(keys_new_data_r, LEFT_BUTTON_POS);

            {1'b1, R6_NUMPAD_MAKE }: keys_new_data_next_r = __set_bit__  (keys_new_data_r, RIGHT_BUTTON_POS);
            {1'b1, R6_NUMPAD_BREAK}: keys_new_data_next_r = __reset_bit__(keys_new_data_r, RIGHT_BUTTON_POS);

            default:                 keys_new_data_next_r = keys_new_data_r;

        endcase


    // Выходы
    assign data_o       = keys_out_data_r;
    assign data_valid_o = keys_out_data_valid_r;


    // Функции для установки и сброса соответствующего заданной позиции бита в "слове"
    localparam WD = 8;
    function [WD-1:0] __set_bit__(input [WD-1:0] word, input integer bit_pos);
        begin

            __set_bit__   = word |  (1 << bit_pos);

        end
    endfunction

    function [WD-1:0] __reset_bit__(input [WD-1:0] word, input integer bit_pos);
        begin

            __reset_bit__ = word & ~(1 << bit_pos);

        end
    endfunction


endmodule
