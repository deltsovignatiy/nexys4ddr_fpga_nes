
/*
 * Description : Digital to analog converter module based on delta-sigma modulation
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


module dsm_dac
    #(
        parameter DATA_WIDTH = 16,            // Разрядность входного сэмпла
        parameter DSM_ORDER  = 1              // Порядок (стадии) ЦАП, может быть 1 или 2
    )
    (
        input  wire                  clk_i,   // Сигнал тактирования
        input  wire                  rst_i,   // Сигнал сброса

        input  wire [DATA_WIDTH-1:0] input_i, // Входной сэмпл
        output wire                  output_o // Выход ЦАП
    );


    localparam DW = DATA_WIDTH;
    localparam EW = 3;
    localparam TW = DW + EW;


    wire [TW-1:0] din_w;
    reg           output_r;
    wire          output_next_w;

    reg  [TW-1:0] latch1_r;
    wire [DW-1:0] q_base_w;
    wire [TW-1:0] q1_w;
    wire [TW-1:0] deltasigma1_w;
    wire          msb1_w;


    always @(posedge clk_i or posedge rst_i)
        if   (rst_i) output_r <= 1'b0;
        else         output_r <= output_next_w;

    always @(posedge clk_i)
        if   (rst_i) latch1_r <= {TW{1'b0}};
        else         latch1_r <= deltasigma1_w;

    assign din_w         = {{EW{input_i[DW-1]}}, input_i};

    assign msb1_w        = latch1_r[TW-1];

    assign q_base_w      = {1'b1, {(DW-1){1'b0}}};

    assign q1_w          = (msb1_w) ? {{EW{1'b1}}, q_base_w} : {{EW{1'b0}}, q_base_w};

    assign deltasigma1_w = q1_w + latch1_r + din_w;

    generate

        if (DSM_ORDER == 1) begin: first_order

            assign output_next_w = ~msb1_w;

        end else begin: second_order

            reg  [TW-1:0] latch2_r;
            wire [TW-1:0] q2_w;
            wire [TW-1:0] deltasigma2_w;
            wire          msb2_w;


            always @(posedge clk_i)
                if   (rst_i) latch2_r <= {TW{1'b0}};
                else         latch2_r <= deltasigma2_w;

            assign msb2_w        = latch2_r[TW-1];

            assign q2_w          = (msb2_w) ? {{EW{1'b1}}, q_base_w} : {{EW{1'b0}}, q_base_w};

            assign deltasigma2_w = q2_w + latch2_r + latch1_r;

            assign output_next_w = ~msb2_w;

        end

    endgenerate


    assign output_o = output_r;


endmodule
