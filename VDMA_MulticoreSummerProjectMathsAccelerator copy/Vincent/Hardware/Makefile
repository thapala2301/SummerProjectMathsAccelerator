ROOT = ../..

SRCS = \
	Testbenches_Sim/sim_top.sv \
	RTL/Analytic_SDF/march_core.sv \
	RTL/Analytic_SDF/scene_sdf.v \
	RTL/Analytic_SDF/sdf_term.v \
	RTL/Analytic_SDF/state_pipe.v \
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

NEURAL_SRCS = \
	RTL/Neural_SDF/neural_sdf_top.sv \
	RTL/Neural_SDF/sdf_nn.sv \
	RTL/Neural_SDF/baking_ctrl.sv \
	RTL/Neural_SDF/neuron_layer.sv \
	RTL/Neural_SDF/neuron.sv \
	RTL/Neural_SDF/neuron_ReLu.sv \
	RTL/Neural_SDF/fp_to_q4_12.sv \
	RTL/Neural_SDF/q4_12_to_fp.sv \
	RTL/Neural_SDF/trilinear_interp.sv \
	RTL/Neural_SDF/blend_lerp.sv \
	RTL/Neural_SDF/sdf_bram.sv \
	RTL/Analytic_SDF/state_pipe.v \
	Floating_Point_Lib/fp_add.v \
	Floating_Point_Lib/fp_sub.v \
	Floating_Point_Lib/fp_mul.v \
	Floating_Point_Lib/fp_abs.v \
	Floating_Point_Lib/fp_min.v \
	Floating_Point_Lib/fp_max.v \
	Floating_Point_Lib/int2fp.v

VFLAGS = --cc --exe --build -sv \
	--top-module sim_top \
	-Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH \
	-Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE

NEURAL_VFLAGS = --cc --exe --build -sv \
	--top-module neural_sdf_top \
	-Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH \
	-Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE

all: build run

build:
	verilator $(VFLAGS) $(SRCS) Testbenches_Sim/sim_analytic.cpp -o Vsim_top

run:
	./obj_dir/Vsim_top
	open frame.ppm

neural:
	verilator $(NEURAL_VFLAGS) $(NEURAL_SRCS) Testbenches_Sim/sim_neural.cpp -o Vneural_sdf_top
	./obj_dir/Vneural_sdf_top
	open neural_frame.ppm

clean:
	rm -rf obj_dir frame.ppm neural_frame.ppm
