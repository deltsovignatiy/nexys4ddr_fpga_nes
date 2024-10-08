
/*
 * Description : RP2A03 audio processor triangle channel implementation module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module cpu_RP2A03_apu_triangle_channel
    (
        input  wire       clk_i,                  // Сигнал тактирования
        input  wire       rst_i,                  // Сигнал сброса

        input  wire       channel_regs_wr_i,      // Сигнал записи данных в регистры канала
        input  wire [1:0] channel_regs_addr_i,    // Адрес регистра для записи
        input  wire [7:0] channel_regs_wr_data_i, // Записываемые данные в регистры канала

        input  wire       half_frame_i,           // Сигнал синхронизации - флаг половины фрейма
        input  wire       quarter_frame_i,        // Сигнал синхронизации - флаг четверти фрейма

        input  wire       channel_enabled_i,      // Сигнал - "канал включен"
        output wire       channel_is_active_o,    // Сигнал - "канал активен"
        output wire [5:0] channel_output_o        // Выход канала
    );


    // Адреса регистров канала
    localparam [ 1:0] LIN_CNTR_LD_REG_ADDR        = 2'h0,
                      TIMERL_REG_ADDR             = 2'h2,
                      LEN_CNTR_LD_TIMERH_REG_ADDR = 2'h3;


    // Границы воспроизводимых значений таймера, определяющего частоту ноты
    localparam [10:0] TIMER_VALUE_THRESHOLD_LOW  = 11'h2,
                      TIMER_VALUE_THRESHOLD_HIGH = 11'h7FD,
                      TVTL                       = TIMER_VALUE_THRESHOLD_LOW,
                      TVTH                       = TIMER_VALUE_THRESHOLD_HIGH;


    // Регистры канала
    wire        lin_cntr_ld_reg_wr_w;
    wire        timerl_reg_wr_w;
    wire        len_cntr_ld_timerh_reg_wr_w;

    // Сигналы управления каналом и генерации выхода
    reg  [ 4:0] sequencer_r;
    wire [ 4:0] sequencer_next_w;
    reg  [10:0] timer_r;
    wire [10:0] timer_next_w;
    reg  [10:0] timer_value_r;
    reg  [10:0] timer_value_next_r;
    reg  [ 7:0] linear_r;
    wire [ 7:0] linear_next_w;
    reg  [ 7:0] linear_value_r;
    wire [ 7:0] linear_value_next_w;
    reg         linear_control_r;
    wire        linear_control_next_w;
    reg         linear_flag_r;
    reg         linear_flag_next_r;
    reg  [ 5:0] output_r;
    wire [ 5:0] output_next_w;

    reg  [ 5:0] sequencer_output_r;
    wire        length_counting_w;
    wire        timer_is_zero_w;
    wire        timer_pulse_w;
    wire        linear_is_nzero_w;
    wire        length_is_nzero_w;
    wire        linear_reload_w;
    wire        linear_update_w;
    wire        output_enabled_w;
    wire [ 5:0] output_mask_w;
    wire        sequencer_update_w;


    // Декодирование доступа к регистрам
    assign lin_cntr_ld_reg_wr_w        = channel_regs_wr_i && (channel_regs_addr_i == LIN_CNTR_LD_REG_ADDR);
    assign timerl_reg_wr_w             = channel_regs_wr_i && (channel_regs_addr_i == TIMERL_REG_ADDR);
    assign len_cntr_ld_timerh_reg_wr_w = channel_regs_wr_i && (channel_regs_addr_i == LEN_CNTR_LD_TIMERH_REG_ADDR);


    // Генерация выходного значения
    always @(posedge clk_i)
        if (rst_i) begin
            timer_value_r    <= 11'h0;
            timer_r          <= 11'h0;
            sequencer_r      <= 5'h0;
            linear_r         <= 7'h0;
            linear_value_r   <= 7'h0;
            linear_control_r <= 1'b0;
            linear_flag_r    <= 1'b0;
        end else begin
            timer_value_r    <= timer_value_next_r;
            timer_r          <= timer_next_w;
            sequencer_r      <= sequencer_next_w;
            linear_r         <= linear_next_w;
            linear_value_r   <= linear_value_next_w;
            linear_control_r <= linear_control_next_w;
            linear_flag_r    <= linear_flag_next_r;
        end

    always @(posedge clk_i)
        begin
            output_r         <= output_next_w;
        end

    assign linear_value_next_w   = (lin_cntr_ld_reg_wr_w) ? channel_regs_wr_data_i[6:0] : linear_value_r;
    assign linear_control_next_w = (lin_cntr_ld_reg_wr_w) ? channel_regs_wr_data_i[7]   : linear_control_r;

    assign length_counting_w     = ~linear_control_r;

    assign linear_is_nzero_w     = |linear_r;

    assign timer_is_zero_w       = ~|timer_r;
    assign timer_pulse_w         = timer_is_zero_w;

    assign sequencer_update_w    = timer_pulse_w && linear_is_nzero_w && length_is_nzero_w;

    assign linear_reload_w       = quarter_frame_i && linear_flag_r;
    assign linear_update_w       = quarter_frame_i && linear_is_nzero_w;

    assign timer_next_w          = (timer_pulse_w     ) ? timer_value_r      : timer_r - 1'b1;
    assign linear_next_w         = (linear_reload_w   ) ? linear_value_r     : linear_r - linear_update_w;
    assign sequencer_next_w      = sequencer_r - sequencer_update_w;

    assign output_enabled_w      = (timer_value_r > TVTL) && (timer_value_r < TVTH);
    assign output_mask_w         = {6{output_enabled_w}};

    assign output_next_w         = sequencer_output_r & output_mask_w;

    wire [1:0] timer_value_next_case_w = {len_cntr_ld_timerh_reg_wr_w, timerl_reg_wr_w};
    always @(*)
        case (timer_value_next_case_w) // one hot
            2'b10:   timer_value_next_r = {channel_regs_wr_data_i[2:0], timer_value_r[7:0]};
            2'b01:   timer_value_next_r = {timer_value_r[10:8], channel_regs_wr_data_i[7:0]};
            default: timer_value_next_r = timer_value_r;
        endcase

    wire [1:0] linear_reload_next_case_w = {len_cntr_ld_timerh_reg_wr_w, quarter_frame_i};
    always @(*)
        casez (linear_reload_next_case_w)
            2'b1_?:  linear_flag_next_r = 1'b1;
            2'b0_1:  linear_flag_next_r = linear_flag_r && linear_control_r;
            default: linear_flag_next_r = linear_flag_r;
        endcase

    always @(*)
        case (sequencer_r)
            5'd0:    sequencer_output_r = 6'd45;
            5'd1:    sequencer_output_r = 6'd42;
            5'd2:    sequencer_output_r = 6'd39;
            5'd3:    sequencer_output_r = 6'd36;
            5'd4:    sequencer_output_r = 6'd33;
            5'd5:    sequencer_output_r = 6'd30;
            5'd6:    sequencer_output_r = 6'd27;
            5'd7:    sequencer_output_r = 6'd24;
            5'd8:    sequencer_output_r = 6'd21;
            5'd9:    sequencer_output_r = 6'd18;
            5'd10:   sequencer_output_r = 6'd15;
            5'd11:   sequencer_output_r = 6'd12;
            5'd12:   sequencer_output_r = 6'd9;
            5'd13:   sequencer_output_r = 6'd6;
            5'd14:   sequencer_output_r = 6'd3;
            5'd15:   sequencer_output_r = 6'd0;
            5'd16:   sequencer_output_r = 6'd0;
            5'd17:   sequencer_output_r = 6'd3;
            5'd18:   sequencer_output_r = 6'd6;
            5'd19:   sequencer_output_r = 6'd9;
            5'd20:   sequencer_output_r = 6'd12;
            5'd21:   sequencer_output_r = 6'd15;
            5'd22:   sequencer_output_r = 6'd18;
            5'd23:   sequencer_output_r = 6'd21;
            5'd24:   sequencer_output_r = 6'd24;
            5'd25:   sequencer_output_r = 6'd27;
            5'd26:   sequencer_output_r = 6'd30;
            5'd27:   sequencer_output_r = 6'd33;
            5'd28:   sequencer_output_r = 6'd36;
            5'd29:   sequencer_output_r = 6'd39;
            5'd30:   sequencer_output_r = 6'd42;
            5'd31:   sequencer_output_r = 6'd45;
        endcase


    // Контроллер счётчика длины ноты
    cpu_RP2A03_apu_length_counter
        length_counter
        (
            .clk_i                       (clk_i                      ),
            .rst_i                       (rst_i                      ),

            .length_counter_load_reg_wr_i(len_cntr_ld_timerh_reg_wr_w),
            .channel_regs_wr_data_i      (channel_regs_wr_data_i     ),

            .half_frame_i                (half_frame_i               ),

            .channel_enabled_i           (channel_enabled_i          ),
            .length_counting_i           (length_counting_w          ),
            .length_is_nzero_o           (length_is_nzero_w          )
        );


    //Выходы
    assign channel_is_active_o = length_is_nzero_w;
    assign channel_output_o    = output_r;


endmodule
