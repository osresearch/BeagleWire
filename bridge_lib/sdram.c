/**
 * \file Host-side interface to the BeagleWire SDRAM controller.
 *
 * This uses the GPMC bus to communicate with the SDRAM controller
 * and is optimized to reduce the number of 16-bit bus transactions
 * required.
 *
 * Reads and Writes are "auto-incrementing" so the address only needs to
 * be updated for a random read.
 *
 * The GPMC interface has three memory mapped registers:
 * Address Low (bits 0-15)
 * Address Hi  (bits 16-25)
 * Data (8 bits) / RD / WR / BUSY / RST
 *
 * To write a value, set the low and hi address registers, then
 * write the data | SDRAM_WR.  Poll the data register
 * until the CMD_WR bit is no longer set.
 * The address auto-increments, so write another byte and poll.
 *
 * To read a value, set the low and hi address registers, then
 * write the data register with SDRAM_RD.  Poll the data register
 * until the RD bit is no longer set and the data will be valid in
 * the lower 8 bits.
 *
 * To reset the SDRAM interface, write the data register with SDRAM_RESET
 * set and poll until it is no longer set.
 */
#include <stdio.h>
#include <stdlib.h>

#include <fcntl.h>
#include <sys/mman.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>

#include "bw_bridge.h"
#include "sdram.h"


#define SDRAM_READ		(1u << 15)
#define SDRAM_WRITE		(1u << 14)
#define SDRAM_RESET		(1u << 13)
#define SDRAM_BUSY		(1u << 12)

// arm-gcc does bad things if __packed__ is enabled
struct bw_sdram_t // __attribute__((__packed__))
{
	volatile uint16_t data; // offset 0
	volatile uint16_t addr_lo; // 16 bits, offset 1
	volatile uint16_t addr_hi; //  9 bits, offset 2
};

struct _sdram_t
{
	struct bridge br;
	struct bw_sdram_t * sd;
};


void
sdram_addr(
	sdram_t * const sdram,
	uint32_t addr
)
{
	sdram->sd->addr_lo = (addr >>  0) & 0xFFFF;
	sdram->sd->addr_hi = (addr >> 16) & 0x01FF;
}


uint32_t
sdram_addr_read(
	sdram_t * const sdram
)
{
	return 0
		| ((sdram->sd->addr_lo <<  0) & 0xFFFF)
		| ((sdram->sd->addr_hi << 16) & 0x01FF);
}


void
sdram_write8(
	sdram_t * const sdram,
	uint8_t value
) {

	sdram->sd->data = value | SDRAM_WRITE;

	// wait for the write to finish
	while(sdram->sd->data & SDRAM_WRITE)
		;
}


void
sdram_write(
	sdram_t * const sdram,
	uint32_t addr,
	const void * buf,
	size_t len
)
{
	sdram_addr(sdram, addr);

	for(size_t i = 0 ; i < len ; i++)
		sdram_write8(sdram, ((const uint8_t*) buf)[i]);
}


uint8_t
sdram_read8(
	sdram_t * const sdram
)
{
	// read the data register until the ready flag bit is set,
	// which will unset the ready bit, so we only have one read
	sdram->sd->data = SDRAM_READ;

	while(1)
	{
		const uint16_t val = sdram->sd->data;
		if ((val & SDRAM_READ) == 0)
			return val & 0xFF;
	}
}


void
sdram_read(
	sdram_t * const sdram,
	void * buf,
	uint32_t addr,
	size_t len
)
{
	sdram_addr(sdram, addr);

	for(size_t i = 0 ; i < len ; i++)
		((uint8_t*)buf)[i] = sdram_read8(sdram);
}



sdram_t *
sdram_init(void)
{
	sdram_t * const sdram = calloc(1, sizeof(*sdram));
	if (!sdram)
		return NULL;

	if (bridge_init(&sdram->br, BW_BRIDGE_MEM_ADR, BW_BRIDGE_MEM_SIZE) < 0)
	{
		free(sdram);
		return NULL;
	}

	sdram->sd = sdram->br.virt_addr;

	// assert reset
	sdram->sd->data = SDRAM_RESET;
	usleep(10000);
	sdram->sd->data = 0;
	usleep(100000);

	return sdram;
}


void
sdram_close(sdram_t * const sdram)
{
	bridge_close(&sdram->br);
	free(sdram);
}

