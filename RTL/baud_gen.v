
module baud_gen_9600 (
    input  wire clk,
    input  wire rstn,
    output reg  baud_tick
);
  parameter BAUD_DIV = 10416; // 100_000_000 / 9600
  reg [13:0] counter;

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      counter   <= 0;
      baud_tick <= 0;
    end else if (counter == BAUD_DIV - 1) begin
      counter   <= 0;
      baud_tick <= 1;
    end else begin
      counter   <= counter + 1;
      baud_tick <= 0;
    end
  end
endmodule
