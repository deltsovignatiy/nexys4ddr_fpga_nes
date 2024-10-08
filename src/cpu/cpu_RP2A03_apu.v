
/*
 * Description : RP2A03 audio processor implementation (5 channles combined with 2 LUT for PCM output generation) module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module cpu_RP2A03_apu
    (
        input  wire        clk_i,                 // Сигнал тактирования
        input  wire        rst_i,                 // Сигнал сброса

        input  wire        apu_wr_i,              // Сигнал записи данных в регистры аудиопроцессора
        input  wire        apu_rd_i,              // Сигнал чтения данных из регистров аудиопроцесора
        input  wire [ 4:0] apu_addr_i,            // Адрес обращения к регистрам аудиопроцессора
        input  wire [ 7:0] apu_wr_data_i,         // Записываемые данные в регистры аудиопроцессора
        output wire [ 7:0] apu_rd_data_o,         // Читаемые данные из регистров аудиопроцессора

        input  wire        apu_cycle_i,           // Сигнал синхонизации с процессом
        output wire [15:0] apu_output_o,          // Выход аудиопроцессора в формате PCM
        output wire        apu_frame_irq_o,       // Сигнал прерывания от фрейм счётчика
        output wire        apu_dmc_channel_irq_o, // Сигнал прерывания от DMC канала

        output wire        dmc_dma_exe_o,         // Сигнал активности DMC DMA
        output wire [15:0] dmc_dma_addr_o,        // Сигнал адреса для DMA от DMC канала
        input  wire        dmc_dma_rd_i,          // Сигнал приема данных DMC от DMA
        input  wire [ 7:0] dmc_dma_rd_data_i      // Данные для DMC от DMA
    );


    // Адреса регистров аудиопроцессора
    localparam [ 4:0] APU_CONTROL_STATUS_REG_ADDR = 5'h15,
                      FRAME_COUNTER_REG_ADDR      = 5'h17;

    localparam [ 2:0] PULSE1_CHANNEL_BASE_ADDR    = 3'h0,
                      PULSE2_CHANNEL_BASE_ADDR    = 3'h1,
                      TRIANGLE_CHANNEL_BASE_ADDR  = 3'h2,
                      NOISE_CHANNEL_BASE_ADDR     = 3'h3,
                      DMC_CHANNEL_BASE_ADDR       = 3'h4;

    // Стадии фрейма
    localparam [15:0] FRAME_1ST_STEP_VALUE        = 16'd7456,
                      FRAME_2ND_STEP_VALUE        = 16'd14912,
                      FRAME_3RD_STEP_VALUE        = 16'd22370,
                      FRAME_4TH_STEP_VALUE        = 16'd29828,
                      FRAME_5TH_STEP_VALUE        = 16'd37280;


    // Общие сигналы и регистры аудиопроцессора
    reg  [ 1:0] frame_counter_reg_r;
    wire [ 1:0] frame_counter_reg_next_w;
    reg  [ 4:0] apu_control_reg_r;
    wire [ 4:0] apu_control_reg_next_w;
    wire [ 6:0] apu_status_reg_w;
    wire [ 7:0] apu_rd_data_w;
    wire        frame_use_5_step_mode_w;
    wire        frame_irq_flag_inhibit_w;
    wire        dmc_channel_irq_clear_w;
    wire        dmc_channel_irq_w;
    wire        frame_counter_reg_wr_w;
    wire        apu_control_reg_wr_w;
    wire        apu_status_reg_rd_w;
    wire [ 1:0] channel_regs_addr_w;

    // Сигналы управления счётчиком фреймов
    reg  [15:0] frame_counter_r;
    wire [15:0] frame_counter_next_w;
    reg         reset_req_r;
    reg         reset_req_next_r;
    reg         quarter_frame_r;
    wire        quarter_frame_next_w;
    reg         half_frame_r;
    wire        half_frame_next_w;
    reg         full_frame_r;
    wire        full_frame_next_w;
    reg         frame_edge_r;
    wire        frame_edge_next_w;
    reg         frame_flag_r;
    reg         frame_flag_next_r;
    reg         frame_irq_r;
    wire        frame_irq_next_w;
    wire        frame_1st_step_w;
    wire        frame_2nd_step_w;
    wire        frame_3rd_step_w;
    wire        frame_4th_step_w;
    wire        frame_5th_step_w;
    wire        last_frame_step_w;
    wire        apu_reset_req_w;
    wire        frame_counter_restart_w;
    wire        enter_5_step_mode_w;
    wire        frame_flag_permitted_w;
    wire        frame_flag_set_w;
    wire        default_quarter_frame_w;
    wire        default_half_frame_w;

    // Сигналы управления каналами
    wire        pulse1_channel_enabled_w;
    wire        pulse2_channel_enabled_w;
    wire        triangle_channel_enabled_w;
    wire        noise_channel_enabled_w;
    wire        dmc_channel_enabled_w;
    wire        dmc_channel_start_w;

    // Сигналы записи данных в регистры каналов
    wire        pulse1_channel_regs_wr_w;
    wire        pulse2_channel_regs_wr_w;
    wire        triangle_channel_regs_wr_w;
    wire        noise_channel_regs_wr_w;
    wire        dmc_channel_regs_wr_w;

    // Сигналы активности каналов
    wire        pulse1_channel_is_active_w;
    wire        pulse2_channel_is_active_w;
    wire        triangle_channel_is_active_w;
    wire        noise_channel_is_active_w;
    wire        dmc_channel_is_active_w;

    // Сигналы выходов каналов
    wire [ 3:0] pulse1_channel_output_w;
    wire [ 3:0] pulse2_channel_output_w;
    wire [ 5:0] triangle_channel_output_w;
    wire [ 4:0] noise_channel_output_w;
    wire [ 6:0] dmc_channel_output_w;

    // Сигналы микширования
    reg  [14:0] apu_output_r;
    wire [14:0] apu_output_next_w;
    wire [15:0] apu_output_dsm_extend_w;
    wire [ 4:0] pulse_channels_output_w;
    wire [ 7:0] tnd_channels_output_w;

    // LUT микширования
    (* rom_style = "block" *)
    reg  [14:0] pulse_lut_output_r;
    (* rom_style = "block" *)
    reg  [14:0] tnd_lut_output_r;


    // Доступ к регистрам аудиопроцессора и его каналов
    always @(posedge clk_i)
        if (rst_i) begin
            frame_counter_reg_r <= 2'h0;
            apu_control_reg_r   <= 5'h0;
        end else begin
            frame_counter_reg_r <= frame_counter_reg_next_w;
            apu_control_reg_r   <= apu_control_reg_next_w;
        end

    assign apu_status_reg_w           = {dmc_channel_irq_w, frame_flag_r, dmc_channel_is_active_w,
                                         noise_channel_is_active_w, triangle_channel_is_active_w,
                                         pulse2_channel_is_active_w, pulse1_channel_is_active_w};

    assign apu_rd_data_w              = {apu_status_reg_w[6:5], 1'b0, apu_status_reg_w[4:0]};

    assign frame_use_5_step_mode_w    = frame_counter_reg_r[1];
    assign frame_irq_flag_inhibit_w   = frame_counter_reg_r[0];

    assign pulse1_channel_enabled_w   = apu_control_reg_r[0];
    assign pulse2_channel_enabled_w   = apu_control_reg_r[1];
    assign triangle_channel_enabled_w = apu_control_reg_r[2];
    assign noise_channel_enabled_w    = apu_control_reg_r[3];
    assign dmc_channel_enabled_w      = apu_control_reg_r[4];

    assign frame_counter_reg_wr_w     = apu_wr_i && (apu_addr_i      == FRAME_COUNTER_REG_ADDR);
    assign apu_control_reg_wr_w       = apu_wr_i && (apu_addr_i      == APU_CONTROL_STATUS_REG_ADDR);
    assign pulse1_channel_regs_wr_w   = apu_wr_i && (apu_addr_i[4:2] == PULSE1_CHANNEL_BASE_ADDR);
    assign pulse2_channel_regs_wr_w   = apu_wr_i && (apu_addr_i[4:2] == PULSE2_CHANNEL_BASE_ADDR);
    assign triangle_channel_regs_wr_w = apu_wr_i && (apu_addr_i[4:2] == TRIANGLE_CHANNEL_BASE_ADDR);
    assign noise_channel_regs_wr_w    = apu_wr_i && (apu_addr_i[4:2] == NOISE_CHANNEL_BASE_ADDR);
    assign dmc_channel_regs_wr_w      = apu_wr_i && (apu_addr_i[4:2] == DMC_CHANNEL_BASE_ADDR);

    assign apu_status_reg_rd_w        = apu_rd_i && (apu_addr_i      == APU_CONTROL_STATUS_REG_ADDR);

    assign dmc_channel_start_w        = apu_control_reg_wr_w && apu_wr_data_i[4];
    assign dmc_channel_irq_clear_w    = apu_control_reg_wr_w;

    assign channel_regs_addr_w        = apu_addr_i[1:0];

    assign frame_counter_reg_next_w   = (frame_counter_reg_wr_w ) ? apu_wr_data_i[7:6] : frame_counter_reg_r;
    assign apu_control_reg_next_w     = (apu_control_reg_wr_w   ) ? apu_wr_data_i[4:0] : apu_control_reg_r;


    // Логика фрейм счётчика
    always @(posedge clk_i)
        if (rst_i) begin
            frame_counter_r <= 16'h2;
            reset_req_r     <= 1'b0;
            quarter_frame_r <= 1'b0;
            half_frame_r    <= 1'b0;
            full_frame_r    <= 1'b0;
            frame_edge_r    <= 1'b0;
            frame_flag_r    <= 1'b0;
            frame_irq_r     <= 1'b0;
        end else begin
            frame_counter_r <= frame_counter_next_w;
            reset_req_r     <= reset_req_next_r;
            quarter_frame_r <= quarter_frame_next_w;
            half_frame_r    <= half_frame_next_w;
            full_frame_r    <= full_frame_next_w;
            frame_edge_r    <= frame_edge_next_w;
            frame_flag_r    <= frame_flag_next_r;
            frame_irq_r     <= frame_irq_next_w;
        end

    assign frame_1st_step_w        = (frame_counter_r == FRAME_1ST_STEP_VALUE);
    assign frame_2nd_step_w        = (frame_counter_r == FRAME_2ND_STEP_VALUE);
    assign frame_3rd_step_w        = (frame_counter_r == FRAME_3RD_STEP_VALUE);
    assign frame_4th_step_w        = (frame_counter_r == FRAME_4TH_STEP_VALUE);
    assign frame_5th_step_w        = (frame_counter_r == FRAME_5TH_STEP_VALUE);

    assign frame_flag_points_w     = frame_4th_step_w || full_frame_r || frame_edge_r;

    assign last_frame_step_w       = (frame_use_5_step_mode_w) ? frame_5th_step_w : frame_4th_step_w;

    assign frame_flag_permitted_w  = ~frame_use_5_step_mode_w && ~frame_irq_flag_inhibit_w;
    assign enter_5_step_mode_w     =  frame_use_5_step_mode_w && apu_cycle_i && reset_req_r;

    assign frame_flag_set_w        = frame_flag_permitted_w && frame_flag_points_w;

    assign default_quarter_frame_w = frame_1st_step_w || frame_2nd_step_w ||
                                     frame_3rd_step_w || last_frame_step_w;
    assign default_half_frame_w    = frame_2nd_step_w || last_frame_step_w;

    assign quarter_frame_next_w    = (enter_5_step_mode_w) ? 1'b1 : default_quarter_frame_w;
    assign half_frame_next_w       = (enter_5_step_mode_w) ? 1'b1 : default_half_frame_w;
    assign full_frame_next_w       = last_frame_step_w;
    assign frame_edge_next_w       = full_frame_r;

    assign apu_reset_req_w         = reset_req_r && apu_cycle_i;

    assign frame_counter_restart_w = apu_reset_req_w || full_frame_r;

    assign frame_irq_next_w        = frame_flag_r && ~frame_irq_flag_inhibit_w && ~apu_status_reg_rd_w;

    assign frame_counter_next_w    = (frame_counter_restart_w) ? 16'h0 : frame_counter_r + 1'b1;

    wire [1:0] reset_req_next_case_w = {frame_counter_reg_wr_w, apu_cycle_i};
    always @(*)
        casez (reset_req_next_case_w)
            2'b1_?:   reset_req_next_r  = 1'b1;
            2'b0_1:   reset_req_next_r  = 1'b0;
            default:  reset_req_next_r  = reset_req_r;
        endcase

    wire [2:0] frame_irq_flag_next_case_w = {frame_irq_flag_inhibit_w, frame_flag_set_w, apu_status_reg_rd_w};
    always @(*)
        casez (frame_irq_flag_next_case_w)
            3'b1_?_?: frame_flag_next_r = 1'b0;
            3'b0_1_?: frame_flag_next_r = 1'b1;
            3'b0_0_1: frame_flag_next_r = 1'b0;
            default:  frame_flag_next_r = frame_flag_r;
        endcase


    // 1-ый прямоугольный канал аудиопроцессора
    cpu_RP2A03_apu_pulse_channel
        #(
            .SWEEP_COMPLEMENT      ("ones'"                     )
        )
        pulse1_channel
        (
            .clk_i                 (clk_i                       ),
            .rst_i                 (rst_i                       ),

            .channel_regs_wr_i     (pulse1_channel_regs_wr_w    ),
            .channel_regs_addr_i   (channel_regs_addr_w         ),
            .channel_regs_wr_data_i(apu_wr_data_i               ),

            .half_frame_i          (half_frame_r                ),
            .quarter_frame_i       (quarter_frame_r             ),

            .channel_enabled_i     (pulse1_channel_enabled_w    ),
            .channel_is_active_o   (pulse1_channel_is_active_w  ),
            .channel_output_o      (pulse1_channel_output_w     )
        );


    // 2-ой прямоугольный канал аудиопроцессора
    cpu_RP2A03_apu_pulse_channel
        #(
            .SWEEP_COMPLEMENT      ("two's"                     )
        )
        pulse2_channel
        (
            .clk_i                 (clk_i                       ),
            .rst_i                 (rst_i                       ),

            .channel_regs_wr_i     (pulse2_channel_regs_wr_w    ),
            .channel_regs_addr_i   (channel_regs_addr_w         ),
            .channel_regs_wr_data_i(apu_wr_data_i               ),

            .half_frame_i          (half_frame_r                ),
            .quarter_frame_i       (quarter_frame_r             ),

            .channel_enabled_i     (pulse2_channel_enabled_w    ),
            .channel_is_active_o   (pulse2_channel_is_active_w  ),
            .channel_output_o      (pulse2_channel_output_w     )
        );


    // Тругольный канал аудиопроцессора
    cpu_RP2A03_apu_triangle_channel
        triangle_channel
        (
            .clk_i                 (clk_i                       ),
            .rst_i                 (rst_i                       ),

            .channel_regs_wr_i     (triangle_channel_regs_wr_w  ),
            .channel_regs_addr_i   (channel_regs_addr_w         ),
            .channel_regs_wr_data_i(apu_wr_data_i               ),

            .half_frame_i          (half_frame_r                ),
            .quarter_frame_i       (quarter_frame_r             ),

            .channel_enabled_i     (triangle_channel_enabled_w  ),
            .channel_is_active_o   (triangle_channel_is_active_w),
            .channel_output_o      (triangle_channel_output_w   )
        );


    // Шумовой канал аудиопроцессора
    cpu_RP2A03_apu_noise_channel
        noise_channel
        (
            .clk_i                 (clk_i                       ),
            .rst_i                 (rst_i                       ),

            .channel_regs_wr_i     (noise_channel_regs_wr_w     ),
            .channel_regs_addr_i   (channel_regs_addr_w         ),
            .channel_regs_wr_data_i(apu_wr_data_i               ),

            .half_frame_i          (half_frame_r                ),
            .quarter_frame_i       (quarter_frame_r             ),

            .channel_enabled_i     (noise_channel_enabled_w     ),
            .channel_is_active_o   (noise_channel_is_active_w   ),
            .channel_output_o      (noise_channel_output_w      )
        );


    // DMC (семпловый) канал аудиопроцессора
    cpu_RP2A03_apu_dmc_channel
        dmc_channel
        (
            .clk_i                 (clk_i                       ),
            .rst_i                 (rst_i                       ),

            .channel_regs_wr_i     (dmc_channel_regs_wr_w       ),
            .channel_regs_addr_i   (channel_regs_addr_w         ),
            .channel_regs_wr_data_i(apu_wr_data_i               ),

            .channel_start_i       (dmc_channel_start_w         ),
            .channel_enabled_i     (dmc_channel_enabled_w       ),
            .channel_irq_clear_i   (dmc_channel_irq_clear_w     ),
            .channel_is_active_o   (dmc_channel_is_active_w     ),
            .channel_output_o      (dmc_channel_output_w        ),
            .channel_irq_o         (dmc_channel_irq_w           ),

            .dmc_dma_exe_o         (dmc_dma_exe_o               ),
            .dmc_dma_addr_o        (dmc_dma_addr_o              ),
            .dmc_dma_rd_i          (dmc_dma_rd_i                ),
            .dmc_dma_rd_data_i     (dmc_dma_rd_data_i           )
        );


    // Логика "смешивания" данных каналов и формирования PCM выхода
    always @(posedge clk_i)
        if   (rst_i) apu_output_r <= 15'h0;
        else         apu_output_r <= apu_output_next_w;

    assign apu_output_dsm_extend_w = {1'b0, apu_output_r};

    assign pulse_channels_output_w = pulse1_channel_output_w + pulse2_channel_output_w;
    assign tnd_channels_output_w   = triangle_channel_output_w + noise_channel_output_w + dmc_channel_output_w;

    assign apu_output_next_w       = pulse_lut_output_r + tnd_lut_output_r;

    always @(posedge clk_i)
        case (pulse_channels_output_w)
            5'h00:   pulse_lut_output_r = 15'd0;
            5'h01:   pulse_lut_output_r = 15'd380;
            5'h02:   pulse_lut_output_r = 15'd752;
            5'h03:   pulse_lut_output_r = 15'd1114;
            5'h04:   pulse_lut_output_r = 15'd1468;
            5'h05:   pulse_lut_output_r = 15'd1814;
            5'h06:   pulse_lut_output_r = 15'd2152;
            5'h07:   pulse_lut_output_r = 15'd2482;
            5'h08:   pulse_lut_output_r = 15'd2805;
            5'h09:   pulse_lut_output_r = 15'd3120;
            5'h0A:   pulse_lut_output_r = 15'd3429;
            5'h0B:   pulse_lut_output_r = 15'd3731;
            5'h0C:   pulse_lut_output_r = 15'd4027;
            5'h0D:   pulse_lut_output_r = 15'd4316;
            5'h0E:   pulse_lut_output_r = 15'd4599;
            5'h0F:   pulse_lut_output_r = 15'd4876;
            5'h10:   pulse_lut_output_r = 15'd5148;
            5'h11:   pulse_lut_output_r = 15'd5414;
            5'h12:   pulse_lut_output_r = 15'd5675;
            5'h13:   pulse_lut_output_r = 15'd5930;
            5'h14:   pulse_lut_output_r = 15'd6181;
            5'h15:   pulse_lut_output_r = 15'd6426;
            5'h16:   pulse_lut_output_r = 15'd6667;
            5'h17:   pulse_lut_output_r = 15'd6904;
            5'h18:   pulse_lut_output_r = 15'd7135;
            5'h19:   pulse_lut_output_r = 15'd7363;
            5'h1A:   pulse_lut_output_r = 15'd7586;
            5'h1B:   pulse_lut_output_r = 15'd7805;
            5'h1C:   pulse_lut_output_r = 15'd8020;
            5'h1D:   pulse_lut_output_r = 15'd8231;
            5'h1E:   pulse_lut_output_r = 15'd8438;
            5'h1F:   pulse_lut_output_r = 15'd0;
        endcase

    always @(posedge clk_i)
        case (tnd_channels_output_w)
            8'h00:   tnd_lut_output_r   = 15'd0;
            8'h01:   tnd_lut_output_r   = 15'd220;
            8'h02:   tnd_lut_output_r   = 15'd437;
            8'h03:   tnd_lut_output_r   = 15'd653;
            8'h04:   tnd_lut_output_r   = 15'd868;
            8'h05:   tnd_lut_output_r   = 15'd1080;
            8'h06:   tnd_lut_output_r   = 15'd1291;
            8'h07:   tnd_lut_output_r   = 15'd1500;
            8'h08:   tnd_lut_output_r   = 15'd1707;
            8'h09:   tnd_lut_output_r   = 15'd1913;
            8'h0A:   tnd_lut_output_r   = 15'd2117;
            8'h0B:   tnd_lut_output_r   = 15'd2320;
            8'h0C:   tnd_lut_output_r   = 15'd2521;
            8'h0D:   tnd_lut_output_r   = 15'd2720;
            8'h0E:   tnd_lut_output_r   = 15'd2918;
            8'h0F:   tnd_lut_output_r   = 15'd3115;
            8'h10:   tnd_lut_output_r   = 15'd3309;
            8'h11:   tnd_lut_output_r   = 15'd3503;
            8'h12:   tnd_lut_output_r   = 15'd3695;
            8'h13:   tnd_lut_output_r   = 15'd3885;
            8'h14:   tnd_lut_output_r   = 15'd4074;
            8'h15:   tnd_lut_output_r   = 15'd4261;
            8'h16:   tnd_lut_output_r   = 15'd4448;
            8'h17:   tnd_lut_output_r   = 15'd4632;
            8'h18:   tnd_lut_output_r   = 15'd4816;
            8'h19:   tnd_lut_output_r   = 15'd4998;
            8'h1A:   tnd_lut_output_r   = 15'd5178;
            8'h1B:   tnd_lut_output_r   = 15'd5357;
            8'h1C:   tnd_lut_output_r   = 15'd5535;
            8'h1D:   tnd_lut_output_r   = 15'd5712;
            8'h1E:   tnd_lut_output_r   = 15'd5887;
            8'h1F:   tnd_lut_output_r   = 15'd6061;
            8'h20:   tnd_lut_output_r   = 15'd6234;
            8'h21:   tnd_lut_output_r   = 15'd6406;
            8'h22:   tnd_lut_output_r   = 15'd6576;
            8'h23:   tnd_lut_output_r   = 15'd6745;
            8'h24:   tnd_lut_output_r   = 15'd6913;
            8'h25:   tnd_lut_output_r   = 15'd7080;
            8'h26:   tnd_lut_output_r   = 15'd7245;
            8'h27:   tnd_lut_output_r   = 15'd7409;
            8'h28:   tnd_lut_output_r   = 15'd7573;
            8'h29:   tnd_lut_output_r   = 15'd7735;
            8'h2A:   tnd_lut_output_r   = 15'd7896;
            8'h2B:   tnd_lut_output_r   = 15'd8055;
            8'h2C:   tnd_lut_output_r   = 15'd8214;
            8'h2D:   tnd_lut_output_r   = 15'd8371;
            8'h2E:   tnd_lut_output_r   = 15'd8528;
            8'h2F:   tnd_lut_output_r   = 15'd8683;
            8'h30:   tnd_lut_output_r   = 15'd8838;
            8'h31:   tnd_lut_output_r   = 15'd8991;
            8'h32:   tnd_lut_output_r   = 15'd9143;
            8'h33:   tnd_lut_output_r   = 15'd9294;
            8'h34:   tnd_lut_output_r   = 15'd9444;
            8'h35:   tnd_lut_output_r   = 15'd9594;
            8'h36:   tnd_lut_output_r   = 15'd9742;
            8'h37:   tnd_lut_output_r   = 15'd9889;
            8'h38:   tnd_lut_output_r   = 15'd10035;
            8'h39:   tnd_lut_output_r   = 15'd10180;
            8'h3A:   tnd_lut_output_r   = 15'd10324;
            8'h3B:   tnd_lut_output_r   = 15'd10468;
            8'h3C:   tnd_lut_output_r   = 15'd10610;
            8'h3D:   tnd_lut_output_r   = 15'd10751;
            8'h3E:   tnd_lut_output_r   = 15'd10892;
            8'h3F:   tnd_lut_output_r   = 15'd11031;
            8'h40:   tnd_lut_output_r   = 15'd11170;
            8'h41:   tnd_lut_output_r   = 15'd11308;
            8'h42:   tnd_lut_output_r   = 15'd11445;
            8'h43:   tnd_lut_output_r   = 15'd11580;
            8'h44:   tnd_lut_output_r   = 15'd11716;
            8'h45:   tnd_lut_output_r   = 15'd11850;
            8'h46:   tnd_lut_output_r   = 15'd11983;
            8'h47:   tnd_lut_output_r   = 15'd12116;
            8'h48:   tnd_lut_output_r   = 15'd12247;
            8'h49:   tnd_lut_output_r   = 15'd12378;
            8'h4A:   tnd_lut_output_r   = 15'd12508;
            8'h4B:   tnd_lut_output_r   = 15'd12637;
            8'h4C:   tnd_lut_output_r   = 15'd12766;
            8'h4D:   tnd_lut_output_r   = 15'd12893;
            8'h4E:   tnd_lut_output_r   = 15'd13020;
            8'h4F:   tnd_lut_output_r   = 15'd13146;
            8'h50:   tnd_lut_output_r   = 15'd13271;
            8'h51:   tnd_lut_output_r   = 15'd13396;
            8'h52:   tnd_lut_output_r   = 15'd13520;
            8'h53:   tnd_lut_output_r   = 15'd13642;
            8'h54:   tnd_lut_output_r   = 15'd13765;
            8'h55:   tnd_lut_output_r   = 15'd13886;
            8'h56:   tnd_lut_output_r   = 15'd14007;
            8'h57:   tnd_lut_output_r   = 15'd14127;
            8'h58:   tnd_lut_output_r   = 15'd14246;
            8'h59:   tnd_lut_output_r   = 15'd14365;
            8'h5A:   tnd_lut_output_r   = 15'd14482;
            8'h5B:   tnd_lut_output_r   = 15'd14599;
            8'h5C:   tnd_lut_output_r   = 15'd14716;
            8'h5D:   tnd_lut_output_r   = 15'd14832;
            8'h5E:   tnd_lut_output_r   = 15'd14947;
            8'h5F:   tnd_lut_output_r   = 15'd15061;
            8'h60:   tnd_lut_output_r   = 15'd15175;
            8'h61:   tnd_lut_output_r   = 15'd15288;
            8'h62:   tnd_lut_output_r   = 15'd15400;
            8'h63:   tnd_lut_output_r   = 15'd15512;
            8'h64:   tnd_lut_output_r   = 15'd15623;
            8'h65:   tnd_lut_output_r   = 15'd15733;
            8'h66:   tnd_lut_output_r   = 15'd15843;
            8'h67:   tnd_lut_output_r   = 15'd15952;
            8'h68:   tnd_lut_output_r   = 15'd16061;
            8'h69:   tnd_lut_output_r   = 15'd16168;
            8'h6A:   tnd_lut_output_r   = 15'd16276;
            8'h6B:   tnd_lut_output_r   = 15'd16382;
            8'h6C:   tnd_lut_output_r   = 15'd16488;
            8'h6D:   tnd_lut_output_r   = 15'd16594;
            8'h6E:   tnd_lut_output_r   = 15'd16699;
            8'h6F:   tnd_lut_output_r   = 15'd16803;
            8'h70:   tnd_lut_output_r   = 15'd16907;
            8'h71:   tnd_lut_output_r   = 15'd17010;
            8'h72:   tnd_lut_output_r   = 15'd17112;
            8'h73:   tnd_lut_output_r   = 15'd17214;
            8'h74:   tnd_lut_output_r   = 15'd17315;
            8'h75:   tnd_lut_output_r   = 15'd17416;
            8'h76:   tnd_lut_output_r   = 15'd17516;
            8'h77:   tnd_lut_output_r   = 15'd17616;
            8'h78:   tnd_lut_output_r   = 15'd17715;
            8'h79:   tnd_lut_output_r   = 15'd17814;
            8'h7A:   tnd_lut_output_r   = 15'd17912;
            8'h7B:   tnd_lut_output_r   = 15'd18009;
            8'h7C:   tnd_lut_output_r   = 15'd18106;
            8'h7D:   tnd_lut_output_r   = 15'd18203;
            8'h7E:   tnd_lut_output_r   = 15'd18299;
            8'h7F:   tnd_lut_output_r   = 15'd18394;
            8'h80:   tnd_lut_output_r   = 15'd18489;
            8'h81:   tnd_lut_output_r   = 15'd18583;
            8'h82:   tnd_lut_output_r   = 15'd18677;
            8'h83:   tnd_lut_output_r   = 15'd18771;
            8'h84:   tnd_lut_output_r   = 15'd18864;
            8'h85:   tnd_lut_output_r   = 15'd18956;
            8'h86:   tnd_lut_output_r   = 15'd19048;
            8'h87:   tnd_lut_output_r   = 15'd19139;
            8'h88:   tnd_lut_output_r   = 15'd19230;
            8'h89:   tnd_lut_output_r   = 15'd19321;
            8'h8A:   tnd_lut_output_r   = 15'd19411;
            8'h8B:   tnd_lut_output_r   = 15'd19500;
            8'h8C:   tnd_lut_output_r   = 15'd19589;
            8'h8D:   tnd_lut_output_r   = 15'd19678;
            8'h8E:   tnd_lut_output_r   = 15'd19766;
            8'h8F:   tnd_lut_output_r   = 15'd19854;
            8'h90:   tnd_lut_output_r   = 15'd19941;
            8'h91:   tnd_lut_output_r   = 15'd20028;
            8'h92:   tnd_lut_output_r   = 15'd20114;
            8'h93:   tnd_lut_output_r   = 15'd20200;
            8'h94:   tnd_lut_output_r   = 15'd20285;
            8'h95:   tnd_lut_output_r   = 15'd20370;
            8'h96:   tnd_lut_output_r   = 15'd20455;
            8'h97:   tnd_lut_output_r   = 15'd20539;
            8'h98:   tnd_lut_output_r   = 15'd20623;
            8'h99:   tnd_lut_output_r   = 15'd20706;
            8'h9A:   tnd_lut_output_r   = 15'd20789;
            8'h9B:   tnd_lut_output_r   = 15'd20871;
            8'h9C:   tnd_lut_output_r   = 15'd20953;
            8'h9D:   tnd_lut_output_r   = 15'd21035;
            8'h9E:   tnd_lut_output_r   = 15'd21116;
            8'h9F:   tnd_lut_output_r   = 15'd21197;
            8'hA0:   tnd_lut_output_r   = 15'd21278;
            8'hA1:   tnd_lut_output_r   = 15'd21358;
            8'hA2:   tnd_lut_output_r   = 15'd21437;
            8'hA3:   tnd_lut_output_r   = 15'd21516;
            8'hA4:   tnd_lut_output_r   = 15'd21595;
            8'hA5:   tnd_lut_output_r   = 15'd21674;
            8'hA6:   tnd_lut_output_r   = 15'd21752;
            8'hA7:   tnd_lut_output_r   = 15'd21830;
            8'hA8:   tnd_lut_output_r   = 15'd21907;
            8'hA9:   tnd_lut_output_r   = 15'd21984;
            8'hAA:   tnd_lut_output_r   = 15'd22060;
            8'hAB:   tnd_lut_output_r   = 15'd22137;
            8'hAC:   tnd_lut_output_r   = 15'd22212;
            8'hAD:   tnd_lut_output_r   = 15'd22288;
            8'hAE:   tnd_lut_output_r   = 15'd22363;
            8'hAF:   tnd_lut_output_r   = 15'd22438;
            8'hB0:   tnd_lut_output_r   = 15'd22512;
            8'hB1:   tnd_lut_output_r   = 15'd22586;
            8'hB2:   tnd_lut_output_r   = 15'd22660;
            8'hB3:   tnd_lut_output_r   = 15'd22733;
            8'hB4:   tnd_lut_output_r   = 15'd22806;
            8'hB5:   tnd_lut_output_r   = 15'd22879;
            8'hB6:   tnd_lut_output_r   = 15'd22951;
            8'hB7:   tnd_lut_output_r   = 15'd23023;
            8'hB8:   tnd_lut_output_r   = 15'd23095;
            8'hB9:   tnd_lut_output_r   = 15'd23166;
            8'hBA:   tnd_lut_output_r   = 15'd23237;
            8'hBB:   tnd_lut_output_r   = 15'd23308;
            8'hBC:   tnd_lut_output_r   = 15'd23378;
            8'hBD:   tnd_lut_output_r   = 15'd23448;
            8'hBE:   tnd_lut_output_r   = 15'd23518;
            8'hBF:   tnd_lut_output_r   = 15'd23587;
            8'hC0:   tnd_lut_output_r   = 15'd23656;
            8'hC1:   tnd_lut_output_r   = 15'd23725;
            8'hC2:   tnd_lut_output_r   = 15'd23793;
            8'hC3:   tnd_lut_output_r   = 15'd23861;
            8'hC4:   tnd_lut_output_r   = 15'd23929;
            8'hC5:   tnd_lut_output_r   = 15'd23996;
            8'hC6:   tnd_lut_output_r   = 15'd24064;
            8'hC7:   tnd_lut_output_r   = 15'd24130;
            8'hC8:   tnd_lut_output_r   = 15'd24197;
            8'hC9:   tnd_lut_output_r   = 15'd24263;
            8'hCA:   tnd_lut_output_r   = 15'd24329;
            default: tnd_lut_output_r   = 15'd0;
        endcase


    // Выходы
    assign apu_output_o          = apu_output_dsm_extend_w;
    assign apu_rd_data_o         = apu_rd_data_w;
    assign apu_frame_irq_o       = frame_irq_r;
    assign apu_dmc_channel_irq_o = dmc_channel_irq_w;


endmodule
