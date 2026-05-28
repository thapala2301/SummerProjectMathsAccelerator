@echo off
echo ========================================
echo Running all testbenches
echo ========================================

echo.
echo [1/3] pixel_dispatch
"C:\iverilog\bin\iverilog.exe" -g2012 -o "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\pd_out" "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\pixel_dispatch_tb.sv" "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\pixel_dispatch.sv"
"C:\iverilog\bin\vvp.exe" "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\pd_out"

echo.
echo [2/3] fb_write
"C:\iverilog\bin\iverilog.exe" -g2012 -o "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\fw_out" "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\fb_write_tb.sv" "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\fb_write.sv"
"C:\iverilog\bin\vvp.exe" "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\fw_out"

echo.
echo [3/3] feedback_ctrl
"C:\iverilog\bin\iverilog.exe" -g2012 -o "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\fc_out" "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\feedback_ctrl_tb.sv" "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\feedback_ctrl.sv" "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\FIFO.sv"
"C:\iverilog\bin\vvp.exe" "C:\Users\THAPA\SummerProjectMathsAccelerator\Thanus\fc_out"

echo.
echo ========================================
echo All tests complete
echo ========================================
pause