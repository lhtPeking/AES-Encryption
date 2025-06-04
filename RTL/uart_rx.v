module uart_rx (
    input  wire clk,
    input  wire rstn,
    input  wire baud_tick,
    input  wire rxd, // rx data
    output reg  valid,
    output reg [7:0] data
);
  localparam RX_IDLE   = 2'd0,
             RX_START  = 2'd1,
             RX_DATA   = 2'd2,
             RX_STOP   = 2'd3;

  reg [1:0] state, next_state;
  reg [2:0] bit_cnt;
  reg [7:0] data_buf;
  reg       rxd_reg;

  // 把rxd打一拍用于稳定输入
  always @(posedge clk) begin
    rxd_reg <= rxd;
  end

  // 状态转移逻辑
  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      state <= RX_IDLE;
    else if (baud_tick)
      state <= next_state;
  end

  // 状态推进逻辑
  always @(*) begin
    case (state)
      RX_IDLE:  next_state = (rxd_reg == 1'b0) ? RX_START : RX_IDLE; // 起始位检测
      RX_START: next_state = RX_DATA;
      RX_DATA:  next_state = (bit_cnt == 3'd7) ? RX_STOP : RX_DATA;
      RX_STOP:  next_state = RX_IDLE;
      default:  next_state = RX_IDLE;
    endcase
  end

  // bit计数器
  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      bit_cnt <= 3'd0;
    else if (baud_tick) begin
      if (state == RX_DATA)
        bit_cnt <= bit_cnt + 1;
      else if (state == RX_IDLE)
        bit_cnt <= 3'd0;
    end
  end

  // 数据缓冲
  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      data_buf <= 8'd0;
    else if (baud_tick && state == RX_DATA)
      data_buf <= {rxd_reg, data_buf[7:1]};
  end

  // 输出数据
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      data  <= 8'd0;
      valid <= 1'b0;
    end else if (baud_tick && state == RX_STOP) begin
      data  <= data_buf;
      valid <= 1'b1;
    end else begin
      valid <= 1'b0;
    end
  end
endmodule
