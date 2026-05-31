//create verilator model,
//  rest, tick clock,
//  stop when all px done,
//  covert ITER val to RGb,
//  write PPM

#include "Vsim_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>

uint32_t W = 640;
uint32_t H=360;
uint32_t N_PIX=W*H;

struct RGB {uint8_t r,g,b;};

RGB iter_to_rgb(uint8_t iter){
    if(iter==0) return {0,0,0};
    uint8_t v = (iter >=64) ? 255 : iter *4;
    return {v,v,v};
}

int main(){
    Vsim_top* dut = new Vsim_top; //create Verilator model
    std::vector<uint8_t> frame(N_PIX,0); //Frame, var name
    int done_count= 0;

    dut->rst_n = 0;
    dut -> clk = 0;
    for (int i = 0; i<20; i++){
        dut->clk ^=1;
        dut -> eval();

    }
    dut -> rst_n= 1;

    while (done_count < N_PIX){
        dut -> clk^=1;
        dut->eval();
        if(dut->clk == 1 && dut->pix_done){
            frame[dut->pix_id] = dut-> pix_iter;
            done_count ++;
        }
    }

    FILE* f = fopen("frame.ppm", "w");
    fprintf(f, "P3\n%d %d\n255\n", W, H);
    for (int i = 0; i<N_PIX; i++){
        RGB c = iter_to_rgb(frame[i]);
        fprintf(f, "%d %d %d\n", c.r, c.g, c.b);
        }
    fclose(f);

    return(0);
}


