
/*
 * Description : RP2A03 audio processor pulse channel implementation module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module cpu_RP2A03_apu_pulse_channel
    #(
        parameter SWEEP_COMPLEMENT = "ones'"      /* "ones'" или "two's" - кодировка отрицательного значения
                                                   * для логики подстройки частоты, обратный или дополнительный код
                                                   * соответственно */
    )
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
        output wire [3:0] channel_output_o        // Выход канала
    );


    // Адреса регистров канала
    localparam [1:0] CONTROL_REG_ADDR            = 2'h0,
                     SWEEP_SETUP_REG_ADDR        = 2'h1,
                     TIMERL_REG_ADDR             = 2'h2,
                     LEN_CNTR_LD_TIMERH_REG_ADDR = 2'h3;


    // Регистры канала
    wire        control_reg_wr_w;
    wire        sweep_setup_reg_wr_w;
    wire        timerl_reg_wr_w;
    wire        len_cntr_ld_timerh_reg_wr_w;

    // Сигналы управления каналом и генерации выхода
    reg  [ 2:0] sequencer_r;
    wire [ 2:0] sequencer_next_w;
    reg  [11:0] timer_r;
    wire [11:0] timer_next_w;
    reg  [10:0] timer_value_r;
    reg  [10:0] timer_value_next_r;
    reg  [ 1:0] duty_cycle_r;
    wire [ 1:0] duty_cycle_next_w;
    reg         envelope_loop_r;
    wire        envelope_loop_next_w;
    reg         const_volume_r;
    wire        const_volume_next_w;
    reg  [ 3:0] volume_r;
    wire [ 3:0] volume_next_w;
    reg  [ 3:0] output_r;
    wire [ 3:0] output_next_w;

    reg  [ 7:0] output_waveform_r;
    wire        length_counting_w;
    wire        timer_is_zero_w;
    wire        timer_pulse_w;
    wire        sequencer_output_w;
    wire        output_enabled_w;
    wire [ 3:0] output_mask_w;
    wire        muting_is_inactive_w;
    wire [10:0] target_timer_value_w;
    wire        timer_value_update_w;
    wire        length_is_nzero_w;
    wire [ 3:0] envelope_level_w;


    // Декодирование доступа к регистрам
    assign control_reg_wr_w            = channel_regs_wr_i && (channel_regs_addr_i == CONTROL_REG_ADDR);
    assign sweep_setup_reg_wr_w        = channel_regs_wr_i && (channel_regs_addr_i == SWEEP_SETUP_REG_ADDR);
    assign timerl_reg_wr_w             = channel_regs_wr_i && (channel_regs_addr_i == TIMERL_REG_ADDR);
    assign len_cntr_ld_timerh_reg_wr_w = channel_regs_wr_i && (channel_regs_addr_i == LEN_CNTR_LD_TIMERH_REG_ADDR);


    // Генерация выходного значения
    always @(posedge clk_i)
        if (rst_i) begin
            timer_value_r   <= 11'h0;
            timer_r         <= 12'h0;
            duty_cycle_r    <= 2'h0;
            envelope_loop_r <= 1'b0;
            const_volume_r  <= 1'b0;
            volume_r        <= 4'h0;
        end else begin
            timer_value_r   <= timer_value_next_r;
            timer_r         <= timer_next_w;
            duty_cycle_r    <= duty_cycle_next_w;
            envelope_loop_r <= envelope_loop_next_w;
            const_volume_r  <= const_volume_next_w;
            volume_r        <= volume_next_w;
        end

    always @(posedge clk_i)
        begin
            sequencer_r     <= sequencer_next_w;
            output_r        <= output_next_w;
        end

    assign duty_cycle_next_w    = (control_reg_wr_w) ? channel_regs_wr_data_i[7:6] : duty_cycle_r;
    assign envelope_loop_next_w = (control_reg_wr_w) ? channel_regs_wr_data_i[5]   : envelope_loop_r;
    assign const_volume_next_w  = (control_reg_wr_w) ? channel_regs_wr_data_i[4]   : const_volume_r;
    assign volume_next_w        = (control_reg_wr_w) ? channel_regs_wr_data_i[3:0] : volume_r;

    assign length_counting_w    = ~envelope_loop_r;

    assign timer_is_zero_w      = ~|timer_r;
    assign timer_pulse_w        = timer_is_zero_w;

    assign timer_next_w         = (timer_pulse_w) ? {timer_value_r, 1'b0} : timer_r - 1'b1;

    assign sequencer_next_w     = (len_cntr_ld_timerh_reg_wr_w) ? 3'h0 : sequencer_r - timer_pulse_w;

    assign sequencer_output_w   = output_waveform_r[sequencer_r];

    assign output_enabled_w     = sequencer_output_w && length_is_nzero_w && muting_is_inactive_w;
    assign output_mask_w        = {4{output_enabled_w}};

    assign output_next_w        = envelope_level_w & output_mask_w;

    wire [2:0] timer_value_next_case_w = {len_cntr_ld_timerh_reg_wr_w, timerl_reg_wr_w, timer_value_update_w};
    always @(*)
        casez (timer_value_next_case_w)
            3'b10_?: timer_value_next_r = {channel_regs_wr_data_i[2:0], timer_value_r[7:0]};
            3'b01_?: timer_value_next_r = {timer_value_r[10:8], channel_regs_wr_data_i[7:0]};
            3'b00_1: timer_value_next_r = target_timer_value_w;
            default: timer_value_next_r = timer_value_r;
        endcase

    always @(*)
        case (duty_cycle_r)
            2'h0:    output_waveform_r  = {1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1}; // 12.5%
            2'h1:    output_waveform_r  = {1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1}; // 25.0%
            2'h2:    output_waveform_r  = {1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1}; // 50.0%
            2'h3:    output_waveform_r  = {1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0}; // 25.0% negated
        endcase


    // Контроллер подстройки частоты
    cpu_RP2A03_apu_sweep_unit
        #(
            .SWEEP_COMPLEMENT(SWEEP_COMPLEMENT)
        )
        sweep_unit
        (
            .clk_i                       (clk_i                      ),
            .rst_i                       (rst_i                      ),

            .sweep_setup_reg_wr_i        (sweep_setup_reg_wr_w       ),
            .channel_regs_wr_data_i      (channel_regs_wr_data_i     ),

            .half_frame_i                (half_frame_i               ),

            .timer_value_i               (timer_value_r              ),
            .muting_is_inactive_o        (muting_is_inactive_w       ),
            .target_timer_value_o        (target_timer_value_w       ),
            .timer_value_update_o        (timer_value_update_w       )
        );


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


    // Контроллер "огибающей"
    cpu_RP2A03_apu_envelope
        envelope
        (
            .clk_i                       (clk_i                      ),
            .rst_i                       (rst_i                      ),

            .length_counter_load_reg_wr_i(len_cntr_ld_timerh_reg_wr_w),

            .quarter_frame_i             (quarter_frame_i            ),

            .const_volume_i              (const_volume_r             ),
            .envelope_loop_i             (envelope_loop_r            ),
            .volume_i                    (volume_r                   ),
            .envelope_level_o            (envelope_level_w           )
        );


    //Выходы
    assign channel_is_active_o = length_is_nzero_w;
    assign channel_output_o    = output_r;


endmodule
