
/*
 * Description : DDR2 user interface (CDC for write data and read data and interface to DDR2 controller) module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module ddr2_user_interface
    (
        output wire [12:0] ddr2_addr_o,        // Линии адреса DDR памяти
        output wire [ 2:0] ddr2_ba_o,          // Линии адреса банка DDR памяти
        output wire        ddr2_ras_n_o,       // Линия команды DDR памяти "row address strobe"
        output wire        ddr2_cas_n_o,       // Линия команды DDR памяти "column address strobe"
        output wire        ddr2_we_n_o,        // Линия команды DDR памяти "write enable"
        output wire [ 0:0] ddr2_ck_p_o,        // Дифференциальный вход сигнала тактирования DDR памяти
        output wire [ 0:0] ddr2_ck_n_o,        // Дифференциальный вход сигнала тактирования DDR памяти
        output wire [ 0:0] ddr2_cke_o,         // Линия активации тактирования DDR памяти
        output wire [ 0:0] ddr2_cs_n_o,        // Линия выбора DDR памяти "chip select"
        output wire [ 1:0] ddr2_dm_o,          // Линии маскирования входных данных DDR памяти
        output wire [ 0:0] ddr2_odt_o,         // Активация встроенного в память сопротивления для соглосования портов DDR памяти
        inout  wire [15:0] ddr2_dq_io,         // Линии данных DDR памяти
        inout  wire [ 1:0] ddr2_dqs_p_io,      // Дифференциальные линии стробирования данных DDR памяти
        inout  wire [ 1:0] ddr2_dqs_n_io,      // Дифференциальные линии стробирования данных DDR памяти

        input  wire        ddr2_cntrl_clk_i,   // Сигнал тактирования контроллера DDR памяти
        input  wire        ddr2_cntrl_rst_i,   // Сигнал сброса контроллера DDR памяти

        input  wire        prg_rom_wr_mclk_i,  // Сигнал тактирования для записи постоянной памяти картриджа
        input  wire        prg_rom_wr_rst_i,   // Сигнас сброса для записи постоянной памяти картриджа (для асинхронного фифо)
        input  wire        prg_rom_wr_i,       // Сигнал записи данных постоянной памяти картриджа
        input  wire [ 7:0] prg_rom_wr_data_i,  // Записываемые данные (rom игры) из SD-карты
        output wire        prg_rom_wr_ready_o, // Контроллер DDR доступен к приёму новых данных

        input  wire        prg_rom_rd_mclk_i,  // Сигнал тактирования для чтения постоянной памяти картриджа
        input  wire        prg_rom_rd_rst_i,   // Сигнас сброса для чтения постоянной памяти картриджа (для логики кросс-клока)
        input  wire        prg_rom_rd_i,       // Сигнал чтения данных постоянной памяти картриджа
        input  wire [18:0] prg_rom_rd_addr_i,  // Адрес обращения к постоянной памяти картриджа
        output wire [ 7:0] prg_rom_rd_data_o   // Читаемые данные постоянной памяти картриджа
    );


    // Сигналы интерфейса контроллера DDR
    wire        ui_clk_w;
    wire        ui_rst_w;
    wire        cntrl_iface_is_idle_w;
    wire        ui_ddr2_calib_complete_w;

    /* Логика пересечения тактовых доменов
     * при чтении кода игры процессором */
    wire        rdprg_wd_clk_w;
    wire        rdprg_wd_rst_w;
    wire [18:0] rdprg_wd_data_w;
    wire        rdprg_wd_valid_w;
    wire        rdprg_rd_clk_w;
    wire        rdprg_rd_rst_w;
    wire        rdprg_rd_ready_w;
    wire [18:0] rdprg_rd_data_w;
    wire        rdprg_rd_valid_w;

    /* Логика пересечения тактовых доменов
     * при записи кода игры при инициализации */
    wire        wrsd_wd_clk_w;
    wire        wrsd_wd_rst_w;
    wire [ 7:0] wrsd_wd_data_w;
    wire        wrsd_wd_write_w;
    wire        wrsd_rd_clk_w;
    wire        wrsd_rd_rst_w;
    wire        wrsd_rd_read_w;
    wire [ 7:0] wrsd_rd_data_w;
    wire        wrsd_rd_empty_w;
    reg         wrsd_rd_valid_r;
    wire        wrsd_rd_valid_next_w;
    reg  [18:0] wrsd_rd_address_r;
    wire [18:0] wrsd_rd_address_next_w;

    // Сигналы для интерфейса контроллеа DDR
    wire [26:0] ui_wr_address_w;
    wire [ 7:0] ui_wr_data_w;
    wire        ui_wr_request_w;

    wire [26:0] ui_rd_address_w;
    wire        ui_rd_request_w;
    wire        ui_rd_data_valid_w;
    wire [ 7:0] ui_rd_data_w;

    // Код игры, прочитанный из DDR памяти
    reg  [ 7:0] prg_rom_rd_data_r;
    wire [ 7:0] prg_rom_rd_data_next_w;

    // Сигнал готовности DDR к приёму для SD-карты
    (* DONT_TOUCH = "TRUE" *)
    reg         ui_ddr2_ready_r;
    wire        ui_ddr2_ready_next_w;
    (* ASYNC_REG = "TRUE" *)
    reg  [ 1:0] prg_rom_wr_ready_r;
    wire [ 1:0] prg_rom_wr_ready_next_w;


    // Логика считывания данных из DDR памяти в процессе исполения кода игры
    assign rdprg_wd_clk_w   = prg_rom_rd_mclk_i;
    assign rdprg_wd_rst_w   = prg_rom_rd_rst_i;
    assign rdprg_wd_data_w  = prg_rom_rd_addr_i;
    assign rdprg_wd_valid_w = prg_rom_rd_i;

    assign rdprg_rd_clk_w   = ui_clk_w;
    assign rdprg_rd_rst_w   = ui_rst_w;
    assign rdprg_rd_ready_w = cntrl_iface_is_idle_w;


    // Пресечение тактовых доменов для адреса очередной исполяемой инструкции
    cross_clock_path
        #(
            .DATA_WIDTH           (19                      ),
            .USE_ACKNOWLEDGEMENT  ("FALSE"                 )
        )
        cross_read_prg
        (
            .wd_clk_i             (rdprg_wd_clk_w          ),
            .wd_rst_i             (rdprg_wd_rst_w          ),
            .wd_valid_i           (rdprg_wd_valid_w        ),
            .wd_data_i            (rdprg_wd_data_w         ),
            .wd_ready_o           (                        ),

            .rd_clk_i             (rdprg_rd_clk_w          ),
            .rd_rst_i             (rdprg_rd_rst_w          ),
            .rd_ready_i           (rdprg_rd_ready_w        ),
            .rd_data_o            (rdprg_rd_data_w         ),
            .rd_valid_o           (rdprg_rd_valid_w        )
        );


    /* Логика записи данных в DDR память при её инициализации кодом игры,
     * прочитанным из SD-карты */
    assign wrsd_wd_clk_w   = prg_rom_wr_mclk_i;
    assign wrsd_wd_rst_w   = prg_rom_wr_rst_i;
    assign wrsd_wd_data_w  = prg_rom_wr_data_i;
    assign wrsd_wd_write_w = prg_rom_wr_i;

    assign wrsd_rd_clk_w   = ui_clk_w;
    assign wrsd_rd_rst_w   = ui_rst_w;
    assign wrsd_rd_read_w  = cntrl_iface_is_idle_w;

    always @(posedge wrsd_rd_clk_w)
        if (wrsd_rd_rst_w) begin
            wrsd_rd_address_r <= 19'h0;
            wrsd_rd_valid_r   <= 1'b0;
        end else begin
            wrsd_rd_address_r <= wrsd_rd_address_next_w;
            wrsd_rd_valid_r   <= wrsd_rd_valid_next_w;
        end

    assign wrsd_rd_valid_next_w   = cntrl_iface_is_idle_w && ~wrsd_rd_empty_w;
    assign wrsd_rd_address_next_w = wrsd_rd_address_r + wrsd_rd_valid_r;


    // Пресечение тактовых доменов для данных очередной инструкции, загружаемой с SD-карты
    async_fifo
        #(
            .DATA_WIDTH           (8                       ),
            .FIFO_DEPTH           (512                     )
        )
        async_fifo_write_sd
        (
            .wd_clk_i             (wrsd_wd_clk_w           ),
            .wd_rst_i             (wrsd_wd_rst_w           ),
            .wd_write_i           (wrsd_wd_write_w         ),
            .wd_data_i            (wrsd_wd_data_w          ),
            .wd_full_o            (                        ),

            .rd_clk_i             (wrsd_rd_clk_w           ),
            .rd_rst_i             (wrsd_rd_rst_w           ),
            .rd_read_i            (wrsd_rd_read_w          ),
            .rd_data_o            (wrsd_rd_data_w          ),
            .rd_empty_o           (wrsd_rd_empty_w         )
        );


    // Подготовленные сигналы для интерфеса контроллера DDR
    assign ui_wr_address_w = {8'h0, wrsd_rd_address_r};
    assign ui_wr_data_w    = wrsd_rd_data_w;
    assign ui_wr_request_w = wrsd_rd_valid_r;

    assign ui_rd_address_w = {8'h0, rdprg_rd_data_w[18:0]};
    assign ui_rd_request_w = rdprg_rd_valid_w;


    // Интерфейс контроллера DDR
    ddr2_controller_interface
        ddr2_controller_interface
        (
            .ddr2_addr_o          (ddr2_addr_o             ),
            .ddr2_ba_o            (ddr2_ba_o               ),
            .ddr2_ras_n_o         (ddr2_ras_n_o            ),
            .ddr2_cas_n_o         (ddr2_cas_n_o            ),
            .ddr2_we_n_o          (ddr2_we_n_o             ),
            .ddr2_ck_p_o          (ddr2_ck_p_o             ),
            .ddr2_ck_n_o          (ddr2_ck_n_o             ),
            .ddr2_cke_o           (ddr2_cke_o              ),
            .ddr2_cs_n_o          (ddr2_cs_n_o             ),
            .ddr2_dm_o            (ddr2_dm_o               ),
            .ddr2_odt_o           (ddr2_odt_o              ),
            .ddr2_dq_io           (ddr2_dq_io              ),
            .ddr2_dqs_p_io        (ddr2_dqs_p_io           ),
            .ddr2_dqs_n_io        (ddr2_dqs_n_io           ),

            .ddr2_cntrl_clk_i     (ddr2_cntrl_clk_i        ),
            .ddr2_cntrl_rst_i     (ddr2_cntrl_rst_i        ),
            .ui_clk_o             (ui_clk_w                ),
            .ui_rst_o             (ui_rst_w                ),

            .rd_request_i         (ui_rd_request_w         ),
            .rd_address_i         (ui_rd_address_w         ),
            .rd_data_o            (ui_rd_data_w            ),
            .rd_data_valid_o      (ui_rd_data_valid_w      ),

            .wr_request_i         (ui_wr_request_w         ),
            .wr_address_i         (ui_wr_address_w         ),
            .wr_data_i            (ui_wr_data_w            ),

            .cntrl_iface_is_idle_o(cntrl_iface_is_idle_w   ),
            .init_calib_complete_o(ui_ddr2_calib_complete_w)
        );


    // Защёлкивание прочитанных из DDR инструкций в процессе исполнения кода игры
    always @(posedge ui_clk_w)
        prg_rom_rd_data_r <= prg_rom_rd_data_next_w;

    assign prg_rom_rd_data_next_w = (ui_rd_data_valid_w) ? ui_rd_data_w : prg_rom_rd_data_r;


    // Перемещение сигнала готовности DDR к новому блоку данных в тактовый домен контроллера SD-карты
    always @(posedge ui_clk_w)
        if (ui_rst_w) begin
            ui_ddr2_ready_r    <= 1'b0;
        end else begin
            ui_ddr2_ready_r    <= ui_ddr2_ready_next_w;
        end

    always @(posedge prg_rom_wr_mclk_i)
        if (prg_rom_wr_rst_i) begin
            prg_rom_wr_ready_r <= 2'h0;
        end else begin
            prg_rom_wr_ready_r <= prg_rom_wr_ready_next_w;
        end

    assign ui_ddr2_ready_next_w    = ui_ddr2_calib_complete_w && wrsd_rd_empty_w;
    assign prg_rom_wr_ready_next_w = {prg_rom_wr_ready_r[0], ui_ddr2_ready_r};


    // Выходы
    assign prg_rom_rd_data_o  = prg_rom_rd_data_r;
    assign prg_rom_wr_ready_o = prg_rom_wr_ready_r[1];


endmodule
