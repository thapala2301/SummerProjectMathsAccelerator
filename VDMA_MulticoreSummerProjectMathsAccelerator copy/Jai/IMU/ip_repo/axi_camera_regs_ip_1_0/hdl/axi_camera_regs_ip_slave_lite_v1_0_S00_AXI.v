
`timescale 1 ns / 1 ps

	module axi_camera_regs_ip_slave_lite_v1_0_S00_AXI #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		// Width of S_AXI address bus — 7 bits needed for 17 registers (max addr 0x40)
		parameter integer C_S_AXI_ADDR_WIDTH	= 7
	)
	(
		// Users to add ports here
		output wire [242:0] lookat_flat,
        output wire [80:0]  cam_origin_flat,
        output wire [80:0]  cam_origin_right_flat,
        output wire [31:0]  frame_base_0,
        output wire [31:0]  frame_base_1,
		// User ports ends
		// Do not modify the ports beyond this line

		// Global Clock Signal
		input wire  S_AXI_ACLK,
		// Global Reset Signal. This Signal is Active LOW
		input wire  S_AXI_ARESETN,
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		input wire [2 : 0] S_AXI_AWPROT,
		input wire  S_AXI_AWVALID,
		output wire  S_AXI_AWREADY,
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		input wire  S_AXI_WVALID,
		output wire  S_AXI_WREADY,
		output wire [1 : 0] S_AXI_BRESP,
		output wire  S_AXI_BVALID,
		input wire  S_AXI_BREADY,
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		input wire [2 : 0] S_AXI_ARPROT,
		input wire  S_AXI_ARVALID,
		output wire  S_AXI_ARREADY,
		output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		output wire [1 : 0] S_AXI_RRESP,
		output wire  S_AXI_RVALID,
		input wire  S_AXI_RREADY
	);

	// AXI4LITE signals
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg  	axi_awready;
	reg  	axi_wready;
	reg [1 : 0] 	axi_bresp;
	reg  	axi_bvalid;
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	reg  	axi_arready;
	reg [1 : 0] 	axi_rresp;
	reg  	axi_rvalid;

	// ADDR_LSB = 2 for 32-bit bus
	// OPT_MEM_ADDR_BITS = 4 gives a 5-bit field [6:2] → 32 addressable registers
	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer OPT_MEM_ADDR_BITS = 4;

	// Register map:
	//  [0:8]   lookat          (9 regs, written by IMU at 0x00-0x20)
	//  [9:11]  cam_origin_left (3 regs, written by IMU at 0x24-0x2C)
	//  [12:14] cam_origin_right(3 regs, written by IMU at 0x30-0x38)
	//  [15]    frame_base_0    (written by config.py at 0x3C)
	//  [16]    frame_base_1    (written by config.py at 0x40)
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg4;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg5;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg6;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg7;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg8;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg9;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg10;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg11;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg12;  // cam_origin_right x
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg13;  // cam_origin_right y
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg14;  // cam_origin_right z
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg15;  // frame_base_0
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg16;  // frame_base_1
	integer	 byte_index;

	// I/O Connections assignments
	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY	= axi_wready;
	assign S_AXI_BRESP	= axi_bresp;
	assign S_AXI_BVALID	= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RRESP	= axi_rresp;
	assign S_AXI_RVALID	= axi_rvalid;

	reg [1:0] state_write;
	reg [1:0] state_read;
	localparam Idle = 2'b00, Raddr = 2'b10, Rdata = 2'b11, Waddr = 2'b10, Wdata = 2'b11;

	// Write state machine
	always @(posedge S_AXI_ACLK)
	  begin
	     if (S_AXI_ARESETN == 1'b0)
	       begin
	         axi_awready <= 0;
	         axi_wready <= 0;
	         axi_bvalid <= 0;
	         axi_bresp <= 0;
	         axi_awaddr <= 0;
	         state_write <= Idle;
	       end
	     else
	       begin
	         case(state_write)
	           Idle:
	             begin
	               if(S_AXI_ARESETN == 1'b1)
	                 begin
	                   axi_awready <= 1'b1;
	                   axi_wready <= 1'b1;
	                   state_write <= Waddr;
	                 end
	               else state_write <= state_write;
	             end
	           Waddr:
	             begin
	               if (S_AXI_AWVALID && S_AXI_AWREADY)
	                  begin
	                    axi_awaddr <= S_AXI_AWADDR;
	                    if(S_AXI_WVALID)
	                      begin
	                        axi_awready <= 1'b1;
	                        state_write <= Waddr;
	                        axi_bvalid <= 1'b1;
	                      end
	                    else
	                      begin
	                        axi_awready <= 1'b0;
	                        state_write <= Wdata;
	                        if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
	                      end
	                  end
	               else
	                  begin
	                    state_write <= state_write;
	                    if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
	                   end
	             end
	          Wdata:
	             begin
	               if (S_AXI_WVALID)
	                 begin
	                   state_write <= Waddr;
	                   axi_bvalid <= 1'b1;
	                   axi_awready <= 1'b1;
	                 end
	                else
	                 begin
	                   state_write <= state_write;
	                   if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
	                 end
	             end
	          endcase
	        end
	      end

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
            slv_reg0  <= 32'h01FC0000; // lookat right.x = +1
            slv_reg1  <= 32'h00000000; // lookat right.y = 0
            slv_reg2  <= 32'h00000000; // lookat right.z = 0
            slv_reg3  <= 32'h00000000; // lookat up.x = 0
            slv_reg4  <= 32'h01FC0000; // lookat up.y = +1
            slv_reg5  <= 32'h00000000; // lookat up.z = 0
            slv_reg6  <= 32'h00000000; // lookat fwd.x = 0
            slv_reg7  <= 32'h00000000; // lookat fwd.y = 0
            slv_reg8  <= 32'h05FC0000; // lookat fwd.z = -1
            slv_reg9  <= 32'h00000000; // cam_origin_left x
            slv_reg10 <= 32'h01F0CCCD; // cam_origin_left y = 0.15 (default height)
            slv_reg11 <= 32'h02048000; // cam_origin_left z = 4.5 (default depth)
            slv_reg12 <= 32'h00000000; // cam_origin_right x
            slv_reg13 <= 32'h01F0CCCD; // cam_origin_right y = 0.15
            slv_reg14 <= 32'h02048000; // cam_origin_right z = 4.5
            slv_reg15 <= 32'h00000000; // frame_base_0 (set by config.py at 0x3C)
            slv_reg16 <= 32'h00000000; // frame_base_1 (set by config.py at 0x40)
	    end
	  else begin
	    if (S_AXI_WVALID)
	      begin
	        case ( (S_AXI_AWVALID) ? S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] : axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	          5'h00: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h01: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h02: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg2[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h03: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg3[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h04: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg4[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h05: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg5[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h06: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg6[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h07: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg7[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h08: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg8[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h09: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg9[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h0A: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg10[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h0B: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg11[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h0C: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg12[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h0D: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg13[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h0E: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg14[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h0F: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg15[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          5'h10: for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg16[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
	          default : begin
	                      slv_reg0 <= slv_reg0; slv_reg1 <= slv_reg1; slv_reg2 <= slv_reg2;
	                      slv_reg3 <= slv_reg3; slv_reg4 <= slv_reg4; slv_reg5 <= slv_reg5;
	                      slv_reg6 <= slv_reg6; slv_reg7 <= slv_reg7; slv_reg8 <= slv_reg8;
	                      slv_reg9 <= slv_reg9; slv_reg10 <= slv_reg10; slv_reg11 <= slv_reg11;
	                      slv_reg12 <= slv_reg12; slv_reg13 <= slv_reg13; slv_reg14 <= slv_reg14;
	                      slv_reg15 <= slv_reg15; slv_reg16 <= slv_reg16;
	                    end
	        endcase
	      end
	  end
	end

	// Read state machine
	always @(posedge S_AXI_ACLK)
	  begin
	    if (S_AXI_ARESETN == 1'b0)
	      begin
	       axi_arready <= 1'b0;
	       axi_rvalid <= 1'b0;
	       axi_rresp <= 1'b0;
	       state_read <= Idle;
	      end
	    else
	      begin
	        case(state_read)
	          Idle:
	            begin
	              if (S_AXI_ARESETN == 1'b1)
	                begin
	                  state_read <= Raddr;
	                  axi_arready <= 1'b1;
	                end
	              else state_read <= state_read;
	            end
	          Raddr:
	            begin
	              if (S_AXI_ARVALID && S_AXI_ARREADY)
	                begin
	                  state_read <= Rdata;
	                  axi_araddr <= S_AXI_ARADDR;
	                  axi_rvalid <= 1'b1;
	                  axi_arready <= 1'b0;
	                end
	              else state_read <= state_read;
	            end
	          Rdata:
	            begin
	              if (S_AXI_RVALID && S_AXI_RREADY)
	                begin
	                  axi_rvalid <= 1'b0;
	                  axi_arready <= 1'b1;
	                  state_read <= Raddr;
	                end
	              else state_read <= state_read;
	            end
	         endcase
	        end
	      end

	assign S_AXI_RDATA =
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h00) ? slv_reg0  :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h01) ? slv_reg1  :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h02) ? slv_reg2  :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h03) ? slv_reg3  :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h04) ? slv_reg4  :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h05) ? slv_reg5  :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h06) ? slv_reg6  :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h07) ? slv_reg7  :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h08) ? slv_reg8  :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h09) ? slv_reg9  :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h0A) ? slv_reg10 :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h0B) ? slv_reg11 :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h0C) ? slv_reg12 :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h0D) ? slv_reg13 :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h0E) ? slv_reg14 :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h0F) ? slv_reg15 :
	    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 5'h10) ? slv_reg16 : 32'd0;

	// Output assignments
    assign lookat_flat[26:0]    = slv_reg0[26:0];
    assign lookat_flat[53:27]   = slv_reg1[26:0];
    assign lookat_flat[80:54]   = slv_reg2[26:0];
    assign lookat_flat[107:81]  = slv_reg3[26:0];
    assign lookat_flat[134:108] = slv_reg4[26:0];
    assign lookat_flat[161:135] = slv_reg5[26:0];
    assign lookat_flat[188:162] = slv_reg6[26:0];
    assign lookat_flat[215:189] = slv_reg7[26:0];
    assign lookat_flat[242:216] = slv_reg8[26:0];

    assign cam_origin_flat[26:0]  = slv_reg9[26:0];
    assign cam_origin_flat[53:27] = slv_reg10[26:0];
    assign cam_origin_flat[80:54] = slv_reg11[26:0];

    assign cam_origin_right_flat[26:0]  = slv_reg12[26:0];
    assign cam_origin_right_flat[53:27] = slv_reg13[26:0];
    assign cam_origin_right_flat[80:54] = slv_reg14[26:0];

    assign frame_base_0 = slv_reg15;
    assign frame_base_1 = slv_reg16;

	endmodule
