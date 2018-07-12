ARCH = arm
CROSS ?= arm-linux-gnueabihf-
CC = $(CROSS)gcc
PWD := $(shell pwd)

CFLAGS = \
        -std=c99 \
	-g \
	-O3 \
        -W \
        -Wall \
        -Wextra \
	-D_DEFAULT_SOURCE \
	-Wp,-MMD,$(dir $@).$(notdir $@).d \
        -Wp,-MT,$@ \

bins-y += sdram
bins-y += i2c
bins-y += main
bins-y += gpmc

all: $(bins-y)

$(bins-y):
	$(CC) -o $@ $^

sdram: sdram-test.o sdram.o bw_bridge.o
i2c: i2c_br.o bw_bridge.o
main: main.o bw_bridge.o
gpmc: gpmc.o bw_bridge.o

clean:
	$(RM) *.o *~ $(bins-y) .*.d

-include .*.d
