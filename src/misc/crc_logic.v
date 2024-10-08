
/*
 * Description : CRC generation logic module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module crc_logic
    #(
        parameter WIDTH            = 16,          // Ширина сдвигового регистра
        parameter NORMAL_REPRESENT = 16'h1021,    /* Нормальное представление полинома — генератора CRC,
                                                   * CRC-16-CCITT == 0x1021, CRC-7 == 0x9 */
        parameter INITIAL_VALUE    = 16'h0        // Начальное значение триггеров в сдвиговом регистре
    )
    (
        input  wire             clk_i,            // Сигнал тактирования
        input  wire             rst_i,            // Сигнал сброса

        input  wire             data_bit_i,       // Входной бит данных
        input  wire             data_bit_valid_i, // Сигнал валидности бита даных
        input  wire             shift_bit_out_i,  // Сигнал "выталкивания" данных из регистра в обход обратной связи
        output wire [WIDTH-1:0] crc_word_o,       // Выходное слово CRC
        output wire             crc_bit_o         // Выходной бит CRC
    );


    localparam          WD = WIDTH;
    localparam [WD-1:0] IV = INITIAL_VALUE;


    reg  [WD-1:0] lfsr_r;
    reg  [WD-1:0] lfsr_next_r;
    wire [   1:0] lfsr_case_w;


    always @(posedge clk_i)
        if (rst_i) begin
            lfsr_r <= IV;
        end else begin
            lfsr_r <= lfsr_next_r;
        end

    assign lfsr_case_w = {data_bit_valid_i, shift_bit_out_i};


    generate

        always @(*)
            case (lfsr_case_w)
                2'b10:   lfsr_next_r[0] = data_bit_i ^ lfsr_r[WD-1];
                2'b11:   lfsr_next_r[0] = data_bit_i;
                default: lfsr_next_r[0] = lfsr_r[0];
            endcase

        for (genvar i = 1; i < WD; i = i + 1) begin: crc

            if ((1'b1 << i) & NORMAL_REPRESENT) begin

                always @(*)
                    case (lfsr_case_w)
                        2'b10:   lfsr_next_r[i] = lfsr_r[i-1] ^ lfsr_next_r[0];
                        2'b11:   lfsr_next_r[i] = lfsr_r[i-1];
                        default: lfsr_next_r[i] = lfsr_r[i];
                    endcase

            end else begin

                always @(*) lfsr_next_r[i] = (data_bit_valid_i) ? lfsr_r[i-1] : lfsr_r[i];

            end

        end

    endgenerate


    assign crc_word_o = lfsr_r;
    assign crc_bit_o  = lfsr_r[WD-1];


endmodule
