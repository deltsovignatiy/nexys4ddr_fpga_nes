
/*
 * Description : SDSPI controller (data link layer) module for SD-card controller
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module sdspi_controller
    (
        input  wire        clk_i,                      // Сигнал тактирования
        input  wire        rst_i,                      // Сигнал сброса

        output wire        spi_clk_o,                  // Сигнал тактирования SPI
        output wire        spi_ncs_o,                  // Сигнал выбора ведомого SPI
        output wire        spi_ncs_en_o,               // Сигнал активации выхода выбора ведомого (управление буфером с 3-им состоянием)
        output wire        spi_mosi_o,                 // Сигнал данных от ведущего к ведомому SPI
        output wire        spi_mosi_en_o,              // Сигнал активации выхода данных от ведущего (управление буфером с 3-им состоянием)
        input  wire        spi_miso_i,                 // Сигнал данных от ведомого к ведущему SPI
        input  wire        phy_ncs_enable_i,           // Сигнал разрешения физ-уровню SPI активировать линии "chip select"

        input  wire        sd_start_transferring_i,    // Сигнал начала транзакции на SDSPI интерфейсе
        input  wire [ 2:0] sd_response_type_i,         // Тип ожидаемого ответа на отправляемую команду
        input  wire        sd_expecting_data_i,        // Ожидаются ли данные в ответе на команду
        input  wire [39:0] sd_cmd_data_i,              // Отправляемая команда SD-карте

        output wire        sdspi_is_idle_o,            // Контроллер SDSPI ноходится в состоянии ожидания новых транзакций
        output wire [39:0] sdspi_response_o,           // Полученный ответ на команду
        output wire        sdspi_response_is_ok_o,     // Полученный на команду ответ ожидаемый
        output wire        sdspi_token_is_ok_o,        // Токен данных при их чтении ожидаемый
        output wire        sdspi_data_crc_is_ok_o,     // CRC данных при их чтении верен
        output wire        sdspi_data_byte_received_o, // Сигнал получения (валидности) очередного байта данных
        output wire [ 7:0] sdspi_data_byte_o,          // Очередной прочитанный байт данных
        output wire [ 8:0] sdspi_data_counter_o        // Счётчик прочитанных байт данных
    );


    // Состояния конечного автомата
    localparam [3:0] IDLE                   = 0,
                     START_TRANSFERRING     = 1,
                     TRANSMITTING_CMD       = 2,
                     RECEIVING_RESPONSE     = 3,
                     CHECK_RESPONSE         = 4,
                     RECEIVING_TOKEN        = 5,
                     CHECK_TOKEN            = 6,
                     RECEIVING_DATA         = 7,
                     CHECK_DATA             = 8,
                     STOP_TRANSFERRING      = 9,
                     TIMEOUT                = 10,
                     RESPONSE_ERROR         = 11,
                     TOKEN_ERROR            = 12,
                     DATA_ERROR             = 13;

    // Типы ответов на команды для SD-карты
    localparam [2:0] NO_RESPONSE            = 0,
                     R1_RESPONSE            = 1,
                     R2_RESPONSE            = 2,
                     R3_RESPONSE            = 3,
                     R7_RESPONSE            = 7;

    // Количество бит, отправляемых при выдаче SD-карте команды
    localparam       CMD_BITS               = 48;

    // Количество принимаемых байт данных в соответствии с типом ответа
    localparam       NO_RESPONSE_BYTES      = 0;
    localparam       R1_RESPONSE_BYTES      = 1;
    localparam       R2_RESPONSE_BYTES      = 2;
    localparam       R3_RESPONSE_BYTES      = 5;
    localparam       R7_RESPONSE_BYTES      = 5;

    // Общее количество байт данных принимаемых при их чтении из SD-карты (данные + crc)
    localparam       DATA_AND_CRC_BYTES     = 514;

    // Таймауты на прием ответа и данных от SD-карты
    localparam       TIMEOUT_RESPONSE_BYTES = 15;
    localparam       TIMEOUT_DATA_BYTES     = 8191;


    // Конечный автомат
    reg  [ 3:0] state_r;
    reg  [ 3:0] state_next_r;

    wire        idle_sn_w;
    wire        transmitting_cmd_sn_w;
    wire        receiving_data_sn_w;
    wire        stop_transferring_ns_w;

    // Сигналы логики отправки команд
    reg         start_transferring_r;
    reg         start_transferring_next_r;
    wire        expecting_response_w;
    reg  [ 3:0] clocks_counter_r;
    reg  [ 3:0] clocks_counter_next_r;
    wire        start_clocks_completed_w;
    wire        stop_clocks_completed_w;
    wire [ 3:0] clocks_counter_incr_w;
    reg  [39:0] cmd_data_shifter_r;
    reg  [39:0] cmd_data_shifter_next_r;
    wire [39:0] cmd_data_shifted_w;
    reg  [ 5:0] cmd_counter_r;
    reg  [ 5:0] cmd_counter_next_r;
    wire [ 5:0] cmd_counter_decr_w;
    reg         cmd_transmitted_r;
    reg         cmd_transmitted_next_r;

    // Сигналы crc отправляемых команд
    wire        crc_7_data_bit_w;
    wire        crc_7_reset_w;
    wire        crc_7_data_bit_valid_w;
    wire        crc_7_shift_bit_out_w;
    wire        crc_7_out_bit_w;
    wire [ 6:0] crc_7_out_word_w;

    // Сигналы логики приёма данных и ответов
    reg  [ 5:0] response_size_r;
    reg  [13:0] response_flags_w;
    wire        response_is_ok_w;
    reg  [ 3:0] bits_counter_r;
    reg  [ 3:0] bits_counter_next_r;
    wire [ 3:0] bits_counter_incr_w;
    reg  [ 7:0] byte_shifter_r;
    reg  [ 7:0] byte_shifter_next_r;
    wire [ 7:0] byte_shifted_w;
    reg  [ 9:0] data_counter_r;
    reg  [ 9:0] data_counter_next_r;
    wire [ 9:0] data_counter_incr_w;
    reg  [39:0] response_r;
    reg  [39:0] response_next_r;
    wire [39:0] response_shifted_w;
    reg  [ 7:0] token_r;
    reg  [ 7:0] token_next_r;
    wire        token_is_start_block_w;
    wire        token_is_error_w;
    wire        token_error_codes_w;
    wire        data_crc_calculated_w;
    reg         crc_16_match_r;
    reg         crc_16_match_next_r;
    reg         data_received_r;
    reg         data_received_next_r;
    reg         waiting_data_r;
    reg         waiting_data_next_r;
    reg  [12:0] timeout_counter_r;
    reg  [12:0] timeout_counter_next_r;
    wire [12:0] timeout_counter_decr_w;
    reg         timeout_r;
    reg         timeout_next_r;
    wire        byte_received_w;
    wire        byte_is_empty_w;
    wire        data_byte_received_w;

    // Сигналы crc принимаемых данных
    wire        crc_16_data_bit_w;
    wire        crc_16_reset_w;
    wire        crc_16_data_bit_valid_w;
    wire        crc_16_shift_bit_out_w;
    wire        crc_16_out_bit_w;
    wire [15:0] crc_16_out_word_w;
    wire        crc_16_check_condition_w;
    wire        crc_16_compare_w;

    // Сигналы физ-уровня
    wire        phy_is_idle_w;
    wire        phy_gets_miso_w;
    wire        phy_sets_mosi_w;
    wire        phy_start_transferring_w;
    wire        phy_stop_transferring_w;
    wire        phy_data_transmitting_w;
    reg         phy_data_bit_r;


    // Конечный автомат
    always @(posedge clk_i)
        if   (rst_i) state_r <= 4'h0;
        else         state_r <= state_next_r;

    wire [1:0] state_next_st_2_case_w = {cmd_transmitted_r, expecting_response_w};
    wire [1:0] state_next_st_3_case_w = {data_received_r,   timeout_r};
    wire [1:0] state_next_st_5_case_w = {data_received_r,   timeout_r};
    wire [1:0] state_next_st_4_case_w = {response_is_ok_w,  sd_expecting_data_i};
    always @(*)
        case (state_r)

            IDLE:                              state_next_r = (start_transferring_r) ? START_TRANSFERRING : IDLE;

            START_TRANSFERRING:                state_next_r = (start_clocks_completed_w) ? TRANSMITTING_CMD :
                                                                                           START_TRANSFERRING;

            TRANSMITTING_CMD:
                case (state_next_st_2_case_w)
                    2'b11:                     state_next_r = RECEIVING_RESPONSE;
                    2'b10:                     state_next_r = STOP_TRANSFERRING;
                    default:                   state_next_r = TRANSMITTING_CMD;
                endcase

            RECEIVING_RESPONSE:
                casez (state_next_st_3_case_w)
                    2'b1_?:                    state_next_r = CHECK_RESPONSE;
                    2'b0_1:                    state_next_r = TIMEOUT;
                    default:                   state_next_r = RECEIVING_RESPONSE;
                endcase

            CHECK_RESPONSE:
                case (state_next_st_4_case_w)
                    2'b11:                     state_next_r = RECEIVING_TOKEN;
                    2'b10:                     state_next_r = STOP_TRANSFERRING;
                    default:                   state_next_r = RESPONSE_ERROR;
                endcase

            RECEIVING_TOKEN:
                casez (state_next_st_5_case_w)
                    2'b1_?:                    state_next_r = CHECK_TOKEN;
                    2'b0_1:                    state_next_r = TIMEOUT;
                    default:                   state_next_r = RECEIVING_TOKEN;
                endcase

            CHECK_TOKEN:                       state_next_r = (token_is_start_block_w) ? RECEIVING_DATA : TOKEN_ERROR;

            RECEIVING_DATA:                    state_next_r = (data_received_r) ? CHECK_DATA : RECEIVING_DATA;

            CHECK_DATA:                        state_next_r = (crc_16_match_r) ? STOP_TRANSFERRING : DATA_ERROR;

            TIMEOUT:                           state_next_r = STOP_TRANSFERRING;

            RESPONSE_ERROR:                    state_next_r = STOP_TRANSFERRING;

            TOKEN_ERROR:                       state_next_r = STOP_TRANSFERRING;

            DATA_ERROR:                        state_next_r = STOP_TRANSFERRING;

            STOP_TRANSFERRING:                 state_next_r = (phy_is_idle_w) ? IDLE : STOP_TRANSFERRING;

            default:                           state_next_r = state_r;

        endcase


    assign idle_sn_w               = (state_next_r == IDLE);
    assign transmitting_cmd_sn_w   = (state_next_r == TRANSMITTING_CMD);
    assign receiving_data_sn_w     = (state_next_r == RECEIVING_DATA);
    assign stop_transferring_ns_w  = (state_next_r == STOP_TRANSFERRING);


    // Логика пустых тактов на физ-уровне SPI
    always @(posedge clk_i)
        if (rst_i) begin
            start_transferring_r <= 1'b0;
        end else begin
            start_transferring_r <= start_transferring_next_r;
        end

    always @(posedge clk_i)
        begin
            clocks_counter_r     <= clocks_counter_next_r;
        end

    assign start_clocks_completed_w =  clocks_counter_r[3];
    assign stop_clocks_completed_w  = ~clocks_counter_r[3];

    assign phy_start_transferring_w = start_transferring_r;
    assign phy_stop_transferring_w  = stop_clocks_completed_w && stop_transferring_ns_w;

    assign clocks_counter_incr_w    = (phy_sets_mosi_w) ? clocks_counter_r + 1'b1 : clocks_counter_r;

    always @(*)
        case (state_next_r)
            IDLE: begin
                start_transferring_next_r = sd_start_transferring_i;
                clocks_counter_next_r     = 4'h0;
            end
            START_TRANSFERRING: begin
                start_transferring_next_r = 1'b0;
                clocks_counter_next_r     = clocks_counter_incr_w;
            end
            STOP_TRANSFERRING: begin
                start_transferring_next_r = 1'b0;
                clocks_counter_next_r     = clocks_counter_incr_w;
            end
            default: begin
                start_transferring_next_r = 1'b0;
                clocks_counter_next_r     = clocks_counter_r;
            end
        endcase


    // Логика отправки команд SD-карте
    always @(posedge clk_i)
        begin
            cmd_counter_r      <= cmd_counter_next_r;
            cmd_transmitted_r  <= cmd_transmitted_next_r;
            cmd_data_shifter_r <= cmd_data_shifter_next_r;
        end

    assign cmd_counter_decr_w      = cmd_counter_r - phy_sets_mosi_w;
    assign cmd_data_shifted_w      = {cmd_data_shifter_r[38:0], 1'b1};

    assign phy_data_transmitting_w = transmitting_cmd_sn_w && phy_ncs_enable_i;

    assign crc_7_reset_w           = ~phy_data_transmitting_w;
    assign crc_7_data_bit_w        = phy_data_bit_r;
    assign crc_7_data_bit_valid_w  = phy_sets_mosi_w;
    assign crc_7_shift_bit_out_w   = |cmd_counter_r && (cmd_counter_r < 6'd9);

    wire [1:0] phy_data_bit_case_w = {phy_data_transmitting_w, crc_7_shift_bit_out_w};
    always @(*)
        case (phy_data_bit_case_w)
            2'b10:   phy_data_bit_r = cmd_data_shifter_r[39];
            2'b11:   phy_data_bit_r = crc_7_out_bit_w;
            default: phy_data_bit_r = 1'b1;
        endcase

    always @(*)
        case (state_next_r)
            IDLE: begin
                cmd_counter_next_r      = CMD_BITS;
                cmd_transmitted_next_r  = 1'b0;
                cmd_data_shifter_next_r = {sd_cmd_data_i};
            end
            TRANSMITTING_CMD: begin
                cmd_counter_next_r      = (phy_sets_mosi_w) ? cmd_counter_decr_w : cmd_counter_r;
                cmd_transmitted_next_r  = (phy_sets_mosi_w) ? ~|cmd_counter_r    : cmd_transmitted_r;
                cmd_data_shifter_next_r = (phy_sets_mosi_w) ? cmd_data_shifted_w : cmd_data_shifter_r;
            end
            default: begin
                cmd_counter_next_r      = cmd_counter_r;
                cmd_transmitted_next_r  = cmd_transmitted_r;
                cmd_data_shifter_next_r = cmd_data_shifter_r;
            end
        endcase


    // Логика вычисления crc команды для SD-карты
    crc_logic
        #(
            .WIDTH                   (7                       ),
            .NORMAL_REPRESENT        (7'h9                    ),
            .INITIAL_VALUE           (7'h0                    )
        )
        cmd_crc_7
        (
            .clk_i                   (clk_i                   ),
            .rst_i                   (crc_7_reset_w           ),
            .data_bit_i              (crc_7_data_bit_w        ),
            .data_bit_valid_i        (crc_7_data_bit_valid_w  ),
            .shift_bit_out_i         (crc_7_shift_bit_out_w   ),
            .crc_word_o              (crc_7_out_word_w        ),
            .crc_bit_o               (crc_7_out_bit_w         )
        );


    // Логика проверки валидности принятых ответов и токенов данных от SD-карты
    always @(*)
        case (sd_response_type_i)
            NO_RESPONSE: response_size_r  = NO_RESPONSE_BYTES;
            R1_RESPONSE: response_size_r  = R1_RESPONSE_BYTES;
            R2_RESPONSE: response_size_r  = R2_RESPONSE_BYTES;
            R3_RESPONSE: response_size_r  = R3_RESPONSE_BYTES;
            R7_RESPONSE: response_size_r  = R7_RESPONSE_BYTES;
            default:     response_size_r  = NO_RESPONSE_BYTES;
        endcase

    always @(*)
        case (sd_response_type_i)
            NO_RESPONSE: response_flags_w = 14'h0;
            R1_RESPONSE: response_flags_w = {response_r[ 6: 1], 8'h0};
            R2_RESPONSE: response_flags_w = {response_r[14: 9], response_r[7:0]};
            R3_RESPONSE: response_flags_w = {response_r[38:33], 8'h0};
            R7_RESPONSE: response_flags_w = {response_r[38:33], 8'h0};
            default:     response_flags_w = 14'h0;
        endcase

    assign expecting_response_w   =  |sd_response_type_i;
    assign response_is_ok_w       = ~|response_flags_w;
    assign token_is_start_block_w =  &token_r[7:1] && ~token_r[0];
    assign token_is_error_w       = ~&token_r[7:4];
    assign token_error_codes_w    =   token_r[3:0];


    // Логика приёма данных и ответов от SD-карты
    always @(posedge clk_i)
        begin
            bits_counter_r    <= bits_counter_next_r;
            byte_shifter_r    <= byte_shifter_next_r;
            data_counter_r    <= data_counter_next_r;
            data_received_r   <= data_received_next_r;
            response_r        <= response_next_r;
            token_r           <= token_next_r;
            crc_16_match_r    <= crc_16_match_next_r;
            waiting_data_r    <= waiting_data_next_r;
            timeout_counter_r <= timeout_counter_next_r;
            timeout_r         <= timeout_next_r;
        end

    assign byte_received_w          = bits_counter_r[3];
    assign byte_is_empty_w          = &byte_shifter_r && waiting_data_r;

    assign bits_counter_incr_w      = bits_counter_r    +  phy_gets_miso_w;
    assign data_counter_incr_w      = data_counter_r    + (byte_received_w && ~byte_is_empty_w);
    assign timeout_counter_decr_w   = timeout_counter_r - (byte_received_w &&  byte_is_empty_w);

    assign byte_shifted_w           = {byte_shifter_r[ 6:0], spi_miso_i};
    assign response_shifted_w       = {response_r    [31:0], byte_shifter_r};

    assign data_byte_received_w     = byte_received_w && ~data_counter_r[9] && receiving_data_sn_w; // <  10'd512
    assign data_crc_calculated_w    = byte_received_w && &data_counter_r[8:0];                      // == 10'd511

    assign crc_16_reset_w           = ~token_is_start_block_w;
    assign crc_16_data_bit_w        = spi_miso_i;
    assign crc_16_data_bit_valid_w  = phy_gets_miso_w;
    assign crc_16_shift_bit_out_w   = data_counter_r[9] && ~data_counter_r[1]; // == 10'd512 || 10'd513
    assign crc_16_check_condition_w = crc_16_shift_bit_out_w && phy_gets_miso_w && crc_16_match_r;
    assign crc_16_compare_w         = crc_16_out_bit_w ~^ spi_miso_i;

    always @(*)
        case (state_next_r)
            IDLE: begin
                bits_counter_next_r    = 4'h0;
                byte_shifter_next_r    = {8{1'b1}};
                data_counter_next_r    = 10'h0;
                data_received_next_r   = 1'b0;
            end
            RECEIVING_RESPONSE: begin
                bits_counter_next_r    = (byte_received_w) ? 4'h0           : bits_counter_incr_w;
                byte_shifter_next_r    = (phy_gets_miso_w) ? byte_shifted_w : byte_shifter_r;
                data_counter_next_r    = data_counter_incr_w;
                data_received_next_r   = (data_counter_r == response_size_r);
            end
            CHECK_RESPONSE: begin
                bits_counter_next_r    = (byte_received_w) ? 4'h0           : bits_counter_incr_w;
                byte_shifter_next_r    = (phy_gets_miso_w) ? byte_shifted_w : byte_shifter_r;
                data_counter_next_r    = 10'h0;
                data_received_next_r   = 1'b0;
            end
            RECEIVING_TOKEN: begin
                bits_counter_next_r    = (byte_received_w) ? 4'h0           : bits_counter_incr_w;
                byte_shifter_next_r    = (phy_gets_miso_w) ? byte_shifted_w : byte_shifter_r;
                data_counter_next_r    = data_counter_incr_w;
                data_received_next_r   = (data_counter_r == 10'h1);
            end
            CHECK_TOKEN: begin
                bits_counter_next_r    = (byte_received_w) ? 4'h0           : bits_counter_incr_w;
                byte_shifter_next_r    = (phy_gets_miso_w) ? byte_shifted_w : byte_shifter_r;
                data_counter_next_r    = 10'h0;
                data_received_next_r   = 1'b0;
            end
            RECEIVING_DATA: begin
                bits_counter_next_r    = (byte_received_w) ? 4'h0           : bits_counter_incr_w;
                byte_shifter_next_r    = (phy_gets_miso_w) ? byte_shifted_w : byte_shifter_r;
                data_counter_next_r    = data_counter_incr_w;
                data_received_next_r   = (data_counter_r == (DATA_AND_CRC_BYTES - 1)) && byte_received_w;
            end
            default: begin
                bits_counter_next_r    = bits_counter_r;
                byte_shifter_next_r    = byte_shifter_r;
                data_counter_next_r    = data_counter_r;
                data_received_next_r   = data_received_r;
            end
        endcase

    always @(*)
        case (state_next_r)
            IDLE: begin
                response_next_r        = {40{1'b1}};
                token_next_r           = {8{1'b1}};
                crc_16_match_next_r    = 1'b1;
            end
            RECEIVING_RESPONSE: begin
                response_next_r        = (byte_received_w) ? response_shifted_w : response_r;
                token_next_r           = token_r;
                crc_16_match_next_r    = crc_16_match_r;
            end
            RECEIVING_TOKEN: begin
                response_next_r        = response_r;
                token_next_r           = (byte_received_w) ? byte_shifter_r : token_r;
                crc_16_match_next_r    = crc_16_match_r;
            end
            RECEIVING_DATA: begin
                response_next_r        = response_r;
                token_next_r           = token_r;
                crc_16_match_next_r    = (crc_16_check_condition_w) ? crc_16_compare_w : crc_16_match_r;
            end
            default: begin
                response_next_r        = response_r;
                token_next_r           = token_r;
                crc_16_match_next_r    = crc_16_match_r;
            end
        endcase

    always @(*)
        case (state_next_r)
            IDLE: begin
                waiting_data_next_r    = 1'b1;
                timeout_counter_next_r = TIMEOUT_RESPONSE_BYTES;
                timeout_next_r         = 1'b0;
            end
            RECEIVING_RESPONSE: begin
                waiting_data_next_r    = (byte_received_w) ? byte_is_empty_w : waiting_data_r;
                timeout_counter_next_r = timeout_counter_decr_w;
                timeout_next_r         = ~|timeout_counter_r;
            end
            CHECK_RESPONSE: begin
                waiting_data_next_r    = 1'b1;
                timeout_counter_next_r = TIMEOUT_DATA_BYTES;
                timeout_next_r         = 1'b0;
            end
            RECEIVING_TOKEN: begin
                waiting_data_next_r    = (byte_received_w) ? byte_is_empty_w : waiting_data_r;
                timeout_counter_next_r = timeout_counter_decr_w;
                timeout_next_r         = ~|timeout_counter_r;
            end
            default: begin
                waiting_data_next_r    = waiting_data_r;
                timeout_counter_next_r = timeout_counter_r;
                timeout_next_r         = timeout_r;
            end
        endcase


    // Логика вычисления crc входных данных от SD-карты
    crc_logic
        #(
            .WIDTH                   (16                      ),
            .NORMAL_REPRESENT        (16'h1021                ),
            .INITIAL_VALUE           (16'h0                   )
        )
        data_crc_16
        (
            .clk_i                   (clk_i                   ),
            .rst_i                   (crc_16_reset_w          ),
            .data_bit_i              (crc_16_data_bit_w       ),
            .data_bit_valid_i        (crc_16_data_bit_valid_w ),
            .shift_bit_out_i         (crc_16_shift_bit_out_w  ),
            .crc_word_o              (crc_16_out_word_w       ),
            .crc_bit_o               (crc_16_out_bit_w        )
        );


    // Физический уровень SPI
    spi_phy
        spi_phy
        (
            .clk_i                   (clk_i                   ),
            .rst_i                   (rst_i                   ),

            .spi_clk_o               (spi_clk_o               ),
            .spi_ncs_o               (spi_ncs_o               ),
            .spi_ncs_en_o            (spi_ncs_en_o            ),
            .spi_mosi_o              (spi_mosi_o              ),
            .spi_mosi_en_o           (spi_mosi_en_o           ),

            .phy_start_transferring_i(phy_start_transferring_w),
            .phy_stop_transferring_i (phy_stop_transferring_w ),
            .phy_data_bit_i          (phy_data_bit_r          ),
            .phy_data_transmitting_i (phy_data_transmitting_w ),
            .phy_ncs_enable_i        (phy_ncs_enable_i        ),
            .phy_is_idle_o           (phy_is_idle_w           ),
            .phy_sets_mosi_o         (phy_sets_mosi_w         ),
            .phy_gets_miso_o         (phy_gets_miso_w         )
        );


    // Выходы
    assign sdspi_is_idle_o            = idle_sn_w;
    assign sdspi_response_o           = response_r;
    assign sdspi_response_is_ok_o     = response_is_ok_w;
    assign sdspi_token_is_ok_o        = token_is_start_block_w;
    assign sdspi_data_crc_is_ok_o     = crc_16_match_r;
    assign sdspi_data_byte_received_o = data_byte_received_w;
    assign sdspi_data_byte_o          = byte_shifter_r;
    assign sdspi_data_counter_o       = data_counter_r[8:0];


endmodule
