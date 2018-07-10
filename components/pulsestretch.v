/*
 * Stretch a pulse for a long time
 */
module pulsestretch(
	input clk,
	input in,
	output out
);

parameter LENGTH = 8;

reg [LENGTH-1:0] counter = 0;

always @(posedge clk)
begin
	if (in) begin
		counter <= 1;
		out <= 1;
	end else
	if (counter != 0) begin
		counter <= counter + 1;
		out <= 1;
	end else begin
		out <= 0;
	end
end

endmodule
