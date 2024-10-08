
/*
 * Description : RP2A03 audio processor noise channel implementation module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module cpu_RP2A03_apu_noise_channel
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
        output wire [4:0] channel_output_o        // Выход канала
    );


    // Адреса регистров канала
    localparam [1:0] CONTROL_REG_ADDR             = 2'h0,
                     NOISE_SETUP_REG_ADDR         = 2'h2,
                     LENGTH_COUNTER_LOAD_REG_ADDR = 2'h3;


    // Регистры канала
    wire        control_reg_wr_w;
    wire        noise_setup_reg_wr_w;
    wire        length_counter_load_reg_wr_w;

    // Сигналы управления каналом и генерации выхода
    reg  [11:0] timer_r;
    wire [11:0] timer_next_w;
    reg  [ 3:0] period_r;
    wire [ 3:0] period_next_w;
    reg         mode_r;
    wire        mode_next_w;
    reg         envelope_loop_r;
    wire        envelope_loop_next_w;
    reg         const_volume_r;
    wire        const_volume_next_w;
    reg  [ 3:0] volume_r;
    wire [ 3:0] volume_next_w;
    reg  [14:0] lfsr_r;
    wire [14:0] lfsr_next_w;
    reg  [ 4:0] output_r;
    wire [ 4:0] output_next_w;

    reg  [11:0] timer_value_r;
    wire        length_counting_w;
    wire        timer_is_zero_w;
    wire        timer_pulse_w;
    wire        lfsr_feedback_w;
    wire        lfsr_output_w;
    wire        output_enabled_w;
    wire [ 4:0] output_mask_w;
    wire        length_is_nzero_w;
    wire [ 3:0] envelope_level_w;
    wire [ 4:0] envelope_level_x2_w;


    // Декодирование доступа к регистрам
    assign control_reg_wr_w             = channel_regs_wr_i && (channel_regs_addr_i == CONTROL_REG_ADDR);
    assign noise_setup_reg_wr_w         = channel_regs_wr_i && (channel_regs_addr_i == NOISE_SETUP_REG_ADDR);
    assign length_counter_load_reg_wr_w = channel_regs_wr_i && (channel_regs_addr_i == LENGTH_COUNTER_LOAD_REG_ADDR);


    // Генерация выходного значения
    always @(posedge clk_i)
        if (rst_i) begin
            period_r        <= 4'h0;
            timer_r         <= 12'h0;
            mode_r          <= 1'b0;
            envelope_loop_r <= 1'b0;
            const_volume_r  <= 1'b0;
            volume_r        <= 4'h0;
            lfsr_r          <= 15'h1;
        end else begin
            period_r        <= period_next_w;
            timer_r         <= timer_next_w;
            mode_r          <= mode_next_w;
            envelope_loop_r <= envelope_loop_next_w;
            const_volume_r  <= const_volume_next_w;
            volume_r        <= volume_next_w;
            lfsr_r          <= lfsr_next_w;
        end

    always @(posedge clk_i)
        begin
            output_r        <= output_next_w;
        end

    assign period_next_w        = (noise_setup_reg_wr_w) ? channel_regs_wr_data_i[3:0] : period_r;
    assign mode_next_w          = (noise_setup_reg_wr_w) ? channel_regs_wr_data_i[7]   : mode_r;
    assign envelope_loop_next_w = (control_reg_wr_w    ) ? channel_regs_wr_data_i[5]   : envelope_loop_r;
    assign const_volume_next_w  = (control_reg_wr_w    ) ? channel_regs_wr_data_i[4]   : const_volume_r;
    assign volume_next_w        = (control_reg_wr_w    ) ? channel_regs_wr_data_i[3:0] : volume_r;

    assign length_counting_w    = ~envelope_loop_r;

    assign timer_is_zero_w      = ~|timer_r;
    assign timer_pulse_w        = timer_is_zero_w;

    assign timer_next_w         = (timer_pulse_w) ? timer_value_r : timer_r - 1'b1;

    assign lfsr_feedback_w      = (mode_r       ) ?  lfsr_r[0] ^ lfsr_r[6]          : lfsr_r[0] ^ lfsr_r[1];
    assign lfsr_next_w          = (timer_pulse_w) ? {lfsr_feedback_w, lfsr_r[14:1]} : lfsr_r;
    assign lfsr_output_w        = ~lfsr_r[0];

    assign envelope_level_x2_w  = envelope_level_w + envelope_level_w;

    assign output_enabled_w     = lfsr_output_w && length_is_nzero_w;
    assign output_mask_w        = {5{output_enabled_w}};

    assign output_next_w        = envelope_level_x2_w & output_mask_w;

    always @(*)
        case (period_r)
            4'h0:    timer_value_r = 12'd3;
            4'h1:    timer_value_r = 12'd7;
            4'h2:    timer_value_r = 12'd15;
            4'h3:    timer_value_r = 12'd31;
            4'h4:    timer_value_r = 12'd63;
            4'h5:    timer_value_r = 12'd95;
            4'h6:    timer_value_r = 12'd127;
            4'h7:    timer_value_r = 12'd159;
            4'h8:    timer_value_r = 12'd201;
            4'h9:    timer_value_r = 12'd253;
            4'hA:    timer_value_r = 12'd379;
            4'hB:    timer_value_r = 12'd507;
            4'hC:    timer_value_r = 12'd761;
            4'hD:    timer_value_r = 12'd1015;
            4'hE:    timer_value_r = 12'd2033;
            4'hF:    timer_value_r = 12'd4067;
        endcase


    // Контроллер счётчика длины ноты
    cpu_RP2A03_apu_length_counter
        length_counter
        (
            .clk_i                       (clk_i                       ),
            .rst_i                       (rst_i                       ),

            .length_counter_load_reg_wr_i(length_counter_load_reg_wr_w),
            .channel_regs_wr_data_i      (channel_regs_wr_data_i      ),

            .half_frame_i                (half_frame_i                ),

            .channel_enabled_i           (channel_enabled_i           ),
            .length_counting_i           (length_counting_w           ),
            .length_is_nzero_o           (length_is_nzero_w           )
        );


    // Контроллер "огибающей"
    cpu_RP2A03_apu_envelope
        envelope
        (
            .clk_i                       (clk_i                       ),
            .rst_i                       (rst_i                       ),

            .length_counter_load_reg_wr_i(length_counter_load_reg_wr_w),

            .quarter_frame_i             (quarter_frame_i             ),

            .const_volume_i              (const_volume_r              ),
            .envelope_loop_i             (envelope_loop_r             ),
            .volume_i                    (volume_r                    ),
            .envelope_level_o            (envelope_level_w            )
        );


    // Выходы
    assign channel_is_active_o = length_is_nzero_w;
    assign channel_output_o    = output_r;


endmodule
