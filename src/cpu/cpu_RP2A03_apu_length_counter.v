
/*
 * Description : RP2A03 audio processor length counter logic (note duration controller) implementation module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module cpu_RP2A03_apu_length_counter
    (
        input  wire       clk_i,                        // Сигнал тактирования
        input  wire       rst_i,                        // Сигнал сброса

        input  wire       length_counter_load_reg_wr_i, // Сигнал записи в регистр управления длительностью ноты
        input  wire [7:0] channel_regs_wr_data_i,       // Записываемые данные в регистр управления длительностью ноты

        input  wire       half_frame_i,                 // Сигнал синхронизации — флаг половины фрейма

        input  wire       channel_enabled_i,            // Сигнал — "канал включен"
        input  wire       length_counting_i,            // Сигнал разрешения обновления счётчика длительности
        output wire       length_is_nzero_o             // Сигнал счётчика длительности не равен нулю
    );


    reg  [7:0] length_r;
    reg  [7:0] length_next_r;
    reg  [7:0] length_lut_value_r;
    wire [4:0] length_counter_load_w;

    wire       channel_disabled_w;
    wire       length_is_nzero_w;
    wire       length_updating_w;


    always @(posedge clk_i)
        if   (rst_i) length_r <= 8'h0;
        else         length_r <= length_next_r;

    assign length_counter_load_w = channel_regs_wr_data_i[7:3];

    assign channel_disabled_w    = ~channel_enabled_i;
    assign length_is_nzero_w     = |length_r;
    assign length_updating_w     = length_is_nzero_w && length_counting_i && half_frame_i;

    wire [2:0] length_counter_next_case_w = {channel_disabled_w, length_updating_w, length_counter_load_reg_wr_i};
    always @(*)
        casez (length_counter_next_case_w)
            3'b1_?_?: length_next_r = 8'h0;
            3'b0_1_?: length_next_r = length_r - 1'b1;
            3'b0_0_1: length_next_r = length_lut_value_r;
            default:  length_next_r = length_r;
        endcase

    always @(*)
        case (length_counter_load_w)
            // Linear length values:
            5'h1F: length_lut_value_r = 8'd30;
            5'h1D: length_lut_value_r = 8'd28;
            5'h1B: length_lut_value_r = 8'd26;
            5'h19: length_lut_value_r = 8'd24;
            5'h17: length_lut_value_r = 8'd22;
            5'h15: length_lut_value_r = 8'd20;
            5'h13: length_lut_value_r = 8'd18;
            5'h11: length_lut_value_r = 8'd16;
            5'h0F: length_lut_value_r = 8'd14;
            5'h0D: length_lut_value_r = 8'd12;
            5'h0B: length_lut_value_r = 8'd10;
            5'h09: length_lut_value_r = 8'd8;
            5'h07: length_lut_value_r = 8'd6;
            5'h05: length_lut_value_r = 8'd4;
            5'h03: length_lut_value_r = 8'd2;
            5'h01: length_lut_value_r = 8'd254;
            // Notes with base length 12 (4/4 at 75 bpm):
            5'h1E: length_lut_value_r = 8'd32;  // 96 times 1/3, quarter note triplet
            5'h1C: length_lut_value_r = 8'd16;  // 48 times 1/3, eighth note triplet
            5'h1A: length_lut_value_r = 8'd72;  // 48 times 1 1/2, dotted quarter
            5'h18: length_lut_value_r = 8'd192; // Whole note
            5'h16: length_lut_value_r = 8'd96;  // Half note
            5'h14: length_lut_value_r = 8'd48;  // Quarter note
            5'h12: length_lut_value_r = 8'd24;  // Eighth note
            5'h10: length_lut_value_r = 8'd12;  // Sixteenth note
            /* Notes with base length 10 (4/4 at 90 bpm, with
             * relative durations being the same as above): */
            5'h0E: length_lut_value_r = 8'd26;  // Approx. 80 times 1/3, quarter note triplet
            5'h0C: length_lut_value_r = 8'd14;  // Approx. 40 times 1/3, eighth note triplet
            5'h0A: length_lut_value_r = 8'd60;  // 40 times 1 1/2, dotted quarter
            5'h08: length_lut_value_r = 8'd160; // Whole note
            5'h06: length_lut_value_r = 8'd80;  // Half note
            5'h04: length_lut_value_r = 8'd40;  // Quarter note
            5'h02: length_lut_value_r = 8'd20;  // Eighth note
            5'h00: length_lut_value_r = 8'd10;  // Sixteenth note
    endcase


    assign length_is_nzero_o = length_is_nzero_w;


endmodule
