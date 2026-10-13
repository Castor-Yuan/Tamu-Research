`timescale 1ns/1ps

module unmask_step #(
    parameter integer N = 8,
    parameter integer TOKEN_W = 8,
    parameter integer CONF_W = 8,
    parameter integer K = 2
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     valid_i,
    input  wire [N-1:0]             mask_i,
    input  wire [N*TOKEN_W-1:0]     tokens_i,
    input  wire [N*TOKEN_W-1:0]     predicted_i,
    input  wire [N*CONF_W-1:0]      confidence_i,
    output logic                    valid_o,
    output logic [N-1:0]            mask_o,
    output logic [N*TOKEN_W-1:0]    tokens_o,
    output logic [N-1:0]            selected_o
);

    logic [N-1:0] selected_next;
    logic [N-1:0] mask_next;
    logic [N*TOKEN_W-1:0] tokens_next;
    integer i, j, rank_count;

    always_comb begin
        selected_next = '0;
        mask_next = mask_i;
        tokens_next = tokens_i;
        rank_count = 0;
        for (i = 0; i < N; i = i + 1) begin
            rank_count = 0;
            for (j = 0; j < N; j = j + 1) begin
                if (mask_i[j] &&
                    ((confidence_i[j*CONF_W +: CONF_W] >
                      confidence_i[i*CONF_W +: CONF_W]) ||
                     ((confidence_i[j*CONF_W +: CONF_W] ==
                       confidence_i[i*CONF_W +: CONF_W]) && (j < i))))
                    rank_count = rank_count + 1;
            end
            if (mask_i[i] && (rank_count < K)) begin
                selected_next[i] = 1'b1;
                mask_next[i] = 1'b0;
                tokens_next[i*TOKEN_W +: TOKEN_W] =
                    predicted_i[i*TOKEN_W +: TOKEN_W];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_o <= 1'b0;
            mask_o <= '0;
            tokens_o <= '0;
            selected_o <= '0;
        end else begin
            valid_o <= valid_i;
            if (valid_i) begin
                mask_o <= mask_next;
                tokens_o <= tokens_next;
                selected_o <= selected_next;
            end
        end
    end
endmodule
