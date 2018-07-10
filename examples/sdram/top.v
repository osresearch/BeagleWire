module top( input         clk,
            inout  [15:0] gpmc_ad,
            input         gpmc_advn,
            input         gpmc_csn1,
            input         gpmc_wein,
            input         gpmc_oen,
            input         gpmc_clk,
            
            input  [1:0]  btn,
            input  [1:0]  sw,
            output [3:0]  led,

            output [7:0]  pmod1,
            output [7:0]  pmod2,
            output [7:0]  pmod3,
            output [7:0]  pmod4,

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

wire sys_clk = clk; // not clk_200 for now

reg oen;
reg wen;
reg csn;
reg [ADDR_WIDTH-1:0]  gpmc_addr;
reg [DATA_WIDTH-1:0]  data_out;
reg [DATA_WIDTH-1:0]  data_in;

reg [24:0]  sd_addr;
reg [7:0]  sd_rd_data;
reg  [7:0]  sd_wr_data;
reg         sd_wr_enable;
reg         sd_rd_enable;
reg        sd_busy;
reg         sd_ack;
reg        sd_rd_ready; 
reg         sd_rst;

// debugging
reg [7:0] sd_command;
reg [4:0] sd_state;


// the SDRAM doesn't respond with busy immediately, so we
// have our own busy signal until it does.
reg busy_wait = 0;
reg sd_rd_ready_stretch;
reg sd_busy_stretch;
pulsestretch #(.LENGTH(8)) stretch0(sys_clk, sd_rd_ready, sd_rd_ready_stretch);
pulsestretch #(.LENGTH(17)) stretch1(sys_clk, sd_busy, sd_busy_stretch);


reg rd_ready = 0;
reg [7:0] rd_data = 0;

reg in_progress = 0;
reg [15:0] cmd_count = 0;
reg [15:0] last_sr = 0;
reg [15:0] rd_count = 0;

always @ (posedge sys_clk)
begin
    // once the SDRAM has acknowledged our command, unset our busy flags
    if (sd_ack) begin
	sd_rd_enable <= 0;
	sd_wr_enable <= 0;
        busy_wait <= 0;
    end

    if (sd_rd_ready) begin
	// new data from the SDRAM is ready; latch the ready bit
	rd_ready <= 1;
	rd_data <= sd_rd_data;
	rd_count <= rd_count + 1;
    end

    if (csn) begin
	in_progress <= 0;
    end else
    if (!wen && oen) begin
	if (!in_progress)
		cmd_count <= cmd_count + 1;
	in_progress <= 1;

	// default is to restore everything to a known state
	//sd_rst <= 0;

	// GPMC writes destroy any pending reads

	case(gpmc_addr)
	0: begin
		// update the status register flags
		// if both read and write are specified, only read
		if (data_out[15:8] != 8'hA5)
			last_sr <= data_out;
		else begin
		sd_rd_enable <= data_out[0];
		sd_wr_enable <= data_out[1];
		sd_rst <= data_out[4];

		// if we are doing a read or write op, go ahead
		// and set our busy flag until the SDRAM acks the command
		busy_wait <= data_out[0] || data_out[1];
		end
	end
	1: begin
		sd_addr[15:0] <= data_out[15:0]; // 16 bits
	end
	2: begin
		sd_addr[24:16] <= data_out[8:0]; // 9 bits
	end
	3: begin
		sd_wr_data <= data_out[7:0];
	end
	endcase
    end else
    if (wen && !oen) begin
	case(gpmc_addr)
	0: begin
		// fill in the read-side of the status register
		data_in[0] <= sd_rd_enable;
		data_in[1] <= sd_wr_enable;
		//data_in[2] <= sd_busy_stretch;

		// we are waiting for either the real busy
		// or the ack to our command
		data_in[2] <= sd_busy || busy_wait;

		data_in[3] <= rd_ready;
		data_in[4] <= sd_rst;
		data_in[5] <= sd_busy;
		data_in[6] <= sd_ack;
		data_in[15:7] <= 0;
		//data_in[15:8] <= last_sr; // cmd_count;
		//data_in[15:4] <= cmd_count;
	end
	4: begin
		// read the data and reset the rd_ready flag
		rd_ready <= 0;
		data_in[7:0] <= rd_data;
		data_in[15:8] <= 0;
	end
	5: data_in <= cmd_count;
	6: data_in <= last_sr;
	7: data_in <= rd_count;
	8: data_in <= { sd_state, sd_command };
	endcase
    end

end

/*
icepll -i 100 -o 200

F_PLLIN:   100.000 MHz (given)
F_PLLOUT:  200.000 MHz (requested)
F_PLLOUT:  200.000 MHz (achieved)

FEEDBACK: SIMPLE
F_PFD:  100.000 MHz
F_VCO:  800.000 MHz

DIVR:  0 (4'b0000)
DIVF:  7 (7'b0000111)
DIVQ:  2 (3'b010)

FILTER_RANGE: 5 (3'b101)
*/

wire clk_200;
wire lock;

SB_PLL40_CORE #(
    .FEEDBACK_PATH("SIMPLE"),
    .PLLOUT_SELECT("GENCLK"),
    .DIVR(4'b0000),
    .DIVF(7'b0000111),
    .DIVQ(3'b010),
    .FILTER_RANGE(3'b101)
) uut (
    .LOCK(lock),
    .RESETB(1'b1),
    .BYPASS(1'b0),
    .REFERENCECLK(clk),
    .PLLOUTCORE(clk_200)
);

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

assign sdram_clk = sys_clk;

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

    .state_out(sd_state),
    .command_out(sd_command),
    
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
