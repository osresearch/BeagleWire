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
sdram_write(
	sdram_t * const sdram,
	uint32_t addr,
	uint8_t value
);

uint8_t
sdram_read(
	sdram_t * const sdram,
	uint32_t addr
);


