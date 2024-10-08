
/*
 * Description : Function clogb2
 * Author      : Deltsov Ignatiy
 * License     : MIT, see LICENSE for details
 */


    // Функция для вычисления логарифма по основанию 2
    function integer __clogb2__(input integer depth);
        begin

            depth = depth - 1;
            for (__clogb2__ = 0; depth > 0; __clogb2__ = __clogb2__ + 1) depth = depth >> 1;

        end
    endfunction
