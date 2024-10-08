
/*
 * Description : DDR2 controller interface module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module ddr2_controller_interface
    (
        output wire [12:0] ddr2_addr_o,           // Линии адреса DDR памяти
        output wire [ 2:0] ddr2_ba_o,             // Линии адреса банка DDR памяти
        output wire        ddr2_ras_n_o,          // Линия команды DDR памяти "row address strobe"
        output wire        ddr2_cas_n_o,          // Линия команды DDR памяти "column address strobe"
        output wire        ddr2_we_n_o,           // Линия команды DDR памяти "write enable"
        output wire [ 0:0] ddr2_ck_p_o,           // Дифференциальный вход сигнала тактирования DDR памяти
        output wire [ 0:0] ddr2_ck_n_o,           // Дифференциальный вход сигнала тактирования DDR памяти
        output wire [ 0:0] ddr2_cke_o,            // Линия активации тактирования DDR памяти
        output wire [ 0:0] ddr2_cs_n_o,           // Линия выбора DDR памяти "chip select"
        output wire [ 1:0] ddr2_dm_o,             // Линии маскирования входных данных DDR памяти
        output wire [ 0:0] ddr2_odt_o,            // Активация встроенного в память сопротивления для соглосования портов DDR памяти
        inout  wire [15:0] ddr2_dq_io,            // Линии данных DDR памяти
        inout  wire [ 1:0] ddr2_dqs_p_io,         // Дифференциальные линии стробирования данных DDR памяти
        inout  wire [ 1:0] ddr2_dqs_n_io,         // Дифференциальные линии стробирования данных DDR памяти

        input  wire        ddr2_cntrl_clk_i,      // Сигнал тактирования контроллера DDR памяти
        input  wire        ddr2_cntrl_rst_i,      // Сигнал сброса контроллера DDR памяти
        output wire        ui_clk_o,              // Сигнал тактирования интерфейса контроллера DDR памяти
        output wire        ui_rst_o,              // Сигнал сброса интерфейса контроллера DDR памяти

        input  wire        rd_request_i,          // Запрос на чтение данных из DDR памяти
        input  wire [26:0] rd_address_i,          // Адрес для чтения данных из DDR памяти
        output wire [ 7:0] rd_data_o,             // Читаемые данные из DDR памяти
        output wire        rd_data_valid_o,       // Флаг валидности прочитанных данных

        input  wire        wr_request_i,          // Запрос на запись данных в DDR память
        input  wire [26:0] wr_address_i,          // Адрес для запис данных в DDR память
        input  wire [ 7:0] wr_data_i,             // Записываемые данные в DDR память

        output wire        cntrl_iface_is_idle_o, // Интерфейс контроллера DDR памяти находится в режиме ожидания
        output wire        init_calib_complete_o  // Калибровка DDR памяти завершена, контроллер доступен
    );


    // Состояние конченого автомата
    localparam [2:0] WAIT_CALIBRATION    = 0,
                     IDLE_WAIT_READ_DATA = 1,
                     SET_WRITE_CMD       = 2,
                     SET_WRITE_DATA_L    = 3,
                     SET_WRITE_DATA_H    = 4,
                     SET_READ_CMD        = 5;

    // Команды для контроллера DDR памяти
    localparam [2:0] CMD_WRITE           = 3'b000,
                     CMD_READ            = 3'b001;


    // Сигналы конного автомата
    reg  [  2:0] state_r;
    reg  [  2:0] state_next_r;
    wire         idle_wait_read_data_sn_w;

    // Выходные данные
    reg          wr_request_r;
    reg          wr_request_next_r;
    reg  [ 26:0] wr_address_r;
    wire [ 26:0] wr_address_next_w;
    reg  [  7:0] wr_data_r;
    wire [  7:0] wr_data_next_w;
    reg          rd_request_r;
    reg          rd_request_next_r;
    reg  [ 26:0] rd_address_r;
    wire [ 26:0] rd_address_next_w;

    // Сигналы интерфейсу от контроллера DDR памяти
    wire         ui_clk_w;
    wire         ui_rst_w;
    wire         init_calib_complete_w;

    wire         app_rdy_w;
    wire         app_wdf_rdy_w;
    wire         app_rd_data_valid_w;
    wire         app_rd_data_end_w;
    wire [ 63:0] app_rd_data_w;

    // Сигнаы логики интерфейса
    reg  [  2:0] app_cmd_r;
    reg  [  2:0] app_cmd_next_r;
    reg          app_en_r;
    reg          app_en_next_r;
    reg  [ 26:0] app_addr_r;
    reg  [ 26:0] app_addr_next_r;
    wire [ 26:0] app_addr_actual_w;
    reg  [ 63:0] app_wdf_data_r;
    reg  [ 63:0] app_wdf_data_next_r;
    reg          app_wdf_wren_r;
    reg          app_wdf_wren_next_r;
    reg          app_wdf_end_r;
    reg          app_wdf_end_next_r;
    reg  [  7:0] app_wdf_mask_r;
    reg  [  7:0] app_wdf_mask_next_r;
    wire [ 15:0] app_wdf_mask_union_w;
    reg  [127:0] read_data_union_r;
    reg  [127:0] read_data_union_next_r;
    wire         read_data_valid_h_w;
    wire         read_data_valid_l_w;
    wire [  7:0] read_data_parsed_w [15:0];
    wire [  7:0] read_data_w;
    reg          read_data_valid_r;
    wire         read_data_valid_next_w;


    // Логичка конечного автомата
    always @(posedge ui_clk_w)
        if   (ui_rst_w) state_r <= 3'h0;
        else            state_r <= state_next_r;

    wire [1:0] state_next_st_1_w = {rd_request_r, wr_request_r};
    wire [1:0] state_next_st_5_w = {app_rdy_w, wr_request_r};
    always @(*)
        case (state_r)

            WAIT_CALIBRATION:             state_next_r = (init_calib_complete_w) ? IDLE_WAIT_READ_DATA :
                                                                                   WAIT_CALIBRATION;

            IDLE_WAIT_READ_DATA:
                casez (state_next_st_1_w)
                    2'b1_?:               state_next_r = SET_READ_CMD;
                    2'b0_1:               state_next_r = SET_WRITE_CMD;
                    default:              state_next_r = IDLE_WAIT_READ_DATA;
                endcase

            SET_WRITE_CMD:                state_next_r = (app_rdy_w) ? SET_WRITE_DATA_L : SET_WRITE_CMD;

            SET_WRITE_DATA_L:             state_next_r = (app_wdf_rdy_w) ? SET_WRITE_DATA_H : SET_WRITE_DATA_L;

            SET_WRITE_DATA_H:             state_next_r = (app_wdf_rdy_w) ? IDLE_WAIT_READ_DATA : SET_WRITE_DATA_H;

            SET_READ_CMD:
                case (state_next_st_5_w)
                    2'b11:                state_next_r = SET_WRITE_CMD;
                    2'b10:                state_next_r = IDLE_WAIT_READ_DATA;
                    default:              state_next_r = SET_READ_CMD;
                endcase

            default:                      state_next_r = state_r;

        endcase


    assign idle_wait_read_data_sn_w = (state_next_r == IDLE_WAIT_READ_DATA);


    // "Защёлкиваем" входные запросы с данными
    always @(posedge ui_clk_w)
        if (ui_rst_w) begin
            wr_request_r <= 1'b0;
            rd_request_r <= 1'b0;
        end else begin
            wr_request_r <= wr_request_next_r;
            rd_request_r <= rd_request_next_r;
        end

    always @(posedge ui_clk_w)
        begin
            wr_address_r <= wr_address_next_w;
            wr_data_r    <= wr_data_next_w;
            rd_address_r <= rd_address_next_w;
        end

    assign wr_address_next_w = (idle_wait_read_data_sn_w) ? wr_address_i : wr_address_r;
    assign wr_data_next_w    = (idle_wait_read_data_sn_w) ? wr_data_i    : wr_data_r;
    assign rd_address_next_w = (idle_wait_read_data_sn_w) ? rd_address_i : rd_address_r;

    always @(*)
        case (state_next_r)
            IDLE_WAIT_READ_DATA: begin
                wr_request_next_r = wr_request_i;
                rd_request_next_r = rd_request_i;
            end
            SET_WRITE_CMD: begin
                wr_request_next_r = 1'b0;
                rd_request_next_r = rd_request_r;
            end
            SET_READ_CMD: begin
                wr_request_next_r = wr_request_r;
                rd_request_next_r = 1'b0;
            end
            default: begin
                wr_request_next_r = wr_request_r;
                rd_request_next_r = rd_request_r;
            end
        endcase


    // Логика интерфейса к контроллеру DDR памяти
    always @(posedge ui_clk_w or posedge ui_rst_w)
        if (ui_rst_w) begin
            app_en_r          <= 1'b0;
            app_wdf_wren_r    <= 1'b0;
            app_wdf_end_r     <= 1'b0;
            read_data_valid_r <= 1'b0;
        end else begin
            app_en_r          <= app_en_next_r;
            app_wdf_wren_r    <= app_wdf_wren_next_r;
            app_wdf_end_r     <= app_wdf_end_next_r;
            read_data_valid_r <= read_data_valid_next_w;
        end

    always @(posedge ui_clk_w)
        begin
            app_cmd_r         <= app_cmd_next_r;
            app_addr_r        <= app_addr_next_r;
            app_wdf_data_r    <= app_wdf_data_next_r;
            app_wdf_mask_r    <= app_wdf_mask_next_r;
            read_data_union_r <= read_data_union_next_r;
        end

    assign app_wdf_mask_union_w   = {16{1'b1}} & ~(1 << app_addr_r[3:0]);

    assign read_data_valid_h_w    = app_rd_data_valid_w &&  app_rd_data_end_w;
    assign read_data_valid_l_w    = app_rd_data_valid_w && ~app_rd_data_end_w;
    assign read_data_valid_next_w = read_data_valid_h_w;

    assign read_data_w            = read_data_parsed_w[app_addr_r[3:0]];

    assign app_addr_actual_w      = {app_addr_r[26:4], 4'b0000};

    generate
        for (genvar i = 0; i < 16; i = i + 1) begin: read_data_parser

            assign read_data_parsed_w[i] = read_data_union_r[(i * 8) +: 8];

        end
    endgenerate

    always @(*)
        case (state_next_r)
            SET_WRITE_CMD: begin
                app_cmd_next_r  = CMD_WRITE;
                app_addr_next_r = wr_address_r;
                app_en_next_r   = 1'b1;
            end
            SET_READ_CMD: begin
                app_cmd_next_r  = CMD_READ;
                app_addr_next_r = rd_address_r;
                app_en_next_r   = 1'b1;
            end
            default: begin
                app_cmd_next_r  = CMD_WRITE;
                app_addr_next_r = app_addr_r;
                app_en_next_r   = 1'b0;
            end
        endcase

    always @(*)
        case (state_next_r)
            SET_WRITE_DATA_L: begin
                app_wdf_data_next_r = {8{wr_data_r}};
                app_wdf_mask_next_r = app_wdf_mask_union_w[ 7:0];
                app_wdf_wren_next_r = 1'b1;
                app_wdf_end_next_r  = 1'b0;
            end
            SET_WRITE_DATA_H: begin
                app_wdf_data_next_r = {8{wr_data_r}};
                app_wdf_mask_next_r = app_wdf_mask_union_w[15:8];
                app_wdf_wren_next_r = 1'b1;
                app_wdf_end_next_r  = 1'b1;
            end
            default: begin
                app_wdf_data_next_r = app_wdf_data_r;
                app_wdf_mask_next_r = app_wdf_mask_r;
                app_wdf_wren_next_r = 1'b0;
                app_wdf_end_next_r  = 1'b0;
            end
        endcase

    wire [1:0] read_data_union_next_case_w = {read_data_valid_h_w, read_data_valid_l_w};
    always @(*)
        case (read_data_union_next_case_w) // one hot
            2'b01:   read_data_union_next_r = {read_data_union_r[127:64], app_rd_data_w};
            2'b10:   read_data_union_next_r = {app_rd_data_w, read_data_union_r[63:0]};
            default: read_data_union_next_r = read_data_union_r;
        endcase


    // Контроллер DDR2 памяти
    ddr2_controller
        ddr2_controller
        (
            .ddr2_addr          (ddr2_addr_o          ),
            .ddr2_ba            (ddr2_ba_o            ),
            .ddr2_ras_n         (ddr2_ras_n_o         ),
            .ddr2_cas_n         (ddr2_cas_n_o         ),
            .ddr2_we_n          (ddr2_we_n_o          ),
            .ddr2_ck_p          (ddr2_ck_p_o          ),
            .ddr2_ck_n          (ddr2_ck_n_o          ),
            .ddr2_cke           (ddr2_cke_o           ),
            .ddr2_cs_n          (ddr2_cs_n_o          ),
            .ddr2_dm            (ddr2_dm_o            ),
            .ddr2_odt           (ddr2_odt_o           ),
            .ddr2_dq            (ddr2_dq_io           ),
            .ddr2_dqs_n         (ddr2_dqs_n_io        ),
            .ddr2_dqs_p         (ddr2_dqs_p_io        ),

            .sys_clk_i          (ddr2_cntrl_clk_i     ),
            .sys_rst            (ddr2_cntrl_rst_i    ),

            .app_addr           (app_addr_actual_w    ),
            .app_cmd            (app_cmd_r            ),
            .app_en             (app_en_r             ),
            .app_rdy            (app_rdy_w            ),
            .app_wdf_rdy        (app_wdf_rdy_w        ),
            .app_wdf_data       (app_wdf_data_r       ),
            .app_wdf_end        (app_wdf_end_r        ),
            .app_wdf_mask       (app_wdf_mask_r       ),
            .app_wdf_wren       (app_wdf_wren_r       ),
            .app_rd_data        (app_rd_data_w        ),
            .app_rd_data_end    (app_rd_data_end_w    ),
            .app_rd_data_valid  (app_rd_data_valid_w  ),

            .app_sr_req         (1'b0                 ),
            .app_sr_active      (                     ),
            .app_ref_req        (1'b0                 ),
            .app_ref_ack        (                     ),
            .app_zq_req         (1'b0                 ),
            .app_zq_ack         (                     ),

            .ui_clk             (ui_clk_w             ),
            .ui_clk_sync_rst    (ui_rst_w             ),

            .init_calib_complete(init_calib_complete_w)
        );


    // Выходы
    assign ui_clk_o              = ui_clk_w;
    assign ui_rst_o              = ui_rst_w;

    assign rd_data_o             = read_data_w;
    assign rd_data_valid_o       = read_data_valid_r;

    assign cntrl_iface_is_idle_o = idle_wait_read_data_sn_w;
    assign init_calib_complete_o = init_calib_complete_w;


endmodule
