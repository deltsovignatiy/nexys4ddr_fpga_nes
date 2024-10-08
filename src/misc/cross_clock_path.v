
/*
 * Description : Clock domain crossing logic module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module cross_clock_path
    #(
        parameter DATA_WIDTH          = 8,       // Ширина данных, проходящих через пересечение доменов тактирования
        parameter USE_ACKNOWLEDGEMENT = "TRUE"   // Имплементировать ли сигнал wd_ready_o, "TRUE" или "FALSE"
    )
    (
        input  wire                  wd_clk_i,   // Сигнал тактирования логики записываемых данных
        input  wire                  wd_rst_i,   // Сигнал сброса логики записываемых данных
        input  wire                  wd_valid_i, // Сигнал валидности логики записываемых данных
        input  wire [DATA_WIDTH-1:0] wd_data_i,  // Записываемые данные
        output wire                  wd_ready_o, // Сигнал готовности к приёму новых записываемых данных

        input  wire                  rd_clk_i,   // Сигнал тактирования логики считываемых данных
        input  wire                  rd_rst_i,   // Сигнал сброса логики считываемых данных
        input  wire                  rd_ready_i, // Сигнал готовности принять новые данные
        output wire [DATA_WIDTH-1:0] rd_data_o,  // Считываемые данные
        output wire                  rd_valid_o  // Сигнал валидности считываемых данных
    );


    localparam DW = DATA_WIDTH;


    // Сигналы домена записи
    (* DONT_TOUCH = "TRUE" *)
    reg  [DW-1:0] wd_data_r;
    wire [DW-1:0] wd_data_next_w;
    (* DONT_TOUCH = "TRUE" *)
    reg           wd_load_r;
    wire          wd_load_next_w;
    wire          wd_new_data_w;
    wire          wd_ready_w;

    // Сигнал домена чтения
    (* DONT_TOUCH = "TRUE" *)
    reg  [DW-1:0] rd_data_r;
    wire [DW-1:0] rd_data_next_w;
    reg           rd_valid_r;
    reg           rd_valid_next_r;
    wire          rd_load_pulse_w;
    (* ASYNC_REG = "TRUE" *)
    reg  [   2:0] rd_load_r;
    wire [   2:0] rd_load_next_w;


    // Защёлкивание входных данных домена записи
    always @(posedge wd_clk_i)
        if (wd_rst_i) begin
            wd_load_r <= 1'b0;
        end else begin
            wd_load_r <= wd_load_next_w;
        end

    always @(posedge wd_clk_i)
        begin
            wd_data_r <= wd_data_next_w;
        end

    assign wd_new_data_w  = wd_valid_i && wd_ready_w;

    assign wd_load_next_w = (wd_new_data_w) ? ~wd_load_r : wd_load_r;
    assign wd_data_next_w = (wd_new_data_w) ?  wd_data_i : wd_data_r;


    /* Пересечение доменов тактирования,
     * защёлкивание входных данных в домене чтения */
    always @(posedge rd_clk_i)
        if (rd_rst_i) begin
            rd_load_r  <= 3'b000;
            rd_valid_r <= 1'b0;
        end else begin
            rd_load_r  <= rd_load_next_w;
            rd_valid_r <= rd_valid_next_r;
        end

    always @(posedge rd_clk_i)
        begin
            rd_data_r  <= rd_data_next_w;
        end

    assign rd_load_next_w  = {rd_load_r[1:0], wd_load_r};

    assign rd_load_pulse_w = rd_load_r[2] ^ rd_load_r[1];

    assign rd_data_next_w  = (rd_load_pulse_w) ? wd_data_r : rd_data_r;

    always @(*)
        if      (rd_load_pulse_w) rd_valid_next_r = 1'b1;
        else if (rd_ready_i     ) rd_valid_next_r = 1'b0;
        else                      rd_valid_next_r = rd_valid_r;


    // Формирование сигнала подтверждения приёма данных доменом чтения
    generate

        if (USE_ACKNOWLEDGEMENT == "TRUE") begin: use_ack

            reg        wd_ready_r;
            reg        wd_ready_next_r;
            wire       wd_ack_pulse_w;
            (* ASYNC_REG = "TRUE" *)
            reg  [2:0] wd_ack_r;
            wire [2:0] wd_ack_next_w;

            wire       rd_new_data_w;
            (* DONT_TOUCH = "TRUE" *)
            reg        rd_ack_r;
            wire       rd_ack_next_w;


            always @(posedge wd_clk_i)
                if (wd_rst_i) begin
                    wd_ready_r <= 1'b1;
                    wd_ack_r   <= 3'b000;
                end else begin
                    wd_ready_r <= wd_ready_next_r;
                    wd_ack_r   <= wd_ack_next_w;
                end

            assign wd_ack_next_w  = {wd_ack_r[1:0], rd_ack_r};

            assign wd_ack_pulse_w = wd_ack_r[2] ^ wd_ack_r[1];

            wire [1:0] wd_ready_next_case_r = {wd_new_data_w, wd_ack_pulse_w};
            always @(*)
                case (wd_ready_next_case_r) // one hot
                    2'b10:   wd_ready_next_r = 1'b0;
                    2'b01:   wd_ready_next_r = 1'b1;
                    default: wd_ready_next_r = wd_ready_r;
                endcase

            always @(posedge rd_clk_i)
                if   (rd_rst_i) rd_ack_r <= 1'b0;
                else            rd_ack_r <= rd_ack_next_w;

            assign rd_new_data_w = rd_ready_i && rd_valid_r;

            assign rd_ack_next_w = (rd_new_data_w) ? ~rd_ack_r : rd_ack_r;

            assign wd_ready_w = wd_ready_r;

        end else begin: dont_use_ack

            assign wd_ready_w = 1'b1;

        end

    endgenerate


    // Выходы
    assign wd_ready_o = wd_ready_w;

    assign rd_valid_o = rd_valid_r;
    assign rd_data_o  = rd_data_r;


endmodule
