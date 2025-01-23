VC := xvlog # Verilog compiler
VE := xelab # Verilog elaborator
VS := xsim  # Verilog simulator

DUT_SRC := ../../modules/axi_burst_w.v

SIM_FILES := testbench.sv axi_w_slave_bfm.sv $(DUT_SRC)

SIM_MODULES := testbench
TOP_MODULE := testbench

VC_FLAGS := -sv

USE_WAVE_CONFIG := -view work.$(TOP_MODULE).wcfg

.PHONY: sim guisim clean cleanall

sim: $(SIM_FILES)
	$(VC) $(VC_FLAGS) $^
	$(VE) $(SIM_MODULES) -debug wave
	$(VS) work.$(TOP_MODULE) -R

guisim: $(SIM_FILES)
	$(VC) $(VC_FLAGS) $^
	$(VE) $(SIM_MODULES) -debug wave
	$(VS) work.$(TOP_MODULE) $(USE_WAVE_CONFIG) -gui

clean:
	rm -f *.log *.jou *.wdb

cleanall: clean
	rm -rf *.pb xsim.dir/ .Xil/
