
module uart_tx (
    input  wire clk,
    input  wire rstn,
    input  wire baud_tick,
    input  wire send,
    input  wire [7:0] data,
    output reg  txd,
    output reg  busy
);
  localparam TX_IDLE  = 2'd0,
             TX_START = 2'd1,
             TX_DATA  = 2'd2,
             TX_STOP  = 2'd3;

  reg [1:0] state, next_state;
  reg [2:0] bit_cnt;
  reg [7:0] data_buf;

  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      state <= TX_IDLE;
    else if (baud_tick)
      state <= next_state;
  end

  always @(*) begin
    case (state)
      TX_IDLE:  next_state = send ? TX_START : TX_IDLE;
      TX_START: next_state = TX_DATA;
      TX_DATA:  next_state = (bit_cnt == 3'd7) ? TX_STOP : TX_DATA;
      TX_STOP:  next_state = TX_IDLE;
      default:  next_state = TX_IDLE;
    endcase
  end

  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      bit_cnt <= 0;
    else if (baud_tick && state == TX_DATA)
      bit_cnt <= bit_cnt + 1;
    else if (state == TX_IDLE)
      bit_cnt <= 0;
  end

  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      data_buf <= 8'd0;
    else if (state == TX_IDLE && send)
      data_buf <= data;
    else if (baud_tick && state == TX_DATA)
      data_buf <= {1'b0, data_buf[7:1]};
  end

  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      txd <= 1'b1;
    else if (baud_tick) begin
      case (state)
        TX_IDLE:  txd <= 1'b1;
        TX_START: txd <= 1'b0;
        TX_DATA:  txd <= data_buf[0];
        TX_STOP:  txd <= 1'b1;
        default:  txd <= 1'b1;
      endcase
    end
  end

  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      busy <= 0;
    else if (state == TX_IDLE && send)
      busy <= 1;
    else if (state == TX_STOP && baud_tick)
      busy <= 0;
  end
endmodule
