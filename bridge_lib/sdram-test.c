#include <stdio.h>
#include <stdlib.h>

#include <fcntl.h>
#include <sys/mman.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>

#include "sdram.h"


void
sdram_linear_test(
	sdram_t * const sdram,
	const size_t ram_size
)
{
	uint8_t * const mem = calloc(sizeof(*mem), ram_size);

	printf("linear write\n");
	for(size_t i = 0 ; i < ram_size ; i++)
	{
		mem[i] = i & 0xFF; // rand();
		sdram_write(sdram, i, mem[i]);
	}

	printf("linear read\n");
	size_t errors = 0;
	for(size_t i = 0 ; i < ram_size ; i++)
	{
		const uint8_t s = sdram_read(sdram, i);
		if (s == mem[i])
			continue;
		errors++;
		const uint8_t s2 = sdram_read(sdram, i);
		printf("%08x: mem %02x != sdram %02x (%02x%s)\n", i, mem[i], s, s2, mem[i] != s2 ? " !" : "");
	}

	printf("%d errors %.3f%%\n", errors, errors * 100.0 / ram_size);
	free(mem);
}

void
sdram_random_test(
	sdram_t * const sdram,
	const size_t ram_size
)
{
	uint8_t * const mem = calloc(sizeof(*mem), ram_size);

	printf("initialize \n");
	for(size_t i = 0 ; i < ram_size ; i++)
	{
		mem[i] = rand();
		sdram_write(sdram, i, mem[i]);
	}

	size_t errors = 0;
	size_t errors2 = 0;
	for(size_t i = 1 ; i < ram_size * 1024 ; i++)
	{
		if (i % 0x10000 == 0)
			printf("%08x: %d errors %.3f%% (%d second try errors %.3f%%)\n",
				i,
				errors,
				errors * 100.0 / i,
				errors2,
				errors2 * 100.0 / i
			);

		const size_t j = rand() % ram_size;
		const uint8_t s = sdram_read(sdram, j);
		if (s == mem[j])
			continue;

		errors++;

		const uint8_t s2 = sdram_read(sdram, j);
		if (s == mem[j])
			continue;

		// if both reads are consistent, then it is probably
		// a write error
		if (s == s2)
			continue;

		if(0)
		printf("%08x: mem %02x != %02x or %02x\n",
			j,
			mem[j],
			s,
			s2
		);

		errors2++;
	}

	printf("%d errors %.3f%% (%d second try errors %.3f%%)\n",
		errors,
		errors * 100.0 / ram_size,
		errors2,
		errors2 * 100.0 / ram_size
	);

	free(mem);
}

int main(int argc, char **argv)
{
	const size_t ram_size = argc > 1
		? strtol(argv[1], NULL, 0)
		: 0x100000;

	sdram_t * const sdram = sdram_init();

	sdram_linear_test(sdram, ram_size);
	sdram_random_test(sdram, ram_size);

	sdram_close(sdram);

	return 0;
}
