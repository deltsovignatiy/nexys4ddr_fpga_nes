
/*
 * Description : Test bench module of nexys4ddr_fpga_nes
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


`timescale 1ps/1ps


module nexys4ddr_fpga_nes_tb;


    parameter CLOCK_FREQUENCY_MHZ = 100;
    parameter UART_BAUDRATE       = 115200;
    parameter DATA_FILE           = "../../../../../nestest/nestest.nes";
    // Путь относительно директории "nexys4ddr_fpga_nes_xpr/nexys4ddr_fpga_nes.sim/sim_1/behav/xsim/"


    localparam CLOCK_PERIOD_PS = (10**6) / CLOCK_FREQUENCY_MHZ;
    localparam BIT_PERIOD_PS   = (10**9) / UART_BAUDRATE * (10**3);
    localparam PS2_TCK_PS      = 30 * (10**6);
    localparam PS2_TSU_PS      = 5  * (10**6);
    localparam PS2_THLD_PS     = 25 * (10**6);


    reg            sys_100mhz_clk_r;
    reg     [ 3:0] sw_r;
    reg            cpu_resetn_r;
    reg            uart_txd_r;
    wire    [15:0] led_w;

    wire           vga_hsync_w;
    wire           vga_vsync_w;
    wire    [ 3:0] vga_red_w;
    wire    [ 3:0] vga_green_w;
    wire    [ 3:0] vga_blue_w;

    reg            ps2_clk_r;
    reg            ps2_data_r;

    wire           sd_disable_w;
    reg            sd_ncd_r;
    wire           sd_spi_clk_w;
    wire           sd_spi_mosi_w;
    reg            sd_spi_miso_r;
    wire           sd_spi_ncs_w;

    wire           aud_sd_w;
    wire           aud_pwm_w;

    wire    [12:0] ddr2_addr_w;
    wire    [ 2:0] ddr2_ba_w;
    wire           ddr2_ras_n_w;
    wire           ddr2_cas_n_w;
    wire           ddr2_we_n_w;
    wire    [ 0:0] ddr2_ck_p_w;
    wire    [ 0:0] ddr2_ck_n_w;
    wire    [ 0:0] ddr2_cke_w;
    wire    [ 0:0] ddr2_cs_n_w;
    wire    [ 1:0] ddr2_dm_w;
    wire    [ 0:0] ddr2_odt_w;
    wire    [15:0] ddr2_dq_w;
    wire    [ 1:0] ddr2_dqs_n_w;
    wire    [ 1:0] ddr2_dqs_p_w;

    reg     [63:0] cpu_cycles_r;

    reg            st_prepare_cmd17_r;
    reg            st_power_off_r;

    integer        fd;


    nexys4ddr_fpga_nes_top
        uut
        (
            .sys_100mhz_clk_i(sys_100mhz_clk_r),
            .sw_i            (sw_r            ),
            .cpu_resetn_i    (cpu_resetn_r    ),
            .ps2_clk_i       (ps2_clk_r       ),
            .ps2_data_i      (ps2_data_r      ),
            .uart_txd_i      (uart_txd_r      ),
            .led_o           (led_w           ),
            .vga_red_o       (vga_red_w       ),
            .vga_green_o     (vga_green_w     ),
            .vga_blue_o      (vga_blue_w      ),
            .vga_hsync_o     (vga_hsync_w     ),
            .vga_vsync_o     (vga_vsync_w     ),

            .sd_disable_o    (sd_disable_w    ),
            .sd_ncd_i        (sd_ncd_r        ),
            .sd_spi_clk_o    (sd_spi_clk_w    ),
            .sd_spi_mosi_o   (sd_spi_mosi_w   ),
            .sd_spi_miso_i   (sd_spi_miso_r   ),
            .sd_spi_ncs_o    (sd_spi_ncs_w    ),

            .aud_sd_o        (aud_sd_w        ),
            .aud_pwm_o       (aud_pwm_w       ),

            .ddr2_addr       (ddr2_addr_w     ),
            .ddr2_ba         (ddr2_ba_w       ),
            .ddr2_cas_n      (ddr2_cas_n_w    ),
            .ddr2_ck_n       (ddr2_ck_n_w     ),
            .ddr2_ck_p       (ddr2_ck_p_w     ),
            .ddr2_cke        (ddr2_cke_w      ),
            .ddr2_ras_n      (ddr2_ras_n_w    ),
            .ddr2_we_n       (ddr2_we_n_w     ),
            .ddr2_dq         (ddr2_dq_w       ),
            .ddr2_dqs_n      (ddr2_dqs_n_w    ),
            .ddr2_dqs_p      (ddr2_dqs_p_w    ),
            .ddr2_cs_n       (ddr2_cs_n_w     ),
            .ddr2_dm         (ddr2_dm_w       ),
            .ddr2_odt        (ddr2_odt_w      )
        );


    ddr2_model
        ddr2_model
        (
            .ck              (ddr2_ck_p_w     ),
            .ck_n            (ddr2_ck_n_w     ),
            .cke             (ddr2_cke_w      ),
            .cs_n            (ddr2_cs_n_w     ),
            .ras_n           (ddr2_ras_n_w    ),
            .cas_n           (ddr2_cas_n_w    ),
            .we_n            (ddr2_we_n_w     ),
            .dm_rdqs         (ddr2_dm_w       ),
            .ba              (ddr2_ba_w       ),
            .addr            (ddr2_addr_w     ),
            .dq              (ddr2_dq_w       ),
            .dqs             (ddr2_dqs_p_w    ),
            .dqs_n           (ddr2_dqs_n_w    ),
            .rdqs_n          (                ),
            .odt             (ddr2_odt_w      )
        );


    always #(CLOCK_PERIOD_PS / 2)
        sys_100mhz_clk_r <= ~sys_100mhz_clk_r;


    always @(posedge uut.cpu_clk_w)
        cpu_cycles_r <= cpu_cycles_r + 1;


    always @(negedge uut.sd_adjust_clk_w)
        st_prepare_cmd17_r <= (uut.cartridge.nes_boot_controller.sd_card_controller.state_r ==
                               uut.cartridge.nes_boot_controller.sd_card_controller.PREPARE_CMD17);

    always @(negedge uut.sd_adjust_clk_w)
        st_power_off_r     <= (uut.cartridge.nes_boot_controller.sd_card_controller.state_r ==
                               uut.cartridge.nes_boot_controller.sd_card_controller.POWER_OFF);


    // CPU RAM Zero Page
    wire [7:0] DBG_cpu_ram_zero_page_w [255:0];
    generate

        for (genvar i = 0; i < 256; i = i + 1) begin
            assign DBG_cpu_ram_zero_page_w[i][7:0] = uut.cpu.cpu_ram.ram_r[i][7:0];
        end

    endgenerate


    initial begin

        $timeformat(-6, 3, " us", 7);

        fd = $fopen(DATA_FILE, "rb");
        if (fd) begin
            $display("NES data file %s was opened successfully [%0t]", DATA_FILE, $realtime);
        end else begin
            $display("NES data file %s was not found [%0t]", DATA_FILE, $realtime);
            $finish;
        end

        st_prepare_cmd17_r <= 1'b0;
        st_power_off_r     <= 1'b0;
        cpu_cycles_r       <= 64'd0;
        sys_100mhz_clk_r   <= 1'b0;
        sw_r               <= 4'b0000;
        cpu_resetn_r       <= 1'b0;
        uart_txd_r         <= 1'b1;
        ps2_data_r         <= 1'b1;
        ps2_clk_r          <= 1'b1;
        sd_spi_miso_r      <= 1'b1;
        sd_ncd_r           <= 1'b1;

        #(CLOCK_PERIOD_PS * 1000);
        sw_r               <= 4'b0011;
        cpu_resetn_r       <= 1'b1;
        sd_ncd_r           <= 1'b0;

        sdspi_send_response_task( 8'h01,         1);
        sdspi_send_response_task(40'h01000001AA, 5);
        sdspi_send_response_task( 8'h01,         1);
        sdspi_send_response_task(40'h0140380000, 5);
        sdspi_send_response_task( 8'h01,         1);
        sdspi_send_response_task( 8'h00,         1);
        sdspi_send_response_task(40'h00C0380000, 5);

        while (~st_power_off_r) begin

            wait (st_prepare_cmd17_r || st_power_off_r);

            if (st_power_off_r) begin
                $display("SD state POWER_OFF is reached [%0t]", $realtime);
            end else if (st_prepare_cmd17_r) begin
                sdspi_send_response_task(8'h00, 1);
                sdspi_send_data_task(fd);
            end

        end

        $fclose(fd);

        repeat (2000) begin
            #(CLOCK_PERIOD_PS * 100000000);
        end

        fork
            begin
                ps2_transmit_byte_task(8'h5A);
                ps2_transmit_byte_task(8'hF0);
                ps2_transmit_byte_task(8'h5A);
                ps2_transmit_byte_task(8'h5A);
            end
            begin
                uart_transmit_byte_task(8'h55);
                uart_transmit_byte_task(8'hAA);
                uart_transmit_byte_task(8'h08);
                uart_transmit_byte_task(8'h08);
            end
        join

        repeat (2000) begin
            #(CLOCK_PERIOD_PS * 100000000);
        end

        $stop;

    end


    task sdspi_send_byte_task(input [7:0] byte);
        integer i;
        begin

            for (i = 8; i > 0; i = i - 1) begin
                @(negedge sd_spi_clk_w);
                sd_spi_miso_r <= byte[i-1];
                $display("Bit %01d - 0b%1b is sent [%0t]", i-1, byte[i-1], $realtime);
            end

        end
    endtask // sdspi_send_byte_task


    task sdspi_send_response_task(input [39:0] response, input integer size_in_bytes);
        integer        i;
        reg     [47:0] cmd_data;
        reg     [ 7:0] byte;
        begin

            wait (uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.state_r ==
                  uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.RECEIVING_RESPONSE);
            $display("SDSPI state RECEIVING_RESPONSE is reached [%0t]", $realtime);
            cmd_data = uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.sd_cmd_data_i;
            $display("Input sdspi cmd data is 0x_%02h_%02h_%02h_%02h_%02h_%02h", cmd_data[47:40], cmd_data[39:32],
                     cmd_data[31:24], cmd_data[23:16], cmd_data[15:8], cmd_data[7:0]);
            $display("Expecting response type is R%01d",
                     uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.sd_response_type_i);

            repeat (7) begin
                @(negedge sd_spi_clk_w);
            end

            $display("Sending response 0x_%02h_%02h_%02h_%02h_%02h [%0t]", response[39:32], response[31:24],
                     response[23:16], response[15:8], response[7:0], $realtime);
            for (i = size_in_bytes; i > 0; i = i - 1) begin
                byte = response[(i * 8 - 1) -: 8];
                sdspi_send_byte_task(byte);
                $display("Response byte %01d - 0x%02h is sent [%0t]", i, byte, $realtime);
            end

            @(negedge sd_spi_clk_w);
            sd_spi_miso_r <= 1'b1;
            $display("Response is sent [%0t]", $realtime);

            wait (uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.state_r ==
                  uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.CHECK_RESPONSE);
            $display("SDSPI state CHECK_RESPONSE is reached [%0t]", $realtime);

        end
    endtask // sdspi_send_response_task


    task sdspi_send_data_task(input integer fd);
        reg     [7:0] token;
        reg     [7:0] crc [1:0];
        reg     [7:0] data_byte;
        integer       i;
        integer       f_tmp;
        begin

            wait (uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.state_r ==
                  uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.RECEIVING_TOKEN);
            $display("SDSPI state RECEIVING_TOKEN is reached [%0t]", $realtime);

            repeat (6) begin
                @(negedge sd_spi_clk_w);
            end

            token = 8'hFE;
            $display("Sending start token 0x_%02h [%0t]", token, $realtime);
            sdspi_send_byte_task(token);
            $display("Start token byte is sent [%0t]", $realtime);

            $display("Sending data [%0t]", $realtime);
            for (i = 0; i < 512; i = i + 1) begin
                f_tmp = $fread(data_byte, fd);
                sdspi_send_byte_task(data_byte);
                $display("Data byte %03d - 0x%02h is sent [%0t]", i, data_byte, $realtime);
            end

            wait (uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.data_crc_calculated_w);
            crc[0] = uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.crc_16_out_word_w[15:8];
            crc[1] = uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.crc_16_out_word_w[ 7:0];
            $display("Sending crc 0x_%02h_%02h [%0t]", crc[0], crc[1], $realtime);
            sdspi_send_byte_task(crc[0]);
            $display("First crc byte is sent [%0t]", $realtime);
            sdspi_send_byte_task(crc[1]);
            $display("Second crc byte is sent [%0t]", $realtime);

            @(negedge sd_spi_clk_w);
            sd_spi_miso_r <= 1'b1;
            $display("Data is sent");

            wait (uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.state_r ==
                  uut.cartridge.nes_boot_controller.sd_card_controller.sdspi_controller.STOP_TRANSFERRING);
            $display("SDSPI state STOP_TRANSFERRING is reached [%0t]", $realtime);

        end
    endtask // sdspi_send_data_task


    task ps2_transmit_bit_task(input bit);
        begin

            ps2_data_r <= bit;

            #(PS2_TSU_PS);

            ps2_clk_r  <= 1'b0;

            #(PS2_THLD_PS);
            #(PS2_TCK_PS - PS2_THLD_PS);

            ps2_clk_r  <= 1'b1;

            #(PS2_TCK_PS - PS2_TSU_PS);

        end
    endtask // ps2_transmit_bit_task


    task ps2_transmit_byte_task(input [7:0] byte);
        integer i;
        begin

            // Send Start Bit
            ps2_transmit_bit_task(1'b0);

            // Send Data Byte
            for (i = 0; i < 8; i = i + 1) begin
                ps2_transmit_bit_task(byte[i]);
            end

            // Send Odd Parity Bit
            ps2_transmit_bit_task(~^byte);

            // Send Stop Bit
            ps2_transmit_bit_task(1'b1);

        end
    endtask // ps2_transmit_byte_task


    task uart_transmit_byte_task(input [7:0] byte);
        integer i;
        begin

            // Send Start Bit
            uart_txd_r <= 1'b0;
            #(BIT_PERIOD_PS);

            // Send Data Byte
            for (i = 0; i < 8; i = i + 1) begin
                uart_txd_r <= byte[i];
                #(BIT_PERIOD_PS);
            end

            // Send Stop Bit
            uart_txd_r <= 1'b1;
            #(BIT_PERIOD_PS);

        end
     endtask // uart_transmit_byte_task


endmodule
