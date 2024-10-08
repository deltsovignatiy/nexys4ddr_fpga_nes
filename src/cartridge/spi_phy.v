
/*
 * Description : SPI physical interface (physical layer) module for SD-card controller
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module spi_phy
    (
        input  wire clk_i,                    // Сигнал тактирования
        input  wire rst_i,                    // Сигнал сброса

        output wire spi_clk_o,                // Сигнал тактирования SPI
        output wire spi_ncs_o,                // Сигнал выбора ведомого SPI
        output wire spi_ncs_en_o,             // Сигнал активации выхода выбора ведомого (управление буфером с 3-им состоянием)
        output wire spi_mosi_o,               // Сигнал данных от ведущего к ведомому SPI
        output wire spi_mosi_en_o,            // Сигнал активации выхода данных от ведущего (управление буфером с 3-им состоянием)

        input  wire phy_start_transferring_i, // Сигнал начала транзакции SPI, активация линии "chip select"
        input  wire phy_stop_transferring_i,  // Сигнал окончания транзакции SPI, деактивация линии "chip select"
        input  wire phy_data_bit_i,           // Текущий бит данных для передачи по линии MOSI
        input  wire phy_data_transmitting_i,  // Сигнал передачи данных от ведущего устройства по линии MOSI
        input  wire phy_ncs_enable_i,         // Сигнал разрешения активации "chip enable"
        output wire phy_is_idle_o,            // SPI находится в состоянии ожидания новго цикла работы
        output wire phy_sets_mosi_o,          // Такт выставления данных на MOSI (spi clk negedge)
        output wire phy_gets_miso_o           // Такт приёма данных по MISO (spi clk posedge)
    );


    // Состояния конечного автомата
    localparam [2:0] IDLE                     = 0,
                     SET_NCS                  = 1,
                     SET_CLK_NEGEDGE_SET_MOSI = 2,
                     SET_CLK_POSEDGE_GET_MISO = 3,
                     STOP_CLOCK               = 4,
                     RESET_NCS                = 5;


    // Конечный автомат
    reg  [2:0] state_r;
    reg  [2:0] state_next_r;

    wire       idle_sn_w;
    wire       set_clk_negedge_set_mosi_sn_w;
    wire       set_clk_posedge_get_miso_sn_w;
    wire       spi_mosi_update_condition_w;
    wire       spi_check_stop_w;

    // Сигналы управления SPI
    reg  [4:0] ncs_counter_r;
    reg  [4:0] ncs_counter_next_r;
    wire       set_ncs_ready_w;
    wire       reset_ncs_ready_w;
    reg        spi_start_r;
    wire       spi_start_next_w;
    reg        spi_stop_r;
    wire       spi_stop_next_w;

    reg        spi_clk_r;
    reg        spi_clk_next_r;
    reg        spi_ncs_r;
    reg        spi_ncs_next_r;
    reg        spi_ncs_en_r;
    reg        spi_ncs_en_next_r;
    reg        spi_mosi_r;
    wire       spi_mosi_next_w;
    reg        spi_mosi_en_r;
    wire       spi_mosi_en_next_w;


    // Логика конечного автомата
    always @(posedge clk_i)
        if   (rst_i) state_r <= 3'h0;
        else         state_r <= state_next_r;

    always @(*)
        case (state_r)

            IDLE:                     state_next_r = (spi_start_r) ? SET_NCS : IDLE;

            SET_NCS:                  state_next_r = (set_ncs_ready_w) ? SET_CLK_NEGEDGE_SET_MOSI : SET_NCS;

            SET_CLK_NEGEDGE_SET_MOSI: state_next_r = SET_CLK_POSEDGE_GET_MISO;

            SET_CLK_POSEDGE_GET_MISO: state_next_r = (spi_stop_r) ? STOP_CLOCK : SET_CLK_NEGEDGE_SET_MOSI;

            STOP_CLOCK:               state_next_r = (clock_stopped_w) ? RESET_NCS : STOP_CLOCK;

            RESET_NCS:                state_next_r = (reset_ncs_ready_w) ? IDLE : RESET_NCS;

            default:                  state_next_r = state_r;

        endcase


    assign idle_sn_w                     = (state_next_r == IDLE);
    assign set_clk_negedge_set_mosi_sn_w = (state_next_r == SET_CLK_NEGEDGE_SET_MOSI);
    assign set_clk_posedge_get_miso_sn_w = (state_next_r == SET_CLK_POSEDGE_GET_MISO);

    assign spi_mosi_update_condition_w   = set_clk_negedge_set_mosi_sn_w && phy_ncs_enable_i;
    assign spi_check_stop_w              = set_clk_posedge_get_miso_sn_w;


    // Логика сигналов SPI
    always @(posedge clk_i or posedge rst_i)
        if (rst_i) begin
            spi_ncs_r     <= 1'b1;
            spi_ncs_en_r  <= 1'b0;
            spi_clk_r     <= 1'b1;
            spi_mosi_r    <= 1'b1;
            spi_mosi_en_r <= 1'b0;
        end else begin
            spi_ncs_r     <= spi_ncs_next_r;
            spi_ncs_en_r  <= spi_ncs_en_next_r;
            spi_clk_r     <= spi_clk_next_r;
            spi_mosi_r    <= spi_mosi_next_w;
            spi_mosi_en_r <= spi_mosi_en_next_w;
        end

    always @(posedge clk_i)
        if (rst_i) begin
            spi_start_r   <= 1'b0;
            spi_stop_r    <= 1'b0;
        end else begin
            spi_start_r   <= spi_start_next_w;
            spi_stop_r    <= spi_stop_next_w;
        end

    always @(posedge clk_i)
        begin
            ncs_counter_r <= ncs_counter_next_r;
        end

    assign spi_start_next_w   = (idle_sn_w       ) ? phy_start_transferring_i : spi_start_r;
    assign spi_stop_next_w    = (spi_check_stop_w) ? phy_stop_transferring_i  : spi_stop_r;

    assign set_ncs_ready_w    =  ncs_counter_r[4];
    assign clock_stopped_w    = ~ncs_counter_r[4];
    assign reset_ncs_ready_w  =  ncs_counter_r[4];

    assign spi_mosi_next_w    = (spi_mosi_update_condition_w) ? phy_data_bit_i          : spi_mosi_r;
    assign spi_mosi_en_next_w = (spi_mosi_update_condition_w) ? phy_data_transmitting_i : spi_mosi_en_r;

    always @(*)
        case (state_next_r)
            IDLE: begin
                ncs_counter_next_r = 5'h0;
                spi_ncs_next_r     = 1'b1;
                spi_ncs_en_next_r  = 1'b0;
            end
            SET_NCS: begin
                ncs_counter_next_r = ncs_counter_r + 1'b1;
                spi_ncs_next_r     = 1'b0;
                spi_ncs_en_next_r  = phy_ncs_enable_i;
            end
            STOP_CLOCK: begin
                ncs_counter_next_r = ncs_counter_r + 1'b1;
                spi_ncs_next_r     = spi_ncs_r;
                spi_ncs_en_next_r  = spi_ncs_en_r;
            end
            RESET_NCS: begin
                ncs_counter_next_r = ncs_counter_r + 1'b1;
                spi_ncs_next_r     = 1'b1;
                spi_ncs_en_next_r  = 1'b0;
            end
            default: begin
                ncs_counter_next_r = ncs_counter_r;
                spi_ncs_next_r     = spi_ncs_r;
                spi_ncs_en_next_r  = spi_ncs_en_r;
            end
        endcase

    always @(*)
        case (state_next_r)
            IDLE:                     spi_clk_next_r = 1'b1;
            SET_CLK_NEGEDGE_SET_MOSI: spi_clk_next_r = 1'b0;
            SET_CLK_POSEDGE_GET_MISO: spi_clk_next_r = 1'b1;
            default:                  spi_clk_next_r = spi_clk_r;
        endcase


    // Выходы
    assign spi_clk_o       = spi_clk_r;
    assign spi_ncs_o       = spi_ncs_r;
    assign spi_ncs_en_o    = spi_ncs_en_r;
    assign spi_mosi_o      = spi_mosi_r;
    assign spi_mosi_en_o   = spi_mosi_en_r;

    assign phy_is_idle_o   = idle_sn_w;
    assign phy_sets_mosi_o = set_clk_negedge_set_mosi_sn_w;
    assign phy_gets_miso_o = set_clk_posedge_get_miso_sn_w;


endmodule
