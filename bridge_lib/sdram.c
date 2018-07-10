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

static inline void mfence(void)
{
	        __asm__ __volatile__("DMB" ::: "memory");
}


#define SDRAM_SR_READ		((1u << 0) | 0xA500)
#define SDRAM_SR_WRITE		((1u << 1) | 0xA500)
#define SDRAM_SR_BUSY		((1u << 2) | 0xA500)
#define SDRAM_SR_READ_READY	((1u << 3) | 0xA500)
#define SDRAM_SR_RESET		((1u << 4) | 0xA500)
#define SDRAM_SR_NONE		(0xA500)

struct _sdram_t // __attribute__((__packed__))
{
	volatile uint16_t sr; // offset 0
	volatile uint16_t addr_lo; // 16 bits, offset 1
	volatile uint16_t addr_hi; //  9 bits, offset 2
	volatile uint16_t wr_data; //  8 bits, offset 3
	volatile uint16_t rd_data; //  8 bits, offset 4
	volatile uint16_t cmd_count; //  16 bits, offset 5
	volatile uint16_t last_cmd; //  16 bits, offset 6
	volatile uint16_t rd_count; //  16 bits, offset 7
};


void
sdram_write(
	sdram_t * const sdram,
	uint32_t addr,
	uint8_t value
) {
	//set sdram address
	sdram->addr_hi = (addr >> 16) & 0x01FF;
	mfence();

	sdram->addr_lo = (addr >>  0) & 0xFFFF;
	mfence();

	//set sdram data
	sdram->wr_data = value;
	mfence();

	//set wr enable flag
	sdram->sr = SDRAM_SR_WRITE;

	//waiting for clr busy bit
	unsigned busy_count = 0;
	if(0) printf("write %08x: %04x => %04x (wr=%04x rd=%04x)\n",
		addr,
		sdram->last_cmd,
		sdram->sr,
		sdram->cmd_count,
		sdram->rd_count
	);
	while (sdram->sr & SDRAM_SR_BUSY)
	{
		busy_count++;
		//printf("sd sr = %04x state = %04x count=%04x\n", sdram->sr, 8[(volatile uint16_t*) sdram], sdram->cmd_count);
	}

	if(busy_count > 1000)
		fprintf(stderr, "write %08x: busy=%u\n", addr, busy_count);
}

uint8_t
sdram_read(
	sdram_t * const sdram,
	uint32_t addr
)
{
	//set sdra, address
	sdram->addr_hi = (addr >> 16) & 0x01FF;
	mfence();
	sdram->addr_lo = (addr >>  0) & 0xFFFF;
	mfence();

	//set rd enable flag
	sdram->sr = SDRAM_SR_READ;
	mfence();

	int busy_count = 0;
	int rd_busy_count =0 ;

	// waiting for clr busy bit
	if(0) printf("%08x: wait busy %04x", addr, sdram->sr);
	while (sdram->sr & SDRAM_SR_BUSY)
		busy_count++;
	if(0) printf(" spin=%u\n", busy_count);


	// waiting for rd ready bit
	if(0) printf("read %08x: %04x => %04x (wr=%04x rd=%04x)\n",
		addr,
		sdram->last_cmd,
		sdram->sr,
		sdram->cmd_count,
		sdram->rd_count
	);
	while (!(sdram->sr & SDRAM_SR_READ_READY))
		rd_busy_count++;
	if (rd_busy_count)
		printf("busy wait %u\n", rd_busy_count);

	// get the data, which will unset the read and ready bit
	const uint8_t val = sdram->rd_data;
	mfence();

	return val;
}


sdram_t *
sdram_init(void)
{
	struct bridge br;
	if (bridge_init(&br, BW_BRIDGE_MEM_ADR, BW_BRIDGE_MEM_SIZE) < 0)
	{
		perror("mmap");
		return NULL;
	}

	sdram_t * const sdram = br.virt_addr;
	printf("sdram=%p\n", sdram);
	printf("sr=%p\n", &sdram->sr);
	printf("addr=%p %p\n", &sdram->addr_lo, &sdram->addr_hi);
	printf("rd_data=%p\n", &sdram->rd_data);

	// assert reset
	sdram->sr = SDRAM_SR_RESET;
	usleep(100000);
	printf("reset\n");
	sdram->sr = SDRAM_SR_NONE;
	usleep(100000);

	return sdram;
}


void
sdram_close(sdram_t * const sdram)
{
	// bridge_close(&br);
}

