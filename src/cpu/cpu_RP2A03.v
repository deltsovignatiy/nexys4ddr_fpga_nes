
/*
 * Description : RP2A03 implementation (CPU core, CPU RAM, APU core, DMA and CPU bus control) module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


`include "defines.vh"


module cpu_RP2A03
    (
        input  wire        clk_i,             // Сигнал тактирования
        input  wire        mclk_i,            // Сигнал тактирования (negedge)
        input  wire        rst_i,             // Сигнал сброса

        input  wire        ppu_nmi_i,         // Прерывание от графического процессора
        input  wire        mapper_irq_i,      // Прерывание от мапперов

        output wire        prg_rom_mclk_o,    // Сигнал тактирования для постоянной памяти картриджа
        output wire        prg_rom_rst_o,     // Сигнас сброса постоянной памяти картриджа (для логики кросс-клока)
        output wire        prg_rom_rd_o,      // Сигнал чтения данных постоянной памяти картриджа
        output wire [14:0] prg_rom_addr_o,    // Адрес обращения к постоянной памяти картриджа
        input  wire [ 7:0] prg_rom_rd_data_i, // Читаемые данные постоянной памяти картриджа

        output wire        prg_ram_mclk_o,    // Сигнал тактирования для оперативной памяти картриджа
        output wire        prg_ram_wr_o,      // Сигнал записи данных оперативной памяти картриджа
        output wire        prg_ram_rd_o,      // Сигнал чтения данных оперативной памяти картриджа
        output wire [12:0] prg_ram_addr_o,    // Адрес обращения к оперативной памяти картриджа
        output wire [ 7:0] prg_ram_wr_data_o, // Записываемые данные оперативной памяти картриджа
        input  wire [ 7:0] prg_ram_rd_data_i, // Читаемые данные оперативной памяти картриджа

        output wire        ppu_wr_o,          // Сигнал записи данных в регистры графического процессора
        output wire        ppu_rd_o,          // Сигнал чтения данных из регистров графического процессора
        output wire [ 2:0] ppu_addr_o,        // Адрес обращения к регистрам графического процессора
        output wire [ 7:0] ppu_wr_data_o,     // Записываемые данные графического процессора
        input  wire [ 7:0] ppu_rd_data_i,     // Читаемые данные графического процессора

        output wire        mapper_clk_o,      // Сигнал тактирования мапперов
        output wire        mapper_rst_o,      // Сигнал сброса мапперов
        output wire        mapper_wr_o,       // Сигнал записи в регистры мапперов
        output wire [14:0] mapper_addr_o,     // Адрес обращения к регистрам мапперов
        output wire [ 7:0] mapper_wr_data_o,  // Записываемые данные мапперов

        input  wire [ 7:0] device_1_input_i,  // Данные 1-го устройства ввода
        input  wire [ 7:0] device_2_input_i,  // Данные 2-го устройства ввода

        output wire [15:0] apu_output_o,      // Выход аудиопроцессора в формате PCM

        output wire        new_instruction_o, // Дебаг, сигнал выборки новой операции ядра
        output wire        state_invalid_o    // Дебаг, сигнал невалидности текущего состояния конечного автомата ядра
    );


    // Используемые адреса на шине
    localparam [15:0] OAM_DATA_ADDR        = 16'h2004,
                      OAM_DMA_INIT_ADDR    = 16'h4014,
                      APU_STATUS_ADDR      = 16'h4015,
                      CONTROLLER_1_ADDR    = 16'h4016,
                      CONTROLLER_2_ADDR    = 16'h4017;

    // Размер оперативной памяти процессора
    localparam        CPU_RAM_SIZE         = 2 * 1024;


    // Сигналы процессорной шины
    wire        cpu_rd_w;
    wire        cpu_wr_w;
    wire [15:0] cpu_addr_w;
    wire [ 7:0] cpu_wr_data_w;
    wire [ 7:0] cpu_rd_data_w;

    // Сигналы системной шины
    wire        bus_rd_w;
    wire        bus_wr_w;
    wire [15:0] bus_addr_w;
    wire [ 7:0] bus_wr_data_w;
    reg  [ 7:0] bus_rd_data_r;

    // Сигналы доступа к постоянной памяти на картридже
    wire        prg_rom_mclk_w;
    wire        prg_rom_rst_w;
    wire        prg_rom_mapper_en_w;
    wire        prg_rom_rd_w;
    wire [14:0] prg_rom_addr_w;

    // Сигналы доступак оперативной памяти а картридже
    wire        prg_ram_mclk_w;
    wire        prg_ram_en_w;
    wire        prg_ram_wr_w;
    wire        prg_ram_rd_w;
    wire [12:0] prg_ram_addr_w;
    wire [ 7:0] prg_ram_wr_data_w;

    // Сигалы доступа к оперативной памяти процессора
    wire        cpu_ram_mclk_w;
    wire        cpu_ram_en_w;
    wire        cpu_ram_wr_w;
    wire        cpu_ram_rd_w;
    wire [10:0] cpu_ram_addr_w;
    wire [ 7:0] cpu_ram_wr_data_w;
    wire [ 7:0] cpu_ram_rd_data_w;

    // Сигналы доступа к грфическому процессору
    wire        ppu_en_w;
    wire        ppu_wr_w;
    wire        ppu_rd_w;
    wire [ 2:0] ppu_addr_w;
    wire [ 7:0] ppu_wr_data_w;

    // Сигналы доступа к мапперам
    wire        mapper_clk_w;
    wire        mapper_rst_w;
    wire        mapper_wr_w;
    wire [14:0] mapper_addr_w;
    wire [ 7:0] mapper_wr_data_w;

    // Сигналы управления систеной шиной
    reg         cpu_ram_data_sel_r;
    reg         prg_ram_data_sel_r;
    reg         ppu_data_sel_r;
    reg         device_1_data_sel_r;
    reg         device_2_data_sel_r;
    reg         apu_data_sel_r;
    wire        apu_dma_cntrl_en_w;

    // Сигналы логики приёма данных с "геймпадов"
    wire [ 7:0] device_1_rd_data_w;
    wire [ 7:0] device_2_rd_data_w;
    wire        device_1_wr_w;
    wire        device_1_wr_data_w;
    wire        device_1_rd_w;
    wire        device_2_rd_w;
    wire        device_rd_w           [1:0];
    reg  [ 7:0] device_shifter_r      [1:0];
    reg  [ 7:0] device_shifter_next_r [1:0];
    wire [ 7:0] device_input_w        [1:0];
    wire [ 7:0] device_rd_data_w      [1:0];
    wire [ 7:0] device_shifted_w      [1:0];

    // Сигналы аудиопроцессора
    wire        apu_wr_w;
    wire        apu_rd_w;
    wire [ 4:0] apu_addr_w;
    wire [ 7:0] apu_wr_data_w;
    wire [ 7:0] apu_rd_data_w;
    wire        apu_frame_irq_w;
    wire        apu_dmc_channel_irq_w;

    // Сигналы контролра прямого доступа к памяти
    reg         apu_dma_cycle_r;
    reg         halt_r;
    reg         halt_next_r;
    wire        cpu_halt_set_w;
    wire        cpu_halt_reset_w;
    wire        dma_read_cycle_w;
    wire        dma_write_cycle_w;
    wire [15:0] dma_addr_w;
    wire        dma_wr_w;
    wire        dma_rd_w;
    wire [ 7:0] dma_wr_data_w;

    // Сигналы DMA для работы со спрайтами графического процессора
    wire        oam_dma_reg_wr_w;
    wire [ 7:0] oam_dma_reg_wr_data_w;
    reg  [ 7:0] oam_dma_reg_r;
    wire [ 7:0] oam_dma_reg_next_w;
    reg  [ 8:0] oam_dma_conter_r;
    wire [ 8:0] oam_dma_counter_next_w;
    reg         oam_dma_exe_r;
    reg         oam_dma_exe_next_r;
    reg  [ 7:0] oam_dma_wr_data_r;
    wire [ 7:0] oam_dma_wr_data_next_w;
    reg         oam_dma_alig_r;
    reg         oam_dma_alig_next_r;
    wire [15:0] oam_dma_rd_addr_w;
    wire [15:0] oam_dma_wr_addr_w;
    wire [15:0] oam_dma_addr_w;
    wire        oam_dma_op_w;
    wire        oam_dma_rd_w;
    wire        oam_dma_wr_w;
    wire        oam_dma_complete_w;
    wire [ 8:0] oam_dma_counter_incr_w;
    wire        oam_dma_alig_reset_w;

    // Сигналы DMA для работы с данными DMC канала аудиопроцессора
    reg         dmc_dma_dummy_r;
    wire        dmc_dma_dummy_next_w;
    wire [ 7:0] dmc_dma_rd_data_w;
    wire [15:0] dmc_dma_addr_w;
    wire        dmc_dma_rd_w;
    wire        dmc_dma_exe_w;
    wire        dmc_dma_op_w;
    wire        dmc_dma_complete_w;


    // Управление и арбитраж системной шины
    assign cpu_rd_w              = ~cpu_wr_w;
    assign cpu_rd_data_w         = bus_rd_data_r;

    assign bus_addr_w            = (halt_r) ? dma_addr_w    : cpu_addr_w;
    assign bus_wr_w              = (halt_r) ? dma_wr_w      : cpu_wr_w;
    assign bus_rd_w              = (halt_r) ? dma_rd_w      : cpu_rd_w;
    assign bus_wr_data_w         = (halt_r) ? dma_wr_data_w : cpu_wr_data_w;

    assign prg_rom_mapper_en_w   =   bus_addr_w[   15];
    assign apu_dma_cntrl_en_w    =  ~bus_addr_w[   15] &&  bus_addr_w[   14] && ~|bus_addr_w[13:5];
    assign prg_ram_en_w          =  ~bus_addr_w[   15] && &bus_addr_w[14:13];
    assign ppu_en_w              = ~|bus_addr_w[15:14] &&  bus_addr_w[   13];
    assign cpu_ram_en_w          = ~|bus_addr_w[15:13];

    assign prg_ram_wr_w          = bus_wr_w && prg_ram_en_w;
    assign cpu_ram_wr_w          = bus_wr_w && cpu_ram_en_w;
    assign ppu_wr_w              = bus_wr_w && ppu_en_w;
    assign mapper_wr_w           = bus_wr_w && prg_rom_mapper_en_w;
    assign oam_dma_reg_wr_w      = bus_wr_w && apu_dma_cntrl_en_w && (bus_addr_w[4:0] == OAM_DMA_INIT_ADDR[4:0]);
    assign device_1_wr_w         = bus_wr_w && apu_dma_cntrl_en_w && (bus_addr_w[4:0] == CONTROLLER_1_ADDR[4:0]);
    assign apu_wr_w              = bus_wr_w && apu_dma_cntrl_en_w && (bus_addr_w[4:0] != OAM_DMA_INIT_ADDR[4:0]) &&
                                                                     (bus_addr_w[4:0] != CONTROLLER_1_ADDR[4:0]);

    assign prg_rom_rd_w          = bus_rd_w && prg_rom_mapper_en_w;
    assign prg_ram_rd_w          = bus_rd_w && prg_ram_en_w;
    assign cpu_ram_rd_w          = bus_rd_w && cpu_ram_en_w;
    assign ppu_rd_w              = bus_rd_w && ppu_en_w;
    assign device_1_rd_w         = bus_rd_w && apu_dma_cntrl_en_w && (bus_addr_w[4:0] == CONTROLLER_1_ADDR[4:0]);
    assign device_2_rd_w         = bus_rd_w && apu_dma_cntrl_en_w && (bus_addr_w[4:0] == CONTROLLER_2_ADDR[4:0]);
    assign apu_rd_w              = bus_rd_w && apu_dma_cntrl_en_w && (bus_addr_w[4:0] == APU_STATUS_ADDR  [4:0]);

    assign prg_rom_mclk_w        = mclk_i;
    assign prg_ram_mclk_w        = mclk_i;
    assign cpu_ram_mclk_w        = mclk_i;
    assign mapper_clk_w          = mclk_i;

    assign prg_rom_rst_w         = rst_i;
    assign mapper_rst_w          = rst_i;

    assign prg_rom_addr_w        = bus_addr_w[14:0];
    assign prg_ram_addr_w        = bus_addr_w[12:0];
    assign cpu_ram_addr_w        = bus_addr_w[10:0];
    assign ppu_addr_w            = bus_addr_w[ 2:0];
    assign mapper_addr_w         = bus_addr_w[14:0];
    assign apu_addr_w            = bus_addr_w[ 4:0];

    assign prg_ram_wr_data_w     = bus_wr_data_w;
    assign cpu_ram_wr_data_w     = bus_wr_data_w;
    assign ppu_wr_data_w         = bus_wr_data_w;
    assign mapper_wr_data_w      = bus_wr_data_w;
    assign oam_dma_reg_wr_data_w = bus_wr_data_w;
    assign device_1_wr_data_w    = bus_wr_data_w[0];
    assign apu_wr_data_w         = bus_wr_data_w;

    always @(posedge mclk_i)
        if (rst_i) begin
            cpu_ram_data_sel_r  <= 1'b0;
            prg_ram_data_sel_r  <= 1'b0;
            ppu_data_sel_r      <= 1'b0;
            device_1_data_sel_r <= 1'b0;
            device_2_data_sel_r <= 1'b0;
            apu_data_sel_r      <= 1'b0;
        end else begin
            cpu_ram_data_sel_r  <= cpu_ram_rd_w;
            prg_ram_data_sel_r  <= prg_ram_rd_w;
            ppu_data_sel_r      <= ppu_rd_w;
            device_1_data_sel_r <= device_1_rd_w;
            device_2_data_sel_r <= device_2_rd_w;
            apu_data_sel_r      <= apu_rd_w;
        end

    wire [5:0] bus_rd_data_case_w = {ppu_data_sel_r, device_1_data_sel_r, device_2_data_sel_r,
                                     apu_data_sel_r, prg_ram_data_sel_r, cpu_ram_data_sel_r};
    always @(*)
        case (bus_rd_data_case_w) // one hot
            6'b100000: bus_rd_data_r = ppu_rd_data_i;
            6'b010000: bus_rd_data_r = device_1_rd_data_w;
            6'b001000: bus_rd_data_r = device_2_rd_data_w;
            6'b000100: bus_rd_data_r = apu_rd_data_w;
            6'b000010: bus_rd_data_r = prg_ram_rd_data_i;
            6'b000001: bus_rd_data_r = cpu_ram_rd_data_w;
            default:   bus_rd_data_r = prg_rom_rd_data_i;
        endcase


    // Логика приёма данных с устройств ввода
    assign device_input_w[0]  = device_1_input_i;
    assign device_input_w[1]  = device_2_input_i;
    assign device_rd_w   [0]  = device_1_rd_w;
    assign device_rd_w   [1]  = device_2_rd_w;
    assign device_1_rd_data_w = device_rd_data_w[0];
    assign device_2_rd_data_w = device_rd_data_w[1];
    assign devices_strobe_w   = device_1_wr_w && device_1_wr_data_w;

    generate
        for (genvar d = 0; d < 2; d = d + 1) begin: devices

            always @(posedge clk_i)
                device_shifter_r[d] <= device_shifter_next_r[d];

            assign device_rd_data_w[d] = {7'b0100000, {device_shifter_r[d][0]}};
            assign device_shifted_w[d] = {1'b0, device_shifter_r[d][7:1]};

            wire [1:0] device_shifter_next_case_w = {devices_strobe_w, device_rd_w[d]};
            always @(*)
                case (device_shifter_next_case_w) // one hot
                    2'b10:   device_shifter_next_r[d] = device_input_w  [d];
                    2'b01:   device_shifter_next_r[d] = device_shifted_w[d];
                    default: device_shifter_next_r[d] = device_shifter_r[d];
                endcase

        end
    endgenerate


    // Ядро центрального процессора
    cpu_RP2A03_6502_core
        cpu_core
        (
            .clk_i                (clk_i                ),
            .mclk_i               (mclk_i               ),
            .rst_i                (rst_i                ),

            .halt_i               (halt_r               ),

            .ppu_nmi_i            (ppu_nmi_i            ),
            .apu_frame_irq_i      (apu_frame_irq_w      ),
            .apu_dmc_irq_i        (apu_dmc_channel_irq_w),
            .mapper_irq_i         (mapper_irq_i         ),

            .cpu_wr_o             (cpu_wr_w             ),
            .cpu_addr_o           (cpu_addr_w           ),
            .cpu_wr_data_o        (cpu_wr_data_w        ),
            .cpu_rd_data_i        (cpu_rd_data_w        ),

            .new_instruction_o    (new_instruction_o    ),
            .state_invalid_o      (state_invalid_o      )
        );


    // Оперативная память процессора
    single_port_no_change_ram
        #(
            .DATA_WIDTH           (8                    ),
            .RAM_DEPTH            (CPU_RAM_SIZE         ),
            .RAM_STYLE            ("block"              ),
            .INIT_VAL             (`MEM_INIT_VAL        ),
            .SIMULATION           (`MEM_SIM             )
        )
        cpu_ram
        (
            .clka_i               (cpu_ram_mclk_w       ),
            .addra_i              (cpu_ram_addr_w       ),
            .rda_i                (cpu_ram_rd_w         ),
            .wra_i                (cpu_ram_wr_w         ),
            .dina_i               (cpu_ram_wr_data_w    ),
            .douta_o              (cpu_ram_rd_data_w    )
        );


    // Аудиопроцессор
    cpu_RP2A03_apu
        apu
        (
            .clk_i                (clk_i                ),
            .rst_i                (rst_i                ),

            .apu_wr_i             (apu_wr_w             ),
            .apu_rd_i             (apu_rd_w             ),
            .apu_addr_i           (apu_addr_w           ),
            .apu_wr_data_i        (apu_wr_data_w        ),
            .apu_rd_data_o        (apu_rd_data_w        ),

            .apu_cycle_i          (apu_dma_cycle_r      ),
            .apu_output_o         (apu_output_o         ),
            .apu_frame_irq_o      (apu_frame_irq_w      ),
            .apu_dmc_channel_irq_o(apu_dmc_channel_irq_w),

            .dmc_dma_exe_o        (dmc_dma_exe_w        ),
            .dmc_dma_addr_o       (dmc_dma_addr_w       ),
            .dmc_dma_rd_i         (dmc_dma_rd_w         ),
            .dmc_dma_rd_data_i    (dmc_dma_rd_data_w    )
        );


    // Управление остановом ядра при работе DMA
    always @(posedge clk_i)
        if (rst_i) begin
            apu_dma_cycle_r <= 1'b1;
            halt_r          <= 1'b0;
        end else begin
            apu_dma_cycle_r <= ~apu_dma_cycle_r;
            halt_r          <= halt_next_r;
        end

    assign dma_read_cycle_w  = ~apu_dma_cycle_r;
    assign dma_write_cycle_w =  apu_dma_cycle_r;

    assign dma_addr_w        = (dmc_dma_rd_w) ? dmc_dma_addr_w : oam_dma_addr_w;
    assign dma_wr_w          = (dmc_dma_rd_w) ? 1'b0           : oam_dma_wr_w;
    assign dma_rd_w          = (dmc_dma_rd_w) ? 1'b1           : oam_dma_rd_w;
    assign dma_wr_data_w     = oam_dma_wr_data_r;

    assign dma_exe_w         = oam_dma_exe_r || dmc_dma_exe_w;

    assign cpu_halt_set_w    =  dma_exe_w && cpu_rd_w;
    assign cpu_halt_reset_w  = ~dma_exe_w;

    wire [1:0] cpu_halted_next_case_w = {cpu_halt_reset_w, cpu_halt_set_w};
    always @(*)
        case (cpu_halted_next_case_w)
            2'b10:   halt_next_r = 1'b0;
            2'b01:   halt_next_r = 1'b1;
            default: halt_next_r = halt_r;
        endcase


    // Логика DMA для работы со спрайтами графического процессора
    always @(posedge clk_i)
        if (rst_i) begin
            oam_dma_exe_r     <= 1'b0;
            oam_dma_alig_r    <= 1'b0;
        end else begin
            oam_dma_exe_r     <= oam_dma_exe_next_r;
            oam_dma_alig_r    <= oam_dma_alig_next_r;
        end

    always @(posedge clk_i)
        begin
            oam_dma_reg_r     <= oam_dma_reg_next_w;
            oam_dma_conter_r  <= oam_dma_counter_next_w;
            oam_dma_wr_data_r <= oam_dma_wr_data_next_w;
        end

    assign oam_dma_rd_addr_w      = {oam_dma_reg_r, oam_dma_conter_r[7:0]};
    assign oam_dma_wr_addr_w      = {OAM_DATA_ADDR};
    assign oam_dma_addr_w         = (dma_write_cycle_w) ? oam_dma_wr_addr_w : oam_dma_rd_addr_w;

    assign oam_dma_op_w           = oam_dma_exe_r && halt_r;

    assign oam_dma_rd_w           = oam_dma_op_w && dma_read_cycle_w && ~dmc_dma_rd_w;
    assign oam_dma_wr_w           = oam_dma_op_w && oam_dma_alig_r && dma_write_cycle_w;

    assign oam_dma_complete_w     = oam_dma_conter_r[8] && oam_dma_wr_w;
    assign oam_dma_counter_incr_w = oam_dma_conter_r     + oam_dma_rd_w;

    assign oam_dma_alig_reset_w   = oam_dma_complete_w || dmc_dma_rd_w;

    assign oam_dma_reg_next_w     = (oam_dma_reg_wr_w) ? oam_dma_reg_wr_data_w  : oam_dma_reg_r;
    assign oam_dma_counter_next_w = (oam_dma_op_w    ) ? oam_dma_counter_incr_w : 9'h0;
    assign oam_dma_wr_data_next_w = (oam_dma_rd_w    ) ? bus_rd_data_r          : oam_dma_wr_data_r;

    wire [1:0] oam_dma_exe_next_case_w = {oam_dma_complete_w, oam_dma_reg_wr_w};
    always @(*)
        case (oam_dma_exe_next_case_w)
            2'b10:   oam_dma_exe_next_r = 1'b0;
            2'b01:   oam_dma_exe_next_r = 1'b1;
            default: oam_dma_exe_next_r = oam_dma_exe_r;
        endcase

    wire [1:0] oam_dma_alig_next_case_w = {oam_dma_alig_reset_w, oam_dma_rd_w};
    always @(*)
        case (oam_dma_alig_next_case_w)
            2'b10:   oam_dma_alig_next_r = 1'b0;
            2'b01:   oam_dma_alig_next_r = 1'b1;
            default: oam_dma_alig_next_r = oam_dma_alig_r;
        endcase


    // Логика DMA для работы с DMC каналом аудиопроцессора
    always @(posedge clk_i)
        dmc_dma_dummy_r <= dmc_dma_dummy_next_w;

    assign dmc_dma_op_w         = dmc_dma_exe_w && halt_r;

    assign dmc_dma_rd_w         = dmc_dma_op_w && dmc_dma_dummy_r && dma_read_cycle_w;

    assign dmc_dma_rd_data_w    = bus_rd_data_r;

    assign dmc_dma_complete_w   = dmc_dma_rd_w;

    assign dmc_dma_dummy_next_w = dmc_dma_op_w;


    // Выходы
    assign prg_rom_mclk_o    = prg_rom_mclk_w;
    assign prg_rom_rst_o     = prg_rom_rst_w;
    assign prg_rom_rd_o      = prg_rom_rd_w;
    assign prg_rom_addr_o    = prg_rom_addr_w;

    assign prg_ram_mclk_o    = prg_ram_mclk_w;
    assign prg_ram_wr_o      = prg_ram_wr_w;
    assign prg_ram_rd_o      = prg_ram_rd_w;
    assign prg_ram_addr_o    = prg_ram_addr_w;
    assign prg_ram_wr_data_o = prg_ram_wr_data_w;

    assign ppu_wr_o          = ppu_wr_w;
    assign ppu_rd_o          = ppu_rd_w;
    assign ppu_addr_o        = ppu_addr_w;
    assign ppu_wr_data_o     = ppu_wr_data_w;

    assign mapper_clk_o      = mapper_clk_w;
    assign mapper_rst_o      = mapper_rst_w;
    assign mapper_wr_o       = mapper_wr_w;
    assign mapper_addr_o     = mapper_addr_w;
    assign mapper_wr_data_o  = mapper_wr_data_w;


endmodule
