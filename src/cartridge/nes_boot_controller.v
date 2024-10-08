
/*
 * Description : NES boot controller module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module nes_boot_controller
    (
        input  wire        clk_i,                 // Сигнал тактирования контроллера SD-карт
        input  wire        rst_i,                 // Сигнал сброса контроллера SD-карт

        output wire        spi_clk_o,             // Сигнал тактирования SPI
        output wire        spi_ncs_o,             // Сигнал выбора ведомого SPI
        output wire        spi_ncs_en_o,          // Сигнал активации выхода выбора ведомого (управление буфером с 3-им состоянием)
        output wire        spi_mosi_o,            // Сигнал данных от ведущего к ведомому SPI
        output wire        spi_mosi_en_o,         // Сигнал активации выхода данных от ведущего (управление буфером с 3-им состоянием)
        input  wire        spi_miso_i,            // Сигнал данных от ведомого ведущему

        output wire        sd_disable_o,          // Сигнал выключения питания SD-карты
        output wire        sd_clk_full_speed_o,   // Сигнал активации полноскоростного тактирования контроллера SD-карт

        output wire        nes_booting_o,         // Происходит загрузка данных игры с SD-карты в память
        output wire        nes_boot_complete_o,   // Считывание данных игры завершено, NES готов к выполнению кода

        output wire [26:0] boot_data_o,           // Считываемые данные (rom игры) из SD-карты
        output wire        boot_data_valid_o,     // Флаг валидности считываемых данных
        output wire        boot_prg_received_o,   // Флаг завершения считывания данных "PRG" (код игры)
        output wire        boot_chr_received_o,   // Флаг завершения считывания данных "CHR" (графика-тайлы)
        input  wire        boot_receiver_ready_i, // Приёмник готов к приходу данных

        output wire [ 5:0] prg_banks_num_o,       // Количество блоков (16 КБ) "prg" данных в игре
        output wire [ 5:0] chr_banks_num_o,       // Количество блоков (8 КБ) "chr" данных в игре
        output wire        chr_mem_is_rom_o,      // Используемая память для графики-тайлов — "read only"
        output wire        chr_mem_is_ram_o,      // Используемая память для графики-тайлов — "random access"
        output wire [ 7:0] mapper_number_o,       // Номер используемого игрой маппера
        output wire        hw_nametable_layout_o, /* Тип "зеркалирования" оперативной видеопамяти,
                                                   * "0" — горизонтальное, "1" — вертикальное */
        output wire        alt_nametable_layout_o // Используется ли нестандартный вариант организации видеопамяти
    );


    // Состояния конечного автомата
    localparam [3:0] WAITING_SD_DDR2_READY = 0,
                     PREPARE_HEADER_READ   = 1,
                     READING_HEADER        = 2,
                     IDLE                  = 3,
                     PREPARE_DATA_READ     = 4,
                     READING_DATA          = 5,
                     CHECK_SD_BLOCK        = 6,
                     UNEXPECTED_RESULT     = 7,
                     SD_READ_FINISHED      = 8;


    // Сигналы конечного автомата
    reg  [ 3:0] state_r;
    reg  [ 3:0] state_next_r;

    wire        reading_header_sn_w;
    wire        reading_data_block_sn_w;
    wire        sd_read_finished_sn_w;

    // Логика считывания данных из SD-карты
    reg  [18:0] rom_data_counter_r;
    reg  [18:0] rom_data_counter_next_r;
    reg  [31:0] block_addr_r;
    reg  [31:0] block_addr_next_r;
    reg         header_received_r;
    wire        header_received_next_w;
    reg         prg_rom_received_r;
    wire        prg_rom_received_next_w;
    reg         chr_rom_received_r;
    wire        chr_rom_received_next_w;
    reg         start_block_read_r;
    reg         start_block_read_next_r;
    reg         read_finished_r;
    wire        read_finished_next_w;
    reg         read_result_is_ok_r;
    reg         read_result_is_ok_next_r;
    reg         boot_complete_r;
    wire        boot_complete_next_w;
    wire        nes_booting_w;

    wire        header_data_edge_w;
    wire        prg_rom_data_edge_w;
    wire        chr_rom_data_edge_w;
    wire        header_data_ready_w;
    wire        prg_rom_data_ready_w;
    wire        chr_rom_data_ready_w;
    wire        nes_data_received_w;
    wire [19:0] rom_data_counter_ex_w;
    wire [18:0] rom_data_counter_incr_w;

    wire        boot_data_valid_w;
    wire [26:0] boot_data_w;

    wire        sd_is_idle_w;
    wire        ready_to_read_data_w;
    wire        sd_cmd_result_is_ok_w;
    wire [ 8:0] sd_data_counter_w;
    wire [ 7:0] sd_data_byte_w;
    wire        sd_data_byte_received_w;

    // Сигналы "парсера" даных игры
    reg  [19:0] prg_rom_size_r;
    wire [19:0] prg_rom_size_next_w;
    reg  [18:0] chr_rom_size_r;
    wire [18:0] chr_rom_size_next_w;
    reg         hw_nametable_layout_r;
    wire        hw_nametable_layout_next_w;
    reg         alt_nametable_layout_r;
    wire        alt_nametable_layout_next_w;
    reg  [ 3:0] bot_mapper_number_r;
    wire [ 3:0] bot_mapper_number_next_w;
    reg  [ 3:0] top_mapper_number_r;
    wire [ 3:0] top_mapper_number_next_w;

    wire [ 7:0] mapper_number_w;
    wire [ 5:0] prg_banks_num_w;
    wire [ 5:0] chr_banks_num_w;
    wire        chr_mem_is_rom_w;
    wire        chr_mem_is_ram_w;

    wire        is_prg_rom_size_byte_w;
    wire        is_chr_rom_size_byte_w;
    wire        is_flags_6_byte_w;
    wire        is_flags_7_byte_w;
    wire        parsing_header_w;
    wire        get_prg_rom_size_w;
    wire        get_chr_rom_size_w;
    wire        get_nametable_layout_w;
    wire        get_alt_nametable_layout_w;
    wire        get_bot_mapper_number_w;
    wire        get_top_mapper_number_w;


    // Логика конечного автомата
    always @(posedge clk_i)
        if   (rst_i) state_r <= 4'h0;
        else         state_r <= state_next_r;

    wire [1:0] state_next_st_4_case_w = {nes_data_received_w, ready_to_read_data_w};
    always @(*)
        case (state_r)

            WAITING_SD_DDR2_READY:             state_next_r = (ready_to_read_data_w) ? PREPARE_HEADER_READ :
                                                                                       WAITING_SD_DDR2_READY;

            PREPARE_HEADER_READ:               state_next_r = READING_HEADER;

            READING_HEADER:                    state_next_r = (header_received_r) ? READING_DATA : READING_HEADER;

            IDLE:
                casez (state_next_st_4_case_w)
                    2'b1_?:                    state_next_r = SD_READ_FINISHED;
                    2'b0_1:                    state_next_r = PREPARE_DATA_READ;
                    default:                   state_next_r = IDLE;
                endcase

            PREPARE_DATA_READ:                 state_next_r = READING_DATA;

            READING_DATA:                      state_next_r = (sd_is_idle_w) ? CHECK_SD_BLOCK : READING_DATA;

            CHECK_SD_BLOCK:                    state_next_r = (read_result_is_ok_r) ? IDLE : UNEXPECTED_RESULT;

            UNEXPECTED_RESULT:                 state_next_r = SD_READ_FINISHED;

            SD_READ_FINISHED:                  state_next_r = SD_READ_FINISHED;

            default:                           state_next_r = state_r;

        endcase


    assign reading_header_sn_w     = (state_next_r == READING_HEADER);
    assign reading_data_block_sn_w = (state_next_r == READING_DATA);
    assign sd_read_finished_sn_w   = (state_next_r == SD_READ_FINISHED);

    assign ready_to_read_data_w    = sd_is_idle_w && boot_receiver_ready_i;


    /* Логика считывания данных игры с SD-карты и
     * отправки их во внутреннюю память */
    always @(posedge clk_i)
        if (rst_i) begin
            header_received_r   <= 1'b0;
            prg_rom_received_r  <= 1'b0;
            chr_rom_received_r  <= 1'b0;
            read_finished_r     <= 1'b0;
            boot_complete_r     <= 1'b0;
        end else begin
            header_received_r   <= header_received_next_w;
            prg_rom_received_r  <= prg_rom_received_next_w;
            chr_rom_received_r  <= chr_rom_received_next_w;
            read_finished_r     <= read_finished_next_w;
            boot_complete_r     <= boot_complete_next_w;
        end

    always @(posedge clk_i)
        begin
            block_addr_r        <= block_addr_next_r;
            rom_data_counter_r  <= rom_data_counter_next_r;
            start_block_read_r  <= start_block_read_next_r;
            read_result_is_ok_r <= read_result_is_ok_next_r;
        end

    assign rom_data_counter_ex_w   = {1'b0, rom_data_counter_r}; // Расширение до prg_rom_size_r
    assign header_data_edge_w      = (sd_data_counter_w     ==  9'd15);
    assign prg_rom_data_edge_w     = (rom_data_counter_ex_w == (prg_rom_size_r - 1'b1));
    assign chr_rom_data_edge_w     = (rom_data_counter_r    == (chr_rom_size_r - 1'b1));

    assign header_data_ready_w     =  header_data_edge_w  && sd_data_byte_received_w;
    assign prg_rom_data_ready_w    =  prg_rom_data_edge_w && sd_data_byte_received_w && ~prg_rom_received_r;
    assign chr_rom_data_ready_w    = (chr_rom_data_edge_w && sd_data_byte_received_w &&  prg_rom_received_r) ||
                                     (chr_mem_is_ram_w    && header_received_r);

    assign header_received_next_w  = (header_data_ready_w  ) ? 1'b1  : header_received_r;
    assign prg_rom_received_next_w = (prg_rom_data_ready_w ) ? 1'b1  : prg_rom_received_r;
    assign chr_rom_received_next_w = (chr_rom_data_ready_w ) ? 1'b1  : chr_rom_received_r;
    assign read_finished_next_w    = (sd_read_finished_sn_w) ? 1'b1  : read_finished_r;
    assign rom_data_counter_incr_w = (prg_rom_data_ready_w ) ? 19'h0 : rom_data_counter_r + sd_data_byte_received_w;

    assign nes_data_received_w     = prg_rom_received_r  && chr_rom_received_r;
    assign boot_complete_next_w    = nes_data_received_w && read_finished_r && sd_disable_o;

    assign nes_booting_w           = ~boot_complete_r;

    assign boot_data_w             = {rom_data_counter_r, sd_data_byte_w};
    assign boot_data_valid_w       = reading_data_block_sn_w && sd_data_byte_received_w && ~nes_data_received_w;

    always @(*)
        case (state_next_r)
            PREPARE_HEADER_READ: begin
                block_addr_next_r        = 32'h0;
                rom_data_counter_next_r  = 19'h0;
                start_block_read_next_r  = 1'b1;
                read_result_is_ok_next_r = 1'b0;
            end
            READING_HEADER: begin
                block_addr_next_r        = block_addr_r;
                rom_data_counter_next_r  = rom_data_counter_r;
                start_block_read_next_r  = 1'b0;
                read_result_is_ok_next_r = read_result_is_ok_r;
            end
            IDLE: begin
                block_addr_next_r        = block_addr_r;
                rom_data_counter_next_r  = rom_data_counter_r;
                start_block_read_next_r  = 1'b0;
                read_result_is_ok_next_r = read_result_is_ok_r;
            end
            PREPARE_DATA_READ: begin
                block_addr_next_r        = block_addr_r + 1'b1;
                rom_data_counter_next_r  = rom_data_counter_r;
                start_block_read_next_r  = 1'b1;
                read_result_is_ok_next_r = 1'b0;
            end
            READING_DATA: begin
                block_addr_next_r        = block_addr_r;
                rom_data_counter_next_r  = rom_data_counter_incr_w;
                start_block_read_next_r  = 1'b0;
                read_result_is_ok_next_r = read_result_is_ok_r;
            end
            CHECK_SD_BLOCK: begin
                block_addr_next_r        = block_addr_r;
                rom_data_counter_next_r  = rom_data_counter_r;
                start_block_read_next_r  = 1'b0;
                read_result_is_ok_next_r = sd_cmd_result_is_ok_w;
            end
            default: begin
                block_addr_next_r        = block_addr_r;
                rom_data_counter_next_r  = rom_data_counter_r;
                start_block_read_next_r  = 1'b0;
                read_result_is_ok_next_r = read_result_is_ok_r;
            end
        endcase


    // "Парсер" заголовка данных игры
    always @(posedge clk_i)
        if (rst_i) begin
            prg_rom_size_r         <= 20'h0;
            chr_rom_size_r         <= 19'h0;
        end else begin
            prg_rom_size_r         <= prg_rom_size_next_w;
            chr_rom_size_r         <= chr_rom_size_next_w;
        end

    always @(posedge clk_i)
        begin
            hw_nametable_layout_r  <= hw_nametable_layout_next_w;
            alt_nametable_layout_r <= alt_nametable_layout_next_w;
            bot_mapper_number_r    <= bot_mapper_number_next_w;
            top_mapper_number_r    <= top_mapper_number_next_w;
        end


    assign mapper_number_w             = {top_mapper_number_r, bot_mapper_number_r};
    assign prg_banks_num_w             = prg_rom_size_r[19:14];
    assign chr_banks_num_w             = chr_rom_size_r[18:13];
    assign chr_mem_is_rom_w            = |chr_banks_num_w;
    assign chr_mem_is_ram_w            = ~chr_mem_is_rom_w;

    // INES header format
    assign is_prg_rom_size_byte_w      = (sd_data_counter_w == 9'd4);
    assign is_chr_rom_size_byte_w      = (sd_data_counter_w == 9'd5);
    assign is_flags_6_byte_w           = (sd_data_counter_w == 9'd6);
    assign is_flags_7_byte_w           = (sd_data_counter_w == 9'd7);

    assign parsing_header_w            = reading_header_sn_w && sd_data_byte_received_w;

    assign get_prg_rom_size_w          = parsing_header_w && is_prg_rom_size_byte_w;
    assign get_chr_rom_size_w          = parsing_header_w && is_chr_rom_size_byte_w;
    assign get_nametable_layout_w      = parsing_header_w && is_flags_6_byte_w;
    assign get_alt_nametable_layout_w  = parsing_header_w && is_flags_6_byte_w;
    assign get_bot_mapper_number_w     = parsing_header_w && is_flags_6_byte_w;
    assign get_top_mapper_number_w     = parsing_header_w && is_flags_7_byte_w;

    // INES header format; "prg" and "chr" sizes converted to bytes
    assign prg_rom_size_next_w         = (get_prg_rom_size_w        ) ? (sd_data_byte_w << 14) : prg_rom_size_r;
    assign chr_rom_size_next_w         = (get_chr_rom_size_w        ) ? (sd_data_byte_w << 13) : chr_rom_size_r;
    assign hw_nametable_layout_next_w  = (get_nametable_layout_w    ) ?  sd_data_byte_w[0]     : hw_nametable_layout_r;
    assign alt_nametable_layout_next_w = (get_alt_nametable_layout_w) ?  sd_data_byte_w[3]     : alt_nametable_layout_r;
    assign bot_mapper_number_next_w    = (get_bot_mapper_number_w   ) ?  sd_data_byte_w[7:4]   : bot_mapper_number_r;
    assign top_mapper_number_next_w    = (get_top_mapper_number_w   ) ?  sd_data_byte_w[7:4]   : top_mapper_number_r;


    // Логика контроллера SD-карт
    sd_card_controller
        sd_card_controller
        (
            .clk_i                  (clk_i                  ),
            .rst_i                  (rst_i                  ),

            .spi_clk_o              (spi_clk_o              ),
            .spi_ncs_o              (spi_ncs_o              ),
            .spi_ncs_en_o           (spi_ncs_en_o           ),
            .spi_mosi_o             (spi_mosi_o             ),
            .spi_mosi_en_o          (spi_mosi_en_o          ),
            .spi_miso_i             (spi_miso_i             ),

            .sd_disable_o           (sd_disable_o           ),
            .sd_clk_full_speed_o    (sd_clk_full_speed_o    ),
            .sd_is_idle_o           (sd_is_idle_w           ),
            .sd_cmd_result_is_ok_o  (sd_cmd_result_is_ok_w  ),
            .sd_data_counter_o      (sd_data_counter_w      ),
            .sd_data_byte_o         (sd_data_byte_w         ),
            .sd_data_byte_received_o(sd_data_byte_received_w),
            .sd_block_addr_i        (block_addr_r           ),
            .sd_start_block_read_i  (start_block_read_r     ),
            .sd_read_finished_i     (read_finished_r        )
        );


    // Выходы
    assign nes_boot_complete_o    = boot_complete_r;
    assign nes_booting_o          = nes_booting_w;

    assign boot_data_o            = boot_data_w;
    assign boot_data_valid_o      = boot_data_valid_w;
    assign boot_prg_received_o    = prg_rom_received_r;
    assign boot_chr_received_o    = chr_rom_received_r;

    assign prg_banks_num_o        = prg_banks_num_w;
    assign chr_banks_num_o        = chr_banks_num_w;
    assign chr_mem_is_rom_o       = chr_mem_is_rom_w;
    assign chr_mem_is_ram_o       = chr_mem_is_ram_w;
    assign mapper_number_o        = mapper_number_w;
    assign hw_nametable_layout_o  = hw_nametable_layout_r;
    assign alt_nametable_layout_o = alt_nametable_layout_r;


endmodule
