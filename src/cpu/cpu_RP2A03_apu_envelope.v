
/*
 * Description : RP2A03 audio processor envelope logic implementation module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module cpu_RP2A03_apu_envelope
    (
        input  wire       clk_i,                        // Сигнал тактирования
        input  wire       rst_i,                        // Сигнал сброса

        input  wire       length_counter_load_reg_wr_i, // Сигнал записи в регистр управления длительностью ноты

        input  wire       quarter_frame_i,              // Сигнал синхронизации — флаг четверти фрейма

        input  wire       const_volume_i,               // Сигнал — флаг постоянной громкости ноты
        input  wire       envelope_loop_i,              // Сигнал — флаг зацикливания воспроизведения ноты
        input  wire [3:0] volume_i,                     // Входной уровень громкости
        output wire [3:0] envelope_level_o              // Выхдной (подстроенный) уровень громкости
    );


    reg        start_flag_r;
    reg        start_flag_next_r;
    reg  [3:0] decay_level_r;
    reg  [3:0] decay_level_next_r;
    reg  [3:0] divider_r;
    wire [3:0] divider_next_w;

    wire       divider_is_zero_w;
    wire       divider_reload_w;
    wire       decay_is_nzero_w;
    wire       decay_updating_w;
    wire [3:0] envelope_level_w;


    always @(posedge clk_i)
        if (rst_i) begin
            start_flag_r  <= 1'b0;
        end else begin
            start_flag_r  <= start_flag_next_r;
        end

    always @(posedge clk_i)
        begin
            decay_level_r <= decay_level_next_r;
            divider_r     <= divider_next_w;
        end

    assign divider_is_zero_w = ~|divider_r;
    assign divider_reload_w  = (start_flag_r || divider_is_zero_w) && quarter_frame_i;

    assign decay_is_nzero_w  = |decay_level_r;
    assign decay_updating_w  = (decay_is_nzero_w || envelope_loop_i) && divider_is_zero_w;

    assign envelope_level_w  = (const_volume_i  ) ? volume_i : decay_level_r;

    assign divider_next_w    = (divider_reload_w) ? volume_i : divider_r - quarter_frame_i;

    wire [1:0] start_flag_next_case_w = {length_counter_load_reg_wr_i, quarter_frame_i};
    always @(*)
        casez (start_flag_next_case_w)
            2'b1_?:  start_flag_next_r  = 1'b1;
            2'b0_1:  start_flag_next_r  = 1'b0;
            default: start_flag_next_r  = start_flag_r;
        endcase

    wire [1:0] decay_level_next_case_w = {quarter_frame_i, start_flag_r};
    always @(*)
        case (decay_level_next_case_w)
            2'b11:   decay_level_next_r = 4'hF;
            2'b10:   decay_level_next_r = decay_level_r - decay_updating_w;
            default: decay_level_next_r = decay_level_r;
        endcase


    assign envelope_level_o = envelope_level_w;


endmodule
