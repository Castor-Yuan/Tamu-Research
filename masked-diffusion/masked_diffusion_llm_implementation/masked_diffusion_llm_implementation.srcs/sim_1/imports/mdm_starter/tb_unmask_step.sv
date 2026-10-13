`timescale 1ns/1ps

module tb_unmask_step;
    localparam integer N = 8;
    localparam integer W = 8;
    parameter integer K = 2;

    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic rst = 1'b1;
    logic valid_i = 1'b0;
    logic [N-1:0] mask_i = '0;
    logic [N*W-1:0] tokens_i = '0;
    logic [N*W-1:0] predicted_i = '0;
    logic [N*W-1:0] confidence_i = '0;
    wire valid_o;
    wire [N-1:0] mask_o, selected_o;
    wire [N*W-1:0] tokens_o;
    integer tests = 0;
    integer trial, p;
    logic [31:0] rng = 32'h19f2a471;
    logic [7:0] random_mask;
    logic [63:0] random_tokens, random_predictions, random_confidence;
    logic [7:0] loop_mask;
    logic [63:0] loop_tokens;

    unmask_step #(.N(N), .TOKEN_W(W), .CONF_W(W), .K(K)) dut (
        .clk(clk), .rst(rst), .valid_i(valid_i), .mask_i(mask_i),
        .tokens_i(tokens_i), .predicted_i(predicted_i),
        .confidence_i(confidence_i), .valid_o(valid_o),
        .mask_o(mask_o), .tokens_o(tokens_o), .selected_o(selected_o)
    );

    function automatic logic [31:0] next_random(input logic [31:0] x);
        logic [31:0] y;
        begin
            y = x ^ (x << 13);
            y = y ^ (y >> 17);
            next_random = y ^ (y << 5);
        end
    endfunction

    // Reference uses repeated maximum extraction, not the DUT's rank circuit.
    task automatic check_case(
        input logic [7:0] m,
        input logic [63:0] t,
        input logic [63:0] pred,
        input logic [63:0] conf,
        input logic enable
    );
        logic [7:0] expected_mask, expected_selected;
        logic [63:0] expected_tokens;
        integer pick, index, best, best_score;
        begin
            @(negedge clk);
            expected_mask = mask_o;
            expected_selected = selected_o;
            expected_tokens = tokens_o;
            if (enable) begin
                expected_mask = m;
                expected_tokens = t;
                expected_selected = '0;
                for (pick = 0; pick < K; pick = pick + 1) begin
                    best = -1;
                    best_score = -1;
                    for (index = 0; index < N; index = index + 1) begin
                        if (expected_mask[index] &&
                            (int'(conf[index*W +: W]) > best_score)) begin
                            best = index;
                            best_score = int'(conf[index*W +: W]);
                        end
                    end
                    if (best >= 0) begin
                        expected_mask[best] = 1'b0;
                        expected_selected[best] = 1'b1;
                        expected_tokens[best*W +: W] = pred[best*W +: W];
                    end
                end
            end
            valid_i = enable;
            mask_i = m;
            tokens_i = t;
            predicted_i = pred;
            confidence_i = conf;
            @(posedge clk);
            #1;
            if ((valid_o !== enable) || (mask_o !== expected_mask) ||
                (selected_o !== expected_selected) ||
                (tokens_o !== expected_tokens)) begin
                $error("case=%0d K=%0d: mask=%h expected=%h selected=%h expected=%h tokens=%h expected=%h",
                       tests, K, mask_o, expected_mask, selected_o,
                       expected_selected, tokens_o, expected_tokens);
                $fatal(1, "FAIL");
            end
            tests = tests + 1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        #1;
        if ({valid_o, mask_o, tokens_o, selected_o} !== '0)
            $fatal(1, "Reset failed");
        @(negedge clk);
        rst = 1'b0;

        // Prompt positions 0 and 1 are preserved even with high input scores.
        // Among masked positions 2..7, positions 2 and 6 have the highest scores.
        check_case(8'hfc, 64'h0000000000001413,
                   64'h1b1a191817161514, 64'h32d2281450b4ffff, 1'b1);
        // Explicit, independently specified result for the worked example.
        // Scores above: position 2=180 and position 6=210.
        if (K == 2) begin
            if ((selected_o !== 8'h44) || (mask_o !== 8'hb8) ||
                (tokens_o !== 64'h001a000000161413))
                $fatal(1, "Worked example failed");
        end

        check_case(8'h00, 64'h123456789abcdef0, '1, '1, 1'b1);
        check_case(8'h80, 64'h0102030405060708, 64'hfe00000000000000, '0, 1'b1);
        check_case(8'hff, '0, 64'h1716151413121110, '0, 1'b1);
        check_case(8'hff, '1, '0, '1, 1'b1);
        check_case(8'hff, '1, '1, '1, 1'b0);

        // Consecutive valid cycles and bubbles; coarse scores exercise ties.
        for (trial = 0; trial < 200; trial = trial + 1) begin
            rng = next_random(rng);
            random_mask = rng[7:0];
            for (p = 0; p < N; p = p + 1) begin
                rng = next_random(rng);
                random_tokens[p*W +: W] = rng[7:0];
                random_predictions[p*W +: W] = rng[15:8];
                random_confidence[p*W +: W] = {4'b0, rng[19:16]};
            end
            check_case(random_mask, random_tokens, random_predictions,
                       random_confidence, ((trial % 7) != 0));
        end

        // Feed back updated state to demonstrate progressive unmasking.
        loop_mask = 8'hfc;
        loop_tokens = 64'h0000000000001413;
        for (trial = 0; trial < 6; trial = trial + 1) begin
            check_case(loop_mask, loop_tokens, 64'h1b1a191817161514,
                       64'h8070605040302010, 1'b1);
            loop_mask = mask_o;
            loop_tokens = tokens_o;
        end
        if ((K > 0) && (mask_o !== '0))
            $fatal(1, "Sequence did not finish");
        @(negedge clk);
        rst = 1'b1;
        @(posedge clk);
        #1;
        if ({valid_o, mask_o, tokens_o, selected_o} !== '0)
            $fatal(1, "Reset after traffic failed");
        $display("PASS: %0d cases, N=%0d K=%0d; reset, ties, prompt preservation, bubbles, feedback", tests, N, K);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Simulation timeout");
    end
endmodule
