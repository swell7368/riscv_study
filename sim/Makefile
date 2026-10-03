MILL ?= $(HOME)/bin/mill
CONFIG ?= freechips.rocketchip.system.TinyConfig
ROCKETCHIP_DIR := ../third_party/rocket-chip

.PHONY: verilog xbar-compile xbar-elf clean

verilog:
	cd $(ROCKETCHIP_DIR) && $(MILL) 'emulator[freechips.rocketchip.system.TestHarness,$(CONFIG)].mfccompiler.compile'

xbar-compile:
	cd $(ROCKETCHIP_DIR) && $(MILL) 'emulator[freechips.rocketchip.unittest.TestHarness,freechips.rocketchip.unittest.TLXbarUnitTestConfig].mfccompiler.compile'

xbar-elf:
	cd $(ROCKETCHIP_DIR) && $(MILL) 'emulator[freechips.rocketchip.unittest.TestHarness,freechips.rocketchip.unittest.TLXbarUnitTestConfig].elf'

clean:
	cd $(ROCKETCHIP_DIR) && rm -rf out
