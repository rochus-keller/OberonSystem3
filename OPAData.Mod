(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE OPAData;	(** prk  **)

(*
	Create the data file containing the tables for OPA
	
	FileFormat:
		InstrTabLen:2
		{(name start:2 end:2 target:4|0X)}
		OpTabLen:2
		{op[0]:2 op[1]:2 op[2]:2 op0:2 op1:2 opc:2 reg:2}
*)


IMPORT
		Files, Texts, Oberon;


CONST
		debug = FALSE;
		
		FileName = "OPA.Data";
		
		(*processor flags*)
		i386 = 0;  i486 = 1;  Pentium = 2;  PentiumPro = 3; 
		FPU = 16;  Privileged = 17;
		
		none = -1;
		
		(* Structure sizes *)
		MnemoLen = 12;

		(* Own Addressing modes, also used in the St and Sc *)
		Reg8 = 08H; Reg16 = 10H; Reg32 = 20H;
		RegAL = 09H; RegAX = 11H; RegEAX = 21H;
		RegDX = 12H;								(* special case for IN/OUT *)
		RegCL = 13H;								(* special case for rotate/shift *)
		Imm8 = 30H; Imm16 = 31H; Imm32 = 32H; SImm8 = 35H; Imm = 36H;
		Const1 = 33H;								(* special case for rotate/shift *)
		Const3 = 34H;								(* special case for INT 3 *)
		RM = 40H; RM8 = 41H; RM16 = 42H; RM32 = 43H; 
		M = 48H; M8 = 49H; M16 = 4AH; M32 = 4BH; M64 = 4CH; M80 = 4DH;
		(*M2 = 4EH;*)
		SReg = 50H;	(* Segment Register *)
		RegCS = 51H; RegDS = 52H; RegES = 53H; RegFS = 54H;
		RegGS = 55H; RegSS = 56H;
		Rel8 = 60H; Rel16 = 61H; Rel32 = 62H; FwdJmp = 63H;
		CRReg = 70H; DRReg = 71H; TRReg = 72H;
		FReg = 80H; FRegST = 81H;
		
		(* Opcodes modifiers *)
		OmReg = 1;		(* register stored in the RM byte as reg/opcode *)
		OmOp = 2;		(* register added to the opcode *)
		OmRMReg = 3;		(* register stored in the RM byte as r/m and reg/opcode*)
		
TYPE
		Mnemo = ARRAY MnemoLen OF CHAR;
		
	(*the types here must be the same as in OPA*)
		InstrDesc = RECORD
					name: Mnemo;
					start, end: INTEGER;	 (* index in the opcode-tab *)
					target: SET;
				END;

		(* Opcode: this structure contains the definition of an opcode, with the
			expected dst/src operands and the information needed to encode it.
			Ex:
				if opc # -1 => modr/m . opc = opc. ( extension of the opcode )
		*)
		OpCode = RECORD
				op: ARRAY 3 OF INTEGER;		(* mode of the dst/src operands, if needed *)
				op0, op1: INTEGER;	   (* opcode *)
				opc: INTEGER;			(* value stored in reg/opcode of modr/m. -1 = none *)
				reg: INTEGER;			(* where is the register stored: none / rm /op *)
			END;
		
VAR
		(*tables*)
		OpTab: POINTER TO ARRAY OF OpCode;	(* Table with the opcodes *)
		OpTabN: INTEGER;		(* nof opcodes in the table *)
		InstrTab: POINTER TO ARRAY OF InstrDesc;	(* Table with the instructions !!Hash *)
		OpTabLen, InstrTabLen: INTEGER;
		
		Clash: ARRAY 32 OF LONGINT;
		
		(*statistic informations*)
		InstrCount, Average: LONGINT;		(* debug: access average *)

		(*docu mode*)
		Docu: BOOLEAN;
		W: Texts.Writer;
		
	PROCEDURE Message(IN str: ARRAY OF CHAR);
	BEGIN
		Texts.WriteString(W, str);  Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
	END Message;
		
	PROCEDURE DumpMode(VAR W: Texts.Writer; mode: INTEGER);
	BEGIN
		CASE mode OF
		  Reg8: Texts.WriteString(W, "r8 ")
		| Reg16: Texts.WriteString(W, "r16 ")
		| Reg32: Texts.WriteString(W, "r32 ")
		| RegAL: Texts.WriteString(W, "AL ")
		| RegAX: Texts.WriteString(W, "AX ")
		| RegEAX: Texts.WriteString(W, "EAX ")
		| RegDX: Texts.WriteString(W, "DX ")
		| RegCL: Texts.WriteString(W, "CL ")
		| RegCS: Texts.WriteString(W, "CS ")
		| RegDS: Texts.WriteString(W, "DS ")
		| RegES: Texts.WriteString(W, "ES ")
		| RegFS: Texts.WriteString(W, "FS ")
		| RegGS: Texts.WriteString(W, "GS ")
		| RegSS: Texts.WriteString(W, "SS ")
		| Imm8: Texts.WriteString(W, "imm8 ")
		| Imm16: Texts.WriteString(W, "imm16 ")
		| Imm32: Texts.WriteString(W, "imm32 ")
		| SImm8: Texts.WriteString(W, "imm8 (signed) ")
		| Imm: Texts.WriteString(W, "imm (generic) ")
		| Const1: Texts.WriteString(W, "1 ")
		| Const3: Texts.WriteString(W, "t3 ")
		| RM: Texts.WriteString(W, "r/m ")
		| RM8: Texts.WriteString(W, "r/m8 ")
		| RM16: Texts.WriteString(W, "r/m16 ")
		| RM32: Texts.WriteString(W, "r/m32 ")
		| SReg: Texts.WriteString(W, "Sreg ")
		| Rel8: Texts.WriteString(W, "rel8 ")
		| Rel16: Texts.WriteString(W, "rel16 ")
		| Rel32: Texts.WriteString(W, "rel32 ")
		| FwdJmp: Texts.WriteString(W, "FwdJmp ")
		| none: Texts.WriteString(W, "none ")
		| M: Texts.WriteString(W, "m ")
		| M8: Texts.WriteString(W, "m8 ")
		| M16: Texts.WriteString(W, "m16 ")
		| M32: Texts.WriteString(W, "m32 ")
		| M64: Texts.WriteString(W, "m64 ")
		| M80: Texts.WriteString(W, "m80 ")
		| CRReg: Texts.WriteString(W, "CR0/CR2-4 ")
		| DRReg: Texts.WriteString(W, "DR0-3/DR6/DR7 ")
		| TRReg: Texts.WriteString(W, "TR6/TR7 ")
		| FReg: Texts.WriteString(W, "ST(i) ")
		| FRegST: Texts.WriteString(W, "ST ")
		ELSE Texts.WriteString(W, "unknown mode ")
		END
	END DumpMode;

(* Table Insertion Procedures *)
	(* Generates the hash index k for the n-th try. n>=0 *)
	PROCEDURE HashFn(IN name: ARRAY OF CHAR; VAR k, n: INTEGER);
		VAR i: INTEGER;
	BEGIN
		IF n = 0 THEN
			i := 0; k := 0;
			WHILE name[i] # 0X DO
				k := (k*16 + ORD(name[i])) MOD InstrTabLen; INC(i)
			END;
			n := 1
		ELSE
				k := (k + n) MOD InstrTabLen; INC(n, 1)
		END
	END HashFn;
	
	PROCEDURE FindInstruction(IN name: ARRAY OF CHAR; VAR inx: INTEGER);
		VAR n: INTEGER;
	BEGIN
		n := 0;
		REPEAT
			HashFn(name, inx, n)
		UNTIL (name = InstrTab[inx].name) OR (InstrTab[inx].name[0] = 0X) OR (n >InstrTabLen);
		IF (InstrTab[inx].name[0] = 0X) OR (n >InstrTabLen) THEN
			inx := -1
		END;
	END FindInstruction;
	
	PROCEDURE InsertMnemo(IN name: ARRAY OF CHAR; VAR k: INTEGER; target: SET);
		VAR n: INTEGER;
	BEGIN
		n := 0;
		REPEAT HashFn(name, k, n)
		UNTIL (InstrTab[k].name[0] = 0X) OR (n > 2*InstrTabLen) OR (InstrTab[k].name = name);
		IF n > 2*InstrTabLen THEN  Message("iOPA, internal instruction table too small!!")  END;
		IF InstrTab[k].name = name THEN 
			Texts.WriteString(W, name); Message(" already in the table");  RETURN
		END;
		InstrTab[k].name := name;  InstrTab[k].target := target;
		InstrTab[k].start := OpTabN; InstrTab[k].end := OpTabN;
		
		DEC(n);
		IF n < LEN(Clash) THEN  INC(Clash[n])  ELSE  INC(Clash[LEN(Clash)-1])  END;
		Average := Average + n; INC(InstrCount);
	END InsertMnemo;
	
	PROCEDURE InsertAlias(IN name, alias: ARRAY OF CHAR);
		VAR n,a: INTEGER;
	BEGIN
		FindInstruction(name, n);
		IF n = -1 THEN
			Texts.WriteString(W, "InsertAlias: the name doesn't exist "); Message(name); RETURN
		END;
		InsertMnemo(alias, a, InstrTab[n].target);
		InstrTab[a].start := InstrTab[n].start; InstrTab[a].end := InstrTab[n].end;
	END InsertAlias;
	
	PROCEDURE InsertOp3(idx, dest, src, o3, op0, op1, opc, om: INTEGER);
		VAR pos: INTEGER;
	BEGIN
		pos := InstrTab[idx].end;
		IF OpTab[pos].op0 # -1 THEN Message("Op Table, overwriting") END;
		OpTab[pos].op[0] := dest; OpTab[pos].op[1] := src; OpTab[pos].op[2] := o3;	(* dest / src addressing mode *)
		OpTab[pos].op0 := op0; OpTab[pos].op1 := op1;	(* opcodes *)
		OpTab[pos].opc := opc; OpTab[pos].reg := om;	(* opcode modifier (rm.opcode) / register storing place (opcode /rm byte) *)
		IF OpTabN < OpTabLen-1 THEN INC(InstrTab[idx].end); INC(OpTabN)
		ELSE Message("Op Table FULL")
		END
	END InsertOp3;
	
	PROCEDURE InsertOp(idx, dest, src, op0, op1, opc, om: INTEGER);
		VAR pos: INTEGER;
	BEGIN
		pos := InstrTab[idx].end;
		IF OpTab[pos].op0 # -1 THEN Message("Op Table, overwriting") END;
		OpTab[pos].op[0] := dest; OpTab[pos].op[1] := src; OpTab[pos].op[2] := none;	(* dest / src addressing mode *)
		OpTab[pos].op0 := op0; OpTab[pos].op1 := op1;	(* opcodes *)
		OpTab[pos].opc := opc; OpTab[pos].reg := om;	(* opcode modifier (rm.opcode) / register storing place (opcode /rm byte) *)
		IF OpTabN < OpTabLen-1 THEN INC(InstrTab[idx].end); INC(OpTabN)
		ELSE Message("Op Table FULL")
		END
	END InsertOp;
	
(* OPA Data *)
	PROCEDURE InsertFloatInstr1;
		VAR k: INTEGER;
	BEGIN
		
		InsertMnemo("F2XM1", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0F0H, none, none);
		
		InsertMnemo("FABS", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0E1H, none, none);
		
		InsertMnemo("FADD", k, {FPU});
		InsertOp(k, M32, none, 0D8H, none, 0, none);
		InsertOp(k, M64, none, 0DCH, none, 0, none);
		InsertOp(k, FRegST, FReg, 0D8H, 0C0H, none, OmOp);
		InsertOp(k, FReg, FRegST, 0DCH, 0C0H, none, OmOp);

		InsertMnemo("FADDP", k, {FPU});
		InsertOp(k, FReg, FRegST, 0DEH, 0C0H, none, OmOp);
		InsertOp(k, none, none, 0DEH, 0C1H, none, none);

		InsertMnemo("FIADD", k, {FPU});
		InsertOp(k, M32, none, 0DAH, none, 0, none);
		InsertOp(k, M16, none, 0DEH, none, 0, none);

		InsertMnemo("FBLD", k, {FPU});
		InsertOp(k, M80, none, 0DFH, none, 4, none);
		
		InsertMnemo("FBSTP", k, {FPU});
		InsertOp(k, M80, none, 0DFH, none, 6, none);
		
		InsertMnemo("FCHS", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0E0H, none, none);

		InsertMnemo("FNCLEX", k, {FPU});
		InsertOp(k, none, none, 0DBH, 0E2H, none, none);

		InsertMnemo("FCOM", k, {FPU});
		InsertOp(k, M32, none, 0D8H, none, 2, none);
		InsertOp(k, M64, none, 0DCH, none, 2, none);
		InsertOp(k, FReg, none, 0D8H, 0D0H, none, OmOp);
		InsertOp(k, none, none, 0DCH, 0D1H, none, none);

		InsertMnemo("FCOMP", k, {FPU});
		InsertOp(k, M32, none, 0D8H, none, 3, none);
		InsertOp(k, M64, none, 0DCH, none, 3, none);
		InsertOp(k, FReg, none, 0D8H, 0D8H, none, OmOp);
		InsertOp(k, none, none, 0D8H, 0D9H, none, none);

		InsertMnemo("FCOMPP", k, {FPU});
		InsertOp(k, none, none, 0DEH, 0D9H, none, none);
		
		InsertMnemo("FCOS", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0FFH, none, none);
		
		InsertMnemo("FDECSTP", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0F6H, none, none);
		
		InsertMnemo("FDIV", k, {FPU});
		InsertOp(k, M32, none, 0D8H, none, 6, none);
		InsertOp(k, M64, none, 0DCH, none, 6, none);
		InsertOp(k, FRegST, FReg, 0D8H, 0F0H, none, OmOp);
		InsertOp(k, FReg, FRegST, 0DCH, 0F8H, none, OmOp);

		InsertMnemo("FDIVP", k, {FPU});
		InsertOp(k, FReg, FRegST, 0DEH, 0F8H, none, OmOp);
		InsertOp(k, none, none, 0DEH, 0F9H, none, none);

		InsertMnemo("FIDIV", k, {FPU});
		InsertOp(k, M32, none, 0DAH, none, 6, none);
		InsertOp(k, M16, none, 0DEH, none, 6, none);

		InsertMnemo("FDIVR", k, {FPU});
		InsertOp(k, M32, none, 0D8H, none, 7, none);
		InsertOp(k, M64, none, 0DCH, none, 7, none);
		InsertOp(k, FRegST, FReg, 0D8H, 0F8H, none, OmOp);
		InsertOp(k, FReg, FRegST, 0DCH, 0F0H, none, OmOp);

		InsertMnemo("FDIVRP", k, {FPU});
		InsertOp(k, FReg, FRegST, 0DEH, 0F0H, none, OmOp);
		InsertOp(k, none, none, 0DEH, 0F1H, none, none);

		InsertMnemo("FIDIVR", k, {FPU});
		InsertOp(k, M32, none, 0DAH, none, 7, none);
		InsertOp(k, M16, none, 0DEH, none, 7, none);

		InsertMnemo("FFREE", k, {FPU});
		InsertOp(k, none, none, 0DDH, 0C0H, none, OmOp);

		InsertMnemo("FICOM", k, {FPU});
		InsertOp(k, M16, none, 0DEH, none, 2, none);
		InsertOp(k, M32, none, 0DAH, none, 2, none);

		InsertMnemo("FICOMP", k, {FPU});
		InsertOp(k, M16, none, 0DEH, none, 3, none);
		InsertOp(k, M32, none, 0DAH, none, 3, none);

		InsertMnemo("FILD", k, {FPU});
		InsertOp(k, M16, none, 0DFH, none, 0, none);
		InsertOp(k, M32, none, 0DBH, none, 0, none);
		InsertOp(k, M64, none, 0DFH, none, 5, none);
		
		InsertMnemo("FINCSTP", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0F7H, none, none);
		
		InsertMnemo("FNINIT", k, {FPU});
		InsertOp(k, none, none, 0DBH, 0E3H, none, none);

		InsertMnemo("FIST", k, {FPU});
		InsertOp(k, M16, none, 0DFH, none, 2, none);
		InsertOp(k, M32, none, 0DBH, none, 2, none);

		InsertMnemo("FISTP", k, {FPU});
		InsertOp(k, M16, none, 0DFH, none, 3, none);
		InsertOp(k, M32, none, 0DBH, none, 3, none);
		InsertOp(k, M64, none, 0DFH, none, 7, none);

		InsertMnemo("FLD", k, {FPU});
		InsertOp(k, M32, none, 0D9H, none, 0, none);
		InsertOp(k, M64, none, 0DDH, none, 0, none);
		InsertOp(k, M80, none, 0DBH, none, 5, none);
		InsertOp(k, FReg, none, 0D9H, 0C0H, none, OmOp);
		
		InsertMnemo("FLD1", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0E8H, none, none);

		InsertMnemo("FLDL2T", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0E9H, none, none);
		
		InsertMnemo("FLDL2E", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0EAH, none, none);

		InsertMnemo("FLDPI", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0EBH, none, none);

		InsertMnemo("FLDLG2", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0ECH, none, none);

		InsertMnemo("FLDLN2", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0EDH, none, none);

		InsertMnemo("FLDZ", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0EEH, none, none);

		InsertMnemo("FLDCW", k, {FPU});
		InsertOp(k, M, none, 0D9H, none, 5, none);

		InsertMnemo("FLDENV", k, {FPU});
		InsertOp(k, M, none, 0D9H, none, 4, none);

		InsertMnemo("FMUL", k, {FPU});
		InsertOp(k, M32, none, 0D8H, none, 1, none);
		InsertOp(k, M64, none, 0DCH, none, 1, none);
		InsertOp(k, FRegST, FReg, 0D8H, 0C8H, none, OmOp);
		InsertOp(k, FReg, FRegST, 0DCH, 0C8H, none, OmOp);

		InsertMnemo("FMULP", k, {FPU});
		InsertOp(k, FReg, FRegST, 0DEH, 0C8H, none, OmOp);
		InsertOp(k, none, none, 0DEH, 0C9H, none, none);

		InsertMnemo("FIMUL", k, {FPU});
		InsertOp(k, M32, none, 0DAH, none, 1, none);
		InsertOp(k, M16, none, 0DEH, none, 1, none);

		InsertMnemo("FNOP", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0D0H, none, none);

		InsertMnemo("FPATAN", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0F3H, none, none);

		InsertMnemo("FPREM", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0F8H, none, none);

		InsertMnemo("FPREM1", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0F5H, none, none);

		InsertMnemo("FPTAN", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0F2H, none, none);

		InsertMnemo("FRNDINT", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0FCH, none, none);

		InsertMnemo("FRSTOR", k, {FPU});
		InsertOp(k, M, none, 0DDH, none, 4, none);

		InsertMnemo("FSAVE", k, {FPU});
		InsertOp(k, M, none, 09BH, 0DDH, 6, none);

		InsertMnemo("FNSAVE", k, {FPU});
		InsertOp(k, M, none, 0DDH, none, 6, none);

		InsertMnemo("FSCALE", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0FDH, none, none);

		InsertMnemo("FSIN", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0FEH, none, none);

		InsertMnemo("FSINCOS", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0FBH, none, none);

		InsertMnemo("FSQRT", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0FAH, none, none);
	END InsertFloatInstr1;
	
	PROCEDURE InsertFloatInstr2;
		VAR k: INTEGER;
	BEGIN
		InsertMnemo("FST", k, {FPU});
		InsertOp(k, M32, none, 0D9H, none, 2, none);
		InsertOp(k, M64, none, 0DDH, none, 2, none);
		InsertOp(k, FReg, none, 0DDH, 0D0H, none, OmOp);

		InsertMnemo("FSTP", k, {FPU});
		InsertOp(k, M32, none, 0D9H, none, 3, none);
		InsertOp(k, M64, none, 0DDH, none, 3, none);
		InsertOp(k, M80, none, 0DBH, none, 7, none);
		InsertOp(k, FReg, none, 0D9H, 0D8H, none, OmOp);

		InsertMnemo("FSTCW", k, {FPU});
		InsertOp(k, M, none, 09BH, 0D9H, 7, none);

		InsertMnemo("FNSTCW", k, {FPU});
		InsertOp(k, M, none, 0D9H, none, 7, none);

		InsertMnemo("FSTENV", k, {FPU});
		InsertOp(k, M, none, 09BH, 0D9H, 6, none);

		InsertMnemo("FNSTENV", k, {FPU});
		InsertOp(k, M, none, 0D9H, none, 6, none);

		InsertMnemo("FSTSW", k, {FPU});
		InsertOp(k, M, none, 09BH, 0DDH, 7, none);

		InsertMnemo("FNSTSW", k, {FPU});
		InsertOp(k, M, none, 0DDH, none, 7, none);

		InsertMnemo("FSUB", k, {FPU});
		InsertOp(k, M32, none, 0D8H, none, 4, none);
		InsertOp(k, M64, none, 0DCH, none, 4, none);
		InsertOp(k, FRegST, FReg, 0D8H, 0E0H, none, OmOp);
		InsertOp(k, FReg, FRegST, 0DCH, 0E8H, none, OmOp);

		InsertMnemo("FSUBP", k, {FPU});
		InsertOp(k, FReg, FRegST, 0DEH, 0E8H, none, OmOp);
		InsertOp(k, none, none, 0DEH, 0E9H, none, none);

		InsertMnemo("FISUB", k, {FPU});
		InsertOp(k, M32, none, 0DAH, none, 4, none);
		InsertOp(k, M16, none, 0DEH, none, 4, none);

		InsertMnemo("FSUBR", k, {FPU});
		InsertOp(k, M32, none, 0D8H, none, 5, none);
		InsertOp(k, M64, none, 0DCH, none, 5, none);
		InsertOp(k, FRegST, FReg, 0D8H, 0E8H, none, OmOp);
		InsertOp(k, FReg, FRegST, 0DCH, 0E0H, none, OmOp);

		InsertMnemo("FSUBRP", k, {FPU});
		InsertOp(k, FReg, FRegST, 0DEH, 0E0H, none, OmOp);
		InsertOp(k, none, none, 0DEH, 0E1H, none, none);

		InsertMnemo("FISUBR", k, {FPU});
		InsertOp(k, M32, none, 0DAH, none, 5, none);
		InsertOp(k, M16, none, 0DEH, none, 5, none);

		InsertMnemo("FTST", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0E4H, none, none);

		InsertMnemo("FUCOM", k, {FPU});
		InsertOp(k, FReg, none, 0DDH, 0E0H, none, OmOp);
		InsertOp(k, none, none, 0DDH, 0E1H, none, none);

		InsertMnemo("FUCOMP", k, {FPU});
		InsertOp(k, FReg, none, 0DDH, 0E8H, none, OmOp);
		InsertOp(k, none, none, 0DDH, 0E9H, none, none);

		InsertMnemo("FUCOMPP", k, {FPU});
		InsertOp(k, none, none, 0DAH, 0E9H, none, none);

		InsertMnemo("FWAIT", k, {FPU});
		InsertOp(k, none, none, 09BH, none, none, none);

		InsertMnemo("FXAM", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0E5H, none, none);

		InsertMnemo("FXCH", k, {FPU});
		InsertOp(k, FReg, none, 0D9H, 0C8H, none, OmOp);
		InsertOp(k, none, none, 0D9H, 0C9H, none, none);

		InsertMnemo("FXTRACT", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0F4H, none, none);

		InsertMnemo("FYL2X", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0F1H, none, none);

		InsertMnemo("FYL2XP1", k, {FPU});
		InsertOp(k, none, none, 0D9H, 0F9H, none, none);
	END InsertFloatInstr2;
	
	
	PROCEDURE InsertInstr1;
		VAR i,k: INTEGER;
	BEGIN
		InsertMnemo("AAA", k, {i386});
		InsertOp(k, none, none, 37H, none, none, none);
		
		InsertMnemo("AAD", k, {i386});
		InsertOp(k, none, none, 0D5H, 0AH, none, none);
		
		InsertMnemo("AAM", k, {i386});
		InsertOp(k, none, none, 0D4H, 0AH, none, none);
		
		InsertMnemo("AAS", k, {i386});
		InsertOp(k, none, none, 3FH, none, none, none);

		FOR i:=0 TO 7 DO				(* similar integer ops *)
			CASE i OF
			  0: InsertMnemo("ADD", k, {i386})
			|1: InsertMnemo("OR", k, {i386})
			|2: InsertMnemo("ADC", k, {i386})
			|3: InsertMnemo("SBB", k, {i386})
			|4: InsertMnemo("AND", k, {i386})
			|5: InsertMnemo("SUB", k, {i386})
			|6: InsertMnemo("XOR", k, {i386})
			|7: InsertMnemo("CMP", k, {i386})
			END;
			InsertOp(k, RegAL, Imm8, 04H + i*08H, none, none, none);
			InsertOp(k, RegAX, Imm16, 05H + i*08H, none, none, none);
			InsertOp(k, RegEAX, Imm32, 05H + i*08H, none, none, none);
			InsertOp(k, RM8, Imm8, 80H, none, i, none);
			InsertOp(k, RM16, SImm8, 83H, none, i, none);
			InsertOp(k, RM32, SImm8, 83H, none, i, none);
			InsertOp(k, RM16, Imm16, 81H, none, i, none);
			InsertOp(k, RM32, Imm32, 81H, none, i, none);
			InsertOp(k, RM8, Reg8, i * 08H, none, none, OmReg);
			InsertOp(k, RM16, Reg16, 01H + i * 08H, none, none, OmReg);
			InsertOp(k, RM32, Reg32, 01H + i * 08H, none, none, OmReg);
			InsertOp(k, Reg8, RM8, 02H + i * 08H, none, none, OmReg);
			InsertOp(k, Reg16, RM16, 03H + i * 08H, none, none, OmReg);
			InsertOp(k, Reg32, RM32, 03H + i * 08H, none, none, OmReg);
		END;
		
		InsertMnemo("ARPL", k, {i386});
		InsertOp(k, RM16, Reg16, 63H, none, none, OmReg);
		
		InsertMnemo("BOUND", k, {i386});
		InsertOp(k, Reg16, M16, 62H, none, none, OmReg);
		InsertOp(k, Reg32, M32, 62H, none, none, OmReg);
		
		InsertMnemo("BSF", k, {i386});
		InsertOp(k, Reg16, RM16, 0FH, 0BCH, none, none);
		InsertOp(k, Reg32, RM32, 0FH, 0BCH, none, none);

		InsertMnemo("BSR", k, {i386});
		InsertOp(k, Reg16, RM16, 0FH, 0BDH, none, none);
		InsertOp(k, Reg32, RM32, 0FH, 0BDH, none, none);

		InsertMnemo("BSWAP", k, {i486});
		InsertOp(k, Reg32, none, 0FH, 0C8H, none, OmOp);
		
		FOR i := 0 TO 3 DO
			CASE i OF
				  0: InsertMnemo("BT", k, {i386})
				| 1: InsertMnemo("BTS", k, {i386})
				| 2: InsertMnemo("BTR", k, {i386})
				| 3: InsertMnemo("BTC", k, {i386})
			END;
			InsertOp(k, RM16, Reg16, 0FH, 0A3H + i*8, none, OmReg);
			InsertOp(k, RM32, Reg32, 0FH, 0A3H + i*8, none, OmReg);
			InsertOp(k, RM16, Imm8, 0FH, 0BAH, i+4, none);
			InsertOp(k, RM32, Imm8, 0FH, 0BAH, i+4, none)
		END;

		InsertMnemo("CALL", k, {i386});
		InsertOp(k, RM16, none, 0FFH, none, 2, none);
		InsertOp(k, Rel32, none, 0E8H, none, none, none);
		InsertOp(k, RM32, none, 0FFH, none, 2, none);
		
		InsertMnemo("CBW", k, {i386});
		InsertOp(k, none, none, 066H, 098H, none, none);
		
		InsertMnemo("CWDE", k, {i386});
		InsertOp(k, none, none, 098H, none, none, none);
		
		FOR i := 8 TO 0DH DO
			CASE i OF
				  8: InsertMnemo("CLC", k, {i386})
				| 9: InsertMnemo("STC", k, {i386})
				| 0AH: InsertMnemo("CLI", k, {i386})
				| 0BH: InsertMnemo("STI", k, {i386})
				| 0CH: InsertMnemo("CLD", k, {i386})
				| 0DH: InsertMnemo("STD", k, {i386})
			END;
			InsertOp(k, none, none, 0F0H + i, none, none, none)
		END;
		
		InsertMnemo("CLTS", k, {i386, Privileged});
		InsertOp(k, none, none, 0FH, 06H, none, none);
		
		InsertMnemo("CMC", k, {i386});
		InsertOp(k, none, none, 0F5H, none, none, none);
		
		FOR i := 0 TO 15 DO
			CASE i OF
			0: InsertMnemo("CMOVO", k, {PentiumPro})
			| 1: InsertMnemo("CMOVNO", k, {PentiumPro})
			| 2: InsertMnemo("CMOVB", k, {PentiumPro})
			| 3: InsertMnemo("CMOVNB", k, {PentiumPro})
			| 4: InsertMnemo("CMOVZ", k, {PentiumPro})
			| 5: InsertMnemo("CMOVNZ", k, {PentiumPro})
			| 6: InsertMnemo("CMOVBE", k, {PentiumPro})
			| 7: InsertMnemo("CMOVNBE", k, {PentiumPro})
			| 8: InsertMnemo("CMOVS", k, {PentiumPro})
			| 9: InsertMnemo("CMOVNS", k, {PentiumPro})
			| 10: InsertMnemo("CMOVP", k, {PentiumPro})
			| 11: InsertMnemo("CMOVNP", k, {PentiumPro})
			| 12: InsertMnemo("CMOVL", k, {PentiumPro})
			| 13: InsertMnemo("CMOVNL", k, {PentiumPro})
			| 14: InsertMnemo("CMOVLE", k, {PentiumPro})
			| 15: InsertMnemo("CMOVNLE", k, {PentiumPro})
			END;
			InsertOp(k, Reg16, RM16, 0FH, 40H + i, none, none);
			InsertOp(k, Reg32, RM32, 0FH, 40H + i, none, none);
		END;
		InsertAlias("CMOVB", "CMOVC"); InsertAlias("CMOVB", "CMOVNAE");
		InsertAlias("CMOVNB", "CMOVNC"); InsertAlias("CMOVNB", "CMOVAE");
		InsertAlias("CMOVZ", "CMOVE");
		InsertAlias("CMOVNZ", "CMOVNE");
		InsertAlias("CMOVBE", "CMOVNA");
		InsertAlias("CMOVNBE", "CMOVA");
		InsertAlias("CMOVP", "CMOVPE");
		InsertAlias("CMOVNP", "CMOVPO");
		InsertAlias("CMOVL", "CMOVNGE");
		InsertAlias("CMOVNL", "CMOVGE");
		InsertAlias("CMOVLE", "CMOVNG");
		InsertAlias("CMOVNLE", "CMOVG");
		
		InsertMnemo("CMPSB", k, {i386});
		InsertOp(k, none, none, 0A6H, none, none, none);
		
		InsertMnemo("CMPSW", k, {i386});
		InsertOp(k, none, none, 066H, 0A7H, none, none);
		
		InsertMnemo("CMPSD", k, {i386});
		InsertOp(k, none, none, 0A7H, none, none, none);

		InsertMnemo("CMPXCHG", k, {i486});
		InsertOp(k, RM8, Reg8, 0FH, 0B0H, none, OmReg);
		InsertOp(k, RM16, Reg16, 0FH, 0B1H, none, OmReg);
		InsertOp(k, RM32, Reg32, 0FH, 0B1H, none, OmReg);

		InsertMnemo("CMPXCHG8B", k, {Pentium});
		InsertOp(k, M64, none, 0FH, 0C7H, 1, none);
		
		InsertMnemo("CPUID", k, {Pentium});
		InsertOp(k, none, none, 0FH, 0A2H, none, none);

		InsertMnemo("CWD", k, {i386});
		InsertOp(k, none, none, 066H, 099H, none, none);
		InsertMnemo("CDQ", k, {i386});
		InsertOp(k, none, none, 099H, none, none, none);
		
		InsertMnemo("DAA", k, {i386});
		InsertOp(k, none, none, 027H, none, none, none);
		InsertMnemo("DAS", k, {i386});
		InsertOp(k, none, none, 02FH, none, none, none);

		InsertMnemo("DEC", k, {i386});
		InsertOp(k, Reg16, none, 48H, none, none, OmOp);
		InsertOp(k, Reg32, none, 48H, none, none, OmOp);
		InsertOp(k, RM8, none, 0FEH, none, 1, none);
		InsertOp(k, RM16, none, 0FFH, none, 1, none);
		InsertOp(k, RM32, none, 0FFH, none, 1, none);
		
		InsertMnemo("DIV", k, {i386});
		InsertOp(k, RegAL, RM8, 0F6H, none, 6, none);
		InsertOp(k, RegAX, RM16, 0F7H, none, 6, none);
		InsertOp(k, RegEAX, RM32, 0F7H, none, 6, none);
		InsertOp(k, RM8, none, 0F6H, none, 6, none);
		InsertOp(k, RM16, none, 0F7H, none, 6, none);
		InsertOp(k, RM32, none, 0F7H, none, 6, none);
		
		InsertMnemo("HLT", k, {i386, Privileged});
		InsertOp(k, none, none, 0F4H, none, none, none);
		
		InsertMnemo("IDIV", k, {i386});
		InsertOp(k, RegAL, RM8, 0F6H, none, 7, none);
		InsertOp(k, RegAX, RM16, 0F7H, none, 7, none);
		InsertOp(k, RegEAX, RM32, 0F7H, none, 7, none);
		InsertOp(k, RM8, none, 0F6H, none, 7, none);
		InsertOp(k, RM16, none, 0F7H, none, 7, none);
		InsertOp(k, RM32, none, 0F7H, none, 7, none);


		InsertMnemo("IMUL", k, {i386});
		InsertOp(k, RM8, none, 0F6H, none, 5, none);
		InsertOp(k, RM16, none, 0F7H, none, 5, none);
		InsertOp(k, RM32, none, 0F7H, none, 5, none);
		InsertOp(k, Reg16, RM16, 0FH, 0AFH, none, OmReg);
		InsertOp(k, Reg32, RM32, 0FH, 0AFH, none, OmReg);
		InsertOp(k, Reg16, SImm8, 06BH, none, none, OmRMReg);
		InsertOp(k, Reg32, SImm8, 06BH, none, none, OmRMReg);
		InsertOp(k, Reg16, Imm16, 069H, none, none, OmRMReg);
		InsertOp(k, Reg32, Imm32, 069H, none, none, OmRMReg);
		InsertOp3(k, Reg16, RM16, SImm8, 06BH, none, none, OmReg);
		InsertOp3(k, Reg32, RM32, SImm8, 06BH, none, none, OmReg);
		InsertOp3(k, Reg16, RM16, Imm16, 069H, none, none, OmReg);
		InsertOp3(k, Reg32, RM32, Imm32, 069H, none, none, OmReg);
	END InsertInstr1;
		
	PROCEDURE InsertInstr2;
		VAR i,k: INTEGER;
	BEGIN
		InsertMnemo("IN", k, {i386});
		InsertOp(k, RegAL, Imm8, 0E4H, none, none, none);
		InsertOp(k, RegAX, Imm8, 0E5H, none, none, none);
		InsertOp(k, RegEAX, Imm8, 0E5H, none, none, none);
		InsertOp(k, RegAL, RegDX, 0ECH, none, none, none);
		InsertOp(k, RegAX, RegDX, 0EDH, none, none, none);
		InsertOp(k, RegEAX, RegDX, 0EDH, none, none, none);

		InsertMnemo("INC", k, {i386});
		InsertOp(k, Reg16, none, 040H, none, none, OmOp);
		InsertOp(k, Reg32, none, 040H, none, none, OmOp);
		InsertOp(k, RM8, none, 0FEH, none, 0, none);
		InsertOp(k, RM16, none, 0FFH, none, 0, none);
		InsertOp(k, RM32, none, 0FFH, none, 0, none);

		InsertMnemo("INSB", k, {i386});
		InsertOp(k, none, none, 06CH, none, none, none);

		InsertMnemo("INSW", k, {i386});
		InsertOp(k, none, none, 066H, 06DH, none, none);
		
		InsertMnemo("INSD", k, {i386});
		InsertOp(k, none, none, 06DH, none, none, none);
		
		InsertMnemo("INT", k, {i386});
		InsertOp(k, Const3, none, 0CCH, none, none, none);
		InsertOp(k, Imm8, none, 0CDH, none, none, none);
		
		InsertMnemo("INTO", k, {i386});
		InsertOp(k, none, none, 0CEH, none, none, none);
		
		InsertMnemo("INVD", k, {i486, Privileged});
		InsertOp(k, none, none, 0FH, 08H, none, none);
		
		InsertMnemo("INVLPG", k, {i486, Privileged});
		InsertOp(k, M, none, 0FH, 01H, 7, none);
		
		InsertMnemo("IRETD", k, {i386});
		InsertOp(k, none, none, 0CFH, none, none, none);
		
		InsertMnemo("JCXZ", k, {i386});
		InsertOp(k, Rel8, none, 067H, 0E3H, none, none);
		
		InsertMnemo("JECXZ", k, {i386});
		InsertOp(k, Rel8, none, 0E3H, none, none, none);
		
		FOR i := 0 TO 15 DO
			CASE i OF
			0: InsertMnemo("JO", k, {i386})
			| 1: InsertMnemo("JNO", k, {i386})
			| 2: InsertMnemo("JB", k, {i386})
			| 3: InsertMnemo("JNB", k, {i386})
			| 4: InsertMnemo("JZ", k, {i386})
			| 5: InsertMnemo("JNZ", k, {i386})
			| 6: InsertMnemo("JBE", k, {i386})
			| 7: InsertMnemo("JNBE", k, {i386})
			| 8: InsertMnemo("JS", k, {i386})
			| 9: InsertMnemo("JNS", k, {i386})
			| 10: InsertMnemo("JP", k, {i386})
			| 11: InsertMnemo("JNP", k, {i386})
			| 12: InsertMnemo("JL", k, {i386})
			| 13: InsertMnemo("JNL", k, {i386})
			| 14: InsertMnemo("JLE", k, {i386})
			| 15: InsertMnemo("JNLE", k, {i386})
			END;
			InsertOp(k, Rel8, none, 70H + i, none, none, none);
			InsertOp(k, Rel16, none, 0FH, 80H + i, none, none);
			InsertOp(k, Rel32, none, 0FH, 80H + i, none, none);
		END;
		InsertAlias("JB", "JC"); InsertAlias("JB", "JNAE");
		InsertAlias("JNB", "JNC"); InsertAlias("JNB", "JAE");
		InsertAlias("JZ", "JE");
		InsertAlias("JNZ", "JNE");
		InsertAlias("JBE", "JNA");
		InsertAlias("JNBE", "JA");
		InsertAlias("JP", "JPE");
		InsertAlias("JNP", "JPO");
		InsertAlias("JL", "JNGE");
		InsertAlias("JNL", "JGE");
		InsertAlias("JLE", "JNG");
		InsertAlias("JNLE", "JG");
		
		InsertMnemo("JMP", k, {i386});
		InsertOp(k, Rel8, none, 0EBH, none, none, none);
		InsertOp(k, RM16, none, 0FFH, none, 4, none);
		InsertOp(k, Rel32, none, 0E9H, none, none, none);
		InsertOp(k, RM32, none, 0FFH, none, 4, none);
		
		InsertMnemo("LAHF", k, {i386});
		InsertOp(k, none, none, 09FH, none, none, none);
		
		InsertMnemo("LAR", k, {i386});
		InsertOp(k, Reg16, RM16, 0FH, 02H, none, OmReg);
		InsertOp(k, Reg32, RM32, 0FH, 02H, none, OmReg);

		InsertMnemo("LEA", k, {i386});
		InsertOp(k, Reg16, M16, 08DH, none, none, OmReg);
		InsertOp(k, Reg16, M32, 08DH, none, none, OmReg);
		(*InsertOp(k, Reg32, M16, 08DH, none, none, OmReg);*)
		InsertOp(k, Reg32, M32, 08DH, none, none, OmReg);

		InsertMnemo("LEAVE", k, {i386});
		InsertOp(k, none, none, 0C9H, none, none, none);

		InsertMnemo("LDS", k, {i386});
		InsertOp(k, Reg16, M16, 0C5H, none, none, OmReg);
		InsertOp(k, Reg32, M32, 0C5H, none, none, OmReg);
		InsertMnemo("LSS", k, {i386});
		InsertOp(k, Reg16, M16, 0FH, 0B2H, none, OmReg);
		InsertOp(k, Reg32, M32, 0FH, 0B2H, none, OmReg);
		InsertMnemo("LES", k, {i386});
		InsertOp(k, Reg16, M16, 0C4H, none, none, OmReg);
		InsertOp(k, Reg32, M32, 0C4H, none, none, OmReg);
		InsertMnemo("LFS", k, {i386});
		InsertOp(k, Reg16, M16, 0FH, 0B4H, none, OmReg);
		InsertOp(k, Reg32, M32, 0FH, 0B4H, none, OmReg);
		InsertMnemo("LGS", k, {i386});
		InsertOp(k, Reg16, M16, 0FH, 0B5H, none, OmReg);
		InsertOp(k, Reg32, M32, 0FH, 0B5H, none, OmReg);
		
		InsertMnemo("LGDT", k, {i386, Privileged});
		InsertOp(k, M, none, 0FH, 01H, 2, none);
		
		InsertMnemo("LIDT", k, {i386, Privileged});
		InsertOp(k, M, none, 0FH, 01H, 3, none);

		InsertMnemo("LOCK", k, {i386});
		InsertOp(k, none, none, 0F0H, none, none, none);

		InsertMnemo("LLDT", k, {i386, Privileged});
		InsertOp(k, RM16, none, 0FH, 00H, 2, none);
		
		InsertMnemo("LMSW", k, {i386, Privileged});
		InsertOp(k, RM16, none, 0FH, 01H, 6, none);

		InsertMnemo("LODSB", k, {i386});
		InsertOp(k, none, none, 0ACH, none, none, none);

		InsertMnemo("LODSW", k, {i386});
		InsertOp(k, none, none, 066H, 0ADH, none, none);

		InsertMnemo("LODSD", k, {i386});
		InsertOp(k, none, none, 0ADH, none, none, none);

		InsertMnemo("LOOP", k, {i386});
		InsertOp(k, Rel8, none, 0E2H, none, none, none);
		
		InsertMnemo("LOOPE", k, {i386});
		InsertOp(k, Rel8, none, 0E1H, none, none, none);
		InsertAlias("LOOPE", "LOOPZ");
		
		InsertMnemo("LOOPNE", k, {i386});
		InsertOp(k, Rel8, none, 0E0H, none, none, none);
		InsertAlias("LOOPNE", "LOOPNZ");

		InsertMnemo("LSL", k, {i386});
		InsertOp(k, Reg16, RM16, 0FH, 03H, none, OmReg);
		InsertOp(k, Reg32, RM32, 0FH, 03H, none, OmReg);

		InsertMnemo("LTR", k, {i386, Privileged});
		InsertOp(k, RM16, none, 0FH, 00H, 3, none);
	END InsertInstr2;
	
	PROCEDURE InsertInstr3;
		VAR i,k: INTEGER;
	BEGIN
		InsertMnemo("MOV", k, {i386});
		InsertOp(k, RM8, Reg8, 88H, none, none, OmReg);
		InsertOp(k, RM16, Reg16, 89H, none, none, OmReg);
		InsertOp(k, RM32, Reg32, 89H, none, none, OmReg);
		InsertOp(k, Reg8, RM8,  8AH, none, none, OmReg);
		InsertOp(k, Reg16, RM16, 8BH, none, none, OmReg);
		InsertOp(k, Reg32, RM32, 8BH, none, none, OmReg);
		InsertOp(k, RM16, SReg, 8CH, none, none, OmReg);
		InsertOp(k, SReg, RM16, 8EH, none, none, OmReg);
		InsertOp(k, Reg8, Imm8,  0B0H, none, none, OmOp);
		InsertOp(k, Reg16, Imm16,  0B8H, none, none, OmOp);
		InsertOp(k, Reg32, Imm32,  0B8H, none, none, OmOp);
		InsertOp(k, RM8, Imm8,  0C6H, none, none, none);
		InsertOp(k, RM16, Imm16,  0C7H, none, none, none);
		InsertOp(k, RM32, Imm32,  0C7H, none, none, none);
		InsertOp(k, Reg32, CRReg, 0FH, 20H, none, OmReg);
		InsertOp(k, CRReg, Reg32, 0FH, 22H, none, OmReg);
		InsertOp(k, Reg32, DRReg, 0FH, 21H, none, OmReg);
		InsertOp(k, DRReg, Reg32, 0FH, 23H, none, OmReg);
		InsertOp(k, Reg32, TRReg, 0FH, 24H, none, OmReg);
		InsertOp(k, TRReg, Reg32, 0FH, 26H, none, OmReg);

		InsertMnemo("MOVSB", k, {i386});
		InsertOp(k, none, none, 0A4H, none, none, none);
		
		InsertMnemo("MOVSW", k, {i386});
		InsertOp(k, none, none, 066H, 0A5H, none, none);
		
		InsertMnemo("MOVSD", k, {i386});
		InsertOp(k, none, none, 0A5H, none, none, none);
		
		InsertMnemo("MOVSX", k, {i386});
		InsertOp(k, Reg16, RM8, 0FH, 0BEH, none, OmReg);
		InsertOp(k, Reg32, RM8, 0FH, 0BEH, none, OmReg);
		InsertOp(k, Reg32, RM16, 0FH, 0BFH, none, OmReg);
		
		InsertMnemo("MOVZX", k, {i386});
		InsertOp(k, Reg16, RM8, 0FH, 0B6H, none, OmReg);
		InsertOp(k, Reg32, RM8, 0FH, 0B6H, none, OmReg);
		InsertOp(k, Reg32, RM16, 0FH, 0B7H, none, OmReg);

		InsertMnemo("MUL", k, {i386});
		InsertOp(k, RegAL, RM8, 0F6H, none, 4, none);
		InsertOp(k, RegAX, RM16, 0F7H, none, 4, none);
		InsertOp(k, RegEAX, RM32, 0F7H, none, 4, none);
		InsertOp(k, RM8, none, 0F6H, none, 4, none);
		InsertOp(k, RM16, none, 0F7H, none, 4, none);
		InsertOp(k, RM32, none, 0F7H, none, 4, none);
		
		InsertMnemo("NEG", k, {i386});
		InsertOp(k, RM8, none, 0F6H, none, 3, none);
		InsertOp(k, RM16, none, 0F7H, none, 3, none);
		InsertOp(k, RM32, none, 0F7H, none, 3, none);

		InsertMnemo("NOP", k, {i386});
		InsertOp(k, none, none, 090H, none, none, none);
		
		InsertMnemo("NOT", k, {i386});
		InsertOp(k, RM8, none, 0F6H, none, 2, none);
		InsertOp(k, RM16, none, 0F7H, none, 2, none);
		InsertOp(k, RM32, none, 0F7H, none, 2, none);

		InsertMnemo("OUT", k, {i386});
		InsertOp(k, Imm8, RegAL, 0E6H, none, none, none);
		InsertOp(k, Imm8, RegAX, 0E7H, none, none, none);
		InsertOp(k, Imm8, RegEAX, 0E7H, none, none, none);
		InsertOp(k, RegDX, RegAL, 0EEH, none, none, none);
		InsertOp(k, RegDX, RegAX, 0EFH, none, none, none);
		InsertOp(k, RegDX, RegEAX, 0EFH, none, none, none);

		InsertMnemo("OUTSB", k, {i386});
		InsertOp(k, none, none, 06EH, none, none, none);
		InsertMnemo("OUTSW", k, {i386});
		InsertOp(k, none, none, 066H, 06FH, none, none);
		InsertMnemo("OUTSD", k, {i386});
		InsertOp(k, none, none, 06FH, none, none, none);

		InsertMnemo("POP", k, {i386});
		InsertOp(k, M32, none, 08FH, none, 0, none);
		InsertOp(k, Reg32, none, 058H, none, none, OmOp);
		InsertOp(k, RegDS, none, 01FH, none, none, none);
		InsertOp(k, RegES, none, 07H, none, none, none);
		InsertOp(k, RegSS, none, 017H, none, none, none);
		InsertOp(k, RegFS, none, 0FH, 0A1H, none, none);
		InsertOp(k, RegGS, none, 0FH, 0A9H, none, none);
		
		InsertMnemo("POPAD", k, {i386});
		InsertOp(k, none, none, 061H, none, none, none);

		InsertMnemo("POPFD", k, {i386});
		InsertOp(k, none, none, 09DH, none, none, none);

		InsertMnemo("PUSH", k, {i386});
		InsertOp(k, Reg32, none, 050H, none, none, OmOp);
		InsertOp(k, SImm8, none, 06AH, none, none, none);
		InsertOp(k, Imm32, none, 068H, none, none, none);
		InsertOp(k, M32, none, 0FFH, none, 6, none);
		InsertOp(k, RegCS, none, 0EH, none, none, none);
		InsertOp(k, RegDS, none, 01EH, none, none, none);
		InsertOp(k, RegES, none, 06H, none, none, none);
		InsertOp(k, RegSS, none, 016H, none, none, none);
		InsertOp(k, RegFS, none, 0FH, 0A0H, none, none);
		InsertOp(k, RegGS, none, 0FH, 0A8H, none, none);
	END InsertInstr3;
		
	PROCEDURE InsertInstr4;
		VAR i,k: INTEGER;
	BEGIN
		InsertMnemo("PUSHAD", k, {i386});
		InsertOp(k, none, none, 060H, none, none, none);

		InsertMnemo("PUSHFD", k, {i386});
		InsertOp(k, none, none, 09CH, none, none, none);

		FOR i := 0 TO 7 DO
			CASE i OF
				  0: InsertMnemo("ROL", k, {i386})
				| 1: InsertMnemo("ROR", k, {i386})
				| 2: InsertMnemo("RCL", k, {i386})
				| 3: InsertMnemo("RCR", k, {i386})
				| 4: InsertMnemo("SHL", k, {i386})
				| 5: InsertMnemo("SHR", k, {i386})
				| 6:  (*SAL*)
				| 7: InsertMnemo("SAR", k, {i386})
			END;
			IF i = 6 THEN ELSE
				InsertOp(k, RM8, Const1, 0D0H, none, i, none);
				InsertOp(k, RM8, RegCL, 0D2H, none, i, none);
				InsertOp(k, RM8, Imm8, 0C0H, none, i, none);
				InsertOp(k, RM16, Const1, 0D1H, none, i, none);
				InsertOp(k, RM16, RegCL, 0D3H, none, i, none);
				InsertOp(k, RM16, Imm8, 0C1H, none, i, none);
				InsertOp(k, RM32, Const1, 0D1H, none, i, none);
				InsertOp(k, RM32, RegCL, 0D3H, none, i, none);
				InsertOp(k, RM32, Imm8, 0C1H, none, i, none)
			END
		END;
		InsertAlias("SHL", "SAL");
		
		InsertMnemo("REP", k, {i386});
		InsertOp(k, none, none, 0F3H, none, none, none);
		InsertAlias("REP", "REPE"); InsertAlias("REP", "REPZ");
		InsertMnemo("REPNE", k, {i386});
		InsertOp(k, none, none, 0F2H, none, none, none);
		InsertAlias("REPNE", "REPNZ");

		InsertMnemo("RET", k, {i386});
		InsertOp(k, none, none, 0C3H, none, none, none);
		InsertOp(k, Imm16, none, 0C2H, none, none, none);

		InsertMnemo("RDMSR", k, {Pentium, Privileged});
		InsertOp(k, none, none, 0FH, 32H, none, none);

		InsertMnemo("RDPMC", k, {PentiumPro, Privileged});
		InsertOp(k, none, none, 0FH, 33H, none, none);

		InsertMnemo("RDTSC", k, {Pentium});
		InsertOp(k, none, none, 0FH, 31H, none, none);

		InsertMnemo("SAHF", k, {i386});
		InsertOp(k, none, none, 09EH, none, none, none);

		InsertMnemo("SCASB", k, {i386});
		InsertOp(k, none, none, 0AEH, none, none, none);
		InsertMnemo("SCASW", k, {i386});
		InsertOp(k, none, none, 66H, 0AFH, none, none);
		InsertMnemo("SCASD", k, {i386});
		InsertOp(k, none, none, 0AFH, none, none, none);

		FOR i:=0 TO 0FH DO
			CASE i OF
				   0: InsertMnemo("SETO", k, {i386})
				| 1: InsertMnemo("SETNO", k, {i386})
				| 2: InsertMnemo("SETB", k, {i386})
				| 3: InsertMnemo("SETNB", k, {i386})
				| 4: InsertMnemo("SETZ", k, {i386})
				| 5: InsertMnemo("SETNZ", k, {i386})
				| 6: InsertMnemo("SETBE", k, {i386})
				| 7: InsertMnemo("SETNBE", k, {i386})
				| 8: InsertMnemo("SETS", k, {i386})
				| 9: InsertMnemo("SETNS", k, {i386})
				| 0AH: InsertMnemo("SETP", k, {i386})
				| 0BH: InsertMnemo("SETNP", k, {i386})
				| 0CH: InsertMnemo("SETL", k, {i386})
				| 0DH: InsertMnemo("SETNL", k, {i386})
				| 0EH: InsertMnemo("SETLE", k, {i386})
				| 0FH: InsertMnemo("SETNLE", k, {i386})
			END;
			InsertOp(k, RM8, none, 0FH, 90H + i, none, none);
		END;
		InsertAlias("SETB", "SETC");
		InsertAlias("SETNB", "SETAE");
		InsertAlias("SETZ", "SETE");
		InsertAlias("SETNBE", "SETA");
		InsertAlias("SETNL", "SETGE");
		InsertAlias("SETNLE", "SETG");
		InsertAlias("SETBE", "SETNA");
		InsertAlias("SETB", "SETNAE");
		InsertAlias("SETNB", "SETNC");
		InsertAlias("SETNZ", "SETNE");
		InsertAlias("SETLE", "SETNG");
		InsertAlias("SETL", "SETNGE");
		InsertAlias("SETP", "SETPE");
		InsertAlias("SETNP", "SETPO");

		InsertMnemo("SGDT", k, {i386});
		InsertOp(k, M, none, 0FH, 01H, 0, none);
		InsertMnemo("SIDT", k, {i386});
		InsertOp(k, M, none, 0FH, 01H, 1, none);

		InsertMnemo("SHLD", k, {i386});
		InsertOp3(k, RM16, Reg16, Imm8, 0FH, 0A4H, none, OmReg);
		InsertOp3(k, RM32, Reg32, Imm8, 0FH, 0A4H, none, OmReg);
		InsertOp3(k, RM16, Reg16, RegCL, 0FH, 0A5H, none, OmReg);
		InsertOp3(k, RM32, Reg32, RegCL, 0FH, 0A5H, none, OmReg);

		InsertMnemo("SHRD", k, {i386});
		InsertOp3(k, RM16, Reg16, Imm8, 0FH, 0ACH, none, OmReg);
		InsertOp3(k, RM32, Reg32, Imm8, 0FH, 0ACH, none, OmReg);
		InsertOp3(k, RM16, Reg16, RegCL, 0FH, 0ADH, none, OmReg);
		InsertOp3(k, RM32, Reg32, RegCL, 0FH, 0ADH, none, OmReg);

		InsertMnemo("SMSW", k, {i386});
		InsertOp(k, RM16, none, 0FH, 01H, 4, none);

		InsertMnemo("SLDT", k, {i386});
		InsertOp(k, RM16, none, 0FH, 00H, 0, none);

		InsertMnemo("STOSB", k, {i386});
		InsertOp(k, none, none, 0AAH, none, none, none);

		InsertMnemo("STOSW", k, {i386});
		InsertOp(k, none, none, 066H, 0ABH, none, none);

		InsertMnemo("STOSD", k, {i386});
		InsertOp(k, none, none,  0ABH, none, none, none);

		InsertMnemo("STR", k, {i386});
		InsertOp(k, RM16, none,  0FH, 00H, 1, none);

		InsertMnemo("TEST", k, {i386});
		InsertOp(k, RegAL, Imm8,  0A8H, none, none, none);
		InsertOp(k, RegAX, Imm16,  0A9H, none, none, none);
		InsertOp(k, RegEAX, Imm32,  0A9H, none, none, none);
		InsertOp(k, RM8, Imm8,  0F6H, none, 0, none);
		InsertOp(k, RM16, Imm16,  0F7H, none, 0, none);
		InsertOp(k, RM32, Imm32,  0F7H, none, 0, none);
		InsertOp(k, RM8, Reg8,  084H, none, none, OmReg);
		InsertOp(k, RM16, Reg16,  085H, none, none, OmReg);
		InsertOp(k, RM32, Reg32,  085H, none, none, OmReg);

		InsertMnemo("VERR", k, {i386});
		InsertOp(k, RM16, none,  0FH, 00H, 4, none);

		InsertMnemo("VERW", k, {i386});
		InsertOp(k, RM16, none,  0FH, 00H, 5, none);

		InsertMnemo("WAIT", k, {i386, FPU});
		InsertOp(k, none, none,  09BH, none, none, none);

		InsertMnemo("WBINVD", k, {i486, Privileged});
		InsertOp(k, none, none,  0FH, 09H, none, none);

		InsertMnemo("WRMSR", k, {Pentium, Privileged});
		InsertOp(k, none, none, 0FH, 30H, none, none);

		InsertMnemo("XADD", k, {i486});
		InsertOp(k, RM8, Reg8,  0FH, 0C0H, none, OmReg);
		InsertOp(k, RM16, Reg16,  0FH, 0C1H, none, OmReg);
		InsertOp(k, RM32, Reg32,  0FH, 0C1H, none, OmReg);

		InsertMnemo("XLATB", k, {i386});
		InsertOp(k, none, none,  0D7H, none, none, none);

		InsertMnemo("XCHG", k, {i386});
		InsertOp(k, RegAX, Reg16, 090H, none, none, OmOp);
		InsertOp(k, Reg16, RegAX, 090H, none, none, OmOp);
		InsertOp(k, RegEAX, Reg32, 090H, none, none, OmOp);
		InsertOp(k, Reg32, RegEAX, 090H, none, none, OmOp);
		InsertOp(k, RM8, Reg8, 086H, none, none, OmReg);
		InsertOp(k, Reg8, RM8, 086H, none, none, OmReg);
		InsertOp(k, RM16, Reg16, 087H, none, none, OmReg);
		InsertOp(k, Reg16, RM16, 087H, none, none, OmReg);
		InsertOp(k, RM32, Reg32, 087H, none, none, OmReg);
		InsertOp(k, Reg32, RM32, 087H, none, none, OmReg);
	END InsertInstr4;
	

PROCEDURE Insert(nofInstr, nofOps: INTEGER);
VAR k: INTEGER;
BEGIN
	InstrTabLen := nofInstr;  OpTabLen := nofOps;
	OpTabN := 0; Average := 0; InstrCount := 0;
	NEW(InstrTab, InstrTabLen); NEW(OpTab, OpTabLen);
	FOR k:= 0 TO OpTabLen-1 DO OpTab[k].op0 := -1 END;
	FOR k:= 0 TO InstrTabLen-1 DO InstrTab[k].name[0] := 0X END;
	FOR k := 0 TO LEN(Clash)-1 DO  Clash[k] := 0  END;
	InsertInstr1;	InsertInstr2;	InsertInstr3;	InsertInstr4;	InsertFloatInstr1;	InsertFloatInstr2;
END Insert;


(* Commands *)

PROCEDURE FindSize*;		(** min-size max-size OpTableSize *)
VAR k, j, min, max: INTEGER; S: Texts.Scanner; i: LONGINT; lr: LONGREAL; bestV, best: LONGINT;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S); min := SHORT(S.i);
	Texts.Scan(S); max := SHORT(S.i);
	Texts.Scan(S); OpTabLen := SHORT(S.i);
	
	bestV := MAX(LONGINT);
	Texts.WriteString(W, "Table Size (KB)   Avg Search Len"); Texts.WriteLn(W);
	FOR j := min TO max DO
		Insert(j, OpTabLen);
		Texts.WriteInt(W, j, 10); Texts.WriteString(W, "/  "); 
		Texts.WriteLongRealFix(W, j*SIZE(InstrDesc) / 1024, 4, 2, 0);
		Texts.WriteString(W, ":  "); Texts.WriteLongRealFix(W, Average / InstrCount, 8, 2, 0); Texts.WriteLn(W);
		IF Average < bestV THEN  bestV := Average;  best := j  END;
		Texts.Append(Oberon.Log, W.buf)
	END;
	
	Texts.WriteLn(W);
	Texts.WriteString(W, "Best: "); Texts.WriteInt(W, best, 4); Texts.WriteString(W, "  avg = "); 
	Texts.WriteLongRealFix(W, bestV / InstrCount, 8, 2, 0); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf)
END FindSize;

PROCEDURE FillTable*;		(** InstrTableSize OpTableSize *)
VAR k, j: INTEGER; S: Texts.Scanner; lr: LONGREAL;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S); k := SHORT(S.i);
	Texts.Scan(S); j := SHORT(S.i);
	Insert(k, j);
	
	Texts.WriteString(W, "InstrTab : "); Texts.WriteInt(W, InstrCount,1); Texts.WriteString(W, "/"); Texts.WriteInt(W, InstrTabLen,1); 
	Texts.WriteRealFix(W, InstrCount/InstrTabLen*100, 5, 2, 0); Texts.WriteString(W, "% used"); Texts.WriteLn(W);
	Texts.WriteString(W, "Table size: "); Texts.WriteLongRealFix(W, j*SIZE(InstrDesc) / 1024, 4, 2, 0); 
	Texts.WriteString(W, "KB"); Texts.WriteLn(W);
	Texts.WriteString(W, "Hash-Table Lookups / Instruction:"); Texts.WriteLn(W);
	lr := 0.0;
	FOR k := 0 TO (LEN(Clash) DIV 4)-1 DO
		lr := lr + Clash[k] * k;
		lr := lr + Clash[k+8] * (k+8);
		lr := lr + Clash[k+16] * (k+16);
		lr := lr + Clash[k+24] * (k+24);
		Texts.WriteInt(W, k+1, 8); Texts.WriteString(W, ": "); Texts.WriteInt(W, Clash[k], 3); Texts.WriteString(W, "           ");
		Texts.WriteInt(W, k+9, 8); Texts.WriteString(W, ": "); Texts.WriteInt(W, Clash[k+8], 3); Texts.WriteString(W, "           ");
		Texts.WriteInt(W, k+17, 8); Texts.WriteString(W, ": "); Texts.WriteInt(W, Clash[k+16], 3); Texts.WriteString(W, "           ");
		Texts.WriteInt(W, k+25, 8); 
		IF k+24 = LEN(Clash)-1 THEN Texts.Write(W, "+") END;
		Texts.WriteString(W, ": "); Texts.WriteInt(W, Clash[k+24], 3); Texts.WriteLn(W)
	END;
	Texts.WriteString(W, "Lookup/Instruction (average): "); Texts.WriteLongRealFix(W, lr / InstrCount, 8, 2, 0); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf)
END FillTable;

PROCEDURE ExportTables*;
VAR f: Files.File; r: Files.Rider; i: LONGINT;
BEGIN
	Texts.WriteString(W, "Creating "); Texts.WriteString(W, FileName);
	f := Files.New(FileName); Files.Set(r, f, 0);
	
	Texts.WriteString(W, " with InstrTabLen = "); Texts.WriteInt(W, InstrTabLen, 0);
	Files.WriteInt(r, InstrTabLen);
	FOR i := 0 TO InstrTabLen-1 DO
		Files.WriteString(r, InstrTab[i].name);
		IF InstrTab[i].name # "" THEN
			Files.WriteInt(r, InstrTab[i].start); Files.WriteInt(r, InstrTab[i].end);
			Files.WriteSet(r, InstrTab[i].target)
		END
	END;
	
	Texts.WriteString(W, " and OpTabLen = "); Texts.WriteInt(W, OpTabN, 0); Texts.WriteLn(W);
	Texts.WriteInt(W, Files.Pos(r),1); Texts.WriteLn(W);
	Files.WriteInt(r, OpTabN);
	FOR i:= 0 TO OpTabN-1 DO
		Files.WriteInt(r, OpTab[i].op[0]); Files.WriteInt(r, OpTab[i].op[1]); Files.WriteInt(r, OpTab[i].op[2]);
		Files.WriteInt(r, OpTab[i].op0); Files.WriteInt(r, OpTab[i].op1);
		Files.WriteInt(r, OpTab[i].opc); Files.WriteInt(r, OpTab[i].reg)
	END;
	Files.Register(f);
	Texts.Append(Oberon.Log, W.buf)
END ExportTables;

PROCEDURE DumpInstructions*;
	VAR f: Files.File; r: Files.Rider; t: Texts.Text;
		low, best: Mnemo; size, i, j, bestIdx, count: LONGINT;
BEGIN
	Docu := TRUE;
	
	(*read table*)
	f := Files.Old(FileName);
	IF f # NIL THEN
		Files.Set(r, f, 0);
		count := 0;
		Files.ReadInt(r, InstrTabLen);  NEW(InstrTab, InstrTabLen);
		FOR i := 0 TO InstrTabLen-1 DO
			Files.ReadString(r, InstrTab[i].name);
			IF InstrTab[i].name # "" THEN
				INC(count);
				Files.ReadInt(r, InstrTab[i].start); Files.ReadInt(r, InstrTab[i].end);
				Files.ReadSet(r, InstrTab[i].target)
			END
		END;
		Files.ReadInt(r, OpTabLen);  NEW(OpTab, OpTabLen);
		FOR i:= 0 TO OpTabLen-1 DO
			Files.ReadInt(r, OpTab[i].op[0]); Files.ReadInt(r, OpTab[i].op[1]); Files.ReadInt(r, OpTab[i].op[2]);
			Files.ReadInt(r, OpTab[i].op0); Files.ReadInt(r, OpTab[i].op1);
			Files.ReadInt(r, OpTab[i].opc); Files.ReadInt(r, OpTab[i].reg)
		END;
		Files.Close(f)
	ELSE
		RETURN
	END;
	Texts.WriteString(W, "<HTML><TITLE>Native / Assembler Instructions</TITLE>"); Texts.WriteLn(W);
	Texts.WriteString(W, "<BODY>"); Texts.WriteLn(W);
	Texts.WriteString(W, "<H3>Supported Assembler Instructions</H3>"); Texts.WriteLn(W);
	Texts.WriteString(W, "<HR>"); Texts.WriteLn(W);
	Texts.WriteString(W, "<TABLE border=1><TR><TH align=left>Instr</TH><TH align=left>Operands</TH><TH align=left>Target</TH><TH align=left>Mode</TH></TR>");
	Texts.WriteLn(W);

	(*create index*)
	low := "";
	FOR i := 0 TO count-1 DO
		best := "ZZZZ";
		FOR j := 0 TO InstrTabLen-1 DO
			IF (InstrTab[j].name > low) & (InstrTab[j].name < best) THEN
				bestIdx := j;  best := InstrTab[j].name
			END
		END;
		low := best;
		size := InstrTab[bestIdx].end-InstrTab[bestIdx].start;
		Texts.WriteString(W, "<TR><TD rowspan="); Texts.WriteInt(W, size, 0);
		Texts.WriteString(W, ">"); Texts.WriteString(W, best); Texts.WriteString(W, "</TD><TD>");
		FOR j := InstrTab[bestIdx].start TO InstrTab[bestIdx].end-1 DO
			IF j # InstrTab[bestIdx].start THEN  Texts.WriteString(W, "<TR><TD>")  END;
			IF OpTab[j].op[0] # none THEN
				DumpMode(W, OpTab[j].op[0]);
				IF OpTab[j].op[1] # none THEN
					Texts.WriteString(W, ", "); DumpMode(W, OpTab[j].op[1]);
					IF OpTab[j].op[2] # none THEN
						Texts.WriteString(W, ", "); DumpMode(W, OpTab[j].op[2])
					END
				END
			END;
			Texts.WriteString(W, "</TD>");
			IF j = InstrTab[bestIdx].start THEN
				Texts.WriteString(W, "<TD rowspan="); Texts.WriteInt(W, size , 0);
				Texts.WriteString(W, ">");
				IF i386 IN InstrTab[bestIdx].target THEN  Texts.WriteString(W, "386")
				ELSIF i486 IN InstrTab[bestIdx].target THEN  Texts.WriteString(W, "486")
				ELSIF Pentium IN InstrTab[bestIdx].target THEN  Texts.WriteString(W, "Pentium")
				ELSIF PentiumPro IN InstrTab[bestIdx].target THEN  Texts.WriteString(W, "PentiumPro")
				ELSE (*Texts.WriteString(W, "Unknown")*)
				END;
				IF {FPU, Privileged} *  InstrTab[bestIdx].target # {} THEN
					Texts.WriteString(W, "<TD rowspan="); Texts.WriteInt(W, size, 0);
					Texts.WriteString(W, ">");
					IF FPU IN InstrTab[bestIdx].target THEN Texts.WriteString(W, "FPU ") END;
					IF Privileged IN InstrTab[bestIdx].target THEN Texts.WriteString(W, "Privileged") END;
					Texts.WriteString(W, "</TD>")
				END;
				Texts.WriteString(W, "</TD>")
			END;
			Texts.WriteString(W, "</TR>"); Texts.WriteLn(W);
		END;
		Texts.WriteLn(W)
	END;
	Texts.WriteString(W, "</TABLE></BODY>"); Texts.WriteLn(W);
	NEW(t); Texts.Open(t, ""); Texts.Append(t, W.buf);
	Oberon.OpenText("instructions.html", t, 640, 400)
END DumpInstructions;
	
BEGIN	Docu := FALSE; Texts.OpenWriter(W)
END OPAData.


OPAData.FindSize  450 700  673		#search for a good table size

OPAData.FillTable InstrTabLen OpTabLen
															# create the table; the length refers to the hash table
OPAData.FillTable 684  673				#create the tables

OPAData.ExportTables						#create the data file

OPAData.DumpInstructions				#dump the instructions (for docs)


OPA.Data
