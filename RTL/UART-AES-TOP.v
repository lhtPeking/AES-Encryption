module uart_aes_top(
    input  wire       clk,
    input  wire       rstn,
    input  wire       uart_rx,
    output wire       uart_tx
);
  localparam IDLE  = 0;
  localparam RECV  = 1;
  localparam EXEC  = 2;
  localparam SEND  = 3;

  reg [1:0]  state, next_state;
  reg [7:0]  cmd, addr;
  reg [31:0] data_buf;
  reg [1:0]  byte_cnt;
  reg [1:0]  tx_cnt;

  reg        uart_send;
  reg [7:0]  tx_byte;
  wire       uart_busy;

  wire       rx_valid;
  wire [7:0] rx_byte;

  uart_rx uart_rx_inst (
      .clk(clk), .rstn(rstn),
      .rxd(uart_rx),
      .valid(rx_valid),
      .data(rx_byte)
  );

  uart_tx uart_tx_inst (
      .clk(clk), .rstn(rstn),
      .baud_tick(1'b1),  // Assume 1:1 baud clk for simplicity, replace with real tick if needed
      .send(uart_send),
      .data(tx_byte),
      .txd(uart_tx),
      .busy(uart_busy)
  );

  wire [31:0] aes_read_data;
  reg         aes_we, aes_cs;
  reg  [7:0]  aes_addr;
  reg [31:0]  aes_write_data;

  aes aes_inst (
      .clk(clk),
      .reset_n(rstn),
      .cs(aes_cs),
      .we(aes_we),
      .address(aes_addr),
      .write_data(aes_write_data),
      .read_data(aes_read_data)
  );

  always @(posedge clk or negedge rstn) begin
    if (!rstn)
      state <= IDLE;
    else
      state <= next_state;
  end

  always @(*) begin
    next_state = state;
    case (state)
      IDLE:
        if (rx_valid) next_state = RECV;
      RECV:
        if ((cmd == 8'h01 && byte_cnt == 3'd5) ||  // Write needs 5 bytes
            (cmd == 8'h02 && byte_cnt == 3'd2))    // Read needs 2 bytes
          next_state = EXEC;
      EXEC:
        next_state = (cmd == 8'h01) ? IDLE : SEND;  // write done; read needs SEND
      SEND:
        if (!uart_busy && tx_cnt == 2'd3) next_state = IDLE; // all 4 bytes sent
    endcase
  end

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      byte_cnt <= 0;
      tx_cnt <= 0;
      cmd <= 0;
      addr <= 0;
      data_buf <= 0;
      aes_we <= 0;
      aes_cs <= 0;
      uart_send <= 0;
      tx_byte <= 8'h00;
    end else begin
      uart_send <= 0;
      aes_we <= 0;
      aes_cs <= 0;

      case (state)
        IDLE: begin
          byte_cnt <= 0;
        end

        RECV: begin
          if (rx_valid) begin
            case (byte_cnt)
              0: cmd <= rx_byte;
              1: addr <= rx_byte;
              2: data_buf[7:0]   <= rx_byte;
              3: data_buf[15:8]  <= rx_byte;
              4: data_buf[23:16] <= rx_byte;
              5: data_buf[31:24] <= rx_byte;
            endcase
            byte_cnt <= byte_cnt + 1;
          end
        end

        EXEC: begin
          aes_addr <= addr;
          aes_cs <= 1;
          if (cmd == 8'h01) begin
            aes_we <= 1;
            aes_write_data <= data_buf;
          end else if (cmd == 8'h02) begin
            tx_cnt <= 0;
          end
        end

        SEND: begin
          if (!uart_busy) begin
            uart_send <= 1;
            case (tx_cnt)
              0: tx_byte <= aes_read_data[7:0];
              1: tx_byte <= aes_read_data[15:8];
              2: tx_byte <= aes_read_data[23:16];
              3: tx_byte <= aes_read_data[31:24];
            endcase
            tx_cnt <= tx_cnt + 1;
          end
        end
      endcase
    end
  end
endmodule
