/**
 *This module provides a simple implementation of fixed point arithmetic
 *
 *@author Ethan Carr
 *@date 12/06/2025
 */

#define FRACTIONAL_BITS 8
#define SCALE_FACTOR (1 << FRACTIONAL_BITS)
#define ROUND_BIT (1 << (FRACTIONAL_BITS - 1))

generic module Fixed_PointC(){
    provides interface Fixed_Point;
}

implementation{
    command uint16_t Fixed_Point.u_fixed_mult(uint16_t x, uint16_t y){
        uint32_t raw = (uint32_t) (x * y);
        uint32_t rounded = raw + ROUND_BIT;
        uint16_t fixed_res = (uint16_t)(rounded >> FRACTIONAL_BITS);    
        return fixed_res;
    }   

    command uint16_t Fixed_Point.u_fixed_div(uint16_t x, uint16_t y){
        uint32_t dividend;
        uint16_t fixed_res;
        if(y == 0){
            return x;
        }
        dividend = (uint32_t)x << FRACTIONAL_BITS;
        fixed_res = (uint16_t)(dividend/y);
        return fixed_res;
    }

    command uint16_t Fixed_Point.fixed_to_uint16(uint16_t fixed){
        return fixed/SCALE_FACTOR;
    }

    command uint16_t Fixed_Point.uint16_to_fixed(uint16_t val){
        return (uint16_t)(val * SCALE_FACTOR);
    }

    command uint16_t Fixed_Point.fixed_ewma_calc(uint16_t curr, uint16_t prev, uint16_t alpha){
        uint16_t curr_scaled = call Fixed_Point.u_fixed_mult(curr, alpha);
        uint16_t prev_scaled = call Fixed_Point.u_fixed_mult(prev, ((uint16_t)1 * SCALE_FACTOR) - alpha);
        uint16_t ewma = curr_scaled + prev_scaled;
        return ewma;
    }
}