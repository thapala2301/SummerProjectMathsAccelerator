ROOT = ../..

SRCS = \
	sim_top.sv \
	march_core.sv \
	scene_sdf.v \
	sdf_term.v \
	state_pipe.v \
	Floating_Point_Lib/fp_add.v \
	Floating_Point_Lib/fp_sub.v \
	Floating_Point_Lib/fp_mul.v \
	Floating_Point_Lib/fp_abs.v \
	Floating_Point_Lib/fp_min.v \
	Floating_Point_Lib/fp_max.v \
	Floating_Point_Lib/fp_isqrt.v \
	Floating_Point_Lib/fp_length.v \
	Floating_Point_Lib/fp_negate.v \
	Floating_Point_Lib/int2fp.v \
	$(ROOT)/Jai/ray_gen.sv \
	$(ROOT)/Thanus/feedback_ctrl.sv \
	$(ROOT)/Thanus/FIFO.sv

VFLAGS = --cc --exe --build -sv \
	--top-module sim_top \
	-Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH \
	-Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE

all: build run

build:
	verilator $(VFLAGS) $(SRCS) sim_main.cpp -o Vsim_top

run:
	./obj_dir/Vsim_top
	open frame.ppm

clean:
	rm -rf obj_dir frame.ppm
