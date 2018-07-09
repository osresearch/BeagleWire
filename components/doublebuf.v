/*
 * Clock-crossing double buffered flip flop.
 */
module doublebuf(
	input clk_in,
	input clk_out,
	input [WIDTH-1:0] in,
	output [WIDTH-1:0] out
);

parameter WIDTH=1;

reg [WIDTH-1:0] t0;
reg [WIDTH-1:0] t1;

always @(posedge clk_in)
begin
	t0 <= in;
end

always @(posedge clk_out)
begin
	t1 <= t0;
	out <= t1;
end

endmodule
