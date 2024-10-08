
/*
 * Description : MMC3 (№4) mapper module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module mapper_mmc3
    (
        input  wire        clk_i,                   // Сигнал тактирования
        input  wire        rst_i,                   // Сигнал сброса

        input  wire        mapper_wr_i,             // Сигнал записи в регистры маппера
        input  wire [14:0] mapper_addr_i,           // Адрес обращения к регистрам маппера
        input  wire [ 7:0] mapper_wr_data_i,        // Записываемые данные в регистры маппера

        input  wire [14:0] prg_rom_addr_i,          // Адрес обращения к постоянной памяти программы картриджа
        input  wire [12:0] prg_ram_addr_i,          // Адрес обращения к оперативной памяти картриджа
        input  wire [12:0] chr_mem_addr_i,          // Адрес обращения к видеопамяти картриджа

        input  wire        alt_nametable_layout_i,  // Используется ли нестандартный вариант организации видеопамяти

        output wire [18:0] mmc3_prg_rom_addr_o,     // Расширенный адрес обращения к постоянной памяти программы картриджа
        output wire [14:0] mmc3_prg_ram_addr_o,     // Расширенный адрес обращения к оперативной памяти картриджа
        output wire [17:0] mmc3_chr_mem_addr_o,     // Расширенный адрес обращения к видеопамяти картриджа
        output wire [ 2:0] mmc3_nametable_layout_o, // Используемая организация оперативной видеопамяти
        output wire        mmc3_prg_ram_en_o,       // Сигнал разрешения работы оперативной памяти на картридже
        output wire        mmc3_prg_ram_wr_en_o,    // Сигнал разрешения записи в оперативную память картриджа
        output wire        mmc3_irq_o               // Прерывание от маппера
    );


    `include "localparam_nametable_layout.vh"


    // Регистры и сигналы маппера
    reg  [ 4:0] bank_select_reg_r;
    wire [ 4:0] bank_select_reg_next_w;
    wire        bank_select_reg_en_w;
    wire        bank_select_reg_wr_w;
    reg         mirroring_reg_r;
    wire        mirroring_reg_next_w;
    wire        mirroring_reg_en_w;
    wire        mirroring_reg_wr_w;
    reg  [ 1:0] prg_ram_protect_reg_r;
    wire [ 1:0] prg_ram_protect_reg_next_w;
    wire        prg_ram_protect_reg_en_w;
    wire        prg_ram_protect_reg_wr_w;

    reg  [ 7:0] addr_data_reg_r     [7:0];
    wire [ 7:0] addr_data_reg_next_w[7:0];
    wire        addr_data_reg_wr_w  [7:0];
    wire        bank_data_reg_en_w;
    wire        bank_data_reg_wr_w;

    wire        prg_rom_bank_mode_w;
    wire        chr_mem_a12_invert_w;
    wire        chr_mem_a12_w;

    reg  [18:0] mmc3_prg_rom_addr_r;
    wire [14:0] mmc3_prg_ram_addr_w;
    reg  [17:0] mmc3_chr_mem_addr_r;
    reg  [ 2:0] mmc3_nametable_layout_r;
    wire        mmc3_prg_ram_en_w;
    wire        mmc3_prg_ram_wr_en_w;

    // Регистры и сигналы генерации прерывания
    reg  [ 7:0] irq_latch_reg_r;
    wire [ 7:0] irq_latch_reg_next_w;
    reg  [ 7:0] irq_counter_r;
    reg  [ 7:0] irq_counter_next_r;
    reg         irq_enabled_r;
    reg         irq_enabled_next_r;
    reg         irq_reload_req_r;
    reg         irq_reload_req_next_r;
    reg         mmc3_irq_r;
    reg         mmc3_irq_next_r;

    reg         irq_a12_r;
    reg  [ 2:0] irq_a12_prev_r;
    wire [ 2:0] irq_a12_prev_next_w;
    wire        irq_a12_posedge_w;

    wire        irq_latch_reg_en_w;
    wire        irq_latch_reg_wr_w;
    wire        irq_disable_reg_en_w;
    wire        irq_disable_reg_wr_w;
    wire        irq_enable_reg_en_w;
    wire        irq_enable_reg_wr_w;
    wire        irq_reload_reg_en_w;
    wire        irq_reload_reg_wr_w;
    wire        irq_zero_flag_w;
    wire        irq_zero_transition_w;
    wire        irq_reload_cond_w;
    wire        mmc3_irq_trigger_w;


    // Логика записи данных в регистры маппера и самого маппинга
    always @(posedge clk_i)
        begin
            mirroring_reg_r       <= mirroring_reg_next_w;
            prg_ram_protect_reg_r <= prg_ram_protect_reg_next_w;
            bank_select_reg_r     <= bank_select_reg_next_w;
        end

    generate
        for (genvar i = 0; i < 8; i = i + 1) begin: bank_data_registers

            always @(posedge clk_i)
                addr_data_reg_r[i] <= addr_data_reg_next_w[i];

            assign addr_data_reg_wr_w  [i] = bank_data_reg_wr_w && (i == bank_select_reg_r[2:0]);
            assign addr_data_reg_next_w[i] = (addr_data_reg_wr_w[i]) ? mapper_wr_data_i : addr_data_reg_r[i];

        end
    endgenerate

    assign bank_select_reg_en_w       = ~mapper_addr_i[14] && ~mapper_addr_i[13] && ~mapper_addr_i[0];
    assign bank_data_reg_en_w         = ~mapper_addr_i[14] && ~mapper_addr_i[13] &&  mapper_addr_i[0];
    assign mirroring_reg_en_w         = ~mapper_addr_i[14] &&  mapper_addr_i[13] && ~mapper_addr_i[0];
    assign prg_ram_protect_reg_en_w   = ~mapper_addr_i[14] &&  mapper_addr_i[13] &&  mapper_addr_i[0];

    assign bank_select_reg_wr_w       = mapper_wr_i && bank_select_reg_en_w;
    assign bank_data_reg_wr_w         = mapper_wr_i && bank_data_reg_en_w;
    assign mirroring_reg_wr_w         = mapper_wr_i && mirroring_reg_en_w;
    assign prg_ram_protect_reg_wr_w   = mapper_wr_i && prg_ram_protect_reg_en_w;

    assign bank_select_reg_next_w     = (bank_select_reg_wr_w    ) ? {mapper_wr_data_i[7:6],
                                                                      mapper_wr_data_i[2:0]} : bank_select_reg_r;
    assign mirroring_reg_next_w       = (mirroring_reg_wr_w      ) ?  mapper_wr_data_i[0]    : mirroring_reg_r;
    assign prg_ram_protect_reg_next_w = (prg_ram_protect_reg_wr_w) ?  mapper_wr_data_i[7:6]  : prg_ram_protect_reg_r;

    assign prg_rom_bank_mode_w        = bank_select_reg_r[3];
    assign chr_mem_a12_invert_w       = bank_select_reg_r[4];
    assign chr_mem_a12_w              = (chr_mem_a12_invert_w) ? ~chr_mem_addr_i[12] : chr_mem_addr_i[12];

    assign mmc3_prg_ram_en_w          =  prg_ram_protect_reg_r[1];
    assign mmc3_prg_ram_wr_en_w       = ~prg_ram_protect_reg_r[0]; // "1" - allow writes, "0" - deny writes

    assign mmc3_prg_ram_addr_w        = {2'h0, prg_ram_addr_i};

    wire [1:0] mmc3_nametable_layout_case_w = {alt_nametable_layout_i, mirroring_reg_r};
    always @(*)
        casez (mmc3_nametable_layout_case_w)
            2'b1_?: mmc3_nametable_layout_r = NAMETABLE_LAYOUT_FOUR_SCREEN;
            2'b0_0: mmc3_nametable_layout_r = NAMETABLE_LAYOUT_VERTICAL_MIRRORING;
            2'b0_1: mmc3_nametable_layout_r = NAMETABLE_LAYOUT_HORIZONTAL_MIRRORING;
        endcase

    wire [2:0] mmc3_chr_mem_addr_case_w = {chr_mem_a12_w, chr_mem_addr_i[11:10]};
    always @(*)
        casez (mmc3_chr_mem_addr_case_w)
            3'b00_?: mmc3_chr_mem_addr_r = {addr_data_reg_r[0][7:1], chr_mem_addr_i[10:0]}; // 0000 - 07FF
            3'b01_?: mmc3_chr_mem_addr_r = {addr_data_reg_r[1][7:1], chr_mem_addr_i[10:0]}; // 0800 - 0FFF
            3'b10_0: mmc3_chr_mem_addr_r = {addr_data_reg_r[2][7:0], chr_mem_addr_i[ 9:0]}; // 1000 - 13FF
            3'b10_1: mmc3_chr_mem_addr_r = {addr_data_reg_r[3][7:0], chr_mem_addr_i[ 9:0]}; // 1400 - 17FF
            3'b11_0: mmc3_chr_mem_addr_r = {addr_data_reg_r[4][7:0], chr_mem_addr_i[ 9:0]}; // 1800 - 1BFF
            3'b11_1: mmc3_chr_mem_addr_r = {addr_data_reg_r[5][7:0], chr_mem_addr_i[ 9:0]}; // 1C00 - 1FFF
        endcase

    wire [2:0] mmc3_prg_rom_addr_case_w = {prg_rom_addr_i[14:13], prg_rom_bank_mode_w};
    always @(*)
        casez (mmc3_prg_rom_addr_case_w)
            3'b00_0: mmc3_prg_rom_addr_r = {addr_data_reg_r[6][5:0], prg_rom_addr_i[12:0]}; // 0000 - 1FFF
            3'b00_1: mmc3_prg_rom_addr_r = {6'h3E,                   prg_rom_addr_i[12:0]}; // 0000 - 1FFF
            3'b01_?: mmc3_prg_rom_addr_r = {addr_data_reg_r[7][5:0], prg_rom_addr_i[12:0]}; // 2000 - 3FFF
            3'b10_0: mmc3_prg_rom_addr_r = {6'h3E,                   prg_rom_addr_i[12:0]}; // 4000 - 5FFF
            3'b10_1: mmc3_prg_rom_addr_r = {addr_data_reg_r[6][5:0], prg_rom_addr_i[12:0]}; // 4000 - 5FFF
            3'b11_?: mmc3_prg_rom_addr_r = {6'h3F,                   prg_rom_addr_i[12:0]}; // 6000 - 7FFF
        endcase


    // Логка прервания от маппера
    always @(posedge clk_i)
        if (rst_i) begin
            irq_enabled_r    <= 1'b0;
            irq_counter_r    <= 8'h0;
            irq_a12_r        <= 1'b0;
            irq_a12_prev_r   <= 3'h0;
            mmc3_irq_r       <= 1'b0;
        end else begin
            irq_enabled_r    <= irq_enabled_next_r;
            irq_counter_r    <= irq_counter_next_r;
            irq_a12_r        <= chr_mem_a12_w;
            irq_a12_prev_r   <= irq_a12_prev_next_w;
            mmc3_irq_r       <= mmc3_irq_next_r;
        end

    always @(posedge clk_i)
        begin
            irq_latch_reg_r  <= irq_latch_reg_next_w;
            irq_reload_req_r <= irq_reload_req_next_r;
        end

    assign irq_a12_prev_next_w   = {irq_a12_prev_r[1:0], irq_a12_r};
    assign irq_a12_posedge_w     = irq_a12_r && ~|irq_a12_prev_r;

    assign irq_zero_flag_w       = ~|irq_counter_r;
    assign irq_zero_transition_w = ~|irq_counter_next_r;

    assign irq_reload_cond_w     = irq_zero_flag_w || irq_reload_req_r;

    assign mmc3_irq_trigger_w    = irq_a12_posedge_w && irq_enabled_r && irq_zero_transition_w;

    assign irq_latch_reg_en_w    = mapper_addr_i[14] && ~mapper_addr_i[13] && ~mapper_addr_i[0];
    assign irq_reload_reg_en_w   = mapper_addr_i[14] && ~mapper_addr_i[13] &&  mapper_addr_i[0];
    assign irq_disable_reg_en_w  = mapper_addr_i[14] &&  mapper_addr_i[13] && ~mapper_addr_i[0];
    assign irq_enable_reg_en_w   = mapper_addr_i[14] &&  mapper_addr_i[13] &&  mapper_addr_i[0];

    assign irq_latch_reg_wr_w    = mapper_wr_i && irq_latch_reg_en_w;
    assign irq_reload_reg_wr_w   = mapper_wr_i && irq_reload_reg_en_w;
    assign irq_disable_reg_wr_w  = mapper_wr_i && irq_disable_reg_en_w;
    assign irq_enable_reg_wr_w   = mapper_wr_i && irq_enable_reg_en_w;

    assign irq_latch_reg_next_w  = (irq_latch_reg_wr_w) ? mapper_wr_data_i[7:0] : irq_latch_reg_r;

    assign mmc3_irq0_next_w      = mmc3_irq_r && ~irq_disable_reg_wr_w;

    wire [1:0] irq_enabled_next_case_w = {irq_enable_reg_wr_w, irq_disable_reg_wr_w};
    always @(*)
        case (irq_enabled_next_case_w) // one hot
            2'b10:   irq_enabled_next_r    = 1'b1;
            2'b01:   irq_enabled_next_r    = 1'b0;
            default: irq_enabled_next_r    = irq_enabled_r;
        endcase

    wire [1:0] irq_reload_req_next_case_w = {irq_reload_reg_wr_w, irq_a12_posedge_w};
    always @(*)
        casez (irq_reload_req_next_case_w)
            2'b1_?:  irq_reload_req_next_r = 1'b1;
            2'b0_1:  irq_reload_req_next_r = 1'b0;
            default: irq_reload_req_next_r = irq_reload_req_r;
        endcase

    wire [1:0] irq_counter_next_case_w = {irq_reload_cond_w, irq_a12_posedge_w};
    always @(*)
        case (irq_counter_next_case_w)
            2'b11:   irq_counter_next_r    = irq_latch_reg_r;
            2'b01:   irq_counter_next_r    = irq_counter_r - 1'b1;
            default: irq_counter_next_r    = irq_counter_r;
        endcase

    wire [1:0] mmc3_irq_next_case_w = {irq_disable_reg_wr_w, mmc3_irq_trigger_w};
    always @(*)
        casez (mmc3_irq_next_case_w)
            2'b1_?:  mmc3_irq_next_r       = 1'b0;
            2'b0_1:  mmc3_irq_next_r       = 1'b1;
            default: mmc3_irq_next_r       = mmc3_irq_r;
        endcase


    assign mmc3_prg_rom_addr_o     = mmc3_prg_rom_addr_r;
    assign mmc3_prg_ram_addr_o     = mmc3_prg_ram_addr_w;
    assign mmc3_chr_mem_addr_o     = mmc3_chr_mem_addr_r;
    assign mmc3_nametable_layout_o = mmc3_nametable_layout_r;
    assign mmc3_prg_ram_en_o       = mmc3_prg_ram_en_w;
    assign mmc3_prg_ram_wr_en_o    = mmc3_prg_ram_wr_en_w;
    assign mmc3_irq_o              = mmc3_irq_next_r;


endmodule
