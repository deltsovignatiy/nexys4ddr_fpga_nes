
/*
 * Description : Defines
 * Author      : Deltsov Ignatiy
 * License     : MIT, See LICENSE for details
 */


/* Макрос для включения/выключения инициализации блочной памяти */

//`define INITIALIZE_MEMORY


/* Макрос используется в симуляции для включения инициализации случайным
 * значением некоторых регистров, у которых нет явного начального состояния,
 * и блочной памяти, если макрос INITIALIZE_MEMORY неактивен */

//`define SIMULATION


`ifdef INITIALIZE_MEMORY
    `define MEM_INIT_VAL 1'b0
`else
    `define MEM_INIT_VAL 1'bx
`endif


`ifdef SIMULATION
    `define MEM_SIM "TRUE"
`else
    `define MEM_SIM "FALSE"
`endif
