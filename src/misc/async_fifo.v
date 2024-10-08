
/*
 * Description : Asynchronous FIFO module
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


`include "defines.vh"


module async_fifo
    #(
        parameter DATA_WIDTH = 8,                // Ширина данных
        parameter FIFO_DEPTH = 16                // Глубина буфера, должна быть степень 2 и >= 4
    )
    (
        input  wire                  wd_clk_i,   // Сигнал тактирования домена записи в FIFO
        input  wire                  wd_rst_i,   // Сигнал сброса домена записи в FIFO
        input  wire                  wd_write_i, // Сигнал записи данных в FIFO
        input  wire [DATA_WIDTH-1:0] wd_data_i,  // Записываемые данные в FIFO
        output wire                  wd_full_o,  // Сигнал заполнености буфера FIFO

        input  wire                  rd_clk_i,   // Сигнал тактирования домена чтения в FIFO
        input  wire                  rd_rst_i,   // Сигнал сброса домена чтения в FIFO
        input  wire                  rd_read_i,  // Сигнал чтения данных из FIFO
        output wire [DATA_WIDTH-1:0] rd_data_o,  // Читаемые данные из FIFO
        output wire                  rd_empty_o  // Сигнал опустошенности FIFO
    );


    `include "function_clogb2.vh"


    // Ширина адресной линии
    localparam ADDRESS_WIDTH = __clogb2__(FIFO_DEPTH);
    localparam AW            = ADDRESS_WIDTH;


    // Сигналы состояния FIFO
    reg           wd_full_r;
    wire          wd_full_next_w;
    reg           rd_empty_r;
    wire          rd_empty_next_w;

    // Сигналы домена записи
    (* DONT_TOUCH = "TRUE" *)
    reg  [  AW:0] wd_wgray_r;
    wire [  AW:0] wd_wgray_next_w;
    reg  [  AW:0] wd_ptr_r;
    wire [  AW:0] wd_ptr_next_w;
    wire          wd_mem_wren_w;
    wire [AW-1:0] wd_act_ptr_w;
    (* ASYNC_REG = "TRUE" *)
    reg  [  AW:0] wd_rgray_r [1:0];

    // Сигналы домена чтения
    (* DONT_TOUCH = "TRUE" *)
    reg  [  AW:0] rd_rgray_r;
    wire [  AW:0] rd_rgray_next_w;
    reg  [  AW:0] rd_ptr_r;
    wire [  AW:0] rd_ptr_next_w;
    wire          rd_mem_rden_w;
    wire [AW-1:0] rd_act_ptr_w;
    (* ASYNC_REG = "TRUE" *)
    reg  [  AW:0] rd_wgray_r [1:0];


    /* Чтобы определить, есть ли место для новых данных в буфере,
     * используем текущий указатель на адрес для чтения в коде Грея,
     * переданный в тактовый домен с логикой записи в фифо.
     * Буфер заполнен в том случае, если ((wd_ptr_r - rd_ptr_r) = (1 << AW)),
     * т.е. адреса на чтение и запись отличаются на старший бит,
     * который служит флагом прохождения указателем очередного полного круга.
     * Тогда, исходя из выражения (grey = value ^ (value >> 1)) для вычисления
     * кода Грея, указатели адресов в коде Грея будут отличаться на два
     * старших бита, т.е. эти биты будут инвертированы */
    assign wd_full_next_w = (wd_wgray_next_w == {~wd_rgray_r[1][AW:AW-1], wd_rgray_r[1][AW-2:0]});

    /* Если есть новые данные, и в памяти фифо есть для них место, то
     * записываем их в модуль memory, инкрементируя указатель адреса
     * и преобразуя его в код Грея */
    assign wd_mem_wren_w   = wd_write_i && ~wd_full_r;
    assign wd_ptr_next_w   = wd_ptr_r + wd_mem_wren_w;
    assign wd_wgray_next_w = {wd_ptr_next_w[AW], wd_ptr_next_w[AW-1:0] ^ wd_ptr_next_w[AW:1]};

    /* Получаем указатель в коде Грея на адрес для чтения из его тактового домена.
     * Обновляем указатели на адрес для записи в бинарном представлении и коде Грея,
     * использующиеся соответственно для непосредственной записи в буфер и для передачи
     * информации о текущей ячейке для записи в тактовый домен с логикой чтения из фифо,
     * а также — флаг переполненности буфера. */
    always @(posedge wd_clk_i)
        if (wd_rst_i) begin
            wd_rgray_r[1] <= {(AW+1){1'b0}};
            wd_rgray_r[0] <= {(AW+1){1'b0}};
            wd_ptr_r      <= {(AW+1){1'b0}};
            wd_wgray_r    <= {(AW+1){1'b0}};
            wd_full_r     <= 1'b0;
        end else begin
            wd_rgray_r[1] <= wd_rgray_r[0];
            wd_rgray_r[0] <= rd_rgray_r;
            wd_ptr_r      <= wd_ptr_next_w;
            wd_wgray_r    <= wd_wgray_next_w;
            wd_full_r     <= wd_full_next_w;
        end


    /* Чтобы определить, есть ли данные, доступные для чтения,
     * используем текущий указатель на адрес для записи в коде Грея,
     * переданный в тактовый домен с логикой чтения в фифо.
     * Буфер пуст в случае, когда указатели на запись и чтение указывают
     * на одну и ту же ячейку памяти (wd_ptr_r = rd_ptr_r), соответственно
     * значения указателей в коде Грея также будут равны */
    assign rd_empty_next_w = (rd_rgray_next_w == rd_wgray_r[1]);

    /* Если есть запрос на чтение и, данные — в памяти фифо, то
     * читаем их из модуля memory, инкрементируя указатель адреса
     * и преобразуя его в код Грея */
    assign rd_mem_rden_w   = rd_read_i && ~rd_empty_r;
    assign rd_ptr_next_w   = rd_ptr_r + rd_mem_rden_w;
    assign rd_rgray_next_w = {rd_ptr_next_w[AW], rd_ptr_next_w[AW-1:0] ^ rd_ptr_next_w[AW:1]};

    /* Получаем указатель в коде Грея на адрес для записи из его тактового домена.
     * Обновляем указатели на адрес для чтения в бинарном представлении и коде Грея,
     * использующиеся соответственно для непосредственного чтения из буфера и для передачи
     * информации о текущей ячейке для чтения в тактовый домен с логикой записи в фифо,
     * а также — флаг опустошённости буфера. После сброса буфер естественным образом пуст,
     * поэтому флаг находится в состоянии — "1" */
    always @(posedge rd_clk_i)
        if (rd_rst_i) begin
            rd_wgray_r[1] <= {(AW+1){1'b0}};
            rd_wgray_r[0] <= {(AW+1){1'b0}};
            rd_ptr_r      <= {(AW+1){1'b0}};
            rd_rgray_r    <= {(AW+1){1'b0}};
            rd_empty_r    <= 1'b1;
        end else begin
            rd_wgray_r[1] <= rd_wgray_r[0];
            rd_wgray_r[0] <= wd_wgray_r;
            rd_ptr_r      <= rd_ptr_next_w;
            rd_rgray_r    <= rd_rgray_next_w;
            rd_empty_r    <= rd_empty_next_w;
        end


    /* Для обращения к нужной ячейке памяти фифо используем указатель
     * без старшего бита — флага для определения состояний full и empty */
    assign wd_act_ptr_w = wd_ptr_r[AW-1:0];
    assign rd_act_ptr_w = rd_ptr_r[AW-1:0];


    // Двухпортовая память
    simple_dual_port_2_clock_ram
        #(
            .DATA_WIDTH(DATA_WIDTH   ),
            .RAM_DEPTH (FIFO_DEPTH   ),
            .RAM_STYLE ("block"      ),
            .INIT_VAL  (`MEM_INIT_VAL),
            .SIMULATION(`MEM_SIM     )
        )
        memory
        (
            .clka_i    (wd_clk_i     ),
            .addra_i   (wd_act_ptr_w ),
            .wra_i     (wd_mem_wren_w),
            .dina_i    (wd_data_i    ),

            .clkb_i    (rd_clk_i     ),
            .addrb_i   (rd_act_ptr_w ),
            .rdb_i     (rd_mem_rden_w),
            .doutb_o   (rd_data_o    )
        );


    // Присваиваем значения выходным сигналам состояния фифо
    assign rd_empty_o = rd_empty_r;
    assign wd_full_o  = wd_full_r;


endmodule

