PROJ = sdram
SRC += top.v
SRC += ../../components/gpmc-sync.v
SRC += ../../components/doublebuf.v
SRC += ../../components/pulsestretch.v
SRC += ../../components/sdram_controller.v

all: $(PROJ).bin $(PROJ).timing
include ../Makefile.beaglewire
