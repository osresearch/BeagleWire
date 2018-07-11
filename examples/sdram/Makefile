PROJ = sdram
all: $(PROJ).bin $(PROJ).timing

SRC += top.v
SRC += ../../components/gpmc-sync.v
SRC += ../../components/doublebuf.v
SRC += ../../components/pulsestretch.v
SRC += ../../components/sdram_controller.v

TEST-y += sdram_testbench

sdram_testbench.vvp: sdram-test.v ../../components/sdram_controller.v

include ../Makefile.beaglewire
