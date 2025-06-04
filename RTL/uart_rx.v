
module uart_rx(
    input clk,
    input rstn,
    input rxd,
    output reg valid,
    output [7:0] data
);
  localparam RX_IDLE = 0,
             RX_START = 1,
             RX_DATA = 2,
             RX_FINISH = 3;

  reg [9:0] data_reg;
  reg [2:0] counter;
  reg [1:0] state, next_state;

  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      state <= RX_IDLE;
    else
      state <= next_state;
  end

  always @(*) begin
    case(state)
      RX_IDLE:   next_state = !data_reg[9] ? RX_START : RX_IDLE;
      RX_START:  next_state = RX_DATA;
      RX_DATA:   next_state = (counter == 3'd7) ? RX_FINISH : RX_DATA;
      RX_FINISH: next_state = RX_IDLE;
      default:   next_state = RX_IDLE;
    endcase
  end

  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      counter <= 0;
    else if (state == RX_DATA)
      counter <= counter + 1;
    else
      counter <= 0;
  end

  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      data_reg <= 10'b1111111111;
    else
      data_reg <= {rxd, data_reg[9:1]};
  end

  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      valid <= 0;
    else if (counter == 3'd7)
      valid <= 1;
    else
      valid <= 0;
  end

  assign data = data_reg[7:0];
endmodule
