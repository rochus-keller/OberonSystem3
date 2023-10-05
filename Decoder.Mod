(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zürich Institute for Computer Systems, 
ETH Center, CH-8092 Zürich. e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract. The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE Decoder;	(** non-portable *) (* NM 2.3.93 / 26.10.93 *)

(* Niklaus Mannhart, Patrik Reali, Pieter Muller *)

	IMPORT Modules, Files, Fonts, Texts, Objects, Display, Oberon, Strings, Out, SYSTEM;

	CONST
		(* prefix *)
		pCS = 2EH; pDS = 3EH; pES = 26H; pFS = 64H; pGS = 65H; pSS = 36H;
		AdrSize = 67H; OpSize = 66H; none = -1;
		
		(* output *)
		PCpos = 0; HexPos = 7; OpPosC = 43; RMPosC = 52; Pos1 = 4;
		OffPos = 35;

		(* addressing modes *)
		Reg = 0; (* Register *)
		Mem1 = 1; (* addressing mode 1 *)
		Mem2 = 2; (* addressing mode 2 *)
		RegImm = 3; (* immediate to register *)
		MemImm = 4; (* memory to register *)
		MemFull = 5; (* full 32 bit adr *)

		(* i386 Register *)
		EAX = 0; ECX = 1; EDX = 2; EBX = 3; ESP = 4; EBP = 5; ESI = 6; EDI = 7; (* 32 bit register *)
		AX = 0; CX = 1; DX = 2; BX = 3; SP =  4; BP = 5; SI = 6; DI = 7; (* 16 bit register *)
		AL = 0; CL = 1; DL = 2; BL = 3; AH = 4; CH = 5; DH = 6; BH = 7; (* 8 bit register *)
		ES = 20; CS = 21; SS = 22; DS = 23; FS = 24; GS = 25;  (* 6, 7 reserved *) (* Segment register *)
		CR = 0; DR = 8; TR = 16;

		(* i387 *)
		SReal = 0; (* single real 32 bit*)
		LReal = 1; (* long real 64 bit *)
		EReal = 2; (* extended real 80 bit *)
		WInt = 3; (* word integer 16 bit *)
		SInt = 4; (* single integer 32 bit *)
		LInt = 5; (* long integer 64 bit *)
		Byte14 = 6; Byte28 = 7; Byte94 = 8; Byte108 = 9;
		Decimal = 10; (* BCD *)
		nothing = 11;

		(* size *)
		Byte = 0; SignExt = 1; (* sign extended *)

		BUG = 40;

		(* String constants, define only once to avoid err 230 *)
		VarEntriesStr = "VarEntries:";
		EntriesStr = "Entries:";
		CommandsStr = "Commands:";
		PointersStr = "Pointers:";
		DataStr = "Data:";
		ConstStr = "Const:     ";
		CodeStr = "Code:     ";
		nofEntriesStr = "  nofEntries:      ";
		nofCmdsStr = "  nofCmds:         ";
		nofPtrsStr = "  nofPtrs:         ";
		nofTypesStr = "  nofTds:          ";
		nofImpsStr = "  nofImps:         ";
		dataSizeStr = "  dataSize:        ";
		constSizeStr = "  conSize:         ";
		codeSizeStr = "  codeSize:        ";
		refSizeStr = "  refSize:         ";
		
		
		(*Targets*)
		Priv = 16;
		i486 = 1; Pentium = 2; PPro = 3;

	TYPE
		ProcArray = POINTER TO ARRAY OF ProcEntry;
		ProcEntry = RECORD
			name: ARRAY 64 OF CHAR;
			point: LONGINT
		END;
		EntryArray = POINTER TO ARRAY OF LONGINT;
		
	VAR
		R, Ref: Files.Rider; (* Rider for Object file *)
		W: Texts.Writer; (* Writer for output on screen *)
		pc, breakpos: LONGINT; column: INTEGER; (* curser position in the current line *)
		prefix, w: INTEGER; adrPrefix, opPrefix: BOOLEAN;
		defaultFont, titleFont: Fonts.Font;
		PE: ProcArray;
		nofPE: LONGINT;
		memory, compilable, suppressOut, suppressH: BOOLEAN;
		ReadAdr: LONGINT;
		target: SET;
		objSuffix: ARRAY 8 OF CHAR;
		OpPos, RMPos: SHORTINT;


(* general Procedures *)

	PROCEDURE Bug (no: INTEGER);
	BEGIN
		Texts.WriteLn(W);  Texts.WriteString(W, "*** decode error ***");
		Texts.WriteLn(W);
		(*Texts.Append(T, W.buf);
		HALT(BUG)*)
	END Bug;

	PROCEDURE Next (VAR ch: CHAR);
	BEGIN
		INC(pc);
		IF memory THEN SYSTEM.GET (ReadAdr, ch); INC (ReadAdr)
		ELSE Files.Read(R, ch)
		END;
		(* IF pc = breakpos THEN Texts.SetFont(W, Fonts.This("Syntax12b.Scn.Fnt"))
		ELSE Texts.SetFont(W, defaultFont)
		END *)
	END Next;

	PROCEDURE GetByte (VAR b: INTEGER);
		VAR ch: CHAR;
	BEGIN
		Next(ch);
		b:= ORD(ch)
	END GetByte;

	PROCEDURE GetWord (VAR w: LONGINT);
		VAR ch: CHAR;
	BEGIN
		Next(ch); w:= ORD(ch);
		Next(ch);  w:= LONG(ORD(ch)) * 100H + w
	END GetWord;
	
	PROCEDURE GetDWord (VAR dw: LONGINT);
		VAR ch: CHAR; byte: INTEGER;
	BEGIN 
		Next(ch); dw:= LONG(ORD(ch));
		Next(ch); dw:= LONG(ORD(ch)) * 100H + dw;
		Next(ch); dw:= LONG(ORD(ch)) * 10000H + dw;
		GetByte(byte); 
		IF byte >= 128 THEN byte:= byte - 256 END;
		dw:= LONG(byte) * 1000000H + dw
	END GetDWord;
	
	PROCEDURE GetNum (VAR x: LONGINT);
		VAR ch: CHAR; n: INTEGER; y: LONGINT;
	BEGIN n := 0; y := 0; Next (ch);
		WHILE ch >= 80X DO INC(y, SYSTEM.LSH(LONG(ch) - 128, n)); INC(n, 7); Next (ch) END;
		x := ASH(SYSTEM.LSH(LONG(ch), 25), n-25) + y
	END GetNum;
	
	PROCEDURE WriteLn; 
	BEGIN
		Texts.WriteLn(W); column:= 0
	END WriteLn;

	PROCEDURE WriteString (str: ARRAY OF CHAR);
	BEGIN
		IF ~suppressOut THEN	Texts.WriteString(W, str); column:= column + SHORT(LEN(str))	END
	END WriteString;
	
	PROCEDURE Write (ch: CHAR);
	BEGIN
		IF ~suppressOut THEN	Texts.Write(W, ch); INC(column)	END
	END Write;
	
	PROCEDURE WriteByte (byte: INTEGER);
	(* write byte in hexadecimal form *)

		PROCEDURE WriteHex(d: INTEGER);
		BEGIN
			IF d > 9 THEN Write(CHR(41H + d - 10))
			ELSE Write(CHR(30H + d))
			END
		END WriteHex;

	BEGIN (* WriteByte *)
		WriteHex(byte DIV 16); WriteHex(byte MOD 16);
		IF (~suppressH) & (column >= OpPos) THEN Write("H") END
	END WriteByte;
	
	PROCEDURE WriteWord (word: LONGINT);
	(* write word in byte form, little endian notation *)
	BEGIN
		WriteByte(SHORT(word MOD 100H)); Write(" ");
		WriteByte(SHORT(word DIV 100H) MOD 100H)
	END WriteWord;
	
	PROCEDURE WriteDWord (dword: LONGINT);
	(* write dword in byte form, little endian notation *)
	BEGIN
		WriteWord(dword MOD 10000H); Write(" ");
		WriteWord((dword DIV 10000H) MOD 10000H)
	END WriteDWord;
	
	PROCEDURE WriteWHex (word: LONGINT);
	(* write word hexadecimal *)
		VAR b: BOOLEAN;
	BEGIN
		b := suppressH; suppressH := TRUE;
		WriteByte(SHORT(word DIV 100H)); WriteByte(SHORT(word MOD 100H));
		IF ~b & (column >= OpPos) THEN Write("H") END;
		suppressH := b;
	END WriteWHex;
	
	PROCEDURE WriteDWHex (dword: LONGINT);
		VAR b: BOOLEAN;
	BEGIN
		b := suppressH; suppressH := TRUE;
		WriteWHex(dword DIV 10000H MOD 10000H); WriteWHex(dword MOD 10000H);
		IF ~b & (column >= OpPos) THEN Write("H") END;
		suppressH := b;
	END WriteDWHex;
	
	PROCEDURE WriteDisp (disp: LONGINT);
	BEGIN
		Texts.WriteInt(W, disp, 1);
		IF disp = MIN(LONGINT) THEN INC(column, 12)	(* " -2147483648" *)
		ELSE
			IF disp <= 0 THEN INC(column) END;
			disp:= ABS(disp);
			WHILE disp # 0 DO
				disp:= disp DIV 10;
				INC(column)
			END
		END
	END WriteDisp;
	
	PROCEDURE Tab (pos: INTEGER);
	BEGIN
		IF ~suppressOut THEN
			WHILE column < pos DO Write(" ") END
		END
	END Tab;

	PROCEDURE WriteOp (opStr: ARRAY OF CHAR);
	BEGIN
		suppressOut := FALSE;
		Tab(OpPos); WriteString(opStr); Tab(RMPos)
	END WriteOp;

	PROCEDURE WriteReg (reg: INTEGER);
	(* w = 0: 8 bit; w = 1: 16/32 bit *)
	BEGIN
		IF reg >= ES (*DS*) THEN 					(*  <<<< MH 15.3.1994 *)
			IF reg = CS THEN WriteString("cs")
			ELSIF reg = DS THEN WriteString("ds")
			ELSIF reg = ES THEN WriteString("es")
			ELSIF reg = SS THEN WriteString("ss")
			ELSIF reg = FS THEN WriteString("fs")
			ELSIF reg = GS THEN WriteString("gs")
			ELSE Bug(BUG)
			END
		ELSIF w = 0 THEN
			IF reg = 0 THEN WriteString("al")
			ELSIF reg = 1 THEN WriteString("cl")
			ELSIF reg = 2 THEN WriteString("dl")
			ELSIF reg = 3 THEN WriteString("bl")
			ELSIF reg = 4 THEN WriteString("ah")
			ELSIF reg = 5 THEN WriteString("ch")
			ELSIF reg = 6 THEN WriteString("dh")
			ELSIF reg = 7 THEN WriteString("bh")
			ELSE Bug(BUG)
			END
		ELSIF opPrefix THEN
			IF reg = 0 THEN WriteString("ax")
			ELSIF reg = 1 THEN WriteString("cx")
			ELSIF reg = 2 THEN WriteString("dx")
			ELSIF reg = 3 THEN WriteString("bx")
			ELSIF reg = 4 THEN WriteString("sp")
			ELSIF reg = 5 THEN WriteString("bp")
			ELSIF reg = 6 THEN WriteString("si")
			ELSIF reg = 7 THEN WriteString("di")
			ELSE Bug(BUG)
			END
		ELSE
			IF reg = 0 THEN WriteString("eax")
			ELSIF reg = 1 THEN WriteString("ecx")
			ELSIF reg = 2 THEN WriteString("edx")
			ELSIF reg = 3 THEN WriteString("ebx")
			ELSIF reg = 4 THEN WriteString("esp")
			ELSIF reg = 5 THEN WriteString("ebp")
			ELSIF reg = 6 THEN WriteString("esi")
			ELSIF reg = 7 THEN WriteString("edi")
			ELSE Bug(BUG)
			END
		END
	END WriteReg;

	PROCEDURE WriteAdrReg(reg: INTEGER);
	BEGIN
		IF adrPrefix THEN
			IF reg = 0 THEN WriteString("ax")
			ELSIF reg = 1 THEN WriteString("cx")
			ELSIF reg = 2 THEN WriteString("dx")
			ELSIF reg = 3 THEN WriteString("bx")
			ELSIF reg = 4 THEN WriteString("sp")
			ELSIF reg = 5 THEN WriteString("bp")
			ELSIF reg = 6 THEN WriteString("si")
			ELSIF reg = 7 THEN WriteString("di")
			ELSE Bug(BUG)
			END
		ELSE
			IF reg = 0 THEN WriteString("eax")
			ELSIF reg = 1 THEN WriteString("ecx")
			ELSIF reg = 2 THEN WriteString("edx")
			ELSIF reg = 3 THEN WriteString("ebx")
			ELSIF reg = 4 THEN WriteString("esp")
			ELSIF reg = 5 THEN WriteString("ebp")
			ELSIF reg = 6 THEN WriteString("esi")
			ELSIF reg = 7 THEN WriteString("edi")
			ELSE Bug(BUG)
			END
		END
	END WriteAdrReg;
	
	PROCEDURE WriteSpecialReg(reg: INTEGER);
	BEGIN
		IF reg >= TR THEN
			WriteString("tr"); Write(CHR( reg-TR + ORD("0")))
		ELSIF reg >= DR THEN
			WriteString("dr"); Write(CHR( reg-DR + ORD("0")))
		ELSE
			WriteString("cr"); Write(CHR( reg-CR + ORD("0")))
		END;
		INCL(target, Priv)
	END WriteSpecialReg;
	
	PROCEDURE WritePrefix (prefix: INTEGER);
	BEGIN
		IF prefix = pCS THEN WriteString("CS:")
		ELSIF prefix = pDS THEN WriteString("DS: ")
		ELSIF prefix = pES THEN WriteString("ES: ")
		ELSIF prefix = pFS THEN WriteString("FS: ")
		ELSIF prefix = pGS THEN WriteString("GS: ")
		ELSIF prefix = pSS THEN WriteString("SS: ")
		ELSE
		END
	END WritePrefix;

	PROCEDURE WriteRegReg (d, reg1, reg2: INTEGER);
	BEGIN
		IF d = 1 THEN
			WriteReg(reg1); Write(","); WriteReg(reg2)
		ELSE
			WriteReg(reg2); Write(","); WriteReg(reg1)
		END
	END WriteRegReg;

	PROCEDURE WriteMem (base, inx, scale: INTEGER; disp: LONGINT);
	BEGIN
		WritePrefix(prefix);
		IF base # none THEN(* register relative *)
			WriteDisp(disp);
			Write("["); WriteAdrReg(base)
		ELSE (* absolute *)
			Write("["); WriteDisp(disp)
		END;
		IF (inx # none) & ~((inx = ESP) & (base = ESP))(* !! 15.4.93 Bug? & (base # ESP) *) THEN (* indexed *)
			IF scale = 0 THEN WriteString(" + 1 * ")
			ELSIF scale = 1 THEN WriteString(" + 2 * ")
			ELSIF scale = 2 THEN WriteString(" + 4 * ")
			ELSE WriteString(" +  8* ")
			END;
			WriteAdrReg(inx)
		END;
		Write("]")
	END WriteMem;

	PROCEDURE WriteMem1 (d, reg, base: INTEGER; disp: LONGINT);
	(* d = TRUE: reg, mem ; d = FALSE: mem, reg *)
	BEGIN
		IF d = 1 THEN 
			WriteReg(reg); Write(",")
		END;
		WriteMem(base, none, 0, disp);
		IF d = 0 THEN 
			Write(","); WriteReg(reg)
		END
	END WriteMem1;

	PROCEDURE WriteMem2 (d, reg, base, inx: INTEGER; scale: SHORTINT; disp: LONGINT);
	(* d = TRUE: reg, mem; d= FALSE: mem, reg *)
	BEGIN
		IF d = 1 THEN
			WriteReg(reg); Write(",")
		END;
		WriteMem(base, inx, scale, disp);
		IF d = 0 THEN
			Write(","); WriteReg(reg)
		END
	END WriteMem2;
	
	PROCEDURE WriteRegImm (reg: INTEGER; imm: LONGINT; hex: BOOLEAN);
	BEGIN
		WriteReg(reg); Write(","); 
		IF hex THEN WriteDWHex(imm) ELSE WriteDisp(imm) END
	END WriteRegImm;
	
	PROCEDURE WriteMemImm (reg, base, inx: INTEGER; scale: SHORTINT; disp, imm: LONGINT; hex: BOOLEAN);
	BEGIN
		WritePrefix(prefix);
		WriteMem(base, inx, scale, disp);
		Write(",");
		IF hex THEN WriteDWHex(imm) ELSE WriteDisp(imm) END
	END WriteMemImm;
	
	PROCEDURE WriteRM (mode: SHORTINT; d, reg, base, inx, scale: INTEGER; disp, imm: LONGINT; hex: BOOLEAN);
	BEGIN
		CASE mode OF
			RegImm:
				WriteRegImm(reg, imm, hex)
		  | MemImm:
				WriteMemImm(reg, base, inx, SHORT(scale), disp, imm, hex)
		  | Reg:
				WriteRegReg(d, reg, base)
		  | Mem1:
				WriteMem1(d, reg, base, disp)
		  | Mem2:
				WriteMem2(d, reg, base, inx, SHORT(scale), disp)
		  | MemFull:
				IF d = 1 THEN 
					WriteReg(reg); Write(",")
				END;
				Write("["); WriteDisp(disp); Write("]");
				IF d = 0 THEN
					Write(","); WriteReg(reg)
				END
		ELSE Bug(BUG)
		END
	END WriteRM;

(* Decode part *)

	PROCEDURE GetImm (w: INTEGER; VAR imm: LONGINT);
		VAR byte: INTEGER;
	BEGIN
		IF w = 0 THEN (* 8 bit *)
			GetByte(byte); WriteByte(byte); Write(" ");
			IF  byte >= 128 THEN byte:= byte - 256 END;
			imm:= byte
		ELSIF opPrefix THEN (* 16 bit *)
			GetWord(imm); WriteWord(imm); Write(" ");
			IF imm >= 32768 THEN imm:= imm - 65536 END
		ELSE (* 32 bit *)
			GetDWord(imm); WriteDWord(imm); Write(" ")
		END
	END GetImm;

	PROCEDURE ModRm (VAR mode: SHORTINT; VAR reg, base, inx: INTEGER; VAR scale: SHORTINT; VAR disp: LONGINT);
		VAR mod, byte, temp: INTEGER;
	BEGIN
		GetByte(byte); WriteByte(byte); Write(" ");
		mod:= byte DIV 40H;
		reg:=(byte DIV 8) MOD 8; 
		base:= byte MOD 8;
		IF mod = 3 THEN (* reg *)
			mode:= Reg; inx:= none
		ELSE
			IF base = 4 THEN (* escape to two bytes *)
				mode:= Mem2;
				GetByte(byte);
				WriteByte(byte); Write(" ");
				scale:= SHORT(byte DIV 40H);
				inx:= (byte DIV 8) MOD 8;
				base:= byte MOD 8
			ELSE (* one byte addressing mode *)
				mode:= Mem1; inx:= none
			END;
			IF mod = 0 THEN (* no displ, or 32 bit address *)
				IF base = 5 THEN (* disp32 *)
					base:= none;
					GetDWord(disp); 
					WriteDWord(disp); Write(" ")
				ELSE disp:= 0
				END
			ELSIF mod = 1 THEN (* 8 bit displ *)
				GetImm(0, disp) 
			ELSE (* 32 bit displacement *)
				GetDWord(disp); 
				WriteDWord(disp); Write(" ")
			END
		END
	END ModRm;

	PROCEDURE Type1 (op: INTEGER; VAR mode: SHORTINT; VAR d, reg, base, inx: INTEGER;
								VAR scale: SHORTINT; VAR disp, imm: LONGINT);
	(* type 1: add, or, adc, sbb, and, sub, xor, cmp *)
	BEGIN
		IF op = 4 THEN
			mode:= RegImm; w:= 0; reg:= AL; GetImm(0, imm)
		ELSIF op = 5 THEN
			mode:= RegImm; w:= 1; reg:= AX; GetImm(1, imm)
		ELSE
			CASE op OF
				0: w:= 0; d:= 0
			  | 1: w:= 1; d:= 0
			  | 2: w:= 0; d:= 1
			  | 3: w:= 1; d:= 1
			ELSE Bug(BUG)
			END;
			ModRm(mode, reg, base, inx, scale, disp)
		END
	END Type1;
	
	PROCEDURE Add (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		Type1(op, mode, d, reg, base, inx, scale, disp, imm);
		WriteOp("add");
		WriteRM(mode, d, reg, base, inx, scale, disp, imm, FALSE)
	END Add;

	PROCEDURE Push (op: INTEGER);
		VAR imm: LONGINT;
	BEGIN
		w:= 1;
		IF op = 60H THEN 
			IF opPrefix THEN WriteOp("pusha") ELSE WriteOp("pushad") END;
		ELSIF op = 68H THEN
			IF opPrefix THEN
				GetWord(imm); WriteWord(imm)
			ELSE
				GetDWord(imm); WriteDWord(imm)
			END;
			WriteOp("push"); WriteDisp(imm)
		ELSIF op = 6AH THEN
			GetImm(0, imm);
			WriteOp("push"); WriteDisp(imm)
		ELSIF op = 9CH THEN 
			IF opPrefix THEN WriteOp("pushf") ELSE WriteOp("pushfd") END;
		ELSE
			WriteOp("push");
			CASE op OF
				6: WriteReg(ES)
			  | 0EH: WriteReg(CS)
			  | 16H: WriteReg(SS)
			  | 1EH: WriteReg(DS)
			  | 50H..57H: WriteReg(op - 50H)
			ELSE Bug(BUG)
			END
		END
	END Push;
	
	PROCEDURE Push2 (op: INTEGER);
	BEGIN
	END Push2;

	PROCEDURE Pop(op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		IF op = 61H THEN 
			IF opPrefix THEN WriteOp("popa") ELSE WriteOp("popad") END;
		ELSIF op = 8FH THEN
			ModRm(mode, reg, base, inx, scale, disp);
			WriteOp("pop");
			IF opPrefix THEN WriteString("word ptr ")
			ELSE WriteString("dword ptr ")
			END;
			WriteMem(base, inx, scale, disp)
		ELSIF op = 9DH THEN 
			IF opPrefix THEN WriteOp("popf") ELSE WriteOp("popfd") END;
		ELSE
			WriteOp("pop");
			w := 1;	(* pop takes only 16 or 32 bit ops *)
			CASE op OF
				7: WriteReg(ES)
			  | 17H: WriteReg(SS)
			  | 1FH: WriteReg(DS)
			  | 58H..5FH: WriteReg(op - 58H)
			 ELSE Bug(BUG)
			 END
		END
	END Pop;

	PROCEDURE Pop2 (op: INTEGER);
	BEGIN
	END Pop2;

	PROCEDURE Or (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		Type1(op - 08H, mode, d, reg, base, inx, scale, disp, imm);
		WriteOp("or");
		WriteRM(mode, d, reg, base, inx, scale, disp, imm, TRUE)
	END Or;
	
	PROCEDURE Adc (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		Type1(op -10H, mode, d, reg, base, inx, scale, disp, imm);
		WriteOp("adc");
		WriteRM(mode, d, reg, base, inx, scale, disp, imm, FALSE)
	END Adc;

	PROCEDURE Sbb (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		Type1(op - 18H, mode, d, reg, base, inx, scale, disp, imm);
		WriteOp("sbb");
		WriteRM(mode, d, reg, base, inx, scale, disp, imm, FALSE)
	END Sbb;

	PROCEDURE  And (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		Type1(op - 20H, mode, d, reg, base, inx, scale, disp, imm);
		WriteOp("and");
		WriteRM(mode, d, reg, base, inx, scale, disp, imm, TRUE)
	END And;

	PROCEDURE Sub (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		Type1(op - 28H, mode, d, reg, base, inx, scale, disp, imm);
		WriteOp("sub");
		WriteRM(mode, d, reg, base, inx, scale, disp, imm, FALSE)
	END Sub;

	PROCEDURE Xor (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		Type1(op - 30H, mode, d, reg, base, inx, scale, disp, imm);
		WriteOp("xor");
		WriteRM(mode, d, reg, base, inx, scale, disp, imm, TRUE)
	END Xor;

	PROCEDURE Cmp (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		Type1(op - 38H, mode, d, reg, base, inx, scale, disp, imm);
		WriteOp("cmp");
		WriteRM(mode, d, reg, base, inx, scale, disp, imm, FALSE)
	END Cmp ;

	PROCEDURE Inc (op: INTEGER);
	BEGIN
		WriteOp("inc"); w := 1;		(* set width to 16/32 bits, bug2 *)
		WriteReg(op - 40H)
	END Inc;

	PROCEDURE Dec (op: INTEGER);
	BEGIN
		WriteOp("dec"); w := 1;
		WriteReg(op - 48H)
	END Dec;

	PROCEDURE Bound (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		w:= 1;
		ModRm(mode, reg, base, inx, scale, disp);
		WriteOp("bound");
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, FALSE)
	END Bound;

	PROCEDURE Imul (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		w:= 1;
		IF op = 69H THEN GetImm(1, imm)
		ELSIF op = 6BH THEN GetImm(0, imm) (* sign extended *)
		END;
		WriteOp("imul");
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, FALSE);
		Write(","); WriteDisp(imm)
	END Imul;

	PROCEDURE Imul2 (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		w:= 1;
		ModRm(mode, reg, base, inx, scale, disp);
		WriteOp("imul");
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, FALSE)
	END Imul2;

	PROCEDURE Ins (op: INTEGER);
	BEGIN
		IF op =  6CH THEN WriteOp("insb")
		ELSIF opPrefix THEN WriteOp("insw")
		ELSE WriteOp("insd")
		END	
	END Ins;

	PROCEDURE Outs (op: INTEGER);
	BEGIN
		IF op = 6EH THEN WriteOp("outsb")
		ELSIF opPrefix THEN WriteOp("outsw")
		ELSE WriteOp("outsd")
		END
	END Outs;

	PROCEDURE Jcc (op: INTEGER);
		VAR disp: INTEGER;
	BEGIN
		GetByte(disp); WriteByte(disp);
		IF disp >= 128 THEN disp:= disp - 256 END;
		CASE op OF
			70H: WriteOp("jo")
		  | 71H: WriteOp("jno")
		  | 72H: WriteOp("jb")
		  | 73H: WriteOp("jnb")
		  | 74H: WriteOp("jz")
		  | 75H: WriteOp("jnz")
		  | 76H: WriteOp("jbe")
		  | 77H: WriteOp("jnbe")
		  | 78H: WriteOp("js")
		  | 79H: WriteOp("jns")
		  | 7AH: WriteOp("jp")
		  | 7BH: WriteOp("jnp")
		  | 7CH: WriteOp("jl")
		  | 7DH: WriteOp("jnl")
		  | 7EH: WriteOp("jle")
		  | 7FH: WriteOp("jnle")
		ELSE Bug(BUG)
		END;
		WriteDisp(disp); WriteString("  ("); (*Texts.*)WriteDWHex(pc + disp); Write(")")
	END Jcc;
	
	PROCEDURE Jcc2 (op: INTEGER);
		VAR disp: LONGINT;
	BEGIN
		IF adrPrefix THEN 
			GetWord(disp); WriteWord(disp)
		ELSE
			GetDWord(disp); WriteDWord(disp)
		END;
		CASE op OF
			80H: WriteOp("jo")
		  | 81H: WriteOp("jno")
		  | 82H: WriteOp("jb")
		  | 83H: WriteOp("jnb")
		  | 84H: WriteOp("jz")
		  | 85H: WriteOp("jnz")
		  | 86H: WriteOp("jbe")
		  | 87H: WriteOp("jnbe")
		  | 88H: WriteOp("js")
		  | 89H: WriteOp("jns")
		  | 8AH: WriteOp("jp")
		  | 8BH: WriteOp("jnp")
		  | 8CH: WriteOp("jl")
		  | 8DH: WriteOp("jnl")
		  | 8EH: WriteOp("jle")
		  | 8FH: WriteOp("jnle")
		ELSE Bug(BUG)
		END;
		WriteDisp(disp); WriteString("  ("); (*Texts.*)WriteDWHex(pc + disp); Write(")")
	END Jcc2;

	PROCEDURE Test (op: INTEGER);
		VAR reg, base, inx, byte: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		IF (op = 0A8H) OR (op = 0A9H) THEN
			IF op = 0A8H THEN 
				w:= 0; reg:= AL
			ELSE 
				w:= 1; reg:= AX
			END;
			GetImm(w, imm);
			mode:= RegImm
		ELSE
			ModRm(mode, reg, base, inx, scale, disp);
			IF op = 84H THEN w:= 0
			ELSE w:= 1
			END
		END;
		WriteOp("test");
		WriteRM(mode, 0, reg, base, inx, scale, disp, imm, FALSE)			(* bug1 *)
	END Test;

	PROCEDURE Xchg (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		IF (op >= 91H) & (op <= 97H) THEN (* xchg .ax, reg *)
			w:= 1; reg:= AX; base:= op MOD 8;
			mode:= Reg
		ELSE
			ModRm(mode, reg, base, inx, scale, disp);
			IF op = 86H THEN w:= 0
			ELSE w:= 1
			END
		END;
		WriteOp("xchg");
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, FALSE)
	END Xchg;

	PROCEDURE Mov (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		IF (op >= 88H) & (op <= 8BH) THEN
			Type1(op - 88H, mode, d, reg, base, inx, scale, disp, imm)
		ELSIF (op >= 0B0H) & (op <= 0B7H) THEN
			mode:= RegImm; w:= 0; reg:= op - 0B0H; GetImm(w, imm)
		ELSIF (op >= 0B8H) & (op <= 0BFH) THEN
			mode:= RegImm; w:= 1; reg:= op - 0B8H; GetImm(w, imm)
		ELSIF (op >= 0A0H) & (op <= 0A3H) THEN
			CASE op OF
				0A0H: w:= 0; d:= 1; reg:= AL
			  | 0A1H: w:= 1; d:= 1; reg:= AX
			  | 0A2H: w:= 0; d:= 0; reg:= AL
			  | 0A3H: w:= 1; d:= 0; reg:= AX
			END;
			mode:= MemFull; 
			IF adrPrefix THEN 
				GetWord(disp); WriteWord(disp)
			ELSE 
				GetDWord(disp); WriteDWord(disp)
			END
		ELSIF op = 8CH THEN (* mov mem, seg *)
			w:= 1; d:= 0; opPrefix:= TRUE;
			ModRm(mode, reg, base, inx, scale, disp);
			reg:= reg + ES (* reg is a segment register *)
		ELSIF op = 8EH THEN (* mov seg, mem *)
			w:= 1; d:= 1; opPrefix:= TRUE;
			ModRm(mode, reg, base, inx, scale, disp);
			reg:= reg + ES (* reg is segment register *)
		ELSIF (op = 0C6H) OR (op = 0C7H) THEN
			d:= 1;
			IF op = 0C6H THEN w:= 0
			ELSE w:= 1
			END;
			ModRm(mode, reg, base, inx, scale, disp);
			IF mode = Reg THEN
				reg:= base; mode:= RegImm
			ELSE mode:= MemImm
			END;
			GetImm(w, imm)
		END;
		WriteOp("mov");
		WriteRM(mode, d, reg, base, inx, scale, disp, imm, FALSE)
	END Mov;

	PROCEDURE Mov2 (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN (* reg, base only used, because Mov2 op codes contains special registers (debug/test/controll) *)
		ModRm(mode, reg, base, inx, scale, disp);
		WriteOp("mov");
		CASE op OF
		 	20H: WriteReg(base); Write(","); WriteSpecialReg(CR+reg)
		  | 21H: WriteReg(base); Write(","); WriteSpecialReg(DR+reg)
		  | 22H: WriteSpecialReg(CR+reg); Write(","); WriteReg(base)
		  | 23H: WriteSpecialReg(DR+reg); Write(","); WriteReg(base)
		  | 24H: WriteReg(base); Write(","); WriteSpecialReg(TR+reg)
		  | 26H: WriteSpecialReg(TR+reg); Write(","); WriteReg(base)
		ELSE Bug(BUG)
		END
	END Mov2;

	PROCEDURE Movzx (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		WriteOp("movzx");
		w:= 1;
		WriteReg(reg); Write(",");
		IF mode = Reg THEN WriteReg(base)
		ELSE
			IF op = 0B6H THEN WriteString("byte ptr ")
			ELSE WriteString("word ptr ")
			END;
			WriteMem(base, inx, scale, disp)
		END 
	END Movzx;
	
	PROCEDURE Movsx (op: INTEGER);
		VAR VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		WriteOp("movsx");
		w:= 1;
		WriteReg(reg); Write(",");
		IF mode = Reg THEN 
			IF op = 0BEH THEN 
				w:= 0; WriteReg(base)
			ELSE
				w:= 1; opPrefix:= TRUE; WriteReg(base)
			END;
		ELSE
			IF op = 0BEH THEN WriteString("byte ptr ")
			ELSE WriteString("word ptr ")
			END;
			WriteMem(base, inx, scale, disp)
		END 
	END Movsx;

	PROCEDURE Lea (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		w:= 1;
		WriteOp("lea");
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, TRUE)
	END Lea;

	PROCEDURE Call (op: INTEGER);
		VAR imm, sel: LONGINT;
	BEGIN
		IF op = 0E8H THEN
			IF adrPrefix THEN
				GetWord(imm); WriteWord(imm)
			ELSE
				GetDWord(imm); WriteDWord(imm)
			END
		ELSE (* intrasegment *)
			IF adrPrefix THEN
				GetWord(imm); WriteWord(imm)
			ELSE
				GetDWord(imm); WriteDWord(imm)
			END;
			GetWord(sel); Write(" "); WriteWord(sel);
		END;
		WriteOp("call");
		IF op = 09AH THEN 
			WriteDisp(sel); Write(":") 
		END;
		WriteDisp(imm); WriteString("  ("); (*Texts.*)WriteDWHex(pc + imm); Write(")")
	END Call;

	PROCEDURE Movs (op: INTEGER);
	BEGIN
		IF op = 0A4H THEN WriteOp("movsb")
		ELSIF (op = 0A5H) & opPrefix THEN WriteOp("movsw")
		ELSIF op  = 0A5H THEN WriteOp("movsd")
		ELSE Bug(BUG)
		END
	END Movs;

	PROCEDURE Cmps (op: INTEGER);
	BEGIN
		IF op = 0A6H THEN WriteOp("cmpsb")
		ELSIF (op = 0A7H) & opPrefix THEN WriteOp("cmpsb")
		ELSIF op = 0A7H THEN WriteOp("cmpsw")
		ELSE Bug(BUG)
		END
	END Cmps;

	PROCEDURE Stos (op: INTEGER);
	BEGIN
		IF op = 0AAH THEN WriteOp("stosb")
		ELSIF (op = 0ABH) & opPrefix THEN WriteOp("stosw")
		ELSIF op = 0ABH THEN WriteOp("stosd")
		ELSE Bug(BUG)
		END
	END Stos;

	PROCEDURE Lods (op: INTEGER);
	BEGIN
		IF op = 0ACH THEN WriteOp("lodsb")
		ELSIF op = 0ADH THEN
			IF opPrefix THEN WriteOp("lodsw") ELSE WriteOp("lodsd") END
		ELSE Bug(BUG)
		END
	END Lods;

	PROCEDURE Scas (op: INTEGER);
	BEGIN
		IF op = 0AEH THEN WriteOp("scasb")
		ELSIF (op = 0AFH) & opPrefix THEN WriteOp("scasw")
		ELSIF op = 0AFH THEN WriteOp("scasd")
		ELSE Bug(BUG)
		END
	END Scas;

	PROCEDURE Ret (op: INTEGER);
		VAR imm: LONGINT;
	BEGIN
		IF (op = 0C2H) OR (op = 0CAH) THEN 
			GetWord(imm); WriteWord(imm) 
		END;
		IF (op = 0CAH) OR (op = 0CBH) THEN WriteOp("ret far")
		ELSE WriteOp("ret")
		END;
		IF (op = 0C2H) OR (op = 0CAH) THEN WriteDisp(imm) END
	END Ret;

	PROCEDURE Enter (op: INTEGER);
		VAR l: LONGINT; b: INTEGER;
	BEGIN
		GetWord(l); WriteWord(l); Write(" ");
		GetByte(b); WriteByte(b); Write(" ");
		WriteOp("enter");
		WriteDisp(l); Write(","); WriteDisp(b)
	END Enter;

	PROCEDURE Les (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		WriteOp("les");
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, FALSE)
	END Les;

	PROCEDURE Lds (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		WriteOp("lds");
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, FALSE)
	END Lds;
	
	PROCEDURE Ldseg (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		IF op = 0B2H THEN WriteOp("lss")
		ELSIF op = 0B4H THEN WriteOp("lfs")
		ELSE WriteOp("lgs")
		END;
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, FALSE)
	END Ldseg;

	PROCEDURE Int (op: INTEGER);
		VAR imm: INTEGER;
	BEGIN
		IF op = 0CDH THEN 
			GetByte(imm); WriteByte(imm)
		ELSE imm := 3
		END;
		WriteOp("int");
		WriteDisp(imm)
	END Int;

	PROCEDURE Loop (op: INTEGER);
		VAR imm: LONGINT;
	BEGIN
		GetImm(0, imm);
		CASE op OF
			0E0H: WriteOp("loopne")
		  | 0E1H: WriteOp("loope")
		  | 0E2H: WriteOp("loop")
		  | 0E3H: IF adrPrefix THEN WriteOp("jcxz") ELSE WriteOp("jecxz") END
		ELSE Bug(BUG)
		END;
		WriteDisp(imm)
	END Loop;

	PROCEDURE InOut (op: INTEGER);
		VAR port: INTEGER; in, dx: BOOLEAN;
	BEGIN
		in := op MOD 4 < 2;
		dx := op MOD 16 >= 8;
		IF ~dx THEN GetByte(port); WriteByte(port) END;
		IF in THEN WriteOp("in") ELSE WriteOp("out") END;
		IF ~in & dx THEN WriteString("dx,")
		ELSIF ~in THEN WriteDisp(port); Write(",") END;
		IF ODD(op) THEN
			IF opPrefix THEN WriteString("ax") ELSE WriteString("eax") END
		ELSE WriteString("al") END;
		IF in THEN
			IF dx THEN WriteString(",dx") ELSE WriteString(","); WriteDisp(port) END
		END
	END InOut;

	PROCEDURE Jmp (op: INTEGER);
		VAR imm: LONGINT; byte: INTEGER;
	BEGIN
		IF (op = 0E9H) OR (op = 0EAH) THEN 
			GetDWord(imm); WriteDWord(imm)
		ELSE
			GetByte(byte); WriteByte(byte); 
			IF byte >= 128 THEN imm:= byte - 256
			ELSE imm:= byte
			END;
		END;
		Tab(OpPos);
		IF op = 0EAH THEN WriteOp("jmp far")
		ELSE WriteOp("jmp")
		END;
		Tab(RMPos); WriteDisp(imm); WriteString ("  ("); (*Texts.*)WriteDWHex(pc + imm); Write(")")
	END Jmp;

	PROCEDURE Lar (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		WriteOp("lar");
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, FALSE)
	END Lar;

	PROCEDURE Lsl (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		WriteOp("lsl");
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, FALSE)
	END Lsl;

	PROCEDURE Setcc (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		w:= 0; (* always 8 bit wide *)
		ModRm(mode, reg, base, inx, scale, disp);
		(* not nice but necessary -> no more constant memory for case table *)
		IF op = 90H THEN WriteOp("seto")
		ELSIF op = 91H THEN WriteOp("setno")
		ELSIF op = 92H THEN WriteOp("setb/setc/setnae")
		ELSIF op = 93H THEN WriteOp("setnb/setae/setnc")
		ELSIF op = 94H THEN WriteOp("setz/sete")
		ELSIF op = 95H THEN WriteOp("setnz/setne")
		ELSIF op = 96H THEN WriteOp("setbe/setna")
		ELSIF op = 97H THEN WriteOp("setnbe/seta")
		ELSIF op = 98H THEN WriteOp("sets")
		ELSIF op = 99H THEN WriteOp("setns")
		ELSIF op = 9AH THEN WriteOp("setp/setpe")
		ELSIF op = 9BH THEN WriteOp("setnp/setnp")
		ELSIF op = 9CH THEN WriteOp("setl/setnge")
		ELSIF op = 9DH THEN WriteOp("setnl/setge")
		ELSIF op = 9EH THEN WriteOp("setle/setng")
		ELSIF op = 9FH THEN WriteOp("setnle/setg")
		ELSE Bug(BUG)
		END;
		IF mode = Reg THEN WriteReg(base)
		ELSE WriteMem(base, inx, scale, disp)
		END
	END Setcc;

	PROCEDURE Bit (op: INTEGER);
		VAR reg, base, inx, d: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		w:= 1;
		ModRm(mode, reg, base, inx, scale, disp);
		IF op = 0A3H THEN 
			WriteOp("bt"); d:= 1
		ELSIF op = 0ABH THEN 
			WriteOp("bts"); d:= 1
		ELSIF op = 0B3H THEN 
			WriteOp("btr"); d:= 1
		ELSIF op = 0BBH THEN 
			WriteOp("btc"); d:= 1
		ELSIF op = 0BCH THEN
			WriteOp("bsf"); d:= 1
		ELSE
			WriteOp("bsr"); d:= 1
		END;
		IF mode = Reg THEN WriteRM(Reg, d, base, reg, none, 0, 0, 0, FALSE)
		ELSE WriteRM(mode, d, reg, base, inx, scale, disp, 0, FALSE)
		END
	END Bit;

	PROCEDURE Shift (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		IF (op = 0A4H) OR (op = 0ACH) THEN (* immediate byte *)
			w:= 0; GetImm(0, imm)
		ELSE
			imm := -1
		END;
		IF (op = 0A4H) OR (op = 0A5H) THEN WriteOp("shld")
		ELSIF (op = 0ACH) OR (op = 0ADH) THEN WriteOp("shrd")
		ELSE Bug(BUG)
		END;
		w := 1;
		WriteRM(mode, 0, reg, base, inx, scale, disp, imm, FALSE);
		Write(",");
		IF imm = -1 THEN WriteString("cl")
		ELSE WriteDisp(imm)
		END
	END Shift;
	
	PROCEDURE Bswap (op: INTEGER);
	BEGIN
		w := 1; INCL(target, i486);
		WriteOp("bswap"); WriteReg(op-0C8H)
	END Bswap;

	PROCEDURE Xadd (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		INCL(target, i486);
		ModRm(mode, reg, base, inx, scale, disp);
		WriteOp("xadd");
		IF op = 0C1H THEN w := 1 END;
		IF mode = Reg THEN WriteReg(base)
		ELSE WriteMem(base, inx, scale, disp)
		END ;
		Write(","); WriteReg(reg)
	END Xadd;
	
	PROCEDURE Cmpxchg (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		INCL(target, i486);
		ModRm(mode, reg, base, inx, scale, disp);
		WriteOp("cmpxchg");
		IF op = 0B1H THEN w := 1 END;
		IF mode = Reg THEN WriteReg(base)
		ELSE WriteMem(base, inx, scale, disp)
		END ;
		Write(","); WriteReg(reg)
	END Cmpxchg;
	
	PROCEDURE Cmov (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		INCL(target, PPro);  w := 1;
		ModRm(mode, reg, base, inx, scale, disp);
		CASE op OF
			40H: WriteOp("cmovo")
		  | 41H: WriteOp("cmovno")
		  | 42H: WriteOp("cmovb")
		  | 43H: WriteOp("cmovnb")
		  | 44H: WriteOp("cmovz")
		  | 45H: WriteOp("cmovnz")
		  | 46H: WriteOp("cmovbe")
		  | 47H: WriteOp("cmovnbe")
		  | 48H: WriteOp("cmovs")
		  | 49H: WriteOp("cmovns")
		  | 4AH: WriteOp("cmovp")
		  | 4BH: WriteOp("cmovnp")
		  | 4CH: WriteOp("cmovl")
		  | 4DH: WriteOp("cmovnl")
		  | 4EH: WriteOp("cmovle")
		  | 4FH: WriteOp("cmovnle")
		ELSE Bug(BUG)
		END;
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, FALSE)
	END Cmov;
	
	PROCEDURE Grp1 (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		IF op = 80H THEN (* byte *)
			w:= 0; GetImm(0, imm)
		ELSIF op = 81H THEN (* full immediate *)
			w:= 1; GetImm(w, imm)
		ELSE (* op = 83H, signed extendes *)
			w:= 1; GetImm(0, imm)
		END;
		CASE reg OF
			0: WriteOp("add")
		  | 1: WriteOp("or")
		  | 2: WriteOp("adc")
		  | 3: WriteOp("sbb")
		  | 4: WriteOp("and")
		  | 5: WriteOp("sub")
		  | 6: WriteOp("xor")
		  | 7: WriteOp("cmp")
		ELSE Bug(BUG)
		END;
		IF mode = Reg THEN WriteReg(base)
		ELSE WriteMem(base, inx, scale, disp)
		END;
		Write(","); 
		IF (reg = 0) OR (reg = 2) OR (reg = 3) OR (reg = 5) OR (reg = 7) THEN WriteDisp(imm)
		ELSE WriteDWHex(imm)
		END
	END Grp1;

	PROCEDURE Grp2 (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		IF (op >= 0D0H) & (op <= 0D3H) THEN
			IF (op = 0D0H) OR (op = 0D2H) THEN w:= 0
			ELSE w:= 1
			END
		ELSE
			IF op = 0C0H THEN w:= 0
			ELSE w:= 1
			END;
			GetImm(0, imm); (* only 8 bit possible *)
		END;
		CASE reg OF
			0: WriteOp("rol")
		  | 1: WriteOp("ror")
		  | 2: WriteOp("rcl")
		  | 3: WriteOp("rcr")
		  | 4: WriteOp("shl/sal")
		  | 5: WriteOp("shr")
		  | 7: WriteOp("sar")
		ELSE Bug(BUG)
		END;
		IF mode = Reg THEN WriteReg(base)
		ELSE WriteMem(base, inx, scale, disp)
		END;
		Write(","); 
		IF (op = 0D0H) OR (op = 0D1H) THEN Write("1")
		ELSIF (op = 0D2H) OR (op = 0D3H) THEN WriteString("cl")  
		ELSE WriteDisp(imm)
		END
	END Grp2;

	PROCEDURE Grp3 (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		ModRm(mode, reg, base, inx, scale, disp);
		IF op = 0F6H THEN w:= 0
		ELSE w:= 1
		END;
		IF reg = 0 (* test *) THEN GetImm(w, imm) END;
		CASE reg OF 
			0: WriteOp("test")
		  | 2: WriteOp("not")
		  | 3: WriteOp("neg")
		  | 4: WriteOp("mul")
		  | 5: WriteOp("imul")
		  | 6: WriteOp("div")
		  | 7: WriteOp("idiv")
		ELSE Bug(BUG)
		END;
		IF mode = Reg THEN WriteReg(base)
		ELSE WriteMem(base, inx, scale, disp)
		END;
		IF reg = 0 THEN 
			Write(","); WriteDisp(imm)
		END
	END Grp3;

	PROCEDURE Grp4 (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		w:= 0;
		ModRm(mode, reg, base, inx, scale, disp);
		IF reg = 0 THEN WriteOp("inc")
		ELSE WriteOp("dec")
		END;
		IF mode # Reg THEN
			WriteString("byte ptr "); WriteMem(base, inx, scale, disp)
		ELSE WriteReg(base)
		END
	END Grp4;

	PROCEDURE Grp5 (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		w:= 1;
		ModRm(mode, reg, base, inx, scale, disp);
		IF reg = 0 THEN WriteOp("inc")
		ELSIF reg = 1 THEN WriteOp("dec")
		ELSIF reg = 2 THEN WriteOp("call")
		ELSIF reg = 3 THEN WriteOp("call far")
		ELSIF reg = 4 THEN WriteOp("jmp")
		ELSIF reg = 5 THEN WriteOp("jmp far")
		ELSIF reg = 6 THEN WriteOp("push")
		ELSE Bug(BUG)
		END;
		IF mode = Reg THEN WriteReg(base)
		ELSE WriteMem(base, inx, scale, disp)
		END
	END Grp5;
	
	PROCEDURE Grp6 (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		w := 1;
		ModRm(mode, reg, base, inx, scale, disp);
		CASE reg OF
		|  0: WriteOp("sldt")
		|  1: WriteOp("str")
		|  2: WriteOp("lldt"); INCL(target, Priv)
		|  3: WriteOp("ltr"); INCL(target, Priv)
		|  4: WriteOp("verr")
		|  6: WriteOp("verw")
		ELSE Bug(BUG)
		END;
		IF mode = Reg THEN WriteReg(base)
		ELSE WriteMem(base, inx, scale, disp)
		END;
	END Grp6;
	
	PROCEDURE Grp7 (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		w := 1;
		ModRm(mode, reg, base, inx, scale, disp);
		CASE reg OF
		|  0: WriteOp("sgdt")
		|  1: WriteOp("sidt")
		|  2: WriteOp("lgdt"); INCL(target, Priv)
		|  3: WriteOp("lidt"); INCL(target, Priv)
		|  4: WriteOp("smsw")
		|  6: WriteOp("lmsw"); INCL(target, Priv)
		|  7: WriteOp("invlpg"); target := target + {Priv,i486}
		ELSE Bug(BUG)
		END;
		IF mode = Reg THEN WriteReg(base)
		ELSE WriteMem(base, inx, scale, disp)
		END;
	END Grp7;
	
	PROCEDURE Grp8 (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		w:= 1;
		ModRm(mode, reg, base, inx, scale, disp);
		GetImm(0, imm); (* always 8 bit wide *)
		CASE reg OF
			4: WriteOp("bt")
		  | 5: WriteOp("bts")
		  | 6: WriteOp("btr")
		  | 7: WriteOp("btc")
		ELSE Bug(BUG)
		END;
		IF mode = Reg THEN WriteReg(base)
		ELSE WriteMem(base, inx, scale, disp)
		END;
		Write(","); WriteDisp(imm)
	END Grp8;

	PROCEDURE Grp9 (op: INTEGER);
		VAR reg, base, inx: INTEGER; scale, mode: SHORTINT; disp, imm: LONGINT;
	BEGIN
		w:= 1;
		ModRm(mode, reg, base, inx, scale, disp);
		CASE reg OF
			1: WriteOp("cmpxch8"); INCL(target, Pentium)
		ELSE Bug(BUG)
		END;
		WriteRM(mode, 1, reg, base, inx, scale, disp, 0, FALSE)
	END Grp9;

	PROCEDURE Escape (op: INTEGER);
	BEGIN
		GetByte(op); WriteByte(op); Write(" ");
		IF op < 50H THEN (* because of DOSOberon *)
			CASE op OF
				0: 
					Grp6(op)
			  | 1: 
					Grp7(op)
			  | 2: 
					Lar(op)
			  | 3:
					Lsl(op)
			  | 6: 
					WriteOp("clts"); INCL(target, Priv)
			  | 8:
					WriteOp("invd"); target := target + {Priv,i486}
			  | 9:
					WriteOp("wbinvd"); target := target + {Priv,i486}
			  | 20H..24H, 26H:
					Mov2(op)
			  | 30H:
			         WriteOp("wrmsr"); target := target + {Priv,Pentium}
			  | 31H:
			         WriteOp("rdtsc"); target := target + {Priv,Pentium}
			  | 32H:
			         WriteOp("rdmsr"); target := target + {Priv,Pentium}
			  | 33H:
			         WriteOp("rdpmc"); target := target + {Priv,Pentium}
			  | 40H..4FH: 
					Cmov(op)
			ELSE Bug(BUG)
			END
		ELSIF op < 0D0H THEN
			CASE op OF
			  | 80H..8FH:
					Jcc2(op)
			  | 90H..9FH:
					Setcc(op)
			  | 0A0H, 0A8H:
					Push2(op)
			  | 0A1H, 0A9H:
					Pop2(op)
			  | 0A2H:
					WriteOp ("cpuid");  INCL(target, Pentium)
			  | 0A3H, 0ABH, 0B3H, 0BBH..0BDH:
					Bit(op)
			  | 0A4H, 0A5H, 0ACH, 0ADH:
					Shift(op)
			  | 0AFH:
					Imul2(op)
			  | 0B0H,0B1H:
					Cmpxchg(op)
			  | 0B2H, 0B4H, 0B5H:
					Ldseg(op)
			  | 0B6H, 0B7H:
					Movzx(op)
			  | 0BEH, 0BFH:
					Movsx(op)
			  | 0BAH:
					Grp8(op)
			  | 0C0H,0C1H:
					Xadd(op)
			  | 0C7H:
					Grp9(op)
			  | 0C8H..0CFH:
					Bswap(op)
			ELSE Bug(BUG)
			END
		ELSE Bug(BUG)
		END
	END Escape;

(* floating point i387 instruction set *)

	PROCEDURE WriteFReg (freg: INTEGER);
	BEGIN
		IF freg = 0 THEN WriteString("st")
		ELSE
			WriteString("st("); WriteDisp(freg); Write(")")
		END
	END WriteFReg;

	PROCEDURE WriteFloat (form: SHORTINT; base, inx: INTEGER; scale: SHORTINT; disp: LONGINT);
	BEGIN
		(* not nice but necessary -> no more constant memory for case table *)
		IF form = SReal THEN WriteString("single ")
		ELSIF form = LReal THEN WriteString("double ")
		ELSIF form = EReal THEN WriteString("extended ")
		ELSIF form = WInt THEN WriteString("word ")
		ELSIF form = SInt THEN WriteString("short ")
		ELSIF form = LInt THEN WriteString("long ")
		ELSIF (form = Byte14) OR (form = Byte94) THEN WriteString("small ")
		ELSIF (form = Byte28) OR (form = Byte108) THEN WriteString("big ")
		ELSIF form = Decimal THEN WriteString("bcd ")
		END;
		WriteMem(base, inx, scale, disp)
	END WriteFloat;

	PROCEDURE Float0 (op: INTEGER);
	(* op is 0D8H *)
		VAR stat, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, stat, base, inx, scale, disp);
		IF mode # Reg THEN (* memory *)
			CASE stat OF
				0: WriteOp("fadd")
			  | 1: WriteOp("fmul")
			  | 2: WriteOp("fcom")
			  | 3: WriteOp("fcomp")
			  | 4: WriteOp("fsub")
			  | 5: WriteOp("fsubr")
			  | 6: WriteOp("fdiv")
			  | 7: WriteOp("fdivr")
			ELSE Bug(BUG)
			END;
			WriteFloat(SReal, base, inx, scale, disp)
		ELSE
			CASE stat OF
				0: WriteOp("fadd"); WriteFReg(0); Write(",")
			  | 1: WriteOp("fmul"); WriteFReg(0); Write(",")
			  | 2: WriteOp("fcom")
			  | 3: WriteOp("fcomp")
			  | 4: WriteOp("fsub"); WriteFReg(0); Write(",")
			  | 5: WriteOp("fsubr"); WriteFReg(0); Write(",")
			  | 6: WriteOp("fdiv"); WriteFReg(0); Write(",")
			  | 7: WriteOp("fdivr"); WriteFReg(0); Write(",")
			ELSE Bug(BUG)
			END;
			WriteFReg(base)
		END
	END Float0;
	
	PROCEDURE Float1 (op: INTEGER);
	(* op is 0D9H *)
		VAR stat, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, stat, base, inx, scale, disp);
		IF mode # Reg THEN
			CASE stat OF
				0: WriteOp("fld")
			  | 2: WriteOp("fst")
			  | 3: WriteOp("fstp")
			  | 4: WriteOp("fldenv")
			  | 5: WriteOp("fldcw")
			  | 6: WriteOp("fstenv")
			  | 7: WriteOp("fstcw")
			ELSE Bug(BUG)
			END;
			IF (stat = 4) OR (stat = 6) THEN
				IF opPrefix THEN WriteFloat(Byte14, base, inx, scale, disp)
				ELSE WriteFloat(Byte28, base, inx, scale, disp)
				END
			ELSIF (stat = 2) OR (stat = 3) THEN WriteFloat(SReal, base, inx, scale, disp)
			ELSE WriteFloat(nothing, base, inx, scale, disp)
			END
		ELSIF stat = 0 THEN 
			WriteOp("fld"); WriteFReg(base)
		ELSIF stat = 1 THEN
			WriteOp("fxch"); WriteFReg(base)
		ELSE
			stat:= stat * 8 + base;
			IF stat = 10H THEN WriteOp("fnop")
			ELSE
				CASE stat OF
					20H: WriteOp("fchs")
				  | 21H: WriteOp("fabs")
				  | 24H: WriteOp("ftst")
				  | 25H: WriteOp("fxam")
				  | 28H: WriteOp("fld1")
				  | 29H: WriteOp("fldl2t")
				  | 2AH: WriteOp("fldl2e")
				  | 2BH: WriteOp("fldpi")
				  | 2CH: WriteOp("fldlg2")
				  | 2DH: WriteOp("fldln2")
				  | 2EH: WriteOp("fldz")
				  | 30H: WriteOp("f2xm1")
				  | 31H: WriteOp("fyl2x")
				  | 32H: WriteOp("fptan")
				  | 33H: WriteOp("fpatan")
				  | 34H: WriteOp("fxtract")
				  | 35H: WriteOp("fprem1")
				  | 36H: WriteOp("fdecstp")
				  | 37H: WriteOp("fincstp")
				  | 38H: WriteOp("fprem")
				  | 39H: WriteOp("fyl2xp1")
				  | 3AH: WriteOp("fsqrt")
				  | 3BH: WriteOp("fsincos")
				  | 3CH: WriteOp("frndint")
				  | 3DH: WriteOp("fscale")
				  | 3EH: WriteOp("fsin")
				  | 3FH: WriteOp("fcos")
				ELSE Bug(BUG)
				END
			END
		END
	END Float1;

	PROCEDURE Float2 (op: INTEGER);
	(* op is 0DAH *)
		VAR stat, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, stat, base, inx, scale, disp);
		IF mode # Reg THEN
			CASE stat OF
				0: WriteOp("fiadd")
			  | 1: WriteOp("fimul")
			  | 2: WriteOp("ficom")
			  | 3: WriteOp("ficomp")
			  | 4: WriteOp("fisub")
			  | 5: WriteOp("fisubr")
			  | 6: WriteOp("fidiv")
			  | 7: WriteOp("fidivr")
			ELSE Bug(BUG)
			END;
			WriteFloat(SInt, base, inx, scale, disp)
		ELSIF stat = 5 THEN WriteOp("fucompp")
		ELSE Bug(BUG)
		END
	END Float2;

	PROCEDURE Float3 (op: INTEGER);
	(* op is 0DBH *)
		VAR stat, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, stat, base, inx, scale, disp);
		IF mode # Reg THEN
			CASE stat OF
				0: WriteOp("fild")
			  | 2: WriteOp("fist")
			  | 3: WriteOp("fistp")
			  | 5: WriteOp("fld")
			  | 7: WriteOp("fstp")
			ELSE Bug(BUG)
			END;
			IF (stat = 5) OR (stat = 7) THEN WriteFloat(EReal, base, inx, scale, disp)
			ELSE WriteFloat(SInt, base, inx, scale, disp)
			END
		ELSIF base = 2 THEN WriteOp("fclex")
		ELSIF base = 3 THEN WriteOp("finit")
		ELSE Bug(BUG)
		END
	END Float3;

	PROCEDURE Float4 (op: INTEGER);
	(* op is 0DCH *)
		VAR stat, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, stat, base, inx, scale, disp);
		IF mode # Reg THEN
			CASE stat OF
				0: WriteOp("fadd")
			  | 1: WriteOp("fmul")
			  | 2: WriteOp("fcom")
			  | 3: WriteOp("fcomp")
			  | 4: WriteOp("fsub")
			  | 5: WriteOp("fsubr")
			  | 6: WriteOp("fdiv")
			  | 7: WriteOp("fdivr")
			ELSE Bug(BUG)
			END;
			WriteFloat(LReal, base, inx, scale, disp)
		ELSE
			CASE stat OF
				0: WriteOp("fadd")
			  | 1: WriteOp("fmul")
			  | 4: WriteOp("fsubr")
			  | 5: WriteOp("fsub")
			  | 6: WriteOp("fdivr")
			  | 7: WriteOp("fdiv")
			ELSE Bug(BUG)
			END;
			WriteFReg(base); Write(","); WriteFReg(0)
		END
	END Float4;

	PROCEDURE Float5 (op: INTEGER);
	(* op is 0DDH *)
		VAR stat, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, stat, base, inx, scale, disp);
		IF mode # Reg THEN (* memory *)
			CASE stat OF
				0: WriteOp("fld")
			  | 2: WriteOp("fst")
			  | 3: WriteOp("fstp")
			  | 4: WriteOp("frstor")
			  | 6: WriteOp("fsave")
			  | 7: WriteOp("fstsw")
			ELSE Bug(BUG)
			END;
			IF (stat = 4) OR (stat = 6) THEN
				IF opPrefix THEN WriteFloat(Byte94, base, inx, scale, disp)
				ELSE WriteFloat(Byte108, base, inx, scale, disp)
				END
			ELSIF stat = 7 THEN WriteFloat(nothing, base, inx, scale, disp)
			ELSE WriteFloat(LReal, base, inx, scale, disp)
			END
		ELSE
			CASE stat OF
				0: WriteOp("ffree")
			  | 2: WriteOp("fst")
			  | 3: WriteOp("fstp")
			  | 4: WriteOp("fucom")
			  | 5: WriteOp("fucomp")
			ELSE Bug(BUG)
			END;
			WriteFReg(base)
		END
	END Float5;

	PROCEDURE Float6(op: INTEGER);
	(* op is 0DEH *)
		VAR stat, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, stat, base, inx, scale, disp);
		IF mode # Reg THEN (* memory *)
			CASE stat OF
				0: WriteOp("fiadd")
			  | 1: WriteOp("fimul")
			  | 2: WriteOp("ficom")
			  | 3: WriteOp("ficomp")
			  | 4: WriteOp("fisub")
			  | 5: WriteOp("fisubr")
			  | 6: WriteOp("fidiv")
			  | 7: WriteOp("fidivr")
			ELSE Bug(BUG)
			END;
			WriteFloat(WInt, base, inx, scale, disp)
		ELSE
			CASE stat OF
				0: WriteOp("faddp")
			  | 1: WriteOp("fmulp")
			  | 3: WriteOp("fcompp")
			  | 4: WriteOp("fsubrp")
			  | 5: WriteOp("fsubp")
			  | 6: WriteOp("fdivrp")
			  | 7: WriteOp("fdivp")
			ELSE Bug(BUG)
			END;
			IF stat # 3 THEN
				WriteFReg(base); Write(","); WriteFReg(0)
			END
		END
	END Float6;
	
	PROCEDURE Float7(op: INTEGER);
	(* op is 0DFH *)
		VAR stat, base, inx: INTEGER; scale, mode: SHORTINT; disp: LONGINT;
	BEGIN
		ModRm(mode, stat, base, inx, scale, disp);
		IF mode # Reg THEN (* memory *)
			CASE stat OF
				0, 5: WriteOp("fild")
			  | 2: WriteOp("fist")
			  | 3, 7: WriteOp("fistp")
			  | 4: WriteOp("fbld")
			  | 6: WriteOp("fbstp")
			ELSE Bug(BUG)
			END;
			IF (stat = 4) OR (stat = 6) THEN WriteFloat(Decimal, base, inx, scale, disp)
			ELSIF (stat = 5) OR (stat = 7) THEN WriteFloat(LInt, base, inx, scale, disp)
			ELSE WriteFloat(WInt, base, inx, scale, disp)
			END
		ELSIF stat = 4 THEN WriteOp("fstsw"); WriteString("ax")
		ELSE Bug(BUG)
		END
	END Float7;

	PROCEDURE Prefix (VAR op: INTEGER);
	BEGIN
		IF (op = pCS) OR (op = pDS) OR (op = pES) OR (op = pFS) OR (op = pGS) OR (op = pSS) THEN
			prefix:= op;
			WriteByte(op); Write("|");
			GetByte(op);
			Prefix(op)
		ELSIF op =  AdrSize THEN 
			adrPrefix:= TRUE;
			WriteByte(op); Write("|");
			GetByte(op);
			Prefix(op)
		ELSIF op = OpSize THEN 
			opPrefix:= TRUE;
			WriteByte(op); Write("|");
			GetByte(op);
			Prefix(op)
		END
	END Prefix;

	PROCEDURE Dump (size: LONGINT);
		VAR op, pe: INTEGER;
	BEGIN
		pc:= 0; pe := 0; target := {};  OpPos := OpPosC; RMPos := RMPosC;
		IF compilable THEN  DEC(OpPos, OffPos);  DEC(RMPos, OffPos)  END;
		WHILE pc < size DO
			IF target # {} THEN
				Tab(70);  Write(";");
				IF i486 IN target THEN WriteString(" i486") END;
				IF Pentium IN target THEN WriteString(" Pentium") END;
				IF PPro IN target THEN WriteString(" PPro") END;
				IF Priv IN target THEN WriteString(" privileged") END;
				target := {}
			END;
			IF pc # 0 THEN WriteLn END;
			adrPrefix:= FALSE; opPrefix:= FALSE; prefix:= none; w := 0;
			IF (pe # nofPE) & (pc >= PE[pe].point) THEN
				WriteLn; Texts.SetFont(W, titleFont);
				WriteString("PROCEDURE "); WriteString(PE[pe].name); 
				IF pc # PE[pe].point THEN WriteString(" adr = "); WriteWHex(PE[pe].point) END;	(* should not happen *)
				WriteLn; Texts.SetFont(W, defaultFont); INC(pe)
			END;
			suppressOut := compilable;
			Tab(PCpos); WriteWHex(pc); Write("H"); Write(":"); Tab(HexPos);
			GetByte(op);
			Prefix(op);
			WriteByte(op); Write(" ");
			IF op < 40H THEN (* because of the DOSOberon *)
				CASE op OF
					0..5: 
						Add(op)
				  | 6, 0EH, 16H, 1EH: 
						Push(op)
				  | 7, 17H, 1FH:
				 		Pop(op)
				  | 8..0DH:
						Or(op)
				  | 0FH:
						Escape(op)
				  | 10H..15H:
						Adc(op)
				  | 18H..1DH:
						Sbb(op)
				  | 20H..25H:
						And(op)
				  | 27H:
						WriteOp("daa")
				  | 28H..2DH:
						Sub(op)
				  | 2FH:
						WriteOp("das")
				  | 30H..35H:
						Xor(op)
				  | 37H:
						WriteOp("aaa")
				  | 38H..3DH:
						Cmp(op)
				  | 3FH:
						WriteOp("aas")
				ELSE Bug(BUG)
				END
			ELSIF op < 80H THEN
				CASE op OF
					40H..47H:
						Inc(op)
				  | 48H..4FH:
						Dec(op)
				  | 50H..57H, 60H, 68H, 6AH:
						Push(op)
				  | 58H..5FH, 61H:
						Pop(op)
				  | 62H:
						Bound(op)
				  | 69H, 6BH:
						Imul(op)
				  | 6CH, 6DH:
						Ins(op)
				  | 6EH, 06FH:
						Outs(op)
				  | 70H..7FH:
						Jcc(op)
				ELSE Bug(BUG)
				END
			ELSIF op < 0C0H THEN
				CASE op OF
					80H..81H, 83H:
						Grp1(op)
				  | 84H..85H:
						Test(op)
				  | 86H..87H, 91H..97H:
						Xchg(op)
				  | 88H..8CH, 8EH, 0A0H..0A3H, 0B0H..0BFH:
						Mov(op)
				  | 8DH:
						Lea(op)
				  | 8FH, 9DH:
						Pop(op)
				  | 90H:
						WriteOp("nop")
				  | 98H:
						IF opPrefix THEN WriteOp("cbw") ELSE WriteOp("cwde") END
				  | 99H:
						IF opPrefix THEN WriteOp("cwd") ELSE WriteOp("cdq") END
				  | 9AH:
						Call(op)
				  | 9BH:
						WriteOp("wait")
				  | 9CH:
						Push(op)
				  | 9EH:
						WriteOp("sahf")
				  | 9FH:
						WriteOp("lahf")
				  | 0A4H..0A5H:
						Movs(op)
				  | 0A6H..0A7H:
						Cmps(op)
				  | 0A8H..0A9H:
						Test(op)
				  | 0AAH..0ABH:
						Stos(op)
				  | 0ACH..0ADH:
						Lods(op)
				  | 0AEH..0AFH:
						Scas(op)
				ELSE Bug(BUG)
				END
			ELSIF op <= 0FFH THEN
				CASE op OF
					0C0H..0C1H:
						Grp2(op)
				  | 0C2H..0C3H, 0CAH, 0CBH:
						Ret(op)
				  | 0C4H:
						Les(op)
				  | 0C5H:
						Lds(op)
				  | 0C6H..0C7H:
						Mov(op)
				  | 0C8H:
						Enter(op)
				  | 0C9H:
						WriteOp("leave")
				  | 0CCH..0CDH:
						Int(op)
				  | 0CEH:
						WriteOp("into")
				  | 0CFH:
						WriteOp("iret")
				  | 0D0H..0D3H:
						Grp2(op)
				  | 0D4H:
						WriteOp("aam")
				  | 0D5H:
						WriteOp("aad")
				  | 0D7H:
						WriteOp("xlat")
				  | 0D8H:
						Float0(op)
				  | 0D9H, 0D6H:
						Float1(op)
				  | 0DAH:
						Float2(op)
				  | 0DBH:
						Float3(op)
				  | 0DCH:
						Float4(op)
				  | 0DDH:
						Float5(op)
				  | 0DEH:
						Float6(op)
				  | 0DFH:
						Float7(op)
				  | 0E0H..0E3H:
						Loop(op) (* and jcxz *)
				  | 0E4H..0E7H, 0ECH..0EFH:
						InOut(op)
				  | 0E8H:
						Call(op)
				  | 0E9H..0EBH:
						Jmp(op)
				  | 0F0H:
						WriteOp("Lock")
				  | 0F2H:
						WriteOp("repne")
				  | 0F3H:
						WriteOp("rep")
				  | 0F4H:
						WriteOp("hlt"); INCL(target, Priv)
				  | 0F5H:
						WriteOp("cmc")
				  | 0F6H..0F7H:
						Grp3(op)
				  | 0F8H:
						WriteOp("clc")
				  | 0F9H:
						WriteOp("stc")
				  | 0FAH:
						WriteOp("cli")
				  | 0FBH:
						WriteOp("sti")
				  | 0FCH:
						WriteOp("cld")
				  | 0FDH:
						WriteOp("std")
				  | 0FEH:
						Grp4(op)
				  | 0FFH:
						Grp5(op)
				ELSE Bug(BUG)
				END
			ELSE Bug(BUG)			
			END
		END;
		IF target # {} THEN
			Tab(60);  Write(";");
			IF i486 IN target THEN WriteString(" i486") END;
			IF Pentium IN target THEN WriteString(" Pentium") END;
			IF PPro IN target THEN WriteString(" PPro") END;
			IF Priv IN target THEN WriteString(" privileged") END
		END;
	END Dump;

	PROCEDURE Reference (size: LONGINT);
		VAR 
			offs, dim, i: LONGINT;
			name: ARRAY 64 OF CHAR;
			b, typeForm: CHAR;
			old: ProcArray;
			
			PROCEDURE GetName(VAR name: ARRAY OF CHAR);
				VAR i: LONGINT;
			BEGIN
				i:= 0;
				REPEAT
					Next(name[i]);
					INC(i);
				UNTIL name[i-1] = 0X
			END GetName;

	BEGIN
		Next(b);
		nofPE := 0; pc := 0;
		WHILE pc < size-1 DO
			IF b # 0F8X THEN
				WriteString("wrong sign!"); WriteByte(ORD(b)); WriteLn;
				RETURN
			ELSE
				WriteLn;
				IF nofPE = LEN(PE) THEN
					old := PE;  NEW(PE, 2*LEN(PE));
					FOR i := 0 TO LEN(old)-1 DO PE[i] := old[i] END
				END;
				GetNum(PE[nofPE].point); 
				GetName(PE[nofPE].name);
				WriteString(PE[nofPE].name); WriteString("   "); Texts.WriteHex(W, PE[nofPE].point); WriteLn;
				INC(nofPE); Next(b);
				WHILE (b >= 1X) & (b <= 4X) DO
					Next(typeForm);
					IF typeForm > 80X THEN GetNum(dim) ELSE dim := -1 END;
					GetNum(offs); GetName(name);
					Tab(Pos1);
					IF b < 3X THEN WriteString("     ")
					ELSE WriteString("VAR  ")
					END;
					WriteString(name); WriteString(": ");
					IF (b = 2X) OR (b = 4X) THEN WriteString("ARRAY OF ")
					ELSIF typeForm >= 10X THEN
						WriteString("ARRAY ");
						IF typeForm > 80X THEN
							IF dim # 0 THEN WriteDisp(dim); WriteString(" ") END
						ELSE
							WriteDisp(1 + ORD(typeForm) DIV 10H);
							WriteString(" ")
						END;
						WriteString("OF ")
					END;
					CASE CHR(ORD(typeForm) MOD 16) OF
						1X: WriteString("BYTE  ")
					  | 2X: WriteString("BOOLEAN  ")
					  | 3X: WriteString("CHAR  ")
					  | 4X: WriteString("SHORTINT  ")
					  | 5X: WriteString("INTEGER  ")
					  | 6X: WriteString("LONGINT  ")
					  | 7X: WriteString("REAL  ")
					  | 8X: WriteString("LONGREAL  ")
					  | 9X: WriteString("SET  ")
					  | 0DX: WriteString("POINTER  ")
					  | 0EX: WriteString("PROCEDURE  ")
					  | 0FX: WriteString("STRING ")
					ELSE Bug(BUG)
					END;
					WriteDisp(offs);
					WriteLn;
					Next(b)
				END
			END
		END
	END Reference;

	PROCEDURE Check (ch: CHAR; str: ARRAY OF CHAR);
		VAR b: CHAR;
	BEGIN
		Next(b); Texts.SetFont(W, titleFont); WriteString(str);
		IF b = ch THEN WriteLn ELSE WriteString(" wrong sign! "); WriteByte(ORD(b)); WriteLn END;
		Texts.SetFont(W, defaultFont)
	END Check;

	PROCEDURE DumpData(VAR a: ARRAY OF CHAR; len: LONGINT);
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE i<len DO 
			IF (a[i] >= " ") & (a[i] <= "~") THEN Write(a[i]) ELSE Write(".") END;
			INC(i)
		END
	END DumpData;

	PROCEDURE ReadExport;
		PROCEDURE LoadScope (level: LONGINT);
			VAR	adr, fp, off: LONGINT; exp: INTEGER;
		BEGIN
			Tab(4+SHORT(level*4)); WriteString("level "); WriteDisp(level);
			Files.ReadBytes (R, exp, 2);
			WriteString(" (exp="); WriteDisp(exp); Write(")"); WriteLn;
			Files.ReadNum (R, fp);
			WHILE fp # 0 DO
				IF fp = 1 THEN
					Files.ReadNum (R, off);
					Tab(4+SHORT(level*4)); WriteString("record tdadr "); WriteDisp(off); WriteLn;
					IF off >= 0 THEN LoadScope (level+1(*1*)) END
				ELSE
					Tab(4+SHORT(level*4)); WriteDWHex(fp);
					IF level = 0 THEN
						Files.ReadNum (R, adr);
						WriteString(" -> "); WriteDisp(adr)
					END;
					WriteLn
				END;
				Files.ReadNum (R, fp)
			END;
		END LoadScope;
		
	BEGIN
		Check (88X, "Export:");
		LoadScope (0);
	END ReadExport;
	
	PROCEDURE ReadUse;
		VAR  name: ARRAY 32 OF CHAR;
		
		PROCEDURE GetString (VAR str: ARRAY OF CHAR);
			VAR i: LONGINT;
		BEGIN
			i := 0;
			REPEAT
				Next (str[i]); INC (i)
			UNTIL (str[i-1] = 0X) OR (str[i-1] > 7FX);
			IF str[i-1] > 7FX THEN str[i-1] := CHR (ORD (str[i-1]) - 80H); str[i] := 0X END
		END GetString;
		
		PROCEDURE CheckUse (level: LONGINT);
			VAR fp, link: LONGINT; tmpErr: BOOLEAN; name: ARRAY 32 OF CHAR;
		BEGIN tmpErr := (level = -1);
			Files.ReadNum (R, fp);
			WHILE fp # 0 DO
				IF fp = 1 THEN Files.ReadNum (R, link);
					IF tmpErr THEN CheckUse (-1)
					ELSE CheckUse (1)
					END
				ELSE
					GetString (name);
					IF level >= 0 THEN tmpErr := FALSE;
						IF level = 0 THEN Files.ReadNum (R, link) END;
					END
				END;
				Files.ReadNum (R, fp)
			END
		END CheckUse;
		
	BEGIN
		Check (8AX, "Use:");
		GetString (name);
		WHILE (name # "") DO CheckUse (0); GetString (name) END
	END ReadUse;

	PROCEDURE WriteProc(pc: LONGINT);
	VAR i: LONGINT;
	BEGIN
		i := 0;  WHILE (i # nofPE) & (pc # PE[i].point) DO INC(i) END;
		IF i # nofPE THEN WriteString(PE[i].name) END
	END WriteProc;
	
	PROCEDURE DecodeObjFile*(objName : ARRAY OF CHAR; VAR T : Texts.Text);
		VAR
			f: Files.File;
			byte, version, i, tag: INTEGER;
			word, dword, nofVarEntries, nofEntries, nofCmds, nofPtrs, notTypes, nofImports,
			nofVarConsLinks, nofLinks, conssize, codesize, nofTypes, refSize, j, ptrs, newMths, refPos: LONGINT;
			symSize: LONGINT;
			name: ARRAY 32 OF CHAR;
			ch: CHAR;
			pos: LONGINT;
			data: ARRAY 16 OF CHAR;
			entry: EntryArray;
	BEGIN
		f := Files.Old(objName);
		IF f = NIL THEN
			T := NIL
		ELSE
			NEW(T); Texts.Open(T, "");
			Files.Set(R, f, 0);
			Texts.SetFont(W, titleFont);
			suppressH := TRUE;
			GetByte (tag);
			IF tag = 0BBH THEN
				WriteString ("Object Model -- Object File Dump"); WriteLn;
				Texts.SetFont(W, defaultFont);
				WriteString("  Version:         "); GetByte(version); WriteByte(version);
				WriteLn;
				Files.ReadNum (R, symSize); Files.Set (R, Files.Base (R), Files.Pos (R) + symSize);	(* skip symbol file *)
			ELSE
				WriteString ("  tag not supported or wrong file type!"); WriteLn; Texts.Append (T, W.buf); RETURN
			END;
			WriteString(refSizeStr); GetDWord(refSize); WriteDWHex(refSize); WriteLn;
			WriteString(nofEntriesStr); GetWord(nofEntries); WriteWHex(nofEntries); WriteLn;
			WriteString(nofCmdsStr); GetWord(nofCmds); WriteWHex(nofCmds); WriteLn;
			WriteString(nofPtrsStr); GetWord(nofPtrs); WriteWHex(nofPtrs); WriteLn;
			WriteString(nofTypesStr); GetWord(nofTypes); WriteWHex(nofTypes); WriteLn;
			WriteString(nofImpsStr); GetWord(nofImports); WriteWHex(nofImports); WriteLn;
			WriteString("  nofVarConsLinks: "); GetWord(nofVarConsLinks); WriteWHex(nofVarConsLinks); WriteLn;
			WriteString("  nofLinks:        "); GetWord(nofLinks); WriteWHex(nofLinks); WriteLn;
			WriteString(dataSizeStr); GetDWord(dword); WriteDWHex(dword); WriteLn;
			WriteString(constSizeStr); GetWord(conssize); WriteWHex(conssize); WriteLn;
			WriteString(codeSizeStr); GetWord(codesize); WriteWHex(codesize); WriteLn;
			WriteString("  Modulename:      ");
			i := 0;
			REPEAT
				Next(name[i]);
				INC(i)
			UNTIL name[i-1] = 0X;
			WriteString(name); WriteLn; WriteLn;
			Texts.Append(T, W.buf);
		(* skip to reference block *)
			pos := Files.Pos(R);  Files.Set(R, f, Files.Length(f)-refSize);
			Check(8CX, "Reference:");
			Reference (refSize);
			Files.Set(R, f, pos);
			pos := T.len;  Texts.Append(T, W.buf);
		(* entry block *)
			Check(82X, EntriesStr);
			i:= 0; NEW(entry, nofEntries);
			WHILE i < nofEntries DO
				Tab(Pos1); GetWord(word); WriteWHex(word); 
				WriteString(" "); WriteProc(word); WriteLn;
				entry[i] := word; INC(i)
			END;
			WriteLn;
		(* Command block *)
			Check(83X, CommandsStr);
			i:= 0;
			WHILE i < nofCmds DO
				Tab(Pos1);
				Next(ch);
				WHILE ch # 0X DO
					Write(ch); Next(ch)
				END;
				Tab(column + 4); GetWord(word); WriteWHex(word); 
				WriteString(" "); WriteProc(word); WriteLn;
				INC(i)
			END;
			WriteLn;
		(* pointer block *)
			Check(84X, PointersStr);
			i:= 0;
			WHILE i < nofPtrs DO
				Tab(Pos1); GetDWord(dword); WriteDWHex(dword); WriteLn;
				INC(i)
			END;
			WriteLn;
		(* import block *)
			Check(85X, "Imports:");
			i:= 0;
			WHILE i < nofImports DO
				Tab(Pos1); 
				Next(ch);
				WHILE ch # 0X DO
					Write(ch); Next(ch)
				END;
				WriteLn;
				INC(i)
			END;
			WriteLn;
		(* VarConsLink block *)
			Check(8DX, "VarConsLinks:");
			i:= 0;
			WHILE i < nofVarConsLinks DO
				WriteString("  modNr: "); GetByte(byte); WriteByte(byte);
				WriteString("  entryNr: "); GetWord(word); WriteWHex(word);
				WriteString("  noffixups: "); GetWord(word); WriteWHex(word); 
				WriteLn; Tab(Pos1);
				j:= SHORT(word);
				WHILE j > 0 DO
					IF j MOD 8 = 0 THEN 
						WriteLn; Tab(Pos1)
					END;
					GetWord(word); WriteWHex(word); Tab(column + 2);
					DEC(j)
				END;
				WriteLn; 
				INC(i)
			END;
			WriteLn;
		(* Link block *)
			Check(86X, "Links:");
			i:= 0;
			WHILE i < nofLinks DO
				Tab(Pos1); GetByte(byte); WriteByte(byte); Tab(column + 2);
				GetByte(byte); WriteByte(byte); Tab(column + 2);
				GetWord(word); WriteWHex(word); WriteLn;
				INC(i)
			END;
			WriteLn;
		(* Data block *)
			Check(87X, ConstStr);
			i:= 0;
			WHILE i < conssize DO
				Tab(Pos1); WriteWHex(i); Write(":"); Tab(column + 2);
				j := 0;
				WHILE (i < conssize) & (j < 16) DO
					GetByte(byte); WriteByte(byte); Tab(column + 1); data[j] := CHR(byte); INC(i); INC(j)
				END;
				Tab(60); DumpData(data, j); WriteLn;
			END;
			WriteLn;
		(* Export Block *)
			ReadExport; WriteLn;
		(* Code block *)
			Check(89X, CodeStr);
			suppressH := FALSE; Dump(codesize); suppressH := TRUE; WriteLn; WriteLn;
		(* Use Block *)
			ReadUse; WriteLn;
		(* type block *)
			Check(8BX, "Type:");
			i:= 0;
			WHILE i < nofTypes DO
				WriteString("  recsize: "); GetDWord(dword); WriteDWHex(dword);
				WriteString("  entry: "); GetWord(word); WriteWHex(word);
				WriteString("  basetypMod: "); GetWord(word); WriteWHex(word);
				WriteString("  basetypEntry: "); GetDWord(dword); WriteDWHex(dword);
				WriteLn;
				WriteString("  nofMths: "); GetWord(word); WriteWHex(word); 
				WriteString("  nofInhMths: "); GetWord(word); WriteWHex(word);
				WriteString("  nofnewMths: "); GetWord(newMths); WriteWHex(newMths);
				WriteString("  nofPtrs: "); GetWord(ptrs); WriteWHex(ptrs);
				WriteLn; WriteString("  ");
				Next(ch);
				WHILE ch # 0X DO
					Write(ch); Next(ch)
				END;
				j:= 0;
				WHILE j < newMths DO
					WriteLn; WriteString("  mthNr: ");
					GetWord(word); WriteWHex(word); WriteString("  entryNr: ");
					GetWord(word); WriteWHex(word);
					WriteString(" "); WriteProc(entry[word]);
					INC(j)
				END;
				WriteString("  ptrOfs: ");
				j:= 0;
				WHILE j < ptrs DO
					IF j MOD 8 = 0 THEN WriteLn END;
					GetDWord(dword); WriteDWHex(dword); WriteString("  ");
					INC(j)
				END;
				WriteLn;
				INC(i)
			END;
			WriteLn;
		(* output *)
			Texts.Insert(T, pos, W.buf);
			Files.Set(R, NIL, 0)
		END
	END DecodeObjFile;
	
	(* ------------------------------------------------------------------------------------ *)
	(* Memory Module Dump *)
	PROCEDURE DumpType (tdadr, codebase: LONGINT);
		VAR tdbase, i, j: LONGINT; ch: CHAR; m: Modules.Module;
		
		PROCEDURE DumpTypeName (tdadr: LONGINT);
			VAR tdbase, i: LONGINT; ch: CHAR;
		BEGIN
			IF tdadr # 0 THEN
				SYSTEM.GET (tdadr-4, tdbase);
				i := tdbase+16; SYSTEM.GET (i, ch);
				WHILE ch # 0X DO Write (ch); INC (i); SYSTEM.GET (i, ch) END
			END
		END DumpTypeName;
		
	BEGIN
		IF tdadr MOD 16 # 8 THEN WriteString (" TDAdr MOD 16 # 8 !!!"); WriteLn; RETURN END;
		
		SYSTEM.GET (tdadr-4, tdbase);
		IF tdbase MOD 32 # 0 THEN WriteString (" TDBase MOD 32 # 0 !!!"); WriteLn; RETURN END;
		(* td name *)
		Tab (Pos1); WriteString ("TD at     "); WriteDWHex (tdadr); 
		Write(" "); Texts.SetFont(W, titleFont); DumpTypeName (tdadr); Texts.SetFont(W, defaultFont); WriteLn;
		Tab (Pos1); WriteString ("TDBase at "); WriteDWHex (tdbase); WriteLn;
				
		(* check td of td *)
		SYSTEM.GET (tdbase-4, i);
		IF i # tdbase THEN WriteString (" TD of TD is wrong"); WriteLn; RETURN END;
		
		(* td size *)
		SYSTEM.GET (tdbase, i); Tab (Pos1); WriteString ("tdsize:   "); WriteDWHex (i); WriteLn;
		SYSTEM.GET (tdbase + 8, i); Tab (Pos1); WriteString ("self:     "); WriteDWHex (i); Write(" "); DumpTypeName (i); WriteLn;
		SYSTEM.GET (tdbase + 12, i); Tab (Pos1); WriteString ("ext:      "); WriteDWHex (i); WriteLn;
		SYSTEM.GET (tdbase + 48, i); Tab (Pos1); WriteString ("mdesc:    "); WriteDWHex (i); 
		m := SYSTEM.VAL (Modules.Module, i); WriteString (" ["); WriteString (m.name); Write ("]"); WriteLn;

		i := tdbase + 52;
		Tab (Pos1); WriteString ("methods"); WriteLn;
		WHILE i <= tdadr - 72 DO
			Tab (Pos1+4); SYSTEM.GET (i, j);
			IF j # 0 THEN
				WriteDWHex ((tdadr-i-72) DIV 4); WriteString(": ");
				WriteDWHex (j-codebase); WriteLn
			END;
			INC (i, 4)
		END;
		
		i := 16;
		Tab (Pos1); WriteString ("tags"); WriteLn;
		WHILE i > 0 DO
			DEC (i);
			SYSTEM.GET (tdadr - 8 - i*4, j);
			IF j # 0 THEN 
				Tab (Pos1+4); WriteByte(SHORT(i)); WriteString(": "); WriteDWHex (j);
				WriteString (" ["); DumpTypeName (j); Write ("]"); WriteLn
			END
		END;
		WriteLn;
		
		Tab (Pos1); WriteString ("rec size: "); SYSTEM.GET (tdadr, j); WriteDWHex (j); WriteLn;
		Tab (Pos1); WriteString ("ptr off"); WriteLn;
		i := tdadr + 4;
		REPEAT
			SYSTEM.GET (i, j); INC (i, 4);
			Tab (Pos1+4); WriteDWHex (j); WriteLn
		UNTIL j < 0;
		WriteLn;
	END DumpType;
	
	
	PROCEDURE DecodeModule* (objName : ARRAY OF CHAR; VAR T : Texts.Text);
		VAR i, j, pos: LONGINT; mod: Modules.Module;
			codesize, refsize, datasize, constsize: LONGINT;
			data: ARRAY 16 OF CHAR;
	BEGIN
		mod := Modules.ThisMod (objName);
		IF mod = NIL THEN T := NIL; RETURN END;
		NEW(T); Texts.Open(T, "");
		Texts.SetFont(W, titleFont); WriteString ("Module Dump"); WriteLn; Texts.SetFont(W, defaultFont);
		suppressH := TRUE;
		WriteString ("  mdesc:           "); WriteDWHex (SYSTEM.VAL (LONGINT, mod)); WriteLn;
		WriteString ("  name:            "); WriteString (mod.name); WriteLn;
		WriteString ("  refcnt:          "); WriteDWHex (mod.refcnt); WriteLn;
		WriteString ("  sb:              "); WriteDWHex (mod.sb); WriteLn;
		datasize := mod.sb - SYSTEM.ADR(mod.data[0]);
		constsize := mod.sb - SYSTEM.ADR(mod.data[0])+ LEN(mod.data);
		codesize := LEN(mod.code);
		refsize := LEN(mod.refs);
		WriteString (dataSizeStr); WriteDWHex (datasize); WriteLn;
		WriteString (constSizeStr); WriteDWHex (constsize); WriteLn;
		WriteString (codeSizeStr); WriteDWHex (codesize); WriteLn;
		WriteString (refSizeStr); WriteDWHex (refsize); WriteLn;
		WriteString (nofEntriesStr); WriteDWHex (LEN(mod.entries)); WriteLn;
		WriteString (nofCmdsStr); WriteDWHex (LEN(mod.cmds)); WriteLn;
		WriteString (nofImpsStr); WriteDWHex (LEN(mod.imports)); WriteLn;
		WriteString (nofTypesStr); WriteDWHex (LEN(mod.tdescs)); WriteLn;
		WriteString (nofPtrsStr); WriteDWHex (LEN(mod.ptrTab)); WriteLn;
		WriteLn;
		Texts.Append(T, W.buf);
		(* skip to reference block *)
		Texts.SetFont(W, titleFont); WriteString ("Reference: "); WriteLn; Texts.SetFont(W, defaultFont);
		pos := ReadAdr; ReadAdr := SYSTEM.ADR (mod.refs[0]);
		Reference (LEN(mod.refs));
		ReadAdr := pos;
		pos := T.len; Texts.Append(T, W.buf);
		(* entry block *)
		Texts.SetFont(W, titleFont); WriteString (EntriesStr); WriteLn; Texts.SetFont(W, defaultFont);
		i:= 0;
		WHILE i < LEN(mod.entries) DO
			Tab(Pos1); WriteDWHex(mod.entries[i]); 
			WriteString(" "); WriteProc(mod.entries[i]); WriteLn;
			INC(i)
		END;
		WriteLn;
		(* Command block *)
		Texts.SetFont(W, titleFont); WriteString (CommandsStr); WriteLn; Texts.SetFont(W, defaultFont);
		i:= 0;
		WHILE i < LEN(mod.cmds) DO
			Tab(Pos1); WriteString (mod.cmds[i].name);
			Tab(column + 4); WriteDWHex(mod.cmds[i].adr); WriteLn;
			INC(i)
		END;
		WriteLn;
		(* pointer block *)
		Texts.SetFont(W, titleFont); WriteString (PointersStr); WriteLn; Texts.SetFont(W, defaultFont);
		i:= 0;
		WHILE i < LEN(mod.ptrTab) DO
			Tab(Pos1); WriteDWHex(mod.ptrTab[i]); WriteLn;
			INC(i)
		END;
		WriteLn;
		(* type block *)
		Texts.SetFont(W, titleFont); WriteString ("TypeDescriptors:"); WriteLn; Texts.SetFont(W, defaultFont);
		i := 0;
		WHILE i < LEN(mod.tdescs) DO
			DumpType (mod.tdescs[i], SYSTEM.ADR(mod.code[0])); WriteLn;
			INC (i)
		END;
		
		Texts.SetFont(W, titleFont); WriteString ("imports: not implemented yet"); WriteLn; Texts.SetFont(W, defaultFont);
		
		(* data/const section *)
		Texts.SetFont(W, titleFont); WriteString (DataStr); WriteLn; Texts.SetFont(W, defaultFont);
		i := 0;
		WHILE i < LEN(mod.data) DO
			Tab(Pos1); WriteWHex(i); Write(":"); Tab(column + 2);
			j := 0;
			WHILE (i < LEN(mod.data)) & (j < 16) DO
				WriteByte(ORD(mod.data[i])); Tab(column + 1); data[j] := mod.data[i]; INC(i); INC(j)
			END;
			Tab(60); DumpData(data, j); WriteLn;
		END;
		WriteLn;
		
		(* code section *)
		Texts.SetFont(W, titleFont); WriteString (CodeStr); WriteLn; Texts.SetFont(W, defaultFont);
		ReadAdr := SYSTEM.ADR (mod.code[0]);
		Dump (LEN(mod.code)); WriteLn; WriteLn;
		
		Texts.SetFont(W, titleFont); WriteString ("import: not implemented yet"); WriteLn; Texts.SetFont(W, defaultFont);
		Texts.SetFont(W, titleFont); WriteString ("struct: not implemented yet"); WriteLn; Texts.SetFont(W, defaultFont);
		Texts.SetFont(W, titleFont); WriteString ("reimp: not implemented yet"); WriteLn; Texts.SetFont(W, defaultFont);
		Texts.SetFont(W, titleFont); WriteString ("export: not implemented yet"); WriteLn; Texts.SetFont(W, defaultFont);

		Texts.Insert(T, pos, W.buf)
	END DecodeModule;

	(** Decoder.Decode Module	Decodes the object file of Module *)
	PROCEDURE Decode*;
		VAR
			i, j: LONGINT;
			name, suf: ARRAY 32 OF CHAR;
			ch: CHAR;
			S: Texts.Scanner;
			beg, end, time: LONGINT;
			T: Texts.Text;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		memory := FALSE; compilable := FALSE;
		WHILE (S.class = Texts.Char) & (S.c = "\") DO	(* get options *)
			Texts.Scan (S);
			i := 0;
			WHILE S.s[i] # 0X DO
				IF (S.s[i] = "m") THEN memory := TRUE
				ELSIF (S.s[i] = "c") THEN compilable := TRUE
				ELSE Out.String("Unsupported option "); Out.Char(S.s[i]); Out.Ln
				END;
				INC(i)
			END;
			Texts.Scan(S)
		END;
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			Oberon.GetSelection(T, beg, end, time);
			IF (T = NIL) OR (time <= 0) THEN S.class := Texts.Inval
			ELSE Texts.OpenScanner(S, T, beg); Texts.Scan(S)
			END
		END;
		IF S.class = Texts.Name THEN i := 0; ch := S.s[0];  j := MAX(LONGINT);
			WHILE ("A" <= CAP(ch)) & (CAP(ch) <= "Z") OR ("0" <= ch) & (ch <= "9") OR (ch = ".") DO
				IF ch = "." THEN j := i END;
				name[i] := ch; INC(i); ch := S.s[i]
			END;
			IF j < i THEN i := j END;
			name[i] := 0X;
			IF ~memory THEN
				Strings.GetSuffix (S.s, suf);
				IF (suf = "Obj") OR (suf = "Obf") OR (suf = "Obx") THEN
					Strings.AppendCh (name, "."); Strings.Append (name, suf)
				ELSE
					Strings.Append (name, objSuffix)
				END
			END;
			Texts.Scan(S); 
			IF S.class = Texts.Int THEN breakpos:= S.i
			ELSE breakpos:= -1
			END;
			IF memory THEN DecodeModule(name, T) ELSE DecodeObjFile(name, T) END;
			IF T # NIL THEN
				name[i+1] := "D"; name[i+2] := "e"; name[i+3] := "c";
				Oberon.OpenText(name, T, 600, 300);
				breakpos := -1
			ELSE
				Out.String("Decoder error: ");Out.String(name); Out.String(" doesn't exist"); Out.Ln;
			END;
			T := NIL
		END
	END Decode;

(* ======================================================================================== *)
(* Returns the frame that is at X, Y on the display. u, v contain the relative coordinates inside this frame *)
PROCEDURE ThisFrame(X, Y: INTEGER; VAR F: Display.Frame);
VAR M: Display.LocateMsg;
BEGIN M.X := X; M.Y := Y; M.F := NIL; M.loc := NIL; Display.Broadcast(M); F := M.loc
END ThisFrame;

(* Get the marked text *)
PROCEDURE GetText(VAR par: Display.Frame): Texts.Text;
VAR M: Objects.LinkMsg; t: Texts.Text;
BEGIN
	t := NIL;
	ThisFrame(Oberon.Pointer.X, Oberon.Pointer.Y, par);
	IF par # NIL THEN
		M.id := Objects.get; M.name := "Model"; M.obj := NIL; M.res := -1; par.handle(par, M);
		IF (M.obj # NIL) & (M.obj IS Texts.Text) THEN t := M.obj(Texts.Text) END
	END;
	RETURN t
END GetText;

PROCEDURE Locate(F: Display.Frame;  T: Texts.Text;  pos: LONGINT);
VAR M: Oberon.CaretMsg;  N: Oberon.ControlMsg;
BEGIN
	IF pos < 0 THEN pos := 0
	ELSIF pos > T.len THEN pos := T.len
	END;
	N.F := NIL; N.id := Oberon.neutralize; Display.Broadcast(N);
	Oberon.FadeCursor(Oberon.Pointer);
	M.id := Oberon.set; M.F := F; M.car := F; M.text := T; M.pos := pos; Display.Broadcast(M)
END Locate;

PROCEDURE Scan(s: ARRAY OF CHAR): LONGINT;
VAR x, i: LONGINT;
BEGIN
	x := 0;  i := 0;
	WHILE ((s[i] >= "0") & (s[i] <= "9")) OR ((s[i] >= "A") & (s[i] <= "F")) & (i # LEN(s)) DO
		IF s[i] >= "A" THEN x := x*16 + (ORD(s[i])-ORD("A")+10)
		ELSE x := x*16 + (ORD(s[i])-ORD("0"))
		END;
		INC(i)
	END;
	RETURN x
END Scan;

PROCEDURE GetLine(VAR r: Texts.Reader;  VAR buf: ARRAY OF CHAR);
VAR i: LONGINT;  ch: CHAR;
BEGIN
	i := 0;
	Texts.Read(r, ch);
	WHILE ~r.eot & (ch # 0DX) DO
		IF i < LEN(buf)-1 THEN buf[i] := ch; INC(i) END;
		Texts.Read(r, ch)
	END;
	buf[i] := 0X
END GetLine;

(** Decoder.Find	Finds the selected pc in the marked window *)
PROCEDURE Find*;
VAR
	fbeg, fend, ftime, breakpc, breakpos: LONGINT;  ftext: Texts.Text;  S1: Texts.Scanner;  
	line: INTEGER;  fpar: Display.Frame;  scan: BOOLEAN;  buf: ARRAY 6 OF CHAR;
	r: Texts.Reader;
BEGIN
	Oberon.GetSelection(ftext, fbeg, fend, ftime);
	IF ftime >= 0 THEN
		Texts.OpenScanner(S1, ftext, fbeg); Texts.Scan(S1); line := S1.line;
		WHILE (S1.class # Texts.Int) & (S1.line = line) DO Texts.Scan(S1) END
	ELSE
		S1.class := Texts.Inval
	END;
	IF S1.class = Texts.Int THEN
		breakpc := S1.i;
		ftext := GetText(fpar);
		Texts.OpenReader(r, ftext, 0);
		GetLine(r, buf);  scan := FALSE;  breakpos := -1;
		WHILE ~r.eot & (breakpos < 0) DO
			IF buf = "Code:" THEN scan := TRUE
			ELSIF scan & (Scan(buf) >= breakpc) THEN breakpos := Texts.Pos(r)-1
			END;
			GetLine(r, buf)
		END;
		IF breakpos >= 0 THEN
			Texts.WriteString(W, "pos ");  Texts.WriteInt(W, breakpos, 1);
			Texts.WriteString(W, "  pc");  Texts.WriteHex(W, breakpc);  Texts.Write(W, "H");
			Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
			Locate(fpar, ftext, breakpos)
		END
	ELSE
		Texts.WriteString(W, "  pc not selected"); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END
END Find;

PROCEDURE SetSuffix*;	(* suffix *)
VAR S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class IN {Texts.Name, Texts.String} THEN
		COPY(S.s, objSuffix);
		Out.String("Object file suffix set to ");
		Out.String(objSuffix)
	ELSE
		Out.String("Parameter not found")
	END;
	Out.Ln
END SetSuffix;

BEGIN
	COPY(Modules.extension, objSuffix);
	(*Out.String("Decoder  NM / pjm / prk"); Out.Ln;*)
	breakpos := -1; suppressH := FALSE; suppressOut := FALSE;
	NEW(PE, 32);
	Texts.OpenWriter(W);  defaultFont := Fonts.This("Courier10.Scn.Fnt"); titleFont := Fonts.This("Oberon12b.Scn.Fnt")
END Decoder.

Decoder.Decode ^
Decoder.Decode \m ^
Decoder.SetSuffix .Obx
