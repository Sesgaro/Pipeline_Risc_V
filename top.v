module top (clk, reset);
    input clk, reset;

    wire        PCSrc;
    wire        load_use;
    wire        PCWrite, IFID_Write;

    reg  [31:0] PC;
    wire [31:0] instr_IF, pc_plus4_IF, pc_next, pc_branch_EX;

    // registros IF/ID para pipeline
    reg [31:0] IFID_instr, IFID_pc;

    // las señales de las entradas
    wire [6:0] opcode_ID;
    wire [4:0] rs1_ID, rs2_ID, rd_ID;
    wire [2:0] func3_ID;
    wire       func7_ID;
    wire        branch_ID, MemRead_ID, MemtoReg_ID, MemWrite_ID, ALUSrc_ID, RegWrite_ID;
    wire [1:0]  ALUOp_ID;
    wire [31:0] rd1_ID, rd2_ID, imm_ID;

    // registros ID/EX
    reg        IDEX_branch, IDEX_MemRead, IDEX_MemtoReg, IDEX_MemWrite, IDEX_ALUSrc, IDEX_RegWrite;
    reg [1:0]  IDEX_ALUOp;
    reg [31:0] IDEX_pc, IDEX_rd1, IDEX_rd2, IDEX_imm;
    reg [4:0]  IDEX_rs1, IDEX_rs2, IDEX_rd;
    reg [2:0]  IDEX_func3;
    reg        IDEX_func7;

    // señales para la etapa execute y forwarding
    wire [3:0]  alu_ctrl_EX;
    wire [31:0] alu_result_EX, alu_in_B;
    wire        zero_EX;
    wire [1:0]  forwardA, forwardB;
    reg  [31:0] alu_in_A, forwardB_val;

    // registros para la memoria
    reg        EXMEM_MemRead, EXMEM_MemtoReg, EXMEM_MemWrite, EXMEM_RegWrite;
    reg [31:0] EXMEM_alu_result, EXMEM_store_data;
    reg [4:0]  EXMEM_rd;

    // señales de la etapa de la memoria
    wire [31:0] mem_out_MEM;

    // registros pipeline MEM/WB
    reg        MEMWB_MemtoReg, MEMWB_RegWrite;
    reg [31:0] MEMWB_mem_out, MEMWB_alu_result;
    reg [4:0]  MEMWB_rd;

    // señales writeback
    wire [31:0] write_data_WB;

    wire [31:0] pc_plus4_old;
    wire [31:0] alu_result_unused;
    wire        branch_taken;

    // ----- etapa FETCH ----- 

    // program counter 
    assign pc_plus4_IF = PC + 4;
    assign pc_plus4_old = PC + 4;
    assign branch_taken = PCSrc;

    // mux del pc para decidir si avanza normal o usa un branch
    assign pc_next = PCSrc ? pc_branch_EX : pc_plus4_IF;

    // memoria de las instrucciones
    instruction_memory inst_memory(.read_address(PC), .inst_out(instr_IF));

    // actualización pc
    always @(posedge clk or posedge reset) begin
        if (reset == 1'b1)
            PC <= 0; // <----- aqui se reinicia
        else if (PCWrite == 1'b1)
            PC <= pc_next; // <----- aqui solo avanza si no hay un memory hazard
    end

    // registros IF/ID
    always @(posedge clk or posedge reset) begin
        if (reset || PCSrc) begin
            IFID_instr <= 0;
            IFID_pc    <= 32'h00000000;
        end else if (IFID_Write) begin
            IFID_instr <= instr_IF;
            IFID_pc    <= PC;
        end
    end

    assign opcode_ID = IFID_instr[6:0];
    assign rs1_ID    = IFID_instr[19:15];
    assign rs2_ID    = IFID_instr[24:20];
    assign rd_ID     = IFID_instr[11:7];
    assign func3_ID  = IFID_instr[14:12];
    assign func7_ID  = IFID_instr[30];

    // ----- etapa DECODE

    // extracción datos 32 bits para hacer las instrucciones
    control_unit control_unit(.instr(opcode_ID), .branch(branch_ID), .MemRead(MemRead_ID),
        .MemtoReg(MemtoReg_ID), .MemWrite(MemWrite_ID), .ALUOp(ALUOp_ID),
        .ALUSrc(ALUSrc_ID), .RegWrite(RegWrite_ID));

    // banco de registros
    register_file register_file(.clk(clk), .reset(reset), .regwrite(MEMWB_RegWrite),
        .reg1(rs1_ID), .reg2(rs2_ID), .rd(MEMWB_rd), .write_data(write_data_WB),
        .rd1(rd1_ID), .rd2(rd2_ID));

    // generaciín de los valores inmediatos o la extensión de signo
    immediate_generator immediate_generator(.op(opcode_ID), .instr(IFID_instr), .imm_ex(imm_ID));

    // detección de riesgos memoria <-----------------------------
    //      si la instrucción es un LOAD y su deestino es una fuente actual...
    assign load_use = (IDEX_MemRead == 1'b1) && (IDEX_rd != 0) &&
                      ((IDEX_rd == rs1_ID) || (IDEX_rd == rs2_ID));
    assign PCWrite    = ~load_use; // ... se congela el PC
    assign IFID_Write = ~load_use;

    // registros ID/EX
    always @(posedge clk or posedge reset) begin
        if (reset || load_use || PCSrc) begin
            IDEX_branch   <= 1'b0;
            IDEX_MemRead  <= 1'b0;
            IDEX_MemtoReg <= 1'b0;
            IDEX_MemWrite <= 1'b0;
            IDEX_ALUSrc   <= 1'b0;
            IDEX_RegWrite <= 1'b0;
            IDEX_ALUOp    <= 2'b0;
            IDEX_pc       <= 32'b0;
            IDEX_rd1      <= 32'b0;
            IDEX_rd2      <= 32'b0;
            IDEX_imm      <= 32'b0;
            IDEX_rs1      <= 5'b0;
            IDEX_rs2      <= 5'b0;
            IDEX_rd       <= 5'b0;
            IDEX_func3    <= 3'b0;
            IDEX_func7    <= 1'b0;
        end else begin
            IDEX_branch   <= branch_ID;
            IDEX_MemRead  <= MemRead_ID;
            IDEX_MemtoReg <= MemtoReg_ID;
            IDEX_MemWrite <= MemWrite_ID;
            IDEX_ALUSrc   <= ALUSrc_ID;
            IDEX_RegWrite <= RegWrite_ID;
            IDEX_ALUOp    <= ALUOp_ID;
            IDEX_pc       <= IFID_pc;
            IDEX_rd1      <= rd1_ID;
            IDEX_rd2      <= rd2_ID;
            IDEX_imm      <= imm_ID;
            IDEX_rs1      <= rs1_ID;
            IDEX_rs2      <= rs2_ID;
            IDEX_rd       <= rd_ID;
            IDEX_func3    <= func3_ID;
            IDEX_func7    <= func7_ID;
        end
    end

    // ----- estapa EXECUTE -----

    // decodificador secundario de la ALU
    alu_control alu_control(.op(IDEX_ALUOp), .func7(IDEX_func7), .func3(IDEX_func3),
        .control_out(alu_ctrl_EX));

    // este forwarding unit evalua si se necesita traer valores "futuros"a la entrada A o B de la ALU
    assign forwardA =
        (EXMEM_RegWrite && (EXMEM_rd != 5'b0) && (EXMEM_rd == IDEX_rs1)) ? 2'b10 :
        (MEMWB_RegWrite && (MEMWB_rd != 5'b0) && (MEMWB_rd == IDEX_rs1)) ? 2'b01 : 2'b00;
    assign forwardB =
        (EXMEM_RegWrite && (EXMEM_rd != 5'b0) && (EXMEM_rd == IDEX_rs2)) ? 2'b10 :
        (MEMWB_RegWrite && (MEMWB_rd != 5'b0) && (MEMWB_rd == IDEX_rs2)) ? 2'b01 : 2'b00;

    // MUX de forawrding para la entrada A de la ALU
    always @(*) begin
        case (forwardA)
            2'b10:   alu_in_A = EXMEM_alu_result;
            2'b01:   alu_in_A = write_data_WB;
            default: alu_in_A = IDEX_rd1;
        endcase
    end

    // MUX forwarding para la entrada B
    always @(*) begin
        case (forwardB)
            2'b10:   forwardB_val = EXMEM_alu_result;
            2'b01:   forwardB_val = write_data_WB;
            default: forwardB_val = IDEX_rd2;
        endcase
    end

    // mux decide si la alu usa un registro o el valor inmediato en su entrada B
    assign alu_in_B      = IDEX_ALUSrc ? IDEX_imm : forwardB_val;

    // cáluclo de la dirección de destino si se toma branch
    assign pc_branch_EX  = IDEX_pc + IDEX_imm;

    // branch AND donde los valores son iguales 
    assign PCSrc         = IDEX_branch & zero_EX;

    // instancia ALU
    ALU_unit alu(.A(alu_in_A), .B(alu_in_B), .Control_in(alu_ctrl_EX),
        .ALU_Result(alu_result_EX), .zero(zero_EX));

    // Registro EX/MEM
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            EXMEM_MemRead    <= 0;
            EXMEM_MemtoReg   <= 1'b0;
            EXMEM_MemWrite   <= 1'b0;
            EXMEM_RegWrite   <= 1'b0;
            EXMEM_alu_result <= 32'd0;
            EXMEM_store_data <= 32'h00000000;
            EXMEM_rd         <= 0;
        end else begin
            // se pasan las señales y el resultado de la ALU a la etapa de memoria
            EXMEM_MemRead    <= IDEX_MemRead;
            EXMEM_MemtoReg   <= IDEX_MemtoReg;
            EXMEM_MemWrite   <= IDEX_MemWrite;
            EXMEM_RegWrite   <= IDEX_RegWrite;
            EXMEM_alu_result <= alu_result_EX;
            EXMEM_store_data <= forwardB_val; // guardando el dato en memoria
            EXMEM_rd         <= IDEX_rd;
        end
    end

    // etapa data memory donde se accede a la memoria
    data_memory data_memory(.clk(clk), .reset(reset), .MemWrite(EXMEM_MemWrite),
        .MemRead(EXMEM_MemRead), .read_address(EXMEM_alu_result),
        .Write_data(EXMEM_store_data), .MemData_out(mem_out_MEM));

    // registro MEM/WB
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            MEMWB_MemtoReg   <= 1'b0;
            MEMWB_RegWrite   <= 1'b0;
            MEMWB_mem_out    <= 32'b0;
            MEMWB_alu_result <= 32'b0;
            MEMWB_rd         <= 5'b0;
        end else begin
            MEMWB_MemtoReg   <= EXMEM_MemtoReg;
            MEMWB_RegWrite   <= EXMEM_RegWrite;
            MEMWB_mem_out    <= mem_out_MEM; // lo que se lee en la RAM
            MEMWB_alu_result <= EXMEM_alu_result; // el cálculo que se hace en ALU
            MEMWB_rd         <= EXMEM_rd;
        end
    end

    // etapa writeback donde el MUX decide si guardar el dato en la memoria lw, o el cálculo en la ALU
    assign write_data_WB = MEMWB_MemtoReg ? MEMWB_mem_out : MEMWB_alu_result;

endmodule
