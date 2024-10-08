
/*
 * Description : MMC1 (№1) mapper module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module mapper_mmc1
    (
        input  wire        clk_i,                   // Сигнал тактирования
        input  wire        rst_i,                   // Сигнал сброса

        input  wire        mapper_wr_i,             // Сигнал записи в регистры маппера
        input  wire [14:0] mapper_addr_i,           // Адрес обращения к регистрам маппера
        input  wire [ 7:0] mapper_wr_data_i,        // Записываемые данные в регистры маппера

        input  wire [14:0] prg_rom_addr_i,          // Адрес обращения к постоянной памяти программы картриджа
        input  wire [12:0] prg_ram_addr_i,          // Адрес обращения к оперативной памяти картриджа
        input  wire [12:0] chr_mem_addr_i,          // Адрес обращения к видеопамяти картриджа

        input  wire        prg_rom_is_512k_i,       // Постояная память картриджа равна 512 Кбайтам
        input  wire        chr_mem_is_ram_i,        // Видеопамять картриджа реализована на ОЗУ

        output wire [18:0] mmc1_prg_rom_addr_o,     // Расширенный адрес обращения к постоянной памяти программы картриджа
        output wire [14:0] mmc1_prg_ram_addr_o,     // Расширенный адрес обращения к оперативной памяти картриджа
        output wire [17:0] mmc1_chr_mem_addr_o,     // Расширенный адрес обращения к видеопамяти картриджа
        output wire [ 2:0] mmc1_nametable_layout_o, // Используемая организация оперативной видеопамяти
        output wire        mmc1_prg_ram_en_o        // Сигнал разрешения работы оперативной памяти на картридже
    );


    `include "localparam_nametable_layout.vh"


    // Сигналы регистров
    reg  [ 4:0] shifter_r;
    reg  [ 4:0] shifter_next_r;
    reg  [ 2:0] counter_r;
    reg  [ 2:0] counter_next_r;
    wire [ 4:0] shifted_cpu_data_w;
    reg  [ 4:0] cntrl_reg_r;
    reg  [ 4:0] cntrl_reg_next_r;
    reg  [ 4:0] chrb0_reg_r;
    wire [ 4:0] chrb0_reg_next_w;
    reg  [ 4:0] chrb1_reg_r;
    wire [ 4:0] chrb1_reg_next_w;
    reg  [ 4:0] prgb_reg_r;
    wire [ 4:0] prgb_reg_next_w;

    wire        regs_wr_cond_w;
    wire        rst_mapper_cond_w;
    wire        rst_count_shift_cond_w;
    wire        cntrl_reg_en_w;
    wire        chrb0_reg_en_w;
    wire        chrb1_reg_en_w;
    wire        prgb_reg_en_w;
    wire        cntrl_reg_wr_cond_w;
    wire        chrb0_reg_wr_cond_w;
    wire        chrb1_reg_wr_cond_w;
    wire        prgb_reg_wr_cond_w;
    wire        chrb0_reg_wr_w;
    wire        chrb1_reg_wr_w;
    wire        prgb_reg_wr_w;

    // Сигналы маппинга
    reg  [18:0] mmc1_prg_rom_addr_r;
    reg  [14:0] mmc1_prg_ram_addr_r;
    reg  [17:0] mmc1_chr_mem_addr_r;
    wire [ 2:0] mmc1_nametable_layout_w;
    wire        mmc1_prg_ram_en_w;

    wire [ 1:0] prg_rom_bank_mode_w;
    wire        chr_mem_bank_mode_w;

    wire        sux_prg_rom_a18_w;
    wire        so_prg_ram_a13_w;
    wire        sx_prg_ram_a13_w;
    wire        sx_prg_ram_a14_w;


    // Логика записи данных от процессора в регистры маппера
    always @(posedge clk_i)
        if (rst_i) begin
            cntrl_reg_r <= 5'h0C;
            chrb0_reg_r <= 5'h0;
            chrb1_reg_r <= 5'h0;
            prgb_reg_r  <= 5'h0;
        end else begin
            cntrl_reg_r <= cntrl_reg_next_r;
            chrb0_reg_r <= chrb0_reg_next_w;
            chrb1_reg_r <= chrb1_reg_next_w;
            prgb_reg_r  <= prgb_reg_next_w;
        end

    always @(posedge clk_i)
        begin
            counter_r   <= counter_next_r;
            shifter_r   <= shifter_next_r;
        end

    assign regs_wr_cond_w         = (counter_r == 3'h4);
    assign rst_mapper_cond_w      = mapper_wr_data_i[7];
    assign rst_count_shift_cond_w = rst_mapper_cond_w || regs_wr_cond_w;

    assign cntrl_reg_en_w         = ~mapper_addr_i[14] && ~mapper_addr_i[13];
    assign chrb0_reg_en_w         = ~mapper_addr_i[14] &&  mapper_addr_i[13];
    assign chrb1_reg_en_w         =  mapper_addr_i[14] && ~mapper_addr_i[13];
    assign prgb_reg_en_w          =  mapper_addr_i[14] &&  mapper_addr_i[13];

    assign cntrl_reg_wr_cond_w    = regs_wr_cond_w && cntrl_reg_en_w;
    assign chrb0_reg_wr_cond_w    = regs_wr_cond_w && chrb0_reg_en_w;
    assign chrb1_reg_wr_cond_w    = regs_wr_cond_w && chrb1_reg_en_w;
    assign prgb_reg_wr_cond_w     = regs_wr_cond_w && prgb_reg_en_w;

    assign chrb0_reg_wr_w         = mapper_wr_i && chrb0_reg_wr_cond_w;
    assign chrb1_reg_wr_w         = mapper_wr_i && chrb1_reg_wr_cond_w;
    assign prgb_reg_wr_w          = mapper_wr_i && prgb_reg_wr_cond_w;

    assign shifted_cpu_data_w     = {mapper_wr_data_i[0], shifter_r[4:1]};

    assign chrb0_reg_next_w       = (chrb0_reg_wr_w) ? shifted_cpu_data_w : chrb0_reg_r;
    assign chrb1_reg_next_w       = (chrb1_reg_wr_w) ? shifted_cpu_data_w : chrb1_reg_r;
    assign prgb_reg_next_w        = (prgb_reg_wr_w ) ? shifted_cpu_data_w : prgb_reg_r;

    wire [1:0] counter_next_case_w = {mapper_wr_i, rst_count_shift_cond_w};
    always @(*)
        case (counter_next_case_w)
            2'b11:   counter_next_r   = 3'b0;
            2'b10:   counter_next_r   = counter_r + 1'b1;
            default: counter_next_r   = counter_r;
        endcase

    wire [1:0] shifter_next_case_w = {mapper_wr_i, rst_count_shift_cond_w};
    always @(*)
        case (shifter_next_case_w  )
            2'b11:   shifter_next_r   = 5'b0;
            2'b10:   shifter_next_r   = shifted_cpu_data_w;
            default: shifter_next_r   = shifter_r;
        endcase

    wire [2:0] cntrl_reg_next_case_w = {mapper_wr_i, rst_mapper_cond_w, cntrl_reg_wr_cond_w};
    always @(*)
        casez (cntrl_reg_next_case_w)
            3'b11_?: cntrl_reg_next_r = cntrl_reg_r | 5'h0C;
            3'b10_1: cntrl_reg_next_r = shifted_cpu_data_w;
            default: cntrl_reg_next_r = cntrl_reg_r;
        endcase


    // Логика маппинга
    assign mmc1_nametable_layout_w =  {1'b0, cntrl_reg_r[1:0]};
    assign mmc1_prg_ram_en_w       = ~prgb_reg_r [4];

    assign prg_rom_bank_mode_w     =  cntrl_reg_r[3:2];
    assign chr_mem_bank_mode_w     =  cntrl_reg_r[4];

    assign sux_prg_rom_a18_w       =  chrb0_reg_r[4] || chrb1_reg_r[4];
    assign so_prg_ram_a13_w        =  chrb0_reg_r[3] || chrb1_reg_r[3];
    assign sx_prg_ram_a13_w        =  chrb0_reg_r[2] || chrb1_reg_r[2];
    assign sx_prg_ram_a14_w        =  chrb0_reg_r[3] || chrb1_reg_r[3];

    wire [2:0] mmc1_prg_rom_addr_case_w = {prg_rom_bank_mode_w, prg_rom_addr_i[14]};
    always @(*)
        casez (mmc1_prg_rom_addr_case_w)
            3'b0_?_?: mmc1_prg_rom_addr_r = {sux_prg_rom_a18_w, prgb_reg_r[3:1], prg_rom_addr_i[14:0]};
            3'b1_0_1: mmc1_prg_rom_addr_r = {sux_prg_rom_a18_w, prgb_reg_r[3:0], prg_rom_addr_i[13:0]};
            3'b1_0_0: mmc1_prg_rom_addr_r = {sux_prg_rom_a18_w, 4'h0,            prg_rom_addr_i[13:0]};
            3'b1_1_1: mmc1_prg_rom_addr_r = {sux_prg_rom_a18_w, 4'hF,            prg_rom_addr_i[13:0]};
            3'b1_1_0: mmc1_prg_rom_addr_r = {sux_prg_rom_a18_w, prgb_reg_r[3:0], prg_rom_addr_i[13:0]};
        endcase

    wire [1:0] mmc1_chr_mem_addr_case_w = {chr_mem_bank_mode_w, chr_mem_addr_i[12]};
    always @(*)
        casez (mmc1_chr_mem_addr_case_w)
            2'b0_?:   mmc1_chr_mem_addr_r = {1'h0, chrb0_reg_r[4:1], chr_mem_addr_i[12:0]};
            2'b1_1:   mmc1_chr_mem_addr_r = {1'h0, chrb1_reg_r[4:0], chr_mem_addr_i[11:0]};
            2'b1_0:   mmc1_chr_mem_addr_r = {1'h0, chrb0_reg_r[4:0], chr_mem_addr_i[11:0]};
        endcase

    wire [1:0] mmc1_prg_ram_addr_case_w = {chr_mem_is_ram_i, prg_rom_is_512k_i};
    always @(*)
        casez (mmc1_prg_ram_addr_case_w)
            2'b0_?:   mmc1_prg_ram_addr_r = {1'b0,             1'b0,             prg_ram_addr_i};
            2'b1_0:   mmc1_prg_ram_addr_r = {1'b0,             so_prg_ram_a13_w, prg_ram_addr_i};
            2'b1_1:   mmc1_prg_ram_addr_r = {sx_prg_ram_a14_w, sx_prg_ram_a13_w, prg_ram_addr_i};
        endcase


    assign mmc1_prg_rom_addr_o     = mmc1_prg_rom_addr_r;
    assign mmc1_prg_ram_addr_o     = mmc1_prg_ram_addr_r;
    assign mmc1_chr_mem_addr_o     = mmc1_chr_mem_addr_r;
    assign mmc1_nametable_layout_o = mmc1_nametable_layout_w;
    assign mmc1_prg_ram_en_o       = mmc1_prg_ram_en_w;


endmodule
