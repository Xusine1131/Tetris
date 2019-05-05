#include<verilated.h>
#include<stdio.h>
#include "../obj_dir/Vgame_plate.h"
#include "test_template.hpp"
#include "../obj_dir/Vgame_plate_tetris.h"

void displayCurrentInfo(TestWrapper<Vgame_plate> &dut){
    puts("Board Info:");
    for(int i = 0; i < 32; ++i){
        dut->dis_logic_y_i = i;
        for(int j = 0; j < 16; ++j){
            dut->dis_logic_x_i = j;
            dut->eval();
            if(dut->dis_logic_mm_o)
                printf("1");
            else if(dut->dis_logic_cm_o)
                printf("*");
            else
                printf("0");
        }
        puts("");
    }
}

int main(int argc, char **argv){
    Verilated::commandArgs(argc, argv);
    TestWrapper<Vgame_plate> wrapper;
    // initial value
    wrapper->clk_i = 0;
    wrapper->reset_i = 0;
    wrapper->opcode_i = 0;
    wrapper->opcode_v_i = 0;
    wrapper->dis_logic_x_i = 0;
    wrapper->dis_logic_y_i = 0;
    wrapper->eval();

    // reset
    wrapper.reset();

    puts("Reset Finished!");

    wrapper.tick();

    while(true){ // Debug list
        char c = 0;
        puts("n for new, s for move down, a for move left, d for move right, x for rotate, c for commit and k for check.");
        scanf("%c", &c);
        fflush(stdin);
        switch (c){
            case 'n': {
                wrapper->opcode_i = Vgame_plate_tetris::eNew;
                break;
            }
            case 's': {
                wrapper->opcode_i = Vgame_plate_tetris::eMoveDown;
                break;
            }
            case 'a': {
                wrapper->opcode_i = Vgame_plate_tetris::eMoveLeft;
                break;
            }
            case 'd': {
                wrapper->opcode_i = Vgame_plate_tetris::eMoveRight;
                break;
            }
            case 'x': {
                wrapper->opcode_i = Vgame_plate_tetris::eRotate;
                break;
            }
            case 'c': {
                wrapper->opcode_i = Vgame_plate_tetris::eCommit;
                break;
            }
            case 'k': {
                wrapper->opcode_i = Vgame_plate_tetris::eCheck;
                break;
            }
            case 'q': {
                return 0;
            }
            default: {
                wrapper->opcode_i = Vgame_plate_tetris::eNop;
            }
        }
        wrapper->opcode_v_i = 1;
        wrapper.tick(false);
        while(!wrapper->done_o)
            wrapper.tick(false);
        wrapper.tick(false);
        wrapper->opcode_v_i = 0;
        wrapper.tick(false);
        displayCurrentInfo(wrapper);
    }

    return 0;
}