module top( input         clk,
            inout  [15:0] gpmc_ad,
            input         gpmc_advn,
            input         gpmc_csn1,
            input         gpmc_wein,
            input         gpmc_oen,
            input         gpmc_clk,
            
/*
            input  [1:0]  btn,
            input  [1:0]  sw,
            output [3:0]  led,

            output [7:0]  pmod1,
            output [7:0]  pmod2,
            output [7:0]  pmod3,
            output [7:0]  pmod4,
*/

            output [12:0] sdram_addr,
            inout  [7:0]  sdram_data,
            output [1:0]  sdram_bank,

            output        sdram_clk,
            output        sdram_cke,
            output        sdram_we,
            output        sdram_cs,
            output        sdram_dqm,
            output        sdram_ras,
            output        sdram_cas);

parameter ADDR_WIDTH = 4;
parameter DATA_WIDTH = 16;

localparam
	SDRAM_CMD_READ	= 15,
	SDRAM_CMD_WRITE	= 14,
	SDRAM_CMD_RESET	= 13,
	SDRAM_CMD_BUSY	= 12;

localparam SD_ADDR_WIDTH = 25;

wire sys_clk = clk;

reg oen;
reg wen;
reg csn;
reg [ADDR_WIDTH-1:0]  gpmc_addr;
reg [DATA_WIDTH-1:0]  data_out;
reg [DATA_WIDTH-1:0]  data_in;

reg [SD_ADDR_WIDTH-1:0] sd_addr; // sent to the SDRAM controller
reg [SD_ADDR_WIDTH-1:0] addr; // local buffer for auto-increment

reg [7:0]  sd_rd_data;
reg [7:0]  sd_wr_data;
reg        sd_wr_enable;
reg        sd_rd_enable;
reg        sd_busy;
reg        sd_ack;
reg        sd_rd_ready; 
reg        sd_rst;

reg rd_in_progress = 0;
reg wr_in_progress = 0;

reg [7:0] rd_data = 0;

reg gpmc_in_progress = 0;
reg [15:0] cmd_count = 0;
reg [15:0] last_sr = 0;
reg [15:0] rd_count = 0;

always @ (posedge sys_clk)
begin
    if (sd_ack) begin
        // once the SDRAM has acknowledged our command,
        // unset our command flags
	sd_rd_enable <= 0;
	sd_wr_enable <= 0;
    end else
    if (sd_busy && wr_in_progress) begin
        // once the SDRAM has started the busy cycle,
	// unlatch our write-in-progress
	wr_in_progress <= 0;
    end else
    if (sd_rd_ready) begin
	// new data from the SDRAM is ready; unlatch the ready bit
	rd_in_progress <= 0;
	rd_data <= sd_rd_data;
    end

    if (csn) begin
	// if the FPGA is not selected, there is nothing else to do
	gpmc_in_progress <= 0;
    end else
    if (!wen && oen && !gpmc_in_progress) begin
	// write command from the host to the fpga
	gpmc_in_progress <= 1;

	case(gpmc_addr)
	0: begin
		// data + cmd register
		sd_rd_enable	<= data_out[SDRAM_CMD_READ];
		rd_in_progress	<= data_out[SDRAM_CMD_READ];
		sd_wr_enable	<= data_out[SDRAM_CMD_WRITE];
		wr_in_progress	<= data_out[SDRAM_CMD_WRITE];
		sd_rst		<= data_out[SDRAM_CMD_RESET];
		sd_wr_data	<= data_out[7:0];

		// if this is a read/write operation, update
		// the SDRAM's address field and auto-increment ours
		if (data_out[SDRAM_CMD_READ]
		|| data_out[SDRAM_CMD_WRITE])
		begin
			sd_addr <= addr;
			addr <= addr + 1;
		end
	end
	1: addr[15:0] <= data_out[15:0]; // low 16 bits
	2: addr[SD_ADDR_WIDTH-1:16] <= data_out[(SD_ADDR_WIDTH-16-1):0]; // high 9 bits
	endcase
    end else
    if (wen && !oen && !gpmc_in_progress) begin
	// read command from the host of the fpga's registers
	gpmc_in_progress <= 1;

	case(gpmc_addr)
	0: begin
		// fill in the status register bits
		data_in <= 0;
		data_in[SDRAM_CMD_READ]		<= rd_in_progress;
		data_in[SDRAM_CMD_WRITE]	<= wr_in_progress || sd_busy;
		data_in[SDRAM_CMD_RESET]	<= sd_rst;
		data_in[SDRAM_CMD_BUSY]		<= sd_busy;
		data_in[7:0]			<= rd_data;
	end
	1: data_in <= { addr[15:0] };
	2: data_in <= { 7'h0, addr[SD_ADDR_WIDTH-1:16] };
	endcase
    end

end


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

    .oen(oen),
    .wen(wen),
    .csn(csn),
    .address(gpmc_addr),
    .data_out(data_out),
    .data_in(data_in)
);

// the sdram is clocked on the rising edge, but that is when all of
// our states change.  invert the clock so that the FPGA's falling edges
// (when the states are stable) is the SDRAM's failing edges
assign sdram_clk = !sys_clk;

sdram_controller sdram_controller_1 (
    .wr_addr(sd_addr),
    .wr_enable(sd_wr_enable),
    .wr_data(sd_wr_data),

    .rd_addr(sd_addr),
    .rd_enable(sd_rd_enable),
    .rd_data(sd_rd_data),
    .rd_ready(sd_rd_ready),
    .busy(sd_busy),
    .ack(sd_ack),
    
    .clk(sys_clk),
    .rst_n(!sd_rst),

    .sd_clk(sdram_clk),
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

endmodule
