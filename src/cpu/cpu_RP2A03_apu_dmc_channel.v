
/*
 * Description : RP2A03 audio processor dmc channel implementation module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module cpu_RP2A03_apu_dmc_channel
    (
        input  wire        clk_i,                  // Сигнал тактирования
        input  wire        rst_i,                  // Сигнал сброса

        input  wire        channel_regs_wr_i,      // Сигнал записи данных в регистры канала
        input  wire [ 1:0] channel_regs_addr_i,    // Адрес регистра для записи
        input  wire [ 7:0] channel_regs_wr_data_i, // Записываемые данные в регистры канала

        input  wire        channel_start_i,        // Сигнал старта канала
        input  wire        channel_enabled_i,      // Сигнал - "канал включен"
        input  wire        channel_irq_clear_i,    // Сигнал сброса прерывания
        output wire        channel_is_active_o,    // Сигнал - "канал активен"
        output wire [ 6:0] channel_output_o,       // Выход канала
        output wire        channel_irq_o,          // Сигнал прерывания от канала

        output wire        dmc_dma_exe_o,          // Сигнал активности DMA
        output wire [15:0] dmc_dma_addr_o,         // Сигнал адреса для DMA
        input  wire        dmc_dma_rd_i,           // Сигнал приема данных от DMA
        input  wire [ 7:0] dmc_dma_rd_data_i       // Данные от DMA
    );


    // Адреса регистров канала
    localparam [1:0] CONTROL_REG_ADDR        = 2'h0,
                     DIRECT_LOAD_REG_ADDR    = 2'h1,
                     SAMPLE_ADDRESS_REG_ADDR = 2'h2,
                     SAMPLE_LENGTH_REG_ADDR  = 2'h3;

    // Границы допустимых значений при обновлении DPCM выхода
    localparam [6:0] DPCM_OUTPUT_UPDATE_THRESHOLD_LOW  = 7'd1,
                     DPCM_OUTPUT_UPDATE_THRESHOLD_HIGH = 7'd126,
                     DPCM_OUTL                         = DPCM_OUTPUT_UPDATE_THRESHOLD_LOW,
                     DPCM_OUTH                         = DPCM_OUTPUT_UPDATE_THRESHOLD_HIGH;


    // Регистры канала
    wire        control_reg_wr_w;
    wire        direct_load_reg_wr_w;
    wire        sample_address_reg_wr_w;
    wire        sample_length_reg_wr_w;
    wire        channel_disabled_w;

    // Сигналы уравления каналом и его данными
    reg  [ 7:0] addr_value_r;
    wire [ 7:0] addr_value_next_w;
    reg  [ 7:0] length_value_r;
    wire [ 7:0] length_value_next_w;
    reg  [ 7:0] data_buffer_r;
    wire [ 7:0] data_buffer_next_w;
    reg         buffer_empty_r;
    reg         buffer_empty_next_r;
    reg  [14:0] sample_addr_r;
    reg  [14:0] sample_addr_next_r;
    reg  [11:0] sample_length_r;
    reg  [11:0] sample_length_next_r;
    reg         sample_start_r;
    wire        sample_start_next_w;
    reg  [ 3:0] rate_r;
    wire [ 3:0] rate_next_w;
    reg         loop_r;
    wire        loop_next_w;
    reg         irq_enabled_r;
    wire        irq_enabled_next_w;
    reg         irq_r;
    reg         irq_next_r;

    wire        sample_data_remains_w;
    wire        sample_data_empty_w;
    wire        sample_data_last_w;
    wire        sample_end_point_w;
    wire        sample_restart_w;
    wire        sample_data_loading_w;
    wire        irq_disabled_w;
    wire        irq_clear_w;
    wire        irq_set_w;
    wire        dmc_dma_exe_w;
    wire [15:0] dmc_dma_addr_w;

    // Сигналы генерации выхода канала
    reg  [ 8:0] timer_r;
    wire [ 8:0] timer_next_w;
    reg  [ 2:0] bits_counter_r;
    wire [ 2:0] bits_counter_next_w;
    reg  [ 7:0] shifter_r;
    reg  [ 7:0] shifter_next_r;
    reg         silence_r;
    wire        silence_next_w;
    reg  [ 6:0] output_r;
    reg  [ 6:0] output_next_r;

    wire        timer_is_zero_w;
    wire        timer_pulse_w;
    wire        bits_counter_is_zero_w;
    wire        cycle_ends_w;
    wire        shifter_update_w;
    wire        output_update_w;
    wire        shifter_out_w;
    wire        output_add_w;
    wire        output_sub_w;
    reg  [ 8:0] timer_value_r;


    // Декодирование доступа к регистрам
    assign control_reg_wr_w        = channel_regs_wr_i && (channel_regs_addr_i == CONTROL_REG_ADDR);
    assign direct_load_reg_wr_w    = channel_regs_wr_i && (channel_regs_addr_i == DIRECT_LOAD_REG_ADDR);
    assign sample_address_reg_wr_w = channel_regs_wr_i && (channel_regs_addr_i == SAMPLE_ADDRESS_REG_ADDR);
    assign sample_length_reg_wr_w  = channel_regs_wr_i && (channel_regs_addr_i == SAMPLE_LENGTH_REG_ADDR);


    // Уравление данными канала
    always @(posedge clk_i)
        if (rst_i) begin
            addr_value_r    <= 8'h0;
            length_value_r  <= 8'h0;
            sample_addr_r   <= 15'h0;
            sample_length_r <= 12'h0;
            rate_r          <= 4'h0;
            loop_r          <= 1'b0;
            irq_enabled_r   <= 1'b0;
            irq_r           <= 1'b0;
            data_buffer_r   <= 8'h0;
            buffer_empty_r  <= 1'b1;
            silence_r       <= 1'b1;
            sample_start_r  <= 1'b0;
        end else begin
            addr_value_r    <= addr_value_next_w;
            length_value_r  <= length_value_next_w;
            sample_addr_r   <= sample_addr_next_r;
            sample_length_r <= sample_length_next_r;
            rate_r          <= rate_next_w;
            loop_r          <= loop_next_w;
            irq_enabled_r   <= irq_enabled_next_w;
            irq_r           <= irq_next_r;
            data_buffer_r   <= data_buffer_next_w;
            buffer_empty_r  <= buffer_empty_next_r;
            silence_r       <= silence_next_w;
            sample_start_r  <= sample_start_next_w;
        end

    assign channel_disabled_w    = ~channel_enabled_i;

    assign addr_value_next_w     = (sample_address_reg_wr_w) ? channel_regs_wr_data_i      : addr_value_r;
    assign length_value_next_w   = (sample_length_reg_wr_w ) ? channel_regs_wr_data_i      : length_value_r;

    assign loop_next_w           = (control_reg_wr_w       ) ? channel_regs_wr_data_i[6]   : loop_r;
    assign irq_enabled_next_w    = (control_reg_wr_w       ) ? channel_regs_wr_data_i[7]   : irq_enabled_r;
    assign rate_next_w           = (control_reg_wr_w       ) ? channel_regs_wr_data_i[3:0] : rate_r;

    assign sample_start_next_w   = channel_start_i && sample_data_empty_w;

    assign sample_data_remains_w =  |sample_length_r;
    assign sample_data_last_w    = ~|sample_length_r[11:1] && sample_length_r[0]; // (sample_length_r == 12'h1)
    assign sample_data_empty_w   =  ~sample_data_remains_w;

    assign sample_end_point_w    = sample_data_last_w && dmc_dma_rd_i && channel_enabled_i;
    assign sample_restart_w      = sample_end_point_w && loop_r;
    assign sample_data_loading_w = sample_start_r || sample_restart_w;

    assign irq_disabled_w        = ~irq_enabled_r;
    assign irq_clear_w           = irq_disabled_w || channel_irq_clear_i;
    assign irq_set_w             = sample_end_point_w && ~loop_r && irq_enabled_r;

    assign dmc_dma_exe_w         = buffer_empty_r && sample_data_remains_w;
    assign dmc_dma_addr_w        = {1'b1, sample_addr_r};

    assign data_buffer_next_w    = (dmc_dma_rd_i) ? dmc_dma_rd_data_i : data_buffer_r;

    assign silence_next_w        = (cycle_ends_w) ? buffer_empty_r : silence_r;

    wire [1:0] empty_next_case_w = {cycle_ends_w, dmc_dma_rd_i};
    always @(*)
        case (empty_next_case_w) // one hot
            2'b10:   buffer_empty_next_r  = 1'b1;
            2'b01:   buffer_empty_next_r  = 1'b0;
            default: buffer_empty_next_r  = buffer_empty_r;
        endcase

    wire [1:0] length_next_case_w = {channel_disabled_w, sample_data_loading_w};
    always @(*)
        casez (length_next_case_w)
            2'b1_?:  sample_length_next_r = 12'h0;
            2'b0_1:  sample_length_next_r = {length_value_r, 4'h1};
            2'b0_0:  sample_length_next_r = sample_length_r - dmc_dma_rd_i;
        endcase

    wire [1:0] addr_next_case_w = {sample_data_loading_w, dmc_dma_rd_i};
    always @(*)
        casez (addr_next_case_w)
            2'b1_?:  sample_addr_next_r   = {1'b1, addr_value_r, 6'h0};
            2'b0_1:  sample_addr_next_r   = sample_addr_r + 1'b1;
            default: sample_addr_next_r   = sample_addr_r;
        endcase

    wire [1:0] irq_next_case_w = {irq_clear_w, irq_set_w};
    always @(*)
        casez (irq_next_case_w)
            2'b1_?:  irq_next_r           = 1'b0;
            2'b0_1:  irq_next_r           = 1'b1;
            default: irq_next_r           = irq_r;
        endcase


    // Генерация выходного значения канала
    always @(posedge clk_i)
        if (rst_i) begin
            output_r       <= 7'h0;
            timer_r        <= 9'h0;
            bits_counter_r <= 3'h0;
        end else begin
            output_r       <= output_next_r;
            timer_r        <= timer_next_w;
            bits_counter_r <= bits_counter_next_w;
        end

    always @(posedge clk_i)
        begin
            shifter_r      <= shifter_next_r;
        end

    assign timer_is_zero_w        = ~|timer_r;
    assign timer_pulse_w          = timer_is_zero_w;

    assign timer_next_w           = (timer_pulse_w) ? timer_value_r : timer_r - 1'b1;

    assign bits_counter_is_zero_w = ~|bits_counter_r;

    assign cycle_ends_w           = bits_counter_is_zero_w &&  timer_pulse_w;
    assign shifter_update_w       = bits_counter_is_zero_w && ~buffer_empty_r;

    assign bits_counter_next_w    = bits_counter_r - timer_pulse_w;

    assign output_update_w        = ~silence_r && timer_pulse_w;
    assign shifter_out_w          =  shifter_r[0];
    assign output_add_w           =  shifter_out_w && (output_r < DPCM_OUTH) && output_update_w;
    assign output_sub_w           = ~shifter_out_w && (output_r > DPCM_OUTL) && output_update_w;

    wire [2:0] output_next_case_w = {direct_load_reg_wr_w, output_add_w, output_sub_w};
    always @(*)
        casez (output_next_case_w)
            3'b1_??: output_next_r  = channel_regs_wr_data_i[6:0];
            3'b0_10: output_next_r  = output_r + 2'd2;
            3'b0_01: output_next_r  = output_r - 2'd2;
            default: output_next_r  = output_r;
        endcase

    wire [1:0] shifter_next_case_w = {timer_pulse_w, shifter_update_w};
    always @(*)
        case (shifter_next_case_w)
            2'b11:   shifter_next_r = data_buffer_r;
            2'b10:   shifter_next_r = {1'b0, shifter_r[7:1]};
            default: shifter_next_r = shifter_r;
        endcase

    always @(*)
        case (rate_r)
            4'h0:    timer_value_r  = 9'd427;
            4'h1:    timer_value_r  = 9'd379;
            4'h2:    timer_value_r  = 9'd339;
            4'h3:    timer_value_r  = 9'd319;
            4'h4:    timer_value_r  = 9'd285;
            4'h5:    timer_value_r  = 9'd253;
            4'h6:    timer_value_r  = 9'd225;
            4'h7:    timer_value_r  = 9'd213;
            4'h8:    timer_value_r  = 9'd189;
            4'h9:    timer_value_r  = 9'd159;
            4'hA:    timer_value_r  = 9'd141;
            4'hB:    timer_value_r  = 9'd127;
            4'hC:    timer_value_r  = 9'd105;
            4'hD:    timer_value_r  = 9'd83;
            4'hE:    timer_value_r  = 9'd71;
            4'hF:    timer_value_r  = 9'd53;
        endcase


    // Выходы
    assign channel_is_active_o = sample_data_remains_w;
    assign channel_output_o    = output_r;
    assign channel_irq_o       = irq_r;

    assign dmc_dma_exe_o       = dmc_dma_exe_w;
    assign dmc_dma_addr_o      = dmc_dma_addr_w;


endmodule
