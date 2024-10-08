
/*
 * Description : RP2A03 audio processor note sweep logic implementation module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module cpu_RP2A03_apu_sweep_unit
    #(
        parameter SWEEP_COMPLEMENT = "ones'"       /* "ones'" или "two's" — кодировка отрицательного значения,
                                                    * обратный или дополнительный код соответственно */
    )
    (
        input  wire        clk_i,                  // Сигнал тактирования
        input  wire        rst_i,                  // Сигнал сброса

        input  wire        sweep_setup_reg_wr_i,   // Сигнал записи в регистр управления подстройкой частоты
        input  wire [ 7:0] channel_regs_wr_data_i, // Записываемые данные в регистр управления подстройкой частоты

        input  wire        half_frame_i,           // Сигнал синхронизации — флаг половины фрейма

        input  wire [10:0] timer_value_i,          // Текущее значение таймера, определяющего действующую частоту ноты
        output wire        muting_is_inactive_o,   // Заглушение канала неактивно
        output wire [10:0] target_timer_value_o,   // Новое значение таймера, изменяющее частоту ноты
        output wire        timer_value_update_o    // Сигнал необходимости обновить значение таймера частоты
    );


    reg         enable_r;
    wire        enable_next_w;
    reg  [ 2:0] period_r;
    wire [ 2:0] period_next_w;
    reg         negate_r;
    wire        negate_next_w;
    reg  [ 2:0] shift_r;
    wire [ 2:0] shift_next_w;
    reg  [ 2:0] counter_r;
    wire [ 2:0] counter_next_w;
    reg         restart_r;
    reg         restart_next_r;

    wire [11:0] pos_change_amount_w;
    wire [11:0] neg_change_amount_w;
    wire [11:0] change_amount_w;
    wire [11:0] change_sum_w;
    wire [10:0] target_timer_value_w;
    wire        target_timer_value_valid_w;
    wire        counter_is_zero_w;
    wire        reload_w;
    wire        timer_value_valid_w;
    wire        muting_is_inactive_w;
    wire        sweeping_is_active_w;
    wire        timer_value_update_w;


    always @(posedge clk_i)
        if (rst_i) begin
            enable_r  <= 1'b0;
            period_r  <= 3'h0;
            negate_r  <= 1'b0;
            shift_r   <= 3'h0;
            restart_r <= 1'b0;
            counter_r <= 3'h0;
        end else begin
            enable_r  <= enable_next_w;
            period_r  <= period_next_w;
            negate_r  <= negate_next_w;
            shift_r   <= shift_next_w;
            restart_r <= restart_next_r;
            counter_r <= counter_next_w;
        end

    assign enable_next_w              = (sweep_setup_reg_wr_i) ? channel_regs_wr_data_i[7]   : enable_r;
    assign period_next_w              = (sweep_setup_reg_wr_i) ? channel_regs_wr_data_i[6:4] : period_r;
    assign negate_next_w              = (sweep_setup_reg_wr_i) ? channel_regs_wr_data_i[3]   : negate_r;
    assign shift_next_w               = (sweep_setup_reg_wr_i) ? channel_regs_wr_data_i[2:0] : shift_r;

    assign pos_change_amount_w        = {1'b0, timer_value_i} >> shift_r;

    generate
        if (SWEEP_COMPLEMENT == "ones'") begin: ones_complement
            assign neg_change_amount_w = ~pos_change_amount_w;
        end else begin: twos_complement
            assign neg_change_amount_w = ~pos_change_amount_w + 1'b1;
        end
    endgenerate

    assign change_amount_w            = (negate_r) ? neg_change_amount_w : pos_change_amount_w;

    assign change_sum_w               = {1'b0, timer_value_i} + change_amount_w;

    assign target_timer_value_w       = (change_sum_w[11]) ? 11'h0 : change_sum_w[10:0];
    assign target_timer_value_valid_w = ~change_sum_w[11];

    assign counter_is_zero_w          = ~|counter_r;
    assign reload_w                   = (counter_is_zero_w || restart_r) && half_frame_i;

    assign timer_value_valid_w        = |timer_value_i[10:3];

    assign muting_is_inactive_w       = timer_value_valid_w && target_timer_value_valid_w;
    assign sweeping_is_active_w       = enable_r && |shift_r;
    assign timer_value_update_w       = counter_is_zero_w && half_frame_i && sweeping_is_active_w && muting_is_inactive_w;

    assign counter_next_w             = (reload_w) ? period_r : counter_r - half_frame_i;

    wire [1:0] restart_next_case_w = {sweep_setup_reg_wr_i, half_frame_i};
    always @(*)
        casez (restart_next_case_w)
            2'b1_?:  restart_next_r = 1'b1;
            2'b0_1:  restart_next_r = 1'b0;
            default: restart_next_r = restart_r;
        endcase


    assign muting_is_inactive_o = muting_is_inactive_w;
    assign target_timer_value_o = target_timer_value_w;
    assign timer_value_update_o = timer_value_update_w;


endmodule
