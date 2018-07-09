#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include <fcntl.h>
#include <sys/mman.h>
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


int main(int argc, char **argv)
{
	uint8_t xor = argc > 1 ? strtol(argv[1], NULL, 0) : 0;

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

	printf("writing....\n");
	for (size_t i=0;i<1024;i++) {
		gpmc[i] = i ^ xor;
	}

	printf("read count=%04x\n", gpmc[0]);
	printf("write count=%04x\n", gpmc[1]);

	printf("reading....\n");
	for (size_t i=2;i<1024;i++) {
		for(int j = 0 ; j < 4 ; j++)
		{
			uint16_t data = gpmc[i];
			if (data == (i ^ xor))
				break;

			printf("try %d data[%02x]=%02x%s\n",
				j,
				i,
				data,
				data == (i ^ xor) ? "" : " BAD"
			);
			//usleep(100);
		}
 	}

	printf("read count=%04x\n", gpmc[0]);
	printf("write count=%04x\n", gpmc[1]);

	bridge_close(&br);

	return 0;
}
