`timescale 1ns / 1ps
module tb_fft();
 
    reg aclk;
 
    reg [15:0] s_axis_config_tdata;
    reg s_axis_config_tvalid;
    wire s_axis_config_tready;
 
    reg [31:0] s_axis_data_tdata;
    reg s_axis_data_tvalid;
    reg s_axis_data_tlast;
    wire s_axis_data_tready;
 
    wire [31:0] m_axis_data_tdata;
    wire m_axis_data_tvalid;
    wire m_axis_data_tlast;
    wire m_axis_data_tready;
 
    wire event_frame_started;
    wire event_tlast_unexpected;
    wire event_tlast_missing;
    wire event_status_channel_halt;
    wire event_data_in_channel_halt;
    wire event_data_out_channel_halt;
 
    integer i;
    integer out_count;
    integer fft_out_file;   // file handle for CSV export
 
    xfft_sim uut (
        .aclk                        (aclk),
        .s_axis_config_tdata         (s_axis_config_tdata),
        .s_axis_config_tvalid        (s_axis_config_tvalid),
        .s_axis_config_tready        (s_axis_config_tready),
        .s_axis_data_tdata           (s_axis_data_tdata),
        .s_axis_data_tvalid          (s_axis_data_tvalid),
        .s_axis_data_tready          (s_axis_data_tready),
        .s_axis_data_tlast           (s_axis_data_tlast),
        .m_axis_data_tdata           (m_axis_data_tdata),
        .m_axis_data_tvalid          (m_axis_data_tvalid),
        .m_axis_data_tready          (m_axis_data_tready),
        .m_axis_data_tlast           (m_axis_data_tlast),
        .event_frame_started         (event_frame_started),
        .event_tlast_unexpected      (event_tlast_unexpected),
        .event_tlast_missing         (event_tlast_missing),
        .event_status_channel_halt   (event_status_channel_halt),
        .event_data_in_channel_halt  (event_data_in_channel_halt),
        .event_data_out_channel_halt (event_data_out_channel_halt)
    );
 
    initial aclk = 0;
    always #5 aclk = ~aclk;
 
    // --------------------------------------------------------
    // Output capture: count samples + write CSV for Python
    // --------------------------------------------------------
    initial out_count = 0;
 
    initial begin
        fft_out_file = $fopen("fft_output.csv", "w");
        $fwrite(fft_out_file, "bin,real,imag\n");
    end
 
    always @(posedge aclk) begin
        if (m_axis_data_tvalid && m_axis_data_tready) begin
            out_count = out_count + 1;
            // Write bin index, real, imag to CSV
            $fwrite(fft_out_file, "%0d,%0d,%0d\n",
                out_count,
                $signed(m_axis_data_tdata[15:0]),
                $signed(m_axis_data_tdata[31:16]));
        end
    end
 
    // --------------------------------------------------------
    // Event monitor (errors only - keeps waveform clean)
    // --------------------------------------------------------
    always @(posedge aclk) begin
        if (event_tlast_unexpected)
            $display("[%0t] EVENT: tlast_UNEXPECTED", $time);
        if (event_status_channel_halt)
            $display("[%0t] EVENT: status_HALT", $time);
        if (event_data_in_channel_halt)
            $display("[%0t] EVENT: data_in_HALT", $time);
        if (event_data_out_channel_halt)
            $display("[%0t] EVENT: data_out_HALT", $time);
    end
 
    // --------------------------------------------------------
    // Main sequence
    // --------------------------------------------------------
    initial begin
        s_axis_config_tdata  = 16'h0000;
        s_axis_config_tvalid = 1'b0;
        s_axis_data_tdata    = 32'h0000_0000;
        s_axis_data_tvalid   = 1'b0;
        s_axis_data_tlast    = 1'b0;
 
        repeat(200) @(posedge aclk);
 
        // PHASE 1: Config - forward FFT, scaling 2'b10 per stage
        s_axis_config_tdata  = 16'h02AB;
        s_axis_config_tvalid = 1'b1;
        while (!s_axis_config_tready) @(posedge aclk);
        @(posedge aclk);
        s_axis_config_tvalid = 1'b0;
        s_axis_config_tdata  = 16'h0000;
 
        repeat(100) @(posedge aclk);
 
        // PHASE 2: Stream 1024 samples (real ramp, imag=0)
        for (i = 0; i < 1024; i = i + 1) begin
            s_axis_data_tdata  = {16'h0000, i[15:0]};
            s_axis_data_tlast  = (i == 1023) ? 1'b1 : 1'b0;
            s_axis_data_tvalid = 1'b1;
            while (!s_axis_data_tready) @(posedge aclk);
            @(posedge aclk);
        end
 
        s_axis_data_tvalid = 1'b0;
        s_axis_data_tlast  = 1'b0;
        s_axis_data_tdata  = 32'h0000_0000;
 
        // PHASE 3: Wait until all 1024 output samples received
        begin : wait_output
            integer timeout;
            timeout = 0;
            while (out_count < 1024 && timeout < 50000) begin
                @(posedge aclk);
                timeout = timeout + 1;
            end
        end
 
        if (out_count == 1024)
            $display("SUCCESS: All 1024 FFT output samples received. CSV written.");
        else
            $display("TIMEOUT: Only %0d/1024 samples received.", out_count);
 
        $fclose(fft_out_file);
        repeat(50) @(posedge aclk);
        $finish;
    end
 
    assign m_axis_data_tready = 1'b1;
 
endmodule
 
 
 