`timescale 1ns / 1ps

module tb_analytic_sdf;



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
    
    string hex_file;
    integer LATENCY;

    initial begin

`ifdef TEST_SCENE_SDF
    hex_file = "test_vectors_scene_sdf.hex";
`elsif TEST_BOX
    hex_file = "test_vectors_sdf_box.hex";
`elsif TEST_CAPPED_TORUS
    hex_file = "test_vectors_sdf_capped_torus.hex";
`elsif TEST_CAPSULE
    hex_file = "test_vectors_sdf_capsule.hex";
`elsif TEST_CHAIN_LINK
    hex_file = "test_vectors_sdf_chain_link.hex";
`elsif TEST_CONE
    hex_file = "test_vectors_sdf_cone.hex";
`elsif TEST_CYLINDER
    hex_file = "test_vectors_sdf_cylinder.hex";
`elsif TEST_DEATH_STAR
    hex_file = "test_vectors_sdf_death_star.hex";
`elsif TEST_ELLIPSOID
    hex_file = "test_vectors_sdf_ellipsoid.hex";
`elsif TEST_GYROID
    hex_file = "test_vectors_sdf_gyroid.hex";
`elsif TEST_HYPERBOLOID
    hex_file = "test_vectors_sdf_hyperboloid.hex";
`elsif TEST_MANDELBULB
    hex_file = "test_vectors_sdf_mandelbulb.hex";
`elsif TEST_OCTAHEDRON
    hex_file = "test_vectors_sdf_octahedron.hex";
`elsif TEST_PYRAMID
    hex_file = "test_vectors_sdf_pyramid.hex";
`elsif TEST_ROUND_BOX
    hex_file = "test_vectors_sdf_round_box.hex";
`elsif TEST_SPHERE
    hex_file = "test_vectors_sdf_sphere.hex";
`elsif TEST_STAR
    hex_file = "test_vectors_sdf_star.hex";
`elsif TEST_TERM
    hex_file = "test_vectors_sdf_term.hex";
`elsif TEST_TORUS
    hex_file = "test_vectors_sdf_torus.hex";
`elsif TEST_TRIANGULAR_PRISM
    hex_file = "test_vectors_sdf_triangular_prism.hex";
`elsif TEST_TWISTED_TORUS
    hex_file = "test_vectors_sdf_twisted_torus.hex";
`elsif TEST_VESICA
    hex_file = "test_vectors_sdf_vesica.hex";
`else
    hex_file = "test_vectors_sdf_sphere.hex";
`endif

        $readmemh(hex_file, vectors);
        $display("Testing SDF Module. Hex File = %s", hex_file);
    end

    reg [26:0] px_in, py_in, pz_in;
    reg in_valid;
    wire [26:0] out_val;
    

    reg valid_pipe [0:150];
    reg [26:0] exp_pipe [0:150]; 
    

`ifdef TEST_SCENE_SDF
    scene_sdf dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_BOX
    sdf_box dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_CAPPED_TORUS
    sdf_capped_torus dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_CAPSULE
    sdf_capsule dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_CHAIN_LINK
    sdf_chain_link dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_CONE
    sdf_cone dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_CYLINDER
    sdf_cylinder dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_DEATH_STAR
    sdf_death_star dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_ELLIPSOID
    sdf_ellipsoid dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_GYROID
    sdf_gyroid dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_HYPERBOLOID
    sdf_hyperboloid dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_MANDELBULB
    sdf_mandelbulb dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_OCTAHEDRON
    sdf_octahedron dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_PYRAMID
    sdf_pyramid dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_ROUND_BOX
    sdf_round_box dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_SPHERE
    sdf_sphere dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_STAR
    sdf_star dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_TERM
    wire [26:0] term_out;
    sdf_term dut(.clk(clk), .vx(px_in), .vy(py_in), .vz(pz_in), .out(term_out));
    assign out_val = term_out;
`elsif TEST_TORUS
    sdf_torus dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_TRIANGULAR_PRISM
    sdf_triangular_prism dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_TWISTED_TORUS
    sdf_twisted_torus dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`elsif TEST_VESICA
    sdf_vesica dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`else
    sdf_sphere dut(.clk(clk), .px(px_in), .py(py_in), .pz(pz_in), .sdf_out(out_val));
`endif
    
    integer i;
    reg [115:0] current_vec;
    reg [26:0] px, py, pz, expected;
    

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

                    if (exp[25:0] != 26'b0) begin
                        $display("Error: [%s]: Sign is wrong. Exp: %x, Act: %x", name, exp, act);
                        $stop;
                    end
                end
                

                if (exp[25:0] == 26'b0 && act[25:18] < 8'h7D) return;
                if (act[25:0] == 26'b0 && exp[25:18] < 8'h7D) return;
                
                if (exp_act != exp_exp) begin
                    if (exp_act == exp_exp + 1) begin
                        mant_diff = $signed({1'b0, mant_act}) - ($signed({1'b0, mant_exp}) - 19'h40000);
                    end
                    else if (exp_exp == exp_act + 1) begin
                        mant_diff = ($signed({1'b0, mant_act}) - 19'h40000) - $signed({1'b0, mant_exp});
                    end
                    else begin
                        $display("Error: [%s]: Exponent mismatch. Exp: %x, Act: %x", name, exp, act);
                        $stop;
                    end
                    
                    if (mant_diff > 65536 || mant_diff < -65536) begin
                        $display("Error: [%s]: Mantissa is off by too much across exponent boundary. Exp: %x, Act: %x", name, exp, act);
                        $stop;
                    end
                    return;
                end
                
                mant_diff = $signed({1'b0, mant_act}) - $signed({1'b0, mant_exp});
                if (mant_diff > 65536 || mant_diff < -65536) begin
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
            expected <= current_vec[26:0];
            
            px_in <= current_vec[110:84];
            py_in <= current_vec[82:56];
            pz_in <= current_vec[54:28];
            expected <= current_vec[26:0];
            
            in_valid <= 0;
            repeat(149) @(posedge clk);
            in_valid <= 1;
            @(posedge clk);
        end
        in_valid <= 0;
        
        repeat(150) @(posedge clk);
        
        $display("ALL TESTS PASSED");
        $finish;
    end

    integer j;
    always @(posedge clk) begin
        valid_pipe[0] <= in_valid;
        exp_pipe[0] <= expected;
        
        for(j=1; j<151; j=j+1) begin
            valid_pipe[j] <= valid_pipe[j-1];
            exp_pipe[j] <= exp_pipe[j-1];
        end
        

        if (valid_pipe[1]) begin
            check_match(out_val, exp_pipe[1], hex_file);
        end
    end

endmodule
