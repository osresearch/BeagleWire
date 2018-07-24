#include <stdio.h>
#include <stdlib.h>

#include <fcntl.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>

#include "sdram.h"

void
sdram_single_test(
	sdram_t * const sdram,
	const size_t ram_size
) {
	for(int j = 0 ; j < 8 ; j++)
	{
		const size_t offset = rand() % ram_size;
		size_t errors = 0;

		const uint8_t w = rand() & 0xF0;
		sdram_addr(sdram, offset);
		sdram_write8(sdram, w);

		for(size_t i = 0 ; i < ram_size ; i++)
		{
			sdram_addr(sdram, offset);
			uint8_t r = sdram_read8(sdram);
			if (r == w)
				continue;
			errors++;
		}

		printf("single: %08zx errors %zu %.2f%%\n",
			offset,
			errors,
			errors * 100.0 / ram_size
		);
	}
}

void
sdram_simple_test(
	sdram_t * const sdram,
	const size_t ram_size
) {
	uint8_t offset = time(NULL) & 0xFF;

	printf("%s: writing\n", __func__);
	for(size_t i = 0 ; i < ram_size ; i++)
	{
		uint8_t v = i + offset;
		sdram_write(sdram, i, &v, sizeof(v));
	}

	printf("%s: reading\n", __func__);
	for(size_t i = 0 ; i < ram_size ; i++)
	{
		if (i % 16 == 0)
			printf("%08x:", i);

		uint8_t v;
		sdram_read(sdram, &v, i, sizeof(v));
		printf("%02x ", (uint8_t)(v - offset));

		if (i % 16 == 15)
			printf("\n");
	}
}

void
sdram_bandwidth_test(
	sdram_t * const sdram,
	const size_t ram_size
)
{
	struct timeval start, end, len;
	double delta;
	uint8_t * const mem = calloc(sizeof(*mem), ram_size);

	printf("fast read\n");
	gettimeofday(&start, NULL);
	sdram_read(sdram, mem, 0, ram_size);
	gettimeofday(&end, NULL);
	timersub(&end, &start, &len);
	delta = len.tv_sec * 1e6 + len.tv_usec;

	printf("Read: %d bytes in %.0f usec, %.3f MB/s\n",
		ram_size,
		delta,
		ram_size / delta
	);

	printf("fast write\n");

	gettimeofday(&start, NULL);
	sdram_write(sdram, 0, mem, ram_size);
	gettimeofday(&end, NULL);
	timersub(&end, &start, &len);
	delta = len.tv_sec * 1e6 + len.tv_usec;

	printf("Write: %d bytes in %.0f usec, %.3f MB/s\n",
		ram_size,
		delta,
		ram_size / delta
	);

	free(mem);
}


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
		sdram_addr(sdram, i);
		sdram_write8(sdram, mem[i]);
	}

	printf("linear read\n");
	size_t errors = 0;
	for(size_t i = 0 ; i < ram_size ; i++)
	{
		sdram_addr(sdram, i);
		const uint8_t s = sdram_read8(sdram);
		if (s == mem[i])
			continue;
		errors++;
		sdram_addr(sdram, i);
		const uint8_t s2 = sdram_read8(sdram);

		if(0)
		printf("%08x: mem %02x != sdram %02x (%02x%s)\n", i, mem[i], s, s2, mem[i] != s2 ? " !" : "");
	}

	printf("%d errors %.3f%%\n", errors, errors * 100.0 / ram_size);

	printf("fast read\n");
	uint8_t * const mem2 = calloc(sizeof(*mem), ram_size);
	sdram_read(sdram, mem2, 0, ram_size);

	errors = 0;
	for(size_t i = 0 ; i < ram_size ; i++)
	{
		if (mem[i] != mem2[i])
			errors++;
	}
	printf("%d errors %.3f%%\n", errors, errors * 100.0 / ram_size);

	free(mem);
	free(mem2);
}

void
sdram_random_test(
	sdram_t * const sdram,
	const size_t ram_size
)
{
	uint8_t * const mem = calloc(sizeof(*mem), ram_size);

	printf("random initialize \n");
	for(size_t i = 0 ; i < ram_size ; i++)
		mem[i] = rand();

	sdram_write(sdram, 0, mem, ram_size);

	size_t errors = 0;
	size_t errors2 = 0;
	size_t errors_fail = 0;

	for(size_t i = 1 ; i < ram_size * 1024 ; i++)
	{
		if (i % 0x10000 == 0)
			printf("%08x: %d errors %.3f%% (retries %.3f fail %.3f%%)\n",
				i,
				errors,
				errors * 100.0 / i,
				errors ? errors2 * 1.0 / errors : 0,
				errors ? errors_fail * 100.0 / errors : 0
			);

		const size_t j = rand() % ram_size;
		sdram_addr(sdram, j);
		const uint8_t s = sdram_read8(sdram);
		if (s == mem[j])
			continue;

		errors++;

		for(int retry = 0 ; retry < 32 ; retry++)
		{

			sdram_addr(sdram, j);
			const uint8_t s2 = sdram_read8(sdram);
			if (s2 == mem[j])
			{
				errors2 += retry;
				break;
			}

			if (retry == 31)
				errors_fail++;
		}
	}

	printf("%zu errors %.3f%% (retries avg %.3f%% total fail %zu)\n",
		errors,
		errors * 100.0 / ram_size / 1024.0,
		errors ? errors2 * 100.0 / errors : 0,
		errors_fail
	);

	free(mem);
}

void
sdram_pong_test(
	sdram_t * const sdram,
	const size_t ram_size
) {
	uint32_t a1 = ram_size / 4;
	uint32_t a2 = ram_size / 4 + ram_size / 2;

	uint8_t old1 = random() & 0xFF;
	uint8_t old2 = random() & 0xFF;

	sdram_addr(sdram, a1);
	sdram_write8(sdram, old1);
	sdram_addr(sdram, a2);
	sdram_write8(sdram, old2);

	unsigned errors11 = 0;
	unsigned errors12 = 0;
	unsigned errors21 = 0;
	unsigned errors22 = 0;

	for(int i = 0 ; i < 1024 ; i++)
	{
		sdram_addr(sdram, a1);
		uint8_t val11 = sdram_read8(sdram);
		if (val11 != old1)
			errors11++;

		sdram_addr(sdram, a1);
		uint8_t val12 = sdram_read8(sdram);
		if (val12 != old1)
			errors12++;

		sdram_addr(sdram, a2);
		uint8_t val21 = sdram_read8(sdram);
		if (val21 != old2)
			errors21++;

		sdram_addr(sdram, a2);
		uint8_t val22 = sdram_read8(sdram);
		if (val22 != old2)
			errors22++;

		old1 = random() & 0xFF;
		old2 = random() & 0xFF;

		sdram_addr(sdram, a1);
		sdram_write8(sdram, old1);

		sdram_addr(sdram, a2);
		sdram_write8(sdram, old2);
	}

	printf("errors %d %d / %d %d\n",
		errors11,
		errors12,
		errors21,
		errors22
      );
}

int main(int argc, char **argv)
{
	const size_t ram_size = argc > 1
		? strtol(argv[1], NULL, 0)
		: 0x100000;
	const unsigned seed = argc > 2
		? strtol(argv[2], NULL, 0)
		: time(NULL);
	printf("seed=%d\n", seed);
	srand(seed);

	sdram_t * const sdram = sdram_init();

	sdram_single_test(sdram, 0x10000);
	sdram_simple_test(sdram, 0x100);
	sdram_pong_test(sdram, ram_size);
	sdram_bandwidth_test(sdram, ram_size);
	sdram_linear_test(sdram, ram_size);
	sdram_random_test(sdram, ram_size);

	sdram_close(sdram);

	return 0;
}
