module game_top_logic #(
  parameter integer width_p = scene_width_p
  ,parameter integer height_p = scene_height_p
  ,parameter debug_p = 1
  ,parameter verilator_sim_p = 1
)(
  input clk_i // = 1MHz
  ,input reset_i

  ,input left_i
  ,input right_i
  ,input rotate_i

  ,input start_i // start signal

  // interaction with vga scanner
  ,input [$clog2(width_p)-1:0] dis_logic_x_i
  ,input [$clog2(height_p)-1:0] dis_logic_y_i
  ,output dis_logic_mm_o // in matrix memory
  ,output dis_logic_cm_o // current state memory
  ,output [3:0][3:0] dis_logic_next_block_o

  // game status
  ,output lose_o
  ,output [3:0][3:0] score_o

  // Debugging ports for FPGA
  ,output [3:0] state_o

  // debug ports for synchronization
  ,output debug_turn_finished_o

);

typedef enum logic[3:0] {eStart = 4'd0, eIdle = 4'd1, eUserInteract = 4'd2, eSystemNew = 4'd3,  eSystemDown = 4'd4, eSystemCommit = 4'd5, eSystemCheck = 4'd6, eAddScore = 4'd7, eLost = 4'd8} state_e /*verilator public*/;
typedef enum logic[1:0] {eUserNop, eUserLeft, eUserRight, eUserRotate} user_op_e /*verilator public*/;

reg [18:0] frequency_divider_r;
always_ff @(posedge clk_i) begin
  if(reset_i) frequency_divider_r <= '0;
  else frequency_divider_r <= frequency_divider_r + 1;
end
wire clk_4hz;
if(!verilator_sim_p)
  assign clk_4hz = frequency_divider_r[16:0] == '1; // [17:0], test is [1:0]
else
  assign clk_4hz = frequency_divider_r[1:0] == '1; // [17:0], test is [1:0]
reg clk_4hz_r;
always_ff @(posedge clk_i) begin
  if(reset_i) clk_4hz_r <= '0;
  else clk_4hz_r <= clk_4hz;
end
wire pos_4hz = clk_4hz & ~clk_4hz_r;
wire clk_1hz;
if(!verilator_sim_p)
  assign clk_1hz = frequency_divider_r[18:0] == '1; // [19:0], test is [3:0]
else
  assign clk_1hz = frequency_divider_r[3:0] == '1;
reg clk_1hz_r;
always_ff @(posedge clk_i) begin
  if(reset_i) clk_1hz_r <= '0;
  else clk_1hz_r <= clk_1hz;
end
wire pos_1hz = clk_1hz & ~clk_1hz_r;

wire op_is_done;
wire add_score_done;
wire touch_bottom;
state_e state_r /*verilator public*/;
state_e state_n /*verilator public*/;
user_op_e user_op_r;

always_ff @(posedge clk_i) begin
  if(reset_i) user_op_r <= eUserNop;
  else if(pos_4hz) begin
    if(left_i) user_op_r <= eUserLeft;
    else if(right_i) user_op_r <= eUserRight;
    else if(rotate_i) user_op_r <= eUserRotate;
  end
end

reg pos_req_r;
always_ff @(posedge clk_i) begin
  if(reset_i) pos_req_r <= '0;
  else if(state_r == eMoveDown) pos_req_r <= '0;
  else if(pos_1hz) pos_req_r <= '1;
end

always_comb unique case(state_r)
  eStart: if(start_i) state_n = eSystemNew; else state_n = eStart;
  eIdle: begin
    if(pos_1hz | pos_req_r) state_n = touch_bottom ? eSystemCommit : eSystemDown;
    else if((left_i | right_i | rotate_i) & pos_4hz) state_n = eUserInteract;
    else state_n = eIdle;
  end
  eSystemNew: begin
    if(pos_1hz) state_n = eIdle;
    else state_n = eSystemNew;
  end
  eUserInteract: begin
    if(op_is_done & pos_4hz) state_n = eIdle;
    else state_n = eUserInteract;
  end
  eSystemDown: begin
    if (lose_o & pos_4hz) state_n = eLost;
    else if(op_is_done) state_n = eIdle;
    else state_n = eSystemDown;
  end
  eSystemCommit: begin
    if(op_is_done & pos_4hz) state_n = eSystemCheck;
    else state_n = eSystemCommit;
  end
  eSystemCheck: begin
    if(op_is_done & pos_4hz) state_n = eAddScore;
    else state_n = eSystemCheck;
  end
  eAddScore: begin
    if(add_score_done) state_n = eSystemNew;
    else state_n = eAddScore;
  end
  eLost: begin
    state_n = eLost;
  end
  default: begin
    state_n = state_r;
  end
endcase

always_ff @(posedge clk_i) begin
  if(reset_i)
    state_r <= eStart;
  else
    state_r <= state_n;
end

opcode_e opcode_to_append;

always_comb unique case(state_r)
  eSystemDown: opcode_to_append = eMoveDown;
  eSystemCommit: opcode_to_append = eCommit;
  eSystemCheck: opcode_to_append = eCheck;
  eSystemNew: opcode_to_append = eNew;
  eUserInteract: unique case(user_op_r)
    eUserLeft: opcode_to_append = eMoveLeft;
    eUserRight: opcode_to_append = eMoveRight;
    eUserRotate: opcode_to_append = eRotate;
    default: opcode_to_append = eNop;
  endcase
  default: opcode_to_append = eNop;
endcase

wire plate_yumi = state_n != state_r;
wire [2:0] line_eliminate_n;
game_plate #(
  .width_p(width_p)
  ,.height_p(height_p)
  ,.debug_p(verilator_sim_p)
) plate (
  .clk_i(clk_i)
  ,.reset_i(reset_i)

  ,.opcode_i(opcode_to_append)
  ,.opcode_v_i(opcode_to_append != eNop)
  ,.ready_o()

  ,.dis_logic_x_i(dis_logic_x_i)
  ,.dis_logic_y_i(dis_logic_y_i)
  ,.dis_logic_mm_o(dis_logic_mm_o)
  ,.dis_logic_cm_o(dis_logic_cm_o)
  ,.dis_logic_next_block_o(dis_logic_next_block_o)

  ,.line_elimination_o(line_eliminate_n)
  ,.line_elimination_v_o()
  ,.lose_o(lose_o)
  ,.done_o(op_is_done)
  ,.block_cannot_move_down_o(touch_bottom)

  ,.yumi_i(plate_yumi)
);

logic [3:0][3:0] score_r;
reg [1:0] score_update_cnt_r;

always_ff @(posedge clk_i) begin
  if(reset_i) begin
    score_r <= '0;
    score_update_cnt_r <= '0;
  end
  else if(state_r == eStart) begin
    score_r <= '0;
    score_update_cnt_r <= '0;
  end
  else if(state_r == eAddScore) begin
    unique case(score_update_cnt_r)
      2'b00: score_r[0] <= score_r[0] + line_eliminate_n;
      2'b01: begin
        score_r[1] <= score_r[1] + 4'(score_r[0] >= 10);
        score_r[0] <= score_r[0] >= 10 ? score_r[0] - 10 : score_r[0];
      end
      2'b10: begin
        score_r[2] <= score_r[2] + 4'(score_r[1] >= 10);
        score_r[1] <= score_r[1] >= 10 ? score_r[1] - 10 : score_r[1];
      end
      2'b11: begin
        score_r[3] <= score_r[3] + 4'(score_r[2] >= 10);
        score_r[2] <= score_r[2] >= 10 ? score_r[2] - 10 : score_r[2];
      end
    endcase
    score_update_cnt_r <= score_update_cnt_r + 1;
  end
end
assign add_score_done = score_update_cnt_r == '1;
assign score_o = score_r;
assign debug_turn_finished_o = state_r == eSystemDown & state_n == eIdle;
assign state_o = state_r;

if(debug_p | verilator_sim_p) begin
  always_ff @(posedge clk_i) begin
    $display("========== Top Logic ==========");
    $display("Current State:%s",state_r.name());
  end
end

endmodule
