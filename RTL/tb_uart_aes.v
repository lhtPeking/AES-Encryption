`timescale 1ns / 1ps

module uart_aes_tb;

  reg clk = 0;
  reg rstn = 0;
  reg uart_rx;
  wire uart_tx;

  // Instantiate DUT
  uart_aes_top dut (
    .clk(clk),
    .rstn(rstn),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx)
  );

  // Clock: 100MHz
  always #5 clk = ~clk;

  initial begin
    clk = 0;
    uart_rx = 1;   // 空闲状态
    rstn = 0;
    #200;
    rstn = 1;
  end


  // UART timing
  localparam BAUD_PERIOD = 104_166; // ~104.166us for 9600 baud @ 1ns resolution

  // Task to send one byte over uart_rx
  task uart_send_byte(input [7:0] data);
    integer i;
    begin
      uart_rx = 0; // Start bit
      #(BAUD_PERIOD);
      for (i = 0; i < 8; i = i + 1) begin
        uart_rx = data[i];
        #(BAUD_PERIOD);
      end
      uart_rx = 1; // Stop bit
      #(BAUD_PERIOD);
    end
  endtask

  // Capture bytes from uart_tx
  reg [7:0] rx_capture [0:3];
  integer bit_idx, byte_idx;
  reg [7:0] shift_reg;
  reg [13:0] bit_time;
  reg sampling;
  reg [3:0] sample_cnt;

  initial begin
    // Initialize
    uart_rx = 1;
    rstn = 0;
    #200;
    rstn = 1;
    #2000;

    // ------------------------------
    // Send WRITE command: cmd=0x01, addr=0x10, data=0xCAFEBABE
    // Format: [cmd][addr][data0][data1][data2][data3]
    // ------------------------------
    uart_send_byte(8'h01); // cmd: write
    uart_send_byte(8'h10); // address
    uart_send_byte(8'hBE); // LSB
    uart_send_byte(8'hBA);
    uart_send_byte(8'hFE);
    uart_send_byte(8'hCA); // MSB

    #2_000_000; // wait for write to complete

    // ------------------------------
    // Send READ command: cmd=0x02, addr=0x10
    // ------------------------------
    uart_send_byte(8'h02); // cmd: read
    uart_send_byte(8'h10); // address

    #1_000_000;

    // ------------------------------
    // Capture UART TX (simulate real UART receiver)
    // ------------------------------
    for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
      // Wait for start bit
      wait (uart_tx == 0);
      #(BAUD_PERIOD + BAUD_PERIOD/2); // move to middle of first data bit
      shift_reg = 0;
      for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
        shift_reg[bit_idx] = uart_tx;
        #(BAUD_PERIOD);
      end
      rx_capture[byte_idx] = shift_reg;
      // Wait for stop bit
      #(BAUD_PERIOD);
    end

    $display("\nReturned data from AES:");
    $display("Byte 0 (LSB): %02X", rx_capture[0]);
    $display("Byte 1     : %02X", rx_capture[1]);
    $display("Byte 2     : %02X", rx_capture[2]);
    $display("Byte 3 (MSB): %02X", rx_capture[3]);

    // Validate returned value = 0xCAFEBABE
    if ({rx_capture[3], rx_capture[2], rx_capture[1], rx_capture[0]} == 32'hCAFEBABE)
      $display("\n Test Passed: Correct AES read-back data.\n");
    else
      $display("\n Test Failed: Incorrect AES output.\n");

    $finish;
  end

endmodule
