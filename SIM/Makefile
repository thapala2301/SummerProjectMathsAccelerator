ROOT := ..

RTL  := $(ROOT)/RTL
FP   := $(RTL)/FP_Lib
CORE := $(RTL)/core
CTRL := $(RTL)/control
VID  := $(RTL)/video
SDF  := $(RTL)/sdf

SRCS = \
	sim_top.sv \
	$(CORE)/march_core.sv \
	$(CORE)/repeat_mod_cell.sv \
	$(CORE)/ray_gen.sv \
	$(CORE)/state_pipe.v \
	$(CORE)/state_pipe_unpacked_array.sv \
	$(SDF)/menger_sdf.sv \
	$(CTRL)/pixel_dispatch.sv \
	$(CTRL)/feedback_ctrl.sv \
	$(CTRL)/FIFO.sv \
	$(VID)/ddr_rgb_writer.sv \
	$(VID)/palette.sv \
	$(FP)/fp_add.v \
	$(FP)/fp_sub.v \
	$(FP)/fp_mul.v \
	$(FP)/fp_abs.v \
	$(FP)/fp_min.v \
	$(FP)/fp_max.v \
	$(FP)/fp_isqrt.v \
	$(FP)/fp_length.v \
	$(FP)/fp_negate.v \
	$(FP)/fp_mod2.v \
	$(FP)/fp_normalize.sv \
	$(FP)/fp_mul_vec3_mat33.sv \
	$(FP)/int2fp.v

VFLAGS = --cc --exe --build -sv \
	--top-module sim_top \
	-Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH \
	-Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
	-Wno-CASEX

VFLAGS_PPM = --cc --exe --build -sv \
	--top-module menger_ppm_top \
	-Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH \
	-Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
	-Wno-CASEX

MENGER_SRCS = \
	menger_ppm_top.sv \
	$(CORE)/repeat_mod_cell.sv \
	$(SDF)/menger_sdf.sv \
	$(CORE)/state_pipe.v \
	$(FP)/fp_add.v \
	$(FP)/fp_sub.v \
	$(FP)/fp_mul.v \
	$(FP)/fp_abs.v \
	$(FP)/fp_min.v \
	$(FP)/fp_max.v \
	$(FP)/fp_mod2.v

all: build run

build:
	verilator $(VFLAGS) $(SRCS) sim_main.cpp -o Vsim_top

run:
	./obj_dir/Vsim_top

# RTL-accurate Menger SDF PPM: spot-checks + 256x256 XY slice render
# Output: menger_rtl.ppm
menger_ppm:
	verilator $(VFLAGS_PPM) $(MENGER_SRCS) tb_menger_ppm_main.cpp -o Vmenger_ppm_top
	./obj_dir/Vmenger_ppm_top

clean:
	rm -rf obj_dir frame.ppm screen.ppm frame.png screen.png menger_rtl.ppm
