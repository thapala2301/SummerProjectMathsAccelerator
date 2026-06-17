ROOT := ..

SRCS = \
	sim_top.sv \
	$(ROOT)/rtl/core/march_core.sv \
	$(ROOT)/rtl/core/repeat_cell.sv \
	$(ROOT)/rtl/sdf/scaffold_sdf.v \
	$(ROOT)/rtl/sdf/twisted_torus_sdf.v \
	$(ROOT)/rtl/core/state_pipe.v \
	$(ROOT)/rtl/core/ray_gen.sv \
	$(ROOT)/rtl/control/pixel_dispatch.sv \
	$(ROOT)/rtl/control/feedback_ctrl.sv \
	$(ROOT)/rtl/control/FIFO.sv \
	$(ROOT)/rtl/video/ddr_rgb_writer.sv \
	$(ROOT)/rtl/video/palette.sv \
	$(ROOT)/rtl/fp/fp_add.v \
	$(ROOT)/rtl/fp/fp_sub.v \
	$(ROOT)/rtl/fp/fp_mul.v \
	$(ROOT)/rtl/fp/fp_abs.v \
	$(ROOT)/rtl/fp/fp_min.v \
	$(ROOT)/rtl/fp/fp_max.v \
	$(ROOT)/rtl/fp/fp_isqrt.v \
	$(ROOT)/rtl/fp/fp_length.v \
	$(ROOT)/rtl/fp/fp_negate.v \
	$(ROOT)/rtl/fp/int2fp.v

VFLAGS = --cc --exe --build -sv \
	--top-module sim_top \
	-Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH \
	-Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
	-Wno-CASEX

all: build run

build:
	verilator $(VFLAGS) $(SRCS) sim_main.cpp -o Vsim_top

run:
	./obj_dir/Vsim_top
	powershell.exe -ExecutionPolicy Bypass -File "$$(wslpath -w $(CURDIR))/convert_ppm_to_png.ps1"

test-fp:
	verilator --cc --exe --build -sv \
		--top-module fp_test_top \
		-Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH \
		-Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
		fp_test_top.sv \
		tb_fp_ops_main.cpp \
		$(ROOT)/rtl/fp/fp_add.v \
		$(ROOT)/rtl/fp/fp_sub.v \
		$(ROOT)/rtl/fp/fp_mul.v \
		$(ROOT)/rtl/fp/fp_abs.v \
		$(ROOT)/rtl/fp/fp_min.v \
		$(ROOT)/rtl/fp/fp_max.v \
		$(ROOT)/rtl/fp/fp_isqrt.v \
		$(ROOT)/rtl/fp/int2fp.v \
		$(ROOT)/rtl/core/state_pipe.v \
		-o Vtb_fp_ops
	./obj_dir/Vtb_fp_ops

test-ray:
	verilator --cc --exe --build -sv \
		--top-module ray_gen_test_top \
		-Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH \
		-Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
		ray_gen_test_top.sv \
		tb_ray_gen_main.cpp \
		$(ROOT)/rtl/core/ray_gen.sv \
		$(ROOT)/rtl/core/state_pipe.v \
		$(ROOT)/rtl/fp/fp_add.v \
		$(ROOT)/rtl/fp/fp_sub.v \
		$(ROOT)/rtl/fp/fp_mul.v \
		$(ROOT)/rtl/fp/fp_abs.v \
		$(ROOT)/rtl/fp/fp_min.v \
		$(ROOT)/rtl/fp/fp_max.v \
		$(ROOT)/rtl/fp/fp_isqrt.v \
		-o Vtb_ray_gen
	./obj_dir/Vtb_ray_gen

test-sdf:
	verilator --cc --exe --build -sv \
		--top-module scene_sdf_test_top \
		-Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH \
		-Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
		scene_sdf_test_top.sv \
		tb_scene_sdf_main.cpp \
		$(ROOT)/rtl/core/repeat_cell.sv \
		$(ROOT)/rtl/sdf/scaffold_sdf.v \
		$(ROOT)/rtl/sdf/twisted_torus_sdf.v \
		$(ROOT)/rtl/core/state_pipe.v \
		$(ROOT)/rtl/fp/fp_add.v \
		$(ROOT)/rtl/fp/fp_sub.v \
		$(ROOT)/rtl/fp/fp_mul.v \
		$(ROOT)/rtl/fp/fp_abs.v \
		$(ROOT)/rtl/fp/fp_min.v \
		$(ROOT)/rtl/fp/fp_max.v \
		$(ROOT)/rtl/fp/fp_isqrt.v \
		$(ROOT)/rtl/fp/fp_length.v \
		-o Vtb_scene_sdf
	./obj_dir/Vtb_scene_sdf

test-length:
	verilator --cc --exe --build -sv \
		--top-module fp_length_test_top \
		-Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH \
		-Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
		fp_length_test_top.sv \
		tb_fp_length_main.cpp \
		$(ROOT)/rtl/fp/fp_add.v \
		$(ROOT)/rtl/fp/fp_sub.v \
		$(ROOT)/rtl/fp/fp_mul.v \
		$(ROOT)/rtl/fp/fp_abs.v \
		$(ROOT)/rtl/fp/fp_min.v \
		$(ROOT)/rtl/fp/fp_max.v \
		$(ROOT)/rtl/fp/fp_isqrt.v \
		$(ROOT)/rtl/fp/fp_length.v \
		$(ROOT)/rtl/core/state_pipe.v \
		-o Vtb_fp_length
	./obj_dir/Vtb_fp_length

test-march:
	verilator --cc --exe --build -sv \
		--top-module march_trace_top \
		-Wno-TIMESCALEMOD -Wno-UNOPTFLAT -Wno-WIDTH \
		-Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
		march_trace_top.sv \
		tb_march_trace_main.cpp \
		$(ROOT)/rtl/core/march_core.sv \
		$(ROOT)/rtl/core/repeat_cell.sv \
		$(ROOT)/rtl/core/ray_gen.sv \
		$(ROOT)/rtl/sdf/scaffold_sdf.v \
		$(ROOT)/rtl/core/state_pipe.v \
		$(ROOT)/rtl/fp/fp_add.v \
		$(ROOT)/rtl/fp/fp_sub.v \
		$(ROOT)/rtl/fp/fp_mul.v \
		$(ROOT)/rtl/fp/fp_abs.v \
		$(ROOT)/rtl/fp/fp_min.v \
		$(ROOT)/rtl/fp/fp_max.v \
		$(ROOT)/rtl/fp/fp_isqrt.v \
		$(ROOT)/rtl/fp/fp_length.v \
		$(ROOT)/rtl/fp/int2fp.v \
		-o Vtb_march_trace
	./obj_dir/Vtb_march_trace

clean:
	rm -rf obj_dir frame.ppm screen.ppm frame.png screen.png
