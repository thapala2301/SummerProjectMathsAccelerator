`timescale 1ns / 1ps

module tb_fp_lib;

    reg clk;
    reg rst_n;
    
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end
    
    initial begin
        rst_n = 0;
        #20 rst_n = 1;
    end
    
    integer cycle_cnt = 0;
    always @(posedge clk) begin
        cycle_cnt <= cycle_cnt + 1;
    end

    reg [135:0] vectors [0:2999];
    
    initial begin
        $readmemh("test_vectors.hex", vectors);
    end

    reg [31:0] a_int_in;
    reg [26:0] a_in, b_in, c_in;
    reg [7:0] op_in;
    reg in_valid;

    wire [26:0] out_add, out_sub, out_mul, out_abs, out_negate, out_min, out_max, out_isqrt, out_length, out_int2fp;
    
    // Latency
    reg [26:0] expected_pipe_add [0:3];
    reg [26:0] expected_pipe_sub [0:3];
    reg [26:0] expected_pipe_mul [0:1];
    reg [26:0] expected_pipe_isqrt [0:15];
    reg [26:0] expected_pipe_length [0:31];
    
    integer errors_comb = 0;
    integer errors_add = 0;
    integer errors_sub = 0;
    integer errors_mul = 0;
    
    // Instances
    fp_add dut_add(.clk(clk), .a(a_in), .b(b_in), .out(out_add));
    fp_sub dut_sub(.clk(clk), .a(a_in), .b(b_in), .out(out_sub));
    fp_mul dut_mul(.clk(clk), .a(a_in), .b(b_in), .out(out_mul));
    fp_abs dut_abs(.in(a_in), .out(out_abs));
    fp_negate dut_negate(.in(a_in), .out(out_negate));
    fp_min dut_min(.a(a_in), .b(b_in), .out(out_min));
    fp_max dut_max(.a(a_in), .b(b_in), .out(out_max));
    fp_isqrt dut_isqrt(.clk(clk), .a(a_in), .out(out_isqrt));
    fp_length dut_length(.clk(clk), .x(a_in), .y(b_in), .z(c_in), .out(out_length));
    int2fp dut_int2fp(.in(a_int_in), .out(out_int2fp));
    
    integer i;
    reg [135:0] current_vec;
    reg [7:0] op;
    reg [31:0] a_int;
    reg [26:0] a, b, c, expected;
    
    // Checker
    task check_match;
        input [26:0] act;
        input [26:0] exp;
        input string name;
        reg [7:0] exp_act, exp_exp;
        reg [17:0] mant_act, mant_exp;
        integer mant_diff;
        begin
            exp_act = act[25:18];
            exp_exp = exp[25:18];
            mant_act = act[17:0];
            mant_exp = exp[17:0];
            
            if (^act === 1'bx) begin
                $display("Error! [%s]: Output is unknown (X or Z): %x", name, act);
                $stop;
            end
            
            if (exp_exp == 8'hFF && mant_exp == 0) begin
                if (exp_act != 8'hFF || mant_act != 0 || act[26] != exp[26]) begin
                    $display("Error: [%s]: Expected Infinity, but got %x", name, act);
                    $stop;
                end
            end
            else if (exp_exp == 8'hFF && mant_exp != 0) begin
                if (exp_act != 8'hFF || mant_act == 0) begin
                    $display("Error: [%s]: Expected NaN, but got %x", name, act);
                    $stop;
                end
            end
            else begin
                if (act[26] != exp[26] && mant_exp != 0) begin
                    $display("Error: [%s]: Sign is wrong. Exp: %x, Act: %x", name, exp, act);
                    $stop;
                end
                
                if (exp_act != exp_exp) begin
                    if (!((exp_act == exp_exp + 1 && mant_act == 0 && mant_exp == 18'h3FFFF) || 
                          (exp_exp == exp_act + 1 && mant_exp == 0 && mant_act == 18'h3FFFF))) begin
                        $display("Error:[%s]: Exponent mismatch. Exp: %x, Act: %x", name, exp, act);
                        $stop;
                    end
                end
                
                mant_diff = $signed({1'b0, mant_act}) - $signed({1'b0, mant_exp});
                if (mant_diff > 2 || mant_diff < -2) begin
                    $display("Error: [%s]: Mantissa is off by too much. Exp: %x, Act: %x", name, exp, act);
                    $stop;
                end
            end
        end
    endtask
    
    initial begin
        in_valid = 0;
        @(posedge rst_n);
        @(posedge clk);
        
        for (i = 0; i < 3000; i = i + 1) begin
            current_vec = vectors[i];
            op = current_vec[135:128];
            a_int = current_vec[127:96];
            a  = current_vec[122:96];
            b  = current_vec[90:64];
            c  = current_vec[58:32];
            expected = current_vec[26:0];
            
            a_in <= a;
            b_in <= b;
            c_in <= c;
            a_int_in <= a_int;
            op_in <= op;
            in_valid <= 1;
            
            if (op == 3) begin
                check_match(out_abs, expected, "ABS");
            end else if (op == 4) begin
                check_match(out_negate, expected, "NEGATE");
            end else if (op == 5) begin
                check_match(out_min, expected, "MIN");
            end else if (op == 6) begin
                check_match(out_max, expected, "MAX");
            end else if (op == 9) begin
                check_match(out_int2fp, expected, "INT2FP");
            end
            
            @(posedge clk);
            in_valid <= 0;
        end
        
        repeat(150) @(posedge clk);
        
        $display("TEST SUMMARY:");
        $display("Total Errors Encountered: %d", errors_comb);
        $finish;
    end

    reg add_valid_pipe [0:3];
    integer j;
    always @(posedge clk) begin
        add_valid_pipe[0] <= (op_in == 0 && in_valid);
        expected_pipe_add[0] <= expected;
        for (j = 1; j < 4; j = j + 1) begin
            add_valid_pipe[j] <= add_valid_pipe[j-1];
            expected_pipe_add[j] <= expected_pipe_add[j-1];
        end
        
        if (add_valid_pipe[3]) begin
            check_match(out_add, expected_pipe_add[3], "ADD");
        end
    end

    reg sub_valid_pipe [0:3];
    integer k;
    always @(posedge clk) begin
        sub_valid_pipe[0] <= (op_in == 1 && in_valid);
        expected_pipe_sub[0] <= expected;
        for (k = 1; k < 4; k = k + 1) begin
            sub_valid_pipe[k] <= sub_valid_pipe[k-1];
            expected_pipe_sub[k] <= expected_pipe_sub[k-1];
        end
        
        if (sub_valid_pipe[3]) begin
            check_match(out_sub, expected_pipe_sub[3], "SUB");
        end
    end

    reg mul_valid_pipe [0:1];
    always @(posedge clk) begin
        mul_valid_pipe[0] <= (op_in == 2 && in_valid);
        expected_pipe_mul[0] <= expected;
        mul_valid_pipe[1] <= mul_valid_pipe[0];
        expected_pipe_mul[1] <= expected_pipe_mul[0];
        
        if (mul_valid_pipe[1]) begin
            check_match(out_mul, expected_pipe_mul[1], "MUL");
        end
    end

    reg isqrt_valid_pipe [0:15];
    integer m;
    always @(posedge clk) begin
        isqrt_valid_pipe[0] <= (op_in == 7 && in_valid);
        expected_pipe_isqrt[0] <= expected;
        for (m = 1; m < 16; m = m + 1) begin
            isqrt_valid_pipe[m] <= isqrt_valid_pipe[m-1];
            expected_pipe_isqrt[m] <= expected_pipe_isqrt[m-1];
        end
        
        if (isqrt_valid_pipe[15]) begin
            check_match(out_isqrt, expected_pipe_isqrt[15], "ISQRT");
        end
    end

    reg length_valid_pipe [0:31];
    integer n;
    always @(posedge clk) begin
        length_valid_pipe[0] <= (op_in == 8 && in_valid);
        expected_pipe_length[0] <= expected;
        for (n = 1; n < 32; n = n + 1) begin
            length_valid_pipe[n] <= length_valid_pipe[n-1];
            expected_pipe_length[n] <= expected_pipe_length[n-1];
        end
        
        if (length_valid_pipe[31]) begin
            check_match(out_length, expected_pipe_length[31], "LENGTH");
        end
    end

endmodule
