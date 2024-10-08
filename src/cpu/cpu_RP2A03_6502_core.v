
/*
 * Description : RP2A03 central processor core (6502 ISA) implementation module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module cpu_RP2A03_6502_core
    (
        input  wire        clk_i,             // Сигнал тактирования
        input  wire        mclk_i,            // Сигнал тактирования (negedge)
        input  wire        rst_i,             // Сигнал сброса

        input  wire        halt_i,            // Останов ядра от логики ПДП

        input  wire        ppu_nmi_i,         // Прерывание от графического процессора
        input  wire        apu_frame_irq_i,   // Прерывание от счётчика фреймов аудиопроцессора
        input  wire        apu_dmc_irq_i,     // Прерывание от DMC канала аудиопроцессора
        input  wire        mapper_irq_i,      // Прерывание от мапперов

        output wire        cpu_wr_o,          // Сигал записи на процессорной шине, "1" — запись, "0" — чтение
        output wire [15:0] cpu_addr_o,        // Адрес обращения на процессорной шине
        output wire [ 7:0] cpu_wr_data_o,     // Записываемые данные на процессорной шине
        input  wire [ 7:0] cpu_rd_data_i,     // Читаемые данные на процессорной шине

        output wire        new_instruction_o, // Дебаг, сигнал выборки новой операции
        output wire        state_invalid_o    // Дебаг, сигнал невалидности текущего состояния конечного автомата
    );


    // 6502 ISA
    localparam [7:0] ADC_ABS = 8'h6D, ADC_ABSX = 8'h7D, ADC_ABSY = 8'h79, ADC_INDX = 8'h61, ADC_INDY = 8'h71,
                                      ADC_IMM  = 8'h69, ADC_ZP   = 8'h65, ADC_ZPX  = 8'h75,
                     AND_ABS = 8'h2D, AND_ABSX = 8'h3D, AND_ABSY = 8'h39, AND_INDX = 8'h21, AND_INDY = 8'h31,
                                      AND_IMM  = 8'h29, AND_ZP   = 8'h25, AND_ZPX  = 8'h35,
                     ASL_ABS = 8'h0E, ASL_ABSX = 8'h1E, ASL_ACC  = 8'h0A, ASL_ZP   = 8'h06, ASL_ZPX  = 8'h16,
                     BCC_REL = 8'h90,
                     BCS_REL = 8'hB0,
                     BEQ_REL = 8'hF0,
                     BIT_ABS = 8'h2C, BIT_ZP   = 8'h24,
                     BMI_REL = 8'h30,
                     BNE_REL = 8'hD0,
                     BPL_REL = 8'h10,
                     BRK_IMP = 8'h00,
                     BVC_REL = 8'h50,
                     BVS_REL = 8'h70,
                     CLC_IMP = 8'h18,
                     CLD_IMP = 8'hD8,
                     CLI_IMP = 8'h58,
                     CLV_IMP = 8'hB8,
                     CMP_ABS = 8'hCD, CMP_ABSX = 8'hDD, CMP_ABSY = 8'hD9, CMP_INDX = 8'hC1, CMP_INDY = 8'hD1,
                                      CMP_IMM  = 8'hC9, CMP_ZP   = 8'hC5, CMP_ZPX  = 8'hD5,
                     CPX_ABS = 8'hEC, CPX_IMM  = 8'hE0, CPX_ZP   = 8'hE4,
                     CPY_ABS = 8'hCC, CPY_IMM  = 8'hC0, CPY_ZP   = 8'hC4,
                     DEC_ABS = 8'hCE, DEC_ABSX = 8'hDE, DEC_ZP   = 8'hC6, DEC_ZPX  = 8'hD6,
                     DEX_IMP = 8'hCA,
                     DEY_IMP = 8'h88,
                     EOR_ABS = 8'h4D, EOR_ABSX = 8'h5D, EOR_ABSY = 8'h59, EOR_INDX = 8'h41, EOR_INDY = 8'h51,
                                      EOR_IMM  = 8'h49, EOR_ZP   = 8'h45, EOR_ZPX  = 8'h55,
                     HLT_IMP = 8'h02,
                     INC_ABS = 8'hEE, INC_ABSX = 8'hFE, INC_ZP   = 8'hE6, INC_ZPX  = 8'hF6,
                     INX_IMP = 8'hE8,
                     INY_IMP = 8'hC8,
                     JMP_ABS = 8'h4C, JMP_IND  = 8'h6C,
                     JSR_ABS = 8'h20,
                     LDA_ABS = 8'hAD, LDA_ABSX = 8'hBD, LDA_ABSY = 8'hB9, LDA_INDX = 8'hA1, LDA_INDY = 8'hB1,
                                      LDA_IMM  = 8'hA9, LDA_ZP   = 8'hA5, LDA_ZPX  = 8'hB5,
                     LDX_ABS = 8'hAE, LDX_ABSY = 8'hBE, LDX_IMM  = 8'hA2, LDX_ZP   = 8'hA6, LDX_ZPY  = 8'hB6,
                     LDY_ABS = 8'hAC, LDY_ABSX = 8'hBC, LDY_IMM  = 8'hA0, LDY_ZP   = 8'hA4, LDY_ZPX  = 8'hB4,
                     LSR_ABS = 8'h4E, LSR_ABSX = 8'h5E, LSR_ACC  = 8'h4A, LSR_ZP   = 8'h46, LSR_ZPX  = 8'h56,
                     NOP_IMP = 8'hEA,
                     ORA_ABS = 8'h0D, ORA_ABSX = 8'h1D, ORA_ABSY = 8'h19, ORA_INDX = 8'h01, ORA_INDY = 8'h11,
                                      ORA_IMM  = 8'h09, ORA_ZP   = 8'h05, ORA_ZPX  = 8'h15,
                     PHA_IMP = 8'h48,
                     PHP_IMP = 8'h08,
                     PLA_IMP = 8'h68,
                     PLP_IMP = 8'h28,
                     ROL_ABS = 8'h2E, ROL_ABSX = 8'h3E, ROL_ACC  = 8'h2A, ROL_ZP   = 8'h26, ROL_ZPX  = 8'h36,
                     ROR_ABS = 8'h6E, ROR_ABSX = 8'h7E, ROR_ACC  = 8'h6A, ROR_ZP   = 8'h66, ROR_ZPX  = 8'h76,
                     RTI_IMP = 8'h40,
                     RTS_IMP = 8'h60,
                     SBC_ABS = 8'hED, SBC_ABSX = 8'hFD, SBC_ABSY = 8'hF9, SBC_INDX = 8'hE1, SBC_INDY = 8'hF1,
                                      SBC_IMM  = 8'hE9, SBC_ZP   = 8'hE5, SBC_ZPX  = 8'hF5,
                     SEC_IMP = 8'h38,
                     SED_IMP = 8'hF8,
                     SEI_IMP = 8'h78,
                     STA_ABS = 8'h8D, STA_ABSX = 8'h9D, STA_ABSY = 8'h99, STA_INDX = 8'h81, STA_INDY = 8'h91,
                                      STA_ZP   = 8'h85, STA_ZPX  = 8'h95,
                     STX_ABS = 8'h8E, STX_ZP   = 8'h86, STX_ZPY  = 8'h96,
                     STY_ABS = 8'h8C, STY_ZP   = 8'h84, STY_ZPX  = 8'h94,
                     TAX_IMP = 8'hAA,
                     TAY_IMP = 8'hA8,
                     TSX_IMP = 8'hBA,
                     TXA_IMP = 8'h8A,
                     TXS_IMP = 8'h9A,
                     TYA_IMP = 8'h98;

    // Opcodes
    localparam [5:0] RST     = 6'd0, // CPU reset, not an opcode
                     ADC     = 6'd1,
                     AND     = 6'd2,
                     ASL     = 6'd3,
                     BCC     = 6'd4,
                     BCS     = 6'd5,
                     BEQ     = 6'd6,
                     BIT     = 6'd7,
                     BMI     = 6'd8,
                     BNE     = 6'd9,
                     BPL     = 6'd10,
                     BVC     = 6'd11,
                     BVS     = 6'd12,
                     CLC     = 6'd13,
                     CLD     = 6'd14,
                     CLI     = 6'd15,
                     CLV     = 6'd16,
                     CMP     = 6'd17,
                     CPX     = 6'd18,
                     CPY     = 6'd19,
                     DEC     = 6'd20,
                     DEX     = 6'd21,
                     DEY     = 6'd22,
                     EOR     = 6'd23,
                     HLT     = 6'd24,
                     INC     = 6'd25,
                     INX     = 6'd26,
                     INY     = 6'd27,
                     JMP     = 6'd28,
                     JSR     = 6'd29,
                     LDA     = 6'd30,
                     LDX     = 6'd31,
                     LDY     = 6'd32,
                     LSR     = 6'd33,
                     NOP     = 6'd34,
                     ORA     = 6'd35,
                     PHA     = 6'd36,
                     PHP     = 6'd37,
                     PLA     = 6'd38,
                     PLP     = 6'd39,
                     ROL     = 6'd40,
                     ROR     = 6'd41,
                     RTI     = 6'd42,
                     RTS     = 6'd43,
                     SBC     = 6'd44,
                     SEC     = 6'd45,
                     SED     = 6'd46,
                     SEI     = 6'd47,
                     STA     = 6'd48,
                     STX     = 6'd49,
                     STY     = 6'd50,
                     TAX     = 6'd51,
                     TAY     = 6'd52,
                     TSX     = 6'd53,
                     TXA     = 6'd54,
                     TXS     = 6'd55,
                     TYA     = 6'd56,
                     INT     = 6'd57, // Hardware interrupts (NMI and IRQ), not an opcode
                     BRK     = 6'd58;

    // Addressing Modes
    localparam [5:0] IMP_RST = 6'd0, // CPU reset, not an addressing mode
                     IMP     = 6'd1,
                     ACC     = 6'd2,
                     REL     = 6'd3,
                     IMM     = 6'd4,
                     ZP_R    = 6'd5,
                     ZP_M    = 6'd6,
                     ZP_W    = 6'd7,
                     ZPX_R   = 6'd8,
                     ZPX_M   = 6'd9,
                     ZPX_W   = 6'd10,
                     ZPY_R   = 6'd11,
                     ZPY_W   = 6'd12,
                     ABS_R   = 6'd13,
                     ABS_M   = 6'd14,
                     ABS_W   = 6'd15,
                     ABS_JMP = 6'd16,
                     ABS_JSR = 6'd17,
                     ABSX_R  = 6'd18,
                     ABSX_M  = 6'd19,
                     ABSX_W  = 6'd20,
                     ABSY_R  = 6'd21,
                     ABSY_W  = 6'd22,
                     INDX_R  = 6'd23,
                     INDX_W  = 6'd24,
                     INDY_R  = 6'd25,
                     INDY_W  = 6'd26,
                     IND_JMP = 6'd27,
                     IMP_PH  = 6'd28,
                     IMP_PL  = 6'd29,
                     IMP_RTI = 6'd30,
                     IMP_RTS = 6'd31,
                     IMP_INT = 6'd32, // Hardware interrupts (NMI and IRQ), not an addressing mode
                     IMP_BRK = 6'd33;


    // States of CPU named after https://www.nesdev.org/6502_cpu.txt
    localparam [5:0] CPU_RESET                     = 6'd0,
                     FETCH_INSTR                   = 6'd1,
                     FETCH_INSTR_WRITEBACK_REG     = 6'd2,
                     FETCH_VAL                     = 6'd3,
                     READ_DUMMY_BYTE_ACC_IMP       = 6'd4,
                     FETCH_ZADDR                   = 6'd5,
                     FETCH_LADDR                   = 6'd6,
                     FETCH_HADDR                   = 6'd7,
                     FETCH_POINT_ADDR              = 6'd8,
                     FETCH_POINT_LADDR             = 6'd9,
                     FETCH_POINT_HADDR             = 6'd10,
                     FETCH_OPERAND                 = 6'd11,
                     READ_DUMMY_BYTE_SP_IMP        = 6'd12,
                     READ_FROM_ADDR_ADD_IND_ADDR   = 6'd13,
                     READ_FROM_EFADDR_R            = 6'd14,
                     READ_FROM_EFADDR_M            = 6'd15,
                     WRITE_REG_TO_EFADDR           = 6'd16,
                     FETCH_EFLADDR                 = 6'd17,
                     FETCH_EFHADDR                 = 6'd18,
                     FETCH_EFHADDR_ADD_IND_EFLADDR = 6'd19,
                     FETCH_HADDR_ADD_IND_LADDR     = 6'd20,
                     READ_FROM_EFADDR_FIX_EFHADDR  = 6'd21,
                     DO_OPERATION                  = 6'd22,
                     WRITE_NEW_VALUE               = 6'd23,
                     FETCH_LBADDR_TO_LATCH         = 6'd24,
                     COPY_TO_PCL_FETCH_TO_PCH_IND  = 6'd25,
                     COPY_TO_PCL_FETCH_TO_PCH_ABS  = 6'd26,
                     ADD_OPERAND_TO_PCL            = 6'd27,
                     FIX_PCH                       = 6'd28,
                     PUSH_PCH_DECREMENT_SP         = 6'd29,
                     PUSH_PCL_DECREMENT_SP         = 6'd30,
                     PUSH_REG_DECREMENT_SP         = 6'd31,
                     INCREMENT_SP                  = 6'd32,
                     PULL_REG                      = 6'd33,
                     PULL_PS_INCREMENT_SP          = 6'd34,
                     PULL_PCL_INCREMENT_SP         = 6'd35,
                     PULL_PCH                      = 6'd36,
                     INCREMENT_PC                  = 6'd37,
                     FETCH_HADDR_JSR               = 6'd38,
                     FETCH_PCL_INTERRUPT_RESET     = 6'd39,
                     FETCH_PCH_INTERRUPT_RESET     = 6'd40,
                     INVALID_STATE                 = 6'd41;


    // Адреса регистров
    localparam [3:0] AC_REG_ADDR        = 4'h0,
                     XI_REG_ADDR        = 4'h1,
                     YI_REG_ADDR        = 4'h2,
                     SP_REG_ADDR        = 4'h3,
                     PS_REG_ADDR        = 4'h4,
                     PCL_REG_ADDR       = 4'h5,
                     PCH_REG_ADDR       = 4'h6,
                     CPU_LADDR_REG_ADDR = 4'h7,
                     CPU_HADDR_REG_ADDR = 4'h8;


    // Операции АЛУ
    localparam [2:0] ALU_NOP = 3'h0,
                     ALU_ADD = 3'h1,
                     ALU_AND = 3'h2,
                     ALU_OR  = 3'h3,
                     ALU_XOR = 3'h4,
                     ALU_MV  = 3'h5,
                     ALU_SL  = 3'h6,
                     ALU_SR  = 3'h7;


    // Сигналы конечного автомата
    reg  [ 5:0] state_r;
    reg  [ 5:0] state_next_r;
    wire        fetch_instr_ns_w;
    wire        fetch_instr_writeback_reg_ns_w;
    wire        fetch_pch_interrupt_reset_ns_w;
    wire        add_operand_to_pcl_ns_w;
    wire        fetch_efhaddr_add_ind_efladdr_ns_w;
    wire        fetch_haddr_add_ind_laddr_ns_w;
    wire        fetch_operand_ns_w;
    wire        invalid_state_ns_w;

    // Сигналы декодера-парсера инструкций
    reg  [ 5:0] opcode_r;
    reg  [ 5:0] opcode_next_r;
    reg  [ 5:0] opcode_decoded_r;
    reg  [ 5:0] addr_mode_r;
    reg  [ 5:0] addr_mode_next_r;
    reg  [ 5:0] addr_mode_decoded_r;
    reg         zero_page_mode_r;
    reg         zero_page_mode_next_r;
    reg         zero_page_mode_decoded_r;
    reg         use_x_reg_r;
    reg         use_x_reg_next_r;
    reg         use_x_reg_decoded_r;
    reg         branch_is_taken_r;
    wire        branch_is_taken_next_w;
    reg         branch_condition_r;
    wire        new_instruction_w;

    // Сигналы регистрового файла
    reg  [ 7:0] register_r       [8:0];
    wire [ 7:0] register_reset_w [8:0];
    wire [ 7:0] register_next_w  [8:0];
    wire        reg_sel_w        [8:0];
    // Текущие (защёлкнутые) состояния регистров на каждом такте
    wire [ 7:0] ac_reg_w;
    wire [ 7:0] xi_reg_w;
    wire [ 7:0] yi_reg_w;
    wire [ 7:0] pcl_reg_w;
    wire [ 7:0] pch_reg_w;
    wire [15:0] pc_reg_w;
    wire [ 7:0] sp_reg_w;
    wire [ 7:0] cpu_laddr_reg_w;
    wire [ 7:0] cpu_haddr_reg_w;
    wire [ 7:0] ps_reg_w;
    wire        n_status_bit_w;
    wire        v_status_bit_w;
    wire        b_status_bit_w;
    wire        u_status_bit_w;
    wire        d_status_bit_w;
    wire        i_status_bit_w;
    wire        z_status_bit_w;
    wire        c_status_bit_w;
    // Обновлённые (вычисленные) состояния регистров на каждом такте
    wire        pc_is_incred_fetch_op_w;
    wire        pc_is_incred_read_dummy_w;
    wire [15:0] pc_sp_reg_updater_w;
    reg  [15:0] pc_sp_reg_r;
    reg  [ 7:0] pc_sp_upd_val_r;
    reg  [15:0] pc_reg_next_r;
    reg  [ 7:0] sp_reg_next_r;
    reg  [ 7:0] ps_reg_next_r;
    reg  [ 7:0] cpu_haddr_reg_next_r;
    reg  [ 7:0] cpu_laddr_reg_next_r;
    reg         n_status_bit_next_r;
    reg         c_status_bit_next_r;
    reg         z_status_bit_next_r;
    reg         v_status_bit_next_r;
    reg         i_status_bit_next_r;
    reg         b_status_bit_next_r;
    reg         u_status_bit_next_r;
    reg         d_status_bit_next_r;

    // Сигналы логики управления процессорной шиной
    reg         cpu_wr_r;
    reg  [15:0] cpu_addr_r;
    wire [ 7:0] cpu_wr_data_w;
    reg  [15:0] cpu_addr_buffer_r;
    reg  [ 7:0] cpu_rd_data_buffer_r;
    reg         use_pc_r;
    reg         use_sp_r;
    reg         use_iv_src_r;
    reg         use_aux_src_r;
    reg         use_ptr_incr_r;
    reg         use_zp_ptr_r;
    wire        use_rst_vector_w;
    wire        use_nmi_vector_w;
    wire        use_irq_vector_w;
    wire        use_zp_mode_w;
    wire        use_eff_addr_w;
    wire        use_zp_addr_w;

    // Сигналы логики АЛУ
    reg         reg_wr_r;
    wire [ 7:0] reg_wr_data_w;
    reg  [ 3:0] dst_reg_addr_r;
    reg  [ 2:0] alu_op_r;
    reg  [ 7:0] alu_in_a_r;
    reg  [ 7:0] alu_in_b_r;
    reg         alu_in_c_r;
    wire [ 7:0] index_reg_data_w;
    reg         alu_carry_r;
    reg  [ 7:0] alu_result_r;
    reg  [ 8:0] alu_buffer_r;

    // Сигналы логики прерываний
    reg         nmi_r;
    reg         nmi_posedge_r;
    reg         nmi_posedge_next_r;
    reg         nmi_received_r;
    reg         nmi_received_next_r;
    reg         irq_received_r;
    reg         irq_received_next_r;
    reg         brk_received_r;
    wire        brk_received_next_w;
    reg         rst_received_r;
    wire        rst_received_next_w;
    wire        nmi_posedge_detect_w;
    wire        nmi_reset_cond_w;
    wire        irq_reset_cond_w;
    wire        irq_poslevel_w;
    wire        irq_enabled_w;
    wire        brk_opcode_w;
    wire        brk_enter_w;
    wire        rst_vector_w;
    wire        nmi_vector_w;
    wire        irq_vector_w;
    wire        hw_interrupt_received_w;
    reg         interrupt_polling_r;
    wire        nmi_polling_w;
    wire        irq_polling_w;

    // Сигналы исправления адреса при пересечении страницы
    reg         fixing_pch_r;
    wire        fixing_pch_next_w;
    reg         fixing_haddr_r;
    reg         fixing_haddr_next_r;
    wire        fixing_pch_rel_w;
    wire        fixing_pch_indy_w;
    wire        fixing_pch_absx_absy_w;
    wire        fixing_pch_indexed_w;
    wire        fixing_pch_rel_cond_w;


    // Отдельно использующиеся состояния конечного автомата
    assign fetch_instr_ns_w                   = (state_next_r == FETCH_INSTR);
    assign fetch_instr_writeback_reg_ns_w     = (state_next_r == FETCH_INSTR_WRITEBACK_REG);
    assign fetch_pch_interrupt_reset_ns_w     = (state_next_r == FETCH_PCH_INTERRUPT_RESET);
    assign add_operand_to_pcl_ns_w            = (state_next_r == ADD_OPERAND_TO_PCL);
    assign fetch_efhaddr_add_ind_efladdr_ns_w = (state_next_r == FETCH_EFHADDR_ADD_IND_EFLADDR);
    assign fetch_haddr_add_ind_laddr_ns_w     = (state_next_r == FETCH_HADDR_ADD_IND_LADDR);
    assign invalid_state_ns_w                 = (state_next_r == INVALID_STATE);
    assign fetch_operand_ns_w                 = (state_next_r == FETCH_OPERAND);

    assign new_instruction_w                  = fetch_instr_ns_w || fetch_instr_writeback_reg_ns_w;


    // Логика контроллера прерываний
    always @(posedge clk_i)
        if (rst_i) begin
            nmi_received_r <= 1'b0;
            irq_received_r <= 1'b0;
            brk_received_r <= 1'b0;
            rst_received_r <= 1'b1;
        end else if (~halt_i) begin
            nmi_received_r <= nmi_received_next_r;
            irq_received_r <= irq_received_next_r;
            brk_received_r <= brk_received_next_w;
            rst_received_r <= rst_received_next_w;
        end

    always @(posedge mclk_i)
        if (rst_i) begin
            nmi_r          <= 1'b0;
            nmi_posedge_r  <= 1'b0;
        end else if (~halt_i) begin
            nmi_r          <= ppu_nmi_i;
            nmi_posedge_r  <= nmi_posedge_next_r;
        end

    assign rst_vector_w            =  rst_received_r;
    assign nmi_vector_w            = ~rst_received_r &&  nmi_received_r;
    assign irq_vector_w            = ~rst_received_r && ~nmi_received_r && (irq_received_r|| brk_received_r);

    assign hw_interrupt_received_w = nmi_received_r || irq_received_r;

    assign nmi_posedge_detect_w    = ppu_nmi_i & ~nmi_r;

    assign irq_poslevel_w          = apu_frame_irq_i || apu_dmc_irq_i || mapper_irq_i;
    assign irq_enabled_w           = ~i_status_bit_w;

    assign brk_opcode_w            = (cpu_rd_data_i == BRK_IMP);
    assign brk_enter_w             = brk_opcode_w && ~hw_interrupt_received_w;

    assign nmi_reset_cond_w        = fetch_pch_interrupt_reset_ns_w && nmi_received_r;
    assign irq_reset_cond_w        = fetch_pch_interrupt_reset_ns_w && irq_received_r;

    assign nmi_polling_w           = interrupt_polling_r;
    assign irq_polling_w           = interrupt_polling_r && irq_enabled_w;

    assign brk_received_next_w     = (new_instruction_w) ? brk_enter_w : brk_received_r;
    assign rst_received_next_w     = (new_instruction_w) ? 1'b0        : rst_received_r;

    wire [1:0] irq_received_next_case_w = {irq_reset_cond_w, irq_polling_w};
    always @(*)
        casez (irq_received_next_case_w)
            2'b1_?:  irq_received_next_r = 1'b0;
            2'b0_1:  irq_received_next_r = irq_poslevel_w;
            default: irq_received_next_r = irq_received_r;
        endcase

    wire [1:0] nmi_posedge_next_case_w = {nmi_reset_cond_w, nmi_posedge_detect_w};
    always @(*)
        casez (nmi_posedge_next_case_w)
            2'b1_?:  nmi_posedge_next_r = 1'b0;
            2'b0_1:  nmi_posedge_next_r = 1'b1;
            default: nmi_posedge_next_r = nmi_posedge_r;
        endcase

    wire [1:0] nmi_received_next_case_w = {nmi_reset_cond_w, nmi_polling_w};
    always @(*)
        casez (nmi_received_next_case_w)
            2'b1_?:  nmi_received_next_r = 1'b0;
            2'b0_1:  nmi_received_next_r = nmi_posedge_r;
            default: nmi_received_next_r = nmi_received_r;
        endcase

    always @(*)
        case (state_next_r)

            WRITE_REG_TO_EFADDR,
            WRITE_NEW_VALUE,
            INCREMENT_PC, FIX_PCH,
            READ_DUMMY_BYTE_ACC_IMP,
            FETCH_OPERAND, PULL_REG,
            FETCH_VAL, READ_FROM_EFADDR_R,
            COPY_TO_PCL_FETCH_TO_PCH_ABS,
            COPY_TO_PCL_FETCH_TO_PCH_IND,
            PULL_PCH, PUSH_REG_DECREMENT_SP: interrupt_polling_r = 1'b1;

            default:                         interrupt_polling_r = 1'b0;

        endcase


    /* Декодер входящих инструкций.
     * Здсь просто разделяем инструкцию на тип операции и адресный режим */
    always @(posedge clk_i)
        if (rst_i) begin
            opcode_r         <= RST;
            addr_mode_r      <= IMP_RST;
            zero_page_mode_r <= 1'b0;
            use_x_reg_r      <= 1'b0;
        end else if (~halt_i) begin
            opcode_r         <= opcode_next_r;
            addr_mode_r      <= addr_mode_next_r;
            zero_page_mode_r <= zero_page_mode_next_r;
            use_x_reg_r      <= use_x_reg_next_r;
        end

    wire [1:0] new_operation_case_w = {hw_interrupt_received_w, new_instruction_w};
    always @(*)
        case (new_operation_case_w)
            2'b11: begin
                opcode_next_r         = INT;
                addr_mode_next_r      = IMP_INT;
                zero_page_mode_next_r = 1'b0;
                use_x_reg_next_r      = 1'b0;
            end
            2'b01: begin
                opcode_next_r         = opcode_decoded_r;
                addr_mode_next_r      = addr_mode_decoded_r;
                zero_page_mode_next_r = zero_page_mode_decoded_r;
                use_x_reg_next_r      = use_x_reg_decoded_r;
            end
            default: begin
                opcode_next_r         = opcode_r;
                addr_mode_next_r      = addr_mode_r;
                zero_page_mode_next_r = zero_page_mode_r;
                use_x_reg_next_r      = use_x_reg_r;
            end
        endcase

    always @(*)
        case (cpu_rd_data_i)
            ADC_IMM: begin
                opcode_decoded_r         = ADC;
                addr_mode_decoded_r      = IMM;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ADC_ZP: begin
                opcode_decoded_r         = ADC;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            ADC_ZPX: begin
                opcode_decoded_r         = ADC;
                addr_mode_decoded_r      = ZPX_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            ADC_ABS: begin
                opcode_decoded_r         = ADC;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ADC_ABSX: begin
                opcode_decoded_r         = ADC;
                addr_mode_decoded_r      = ABSX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            ADC_ABSY: begin
                opcode_decoded_r         = ADC;
                addr_mode_decoded_r      = ABSY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ADC_INDX: begin
                opcode_decoded_r         = ADC;
                addr_mode_decoded_r      = INDX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            ADC_INDY: begin
                opcode_decoded_r         = ADC;
                addr_mode_decoded_r      = INDY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            AND_IMM: begin
                opcode_decoded_r         = AND;
                addr_mode_decoded_r      = IMM;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            AND_ZP: begin
                opcode_decoded_r         = AND;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            AND_ZPX: begin
                opcode_decoded_r         = AND;
                addr_mode_decoded_r      = ZPX_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            AND_ABS: begin
                opcode_decoded_r         = AND;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            AND_ABSX: begin
                opcode_decoded_r         = AND;
                addr_mode_decoded_r      = ABSX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            AND_ABSY: begin
                opcode_decoded_r         = AND;
                addr_mode_decoded_r      = ABSY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            AND_INDX: begin
                opcode_decoded_r         = AND;
                addr_mode_decoded_r      = INDX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            AND_INDY: begin
                opcode_decoded_r         = AND;
                addr_mode_decoded_r      = INDY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ASL_ACC: begin
                opcode_decoded_r         = ASL;
                addr_mode_decoded_r      = ACC;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ASL_ZP: begin
                opcode_decoded_r         = ASL;
                addr_mode_decoded_r      = ZP_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            ASL_ZPX: begin
                opcode_decoded_r         = ASL;
                addr_mode_decoded_r      = ZPX_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            ASL_ABS: begin
                opcode_decoded_r         = ASL;
                addr_mode_decoded_r      = ABS_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ASL_ABSX: begin
                opcode_decoded_r         = ASL;
                addr_mode_decoded_r      = ABSX_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            BCC_REL: begin
                opcode_decoded_r         = BCC;
                addr_mode_decoded_r      = REL;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            BCS_REL: begin
                opcode_decoded_r         = BCS;
                addr_mode_decoded_r      = REL;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            BEQ_REL: begin
                opcode_decoded_r         = BEQ;
                addr_mode_decoded_r      = REL;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            BMI_REL: begin
                opcode_decoded_r         = BMI;
                addr_mode_decoded_r      = REL;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            BNE_REL: begin
                opcode_decoded_r         = BNE;
                addr_mode_decoded_r      = REL;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            BPL_REL: begin
                opcode_decoded_r         = BPL;
                addr_mode_decoded_r      = REL;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            BVC_REL: begin
                opcode_decoded_r         = BVC;
                addr_mode_decoded_r      = REL;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            BVS_REL: begin
                opcode_decoded_r         = BVS;
                addr_mode_decoded_r      = REL;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            BIT_ZP: begin
                opcode_decoded_r         = BIT;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            BIT_ABS: begin
                opcode_decoded_r         = BIT;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            BRK_IMP: begin
                opcode_decoded_r         = BRK;
                addr_mode_decoded_r      = IMP_BRK;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CLC_IMP: begin
                opcode_decoded_r         = CLC;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CLD_IMP: begin
                opcode_decoded_r         = CLD;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CLI_IMP: begin
                opcode_decoded_r         = CLI;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CLV_IMP: begin
                opcode_decoded_r         = CLV;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CMP_IMM: begin
                opcode_decoded_r         = CMP;
                addr_mode_decoded_r      = IMM;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CMP_ZP: begin
                opcode_decoded_r         = CMP;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            CMP_ZPX: begin
                opcode_decoded_r         = CMP;
                addr_mode_decoded_r      = ZPX_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            CMP_ABS: begin
                opcode_decoded_r         = CMP;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CMP_ABSX: begin
                opcode_decoded_r         = CMP;
                addr_mode_decoded_r      = ABSX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            CMP_ABSY: begin
                opcode_decoded_r         = CMP;
                addr_mode_decoded_r      = ABSY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CMP_INDX: begin
                opcode_decoded_r         = CMP;
                addr_mode_decoded_r      = INDX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            CMP_INDY: begin
                opcode_decoded_r         = CMP;
                addr_mode_decoded_r      = INDY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CPX_IMM: begin
                opcode_decoded_r         = CPX;
                addr_mode_decoded_r      = IMM;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CPX_ZP: begin
                opcode_decoded_r         = CPX;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            CPX_ABS: begin
                opcode_decoded_r         = CPX;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CPY_IMM: begin
                opcode_decoded_r         = CPY;
                addr_mode_decoded_r      = IMM;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            CPY_ZP: begin
                opcode_decoded_r         = CPY;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            CPY_ABS: begin
                opcode_decoded_r         = CPY;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            DEC_ZP: begin
                opcode_decoded_r         = DEC;
                addr_mode_decoded_r      = ZP_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            DEC_ZPX: begin
                opcode_decoded_r         = DEC;
                addr_mode_decoded_r      = ZPX_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            DEC_ABS: begin
                opcode_decoded_r         = DEC;
                addr_mode_decoded_r      = ABS_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            DEC_ABSX: begin
                opcode_decoded_r         = DEC;
                addr_mode_decoded_r      = ABSX_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            DEX_IMP: begin
                opcode_decoded_r         = DEX;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            DEY_IMP: begin
                opcode_decoded_r         = DEY;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            EOR_IMM: begin
                opcode_decoded_r         = EOR;
                addr_mode_decoded_r      = IMM;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            EOR_ZP: begin
                opcode_decoded_r         = EOR;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            EOR_ZPX: begin
                opcode_decoded_r         = EOR;
                addr_mode_decoded_r      = ZPX_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            EOR_ABS: begin
                opcode_decoded_r         = EOR;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            EOR_ABSX: begin
                opcode_decoded_r         = EOR;
                addr_mode_decoded_r      = ABSX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            EOR_ABSY: begin
                opcode_decoded_r         = EOR;
                addr_mode_decoded_r      = ABSY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            EOR_INDX: begin
                opcode_decoded_r         = EOR;
                addr_mode_decoded_r      = INDX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            EOR_INDY: begin
                opcode_decoded_r         = EOR;
                addr_mode_decoded_r      = INDY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            INC_ZP: begin
                opcode_decoded_r         = INC;
                addr_mode_decoded_r      = ZP_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            INC_ZPX: begin
                opcode_decoded_r         = INC;
                addr_mode_decoded_r      = ZPX_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            INC_ABS: begin
                opcode_decoded_r         = INC;
                addr_mode_decoded_r      = ABS_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            INC_ABSX: begin
                opcode_decoded_r         = INC;
                addr_mode_decoded_r      = ABSX_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            INX_IMP: begin
                opcode_decoded_r         = INX;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            INY_IMP: begin
                opcode_decoded_r         = INY;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            JMP_ABS: begin
                opcode_decoded_r         = JMP;
                addr_mode_decoded_r      = ABS_JMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            JMP_IND: begin
                opcode_decoded_r         = JMP;
                addr_mode_decoded_r      = IND_JMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            JSR_ABS: begin
                opcode_decoded_r         = JSR;
                addr_mode_decoded_r      = ABS_JSR;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDA_IMM: begin
                opcode_decoded_r         = LDA;
                addr_mode_decoded_r      = IMM;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDA_ZP: begin
                opcode_decoded_r         = LDA;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDA_ZPX: begin
                opcode_decoded_r         = LDA;
                addr_mode_decoded_r      = ZPX_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            LDA_ABS: begin
                opcode_decoded_r         = LDA;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDA_ABSX: begin
                opcode_decoded_r         = LDA;
                addr_mode_decoded_r      = ABSX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            LDA_ABSY: begin
                opcode_decoded_r         = LDA;
                addr_mode_decoded_r      = ABSY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDA_INDX: begin
                opcode_decoded_r         = LDA;
                addr_mode_decoded_r      = INDX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            LDA_INDY: begin
                opcode_decoded_r         = LDA;
                addr_mode_decoded_r      = INDY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDX_IMM: begin
                opcode_decoded_r         = LDX;
                addr_mode_decoded_r      = IMM;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDX_ZP: begin
                opcode_decoded_r         = LDX;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDX_ZPY: begin
                opcode_decoded_r         = LDX;
                addr_mode_decoded_r      = ZPY_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDX_ABS: begin
                opcode_decoded_r         = LDX;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDX_ABSY: begin
                opcode_decoded_r         = LDX;
                addr_mode_decoded_r      = ABSY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDY_IMM: begin
                opcode_decoded_r         = LDY;
                addr_mode_decoded_r      = IMM;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDY_ZP: begin
                opcode_decoded_r         = LDY;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDY_ZPX: begin
                opcode_decoded_r         = LDY;
                addr_mode_decoded_r      = ZPX_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            LDY_ABS: begin
                opcode_decoded_r         = LDY;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LDY_ABSX: begin
                opcode_decoded_r         = LDY;
                addr_mode_decoded_r      = ABSX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            LSR_ACC: begin
                opcode_decoded_r         = LSR;
                addr_mode_decoded_r      = ACC;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LSR_ZP: begin
                opcode_decoded_r         = LSR;
                addr_mode_decoded_r      = ZP_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            LSR_ZPX: begin
                opcode_decoded_r         = LSR;
                addr_mode_decoded_r      = ZPX_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            LSR_ABS: begin
                opcode_decoded_r         = LSR;
                addr_mode_decoded_r      = ABS_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            LSR_ABSX: begin
                opcode_decoded_r         = LSR;
                addr_mode_decoded_r      = ABSX_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            NOP_IMP: begin
                opcode_decoded_r         = NOP;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ORA_IMM: begin
                opcode_decoded_r         = ORA;
                addr_mode_decoded_r      = IMM;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ORA_ZP: begin
                opcode_decoded_r         = ORA;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            ORA_ZPX: begin
                opcode_decoded_r         = ORA;
                addr_mode_decoded_r      = ZPX_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            ORA_ABS: begin
                opcode_decoded_r         = ORA;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ORA_ABSX: begin
                opcode_decoded_r         = ORA;
                addr_mode_decoded_r      = ABSX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            ORA_ABSY: begin
                opcode_decoded_r         = ORA;
                addr_mode_decoded_r      = ABSY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ORA_INDX: begin
                opcode_decoded_r         = ORA;
                addr_mode_decoded_r      = INDX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            ORA_INDY: begin
                opcode_decoded_r         = ORA;
                addr_mode_decoded_r      = INDY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            PHA_IMP: begin
                opcode_decoded_r         = PHA;
                addr_mode_decoded_r      = IMP_PH;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            PHP_IMP: begin
                opcode_decoded_r         = PHP;
                addr_mode_decoded_r      = IMP_PH;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            PLA_IMP: begin
                opcode_decoded_r         = PLA;
                addr_mode_decoded_r      = IMP_PL;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            PLP_IMP: begin
                opcode_decoded_r         = PLP;
                addr_mode_decoded_r      = IMP_PL;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ROL_ACC: begin
                opcode_decoded_r         = ROL;
                addr_mode_decoded_r      = ACC;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ROL_ZP: begin
                opcode_decoded_r         = ROL;
                addr_mode_decoded_r      = ZP_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            ROL_ZPX: begin
                opcode_decoded_r         = ROL;
                addr_mode_decoded_r      = ZPX_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            ROL_ABS: begin
                opcode_decoded_r         = ROL;
                addr_mode_decoded_r      = ABS_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ROL_ABSX: begin
                opcode_decoded_r         = ROL;
                addr_mode_decoded_r      = ABSX_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            ROR_ACC: begin
                opcode_decoded_r         = ROR;
                addr_mode_decoded_r      = ACC;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ROR_ZP: begin
                opcode_decoded_r         = ROR;
                addr_mode_decoded_r      = ZP_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            ROR_ZPX: begin
                opcode_decoded_r         = ROR;
                addr_mode_decoded_r      = ZPX_M;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            ROR_ABS: begin
                opcode_decoded_r         = ROR;
                addr_mode_decoded_r      = ABS_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            ROR_ABSX: begin
                opcode_decoded_r         = ROR;
                addr_mode_decoded_r      = ABSX_M;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            RTI_IMP: begin
                opcode_decoded_r         = RTI;
                addr_mode_decoded_r      = IMP_RTI;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            RTS_IMP: begin
                opcode_decoded_r         = RTS;
                addr_mode_decoded_r      = IMP_RTS;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            SBC_IMM: begin
                opcode_decoded_r         = SBC;
                addr_mode_decoded_r      = IMM;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            SBC_ZP: begin
                opcode_decoded_r         = SBC;
                addr_mode_decoded_r      = ZP_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            SBC_ZPX: begin
                opcode_decoded_r         = SBC;
                addr_mode_decoded_r      = ZPX_R;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            SBC_ABS: begin
                opcode_decoded_r         = SBC;
                addr_mode_decoded_r      = ABS_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            SBC_ABSX: begin
                opcode_decoded_r         = SBC;
                addr_mode_decoded_r      = ABSX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            SBC_ABSY: begin
                opcode_decoded_r         = SBC;
                addr_mode_decoded_r      = ABSY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            SBC_INDX: begin
                opcode_decoded_r         = SBC;
                addr_mode_decoded_r      = INDX_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            SBC_INDY: begin
                opcode_decoded_r         = SBC;
                addr_mode_decoded_r      = INDY_R;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            SEC_IMP: begin
                opcode_decoded_r         = SEC;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            SED_IMP: begin
                opcode_decoded_r         = SED;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            SEI_IMP: begin
                opcode_decoded_r         = SEI;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            STA_ZP: begin
                opcode_decoded_r         = STA;
                addr_mode_decoded_r      = ZP_W;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            STA_ZPX: begin
                opcode_decoded_r         = STA;
                addr_mode_decoded_r      = ZPX_W;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            STA_ABS: begin
                opcode_decoded_r         = STA;
                addr_mode_decoded_r      = ABS_W;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            STA_ABSX: begin
                opcode_decoded_r         = STA;
                addr_mode_decoded_r      = ABSX_W;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            STA_ABSY: begin
                opcode_decoded_r         = STA;
                addr_mode_decoded_r      = ABSY_W;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            STA_INDX: begin
                opcode_decoded_r         = STA;
                addr_mode_decoded_r      = INDX_W;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b1;
            end
            STA_INDY: begin
                opcode_decoded_r         = STA;
                addr_mode_decoded_r      = INDY_W;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            STX_ZP: begin
                opcode_decoded_r         = STX;
                addr_mode_decoded_r      = ZP_W;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            STX_ZPY: begin
                opcode_decoded_r         = STX;
                addr_mode_decoded_r      = ZPY_W;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            STX_ABS: begin
                opcode_decoded_r         = STX;
                addr_mode_decoded_r      = ABS_W;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            STY_ZP: begin
                opcode_decoded_r         = STY;
                addr_mode_decoded_r      = ZP_W;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b0;
            end
            STY_ZPX: begin
                opcode_decoded_r         = STY;
                addr_mode_decoded_r      = ZPX_W;
                zero_page_mode_decoded_r = 1'b1;
                use_x_reg_decoded_r      = 1'b1;
            end
            STY_ABS: begin
                opcode_decoded_r         = STY;
                addr_mode_decoded_r      = ABS_W;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            TAX_IMP: begin
                opcode_decoded_r         = TAX;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            TAY_IMP: begin
                opcode_decoded_r         = TAY;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            TSX_IMP: begin
                opcode_decoded_r         = TSX;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            TXA_IMP: begin
                opcode_decoded_r         = TXA;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            TXS_IMP: begin
                opcode_decoded_r         = TXS;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            TYA_IMP: begin
                opcode_decoded_r         = TYA;
                addr_mode_decoded_r      = IMP;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
            default: begin
                opcode_decoded_r         = RST;
                addr_mode_decoded_r      = IMP_RST;
                zero_page_mode_decoded_r = 1'b0;
                use_x_reg_decoded_r      = 1'b0;
            end
        endcase


    // Переходы конечного автомата реализованы в соответствии с https://www.nesdev.org/6502_cpu.txt
    always @(posedge clk_i)
        if      (rst_i  ) state_r <= CPU_RESET;
        else if (~halt_i) state_r <= state_next_r;

    always @(*)
        case (state_r)

            CPU_RESET:                         state_next_r = PUSH_PCH_DECREMENT_SP;

            FETCH_INSTR, FETCH_INSTR_WRITEBACK_REG:
                case (addr_mode_r)
                    IMM:                       state_next_r = FETCH_VAL;
                    ACC, IMP:                  state_next_r = READ_DUMMY_BYTE_ACC_IMP;
                    ZP_R, ZP_W, ZPX_R,
                    ZPX_W, ZPY_R, ZPY_W,
                    ZP_M, ZPX_M:               state_next_r = FETCH_ZADDR;
                    ABSX_R, ABSX_W, ABSY_R,
                    ABSY_W, ABS_M, ABSX_M,
                    ABS_JMP, ABS_JSR,
                    ABS_R, ABS_W:              state_next_r = FETCH_LADDR;
                    INDX_R, INDY_R,
                    INDX_W, INDY_W:            state_next_r = FETCH_POINT_ADDR;
                    IND_JMP:                   state_next_r = FETCH_POINT_LADDR;
                    REL:                       state_next_r = FETCH_OPERAND;
                    IMP_PH, IMP_PL,
                    IMP_RTI, IMP_RTS,
                    IMP_INT, IMP_BRK:          state_next_r = READ_DUMMY_BYTE_SP_IMP;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            WRITE_NEW_VALUE,
            WRITE_REG_TO_EFADDR,
            READ_DUMMY_BYTE_ACC_IMP:           state_next_r = FETCH_INSTR;

            FETCH_VAL, READ_FROM_EFADDR_R:     state_next_r = FETCH_INSTR_WRITEBACK_REG;

            READ_DUMMY_BYTE_SP_IMP:
                case (addr_mode_r)
                    IMP_PH:                    state_next_r = PUSH_REG_DECREMENT_SP;
                    IMP_PL, IMP_RTI, IMP_RTS:  state_next_r = INCREMENT_SP;
                    IMP_INT, IMP_BRK:          state_next_r = PUSH_PCH_DECREMENT_SP;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            FETCH_ZADDR:
                case (addr_mode_r)
                    ZP_R:                      state_next_r = READ_FROM_EFADDR_R;
                    ZPX_R, ZPY_R, ZPX_W,
                    ZPY_W, ZPX_M:              state_next_r = READ_FROM_ADDR_ADD_IND_ADDR;
                    ZP_M:                      state_next_r = READ_FROM_EFADDR_M;
                    ZP_W:                      state_next_r = WRITE_REG_TO_EFADDR;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            READ_FROM_ADDR_ADD_IND_ADDR:
                case (addr_mode_r)
                    ZPX_R, ZPY_R:              state_next_r = READ_FROM_EFADDR_R;
                    ZPX_M:                     state_next_r = READ_FROM_EFADDR_M;
                    INDX_R, INDX_W:            state_next_r = FETCH_EFLADDR;
                    ZPX_W, ZPY_W:              state_next_r = WRITE_REG_TO_EFADDR;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            FETCH_LADDR:
                case (addr_mode_r)
                    ABS_R, ABS_M, ABS_W:       state_next_r = FETCH_HADDR;
                    ABSX_R, ABSX_W,
                    ABSY_R, ABSY_W, ABSX_M:    state_next_r = FETCH_HADDR_ADD_IND_LADDR;
                    ABS_JMP:                   state_next_r = COPY_TO_PCL_FETCH_TO_PCH_ABS;
                    ABS_JSR:                   state_next_r = FETCH_HADDR_JSR;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            FETCH_HADDR:
                case (addr_mode_r)
                    ABS_R:                     state_next_r = READ_FROM_EFADDR_R;
                    ABS_M:                     state_next_r = READ_FROM_EFADDR_M;
                    ABS_W:                     state_next_r = WRITE_REG_TO_EFADDR;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            FETCH_HADDR_JSR:                   state_next_r = PUSH_PCH_DECREMENT_SP;

            FETCH_HADDR_ADD_IND_LADDR:
                case (addr_mode_r)
                    ABSX_R, ABSY_R:            state_next_r = (fixing_haddr_r) ? READ_FROM_EFADDR_FIX_EFHADDR :
                                                                                 READ_FROM_EFADDR_R;
                    ABSX_M, ABSX_W, ABSY_W:    state_next_r = READ_FROM_EFADDR_FIX_EFHADDR;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            READ_FROM_EFADDR_FIX_EFHADDR:
                case (addr_mode_r)
                    ABSX_R, ABSY_R, INDY_R:    state_next_r = READ_FROM_EFADDR_R;
                    ABSX_M:                    state_next_r = READ_FROM_EFADDR_M;
                    ABSX_W, ABSY_W, INDY_W:    state_next_r = WRITE_REG_TO_EFADDR;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            FETCH_POINT_ADDR:
                case (addr_mode_r)
                    INDX_R, INDX_W:            state_next_r = READ_FROM_ADDR_ADD_IND_ADDR;
                    INDY_R, INDY_W:            state_next_r = FETCH_EFLADDR;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            FETCH_EFLADDR:
                case (addr_mode_r)
                    INDX_R, INDX_W:            state_next_r = FETCH_EFHADDR;
                    INDY_R, INDY_W:            state_next_r = FETCH_EFHADDR_ADD_IND_EFLADDR;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            FETCH_EFHADDR :
                case (addr_mode_r)
                    INDX_R:                    state_next_r = READ_FROM_EFADDR_R;
                    INDX_W:                    state_next_r = WRITE_REG_TO_EFADDR;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            FETCH_EFHADDR_ADD_IND_EFLADDR :
                case (addr_mode_r)
                    INDY_R:                    state_next_r = (fixing_haddr_r) ? READ_FROM_EFADDR_FIX_EFHADDR :
                                                                                 READ_FROM_EFADDR_R;
                    INDY_W:                    state_next_r = READ_FROM_EFADDR_FIX_EFHADDR;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            READ_FROM_EFADDR_M:                state_next_r = DO_OPERATION;

            DO_OPERATION:                      state_next_r = WRITE_NEW_VALUE;

            FETCH_POINT_LADDR:                 state_next_r = FETCH_POINT_HADDR;

            FETCH_POINT_HADDR:                 state_next_r = FETCH_LBADDR_TO_LATCH;

            FETCH_LBADDR_TO_LATCH:             state_next_r = COPY_TO_PCL_FETCH_TO_PCH_IND;

            FETCH_OPERAND:                     state_next_r = (branch_is_taken_r) ? ADD_OPERAND_TO_PCL : FETCH_INSTR;

            ADD_OPERAND_TO_PCL:                state_next_r = (fixing_haddr_r) ? FIX_PCH : FETCH_INSTR;

            FIX_PCH:                           state_next_r = FETCH_INSTR;

            PUSH_PCH_DECREMENT_SP:             state_next_r = PUSH_PCL_DECREMENT_SP;

            PUSH_PCL_DECREMENT_SP:
                case (addr_mode_r)
                    ABS_JSR:                   state_next_r = COPY_TO_PCL_FETCH_TO_PCH_ABS;
                    IMP_INT, IMP_BRK, IMP_RST: state_next_r = PUSH_REG_DECREMENT_SP;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            PUSH_REG_DECREMENT_SP:
                case (addr_mode_r)
                    IMP_INT, IMP_BRK, IMP_RST: state_next_r = FETCH_PCL_INTERRUPT_RESET;
                    IMP_PH:                    state_next_r = FETCH_INSTR;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            INCREMENT_SP:
                case (addr_mode_r)
                    IMP_PL:                    state_next_r = PULL_REG;
                    IMP_RTI:                   state_next_r = PULL_PS_INCREMENT_SP;
                    IMP_RTS:                   state_next_r = PULL_PCL_INCREMENT_SP;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            PULL_REG:                          state_next_r = FETCH_INSTR;

            PULL_PS_INCREMENT_SP:              state_next_r = PULL_PCL_INCREMENT_SP;

            PULL_PCL_INCREMENT_SP:             state_next_r = PULL_PCH;

            PULL_PCH:
                case (addr_mode_r)
                    IMP_RTI:                   state_next_r = FETCH_INSTR;
                    IMP_RTS:                   state_next_r = INCREMENT_PC;
                    default:                   state_next_r = INVALID_STATE;
                endcase

            INCREMENT_PC:                      state_next_r = FETCH_INSTR;

            FETCH_PCL_INTERRUPT_RESET:         state_next_r = FETCH_PCH_INTERRUPT_RESET;

            FETCH_PCH_INTERRUPT_RESET:         state_next_r = FETCH_INSTR;

            COPY_TO_PCL_FETCH_TO_PCH_ABS,
            COPY_TO_PCL_FETCH_TO_PCH_IND:      state_next_r = FETCH_INSTR;

            INVALID_STATE:                     state_next_r = INVALID_STATE;

            default:                           state_next_r = state_r;

        endcase


    // Состояние флага условного перехода
    always @(posedge clk_i)
        if (~halt_i) branch_is_taken_r <= branch_is_taken_next_w;

    assign branch_is_taken_next_w = branch_condition_r && fetch_operand_ns_w;

    always @(*)
        case (opcode_r)
            BCC:     branch_condition_r = ~c_status_bit_w;
            BCS:     branch_condition_r =  c_status_bit_w;
            BEQ:     branch_condition_r =  z_status_bit_w;
            BNE:     branch_condition_r = ~z_status_bit_w;
            BMI:     branch_condition_r =  n_status_bit_w;
            BPL:     branch_condition_r = ~n_status_bit_w;
            BVC:     branch_condition_r = ~v_status_bit_w;
            BVS:     branch_condition_r =  v_status_bit_w;
            default: branch_condition_r =  1'b0;
        endcase


    /* Подготавливаем сигналы для подачи на АЛУ в зависимсти от текущего состояния и исполняемой операции.
     * Получаем тип АЛУ операции, входы АЛУ, флаг записи результата в регистровый файл и адресное пространство,
     * в какой регистр пишем результат.
     * Для разных операции какие-то сигналы могут быть незначащими */
    always @(*)
        case (state_next_r)
            READ_DUMMY_BYTE_ACC_IMP,
            FETCH_INSTR_WRITEBACK_REG: begin
                cpu_wr_r               = 1'b0;
                case (opcode_r)
                    ADC: begin
                        alu_op_r       = ALU_ADD;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = cpu_rd_data_buffer_r;
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    SBC: begin
                        alu_op_r       = ALU_ADD;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = ~cpu_rd_data_buffer_r;
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    AND: begin
                        alu_op_r       = ALU_AND;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = cpu_rd_data_buffer_r;
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    ORA: begin
                        alu_op_r       = ALU_OR;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = cpu_rd_data_buffer_r;
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    EOR: begin
                        alu_op_r       = ALU_XOR;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = cpu_rd_data_buffer_r;
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    LDA: begin
                        alu_op_r       = ALU_MV;
                        alu_in_a_r     = cpu_rd_data_buffer_r;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    LDX: begin
                        alu_op_r       = ALU_MV;
                        alu_in_a_r     = cpu_rd_data_buffer_r;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = XI_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    LDY: begin
                        alu_op_r       = ALU_MV;
                        alu_in_a_r     = cpu_rd_data_buffer_r;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = YI_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    CMP: begin
                        alu_op_r       = ALU_ADD;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = ~cpu_rd_data_buffer_r;
                        alu_in_c_r     = 1'b1;
                        dst_reg_addr_r = 4'h0; // Don't care
                        reg_wr_r       = 1'b0;
                    end
                    CPX: begin
                        alu_op_r       = ALU_ADD;
                        alu_in_a_r     = xi_reg_w;
                        alu_in_b_r     = ~cpu_rd_data_buffer_r;
                        alu_in_c_r     = 1'b1;
                        dst_reg_addr_r = 4'h0; // Don't care
                        reg_wr_r       = 1'b0;
                    end
                    CPY: begin
                        alu_op_r       = ALU_ADD;
                        alu_in_a_r     = yi_reg_w;
                        alu_in_b_r     = ~cpu_rd_data_buffer_r;
                        alu_in_c_r     = 1'b1;
                        dst_reg_addr_r = 4'h0; // Don't care
                        reg_wr_r       = 1'b0;
                    end
                    BIT: begin
                        alu_op_r       = ALU_AND;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = cpu_rd_data_buffer_r;
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = 4'h0; // Don't care
                        reg_wr_r       = 1'b0;
                    end
                    ASL: begin
                        alu_op_r       = ALU_SL;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = 1'b0;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    LSR: begin
                        alu_op_r       = ALU_SR;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = 1'b0;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    ROL: begin
                        alu_op_r       = ALU_SL;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    ROR: begin
                        alu_op_r       = ALU_SR;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    INX: begin
                        alu_op_r       = ALU_ADD;
                        alu_in_a_r     = xi_reg_w;
                        alu_in_b_r     = 1'b1;
                        alu_in_c_r     = 1'b0;
                        dst_reg_addr_r = XI_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    INY: begin
                        alu_op_r       = ALU_ADD;
                        alu_in_a_r     = yi_reg_w;
                        alu_in_b_r     = 1'b1;
                        alu_in_c_r     = 1'b0;
                        dst_reg_addr_r = YI_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    DEX: begin
                        alu_op_r       = ALU_ADD;
                        alu_in_a_r     = xi_reg_w;
                        alu_in_b_r     = 8'hFF;
                        alu_in_c_r     = 1'b0;
                        dst_reg_addr_r = XI_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    DEY: begin
                        alu_op_r       = ALU_ADD;
                        alu_in_a_r     = yi_reg_w;
                        alu_in_b_r     = 8'hFF;
                        alu_in_c_r     = 1'b0;
                        dst_reg_addr_r = YI_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    TAX: begin
                        alu_op_r       = ALU_MV;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = XI_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    TAY: begin
                        alu_op_r       = ALU_MV;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = YI_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    TXA: begin
                        alu_op_r       = ALU_MV;
                        alu_in_a_r     = xi_reg_w;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    TYA: begin
                        alu_op_r       = ALU_MV;
                        alu_in_a_r     = yi_reg_w;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = AC_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    TSX: begin
                        alu_op_r       = ALU_MV;
                        alu_in_a_r     = sp_reg_w;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = XI_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    TXS: begin
                        alu_op_r       = ALU_MV;
                        alu_in_a_r     = xi_reg_w;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                        dst_reg_addr_r = SP_REG_ADDR;
                        reg_wr_r       = 1'b1;
                    end
                    CLC, CLD, CLI, CLV,
                    NOP, SEC, SED, SEI: begin
                        alu_op_r       = ALU_NOP;
                        alu_in_a_r     = 8'h0; // Don't care
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = 1'b0; // Don't care
                        dst_reg_addr_r = 4'h0; // Don't care
                        reg_wr_r       = 1'b0;
                    end
                    default: begin
                        alu_op_r       = ALU_NOP;
                        alu_in_a_r     = 8'h0; // Don't care
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = 1'b0; // Don't care
                        dst_reg_addr_r = 4'h0; // Don't care
                        reg_wr_r       = 1'b0;
                    end
                endcase
            end
            DO_OPERATION: begin
                alu_in_a_r             = cpu_rd_data_i;
                dst_reg_addr_r         = 4'h0; // Don't care
                reg_wr_r               = 1'b0;
                cpu_wr_r               = 1'b0; // Результат остаётся в буфере АЛУ
                case (opcode_r)
                    ASL: begin
                        alu_op_r       = ALU_SL;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = 1'b0;
                    end
                    LSR: begin
                        alu_op_r       = ALU_SR;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = 1'b0;
                    end
                    ROL: begin
                        alu_op_r       = ALU_SL;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                    end
                    ROR: begin
                        alu_op_r       = ALU_SR;
                        alu_in_b_r     = 8'h0; // Don't care
                        alu_in_c_r     = c_status_bit_w;
                    end
                    INC: begin
                        alu_op_r       = ALU_ADD;
                        alu_in_b_r     = 1'b1;
                        alu_in_c_r     = 1'b0; // Don't care
                    end
                    DEC: begin
                        alu_op_r       = ALU_ADD;
                        alu_in_b_r     = 8'hFF;
                        alu_in_c_r     = 1'b0; // Don't care
                    end
                    default: begin
                        alu_op_r       = ALU_NOP;
                        alu_in_b_r     = 8'h0;
                        alu_in_c_r     = 1'b0;
                    end
                endcase
            end
            WRITE_NEW_VALUE: begin
                alu_op_r               = ALU_NOP;
                alu_in_a_r             = 8'h0; // Don't care
                alu_in_b_r             = 8'h0; // Don't care
                alu_in_c_r             = 1'b0; // Don't care
                dst_reg_addr_r         = 4'h0; // Don't care
                reg_wr_r               = 1'b0;
                cpu_wr_r               = 1'b1;
            end
            ADD_OPERAND_TO_PCL: begin
                alu_op_r               = ALU_ADD;
                alu_in_a_r             = pcl_reg_w;
                alu_in_b_r             = cpu_rd_data_buffer_r;
                alu_in_c_r             = 1'b0;
                dst_reg_addr_r         = PCL_REG_ADDR;
                reg_wr_r               = 1'b1;
                cpu_wr_r               = 1'b0;
            end
            FETCH_HADDR_ADD_IND_LADDR,
            FETCH_EFHADDR_ADD_IND_EFLADDR: begin
                alu_op_r               = ALU_ADD;
                alu_in_a_r             = cpu_laddr_reg_w;
                alu_in_b_r             = index_reg_data_w;
                alu_in_c_r             = 1'b0;
                dst_reg_addr_r         = CPU_LADDR_REG_ADDR;
                reg_wr_r               = 1'b1;
                cpu_wr_r               = 1'b0;
            end
            FIX_PCH: begin
                alu_op_r               = ALU_ADD;
                alu_in_a_r             = pch_reg_w;
                alu_in_b_r             = (fixing_pch_r) ? 8'hFF : 1'b1;
                alu_in_c_r             = 1'b0;
                dst_reg_addr_r         = PCH_REG_ADDR;
                reg_wr_r               = 1'b1;
                cpu_wr_r               = 1'b0;
            end
            READ_FROM_EFADDR_FIX_EFHADDR: begin
                alu_op_r               = ALU_ADD;
                alu_in_a_r             = cpu_haddr_reg_w;
                alu_in_b_r             = fixing_haddr_r;
                alu_in_c_r             = 1'b0;
                dst_reg_addr_r         = CPU_HADDR_REG_ADDR;
                reg_wr_r               = 1'b1;
                cpu_wr_r               = 1'b0;
            end
            PUSH_PCH_DECREMENT_SP: begin
                alu_op_r               = ALU_MV;
                alu_in_a_r             = pch_reg_w;
                alu_in_b_r             = 8'h0; // Don't care
                alu_in_c_r             = 1'b0; // Don't care
                dst_reg_addr_r         = 4'h0; // Don't care
                reg_wr_r               = 1'b0;
                cpu_wr_r               = |opcode_r; // (opcode_r != RST)
            end
            PUSH_PCL_DECREMENT_SP: begin
                alu_op_r               = ALU_MV;
                alu_in_a_r             = pcl_reg_w;
                alu_in_b_r             = 8'h0; // Don't care
                alu_in_c_r             = 1'b0; // Don't care
                dst_reg_addr_r         = 4'h0; // Don't care
                reg_wr_r               = 1'b0;
                cpu_wr_r               = |opcode_r; // (opcode_r != RST)
            end
            WRITE_REG_TO_EFADDR: begin
                alu_op_r               = ALU_MV;
                alu_in_b_r             = 8'h0; // Don't care
                alu_in_c_r             = 1'b0; // Don't care
                dst_reg_addr_r         = 4'h0; // Don't care
                reg_wr_r               = 1'b0;
                cpu_wr_r               = 1'b1;
                case (opcode_r)
                    STA:
                        alu_in_a_r     = ac_reg_w;
                    STX:
                        alu_in_a_r     = xi_reg_w;
                    STY:
                        alu_in_a_r     = yi_reg_w;
                    default:
                        alu_in_a_r     = ac_reg_w;
                endcase
            end
            PUSH_REG_DECREMENT_SP: begin
                alu_in_c_r             = 1'b0; // Don't care
                dst_reg_addr_r         = 4'h0; // Don't care
                reg_wr_r               = 1'b0;
                cpu_wr_r               = |opcode_r; // (opcode_r != RST)
                case (opcode_r)
                    INT, RST: begin
                        alu_op_r       = ALU_OR;
                        alu_in_a_r     = ps_reg_w;
                        alu_in_b_r     = 8'b00100000;
                    end
                    BRK, PHP: begin
                        alu_op_r       = ALU_OR;
                        alu_in_a_r     = ps_reg_w;
                        alu_in_b_r     = 8'b00110000;
                    end
                    PHA: begin
                        alu_op_r       = ALU_MV;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = 8'h0; // Don't care
                    end
                    default: begin
                        alu_op_r       = ALU_MV;
                        alu_in_a_r     = ac_reg_w;
                        alu_in_b_r     = 8'h0;
                    end
                endcase
            end
            PULL_REG: begin
                alu_in_a_r             = cpu_rd_data_i;
                alu_in_c_r             = 1'b0; // Don't care
                reg_wr_r               = 1'b1;
                cpu_wr_r               = 1'b0;
                case (opcode_r)
                    PLA: begin
                        alu_op_r       = ALU_MV;
                        alu_in_b_r     = 8'h0; // Don't care
                        dst_reg_addr_r = AC_REG_ADDR;
                    end
                    PLP: begin
                        alu_op_r       = ALU_AND;
                        alu_in_b_r     = 8'b11001111;
                        dst_reg_addr_r = PS_REG_ADDR;
                    end
                    default: begin
                        alu_op_r       = ALU_MV;
                        alu_in_b_r     = 8'h0;
                        dst_reg_addr_r = AC_REG_ADDR;
                    end
                endcase
            end
            PULL_PS_INCREMENT_SP: begin
                alu_op_r               = ALU_AND;
                alu_in_a_r             = cpu_rd_data_i;
                alu_in_b_r             = 8'b11001111;
                alu_in_c_r             = 1'b0; // Don't care
                dst_reg_addr_r         = PS_REG_ADDR;
                reg_wr_r               = 1'b1;
                cpu_wr_r               = 1'b0;
            end
            READ_FROM_ADDR_ADD_IND_ADDR: begin
                alu_op_r               = ALU_ADD;
                alu_in_a_r             = cpu_laddr_reg_w;
                alu_in_b_r             = index_reg_data_w;
                alu_in_c_r             = 1'b0; // Don't care
                dst_reg_addr_r         = CPU_LADDR_REG_ADDR;
                reg_wr_r               = 1'b1;
                cpu_wr_r               = 1'b0;
            end
            default: begin
                alu_op_r               = ALU_NOP;
                alu_in_a_r             = 8'h0; // Don't care
                alu_in_b_r             = 8'h0; // Don't care
                alu_in_c_r             = 1'b0; // Don't care
                dst_reg_addr_r         = 4'h0; // Don't care
                reg_wr_r               = 1'b0;
                cpu_wr_r               = 1'b0;
            end
        endcase

    assign index_reg_data_w = (use_x_reg_r) ? xi_reg_w : yi_reg_w;


    // Обновление буферных регистров адреса
    always @(*)
        case (state_next_r)
            FETCH_POINT_ADDR,
            FETCH_OPERAND, FETCH_LADDR,
            FETCH_POINT_LADDR,
            FETCH_LBADDR_TO_LATCH,
            FETCH_ZADDR, FETCH_EFLADDR:    cpu_laddr_reg_next_r = cpu_rd_data_i;

            default:                       cpu_laddr_reg_next_r = cpu_laddr_reg_w;
        endcase


    always @(*)
        case (state_next_r)

            FETCH_HADDR_ADD_IND_LADDR,
            FETCH_EFHADDR_ADD_IND_EFLADDR: cpu_haddr_reg_next_r = cpu_rd_data_i;

            FETCH_EFHADDR,
            FETCH_POINT_HADDR,
            FETCH_HADDR_JSR, FETCH_HADDR:  cpu_haddr_reg_next_r = cpu_rd_data_i;

            default:                       cpu_haddr_reg_next_r = cpu_haddr_reg_w;

        endcase


    // Вычисление нового значения счётчика инструкций и указателя стека
    assign pc_is_incred_fetch_op_w   = ~hw_interrupt_received_w;
    assign pc_is_incred_read_dummy_w = brk_received_r;
    assign pc_sp_reg_updater_w       = pc_sp_reg_r + pc_sp_upd_val_r;

    always @(*)
        case (state_next_r)

            FETCH_INSTR,
            FETCH_INSTR_WRITEBACK_REG: begin
                pc_sp_reg_r     = pc_reg_w;
                pc_sp_upd_val_r = {7'h0, pc_is_incred_fetch_op_w};
            end

            READ_DUMMY_BYTE_SP_IMP: begin
                pc_sp_reg_r     = pc_reg_w;
                pc_sp_upd_val_r = {7'h0, pc_is_incred_read_dummy_w};
            end

            CPU_RESET,
            FETCH_POINT_ADDR,
            FETCH_POINT_LADDR,
            FETCH_POINT_HADDR,
            FETCH_VAL, FETCH_ZADDR,
            FETCH_HADDR, FETCH_LADDR,
            FETCH_HADDR_ADD_IND_LADDR,
            FETCH_OPERAND, INCREMENT_PC: begin
                pc_sp_reg_r     = pc_reg_w;
                pc_sp_upd_val_r = 8'h1;
            end

            PUSH_PCH_DECREMENT_SP,
            PUSH_PCL_DECREMENT_SP,
            PUSH_REG_DECREMENT_SP: begin
                pc_sp_reg_r     = {8'h0, sp_reg_w};
                pc_sp_upd_val_r = 8'hFF;
            end

            INCREMENT_SP,
            PULL_PS_INCREMENT_SP,
            PULL_PCL_INCREMENT_SP: begin
                pc_sp_reg_r     = {8'h0, sp_reg_w};
                pc_sp_upd_val_r = 8'h1;
            end

            default: begin
                pc_sp_reg_r     = pc_reg_w;
                pc_sp_upd_val_r = 8'h1;
            end

        endcase


    // Обновление счётчика инструкций
    always @(*)
        case (state_next_r)

            FETCH_INSTR,
            FETCH_INSTR_WRITEBACK_REG:    pc_reg_next_r = pc_sp_reg_updater_w;

            READ_DUMMY_BYTE_SP_IMP:       pc_reg_next_r = pc_sp_reg_updater_w;

            CPU_RESET,
            FETCH_POINT_ADDR,
            FETCH_POINT_LADDR,
            FETCH_POINT_HADDR,
            FETCH_VAL, FETCH_ZADDR,
            FETCH_HADDR, FETCH_LADDR,
            FETCH_HADDR_ADD_IND_LADDR,
            FETCH_OPERAND, INCREMENT_PC:  pc_reg_next_r = pc_sp_reg_updater_w;

            PULL_PCL_INCREMENT_SP,
            FETCH_PCL_INTERRUPT_RESET:    pc_reg_next_r = {pch_reg_w, cpu_rd_data_i};

            PULL_PCH,
            FETCH_PCH_INTERRUPT_RESET:    pc_reg_next_r = {cpu_rd_data_i, pcl_reg_w};

            COPY_TO_PCL_FETCH_TO_PCH_ABS,
            COPY_TO_PCL_FETCH_TO_PCH_IND: pc_reg_next_r = {cpu_rd_data_i, cpu_laddr_reg_w};

            default:                      pc_reg_next_r = pc_reg_w;

        endcase


    // Обновление указателя стека
    always @(*)
        case (state_next_r)

            PUSH_PCH_DECREMENT_SP,
            PUSH_PCL_DECREMENT_SP,
            PUSH_REG_DECREMENT_SP:        sp_reg_next_r = pc_sp_reg_updater_w;

            INCREMENT_SP,
            PULL_PS_INCREMENT_SP,
            PULL_PCL_INCREMENT_SP:        sp_reg_next_r = pc_sp_reg_updater_w;

            default:                      sp_reg_next_r = sp_reg_w;

        endcase


    // Обновление флагов процессора в зависимости от результатов операции на АЛУ
    always @(*)                           ps_reg_next_r = {n_status_bit_next_r, v_status_bit_next_r, u_status_bit_next_r,
                                                           b_status_bit_next_r, d_status_bit_next_r, i_status_bit_next_r,
                                                           z_status_bit_next_r, c_status_bit_next_r};


    always @(*)
        case (state_next_r)

            FETCH_INSTR_WRITEBACK_REG:
                case (opcode_r)
                    BIT:                  n_status_bit_next_r = alu_in_b_r[7];
                    default:              n_status_bit_next_r = alu_result_r[7];
                endcase

            PULL_REG,
            WRITE_NEW_VALUE:              n_status_bit_next_r = alu_result_r[7];

            READ_DUMMY_BYTE_ACC_IMP:
                case (opcode_r)
                    ASL, DEX, DEY,
                    INX, INY, LSR,
                    ROL, ROR, TAX,
                    TAY, TSX, TXA, TYA:   n_status_bit_next_r = alu_result_r[7];
                    default:              n_status_bit_next_r = n_status_bit_w;
                endcase

            default:                      n_status_bit_next_r = n_status_bit_w;

        endcase


    always @(*)
        case (state_next_r)

            WRITE_NEW_VALUE:
                case (opcode_r)
                    INC, DEC:             c_status_bit_next_r = c_status_bit_w;
                    default:              c_status_bit_next_r = alu_carry_r;
                endcase

            FETCH_INSTR_WRITEBACK_REG:
                case (opcode_r)
                    SBC:                  c_status_bit_next_r = alu_carry_r;
                    default:              c_status_bit_next_r = alu_carry_r;
                endcase

            READ_DUMMY_BYTE_ACC_IMP:
                case (opcode_r)
                    INX, INY,
                    DEX, DEY,
                    CLD, CLI, CLV,
                    NOP, SED, SEI:        c_status_bit_next_r = c_status_bit_w;
                    SEC:                  c_status_bit_next_r = 1'b1;
                    CLC:                  c_status_bit_next_r = 1'b0;
                    default:              c_status_bit_next_r = alu_carry_r;
                endcase

            default:                      c_status_bit_next_r = c_status_bit_w;

        endcase


    always @(*)
        case (state_next_r)

            WRITE_NEW_VALUE,
            FETCH_INSTR_WRITEBACK_REG:    z_status_bit_next_r = ~|alu_result_r;

            READ_DUMMY_BYTE_ACC_IMP:
                case (opcode_r)
                    ASL, DEX, DEY,
                    INX, INY, LSR,
                    ROL, ROR, TAX,
                    TAY, TSX, TXA,
                    TYA:                  z_status_bit_next_r = ~|alu_result_r;
                    default:              z_status_bit_next_r = z_status_bit_w;
                endcase

            PULL_REG:
                case (opcode_r)
                    PLA:                  z_status_bit_next_r = ~|alu_result_r;
                    PLP:                  z_status_bit_next_r = z_status_bit_w;
                    default:              z_status_bit_next_r = ~|alu_result_r;
                endcase

            default:                      z_status_bit_next_r = z_status_bit_w;

        endcase


    always @(*)
        case (state_next_r)

            FETCH_INSTR_WRITEBACK_REG:
                case (opcode_r)
                    ADC:                  v_status_bit_next_r = ( alu_in_a_r[7] &  alu_in_b_r[7] & ~alu_result_r[7]) ||
                                                                (~alu_in_a_r[7] & ~alu_in_b_r[7] &  alu_result_r[7]);
                    SBC:                  v_status_bit_next_r = ( alu_in_a_r[7] ^ alu_result_r[7]) &&
                                                                ( alu_in_b_r[7] ^ alu_result_r[7]);
                    BIT:                  v_status_bit_next_r = alu_in_b_r[6];
                    default:              v_status_bit_next_r = v_status_bit_w;
                endcase

            READ_DUMMY_BYTE_ACC_IMP:
                case (opcode_r)
                    CLV:                  v_status_bit_next_r = 1'b0;
                    default:              v_status_bit_next_r = v_status_bit_w;
                endcase

            default:                      v_status_bit_next_r = v_status_bit_w;

        endcase


    always @(*)
        case (state_next_r)

            READ_DUMMY_BYTE_ACC_IMP:
                case (opcode_r)
                    SEI:                  i_status_bit_next_r = 1'b1;
                    CLI:                  i_status_bit_next_r = 1'b0;
                    default:              i_status_bit_next_r = i_status_bit_w;
                endcase

            FETCH_PCL_INTERRUPT_RESET:    i_status_bit_next_r = 1'b1;

            default:                      i_status_bit_next_r = i_status_bit_w;

        endcase


    always @(*)                           b_status_bit_next_r = b_status_bit_w;


    always @(*)                           u_status_bit_next_r = u_status_bit_w;


    always @(*)
        case (state_next_r)

            READ_DUMMY_BYTE_ACC_IMP:
                case (opcode_r)
                    SED:                  d_status_bit_next_r = 1'b1;
                    CLD:                  d_status_bit_next_r = 1'b0;
                    default:              d_status_bit_next_r = d_status_bit_w;
                endcase

            default:                      d_status_bit_next_r = d_status_bit_w;

        endcase


    always @(posedge clk_i)
        if (~halt_i) begin
            fixing_pch_r   <= fixing_pch_next_w;
            fixing_haddr_r <= fixing_haddr_next_r;
        end

    assign fixing_pch_rel_w       = add_operand_to_pcl_ns_w;            // Relative addressing
    assign fixing_pch_indy_w      = fetch_efhaddr_add_ind_efladdr_ns_w; // Indirect indexed addressing
    assign fixing_pch_absx_absy_w = fetch_haddr_add_ind_laddr_ns_w;     // Absolute indexed addressing
    assign fixing_pch_indexed_w   = fixing_pch_indy_w || fixing_pch_absx_absy_w;

    assign fixing_pch_rel_cond_w  = (~alu_in_a_r[7] &  alu_in_b_r[7] &  alu_result_r[7]) ||
                                    ( alu_in_a_r[7] & ~alu_in_b_r[7] & ~alu_result_r[7]);

    assign fixing_pch_next_w      = (fixing_pch_rel_w) ? alu_in_b_r[7] : 1'b0;

    wire [1:0] fixing_haddr_next_case_w = {fixing_pch_rel_w, fixing_pch_indexed_w};
    always @(*)
        case (fixing_haddr_next_case_w) // one hot
            2'b10:   fixing_haddr_next_r = fixing_pch_rel_cond_w;
            2'b01:   fixing_haddr_next_r = alu_carry_r;
            default: fixing_haddr_next_r = 1'b0;
        endcase


    // Логика АЛУ
    always @(*)
        case (alu_op_r)

            ALU_ADD: {alu_carry_r, alu_result_r} = (alu_in_a_r + alu_in_b_r + alu_in_c_r);

            ALU_AND: {alu_carry_r, alu_result_r} = {alu_in_c_r, alu_in_a_r & alu_in_b_r};

            ALU_OR:  {alu_carry_r, alu_result_r} = {alu_in_c_r, alu_in_a_r | alu_in_b_r};

            ALU_XOR: {alu_carry_r, alu_result_r} = {alu_in_c_r, alu_in_a_r ^ alu_in_b_r};

            ALU_MV:  {alu_carry_r, alu_result_r} = {alu_in_c_r, alu_in_a_r};

            ALU_SL:  {alu_carry_r, alu_result_r} = {alu_in_a_r, alu_in_c_r};

            ALU_SR:  {alu_carry_r, alu_result_r} = {alu_in_a_r[0], alu_in_c_r, alu_in_a_r[7:1]};

            ALU_NOP: {alu_carry_r, alu_result_r} = {alu_buffer_r};

        endcase

    always @(posedge clk_i)
        if (~halt_i) alu_buffer_r <= {alu_carry_r, alu_result_r};

    assign cpu_wr_data_w = alu_result_r;
    assign reg_wr_data_w = alu_result_r;


    // Логика регистрового файла
    generate
        for (genvar i = 0; i < 9; i = i + 1) begin: register_file

            always @(posedge clk_i)
                if      (rst_i  ) register_r[i] <= register_reset_w[i];
                else if (~halt_i) register_r[i] <= register_next_w [i];

            assign reg_sel_w[i] = reg_wr_r && (dst_reg_addr_r == i);

            case (i)

                SP_REG_ADDR : begin // Stack Pointer
                    assign register_reset_w[i] = 8'h00; // 8'hFD - after reset sequence
                    assign register_next_w [i] = (reg_sel_w[i]) ? reg_wr_data_w : sp_reg_next_r;
                end

                PS_REG_ADDR : begin // Process Status
                    assign register_reset_w[i] = 8'h04; // I flag is set
                    assign register_next_w [i] = (reg_sel_w[i]) ? reg_wr_data_w : ps_reg_next_r;
                end

                PCL_REG_ADDR : begin // PCL Register
                    assign register_reset_w[i] = 8'hFC;
                    assign register_next_w [i] = (reg_sel_w[i]) ? reg_wr_data_w : pc_reg_next_r[ 7:0];
                end

                PCH_REG_ADDR : begin // PCH Register
                    assign register_reset_w[i] = 8'hFF;
                    assign register_next_w [i] = (reg_sel_w[i]) ? reg_wr_data_w : pc_reg_next_r[15:8];
                end

                CPU_LADDR_REG_ADDR : begin // CPU LB Address Register
                    assign register_reset_w[i] = 8'h00;
                    assign register_next_w [i] = (reg_sel_w[i]) ? reg_wr_data_w : cpu_laddr_reg_next_r;
                end

                CPU_HADDR_REG_ADDR : begin // CPU HB Address Register
                    assign register_reset_w[i] = 8'h00;
                    assign register_next_w [i] = (reg_sel_w[i]) ? reg_wr_data_w : cpu_haddr_reg_next_r;
                end

                default : begin // Accumulator, X Index, Y Index
                    assign register_reset_w[i] = 8'h00;
                    assign register_next_w [i] = (reg_sel_w[i]) ? reg_wr_data_w : register_r[i];
                end

            endcase

        end
    endgenerate

    assign ac_reg_w        = register_r[AC_REG_ADDR];
    assign xi_reg_w        = register_r[XI_REG_ADDR];
    assign yi_reg_w        = register_r[YI_REG_ADDR];
    assign sp_reg_w        = register_r[SP_REG_ADDR];
    assign ps_reg_w        = register_r[PS_REG_ADDR];
    assign cpu_laddr_reg_w = register_r[CPU_LADDR_REG_ADDR];
    assign cpu_haddr_reg_w = register_r[CPU_HADDR_REG_ADDR];
    assign n_status_bit_w  = register_r[PS_REG_ADDR][7];
    assign v_status_bit_w  = register_r[PS_REG_ADDR][6];
    assign u_status_bit_w  = register_r[PS_REG_ADDR][5];
    assign b_status_bit_w  = register_r[PS_REG_ADDR][4];
    assign d_status_bit_w  = register_r[PS_REG_ADDR][3];
    assign i_status_bit_w  = register_r[PS_REG_ADDR][2];
    assign z_status_bit_w  = register_r[PS_REG_ADDR][1];
    assign c_status_bit_w  = register_r[PS_REG_ADDR][0];
    assign pcl_reg_w       = register_r[PCL_REG_ADDR];
    assign pch_reg_w       = register_r[PCH_REG_ADDR];
    assign pc_reg_w        = {pch_reg_w, pcl_reg_w};


    // Логика управления адресом на процессорной шине
    always @(*)
        case (state_next_r)
            DO_OPERATION, WRITE_REG_TO_EFADDR,
            READ_FROM_EFADDR_R, READ_FROM_EFADDR_M,
            READ_FROM_EFADDR_FIX_EFHADDR, WRITE_NEW_VALUE,
            FETCH_LBADDR_TO_LATCH, READ_FROM_ADDR_ADD_IND_ADDR: begin
                use_aux_src_r  = 1'b1;
                use_pc_r       = 1'b0;
                use_sp_r       = 1'b0;
                use_iv_src_r   = 1'b0;
                use_zp_ptr_r   = 1'b0;
                use_ptr_incr_r = 1'b0;
            end
            COPY_TO_PCL_FETCH_TO_PCH_ABS,
            FETCH_POINT_HADDR, FETCH_VAL,
            FETCH_POINT_ADDR, FETCH_POINT_LADDR,
            FETCH_LADDR, FETCH_HADDR, FETCH_ZADDR,
            FETCH_INSTR, FETCH_INSTR_WRITEBACK_REG,
            FETCH_OPERAND, FETCH_HADDR_ADD_IND_LADDR,
            READ_DUMMY_BYTE_ACC_IMP, READ_DUMMY_BYTE_SP_IMP: begin
                use_aux_src_r  = 1'b0;
                use_pc_r       = 1'b1;
                use_sp_r       = 1'b0;
                use_iv_src_r   = 1'b0;
                use_zp_ptr_r   = 1'b0;
                use_ptr_incr_r = 1'b0;
            end
            PULL_REG, PULL_PCH,
            PUSH_REG_DECREMENT_SP, INCREMENT_SP,
            PULL_PS_INCREMENT_SP, PULL_PCL_INCREMENT_SP,
            PUSH_PCH_DECREMENT_SP, PUSH_PCL_DECREMENT_SP: begin
                use_aux_src_r  = 1'b0;
                use_pc_r       = 1'b0;
                use_sp_r       = 1'b1;
                use_iv_src_r   = 1'b0;
                use_zp_ptr_r   = 1'b0;
                use_ptr_incr_r = 1'b0;
            end
            FETCH_PCL_INTERRUPT_RESET: begin
                use_aux_src_r  = 1'b0;
                use_pc_r       = 1'b0;
                use_sp_r       = 1'b0;
                use_iv_src_r   = 1'b1;
                use_zp_ptr_r   = 1'b0;
                use_ptr_incr_r = 1'b0;
            end
            FETCH_EFLADDR: begin
                use_aux_src_r  = 1'b0;
                use_pc_r       = 1'b0;
                use_sp_r       = 1'b0;
                use_iv_src_r   = 1'b0;
                use_zp_ptr_r   = 1'b1;
                use_ptr_incr_r = 1'b0;
            end
            FETCH_EFHADDR,
            FETCH_PCH_INTERRUPT_RESET,
            COPY_TO_PCL_FETCH_TO_PCH_IND,
            FETCH_EFHADDR_ADD_IND_EFLADDR: begin
                use_aux_src_r  = 1'b0;
                use_pc_r       = 1'b0;
                use_sp_r       = 1'b0;
                use_iv_src_r   = 1'b0;
                use_zp_ptr_r   = 1'b0;
                use_ptr_incr_r = 1'b1;
            end
            default: begin
                use_aux_src_r  = 1'b0;
                use_pc_r       = 1'b0;
                use_sp_r       = 1'b0;
                use_iv_src_r   = 1'b0;
                use_zp_ptr_r   = 1'b0;
                use_ptr_incr_r = 1'b0;
            end
        endcase

    assign use_rst_vector_w = use_iv_src_r  &&  rst_vector_w;
    assign use_nmi_vector_w = use_iv_src_r  &&  nmi_vector_w;
    assign use_irq_vector_w = use_iv_src_r  &&  irq_vector_w;
    assign use_zp_mode_w    = use_aux_src_r &&  zero_page_mode_r;
    assign use_eff_addr_w   = use_aux_src_r && ~zero_page_mode_r;
    assign use_zp_addr_w    = use_zp_mode_w ||  use_zp_ptr_r;

    wire [7:0] cpu_addr_case_w = {use_pc_r, use_sp_r, use_rst_vector_w, use_nmi_vector_w, use_irq_vector_w,
                                  use_zp_addr_w, use_eff_addr_w, use_ptr_incr_r};
    always @(*)
        case (cpu_addr_case_w) // one hot
            8'b10000000: cpu_addr_r = {pc_reg_w};
            8'b01000000: cpu_addr_r = {8'h01, sp_reg_w};
            8'b00100000: cpu_addr_r = {8'hFF, 8'hFC};
            8'b00010000: cpu_addr_r = {8'hFF, 8'hFA};
            8'b00001000: cpu_addr_r = {8'hFF, 8'hFE};
            8'b00000100: cpu_addr_r = {8'h00, cpu_laddr_reg_w};
            8'b00000010: cpu_addr_r = {cpu_haddr_reg_w, cpu_laddr_reg_w};
            8'b00000001: cpu_addr_r = {cpu_addr_buffer_r[15:8], {cpu_addr_buffer_r[7:0] + 1'b1}};
            default:     cpu_addr_r = {cpu_addr_buffer_r};
        endcase

    always @(posedge clk_i)
        if (~halt_i) begin
            cpu_addr_buffer_r    <= cpu_addr_r;
            cpu_rd_data_buffer_r <= cpu_rd_data_i;
        end


    //Выходы
    assign cpu_addr_o        = cpu_addr_r;
    assign cpu_wr_o          = cpu_wr_r;
    assign cpu_wr_data_o     = cpu_wr_data_w;

    assign new_instruction_o = new_instruction_w;
    assign state_invalid_o   = invalid_state_ns_w;


endmodule
