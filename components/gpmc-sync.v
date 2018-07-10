module gpmc_sync(
	input                    clk,

	// GPMC INTERFACE
	inout  [15:0]            gpmc_ad,
	input                    gpmc_advn,
	input                    gpmc_csn1,
	input                    gpmc_wein,
	input                    gpmc_oen,
	input                    gpmc_clk,

	// HOST INTERFACE
	output                   oen,
	output                   wen,
	output                   csn,
	output [ADDR_WIDTH-1:0]  address,
	output [DATA_WIDTH-1:0]  data_out,
	input  [DATA_WIDTH-1:0]  data_in
);

parameter ADDR_WIDTH = 16;
parameter DATA_WIDTH = 16;

wire [DATA_WIDTH-1:0] gpmc_data_in;
reg csn_buffered;

/*
 * Tri-State buffer control
 * Output enable is on the host signals, not ours, so that it
 * will transition as soon as the host changes the signals.
 *
 * This does mean that our output might be invalid for a little while,
 * but it should be fixed up before the next GPMC clock.
 */
SB_IO # (
	.PIN_TYPE(6'b1010_01),
	.PULLUP(1'b 0)
) gpmc_ad_io [15:0] (
	.PACKAGE_PIN(gpmc_ad),
	.OUTPUT_ENABLE(!gpmc_csn1 && gpmc_advn && !gpmc_oen && gpmc_wein),
	.D_OUT_0(data_in),
	.D_IN_0(gpmc_data_in)
);


doublebuf #(.WIDTH(ADDR_WIDTH)) gpmc_addr_buffer(
	.clk_in(!gpmc_clk && !gpmc_csn1 && !gpmc_advn && gpmc_wein && gpmc_oen),
	.clk_out(clk),
	.in(gpmc_data_in[ADDR_WIDTH-1:0]),
	.out(address)
);

doublebuf #(.WIDTH(3+DATA_WIDTH)) gpmc_buffer(
	.clk_in(!gpmc_clk),
	.clk_out(clk),
	.in({gpmc_csn1, gpmc_wein, gpmc_oen, gpmc_data_in}),
	.out({csn_buffered, wen, oen, data_out})
);


always @ (posedge clk)
begin
	// sample the double-buffered cs pin on our clock.
	// this fixed all of the read errors in the GPMC test
	csn <= csn_buffered;
end

endmodule
