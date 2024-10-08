
/*
 * Description : SD-card controller module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module sd_card_controller
    (
        input  wire        clk_i,                   // Сигнал тактирования
        input  wire        rst_i,                   // Сигнал сброса

        output wire        spi_clk_o,               // Сигнал тактирования SPI
        output wire        spi_ncs_o,               // Сигнал выбора ведомого SPI
        output wire        spi_ncs_en_o,            // Сигнал активации выхода выбора ведомого (управление буфером с 3-им состоянием)
        output wire        spi_mosi_o,              // Сигнал данных от ведущего к ведомому SPI
        output wire        spi_mosi_en_o,           // Сигнал активации выхода данных от ведущего (управление буфером с 3-им состоянием)
        input  wire        spi_miso_i,              // Сигнал данных от ведомого ведущему

        output wire        sd_disable_o,            // Сигнал выключения питания SD-карты
        output wire        sd_clk_full_speed_o,     // Сигнал активации полноскоростного тактирования контроллера sd-карт
        output wire        sd_is_idle_o,            // Контроллер SD-карт в состоянии ожидания новых транзакций
        output wire        sd_cmd_result_is_ok_o,   // Выполнение команды завершено корректно
        output wire        sd_data_byte_received_o, // Сигнал получения (валидности) очередного байта данных (приём данных)
        output wire [ 7:0] sd_data_byte_o,          // Очередной прочитанный байт данных (приём данных)
        output wire [ 8:0] sd_data_counter_o,       // Счётчик прочитанных байт данных (приём данных)
        input  wire [31:0] sd_block_addr_i,         // Адрес блока SD-карты для чтения данных из него
        input  wire        sd_start_block_read_i,   // Начать чтения блока данных SD-карты
        input  wire        sd_read_finished_i       // Считывание всех необходимых данных из SD-карты закончено
    );


    // Состояния конечного автомата
    localparam [ 4:0] POWER_ON               = 0,
                      PREPARE_CLK_LAUNCH     = 1,
                      EXECUTING_CLK_LAUNCH   = 2,
                      PREPARE_CMD0           = 3,
                      EXECUTING_CMD0         = 4,
                      CHECK_CMD0_RESPONSE    = 5,
                      PREPARE_CMD8           = 6,
                      EXECUTING_CMD8         = 7,
                      CHECK_CMD8_RESPONSE    = 8,
                      PREPARE_CMD59          = 9,
                      EXECUTING_CMD59        = 10,
                      CHECK_CMD59_RESPONSE   = 11,
                      PREPARE_CMD58_1        = 12,
                      EXECUTING_CMD58_1      = 13,
                      CHECK_CMD58_1_RESPONSE = 14,
                      PREPARE_CMD55          = 15,
                      EXECUTING_CMD55        = 16,
                      CHECK_CMD55_RESPONSE   = 17,
                      PREPARE_ACMD41         = 18,
                      EXECUTING_ACMD41       = 19,
                      CHECK_ACMD41_RESPONSE  = 20,
                      PREPARE_CMD58_2        = 21,
                      EXECUTING_CMD58_2      = 22,
                      CHECK_CMD58_2_RESPONSE = 23,
                      IDLE                   = 24,
                      ENABLE_CLK_FULL_SPEED  = 25,
                      PREPARE_CMD17          = 26,
                      EXECUTING_CMD17        = 27,
                      CHECK_CMD17_RESPONSE   = 28,
                      UNEXPECTED_RESULT      = 29,
                      INIT_ERROR             = 30,
                      POWER_OFF              = 31;

    // Типы ответов на команды для SD-карты
    localparam [ 2:0] NO_RESPONSE            = 0,
                      R1_RESPONSE            = 1,
                      R2_RESPONSE            = 2,
                      R3_RESPONSE            = 3,
                      R7_RESPONSE            = 7;

    // Код исполняемы команд SD-карт
    localparam [39:0] CMD0_AND_ARGUMENTS     = 40'h40_00_00_00_00;
    localparam [39:0] CMD8_AND_ARGUMENTS     = 40'h48_00_00_01_AA;
    localparam [39:0] CMD59_AND_ARGUMENTS    = 40'h7B_00_00_00_01;
    localparam [39:0] CMD58_AND_ARGUMENTS    = 40'h7A_00_00_00_00;
    localparam [39:0] CMD55_AND_ARGUMENTS    = 40'h77_00_00_00_00;
    localparam [39:0] ACMD41_AND_ARGUMENTS   = 40'h69_40_00_00_00;
    localparam [39:0] CMD17_NO_ARGUMENTS     = 40'h51_00_00_00_00;


    // Сигналы конечного автомата
    reg  [ 4:0] state_r;
    reg  [ 4:0] state_next_r;

    wire        prepare_launch_sn_w;
    wire        check_acmd41_response_sn_w;
    wire        idle_sn_w;
    wire        power_off_sn_w;
    wire        enable_clk_full_speed_sn_w;

    // Конфигурирование отправляемой команды
    reg  [39:0] cmd_data_r;
    reg  [39:0] cmd_data_next_r;
    reg  [ 2:0] response_type_r;
    reg  [ 2:0] response_type_next_r;
    reg         ncs_enable_r;
    reg         ncs_enable_next_r;
    reg         expecting_data_r;
    reg         expecting_data_next_r;
    reg         start_transferring_r;
    reg         start_transferring_next_r;

    // Сигналы состояния SDSPI котнроллера
    wire        sdspi_is_idle_w;
    wire [39:0] sdspi_response_w;
    wire        sdspi_response_is_ok_w;
    wire        sdspi_token_is_ok_w;
    wire        sdspi_data_crc_is_ok_w;

    // Сигналы чтения данных из SD-карты
    reg         start_block_read_r;
    reg         start_block_read_next_r;
    reg  [31:0] block_addr_r;
    wire [31:0] block_addr_next_w;
    reg         read_finished_r;
    wire        read_finished_next_w;

    // Сигналы управления и состояния SD-карты
    wire        power_good_w;
    wire        not_power_good_w;
    reg  [15:0] pwrg_counter_r;
    wire [15:0] pwrg_counter_next_w;
    reg         clk_launch_bit_r;
    wire        clk_launch_bit_next_w;
    reg         sd_disable_r;
    wire        sd_disable_next_w;
    reg         cmd_resut_is_ok_r;
    reg         cmd_result_is_ok_next_r;
    reg         init_completed_r;
    wire        init_completed_next_w;
    reg         sd_clk_full_speed_r;
    wire        sd_clk_full_speed_next_w;

    wire        cmd8_voltage_accepted_w;
    wire        acmd41_sd_is_ready_w;
    wire        cmd58_1_ocr_vdd_is_ok_w;
    wire        cmd58_2_ocr_power_hc_is_ok_w;
    wire        cmd58_ocr_ccs_bit_w;


    // Инициализация питания
    always @(posedge clk_i)
        if (rst_i) begin
            pwrg_counter_r   <= 16'h0;
            clk_launch_bit_r <= 1'b1;
        end else begin
            pwrg_counter_r   <= pwrg_counter_next_w;
            clk_launch_bit_r <= clk_launch_bit_next_w;
        end

    assign power_good_w          = pwrg_counter_r[15];
    assign not_power_good_w      = ~power_good_w;
    assign pwrg_counter_next_w   = pwrg_counter_r + not_power_good_w;
    assign clk_launch_bit_next_w = (prepare_launch_sn_w) ? ~clk_launch_bit_r : clk_launch_bit_r;


    // Конечный автомат
    always @(posedge clk_i)
        if   (rst_i) state_r <= 5'h0;
        else         state_r <= state_next_r;

    wire [1:0] state_next_st_2_case_w  = {sdspi_is_idle_w, clk_launch_bit_r};
    wire [1:0] state_next_st_17_case_w = {cmd_resut_is_ok_r, init_completed_r};
    wire [1:0] state_next_st_21_case_w = {start_block_read_r, read_finished_r};
    always @(*)
        case (state_r)

            POWER_ON:                          state_next_r = (power_good_w) ? PREPARE_CLK_LAUNCH : POWER_ON;

            PREPARE_CLK_LAUNCH:                state_next_r = EXECUTING_CLK_LAUNCH;

            EXECUTING_CLK_LAUNCH:
                case (state_next_st_2_case_w)
                    2'b11:                     state_next_r = PREPARE_CMD0;
                    2'b10:                     state_next_r = PREPARE_CLK_LAUNCH;
                    default:                   state_next_r = EXECUTING_CLK_LAUNCH;
                endcase

            PREPARE_CMD0:                      state_next_r = EXECUTING_CMD0;

            EXECUTING_CMD0:                    state_next_r = (sdspi_is_idle_w) ? CHECK_CMD0_RESPONSE : EXECUTING_CMD0;

            CHECK_CMD0_RESPONSE:               state_next_r = (cmd_resut_is_ok_r) ? PREPARE_CMD8 : INIT_ERROR;

            PREPARE_CMD8:                      state_next_r = EXECUTING_CMD8;

            EXECUTING_CMD8:                    state_next_r = (sdspi_is_idle_w) ? CHECK_CMD8_RESPONSE : EXECUTING_CMD8;

            CHECK_CMD8_RESPONSE:               state_next_r = (cmd_resut_is_ok_r) ? PREPARE_CMD59 : INIT_ERROR;

            PREPARE_CMD59:                     state_next_r = EXECUTING_CMD59;

            EXECUTING_CMD59:                   state_next_r = (sdspi_is_idle_w) ? CHECK_CMD59_RESPONSE :
                                                                                  EXECUTING_CMD59;

            CHECK_CMD59_RESPONSE:              state_next_r = (cmd_resut_is_ok_r) ? PREPARE_CMD58_1 : INIT_ERROR;

            PREPARE_CMD58_1:                   state_next_r = EXECUTING_CMD58_1;

            EXECUTING_CMD58_1:                 state_next_r = (sdspi_is_idle_w) ? CHECK_CMD58_1_RESPONSE :
                                                                                  EXECUTING_CMD58_1;

            CHECK_CMD58_1_RESPONSE:            state_next_r = (cmd_resut_is_ok_r) ? PREPARE_CMD55 : INIT_ERROR;

            PREPARE_CMD55:                     state_next_r = EXECUTING_CMD55;

            EXECUTING_CMD55:                   state_next_r = (sdspi_is_idle_w) ? CHECK_CMD55_RESPONSE :
                                                                                  EXECUTING_CMD55;

            CHECK_CMD55_RESPONSE:              state_next_r = (cmd_resut_is_ok_r) ? PREPARE_ACMD41 : INIT_ERROR;

            PREPARE_ACMD41:                    state_next_r = EXECUTING_ACMD41;

            EXECUTING_ACMD41:                  state_next_r = (sdspi_is_idle_w) ? CHECK_ACMD41_RESPONSE :
                                                                                  EXECUTING_ACMD41;

            CHECK_ACMD41_RESPONSE:
                case (state_next_st_17_case_w)
                    2'b11:                     state_next_r = PREPARE_CMD58_2;
                    2'b10:                     state_next_r = PREPARE_CMD55;
                    default:                   state_next_r = INIT_ERROR;
                endcase

            PREPARE_CMD58_2:                   state_next_r = EXECUTING_CMD58_2;

            EXECUTING_CMD58_2:                 state_next_r = (sdspi_is_idle_w) ? CHECK_CMD58_2_RESPONSE :
                                                                                  EXECUTING_CMD58_2;

            CHECK_CMD58_2_RESPONSE:            state_next_r = (cmd_resut_is_ok_r) ? ENABLE_CLK_FULL_SPEED : INIT_ERROR;

            ENABLE_CLK_FULL_SPEED:             state_next_r = IDLE;

            IDLE:
                case (state_next_st_21_case_w)
                    2'b10:                     state_next_r = PREPARE_CMD17;
                    2'b01:                     state_next_r = POWER_OFF;
                    default:                   state_next_r = IDLE;
                endcase

            PREPARE_CMD17:                     state_next_r = EXECUTING_CMD17;

            EXECUTING_CMD17:                   state_next_r = (sdspi_is_idle_w) ? CHECK_CMD17_RESPONSE :
                                                                                  EXECUTING_CMD17;

            CHECK_CMD17_RESPONSE:              state_next_r = (cmd_resut_is_ok_r) ? IDLE : UNEXPECTED_RESULT;

            UNEXPECTED_RESULT:                 state_next_r = IDLE;

            INIT_ERROR:                        state_next_r = POWER_OFF;

            POWER_OFF:                         state_next_r = POWER_OFF;

            default:                           state_next_r = state_r;

        endcase


    assign prepare_launch_sn_w         = (state_next_r == PREPARE_CLK_LAUNCH);
    assign check_acmd41_response_sn_w  = (state_next_r == CHECK_ACMD41_RESPONSE);
    assign idle_sn_w                   = (state_next_r == IDLE);
    assign power_off_sn_w              = (state_next_r == POWER_OFF);
    assign enable_clk_full_speed_sn_w  = (state_next_r == ENABLE_CLK_FULL_SPEED);


    // Управление чтением данных с SD-карты
    always @(posedge clk_i)
        begin
            start_block_read_r <= start_block_read_next_r;
            block_addr_r       <= block_addr_next_w;
            read_finished_r    <= read_finished_next_w;
        end

    assign block_addr_next_w    = (idle_sn_w) ? sd_block_addr_i : block_addr_r;
    assign read_finished_next_w = sd_read_finished_i;

    always @(*)
        case (state_next_r)
            IDLE:          start_block_read_next_r = sd_start_block_read_i;
            PREPARE_CMD17: start_block_read_next_r = 1'b0;
            default:       start_block_read_next_r = 1'b0;
        endcase


    // Формирование отправляемой в SD-карты команды
    always @(posedge clk_i)
        if (rst_i) begin
            start_transferring_r <= 1'b0;
        end else begin
            start_transferring_r <= start_transferring_next_r;
        end

    always @(posedge clk_i)
        begin
            cmd_data_r           <= cmd_data_next_r;
            response_type_r      <= response_type_next_r;
            expecting_data_r     <= expecting_data_next_r;
            ncs_enable_r         <= ncs_enable_next_r;
        end

    always @(*)
        case (state_next_r)
            IDLE, UNEXPECTED_RESULT: begin
                cmd_data_next_r           = {40{1'b1}};
                response_type_next_r      = NO_RESPONSE;
                expecting_data_next_r     = 1'b0;
                ncs_enable_next_r         = 1'b0;
                start_transferring_next_r = 1'b0;
            end
            PREPARE_CLK_LAUNCH: begin
                cmd_data_next_r           = {40{1'b1}};
                response_type_next_r      = NO_RESPONSE;
                expecting_data_next_r     = 1'b0;
                ncs_enable_next_r         = 1'b0;
                start_transferring_next_r = 1'b1;
            end
            PREPARE_CMD0: begin
                cmd_data_next_r           = CMD0_AND_ARGUMENTS;
                response_type_next_r      = R1_RESPONSE;
                expecting_data_next_r     = 1'b0;
                ncs_enable_next_r         = 1'b1;
                start_transferring_next_r = 1'b1;
            end
            PREPARE_CMD8: begin
                cmd_data_next_r           = CMD8_AND_ARGUMENTS;
                response_type_next_r      = R7_RESPONSE;
                expecting_data_next_r     = 1'b0;
                ncs_enable_next_r         = 1'b1;
                start_transferring_next_r = 1'b1;
            end
            PREPARE_CMD59: begin
                cmd_data_next_r           = CMD59_AND_ARGUMENTS;
                response_type_next_r      = R1_RESPONSE;
                expecting_data_next_r     = 1'b0;
                ncs_enable_next_r         = 1'b1;
                start_transferring_next_r = 1'b1;
            end
            PREPARE_CMD55: begin
                cmd_data_next_r           = CMD55_AND_ARGUMENTS;
                response_type_next_r      = R1_RESPONSE;
                expecting_data_next_r     = 1'b0;
                ncs_enable_next_r         = 1'b1;
                start_transferring_next_r = 1'b1;
            end
            PREPARE_ACMD41: begin
                cmd_data_next_r           = ACMD41_AND_ARGUMENTS;
                response_type_next_r      = R1_RESPONSE;
                expecting_data_next_r     = 1'b0;
                ncs_enable_next_r         = 1'b1;
                start_transferring_next_r = 1'b1;
            end
            PREPARE_CMD58_1,
            PREPARE_CMD58_2: begin
                cmd_data_next_r           = CMD58_AND_ARGUMENTS;
                response_type_next_r      = R3_RESPONSE;
                expecting_data_next_r     = 1'b0;
                ncs_enable_next_r         = 1'b1;
                start_transferring_next_r = 1'b1;
            end
            PREPARE_CMD17: begin
                cmd_data_next_r           = {CMD17_NO_ARGUMENTS[39:32], block_addr_r};
                response_type_next_r      = R1_RESPONSE;
                expecting_data_next_r     = 1'b1;
                ncs_enable_next_r         = 1'b1;
                start_transferring_next_r = 1'b1;
            end
            default: begin
                cmd_data_next_r           = cmd_data_r;
                response_type_next_r      = response_type_r;
                expecting_data_next_r     = expecting_data_r;
                ncs_enable_next_r         = ncs_enable_r;
                start_transferring_next_r = 1'b0;
            end
        endcase


    // Управление состоянием SD-карты
    always @(posedge clk_i or posedge rst_i)
        if (rst_i) begin
            sd_disable_r        <= 1'b1;
        end else begin
            sd_disable_r        <= sd_disable_next_w;
        end

    always @(posedge clk_i)
        if (rst_i) begin
            init_completed_r    <= 1'b0;
            sd_clk_full_speed_r <= 1'b0;
        end else begin
            init_completed_r    <= init_completed_next_w;
            sd_clk_full_speed_r <= sd_clk_full_speed_next_w;
        end

    always @(posedge clk_i)
        begin
            cmd_resut_is_ok_r   <= cmd_result_is_ok_next_r;
        end

    assign cmd8_voltage_accepted_w      = (sdspi_response_w[11:0] == CMD8_AND_ARGUMENTS[11:0]);
    assign acmd41_sd_is_ready_w         = ~sdspi_response_w[0];
    assign cmd58_1_ocr_vdd_is_ok_w      = &sdspi_response_w[21:19];
    assign cmd58_2_ocr_power_hc_is_ok_w =  sdspi_response_w[31:30];
    assign cmd58_ocr_ccs_bit_w          =  sdspi_response_w[30];

    assign init_completed_next_w        = (check_acmd41_response_sn_w) ? acmd41_sd_is_ready_w : init_completed_r;
    assign sd_clk_full_speed_next_w     = (enable_clk_full_speed_sn_w) ? 1'b1                 : sd_clk_full_speed_r;

    assign sd_disable_next_w            = power_off_sn_w;

    always @(*)
        case (state_next_r)

            IDLE:                   cmd_result_is_ok_next_r = 1'b0;

            CHECK_CMD0_RESPONSE,
            CHECK_CMD59_RESPONSE,
            CHECK_CMD55_RESPONSE,
            CHECK_ACMD41_RESPONSE:  cmd_result_is_ok_next_r = sdspi_response_is_ok_w;

            CHECK_CMD8_RESPONSE:    cmd_result_is_ok_next_r = sdspi_response_is_ok_w && cmd8_voltage_accepted_w;

            CHECK_CMD58_1_RESPONSE: cmd_result_is_ok_next_r = sdspi_response_is_ok_w && cmd58_1_ocr_vdd_is_ok_w;

            CHECK_CMD58_2_RESPONSE: cmd_result_is_ok_next_r = sdspi_response_is_ok_w && cmd58_2_ocr_power_hc_is_ok_w;

            CHECK_CMD17_RESPONSE:   cmd_result_is_ok_next_r = sdspi_response_is_ok_w && sdspi_token_is_ok_w &&
                                                              sdspi_data_crc_is_ok_w;

            default:                cmd_result_is_ok_next_r = cmd_resut_is_ok_r;

        endcase


    // Логика SDSPI контрллера
    sdspi_controller
        sdspi_controller
        (
            .clk_i                     (clk_i                  ),
            .rst_i                     (rst_i                  ),

            .spi_clk_o                 (spi_clk_o              ),
            .spi_ncs_o                 (spi_ncs_o              ),
            .spi_ncs_en_o              (spi_ncs_en_o           ),
            .spi_mosi_o                (spi_mosi_o             ),
            .spi_mosi_en_o             (spi_mosi_en_o          ),
            .spi_miso_i                (spi_miso_i             ),

            .phy_ncs_enable_i          (ncs_enable_r           ),

            .sd_start_transferring_i   (start_transferring_r   ),
            .sd_response_type_i        (response_type_r        ),
            .sd_expecting_data_i       (expecting_data_r       ),
            .sd_cmd_data_i             (cmd_data_r             ),

            .sdspi_is_idle_o           (sdspi_is_idle_w        ),
            .sdspi_response_o          (sdspi_response_w       ),
            .sdspi_response_is_ok_o    (sdspi_response_is_ok_w ),
            .sdspi_token_is_ok_o       (sdspi_token_is_ok_w    ),
            .sdspi_data_crc_is_ok_o    (sdspi_data_crc_is_ok_w ),
            .sdspi_data_byte_received_o(sd_data_byte_received_o),
            .sdspi_data_byte_o         (sd_data_byte_o         ),
            .sdspi_data_counter_o      (sd_data_counter_o      )
        );


    // Выходы
    assign sd_disable_o          = sd_disable_r;
    assign sd_clk_full_speed_o   = sd_clk_full_speed_r;
    assign sd_is_idle_o          = idle_sn_w;
    assign sd_cmd_result_is_ok_o = cmd_resut_is_ok_r;


endmodule
