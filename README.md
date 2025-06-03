# AES Encryption on FPGA Board.
## 1 Project Overview
This project is modified from the `main` branch of the `0aca1` repository. Based on the original RTL design, 192-bit encryption and decryption functionality has been added (located in the `RTL` folder). Additionally, bidirectional communication between the FPGA and the host computer is implemented via UART.
## 2 各module的接口信息
下面从architecture的层级对RTL代码进行分析.
### aes_core module
```
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
```
aes_core利用FSM架构实现了对整个AES加密过程的控制. `encdec`是用来区分现在是加密还是译码的input状态变量，`init`和`next`分别用来指定aes_core控制的FSM处于`CTRL_INIT`状态还是`CTRL_NEXT`状态. 在对变量`aes_core_ctrl`敏感的FSM中，存在`CTRL_IDEL`、`CTRL_INIT`和`CTRL_NEXT`三种状态，状态转换以`CTRL_IDEL -> CTRL_INIT/CTRL_NEXT -> CTRL_IDEL`的形式发生. `ready`信号作为轮密钥生成的完成信号，用于提醒FPGA可以进行下一步加密或译码. 

**以加密过程为例**，加密的时候需要先将`init`置为1，`keymem`module接收到`init`信息后开始密钥生成，与此同时在FSM控制块中发生`aes_core_ctrl_new = CTRL_INIT`，并在下一轮时钟沿到来时将`aes_core_ctrl_reg`赋值为`CTRL_INIT`，FSM进入轮密钥扩展运算状态. 

等待轮密钥计算完成，`key_ready`module会输出`key_ready == 1`作为完成信号，FSM接收到这个信号后将自己的状态重置为`CTRL_IDEL`，同时将`ready_new`置为1，`ready_new`在下一轮时钟沿的时候通过将`ready_reg`置为1，进而通过组合逻辑将`ready`置为1，而`ready`信号作为output告诉上位机轮密钥生成已完成，可以开始加密.

于是上位机将`next`置为1，FSM从`CTRL_IDEL`状态进入`CTRL_NEXT`状态，与此同时在`encdec_mux`组合逻辑过程块中，通过`encdec == 1`来判断现在是加密状态，于是将`enc_next`赋值为1，`enc_block`module在接收到`enc_next`信号之后开始利用明文和轮密钥进行加密运算. 运算完成后将`enc_ready`置为1，后者再通过组合逻辑将`muxed_ready`置为1，FSM检测到该信号后回到`CTRL_IDEL`状态，并同时将`result_valid`置为1，使得生成的`result`可以被读出，自此完成AES的加密.

这个复杂的控制过程由上位机的`init`信号和`next`信号完全把控FPGA的行为，在得到许可后FPGA利用FSM实现状态的层级控制与自动化状态转换，模块之间的握手信息非常简明清晰.

### aes_key_mem module
```
module aes_key_mem(
                   input wire            clk,
                   input wire            reset_n,

                   input wire [255 : 0]  key,
                   input wire            keylen,
                   input wire            init,

                   input wire    [3 : 0] round,
                   output wire [127 : 0] round_key,
                   output wire           ready,


                   output wire [31 : 0]  sboxw,
                   input wire  [31 : 0]  new_sboxw
                  );
```
这个module的架构比较神奇，为了满足一次性计算出所有轮密钥的需求，`round_key`只是一个输出端口，真正生成的轮密钥是存储在`reg [127 : 0] key_mem [0 : 14]`中的，在组合逻辑中利用input`round`变量，利用`key_mem[round]`将每一轮的轮密钥取出，而在aes_core中`round`会随着轮数的变化而变化，从而实现轮密钥的及时供给.

### aes_encipher_block module
```
module aes_encipher_block(
                          input wire            clk,
                          input wire            reset_n,

                          input wire            next,

                          input wire            keylen,
                          output wire [3 : 0]   round,
                          input wire [127 : 0]  round_key,

                          output wire [31 : 0]  sboxw,
                          input wire  [31 : 0]  new_sboxw,

                          input wire [127 : 0]  block,
                          output wire [127 : 0] new_block,
                          output wire           ready
                         );
```
在加密过程中，也是每轮取出不同的轮密钥进行加密，输出的判断条件是：根据`keylen`判断`num_rounds`的大小，将`round_ctr_reg`与`num_rounds`进行比较，全部完成后将`ready`信号置1并输出`new_block`. `aes_decipher_block module`的逻辑基本与`aes_encipher_block module`相同.

### aes_sbox module
```
module aes_sbox(
                input wire [31 : 0]  sboxw,
                output wire [31 : 0] new_sboxw
               );
```

### aes_inv_sbox module
```
module aes_inv_sbox(
                    input wire  [31 : 0] sword,
                    output wire [31 : 0] new_sword
                   );
```

### aes module
```
module aes(
           // Clock and reset.
           input wire           clk,
           input wire           reset_n,

           // Control.
           input wire           cs,
           input wire           we,

           // Data ports.
           input wire  [7 : 0]  address,
           input wire  [31 : 0] write_data,
           output wire [31 : 0] read_data
          );
```

## 3 在原仓库基础上的改动
