module sdram_controller (
    // host contorller
    input                      clk,
    input                      rst_n,
    input  [HADDR_WIDTH-1:0]   wr_addr,
    input  [7:0]               wr_data,
    input                      wr_enable,
    input  [HADDR_WIDTH-1:0]   rd_addr,
    output [7:0]               rd_data,
    input                      rd_enable,

    // host controller status signals
    output                     rd_ready,
    output reg                 ack,
    output                     busy,

    // debugging
    output [4:0]               state_debug,
    output [7:0]               command_debug,

    // physical connections to the SDRAM chip
    output reg [SDRADDR_WIDTH-1:0] addr,
    output reg [BANK_WIDTH-1:0]    bank_addr,
    inout  [7:0]               data,
    output                     clock_enable,
    output                     cs_n,
    output                     ras_n,
    output                     cas_n,
    output                     we_n,
    output                     data_mask 
);

parameter ROW_WIDTH = 13;
parameter COL_WIDTH = 10;
parameter BANK_WIDTH = 2;

parameter SDRADDR_WIDTH = ROW_WIDTH > COL_WIDTH ? ROW_WIDTH : COL_WIDTH;
parameter HADDR_WIDTH   = BANK_WIDTH + ROW_WIDTH + COL_WIDTH;

parameter CLK_FREQUENCY = 100;  // Mhz
parameter REFRESH_TIME =  32;   // ms     (how often we need to refresh)
parameter REFRESH_COUNT = 8192; // cycles (how many refreshes required per refresh time)

// clk / refresh =  clk / sec
//                , sec / refbatch
//                , ref / refbatch
localparam CYCLES_BETWEEN_REFRESH = ( CLK_FREQUENCY
                                      * 1_000
                                      * REFRESH_TIME
                                    ) / REFRESH_COUNT;

localparam IDLE      = 5'b00000;

localparam INIT_NOP1 = 5'b01000,
           INIT_PRE1 = 5'b01001,
           INIT_NOP2 = 5'b00101,
           INIT_REF1 = 5'b01010,
           INIT_NOP3 = 5'b01011,
           INIT_REF2 = 5'b01100,
           INIT_MRS  = 5'b01101,
           INIT_LOAD = 5'b01110,
           INIT_NOP4 = 5'b01111;

localparam REF_PRE  =  5'b00001,
           REF_NOP1 =  5'b00010,
           REF_REF  =  5'b00011,
           REF_NOP2 =  5'b00100;

localparam READ_ACT  = 5'b10000,
           READ_NOP1 = 5'b10001,
           READ_PRECAS=5'b10010,
           READ_CAS  = 5'b10011,
           READ_NOP2 = 5'b10100,
           READ_READ = 5'b10101;

localparam WRIT_ACT  = 5'b11000,
           WRIT_NOP1 = 5'b11001,
           WRIT_PRECAS=5'b11010,
           WRIT_CAS  = 5'b11011,
           WRIT_NOP2 = 5'b11100;

// Commands              CC RCW BB A
//                       KS AAE AA 1
//                       E  SS  10 0
localparam CMD_PALL = 8'b10_010_00_1, // Precharge all banks
           CMD_REF  = 8'b10_001_00_0, // CBR Auto-refresh
           CMD_NOP  = 8'b10_111_00_0, // NOP
           CMD_MRS  = 8'b10_000_00_x, // Mode Register Set
           CMD_BACT = 8'b10_011_xx_x, // Bank Activate
           CMD_READ = 8'b10_101_xx_1, // Read with auto precharge
           CMD_WRIT = 8'b10_100_xx_1; // Write with auto precharge

reg  [HADDR_WIDTH-1:0]   haddr_r;
reg  [7:0]               wr_data_r;
reg  [7:0]               rd_data_r;
reg                      busy;
reg                      data_mask_r;
reg [SDRADDR_WIDTH-1:0]  addr_r;
reg [BANK_WIDTH-1:0]     bank_addr_r;
reg                      rd_ready_r;
wire                     data_mask;

assign data_mask = data_mask_r;
assign rd_data   = rd_data_r;

reg [3:0] state_cnt;
reg [9:0] refresh_cnt;
reg refresh_required;

reg [7:0] command;
reg [4:0] state;

assign command_debug = command;
assign state_debug = state;

assign {clock_enable, cs_n, ras_n, cas_n, we_n} = command[7:3];

// Tri-State buffer control
wire [7:0] data_in_from_buffer;
SB_IO # (
    .PIN_TYPE(6'b1010_01),
    .PULLUP(1'b 0)
) data_io [7:0] (
    .PACKAGE_PIN(data),
    .OUTPUT_ENABLE(state == WRIT_CAS),
    .D_OUT_0(wr_data_r),
    .D_IN_0(data_in_from_buffer)
);

assign rd_ready = rd_ready_r;

// on the falling edge of our clock, which is the rising edge of
// the DRAM clock, sample the input
always @ (negedge clk)
begin
	if (state == READ_READ)
		$display("read input data");
	rd_data_r <= data_in_from_buffer;
	rd_ready_r <= state == READ_READ;
end

// HOST INTERFACE
// all registered on posedge


// Copy our bank, row and commands to the output pins
always @*
begin
	if (state[4]) begin
		// we're in a read/write state, so set our busy flag
		busy <= 1;
		bank_addr <= bank_addr_r;
		addr <= addr_r;
	end else
	begin
		// neither read nor write
		busy <= 0;
		bank_addr <= command[2:1];

		if (state == INIT_LOAD)
			addr <= addr_r;
		else begin
			addr <= 0;
			addr[10] <= command[0];
		end
	end
end

// Handle refresh counter.  count down until we hit our threshold,
// then set the refresh required flag so that the state machine
// will enter the refresh on the next idle loop.
always @ (posedge clk)
begin
	refresh_required <= 0;

	if (~rst_n || state == REF_NOP2)
		refresh_cnt <= CYCLES_BETWEEN_REFRESH[9:0];
	else
	if (refresh_cnt != 0)
		refresh_cnt <= refresh_cnt - 1;
	else
		refresh_required <= 1;
end


/* Handle logic for sending addresses to SDRAM based on current state*/
always @(posedge clk)
begin
    if (state[4])
      data_mask_r <= 1'b0;
    else
      data_mask_r <= 1'b1;

   if (state == IDLE) begin
	// prepare to activate the bank and page
	if (rd_enable)
	begin
		haddr_r <= rd_addr;
		bank_addr_r <= rd_addr[HADDR_WIDTH-1 : HADDR_WIDTH-(BANK_WIDTH)];
		addr_r <= rd_addr[HADDR_WIDTH-BANK_WIDTH-1 : HADDR_WIDTH-BANK_WIDTH-ROW_WIDTH];
	end else
	if (wr_enable) begin
		wr_data_r <= wr_data;
		haddr_r <= wr_addr;
		bank_addr_r <= wr_addr[HADDR_WIDTH-1 : HADDR_WIDTH-(BANK_WIDTH)];
		addr_r <= wr_addr[HADDR_WIDTH-BANK_WIDTH-1 : HADDR_WIDTH-BANK_WIDTH-ROW_WIDTH];
	end
   end else

   if (state == READ_PRECAS || state == WRIT_PRECAS) begin
     // Prepare to send Column Address (lower bits)
     // Set bank to precharge
     bank_addr_r <= haddr_r[HADDR_WIDTH-1 : HADDR_WIDTH-(BANK_WIDTH)];

     // Select the CAS address to the bottom 
     addr_r		<= 0;
     addr_r[10]		<= 1; // A10 == auto precharge
     addr_r[COL_WIDTH-1:0] <= haddr_r[COL_WIDTH-1:0];
   end else

   if (state == INIT_MRS) begin
     // Prepare to program mode register during INIT_LOAD cycle
     // This is only done during a reset, not on every read
     addr_r		<= 0;
     addr_r[9]		<= 1; // Burst length (1 = single location)
     addr_r[8:7]	<= 0; // Mode 00 == normal
     addr_r[6:4]	<= 2; // CAS latency 2
     addr_r[3]		<= 0; // Burst type sequential
     addr_r[2:0]	<= 0; // Burst length 1
   end
end

// Next state logic
always @ (posedge clk)
begin
   // default is no command, immediate transition, not acking user
   command <= CMD_NOP;
   state_cnt <= 0;
   ack <= 0;

   if (~rst_n) begin
	// if the host initiates a reset, go into the INIT_NOP1 state
	// until they release it.
	// todo: should there be some sort of de-select command here?
	state <= INIT_NOP1;
	state_cnt <= 15;
   end else
   if (state == IDLE)
        // Monitor for refresh or hold
        if (refresh_required)
          begin
          state <= REF_PRE;
          command <= CMD_PALL;
          end
        else
	if (rd_enable)
          begin
	  // address will be set in the address handling block
          state <= READ_ACT;
          command <= CMD_BACT;
          ack <= 1;
          end
        else
	if (wr_enable)
          begin
	  // address will be set in the address handling block
          state <= WRIT_ACT;
          command <= CMD_BACT;
          ack <= 1;
          end
        else
          begin
          // HOLD in the idle state
          state <= IDLE;
          end
    else
    if (state_cnt != 0)
      // remain in the current state until state_cnt goes to zero
      state_cnt <= state_cnt - 1;
    else
	// transition to the next state
        case (state)
          // INIT ENGINE
          INIT_NOP1:	begin state <= INIT_PRE1; command <= CMD_PALL; end
          INIT_PRE1:	begin state <= INIT_NOP2; end
          INIT_NOP2:	begin state <= INIT_REF1; command <= CMD_REF; end
          INIT_REF1:	begin state <= INIT_NOP3; state_cnt <= 7; end
          INIT_NOP3:	begin state <= INIT_REF2; command <= CMD_REF; end
          INIT_REF2:	begin state <= INIT_NOP4; state_cnt <= 6; end
          INIT_NOP4:	begin state <= INIT_MRS; end
          INIT_MRS:	begin state <= INIT_LOAD; command <= CMD_MRS; end
          INIT_LOAD:	begin state <= REF_NOP2; state_cnt <= 7; end
          //INIT_NOP5:	begin state <= IDLE; end

          // REFRESH
          REF_PRE:	begin state <= REF_NOP1; end
          REF_NOP1:	begin state <= REF_REF; command <= CMD_REF; end
          REF_REF:	begin state <= REF_NOP2; state_cnt <= 7; end
          REF_NOP2:	begin state <= IDLE; end

          // WRITE:
          // CAS latency is two, so we spent one cycles in NOP2
          // tRCD (Active command to R/W command delay time) is same as CAS
          WRIT_ACT:	begin state <= WRIT_NOP1; state_cnt <= 1; end
          WRIT_NOP1:	begin state <= WRIT_PRECAS; end
          WRIT_PRECAS:	begin state <= WRIT_CAS; command <= CMD_WRIT; end
          WRIT_CAS:	begin state <= WRIT_NOP2; state_cnt <= 0; end
          WRIT_NOP2:	begin state <= IDLE; state_cnt <= 2; end

          // READ: CAS latency is two, so we spent one cycles in NOP2
          READ_ACT:	begin state <= READ_NOP1; state_cnt <= 1; end
          READ_NOP1:	begin state <= READ_PRECAS; end
          READ_PRECAS:	begin state <= READ_CAS; command <= CMD_READ; end
          READ_CAS:	begin state <= READ_NOP2; state_cnt <= 0; end
          READ_NOP2:	begin state <= READ_READ; end
          READ_READ:	begin state <= IDLE; end

          default:	begin state <= IDLE; end
          endcase
end

endmodule
