
################################################################
# This is a generated script based on design: control_bd
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2025.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source control_bd_script.tcl

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7z020clg400-1
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name control_bd

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:processing_system7:5.5\
xilinx.com:user:axi_camera_regs_ip:1.0\
xilinx.com:ip:smartconnect:1.0\
xilinx.com:ip:axi_vdma:6.3\
xilinx.com:ip:v_tc:6.2\
xilinx.com:ip:v_axi4s_vid_out:4.0\
xilinx.com:ip:axi_gpio:2.0\
xilinx.com:ip:xlconstant:1.1\
xilinx.com:ip:xlconcat:2.1\
xilinx.com:ip:axis_subset_converter:1.1\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set DDR [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR ]

  set FIXED_IO [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO ]

  set S_AXI_FB_WR [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_FB_WR ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {32} \
   CONFIG.ARUSER_WIDTH {0} \
   CONFIG.AWUSER_WIDTH {0} \
   CONFIG.BUSER_WIDTH {0} \
   CONFIG.DATA_WIDTH {64} \
   CONFIG.HAS_BRESP {1} \
   CONFIG.HAS_BURST {1} \
   CONFIG.HAS_CACHE {1} \
   CONFIG.HAS_LOCK {1} \
   CONFIG.HAS_PROT {1} \
   CONFIG.HAS_QOS {1} \
   CONFIG.HAS_REGION {1} \
   CONFIG.HAS_RRESP {1} \
   CONFIG.HAS_WSTRB {1} \
   CONFIG.ID_WIDTH {0} \
   CONFIG.MAX_BURST_LENGTH {256} \
   CONFIG.NUM_READ_OUTSTANDING {1} \
   CONFIG.NUM_READ_THREADS {1} \
   CONFIG.NUM_WRITE_OUTSTANDING {1} \
   CONFIG.NUM_WRITE_THREADS {1} \
   CONFIG.PROTOCOL {AXI4} \
   CONFIG.READ_WRITE_MODE {READ_WRITE} \
   CONFIG.RUSER_BITS_PER_BYTE {0} \
   CONFIG.RUSER_WIDTH {0} \
   CONFIG.SUPPORTS_NARROW_BURST {1} \
   CONFIG.WUSER_BITS_PER_BYTE {0} \
   CONFIG.WUSER_WIDTH {0} \
   ] $S_AXI_FB_WR


  # Create ports
  set lookat_flat [ create_bd_port -dir O -from 242 -to 0 lookat_flat ]
  set cam_origin_flat [ create_bd_port -dir O -from 80 -to 0 cam_origin_flat ]
  set frame_base_0 [ create_bd_port -dir O -from 31 -to 0 frame_base_0 ]
  set frame_base_1 [ create_bd_port -dir O -from 31 -to 0 frame_base_1 ]
  set scene_ctrl_flat [ create_bd_port -dir O -from 319 -to 0 scene_ctrl_flat ]
  set pl_axi_aresetn [ create_bd_port -dir I -type rst pl_axi_aresetn ]
  set pixel_aresetn_in [ create_bd_port -dir I -type rst pixel_aresetn_in ]
  set_property CONFIG.POLARITY {ACTIVE_LOW} $pixel_aresetn_in
  set vid_hsync [ create_bd_port -dir O -type data vid_hsync ]
  set vid_vsync [ create_bd_port -dir O -type data vid_vsync ]
  set vid_active [ create_bd_port -dir O -type data vid_active ]
  set vid_data [ create_bd_port -dir O -from 23 -to 0 -type data vid_data ]
  set frame_status [ create_bd_port -dir I -from 1 -to 0 -type data frame_status ]
  set frame_ack [ create_bd_port -dir O -from 0 -to 0 -type data frame_ack ]
  set pl_axi_aclk [ create_bd_port -dir I -type clk -freq_hz 125000000 pl_axi_aclk ]
  set pixel_clk_in [ create_bd_port -dir I -type clk -freq_hz 51206400 pixel_clk_in ]

  # Create instance: processing_system7_0, and set properties
  set processing_system7_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0 ]
  set_property -dict [list \
    CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP1 {1} \
  ] $processing_system7_0


  # Create instance: axi_camera_regs_ip_0, and set properties
  set axi_camera_regs_ip_0 [ create_bd_cell -type ip -vlnv xilinx.com:user:axi_camera_regs_ip:1.0 axi_camera_regs_ip_0 ]

  # Create instance: smartconnect_0, and set properties
  set smartconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0 ]
  set_property CONFIG.NUM_MI {3} $smartconnect_0


  # Create instance: axi_vdma_0, and set properties
  set axi_vdma_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_0 ]
  set_property -dict [list \
    CONFIG.c_include_s2mm {0} \
    CONFIG.c_include_internal_genlock {0} \
    CONFIG.c_mm2s_genlock_mode {0} \
    CONFIG.c_use_fsync {0} \
    CONFIG.c_use_mm2s_fsync {0} \
    CONFIG.c_flush_on_fsync {0} \
    CONFIG.c_num_fstores {2} \
  ] $axi_vdma_0


  # Create instance: v_tc_0, and set properties
  set v_tc_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_tc:6.2 v_tc_0 ]
  set_property -dict [list \
    CONFIG.GEN_F0_VBLANK_HEND {512} \
    CONFIG.GEN_F0_VBLANK_HSTART {512} \
    CONFIG.GEN_F0_VFRAME_SIZE {635} \
    CONFIG.GEN_F0_VSYNC_HEND {512} \
    CONFIG.GEN_F0_VSYNC_HSTART {512} \
    CONFIG.GEN_F0_VSYNC_VEND {615} \
    CONFIG.GEN_F0_VSYNC_VSTART {612} \
    CONFIG.GEN_HACTIVE_SIZE {1024} \
    CONFIG.GEN_HFRAME_SIZE {1344} \
    CONFIG.GEN_HSYNC_END {1204} \
    CONFIG.GEN_HSYNC_START {1184} \
    CONFIG.GEN_VACTIVE_SIZE {600} \
    CONFIG.HAS_AXI4_LITE {false} \
    CONFIG.VIDEO_MODE {Custom} \
    CONFIG.enable_detection {false} \
  ] $v_tc_0


  # Create instance: v_axi4s_vid_out_0, and set properties
  set v_axi4s_vid_out_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out:4.0 v_axi4s_vid_out_0 ]

  # Create instance: axi_gpio_0, and set properties
  set axi_gpio_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0 ]
  set_property -dict [list \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_ALL_OUTPUTS_2 {1} \
    CONFIG.C_GPIO2_WIDTH {1} \
    CONFIG.C_GPIO_WIDTH {2} \
    CONFIG.C_IS_DUAL {1} \
  ] $axi_gpio_0


  # Create instance: smartconnect_fb, and set properties
  set smartconnect_fb [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_fb ]
  set_property CONFIG.NUM_SI {1} $smartconnect_fb


  # Create instance: value_1, and set properties
  set value_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 value_1 ]

  # Create instance: smartconnect_vdma, and set properties
  set smartconnect_vdma [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_vdma ]
  set_property CONFIG.NUM_SI {1} $smartconnect_vdma


  # Create instance: axis_subset_converter_0, and set properties
  set axis_subset_converter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_subset_converter:1.1 axis_subset_converter_0 ]
  set_property -dict [list \
    CONFIG.M_HAS_TKEEP {1} \
    CONFIG.M_HAS_TLAST {1} \
    CONFIG.M_HAS_TREADY {1} \
    CONFIG.M_HAS_TSTRB {0} \
    CONFIG.M_TDATA_NUM_BYTES {3} \
    CONFIG.M_TDEST_WIDTH {0} \
    CONFIG.M_TID_WIDTH {0} \
    CONFIG.M_TUSER_WIDTH {1} \
    CONFIG.S_HAS_TKEEP {1} \
    CONFIG.S_HAS_TLAST {1} \
    CONFIG.S_HAS_TREADY {1} \
    CONFIG.S_HAS_TSTRB {0} \
    CONFIG.S_TDATA_NUM_BYTES {4} \
    CONFIG.S_TDEST_WIDTH {0} \
    CONFIG.S_TID_WIDTH {0} \
    CONFIG.S_TUSER_WIDTH {1} \
    CONFIG.TDATA_REMAP {tdata[23:0]} \
  ] $axis_subset_converter_0

  set_property -dict [list \
    CONFIG.M_HAS_TKEEP.VALUE_MODE {auto} \
    CONFIG.M_HAS_TLAST.VALUE_MODE {auto} \
    CONFIG.M_HAS_TREADY.VALUE_MODE {auto} \
    CONFIG.M_HAS_TSTRB.VALUE_MODE {auto} \
    CONFIG.M_TDEST_WIDTH.VALUE_MODE {auto} \
    CONFIG.M_TID_WIDTH.VALUE_MODE {auto} \
    CONFIG.M_TUSER_WIDTH.VALUE_MODE {auto} \
    CONFIG.S_HAS_TKEEP.VALUE_MODE {auto} \
    CONFIG.S_HAS_TLAST.VALUE_MODE {auto} \
    CONFIG.S_HAS_TREADY.VALUE_MODE {auto} \
    CONFIG.S_HAS_TSTRB.VALUE_MODE {auto} \
    CONFIG.S_TDEST_WIDTH.VALUE_MODE {auto} \
    CONFIG.S_TID_WIDTH.VALUE_MODE {auto} \
    CONFIG.S_TUSER_WIDTH.VALUE_MODE {auto} \
  ] $axis_subset_converter_0


  # Create interface connections
  connect_bd_intf_net -intf_net S_AXI_FB_WR_1 [get_bd_intf_ports S_AXI_FB_WR] [get_bd_intf_pins smartconnect_fb/S00_AXI]
  connect_bd_intf_net -intf_net axi_vdma_0_M_AXIS_MM2S [get_bd_intf_pins axi_vdma_0/M_AXIS_MM2S] [get_bd_intf_pins axis_subset_converter_0/S_AXIS]
  connect_bd_intf_net -intf_net axi_vdma_0_M_AXI_MM2S [get_bd_intf_pins axi_vdma_0/M_AXI_MM2S] [get_bd_intf_pins smartconnect_vdma/S00_AXI]
  connect_bd_intf_net -intf_net axis_subset_converter_0_M_AXIS [get_bd_intf_pins axis_subset_converter_0/M_AXIS] [get_bd_intf_pins v_axi4s_vid_out_0/video_in]
  connect_bd_intf_net -intf_net processing_system7_0_DDR [get_bd_intf_ports DDR] [get_bd_intf_pins processing_system7_0/DDR]
  connect_bd_intf_net -intf_net processing_system7_0_FIXED_IO [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins processing_system7_0/FIXED_IO]
  connect_bd_intf_net -intf_net processing_system7_0_M_AXI_GP0 [get_bd_intf_pins smartconnect_0/S00_AXI] [get_bd_intf_pins processing_system7_0/M_AXI_GP0]
  connect_bd_intf_net -intf_net smartconnect_0_M00_AXI [get_bd_intf_pins axi_camera_regs_ip_0/S00_AXI] [get_bd_intf_pins smartconnect_0/M00_AXI]
  connect_bd_intf_net -intf_net smartconnect_0_M01_AXI [get_bd_intf_pins smartconnect_0/M01_AXI] [get_bd_intf_pins axi_vdma_0/S_AXI_LITE]
  connect_bd_intf_net -intf_net smartconnect_0_M02_AXI [get_bd_intf_pins smartconnect_0/M02_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]
  connect_bd_intf_net -intf_net smartconnect_fb_M00_AXI [get_bd_intf_pins smartconnect_fb/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]
  connect_bd_intf_net -intf_net smartconnect_vdma_M00_AXI [get_bd_intf_pins processing_system7_0/S_AXI_HP1] [get_bd_intf_pins smartconnect_vdma/M00_AXI]
  connect_bd_intf_net -intf_net v_tc_0_vtiming_out [get_bd_intf_pins v_tc_0/vtiming_out] [get_bd_intf_pins v_axi4s_vid_out_0/vtiming_in]

  # Create port connections
  connect_bd_net -net axi_camera_regs_ip_0_cam_origin_flat  [get_bd_pins axi_camera_regs_ip_0/cam_origin_flat] \
  [get_bd_ports cam_origin_flat]
  connect_bd_net -net axi_camera_regs_ip_0_lookat_flat  [get_bd_pins axi_camera_regs_ip_0/lookat_flat] \
  [get_bd_ports lookat_flat]
  connect_bd_net -net axi_camera_regs_ip_0_frame_base_0  [get_bd_pins axi_camera_regs_ip_0/frame_base_0] \
  [get_bd_ports frame_base_0]
  connect_bd_net -net axi_camera_regs_ip_0_frame_base_1  [get_bd_pins axi_camera_regs_ip_0/frame_base_1] \
  [get_bd_ports frame_base_1]
  connect_bd_net -net axi_camera_regs_ip_0_scene_ctrl_flat  [get_bd_pins axi_camera_regs_ip_0/scene_ctrl_flat] \
  [get_bd_ports scene_ctrl_flat]
  connect_bd_net -net axi_gpio_0_gpio2_io_o  [get_bd_pins axi_gpio_0/gpio2_io_o] \
  [get_bd_ports frame_ack]
  connect_bd_net -net frame_status_1  [get_bd_ports frame_status] \
  [get_bd_pins axi_gpio_0/gpio_io_i]
  connect_bd_net -net pixel_aresetn_in_1  [get_bd_ports pixel_aresetn_in] \
  [get_bd_pins v_tc_0/resetn] \
  [get_bd_pins v_axi4s_vid_out_0/aresetn] \
  [get_bd_pins axis_subset_converter_0/aresetn]
  connect_bd_net -net pixel_clk_in_1  [get_bd_ports pixel_clk_in] \
  [get_bd_pins v_tc_0/clk] \
  [get_bd_pins v_axi4s_vid_out_0/aclk] \
  [get_bd_pins axi_vdma_0/m_axis_mm2s_aclk] \
  [get_bd_pins axis_subset_converter_0/aclk]
  connect_bd_net -net s00_axi_aclk_0_1  [get_bd_ports pl_axi_aclk] \
  [get_bd_pins axi_camera_regs_ip_0/s00_axi_aclk] \
  [get_bd_pins smartconnect_0/aclk] \
  [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
  [get_bd_pins axi_gpio_0/s_axi_aclk] \
  [get_bd_pins axi_vdma_0/s_axi_lite_aclk] \
  [get_bd_pins smartconnect_fb/aclk] \
  [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] \
  [get_bd_pins processing_system7_0/S_AXI_HP1_ACLK] \
  [get_bd_pins axi_vdma_0/m_axi_mm2s_aclk] \
  [get_bd_pins smartconnect_vdma/aclk]
  connect_bd_net -net s00_axi_aresetn_0_1  [get_bd_ports pl_axi_aresetn] \
  [get_bd_pins axi_camera_regs_ip_0/s00_axi_aresetn] \
  [get_bd_pins smartconnect_0/aresetn] \
  [get_bd_pins axi_vdma_0/axi_resetn] \
  [get_bd_pins axi_gpio_0/s_axi_aresetn] \
  [get_bd_pins smartconnect_fb/aresetn] \
  [get_bd_pins smartconnect_vdma/aresetn]
  connect_bd_net -net v_axi4s_vid_out_0_vid_active_video  [get_bd_pins v_axi4s_vid_out_0/vid_active_video] \
  [get_bd_ports vid_active]
  connect_bd_net -net v_axi4s_vid_out_0_vid_data  [get_bd_pins v_axi4s_vid_out_0/vid_data] \
  [get_bd_ports vid_data]
  connect_bd_net -net v_axi4s_vid_out_0_vid_hsync  [get_bd_pins v_axi4s_vid_out_0/vid_hsync] \
  [get_bd_ports vid_hsync]
  connect_bd_net -net v_axi4s_vid_out_0_vid_vsync  [get_bd_pins v_axi4s_vid_out_0/vid_vsync] \
  [get_bd_ports vid_vsync]
  connect_bd_net -net v_axi4s_vid_out_0_vtg_ce  [get_bd_pins v_axi4s_vid_out_0/vtg_ce] \
  [get_bd_pins v_tc_0/clken]
  connect_bd_net -net value_1_dout  [get_bd_pins value_1/dout] \
  [get_bd_pins v_tc_0/gen_clken]
  # Create address segments
  assign_bd_address -offset 0x43C00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_camera_regs_ip_0/S00_AXI/S00_AXI_reg] -force
  assign_bd_address -offset 0x41200000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_gpio_0/S_AXI/Reg] -force
  assign_bd_address -offset 0x43000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_vdma_0/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces axi_vdma_0/Data_MM2S] [get_bd_addr_segs processing_system7_0/S_AXI_HP1/HP1_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces S_AXI_FB_WR] [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


