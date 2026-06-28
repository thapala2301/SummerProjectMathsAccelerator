`timescale 1ns / 1ps

module tb_scene_sdf;

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

    reg [115:0] vectors [0:199];
    
    initial begin
        $readmemh("test_vectors_scene_sdf.hex", vectors);
    end

    reg [26:0] px_in, py_in, pz_in;
    reg in_valid;

    wire [26:0] out_val;
    
    // Latency
    reg [26:0] exp_pipe [0:38];
    
    integer errors = 0;
    
    // Instances
    scene_sdf dut(
        .clk(clk),
        .px(px_in),
        .py(py_in),
        .pz(pz_in),
        .sdf_out(out_val)
    );
    
    integer i;
    reg [115:0] current_vec;
    reg [26:0] px, py, pz, expected;
    
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
                $display("Error: [%s]: Output is unknown (X or Z): %x", name, act);
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
                        $display("Error: [%s]: Exponent mismatch. Exp: %x, Act: %x", name, exp, act);
                        $stop;
                    end
                end
                
                mant_diff = $signed({1'b0, mant_act}) - $signed({1'b0, mant_exp});
                if (mant_diff > 8 || mant_diff < -8) begin
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
        
        for (i = 0; i < 200; i = i + 1) begin
            current_vec = vectors[i];
            px = current_vec[110:84];
            py = current_vec[82:56];
            pz = current_vec[54:28];
            expected = current_vec[26:0];
            
            px_in <= px;
            py_in <= py;
            pz_in <= pz;
            in_valid <= 1;
            
            @(posedge clk);
        end
        in_valid <= 0;
        
        repeat(100) @(posedge clk);
        
        $display("ALL TESTS PASSED");
        $finish;
    end

    reg valid_pipe [0:38];
    integer j;
    always @(posedge clk) begin
        valid_pipe[0] <= in_valid;
        exp_pipe[0] <= expected;
        
        for(j=1; j<39; j=j+1) begin
            valid_pipe[j] <= valid_pipe[j-1];
            exp_pipe[j] <= exp_pipe[j-1];
        end
        
        if (valid_pipe[38]) begin
            check_match(out_val, exp_pipe[38], "SCENE_SDF");
        end
    end

endmodule
