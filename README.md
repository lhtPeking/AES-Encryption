# AES Encryption on FPGA Board.
## 过程控制基本原理
### AES_CORE
要从INIT切换到NEXT，需要先由外界信号init驱动keymem生成扩展信号后，检测到key_ready==1，进入CTRL_INIT的主控制环中，将aes_core_ctrl_new改为IDEL；再之后等待外界信号next，trigger enc_block的起始，同时在CTRL_IDEL中将aes_core_ctrl_new改为CTRL_NEXT，在下一轮时钟沿的时候进入CTRL_NEXT状态，再之后等待enc_block计算完成，muxed_ready==1时进入CTRL_NEXT的主控制环，再将aes_core_ctrl_new = CTRL_IDLE，下一轮时钟沿重新回到IDLE状态.
外部控制模块（比如 MCU、控制器、DMA）怎么知道 AES 内部计算是否完成？何时可以发下一个命令？靠`ready`和`result_valid`两个输出信号，AES 核心已经明确暴露出状态供外界查询.