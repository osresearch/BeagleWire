module SB_IO(
	inout PACKAGE_PIN,
	input OUTPUT_ENABLE,
	input D_OUT_0,
	output D_IN_0
);
parameter PIN_TYPE = 0;
parameter PULLUP = 0;

endmodule


module sdram_testbench;
reg clk;
wire [4:0] state;
wire [7:0] command;
reg sd_wr_enable = 0;
reg sd_rd_enable = 0;
wire [7:0]  sd_rd_data;
wire [7:0]  sd_wr_data;
wire sd_rd_ready;
reg sd_rst = 0;
wire sd_ack;
wire sd_busy;

localparam SD_ADDR_WIDTH = 25;
reg [SD_ADDR_WIDTH-1:0] sd_addr; // sent to the SDRAM controller

            wire [12:0] sdram_addr;
            wire [7:0]  sdram_data;
            wire [1:0]  sdram_bank;

            wire        sdram_clk;
            wire        sdram_cke;
            wire        sdram_we;
            wire        sdram_cs;
            wire        sdram_dqm;
            wire        sdram_ras;
            wire        sdram_cas;


sdram_controller sdram(
    .wr_addr(sd_addr),
    .wr_enable(sd_wr_enable),
    .wr_data(sd_wr_data),

    .rd_addr(sd_addr),
    .rd_enable(sd_rd_enable),
    .rd_data(sd_rd_data),
    .rd_ready(sd_rd_ready),
    .busy(sd_busy),
    .ack(sd_ack),
    
    .clk(clk),
    .rst_n(!sd_rst),

	.state_debug(state),
	.command_debug(command),

    .addr(sdram_addr),
    .bank_addr(sdram_bank),
    .data(sdram_data),
    .clock_enable(sdram_cke),
    .cs_n(sdram_cs),
    .ras_n(sdram_ras),
    .cas_n(sdram_cas),
    .we_n(sdram_we),
    .data_mask(sdram_dqm)
);

initial begin
	clk = 0;
end

// Step the clock every 5 cycles, so 10 cycles == 1 pulse
always #5 clk = !clk;

always #1 $display("%6d: %b state=%b cmd=%b addr=%b rd=%b ack=%b ready=%b",
		$time,
		clk,
		state,
		command,
		sdram_addr,
		sd_rd_enable,
		sd_ack,
		sd_rd_ready
	);

always begin
	#10 sd_addr <= 25'hECAFBAD;

	#10 sd_rst = 0;

	#150 sd_rd_enable = 1;
	#80 sd_rd_enable = 0;

	#1000 $finish;
end

always @(posedge clk)
	if (sd_ack) begin
		sd_rd_enable <= 0;
		sd_wr_enable <= 0;
	end


endmodule
