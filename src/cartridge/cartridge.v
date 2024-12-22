
/*
 * Description : NES cartridge logic module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 *
 * Module contains logic for mappers, PRG and CHR memory units including DDR2 controller and
 * SD-card data read controller for memory initialization
 */


`include "defines.vh"


module cartridge
    (
        input  wire        prg_rom_mclk_i,      // Сигнал тактирования для постоянной памяти картриджа
        input  wire        prg_rom_rst_i,       // Сигнас сброса постоянной памяти картриджа (для логики кросс-клока)
        input  wire        prg_rom_rd_i,        // Сигнал чтения данных постоянной памяти картриджа
        input  wire [14:0] prg_rom_addr_i,      // Адрес обращения к постоянной памяти картриджа
        output wire [ 7:0] prg_rom_rd_data_o,   // Читаемые данные постоянной памяти картриджа

        input  wire        prg_ram_mclk_i,      // Сигнал тактирования для оперативной памяти картриджа
        input  wire        prg_ram_wr_i,        // Сигнал записи данных оперативной памяти картриджа
        input  wire        prg_ram_rd_i,        // Сигнал чтения данных оперативной памяти картриджа
        input  wire [12:0] prg_ram_addr_i,      // Адрес обращения к оперативной памяти картриджа
        input  wire [ 7:0] prg_ram_wr_data_i,   // Записываемые данные оперативной памяти картриджа
        output wire [ 7:0] prg_ram_rd_data_o,   // Читаемые данные оперативной памяти картриджа

        input  wire        chr_mem_mclk_i,      // Сигнал тактирования для видеопамяти картриджа
        input  wire        chr_mem_wr_i,        // Сигнал записи данных видеопамяти картриджа
        input  wire        chr_mem_rd_i,        // Сигнал чтения данных видеопамяти картриджа
        input  wire [12:0] chr_mem_addr_i,      // Адрес обращения к видеопамяти картриджа
        input  wire [ 7:0] chr_mem_wr_data_i,   // Записываемые данные видеопамяти картриджа
        output wire [ 7:0] chr_mem_rd_data_o,   // Читаемые данные видеопамяти картриджа

        input  wire        mapper_clk_i,        // Сигнал тактирования мапперов
        input  wire        mapper_rst_i,        // Сигнал сброса мапперов
        input  wire        mapper_wr_i,         // Сигнал записи в регистры мапперов
        input  wire [14:0] mapper_addr_i,       // Адрес обращения к регистрам мапперов
        input  wire [ 7:0] mapper_wr_data_i,    // Записываемые данные мапперов

        output wire [ 2:0] nametable_layout_o,  // Используемая организация оперативной видеопамяти в графическом процессоре

        output wire        mapper_irq_o,        // Прерывание от мапперов

        input  wire        sd_adjust_clk_i,     // Регулирумый сигнал тактирования контроллера SD-карт 781.250 КГц -> 50.000 МГц
        input  wire        sd_full_nobuf_clk_i, // Сигнал тактирования котроллера SD-карт без буфера для мультиплексора
        input  wire        sd_rst_i,            // Сигнал сброса контроллера SD-карт
        output wire        sd_disable_o,        // Сигнал выключения питания SD-карты
        output wire        sd_clk_full_speed_o, // Сигнал активации полноскоростного тактирования контроллера SD-карт
        output wire        nes_boot_complete_o, // Сигнал завершения считывания данных игры и их готовности к исполнению
        input  wire [ 7:0] nes_game_index_i,    // Индекс загружаемой с SD-карты игры

        output wire        spi_clk_o,           // Сигнал тактирования SPI
        output wire        spi_ncs_o,           // Сигнал выбора ведомого SPI
        output wire        spi_ncs_en_o,        // Сигнал активации выхода выбора ведомого (управление буфером с 3-им состоянием)
        output wire        spi_mosi_o,          // Сигнал данных от ведущего к ведомому SPI
        output wire        spi_mosi_en_o,       // Сигнал активации выхода данных от ведущего (управление буфером с 3-им состоянием)
        input  wire        spi_miso_i,          // Сигнал данных от ведомого ведущему

        input  wire        ddr2_cntrl_clk_i,    // Сигнал тактирования контроллера DDR памяти
        input  wire        ddr2_cntrl_rst_i,    // Сигнал сброса контроллера DDR памяти

        output wire [12:0] ddr2_addr_o,         // Линии адреса DDR памяти
        output wire [ 2:0] ddr2_ba_o,           // Линии адреса банка DDR памяти
        output wire        ddr2_ras_n_o,        // Линия команды DDR памяти "row address strobe"
        output wire        ddr2_cas_n_o,        // Линия команды DDR памяти "column address strobe"
        output wire        ddr2_we_n_o,         // Линия команды DDR памяти "write enable"
        output wire [ 0:0] ddr2_ck_p_o,         // Дифференциальный вход сигнала тактирования DDR памяти
        output wire [ 0:0] ddr2_ck_n_o,         // Дифференциальный вход сигнала тактирования DDR памяти
        output wire [ 0:0] ddr2_cke_o,          // Линия активации тактирования DDR памяти
        output wire [ 0:0] ddr2_cs_n_o,         // Линия выбора DDR памяти "chip select"
        output wire [ 1:0] ddr2_dm_o,           // Линии маскирования входных данных DDR памяти
        output wire [ 0:0] ddr2_odt_o,          // Активация встроенного в память сопротивления для соглосования портов DDR памяти
        inout  wire [15:0] ddr2_dq_io,          // Линии данных DDR памяти
        inout  wire [ 1:0] ddr2_dqs_p_io,       // Дифференциальные линии стробирования данных DDR памяти
        inout  wire [ 1:0] ddr2_dqs_n_io        // Дифференциальные линии стробирования данных DDR памяти
    );


    // Поддерживаемые мапперы
    localparam [7:0] MAPPER_NROM  = 8'd0,
                     MAPPER_MMC1  = 8'd1,
                     MAPPER_UxROM = 8'd2,
                     MAPPER_CNROM = 8'd3,
                     MAPPER_MMC3  = 8'd4,
                     MAPPER_AxROM = 8'd7;


    // Размер памяти на картридже (реализованной на block ram)
    localparam       CHR_MEM_SIZE = 256 * 1024;
    localparam       PRG_RAM_SIZE = 32  * 1024;


    // Сигналы маппера NROM
    wire [18:0] nrom_prg_rom_addr_w;
    wire [14:0] nrom_prg_ram_addr_w;
    wire [17:0] nrom_chr_mem_addr_w;
    wire [ 2:0] nrom_nametable_layout_w;

    // Сигналы маппера MMC1
    wire        mmc1_rst_w;
    wire [18:0] mmc1_prg_rom_addr_w;
    wire [14:0] mmc1_prg_ram_addr_w;
    wire [17:0] mmc1_chr_mem_addr_w;
    wire [ 2:0] mmc1_nametable_layout_w;
    wire        mmc1_prg_ram_en_w;

    // Сигналы маппера UxROM
    wire [18:0] uxrom_prg_rom_addr_w;
    wire [14:0] uxrom_prg_ram_addr_w;
    wire [17:0] uxrom_chr_mem_addr_w;
    wire [ 2:0] uxrom_nametable_layout_w;

    // Сигналы маппера CNROM
    wire [18:0] cnrom_prg_rom_addr_w;
    wire [14:0] cnrom_prg_ram_addr_w;
    wire [17:0] cnrom_chr_mem_addr_w;
    wire [ 2:0] cnrom_nametable_layout_w;

    // Сигналы маппера MMC3
    wire        mmc3_rst_w;
    wire [18:0] mmc3_prg_rom_addr_w;
    wire [14:0] mmc3_prg_ram_addr_w;
    wire [17:0] mmc3_chr_mem_addr_w;
    wire [ 2:0] mmc3_nametable_layout_w;
    wire        mmc3_prg_ram_en_w;
    wire        mmc3_prg_ram_wr_en_w;
    wire        mmc3_irq_w;

    // Сигналы маппера AxROM
    wire        axrom_rst_w;
    wire [18:0] axrom_prg_rom_addr_w;
    wire [14:0] axrom_prg_ram_addr_w;
    wire [17:0] axrom_chr_mem_addr_w;
    wire [ 2:0] axrom_nametable_layout_w;

    // Объединённые и мультиплексированные сигналы с мапперов
    reg  [18:0] mapper_prg_rom_addr_r;
    reg  [14:0] mapper_prg_ram_addr_r;
    reg  [17:0] mapper_chr_mem_addr_r;
    reg  [ 2:0] mapper_nametable_layout_r;
    reg         mapper_prg_ram_en_r;
    reg         mapper_prg_ram_wr_en_r;
    reg         mapper_irq_r;
    wire [18:0] mapper_prg_rom_addr_masked_w;
    wire [14:0] mapper_prg_ram_addr_masked_w;
    wire [17:0] mapper_chr_mem_addr_masked_w;

    // Интерфейс для постоянной памяти картриджа
    wire        prg_rom_rd_mclk_w;
    wire        prg_rom_rd_rst_w;
    wire        prg_rom_rd_w;
    wire [18:0] prg_rom_rd_addr_w;
    wire [ 7:0] prg_rom_rd_data_w;

    wire        prg_rom_wr_mclk_w;
    wire        prg_rom_wr_rst_w;
    wire        prg_rom_wr_w;
    wire [ 7:0] prg_rom_wr_data_w;
    wire        prg_rom_wr_ready_w;

    // Интерфейс для оперативной памяти картриджа
    wire        prg_ram_mclk_w;
    wire        prg_ram_rd_w;
    wire        prg_ram_wr_w;
    wire [14:0] prg_ram_addr_w;
    wire [ 7:0] prg_ram_rd_data_w;
    wire [ 7:0] prg_ram_wr_data_w;

    // Интерфейс для видеопамяти картриджа
    wire        chr_mem_mclk_w;
    wire        chr_mem_rd_w;
    wire        chr_mem_wr_w;
    wire [17:0] chr_mem_addr_w;
    wire [ 7:0] chr_mem_rd_data_w;
    wire [ 7:0] chr_mem_wr_data_w;

    // Интерфейсные сигналы контроллера чтения данных с SD-карты
    wire [26:0] boot_data_w;
    wire        boot_data_valid_w;
    wire        boot_prg_received_w;
    wire        boot_chr_received_w;
    wire        boot_receiver_ready_w;
    wire        boot_chr_mem_wr_w;
    wire        nes_booting_w;

    // Заголовочная информация об игре и её маппере
    wire [ 5:0] prg_banks_num_w;
    wire [ 5:0] chr_banks_num_w;
    wire [ 7:0] mapper_number_w;
    wire        hw_nametable_layout_w;
    wire        alt_nametable_layout_w;

    wire        chr_mem_is_rom_w;
    wire        chr_mem_is_ram_w;
    wire        prg_rom_is_512k_w;
    wire [ 5:0] last_prg_bank_addr_w;
    wire [ 5:0] last_chr_bank_addr_w;
    wire [18:0] prg_rom_addr_mask_w;
    wire [14:0] prg_ram_addr_mask_w;
    wire [17:0] chr_mem_addr_mask_w;


    /* Количество банков PRG и CHR памяти всегда является степенью двойки.
     * Банк PRG = 16 КБ (0 - 3FFF), банк CHR = 8 КБ (0 - 1FFF).
     * Максимальный размер самой объёмной официальной игры:
     * 512 КБ PRG ROM и 256 КБ CHR ROM */
    assign prg_rom_is_512k_w    = (prg_banks_num_w == 8'd32);

    assign last_prg_bank_addr_w =  prg_banks_num_w - 1'b1;
    assign last_chr_bank_addr_w = (chr_mem_is_rom_w) ? chr_banks_num_w - 1'b1 : 6'h0;

    assign prg_rom_addr_mask_w  = {last_prg_bank_addr_w[4:0], 14'h3FFF};
    assign prg_ram_addr_mask_w  = {14'h3FFF};
    assign chr_mem_addr_mask_w  = {last_chr_bank_addr_w[4:0], 13'h1FFF};

    assign axrom_rst_w          = mapper_rst_i || (mapper_number_w != MAPPER_AxROM);
    assign mmc1_rst_w           = mapper_rst_i || (mapper_number_w != MAPPER_MMC1);
    assign mmc3_rst_w           = mapper_rst_i || (mapper_number_w != MAPPER_MMC3);


    // Маппер NROM
    mapper_nrom
        mapper_nrom
        (
            .prg_rom_addr_i          (prg_rom_addr_i          ),
            .prg_ram_addr_i          (prg_ram_addr_i          ),
            .chr_mem_addr_i          (chr_mem_addr_i          ),
            .hw_nametable_layout_i   (hw_nametable_layout_w   ),
            .nrom_prg_rom_addr_o     (nrom_prg_rom_addr_w     ),
            .nrom_prg_ram_addr_o     (nrom_prg_ram_addr_w     ),
            .nrom_chr_mem_addr_o     (nrom_chr_mem_addr_w     ),
            .nrom_nametable_layout_o (nrom_nametable_layout_w )
        );


    // Маппер MMC1
    mapper_mmc1
        mapper_mmc1
        (
            .clk_i                   (mapper_clk_i            ),
            .rst_i                   (mmc1_rst_w              ),
            .mapper_wr_i             (mapper_wr_i             ),
            .mapper_addr_i           (mapper_addr_i           ),
            .mapper_wr_data_i        (mapper_wr_data_i        ),
            .prg_rom_addr_i          (prg_rom_addr_i          ),
            .prg_ram_addr_i          (prg_ram_addr_i          ),
            .chr_mem_addr_i          (chr_mem_addr_i          ),
            .prg_rom_is_512k_i       (prg_rom_is_512k_w       ),
            .chr_mem_is_ram_i        (chr_mem_is_ram_w        ),
            .mmc1_prg_rom_addr_o     (mmc1_prg_rom_addr_w     ),
            .mmc1_prg_ram_addr_o     (mmc1_prg_ram_addr_w     ),
            .mmc1_chr_mem_addr_o     (mmc1_chr_mem_addr_w     ),
            .mmc1_nametable_layout_o (mmc1_nametable_layout_w ),
            .mmc1_prg_ram_en_o       (mmc1_prg_ram_en_w       )
        );


    // Маппер UxROM
    mapper_uxrom
        mapper_uxrom
        (
            .clk_i                   (mapper_clk_i            ),
            .mapper_wr_i             (mapper_wr_i             ),
            .mapper_wr_data_i        (mapper_wr_data_i        ),
            .prg_rom_addr_i          (prg_rom_addr_i          ),
            .prg_ram_addr_i          (prg_ram_addr_i          ),
            .chr_mem_addr_i          (chr_mem_addr_i          ),
            .hw_nametable_layout_i   (hw_nametable_layout_w   ),
            .uxrom_prg_rom_addr_o    (uxrom_prg_rom_addr_w    ),
            .uxrom_prg_ram_addr_o    (uxrom_prg_ram_addr_w    ),
            .uxrom_chr_mem_addr_o    (uxrom_chr_mem_addr_w    ),
            .uxrom_nametable_layout_o(uxrom_nametable_layout_w)
        );


    // Маппер CNROM
    mapper_cnrom
        mapper_cnrom
        (
            .clk_i                   (mapper_clk_i            ),
            .mapper_wr_i             (mapper_wr_i             ),
            .mapper_wr_data_i        (mapper_wr_data_i        ),
            .prg_rom_addr_i          (prg_rom_addr_i          ),
            .prg_ram_addr_i          (prg_ram_addr_i          ),
            .chr_mem_addr_i          (chr_mem_addr_i          ),
            .hw_nametable_layout_i   (hw_nametable_layout_w   ),
            .cnrom_prg_rom_addr_o    (cnrom_prg_rom_addr_w    ),
            .cnrom_prg_ram_addr_o    (cnrom_prg_ram_addr_w    ),
            .cnrom_chr_mem_addr_o    (cnrom_chr_mem_addr_w    ),
            .cnrom_nametable_layout_o(cnrom_nametable_layout_w)
        );


    // Маппер MMC3
    mapper_mmc3
        mapper_mmc3
        (
            .clk_i                   (mapper_clk_i            ),
            .rst_i                   (mmc3_rst_w              ),
            .mapper_wr_i             (mapper_wr_i             ),
            .mapper_addr_i           (mapper_addr_i           ),
            .mapper_wr_data_i        (mapper_wr_data_i        ),
            .prg_rom_addr_i          (prg_rom_addr_i          ),
            .prg_ram_addr_i          (prg_ram_addr_i          ),
            .chr_mem_addr_i          (chr_mem_addr_i          ),
            .alt_nametable_layout_i  (alt_nametable_layout_w  ),
            .mmc3_prg_rom_addr_o     (mmc3_prg_rom_addr_w     ),
            .mmc3_prg_ram_addr_o     (mmc3_prg_ram_addr_w     ),
            .mmc3_chr_mem_addr_o     (mmc3_chr_mem_addr_w     ),
            .mmc3_nametable_layout_o (mmc3_nametable_layout_w ),
            .mmc3_prg_ram_en_o       (mmc3_prg_ram_en_w       ),
            .mmc3_prg_ram_wr_en_o    (mmc3_prg_ram_wr_en_w    ),
            .mmc3_irq_o              (mmc3_irq_w              )
        );


    // Маппер AxROM
    mapper_axrom
        mapper_axrom
        (
            .clk_i                   (mapper_clk_i            ),
            .rst_i                   (axrom_rst_w             ),
            .mapper_wr_i             (mapper_wr_i             ),
            .mapper_wr_data_i        (mapper_wr_data_i        ),
            .prg_rom_addr_i          (prg_rom_addr_i          ),
            .prg_ram_addr_i          (prg_ram_addr_i          ),
            .chr_mem_addr_i          (chr_mem_addr_i          ),
            .axrom_prg_rom_addr_o    (axrom_prg_rom_addr_w    ),
            .axrom_prg_ram_addr_o    (axrom_prg_ram_addr_w    ),
            .axrom_chr_mem_addr_o    (axrom_chr_mem_addr_w    ),
            .axrom_nametable_layout_o(axrom_nametable_layout_w)
        );


    // Мультиплексирование мапперов
    always @(*)
        case (mapper_number_w)
            MAPPER_NROM: begin
                mapper_prg_rom_addr_r     = nrom_prg_rom_addr_w;
                mapper_prg_ram_addr_r     = nrom_prg_ram_addr_w;
                mapper_chr_mem_addr_r     = nrom_chr_mem_addr_w;
                mapper_nametable_layout_r = nrom_nametable_layout_w;
                mapper_prg_ram_en_r       = 1'b1;
                mapper_prg_ram_wr_en_r    = 1'b1;
                mapper_irq_r              = 1'b0;
            end
            MAPPER_MMC1: begin
                mapper_prg_rom_addr_r     = mmc1_prg_rom_addr_w;
                mapper_prg_ram_addr_r     = mmc1_prg_ram_addr_w;
                mapper_chr_mem_addr_r     = mmc1_chr_mem_addr_w;
                mapper_nametable_layout_r = mmc1_nametable_layout_w;
                mapper_prg_ram_en_r       = mmc1_prg_ram_en_w;
                mapper_prg_ram_wr_en_r    = 1'b1;
                mapper_irq_r              = 1'b0;
            end
            MAPPER_UxROM: begin
                mapper_prg_rom_addr_r     = uxrom_prg_rom_addr_w;
                mapper_prg_ram_addr_r     = uxrom_prg_ram_addr_w;
                mapper_chr_mem_addr_r     = uxrom_chr_mem_addr_w;
                mapper_nametable_layout_r = uxrom_nametable_layout_w;
                mapper_prg_ram_en_r       = 1'b1;
                mapper_prg_ram_wr_en_r    = 1'b1;
                mapper_irq_r              = 1'b0;
            end
            MAPPER_CNROM: begin
                mapper_prg_rom_addr_r     = cnrom_prg_rom_addr_w;
                mapper_prg_ram_addr_r     = cnrom_prg_ram_addr_w;
                mapper_chr_mem_addr_r     = cnrom_chr_mem_addr_w;
                mapper_nametable_layout_r = cnrom_nametable_layout_w;
                mapper_prg_ram_en_r       = 1'b1;
                mapper_prg_ram_wr_en_r    = 1'b1;
                mapper_irq_r              = 1'b0;
            end
            MAPPER_MMC3:  begin
                mapper_prg_rom_addr_r     = mmc3_prg_rom_addr_w;
                mapper_prg_ram_addr_r     = mmc3_prg_ram_addr_w;
                mapper_chr_mem_addr_r     = mmc3_chr_mem_addr_w;
                mapper_nametable_layout_r = mmc3_nametable_layout_w;
                mapper_prg_ram_en_r       = mmc3_prg_ram_en_w;
                mapper_prg_ram_wr_en_r    = mmc3_prg_ram_wr_en_w;
                mapper_irq_r              = mmc3_irq_w;
            end
            MAPPER_AxROM: begin
                mapper_prg_rom_addr_r     = axrom_prg_rom_addr_w;
                mapper_prg_ram_addr_r     = axrom_prg_ram_addr_w;
                mapper_chr_mem_addr_r     = axrom_chr_mem_addr_w;
                mapper_nametable_layout_r = axrom_nametable_layout_w;
                mapper_prg_ram_en_r       = 1'b1;
                mapper_prg_ram_wr_en_r    = 1'b1;
                mapper_irq_r              = 1'b0;
            end
            default: begin
                mapper_prg_rom_addr_r     = 19'h0;
                mapper_prg_ram_addr_r     = 15'h0;
                mapper_chr_mem_addr_r     = 18'h0;
                mapper_nametable_layout_r = 3'h0;
                mapper_prg_ram_en_r       = 1'b0;
                mapper_prg_ram_wr_en_r    = 1'b0;
                mapper_irq_r              = 1'b0;
            end
        endcase

    assign mapper_prg_rom_addr_masked_w = mapper_prg_rom_addr_r & prg_rom_addr_mask_w;
    assign mapper_prg_ram_addr_masked_w = mapper_prg_ram_addr_r & prg_ram_addr_mask_w;
    assign mapper_chr_mem_addr_masked_w = mapper_chr_mem_addr_r & chr_mem_addr_mask_w;


    // Интерфейс и доступ к памяти на картридже
    assign boot_prg_rom_wr_w     = boot_data_valid_w && ~boot_prg_received_w;
    assign boot_chr_mem_wr_w     = boot_data_valid_w &&  boot_prg_received_w && ~boot_chr_received_w;
    assign boot_receiver_ready_w = (boot_prg_received_w) ? 1'b1 : prg_rom_wr_ready_w;

    assign prg_rom_rd_mclk_w     = prg_rom_mclk_i;
    assign prg_rom_rd_rst_w      = prg_rom_rst_i;
    assign prg_rom_rd_w          = prg_rom_rd_i;
    assign prg_rom_rd_addr_w     = mapper_prg_rom_addr_masked_w;

    assign prg_rom_wr_mclk_w     = sd_adjust_clk_i;
    assign prg_rom_wr_rst_w      = sd_rst_i;
    assign prg_rom_wr_w          = boot_prg_rom_wr_w;
    assign prg_rom_wr_data_w     = boot_data_w[7:0];

    assign prg_ram_mclk_w        = prg_ram_mclk_i;
    assign prg_ram_rd_w          = mapper_prg_ram_en_r && prg_ram_rd_i;
    assign prg_ram_wr_w          = mapper_prg_ram_en_r && mapper_prg_ram_wr_en_r && prg_ram_wr_i;
    assign prg_ram_addr_w        = mapper_prg_ram_addr_masked_w;
    assign prg_ram_wr_data_w     = prg_ram_wr_data_i;

    assign chr_mem_rd_w          = chr_mem_rd_i;
    assign chr_mem_wr_w          = (nes_booting_w) ? boot_chr_mem_wr_w : chr_mem_wr_i;
    assign chr_mem_addr_w        = (nes_booting_w) ? boot_data_w[25:8] : mapper_chr_mem_addr_masked_w;
    assign chr_mem_wr_data_w     = (nes_booting_w) ? boot_data_w[ 7:0] : chr_mem_wr_data_i;


    /* Мультиплексирование тактового сигнала для видеопамяти,
     * при инициализации используется тактовый сигнал от SD-контроллера,
     * при рендере графики используется тактовый сигнал видеопроцессора */
    BUFGMUX_CTRL
        chr_mem_mclk_mux_ctrl
        (
            .O                       (chr_mem_mclk_w          ),
            .I0                      (chr_mem_mclk_i          ),
            .I1                      (sd_full_nobuf_clk_i     ),
            .S                       (nes_booting_w           )
        );


    // Видеопамять картриджа — BRAM
    single_port_no_change_ram
        #(
            .DATA_WIDTH              (8                       ),
            .RAM_DEPTH               (CHR_MEM_SIZE            ),
            .RAM_STYLE               ("block"                 ),
            .INIT_VAL                (`MEM_INIT_VAL           ),
            .SIMULATION              (`MEM_SIM                )
        )
        chr_mem
        (
            .clka_i                  (chr_mem_mclk_w          ),
            .addra_i                 (chr_mem_addr_w          ),
            .rda_i                   (chr_mem_rd_w            ),
            .wra_i                   (chr_mem_wr_w            ),
            .dina_i                  (chr_mem_wr_data_w       ),
            .douta_o                 (chr_mem_rd_data_w       )
        );


    // Оперативная память картриджа — BRAM
    single_port_no_change_ram
        #(
            .DATA_WIDTH              (8                       ),
            .RAM_DEPTH               (PRG_RAM_SIZE            ),
            .RAM_STYLE               ("block"                 ),
            .INIT_VAL                (`MEM_INIT_VAL           ),
            .SIMULATION              (`MEM_SIM                )
        )
        prg_ram
        (
            .clka_i                  (prg_ram_mclk_w          ),
            .addra_i                 (prg_ram_addr_w          ),
            .rda_i                   (prg_ram_rd_w            ),
            .wra_i                   (prg_ram_wr_w            ),
            .dina_i                  (prg_ram_wr_data_w       ),
            .douta_o                 (prg_ram_rd_data_w       )
        );


    // Постоянная память картриджа — контроллер DDR памяти с интерфейсом
    ddr2_user_interface
        ddr2_user_interface
        (
            .ddr2_addr_o             (ddr2_addr_o             ),
            .ddr2_ba_o               (ddr2_ba_o               ),
            .ddr2_ras_n_o            (ddr2_ras_n_o            ),
            .ddr2_cas_n_o            (ddr2_cas_n_o            ),
            .ddr2_we_n_o             (ddr2_we_n_o             ),
            .ddr2_ck_p_o             (ddr2_ck_p_o             ),
            .ddr2_ck_n_o             (ddr2_ck_n_o             ),
            .ddr2_cke_o              (ddr2_cke_o              ),
            .ddr2_cs_n_o             (ddr2_cs_n_o             ),
            .ddr2_dm_o               (ddr2_dm_o               ),
            .ddr2_odt_o              (ddr2_odt_o              ),
            .ddr2_dq_io              (ddr2_dq_io              ),
            .ddr2_dqs_p_io           (ddr2_dqs_p_io           ),
            .ddr2_dqs_n_io           (ddr2_dqs_n_io           ),

            .ddr2_cntrl_clk_i        (ddr2_cntrl_clk_i        ),
            .ddr2_cntrl_rst_i        (ddr2_cntrl_rst_i        ),

            .prg_rom_wr_mclk_i       (prg_rom_wr_mclk_w       ),
            .prg_rom_wr_rst_i        (prg_rom_wr_rst_w        ),
            .prg_rom_wr_i            (prg_rom_wr_w            ),
            .prg_rom_wr_data_i       (prg_rom_wr_data_w       ),
            .prg_rom_wr_ready_o      (prg_rom_wr_ready_w      ),

            .prg_rom_rd_mclk_i       (prg_rom_rd_mclk_w       ),
            .prg_rom_rd_rst_i        (prg_rom_rd_rst_w        ),
            .prg_rom_rd_i            (prg_rom_rd_w            ),
            .prg_rom_rd_addr_i       (prg_rom_rd_addr_w       ),
            .prg_rom_rd_data_o       (prg_rom_rd_data_w       )
        );


    // Контроллер загрузки NES — чтение образа игры с SD-карты
    nes_boot_controller
        nes_boot_controller
        (
            .clk_i                   (sd_adjust_clk_i         ),
            .rst_i                   (sd_rst_i                ),

            .spi_clk_o               (spi_clk_o               ),
            .spi_ncs_o               (spi_ncs_o               ),
            .spi_ncs_en_o            (spi_ncs_en_o            ),
            .spi_mosi_o              (spi_mosi_o              ),
            .spi_mosi_en_o           (spi_mosi_en_o           ),
            .spi_miso_i              (spi_miso_i              ),

            .sd_disable_o            (sd_disable_o            ),
            .sd_clk_full_speed_o     (sd_clk_full_speed_o     ),

            .nes_game_index_i        (nes_game_index_i        ),
            .nes_booting_o           (nes_booting_w           ),
            .nes_boot_complete_o     (nes_boot_complete_o     ),

            .boot_data_o             (boot_data_w             ),
            .boot_data_valid_o       (boot_data_valid_w       ),
            .boot_prg_received_o     (boot_prg_received_w     ),
            .boot_chr_received_o     (boot_chr_received_w     ),
            .boot_receiver_ready_i   (boot_receiver_ready_w   ),

            .prg_banks_num_o         (prg_banks_num_w         ),
            .chr_banks_num_o         (chr_banks_num_w         ),
            .chr_mem_is_rom_o        (chr_mem_is_rom_w        ),
            .chr_mem_is_ram_o        (chr_mem_is_ram_w        ),
            .mapper_number_o         (mapper_number_w         ),
            .hw_nametable_layout_o   (hw_nametable_layout_w   ),
            .alt_nametable_layout_o  (alt_nametable_layout_w  )
        );


    // Выходы
    assign prg_rom_rd_data_o  = prg_rom_rd_data_w;
    assign prg_ram_rd_data_o  = prg_ram_rd_data_w;
    assign chr_mem_rd_data_o  = chr_mem_rd_data_w;
    assign nametable_layout_o = mapper_nametable_layout_r;
    assign mapper_irq_o       = mapper_irq_r;


endmodule
