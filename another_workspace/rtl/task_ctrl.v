`timescale 1ns/1ps
`default_nettype none

module task_ctrl (
    input  wire clk,
    input  wire rst_n,
    input  wire start_pulse,
    input  wire soft_reset_pulse,
    input  wire init_done,
    input  wire run_done,
    input  wire all_idle,
    input  wire error_in,
    output reg  task_busy,
    output reg  task_done_pulse,
    output reg  task_error,
    output reg  global_clear,
    output reg  run_enable,
    output reg  init_start
);

localparam [2:0] ST_IDLE  = 3'd0;
localparam [2:0] ST_INIT  = 3'd1;
localparam [2:0] ST_RUN   = 3'd2;
localparam [2:0] ST_DRAIN = 3'd3;
localparam [2:0] ST_DONE  = 3'd4;
localparam [2:0] ST_ERROR = 3'd5;

reg [2:0] state_reg;

always @(posedge clk) begin
    if (!rst_n || soft_reset_pulse) begin
        state_reg <= ST_IDLE;
        task_busy <= 1'b0;
        task_done_pulse <= 1'b0;
        task_error <= 1'b0;
        global_clear <= 1'b1;
        run_enable <= 1'b0;
        init_start <= 1'b0;
    end else begin
        task_done_pulse <= 1'b0;
        global_clear <= 1'b0;
        init_start <= 1'b0;
        case (state_reg)
            ST_IDLE: begin
                task_busy <= 1'b0;
                run_enable <= 1'b0;
                if (start_pulse) begin
                    state_reg <= ST_INIT;
                    task_busy <= 1'b1;
                    global_clear <= 1'b1;
                    init_start <= 1'b1;
                    // page_manager/score_scheduler 以 start && run_enable
                    // 作为任务接受条件，因此启动脉冲同拍必须拉高使能。
                    run_enable <= 1'b1;
                    task_error <= 1'b0;
                end
            end
            ST_INIT: begin
                task_busy <= 1'b1;
                if (error_in) begin
                    state_reg <= ST_ERROR;
                    task_error <= 1'b1;
                end else if (init_done) begin
                    state_reg <= ST_RUN;
                    run_enable <= 1'b1;
                end
            end
            ST_RUN: begin
                task_busy <= 1'b1;
                run_enable <= 1'b1;
                if (error_in) begin
                    state_reg <= ST_ERROR;
                    task_error <= 1'b1;
                    run_enable <= 1'b0;
                end else if (run_done) begin
                    state_reg <= ST_DRAIN;
                    run_enable <= 1'b0;
                end
            end
            ST_DRAIN: begin
                task_busy <= 1'b1;
                if (error_in) begin
                    state_reg <= ST_ERROR;
                    task_error <= 1'b1;
                end else if (all_idle) begin
                    state_reg <= ST_DONE;
                end
            end
            ST_DONE: begin
                task_done_pulse <= 1'b1;
                task_busy <= 1'b0;
                state_reg <= ST_IDLE;
            end
            default: begin
                task_busy <= 1'b0;
                run_enable <= 1'b0;
                task_error <= 1'b1;
                state_reg <= ST_ERROR;
            end
        endcase
    end
end

endmodule

`default_nettype wire
