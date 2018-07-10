#pragma once
#include <stdint.h>

typedef struct _sdram_t sdram_t;

sdram_t *
sdram_init(void);

void
sdram_close(
	sdram_t * const sdram
);

void
sdram_addr(
	sdram_t * const sdram,
	uint32_t addr
);

uint8_t
sdram_read8(
	sdram_t * const sdram
);


void
sdram_write8(
	sdram_t * const sdram,
	uint8_t val
);

void
sdram_write(
	sdram_t * const sdram,
	uint32_t addr,
	const void * value,
	size_t len
);

void
sdram_read(
	sdram_t * const sdram,
	void * value,
	uint32_t addr,
	size_t len
);



