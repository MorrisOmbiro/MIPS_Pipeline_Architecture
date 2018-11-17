//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module CPU (clock);
   parameter LW = 6'b100011, SW = 6'b101011, BEQ = 6'b000100, no_op = 32'b0000000_0000000_0000000_0000000, ALUop = 6'b0,
              BNE = 6'b000101, JRT = 6'b011110;

   integer fd,code,str,t;
   input clock;
  
   reg[31:0] PC, IFIDPC, IDEXPC, Regs[0:31], IMemory[0:1023], DMemory[0:1023], // separate memories
             IFIDIR, IDEXA, IDEXB, IDEXC, IDEXIR, EXMEMIR, EXMEMB, // pipeline registers
             EXMEMALUOut, MEMWBValue, MEMWBIR; // pipeline registers
             
   //reg[31:0] PCID, PCEX;
   wire [4:0] IDEXrs, IDEXrt, EXMEMrd, EXMEMrs, MEMWBrd, MEMWBrs, EXMEMrt, IFIDrs, IFIDrt, IDEXshamt, EXMEMshamt; //hold register fields
   wire [5:0] EXMEMop, MEMWBop, IDEXop, IFIDop; //Hold opcodes
   wire [31:0] Ain, Bin, Cin;
   
   reg [31:0] loop; // change the i field into a 32 bit and then shift it left by 2 
   reg EXMEMFlag, MEMWBFlag; 

   //declare the bypass signals
   wire takebranch, stall, bypassAfromMEM, bypassAfromALUinWB,bypassBfromMEM, bypassBfromALUinWB, 
        bypassCfromMEM, bypassCfromALUinWB, bypassAfromLWinWB, bypassBfromLWinWB, bypassCfromLWinWB;
   wire bypassIDEXAfromWB, bypassIDEXBfromWB, bypassIDEXCfromWB;
   
   wire jrStall;
   // LOGIC ! 
   // These assignments are just definitions of fields from the pipeline registers 
   assign IDEXrs = IDEXIR[25:21];  assign IDEXrt = IDEXIR[20:16];  assign EXMEMrd = EXMEMIR[15:11]; assign EXMEMrs = EXMEMIR[25:21];
                   assign EXMEMrt = EXMEMIR[20:16];
   assign IDEXshamt = IDEXIR[10:6];assign EXMEMshamt = EXMEMIR[10:6];
   assign MEMWBrd = MEMWBIR[15:11]; assign EXMEMop = EXMEMIR[31:26];
   assign MEMWBop = MEMWBIR[31:26];  assign IDEXop = IDEXIR[31:26];
   assign IFIDop = IFIDIR[31:26]; assign IFIDrs = IFIDIR[25:21]; assign IFIDrt = IFIDIR[20:16];
    
    
    assign jrStall = (IFIDIR[31:26] == JRT || IDEXIR[31:26] == JRT); 
   // THis is the implementation of the forwarding unit 
   
   // The bypass to input A from the MEM stage for an ALU operation
   assign bypassAfromMEM = (IDEXrs == EXMEMrd) & (IDEXrs!=0) & (EXMEMop==ALUop) |
                            ((IDEXrt == EXMEMrs) & (EXMEMop == JRT) & (EXMEMFlag == 1)); // yes, bypass
            
   // The bypass to input B from the MEM stage for an ALU operation
   assign bypassBfromMEM = (IDEXrt == EXMEMrd)&(IDEXrt!=0) & (EXMEMop==ALUop) | // yes, bypass
                ((IDEXrs == EXMEMrs) & (EXMEMop == JRT) & (EXMEMFlag == 1)); // yes, bypass

   // The bypass to input C from the MEM stage for an ALU operation 
   assign bypassCfromMEM = ((IDEXIR[10:6] == EXMEMrd)&(IDEXIR[10:6]!=0)&(EXMEMop==ALUop)) | 
                             ((IDEXIR[10:6] == EXMEMrs) & (EXMEMop == JRT)& (EXMEMFlag == 1)); // yes, bypass

   
   // The bypass to input A from the WB stage for an ALU operation
   assign bypassAfromALUinWB =( IDEXrs == MEMWBrd) & (IDEXrs!=0) & (MEMWBop==ALUop) |
                               ((IDEXrt == EXMEMrs) & (EXMEMop == JRT)& (MEMWBFlag == 1)); // yes, bypass

   // The bypass to input B from the WB stage for an ALU operation
   assign bypassBfromALUinWB = ((IDEXrt == MEMWBrd) & (IDEXrt!=0) & (MEMWBop==ALUop)) | 
                               ((IDEXrs == EXMEMrs) & (EXMEMop == JRT) & MEMWBFlag == 1); // yes, bypass)     ;
   // THe bypass to input C from the WB stage for an ALU operation
   assign bypassCfromALUinWB = (IDEXIR[10:6] == MEMWBrd) & (IDEXIR[10:6] != 0) & (MEMWBop == ALUop) | 
                                ((IDEXIR[10:6] == EXMEMrs) & (EXMEMop == JRT) & MEMWBFlag == 1); // yes, bypass);
   
   // The bypass to input A from the WB stage for an LW operation
   assign bypassAfromLWinWB =(IDEXrs == MEMWBIR[20:16]) & (IDEXrs!=0) & (MEMWBop==LW);
   // The bypass to input B from the WB stage for an LW operation
   assign bypassBfromLWinWB = (IDEXrt == MEMWBIR[20:16]) & (IDEXrt!=0) & (MEMWBop==LW);
   // The bypass to input C from the WB stage for an LW operation 
   assign bypassCfromLWinWB = (IDEXIR[10:6] == MEMWBIR[20:16]) & (IDEXIR[10:6] != 0) & (MEMWBop==LW);
    // ^^^ this might never happen 
    
   // The A input to the ALU is bypassed from MEM if there is a bypass there,
   // Otherwise from WB if there is a bypass there, and otherwise comes from the IDEX register
   assign Ain = bypassAfromMEM? EXMEMALUOut :
               (bypassAfromALUinWB | bypassAfromLWinWB)? MEMWBValue : IDEXA;
   // The B input to the ALU is bypassed from MEM if there is a bypass there,
   // Otherwise from WB if there is a bypass there, and otherwise comes from the IDEX register
   assign Bin = bypassBfromMEM? EXMEMALUOut :
               (bypassBfromALUinWB | bypassBfromLWinWB)? MEMWBValue : IDEXB;

  assign Cin = bypassCfromMEM ? EXMEMALUOut : 
               (bypassCfromALUinWB | bypassCfromLWinWB)? MEMWBValue : IDEXC;
                
   //Forwarding from the WB stage to the decode stage
   assign bypassIDEXAfromWB = (MEMWBIR != no_op) & (IFIDIR != no_op) &
   (((IFIDIR[25:21] == MEMWBIR[20:16]) & (MEMWBop == LW)) | ( (MEMWBop == ALUop) & (MEMWBrd == IFIDIR[25:21])));
   assign bypassIDEXBfromWB = (MEMWBIR != no_op) & (IFIDIR != no_op) &
   (((IFIDIR[20:16] == MEMWBIR[20:16]) & (MEMWBop == LW)) | ( (MEMWBop == ALUop) & (MEMWBrd == IFIDIR[20:16])));
   assign bypassIDEXCfromWB = (MEMWBIR != no_op) & (IFIDIR != no_op) &
      (((IFIDIR[10:6] == MEMWBIR[20:16]) & (MEMWBop == LW)) | ( (MEMWBop == ALUop) & (MEMWBrd == IFIDIR[10:6])));
   
   // The signal for detecting a stall based on the use of a result from LW
   assign stall = (IDEXIR[31:26]==LW) && // source instruction is a load
         ((((IFIDop==LW)) && (IFIDrs==IDEXrt)) | // stall for LW address calc 
         ((IFIDop==ALUop) && ((IFIDrs==IDEXrt) | (IFIDrt==IDEXrt))) |  //ALU use
         ((IFIDop==SW) &&  ((IFIDrs==IDEXrt) | (IFIDrt==IDEXrt))));  //stall for SW 

   //Signal for a taken branch: instruction is BEQ and registers are equal
   assign takebranch = ((IFIDIR[31:26]==BEQ) && (Regs[IFIDIR[25:21]] == Regs[IFIDIR[20:16]])) | 
                       ((IFIDIR[31:26]==BNE) && (Regs[IFIDIR[25:21]] != Regs[IFIDIR[20:16]]));
   
   reg [10:0] i; //used to initialize registers
   // INITIAL STATE of registers and memory 
   initial begin
      t=0 ;
      #1 //delay of 1, wait for the input ports to initialize
      PC = 0;
      IFIDIR = no_op; IDEXIR = no_op; EXMEMIR = no_op; MEMWBIR = no_op; // put no_ops in pipeline registers
      for (i=0;i<=31;i=i+1) Regs[i]=i; //initialize registers -- just so they aren't don't cares
      for(i=0;i<=1023;i=i+1) IMemory[i]=0;
      for(i=0;i<=1023;i=i+1) DMemory[i]=0;
      // This is where you will need to specify the running benchmark 
      // We execute the instructions in imem.dat
      fd=$fopen("./regs.dat","r"); 
      i=0; while(!$feof(fd)) begin
        code=$fscanf(fd, "%b\n", str);
        Regs[i]=str;
       $display("Register %d: = %d", i, Regs[i]);
        i=i+1;
      end
      i=0; fd=$fopen("./dmem.dat","r");
      while(!$feof(fd)) begin
        code=$fscanf(fd, "%b\n", str);
        DMemory[i]=str;
        i=i+1;
      end
      i=0; fd=$fopen("./imem.dat","r");
      while(!$feof(fd)) begin
        code=$fscanf(fd, "%b\n", str);
        IMemory[i]=str;
        i=i+1;
      end
      #396
      i=0; fd =$fopen("./mem_result.dat","w" ); //open memory result file
      while(i < 32)
      begin
        // This is happening in case we fail at branch prediction ?????? 
        str = DMemory[i];  //dump the first 32 memory values
        $fwrite(fd, "%b\n", str);
        i=i+1;
      end
      $fclose(fd);
      i=0; fd =$fopen("./regs_result.dat","w" ); //open register result file
      while(i < 32)
      begin
        str = Regs[i];  //dump the register values
        $display("Output Register %d: = %d", i, Regs[i]);
        $fwrite(fd, "%b\n", str);
        i=i+1;
      end
      $fclose(fd);
   end
    // PIPELINE STAGES  
   always @ (posedge clock) begin
      t = t + 1;
      if (~stall) begin // the first three pipeline stages stall if there is a load hazard
                  //IF stage
         //IF stage

         if(jrStall) 
            IFIDIR <= no_op;
        
         else if (~takebranch) begin
            IFIDIR <= IMemory[PC>>2];
            PC <= PC + 4;
            IFIDPC <= PC; 
         end else begin // a taken branch is in ID; instruction in IF is wrong; insert a no_op and reset the PC
            IFIDIR <= no_op;
            PC <= PC + ({{16{IFIDIR[15]}}, IFIDIR[15:0]}<<2); // reset the PC 
         end
         
         //ID stage 
         IDEXPC <= IFIDPC;
         if ( ~bypassIDEXAfromWB )begin
               IDEXA <= Regs[IFIDIR[25:21]];
             end
         else begin
               IDEXA <= MEMWBValue;
              end
             
         if ( ~bypassIDEXBfromWB) begin // if we are not getting data back from WB to IDEX register (data hazard)
            IDEXB <= Regs[IFIDIR[20:16]]; // get two registers
         end
         else
            IDEXB <= MEMWBValue;
       
        if ( ~bypassIDEXCfromWB)
              IDEXC <= Regs[IFIDIR[10:6]];
             else 
              IDEXC <= MEMWBValue;
             
        IDEXIR <= IFIDIR;  //pass along IR

        end // ending the IF (~stall)
      
      else begin  //Freeze first two stages of pipeline; inject a nop into the ID output
         IDEXIR <= no_op;
      end
      
      
      //EX stage of the pipeline
      
      if ((IDEXop==LW) |(IDEXop==SW))  // address calculation & copy B
        begin
           EXMEMALUOut <= Ain +{{16{IDEXIR[15]}}, IDEXIR[15:0]};
        end
      else if (IDEXop==ALUop) case (IDEXIR[5:0]) //case for the various R-type instructions
               32: begin // add
                      EXMEMALUOut <= Ain + Bin;  
                      EXMEMFlag <= 1;
                   end
               34: begin // sub
                      EXMEMALUOut <= Ain - Bin;
                      EXMEMFlag <= 1;
                   end
               36: begin // and
                      EXMEMALUOut <= Ain & Bin; 
                      EXMEMFlag <= 1;
                   end
               37: begin // or 
                      EXMEMALUOut <= Ain | Bin;
                      EXMEMFlag <= 1;
                   end
               42: begin // slt
                     if(Ain < Bin) begin
                        EXMEMALUOut <= 1;
                        EXMEMFlag <= 1;
                        end
                     else begin
                        EXMEMALUOut <= 0; // propagate something else 
                        EXMEMFlag <= 0;
                    end 
                   end  
               29: begin 
                     if(Ain < Bin) begin
                        EXMEMALUOut <= Cin;
                        EXMEMFlag <= 1; 
                        end
                     else begin  // we need to forward the Rd value ! 
                        EXMEMFlag <= 0; 
                     end  
                   end
               default: ; 
             endcase
       else if (IDEXop == JRT) begin // JRT  
            if(Ain == 0) begin
               PC <= IDEXPC + ({{16{IDEXIR[15]}}, IDEXIR[15:0]}<<2) + 4;
               EXMEMALUOut <= Ain + 1;
               EXMEMFlag <= 1;
            end
            else EXMEMFlag <= 0;      
       end
             // Below line we pass on the B register which holds the rt and we also pass the IDEXIR instruction onto the EXMEMIR stage 
             // Keeping in mind we also need to take care of data hazard cases 
             // There are two ways we are gonna be able to flush this, one way would be to stall the incoming instruction in the pipeline 
             // The other way is to forward the data onto the register of the next one ! 
      EXMEMIR <= IDEXIR; EXMEMB <= Bin; //pass along the IR & B register
      //MEM stage
      if (EXMEMop==ALUop | EXMEMop == JRT)begin 
        MEMWBValue <= EXMEMALUOut;
        MEMWBFlag <= EXMEMFlag;
      end //pass along ALU result 
         else if (EXMEMop == LW) MEMWBValue <= DMemory[EXMEMALUOut>>2];
            else if (EXMEMop == SW) DMemory[EXMEMALUOut>>2] <=EXMEMB; //store
            else if (EXMEMop == JRT) MEMWBValue <= EXMEMALUOut; // pass along result
      //WB stage
      MEMWBFlag <= EXMEMFlag;
      MEMWBIR <= EXMEMIR; //pass along IR
      if(MEMWBop == JRT) begin 
            if(~EXMEMFlag) ;
            else 
            Regs[MEMWBrs] <= MEMWBValue;
      end
      if ((MEMWBop==ALUop) & (MEMWBrd != 0)) begin
            if((MEMWBIR[5:0] == 29) & !MEMWBFlag);
            else
                Regs[MEMWBrd] <= MEMWBValue;    
      end
      
      else if ((MEMWBop == LW)& (MEMWBIR[20:16] != 0)) begin
               // 20:16
               Regs[MEMWBIR[20:16]] <= MEMWBValue;
           end
      else if (MEMWBop == JRT & MEMWBIR[25:21] != 0 & MEMWBFlag) begin
                Regs[MEMWBIR[25:21]] <= MEMWBValue;
      end
   end
endmodule
