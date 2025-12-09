/**
 *This is an interface for Fixed Point Arithmetic
 *
 *@author Ethan Carr
 *@date 12/06/2025
 */

 interface Fixed_Point{
   command uint16_t u_fixed_mult(uint16_t x, uint16_t y);

   command uint16_t u_fixed_div(uint16_t x, uint16_t y);

   command uint16_t fixed_to_uint16(uint16_t fixed);

   command uint16_t uint16_to_fixed(uint16_t val);

   command uint16_t fixed_ewma_calc(uint16_t curr, uint16_t prev, uint16_t alpha);
 }
