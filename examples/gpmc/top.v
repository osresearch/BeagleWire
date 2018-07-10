/*
 * Create a memory mapped array on the GPMC bus
 */
module top(
	input		clk,
	inout [15:0]	gpmc_ad,
	input		gpmc_advn,
	input		gpmc_csn1,
	input		gpmc_wein,
	input		gpmc_oen,
	input		gpmc_clk
);

wire sys_clk = clk;

parameter ADDR_WIDTH = 10; // 1024 words
parameter DATA_WIDTH = 16;

reg oe;
reg we;
reg cs;
reg [ADDR_WIDTH-1:0]  addr;
reg [DATA_WIDTH-1:0]  data_rx;
reg [DATA_WIDTH-1:0]  data_tx;
reg [DATA_WIDTH-1:0]  mem[0:(1 << ADDR_WIDTH)-1];

gpmc_sync #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH))
gpmc_controller (
    .clk(sys_clk),

    .gpmc_ad(gpmc_ad),
    .gpmc_advn(gpmc_advn),
    .gpmc_csn1(gpmc_csn1),
    .gpmc_wein(gpmc_wein),
    .gpmc_oen(gpmc_oen),
    .gpmc_clk(gpmc_clk),

    .oen(oe),
    .wen(we),
    .csn(cs),
    .address(addr),
    .data_out(data_rx),
    .data_in(data_tx)
);


reg [15:0] wr_count = 0;
reg [15:0] rd_count = 0;
reg gpmc_in_progress = 0;

always @ (posedge sys_clk)
begin
    if (cs) begin
	// nothing to do until we are selected
	gpmc_in_progress <= 0;
    end else
    if (!we && oe) begin
	// write to the sdram controller.
	gpmc_in_progress <= 1;
	if (!gpmc_in_progress)
		wr_count <= wr_count + 1;

	mem[addr] <= data_rx;

    end else

    if (we && !oe) begin
	gpmc_in_progress <= 1;
	if (!gpmc_in_progress)
		rd_count <= rd_count + 1;

	if (addr == 0)
		data_tx <= rd_count;
	else
	if (addr == 1)
		data_tx <= wr_count;
	else
		data_tx <= mem[addr];

    end
end

endmodule
