#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include <fcntl.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>

#include "bw_bridge.h"

static inline void mfence(void)
{
	__asm__ __volatile__("DMB" ::: "memory");
}

#define MEM_SIZE 1024
static uint16_t mem[MEM_SIZE];


int main(int argc, char **argv)
{
	unsigned int seed = argc > 1 ? strtoul(argv[1], NULL, 0) : 0;

	struct bridge br;
	if (bridge_init(&br, BW_BRIDGE_MEM_ADR, BW_BRIDGE_MEM_SIZE) < 0)
	{
		perror("mmap");
		return 1;
	}

	volatile uint16_t * const gpmc = br.virt_addr;
	printf("gpmc=%p\n", gpmc);
	printf("read count=%04x\n", gpmc[0]);
	printf("write count=%04x\n", gpmc[1]);

	// do a linear pass to verify simple behaviour
	srand(seed);

	uint16_t xor = rand();

	printf("writing....\n");
	for (size_t i=2 ; i < MEM_SIZE ; i++)
		mem[i] = gpmc[i] = i ^ xor;

	printf("read count=%04x\n", gpmc[0]);
	printf("write count=%04x\n", gpmc[1]);

	printf("reading....\n");
	for (size_t i=2;i<1024;i++) {
		for(int j = 0 ; j < 4 ; j++)
		{
			const uint16_t data = gpmc[i];
			if (data == mem[i])
				break;

			printf("try %d data[%02x] = %04x != %04x%s\n",
				j,
				i,
				data,
				mem[i],
				data == mem[i] ? "" : " BAD"
			);
			//usleep(100);
		}
 	}

	printf("read count=%04x\n", gpmc[0]);
	printf("write count=%04x\n", gpmc[1]);

	// do a random stress test until we're killed
	size_t errors = 0;
	for(size_t t = 1 ; t < MEM_SIZE * MEM_SIZE ; t++)
	{
		uint16_t i = rand() % MEM_SIZE;
		if (i == 0 || i == 1)
			continue;

		uint16_t g = gpmc[i];
		uint16_t m = mem[i];

		if (g != m)
		{
			//printf("%04x: gpmc=%04x mem=%04x\n", i, g, m);
			errors++;
		}

		gpmc[i] = mem[i] = rand();

		if (t % 0x10000 == 0)
			printf("%08x: %d errors %.3f%%\n",
				t,
				errors,
				errors * 100.0 / t
			);
	}
				
	struct timeval start, end, len;
	double delta;
	const int iters = 4096;

	printf("time write\n");
	gettimeofday(&start, NULL);
	for (int iter = 0 ; iter < iters ; iter++)
		for (size_t i=2 ; i < MEM_SIZE ; i++)
			gpmc[i] = i ^ xor;
	gettimeofday(&end, NULL);
	timersub(&end, &start, &len);
	delta = len.tv_sec * 1e6 + len.tv_usec;
	printf("write %d words in %.6f sec = %.3f MT/s\n",
		iters * MEM_SIZE,
		delta * 1e-6,
		iters * MEM_SIZE / delta
	);

	printf("time read\n");
	errors = 0;
	gettimeofday(&start, NULL);
	for (int iter = 0 ; iter < iters ; iter++)
		for (size_t i=2 ; i < MEM_SIZE ; i++)
		{
			if (gpmc[i] != (i ^ xor))
				errors++;
		}
	gettimeofday(&end, NULL);
	timersub(&end, &start, &len);
	delta = len.tv_sec * 1e6 + len.tv_usec;

	printf("read %d words in %.6f sec = %.3f MT/s errors=%d\n",
		iters * MEM_SIZE,
		delta * 1e-6,
		iters * MEM_SIZE / delta,
		errors
	);

	bridge_close(&br);

	return 0;
}
