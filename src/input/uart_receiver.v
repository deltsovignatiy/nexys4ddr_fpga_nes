
/*
 * Description : UART receiver module, no parity bit, 1 stop bit
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module uart_receiver
    #(
        parameter CLK_FREQ_HZ = 115200000, // Частота сигнала тактирования
        parameter BAUDRATE    = 921600     // Бодрейт UART
    )
    (
        input  wire       clk_i,           // Сигнал тактирования
        input  wire       rst_i,           // Сигнал сброса

        input  wire       rxd_i,           // Сигнал UART интерфейса — "RXD" вход данных
        input  wire       buffer_ready_i,  // Сигнал готовности к приёму выходных данных
        output wire [7:0] data_o,          // Выходные данные
        output wire       data_valid_o     // Сигнал валидности выходных данных
    );


    `include "function_clogb2.vh"


    // Параметры бодрейта
    localparam FULL_BIT_DURATION_IN_CYCLES = CLK_FREQ_HZ / BAUDRATE;
    localparam HALF_BIT_DURATION_IN_CYCLES = FULL_BIT_DURATION_IN_CYCLES / 2;
    localparam CYCLES_COUNTER_WIDTH        = __clogb2__(FULL_BIT_DURATION_IN_CYCLES);
    localparam CCW                         = CYCLES_COUNTER_WIDTH;


    // Состояния конечного автомата
    localparam [2:0] IDLE              = 0,
                     OFFSET_START_BIT  = 1,
                     RECEIVE_START_BIT = 2,
                     OFFSET_DATA_BIT   = 3,
                     RECEIVE_DATA_BIT  = 4,
                     OFFSET_STOP_BIT   = 5,
                     RECEIVE_STOP_BIT  = 6;


    // Конечный автомат
    reg [    2:0] state_r;
    reg [    2:0] state_next_r;

    // Управляющие сигналы
    wire          halfbod_w;
    wire          fullbod_w;
    wire          all_data_received_w;
    wire          start_bit_w;
    reg           rxd_r;
    reg           rxd_prev_r;

    // Приём данных
    reg [    2:0] bit_counter_r;
    reg [    2:0] bit_counter_next_r;
    reg [CCW-1:0] cycles_counter_r;
    reg [CCW-1:0] cycles_counter_next_r;
    reg [    7:0] received_data_r;
    reg [    7:0] received_data_next_r;
    reg [    7:0] output_data_r;
    reg [    7:0] output_data_next_r;
    reg           output_data_valid_r;
    reg           output_data_valid_next_r;


    // Контроль начала и конца передачи данных
    assign halfbod_w           = (cycles_counter_r == HALF_BIT_DURATION_IN_CYCLES);
    assign fullbod_w           = (cycles_counter_r == FULL_BIT_DURATION_IN_CYCLES);
    assign start_bit_w         = ~rxd_r & rxd_prev_r;
    assign all_data_received_w = ~|bit_counter_r; // bit_counter_r == 3'h0

    always @(posedge clk_i)
        if   (rst_i) {rxd_prev_r, rxd_r} <= 2'b11;
        else         {rxd_prev_r, rxd_r} <= {rxd_r, rxd_i};


    // Логика конечного автомата
    always @(posedge clk_i)
        if   (rst_i) state_r  <= IDLE;
        else         state_r  <= state_next_r;

    always @(*)
        case (state_r)

            // Ждём старт-бит
            IDLE:              state_next_r = (start_bit_w) ? OFFSET_START_BIT : IDLE;

            // Отступили на середину принимаемого стартового бита
            OFFSET_START_BIT:  state_next_r = (halfbod_w) ? RECEIVE_START_BIT : OFFSET_START_BIT;

            // Принимаем старт-бит
            RECEIVE_START_BIT: state_next_r = OFFSET_DATA_BIT;

            // Делаем шаги по полному биту, сохраняя отступ на середину
            OFFSET_DATA_BIT:   state_next_r = (fullbod_w) ? RECEIVE_DATA_BIT : OFFSET_DATA_BIT;

            // Принимаем очередной бит данных
            RECEIVE_DATA_BIT:  state_next_r = (all_data_received_w) ? OFFSET_STOP_BIT : OFFSET_DATA_BIT;

            // Делаем последний полный шаг на полный бит для приема стопа
            OFFSET_STOP_BIT:   state_next_r = (fullbod_w) ? RECEIVE_STOP_BIT : OFFSET_STOP_BIT;

            // Принимаем стоп-бит на его середине и прыгаем в IDLE, готовые к новой передаче
            RECEIVE_STOP_BIT:  state_next_r = IDLE;

            default:           state_next_r = IDLE;

        endcase


    // Логика приёма данных по UART
    always @(posedge clk_i)
        if (rst_i) begin
            output_data_valid_r <= 1'b0;
        end else begin
            output_data_valid_r <= output_data_valid_next_r;
        end

    always @(posedge clk_i)
        begin
            bit_counter_r       <= bit_counter_next_r;
            cycles_counter_r    <= cycles_counter_next_r;
            received_data_r     <= received_data_next_r;
            output_data_r       <= output_data_next_r;
        end

    always @(*)
        case (state_next_r)
            IDLE: begin
                bit_counter_next_r       = 3'h0;
                received_data_next_r     = received_data_r;
            end
            RECEIVE_DATA_BIT: begin
                bit_counter_next_r       = bit_counter_r + 1'b1;
                received_data_next_r     = {rxd_r, received_data_r[7:1]};
            end
            default: begin
                bit_counter_next_r       = bit_counter_r;
                received_data_next_r     = received_data_r;
            end
        endcase

    always @(*)
        case (state_next_r)
            RECEIVE_STOP_BIT: begin
                output_data_next_r       = (~output_data_valid_r) ? received_data_r[7:0] : output_data_r[7:0];
                output_data_valid_next_r = 1'b1;
            end
            default: begin
                output_data_next_r       = output_data_r;
                output_data_valid_next_r = (buffer_ready_i) ? 1'b0 : output_data_valid_r;
            end
        endcase

    always @(*)
        case (state_next_r)
            OFFSET_DATA_BIT,
            OFFSET_STOP_BIT,
            OFFSET_START_BIT: cycles_counter_next_r = cycles_counter_r + 1'b1;
            default:          cycles_counter_next_r = {CCW{1'b0}};
        endcase


    // Выходы
    assign data_valid_o = output_data_valid_r;
    assign data_o       = output_data_r;


endmodule
