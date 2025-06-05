//======================================================================
// aes.core.v
// ----------
// The AES core. This core supports key size of 128(nr = 10), 192(nr = 12) and 256(nr = 14) bits.
// Most of the functionality is within the submodules.
//======================================================================

module aes_core(
                input wire            clk,
                input wire            reset_n,

                input wire            encdec,
                input wire            init, // 控制信号用于控制FSM
                input wire            next, // 控制信号用于控制FSM
                output wire           ready,

                input wire [255 : 0]  key, // 128 位时只使用低 128 位
                input wire            keylen,

                input wire [127 : 0]  block,
                output wire [127 : 0] result,
                output wire           result_valid
               );

  //----------------------------------------------------------------
  // Internal constant and parameter definitions.
  //----------------------------------------------------------------
  localparam CTRL_IDLE  = 2'h0;
  localparam CTRL_INIT  = 2'h1; // 密钥扩展的控制信号
  localparam CTRL_NEXT  = 2'h2; // 加密解密的控制信号

  //----------------------------------------------------------------
  // Registers including update variables and write enable.
  //----------------------------------------------------------------
  reg [1 : 0] aes_core_ctrl_reg;
  reg [1 : 0] aes_core_ctrl_new;
  reg         aes_core_ctrl_we;

  reg         result_valid_reg;
  reg         result_valid_new;
  reg         result_valid_we;

  reg         ready_reg;
  reg         ready_new;
  reg         ready_we;

  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  reg            init_state;

  wire [127 : 0] round_key;
  wire           key_ready;

  reg            enc_next;
  wire [3 : 0]   enc_round_nr;
  wire [127 : 0] enc_new_block;
  wire           enc_ready;
  wire [31 : 0]  enc_sboxw;

  reg            dec_next;
  wire [3 : 0]   dec_round_nr;
  wire [127 : 0] dec_new_block;
  wire           dec_ready;

  reg [127 : 0]  muxed_new_block;
  reg [3 : 0]    muxed_round_nr;
  reg            muxed_ready;

  wire [31 : 0]  keymem_sboxw; // key memory's sbox word

  reg [31 : 0]   muxed_sboxw;
  wire [31 : 0]  new_sboxw;

  //----------------------------------------------------------------
  // Instantiations.
  //----------------------------------------------------------------
  aes_encipher_block enc_block(
                               .clk(clk),
                               .reset_n(reset_n),

                               .next(enc_next),

                               .keylen(keylen),
                               .round(enc_round_nr),
                               .round_key(round_key),

                               .sboxw(enc_sboxw),
                               .new_sboxw(new_sboxw),

                               .block(block),
                               .new_block(enc_new_block),
                               .ready(enc_ready)
                              );


  aes_decipher_block dec_block(
                               .clk(clk),
                               .reset_n(reset_n),

                               .next(dec_next),

                               .keylen(keylen),
                               .round(dec_round_nr),
                               .round_key(round_key),

                               .block(block),
                               .new_block(dec_new_block),
                               .ready(dec_ready)
                              );


  aes_key_mem keymem( // 实现 AES 密钥扩展（Key Schedule）与储存，每一轮都需要新的密钥来完成轮密钥加，AES的密钥扩展与明文无关
                     .clk(clk),
                     .reset_n(reset_n),

                     .key(key),
                     .keylen(keylen),
                     .init(init),

                     .round(muxed_round_nr),
                     .round_key(round_key),
                     .ready(key_ready),

                     .sboxw(keymem_sboxw),
                     .new_sboxw(new_sboxw)
                    );


  aes_sbox sbox(.sboxw(muxed_sboxw), .new_sboxw(new_sboxw));


  //----------------------------------------------------------------
  // Concurrent connectivity for ports etc.
  //----------------------------------------------------------------
  assign ready        = ready_reg;
  assign result       = muxed_new_block;
  assign result_valid = result_valid_reg;


  //----------------------------------------------------------------
  // reg_update
  //
  // Update functionality for all registers in the core.
  // All registers are positive edge triggered with asynchronous
  // active low reset. All registers have write enable.
  //----------------------------------------------------------------
  always @ (posedge clk or negedge reset_n)
    begin: reg_update // begin: label 是命名块，命名块会在波形图、层次树中作为一个可见的作用域
      if (!reset_n)
        begin // 初始状态
          result_valid_reg  <= 1'b0;
          ready_reg         <= 1'b1;
          aes_core_ctrl_reg <= CTRL_IDLE;
        end
      else
        begin
          // new变量应该来源于组合逻辑，new早就计算好，等时钟沿到来之后进行reg的更新
          if (result_valid_we) // Write Enable 写使能，在修改变量前都需要检查一下这个变量对应的WE变量是否为1
            result_valid_reg <= result_valid_new;

          if (ready_we)
            ready_reg <= ready_new;

          if (aes_core_ctrl_we)
            aes_core_ctrl_reg <= aes_core_ctrl_new;
        end
    end // reg_update


  //----------------------------------------------------------------
  // sbox_mux
  //
  // Controls which of the encipher datapath or the key memory
  // that gets access to the sbox.
  //----------------------------------------------------------------
  always @*
    begin : sbox_mux // 密钥扩展和加解密里用到的s-box可以不同，这里用多路复用的逻辑进行实现
      if (init_state)
        begin
          muxed_sboxw = keymem_sboxw;
        end
      else
        begin
          muxed_sboxw = enc_sboxw;
        end
    end // sbox_mux


  //----------------------------------------------------------------
  // encdex_mux
  //
  // Controls which of the datapaths that get the next signal, have
  // access to the memory as well as the block processing result.
  //----------------------------------------------------------------
  always @* // enc还是dec的状态决定
    begin : encdec_mux
      enc_next = 1'b0;
      dec_next = 1'b0;

      if (encdec)
        begin
          // Encipher operations
          enc_next        = next;
          muxed_round_nr  = enc_round_nr;
          muxed_new_block = enc_new_block;
          muxed_ready     = enc_ready;
        end
      else
        begin
          // Decipher operations
          dec_next        = next;
          muxed_round_nr  = dec_round_nr;
          muxed_new_block = dec_new_block;
          muxed_ready     = dec_ready;
        end
    end // encdec_mux


  //----------------------------------------------------------------
  // aes_core_ctrl
  //
  // Control FSM for aes core. Basically tracks if we are in
  // key init, encipher or decipher modes and connects the
  // different submodules to shared resources and interface ports.
  //----------------------------------------------------------------
  always @*
    // 最关键的状态转移过程块，用于更新new和we变量
    // 这个 FSM 的设计风格是“纯粹控制流状态机”：它不执行加解密或密钥扩展的实际计算，它只负责控制“何时激活哪个子模块”，具体运算都发生在子模块aes_encipher_block, aes_decipher_block, aes_key_mem中
    begin : aes_core_ctrl
      // begin一开始的初始化操作
      init_state        = 1'b0;
      ready_new         = 1'b0;
      ready_we          = 1'b0;
      result_valid_new  = 1'b0;
      result_valid_we   = 1'b0;
      aes_core_ctrl_new = CTRL_IDLE;
      aes_core_ctrl_we  = 1'b0;

      case (aes_core_ctrl_reg)
        CTRL_IDLE:
          begin
            if (init) // init控制信号
              begin
                init_state        = 1'b1;
                ready_new         = 1'b0;
                ready_we          = 1'b1;
                result_valid_new  = 1'b0;
                result_valid_we   = 1'b1;
                aes_core_ctrl_new = CTRL_INIT;
                aes_core_ctrl_we  = 1'b1;
              end
            else if (next) // next控制信号
              begin
                init_state        = 1'b0;
                ready_new         = 1'b0;
                ready_we          = 1'b1;
                result_valid_new  = 1'b0;
                result_valid_we   = 1'b1;
                aes_core_ctrl_new = CTRL_NEXT;
                aes_core_ctrl_we  = 1'b1;
              end
          end

        CTRL_INIT:
          begin
            init_state = 1'b1; // 只有在INIT的时候init_state才是1, 组合逻辑sbox_mux由init_state调控进行s-box的切换

            if (key_ready) // key_ready用于指示密钥扩展是否完成
              begin
                ready_new         = 1'b1;
                ready_we          = 1'b1;
                aes_core_ctrl_new = CTRL_IDLE;
                aes_core_ctrl_we  = 1'b1;
              end
          end

        CTRL_NEXT:
          begin
            init_state = 1'b0;

            if (muxed_ready) // muxed_ready来源于对enc_ready和dec_ready的多路复用
              begin
                ready_new         = 1'b1;
                ready_we          = 1'b1;
                result_valid_new  = 1'b1;
                result_valid_we   = 1'b1;
                aes_core_ctrl_new = CTRL_IDLE;
                aes_core_ctrl_we  = 1'b1;
              end
          end

        default:
          begin

          end
      endcase // case (aes_core_ctrl_reg)

    end // aes_core_ctrl
endmodule // aes_core