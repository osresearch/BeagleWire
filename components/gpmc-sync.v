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

reg [DATA_WIDTH-1:0] gpmc_data_out;
wire [DATA_WIDTH-1:0] gpmc_data_in_raw;
reg [DATA_WIDTH-1:0] gpmc_data_in;
reg advn;

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
	.D_OUT_0(gpmc_data_out),
	.D_IN_0(gpmc_data_in_raw)
);


/* Clock crossing buffer for the entirety of the data */
doublebuf #(.WIDTH(DATA_WIDTH)) gpmc_data_buf(
	.clk_in(!gpmc_clk),
	.clk_out(clk),
	.in(gpmc_data_in_raw),
	.out(gpmc_data_in)
);

/* Clock crossing buffer for the control lines */
doublebuf #(.WIDTH(4)) gpmc_control_buf(
	.clk_in(!gpmc_clk),
	.clk_out(clk),
	.in({gpmc_oen, gpmc_wein, gpmc_csn1, gpmc_advn}),
	.out({oen, wen, csn, advn})
);


always @ (posedge clk)
begin
	// always copy the user data to the output register
	// even if this is not an output cycle
	gpmc_data_out <= data_in;

	// we have been selected and the clock edge is falling
	if (!csn && !advn && wen && oen)
	begin
		// this cycle clocks in the address
		address <= gpmc_data_in[ADDR_WIDTH-1:0];
	end

	if (!csn && advn && !wen && oen) begin
		// this cycle has data from the host
		data_out <= gpmc_data_in;
	end
end

endmodule
