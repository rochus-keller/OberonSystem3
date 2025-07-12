(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

(* ASM - i80386 assembler module for the OP2 compiler *)
(* pjm, prk *)



MODULE OPA;	(** non-portable *)
	IMPORT SYSTEM, Files, OPM, OPS, OPT, OPB;



	CONST 

		FileName = "OPA.Data";

		none = -1;
	
		(*processor targets*)
		i386 = 0;  i486 = 1;  Pentium = 2;  PentiumPro = 3; 
		FPU = 16;  Privileged = 17;
		
		(* node classes for inline instructions*)
		Nassembler = 29;
		Ncode = 30;
		Nfixup = 31;
		
		(* Own Symbol Table types *)
		StLabel = 0; StFwdLabel = 1;
		StConst = 3; StType = 4; StVar = 5; StVarPar = 6; StGlobal = 7;
		StMod = 11;

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
		
		(* Scanner: ASCII codes *)
		TAB = 09X;
		CR = 0DX;
		SPACE = 20X;
		(* Scanner: Sym values *)
		ScUndef = 0;
		ScIdent = 1; 
		ScSemicolon = 2;	(* ; *)
		ScAt = 3;	(* @ *)
		ScNumber = 4;
		ScComma = 5; 	(* , *)
		ScLBrak = 6;	(* [ *)
		ScRBrak = 7;	(* ] *)
		ScCR = 8;
		ScMult = 9;	(* * *)
		ScEnd = 10;
		ScLabel = 11;
		ScColon = 12;	(* : *)
		ScPlus = 13;
		ScMinus = 14;
		ScDiv = 15;
		ScLPar = 16;
		ScRPar = 17;
		ScString = 18;
		ScPoint = 19;
		ScLBrace = 20;
		ScRBrace = 21;
		
		(* Structure sizes *)
		NameLen = 32;
		MaxStrLen = 256;
		MnemoLen = 12;
		
		(* Opcodes modifiers *)
		OmReg = 1;		(* register stored in the RM byte as reg/opcode *)
		OmOp = 2;		(* register added to the opcode *)
		OmRMReg = 3;		(* register stored in the RM byte as r/m and reg/opcode*)
		
		(* Match evaluation *)
		NoMatch = 0; SizeCast = 1; TypeCast = 2; ConstCast = 3; Hit = 4;

	TYPE 
		Name = OPS.Name;
		Mnemo = ARRAY MnemoLen OF CHAR;
		
		(*Object: The symbol table. It's an ordered binary tree. First element is root.right *)
		Object = POINTER TO ObjDesc;
		FixPnt = POINTER TO FixPntDesc;
		
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
		
		Operand = RECORD
					mode: INTEGER;		(* the mode: Reg8.... *)
					imm: LONGINT;		(* the constant *)
					disp: LONGINT;
					index, base, reg: INTEGER;
					seg, scale: INTEGER;	(* segment override *)
					obj: Object;			(* the jmp label for forward jumps / the object referenced *)
				END;
				
		ObjDesc = RECORD
							typ: INTEGER;
							val, size:  LONGINT;		(* if typ <0 => pos of first use of this label *)
							name: Name;
							left, right, next: Object;
							fix: FixPnt;
							obj: OPT.Object
					 END;
		
		FixPntDesc = RECORD
						pc: LONGINT;
						node: OPT.Node;
						pos: LONGINT;
						next: FixPnt;
					END;

VAR
	(* Global structures *)
		root:  Object;	(* symbol table *)
		OpTab: POINTER TO ARRAY OF OpCode;	(* Table with the opcodes *)
		OpTabLen: INTEGER;		(* nof opcodes in the table *)
		InstrTab: POINTER TO ARRAY OF InstrDesc;	(* Table with the instructions !!Hash *)
		InstrTabLen: INTEGER;
		SizeTab: ARRAY 17 OF SHORTINT;		(* size of the oberon types *)
		TargetTab: ARRAY 32 OF RECORD  name: Name;  flag: SET  END;
		TargetCount: LONGINT;
		
	(* Configuration *)
		export, inline: BOOLEAN;		(* code is exported / inlined *)
		FirstTime: BOOLEAN;		(* First time the module is used *)
		Target: SET;						(* The target processor*)
		pc: LONGINT;	(* program counter. Should be used only for pc-rel jumps !! *)
		
	(* Scanner variables *)
		(*ch: CHAR;*)			(* look-ahead char is OPS.ch*)
		sym: INTEGER; 	(* last token read *)
		ident: Name;		(* last identifier read *)
		val: LONGINT;	  (* last value read *)
		str: ARRAY MaxStrLen OF CHAR;
		errpos: LONGINT;	(* starting position of the last instruction *)
	
	(* Instruction nodes *)
		first, last: OPT.Node;	(* first and last nodes in the instruction stream *)
		fixlist: OPT.Node;	(* list of fixups to be done by the back-end *)

(* ------------------------------------------------------------------- *)
(* Special functions *)

	PROCEDURE AND(a,b: LONGINT):LONGINT;
	BEGIN RETURN(ORD( BITS(a) * BITS(b)))
	END AND;

(* ------------------------------------------------------------------- *)
(* Addressing Mode functions *)


	
	PROCEDURE ModeSize(mode: INTEGER): INTEGER;
	BEGIN
		CASE mode OF
		  Imm8, Const1, Const3, Rel8, RegAL, RegCL, Reg8, RM8, M8, SImm8:
				RETURN(1)
		| Imm16, Rel16, RegAX, RegDX, Reg16, RM16, M16, SReg, RegCS, RegDS, RegES, RegFS, RegGS, RegSS:
				RETURN(2)
		| Imm32, Rel32, FwdJmp, RegEAX, Reg32, RM32, M32:
				RETURN(4)
		| M64:
				RETURN(8)
		| M80:
				RETURN(10)
		| RM:
				RETURN(0)
		ELSE RETURN(0)
		END
	END ModeSize;
	
	PROCEDURE ConstSize(i: LONGINT; signed: BOOLEAN):INTEGER;
	BEGIN
		IF (MIN(SHORTINT) <= i) & (MAX(SHORTINT) >= i) OR (~signed & (AND(i,0FFFFFF00H)=0)) THEN
			RETURN(1)
		ELSIF (MIN(INTEGER) <= i) & (MAX(INTEGER) >= i) OR (~signed & (AND(i,0FFFF0000H)=0))THEN
			RETURN(2)
		ELSE
			RETURN(4)
		END
	END ConstSize;
	
	PROCEDURE IsRegMode(m: INTEGER; strict: BOOLEAN):BOOLEAN;
	BEGIN
		RETURN((m=Reg8)OR(m=Reg16)OR(m=Reg32)OR
			(~strict &((m=RegAL)OR(m=RegAX)OR(m=RegEAX)OR(m=RegDX))))
	END IsRegMode;
	
	PROCEDURE IsSRegMode(m: INTEGER; strict: BOOLEAN):BOOLEAN;
	BEGIN
		RETURN((m=SReg)OR (~strict &(m=RegCS)OR(m=RegDS)OR(m=RegES)OR
			(m=RegFS)OR(m=RegGS)OR(m=RegSS)))
	END IsSRegMode;
	
	PROCEDURE IsSpecRegMode(m: INTEGER):BOOLEAN;
	BEGIN
		RETURN((m=CRReg)OR(m=DRReg)OR(m=TRReg))
	END IsSpecRegMode;
	
	PROCEDURE IsMMode(m: INTEGER):BOOLEAN;
	BEGIN
		RETURN((m=M)OR(m=M8)OR(m=M16)OR(m=M32)OR(m=M64)OR(m=M80))
	END IsMMode;
	
	PROCEDURE IsModRmMode(m: INTEGER):BOOLEAN;
	BEGIN
		RETURN((m=RM)OR(m=RM8)OR(m=RM16)OR(m=RM32) (*OR IsMMode(m)*))
	END IsModRmMode;
	
	PROCEDURE IsFRegMode(m: INTEGER; strict: BOOLEAN):BOOLEAN;
	BEGIN
		RETURN((m=FReg) OR (~strict & (m=FRegST)))
	END IsFRegMode;

	PROCEDURE NeedModRM(mode, regpos: INTEGER): BOOLEAN;
	BEGIN
		RETURN(IsModRmMode(mode) OR IsMMode(mode) OR
						((regpos = OmReg) OR (regpos =  OmRMReg)) & (IsRegMode(mode,TRUE) OR IsSRegMode(mode, FALSE) OR IsSpecRegMode(mode)))
	END NeedModRM;
	
	PROCEDURE IsImmMode(m: INTEGER):BOOLEAN;
	BEGIN
		RETURN((m=Imm8)OR(m=Imm16)OR(m=Imm32)OR(m=SImm8)OR(m=Imm))
	END IsImmMode;
	
	PROCEDURE IsRelMode(m: INTEGER):BOOLEAN;
	BEGIN
		RETURN((m=Rel8)OR(m=Rel16)OR(m=Rel32))
	END IsRelMode;
	
	PROCEDURE Evaluate(VAR op: Operand; mode: INTEGER):INTEGER;
	BEGIN
		IF mode = op.mode THEN RETURN(Hit)	(* 80% of the checks, now the 20% special cases *)
		ELSIF IsModRmMode(mode) THEN
			IF IsMMode(op.mode) THEN
				IF ModeSize(op.mode)=ModeSize(mode) THEN RETURN Hit
				ELSIF (op.mode = RM) OR (op.mode = M) THEN RETURN SizeCast
				ELSE RETURN NoMatch END
			ELSIF IsRegMode(op.mode, FALSE) & (ModeSize(op.mode)=ModeSize(mode)) THEN RETURN TypeCast
			ELSE RETURN NoMatch END
		ELSIF IsRegMode(mode,TRUE) THEN	(* cannot be a specific reg (AL,AX,EAX) *)
			IF ModeSize(op.mode)=ModeSize(mode) THEN
				IF IsRegMode(op.mode,TRUE) THEN RETURN Hit
				ELSIF IsRegMode(op.mode, FALSE) THEN RETURN TypeCast
				ELSE RETURN NoMatch END
			ELSE RETURN NoMatch
			END
		ELSIF mode = RegDX THEN
			IF (op.mode = Reg16) & (op.reg = 2) THEN RETURN Hit ELSE RETURN NoMatch END	(* special case for IN/OUT which uses DX *)
		ELSIF mode = RegCL THEN
			IF (op.mode = Reg8) & (op.reg = 1) THEN RETURN Hit ELSE RETURN NoMatch END	(* special case for shift/rotate which uses CL *)
		ELSIF IsRegMode(mode, FALSE) THEN RETURN NoMatch
		ELSIF IsImmMode(mode) THEN
			IF op.mode = Imm THEN
				IF ModeSize(mode)  > ConstSize(op.imm, mode = SImm8) THEN RETURN ConstCast
				ELSIF ModeSize(mode)  = ConstSize(op.imm, mode = SImm8) THEN RETURN Hit
				ELSE RETURN NoMatch END
			ELSIF IsImmMode(op.mode) THEN
				IF ModeSize(mode)  > ModeSize(op.mode) THEN RETURN ConstCast
				ELSIF ModeSize(mode)  = ModeSize(op.mode) THEN RETURN Hit
				ELSE RETURN NoMatch END
			ELSE RETURN NoMatch END
		ELSIF mode = Const1 THEN
			IF IsImmMode(op.mode) & (op.imm = 1) THEN RETURN Hit ELSE RETURN NoMatch END
		ELSIF mode = Const3 THEN
			IF IsImmMode(op.mode) & (op.imm = 3) THEN RETURN Hit ELSE RETURN NoMatch END
		ELSIF IsMMode(mode) THEN
			IF IsMMode(op.mode) THEN
				IF ModeSize(op.mode)=ModeSize(mode) THEN RETURN Hit
				ELSIF (op.mode = M) OR (mode = M) THEN RETURN SizeCast
				ELSE RETURN NoMatch END
			ELSE RETURN NoMatch END
		ELSIF mode = SReg THEN
			IF IsSRegMode(op.mode,FALSE) THEN RETURN Hit ELSE RETURN NoMatch END
		ELSIF IsRelMode(mode) THEN
			IF (mode = Rel32) & (op.mode = FwdJmp) THEN RETURN Hit
			ELSIF IsImmMode(op.mode) THEN
				IF ModeSize(mode) = ConstSize(op.imm, TRUE) (*ModeSize(op.mode)*) THEN RETURN Hit
				ELSIF ModeSize(mode) > ConstSize(op.imm, TRUE) (*ModeSize(op.mode)*) THEN RETURN ConstCast
				ELSE RETURN NoMatch END
			ELSE RETURN NoMatch END 
			
		ELSIF mode = FReg THEN
			IF IsFRegMode(op.mode, TRUE) THEN RETURN Hit 
			ELSIF IsFRegMode(op.mode, FALSE) THEN RETURN TypeCast
			ELSE RETURN NoMatch END
		ELSE RETURN NoMatch
		END

	END Evaluate;
	
	
	PROCEDURE Match(VAR ind: INTEGER; VAR op: ARRAY OF Operand);
		VAR start, end, i, j, k, best: INTEGER;
		
	BEGIN

		start := InstrTab[ind].start; end := InstrTab[ind].end; ind := -1; best := 0;
		WHILE start < end DO
			i := Evaluate(op[0], OpTab[start].op[0]);
			IF (i = NoMatch) THEN 
			ELSE
				j := Evaluate(op[1], OpTab[start].op[1]);
				IF j = NoMatch  THEN i := NoMatch
				ELSE
					k := Evaluate(op[2], OpTab[start].op[2]);
					IF (i < j) & (i < k) THEN
					ELSIF j < k THEN i :=  j
					ELSE i := k
					END
				END
			END;

			IF i # NoMatch THEN
				IF i = Hit THEN ind := start; RETURN
				ELSIF i > best THEN ind := start; best := i
				ELSIF (i = best) & (i = SizeCast) THEN OPM.Mark(512, errpos); ind := -1; RETURN
				END
			END;
			INC(start)
		END;
		IF ind = -1 THEN OPM.Mark(501, errpos) END
	END Match;
	

(* ------------------------------------------------------------------- *)
(* Symbol Table / Instr Table / Op Table  functions *)

	PROCEDURE insert(IN name: ARRAY OF CHAR; VAR obj: Object);
		VAR ob0, ob1: Object; d: INTEGER;
	BEGIN ob0 := root; ob1 := ob0.right; d := 1;
		LOOP
			IF ob1 = NIL THEN (*insert undefined label*)
				NEW(ob1); ob1.name := name; ob1.typ := StFwdLabel;
				ob1.left := NIL; ob1.right := NIL; ob1.fix := NIL; ob1.obj := NIL;
				ob1.next := root.next; root.next := ob1;
				ob1.val := OPM.errpos;
				IF d < 0 THEN ob0.left := ob1 ELSE ob0.right := ob1 END;
			ELSIF name < ob1.name THEN d := -1; ob0 := ob1; ob1 := ob1.left
			ELSIF name > ob1.name THEN d :=  1; ob0 := ob1; ob1 := ob1.right
			ELSE (*found, no insertion*) EXIT END
		END;

		obj := ob1
	END insert;

	PROCEDURE ConvertObj(ob: OPT.Object): Object;
	VAR obj: Object;
	BEGIN
		IF ob # NIL THEN
			NEW(obj);
			CASE ob.mode OF
			  1: (* Var *)
					obj.val := 1; obj.size := SizeTab[ob.typ.form];
					IF ob.mnolev <= 0 THEN
						obj.typ := StGlobal
					ELSE
						obj.typ := StVar 
					END
			| 2: (* VarPar *)
					obj.typ := StVarPar; obj.val := 1; obj.size := 4
			| 3: (* Con *)
					obj.typ := StConst; obj.val := ob.conval.intval;
					IF (ob.typ.form > 6) OR (ob.typ.form = 2) THEN OPM.err(51)
					END
			| 5: (* Type *)
					obj.typ := StType; obj.size := SizeTab[ob.typ.form]; OPM.err(514)
			| 11: (* Mod *)
					obj.typ := StMod
			ELSE obj.typ := StConst; obj.val := 0; OPM.err(514)
			END;
			obj.obj := ob
		END;
		RETURN obj
	END ConvertObj;

	PROCEDURE find(VAR name: Name; VAR obj: Object);
		VAR ob0: Object; ob : OPT.Object;
	BEGIN ob0 := root.right;

		WHILE (ob0 # NIL) & (ob0.name # name) DO

			IF name < ob0.name THEN ob0 := ob0.left ELSE ob0 := ob0.right END
		END;

		obj := ob0;
		IF obj = NIL THEN
			OPS.name := name; OPT.Find(ob);
			IF ob # NIL THEN  obj := ConvertObj(ob)  ELSE  insert(name, obj)		(* create forward jump *)
			END;
		END;
	END find;

	(* Generates the hash index k for the n-th try. n>=0 *)
	PROCEDURE HashFn(VAR name: ARRAY OF CHAR; VAR k, n: INTEGER);
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
	
	PROCEDURE FindInstruction(VAR name: ARRAY OF CHAR; VAR inx: INTEGER);
		VAR n: INTEGER;
	BEGIN
		n := 0;
		REPEAT
			HashFn(name, inx, n)
		UNTIL (name = InstrTab[inx].name) OR (InstrTab[inx].name[0] = 0X) OR (n >InstrTabLen);
		IF (InstrTab[inx].name[0] = 0X) OR (n >InstrTabLen) THEN inx := -1 
		ELSIF (InstrTab[inx].target+Target # Target) THEN	OPM.err(515)
		END
	END FindInstruction;
	
(* ------------------------------------------------------------------- *)
(* Scanner functions *)

	PROCEDURE skipBlanks;
	BEGIN
		WHILE (OPS.ch = SPACE) OR (OPS.ch = TAB) DO OPM.Get(OPS.ch) END;
		IF OPS.ch = ";" THEN
			WHILE (OPS.ch # CR) DO OPM.Get(OPS.ch) END	(* Skip comments *)
		END
	END skipBlanks;

	PROCEDURE GetIdent(VAR name: Name);
		VAR i: INTEGER;
	BEGIN i := 0; OPM.errpos := OPM.curpos - 1;
		REPEAT
			IF i < NameLen-1 THEN name[i] := OPS.ch; INC(i) END;
			OPM.Get(OPS.ch)
		UNTIL ~(("A" <= CAP(OPS.ch)) & (CAP(OPS.ch) <= "Z") OR ("0" <= OPS.ch) & (OPS.ch <= "9"));
		name[i] := 0X
	END GetIdent;

	PROCEDURE Get(VAR sym: INTEGER);
	
		PROCEDURE Comment;
		BEGIN

			OPM.Get(OPS.ch);	(* skip "*" *)
			REPEAT
				REPEAT
					OPM.Get(OPS.ch);
					IF OPS.ch = "(" THEN
						OPM.Get(OPS.ch);
						IF OPS.ch = "*" THEN Comment END
					END;
				UNTIL (OPS.ch = "*") OR (OPS.ch = OPM.Eot);
				OPM.Get(OPS.ch)
			UNTIL (OPS.ch = ")") OR (OPS.ch = OPM.Eot);
			OPM.Get(OPS.ch)

		END Comment;
		
		PROCEDURE Str;
			VAR och: CHAR; i: LONGINT;
		BEGIN
			och := OPS.ch; i := 0;
			LOOP
				OPM.Get(OPS.ch);
				IF OPS.ch = och THEN EXIT
				ELSIF OPS.ch < " " THEN OPM.err(3); EXIT
				ELSIF i = MaxStrLen-1 THEN OPM.err(241); EXIT
				END;
				str[i] := OPS.ch; INC(i)
			END;
			OPM.Get(OPS.ch);
			str[i] := 0X; val := i;
		END Str;
		
	BEGIN
		skipBlanks;
		OPM.errpos := OPM.curpos;
		CASE OPS.ch OF
		  "A" .. "Z", "a" .. "z" :
				GetIdent(ident); 
				IF OPS.ch = ":" THEN 
					OPM.Get(OPS.ch); sym := ScLabel
        		ELSIF ident = "END" THEN
        			sym := ScEnd
        		ELSE
					sym := ScIdent(*; find(ident, obj);
					IF obj # NIL THEN type := SHORT(obj.typ); val := obj.val 
					ELSE type := none END*)
				END
		| "0".."9":
				val := 0; sym := ScNumber;
				OPS.Number;
				ASSERT(OPS.numtyp <= 2);
				val := OPS.intval
		| ";":   OPM.Get(OPS.ch); sym := ScSemicolon
		| "@": OPM.Get(OPS.ch); sym := ScAt
		| ",":   OPM.Get(OPS.ch); sym := ScComma
		| "[":   OPM.Get(OPS.ch); sym := ScLBrak
		| "]":   OPM.Get(OPS.ch); sym := ScRBrak
		| "{":   OPM.Get(OPS.ch); sym := ScLBrace
		| "}":   OPM.Get(OPS.ch); sym := ScRBrace
		| CR:	OPM.Get(OPS.ch); sym := ScCR
		| "*":	OPM.Get(OPS.ch); sym := ScMult
		| "/":	OPM.Get(OPS.ch); sym := ScDiv
		| "+":	OPM.Get(OPS.ch); sym := ScPlus
		| "-":	OPM.Get(OPS.ch); sym := ScMinus
		| "(":   OPM.Get(OPS.ch);
					IF OPS.ch = "*" THEN Comment; Get(sym)
					ELSE sym := ScLPar
					END;
		| ")":   OPM.Get(OPS.ch); sym := ScRPar
		| ":":	OPM.Get(OPS.ch); sym := ScColon
		| ".":	OPM.Get(OPS.ch); sym := ScPoint
		| 22X, 27X: Str; sym := ScString;
		ELSE  sym := ScUndef; OPM.Get(OPS.ch)
		END

	END Get;
	
	PROCEDURE Check(s: INTEGER);
	BEGIN IF sym # s THEN OPM.err(s) END;
		Get(sym)
	END Check;

	PROCEDURE Qualident(VAR obj: Object);
	VAR i: LONGINT;  o: OPT.Object;
	BEGIN
		obj := NIL;
		IF sym = ScIdent THEN
			IF ident = "SYSTEM" THEN
				IF ~OPT.SYSimported THEN OPM.err(135) END;
				OPS.name := "SYSTEM";
				OPT.Find(o);
				IF o # NIL THEN
					INCL(o.flag, OPT.used)
				END;
				Get(sym);
				IF sym=ScPoint THEN
					Get(sym);
					IF sym = ScIdent THEN
						i := 0;
						WHILE (i < TargetCount) & (TargetTab[i].name # ident) DO INC(i) END;
						IF i = TargetCount THEN OPM.err(0)
						ELSE
							NEW(obj); obj.typ := StConst;  obj.val := i
						END
					ELSE OPM.err(0)
					END;
					Get(sym)
				ELSE OPM.err(18(*point*))
				END
			ELSE
				Get(sym);  find(ident, obj);
				IF (obj#NIL) & (sym=ScPoint) & (obj.typ=StMod) THEN
					Get(sym);  OPS.name := ident;
					OPT.FindImport(obj.obj, obj.obj);  obj := ConvertObj(obj.obj)
				END;
				IF obj=NIL THEN OPM.err(0) END
			END
		ELSE OPM.err(40)
		END
	END Qualident;
	
	PROCEDURE Expression(VAR x: LONGINT);
		VAR y: LONGINT; op : INTEGER;

		PROCEDURE Factor(VAR x: LONGINT);
		BEGIN
			IF sym = ScNumber THEN x := val; Get(sym)
			ELSIF sym = ScLPar THEN
				Get(sym); Expression(x);
				Check(ScRPar)
			ELSE OPM.err(601)
			END
		END Factor;
	
		PROCEDURE Term(VAR x: LONGINT);
			VAR y: LONGINT; op : INTEGER;
		BEGIN
			Factor(x);
			WHILE (sym = ScMult) OR (sym = ScDiv) DO
				op := sym; Get(sym);
				Factor(y);
				IF op = ScMult THEN x := x * y ELSE x := x DIV y END
			END
		END Term;
	
	BEGIN
		IF sym = ScMinus THEN op := sym; Get(sym); Term(x); x := -x
		ELSE Term(x)
		END;
		WHILE (sym = ScPlus) OR (sym = ScMinus) DO
			op := sym; Get(sym);
			Term(y);
			IF op = ScPlus THEN x := x + y ELSE x := x - y END
		END
	END Expression;

	PROCEDURE GetBaseIndex(VAR o: Operand; size: LONGINT);
		VAR obj: Object;
	BEGIN
		CASE size OF
			  0: o.mode := M
			| 1: o.mode := M8
			| 2: o.mode := M16
			| 4: o.mode := M32
			| 8: o.mode := M64
			| 10: o.mode := M80
		END;
		o.disp := o.imm; o.imm := 0;		(* this is not a const but a rm !! *)
		WHILE (sym = ScLBrak) OR (sym = ScPlus) DO
			Get(sym);
			IF sym = ScIdent THEN find(ident, obj) ELSE obj := NIL END;
			IF (obj = NIL) OR ~IsRegMode(obj.typ, FALSE) OR (ModeSize(obj.typ) # 4) THEN 
				OPM.err(506); RETURN
			END;
			Get(sym);
			IF sym = ScMult THEN		(* This is the index, get the scale *)
				IF o.index # none THEN OPM.err(509); RETURN END;
				o.index := SHORT(obj.val);
				Get(sym);
				IF (sym # ScNumber) OR ((val # 1) & (val # 2) & (val # 4) & (val # 8)) THEN 
					OPM.err(508); RETURN
				END;
				o.scale := SHORT(val);
				Get(sym);
			ELSIF (sym = ScRBrak) OR (sym = ScPlus) THEN
				IF o.base = none THEN o.base := SHORT(obj.val)
				ELSIF o.index = none THEN o.index := SHORT(obj.val)
				ELSE OPM.err(509)
				END;
			ELSE OPM.err(510); RETURN
			END;
			IF sym = ScRBrak THEN Get(sym) END
		END; (* WHILE ScLBrak *)
		END GetBaseIndex;

	PROCEDURE GetOperand(VAR o: Operand);
		VAR obj: Object; size: LONGINT;
	BEGIN
		o.reg := none; o.disp := 0; o.base := none; o.index := none; o.imm := 0;
		o.seg := none; o.scale := none; o.obj := NIL;
		size := 0;	(* unknown size *)
		IF sym = ScIdent THEN
			find(ident, obj);
			IF (obj # NIL) & (obj.typ = SReg) THEN
				o.seg := SHORT(obj.val); Get(sym); Check(ScColon);
				IF sym = ScIdent THEN find(ident, obj) END
			END
		END;
		IF (sym = ScIdent) & (obj # NIL) & (obj.typ = StType) THEN
			size := SHORT(obj.size); Get(sym);
			IF (sym # ScIdent) OR (ident # "PTR") THEN (* OPM.err(511) *)	(* PTR is optional *)
			ELSE Get(sym)
			END;
			IF sym = ScIdent THEN find(ident, obj) END
		END;
		CASE sym OF
		  ScAt:
				Get(sym);
				IF sym # ScNumber THEN OPM.err(-601) END;
				o.disp := val; o.mode := RM32;
				Get(sym);
		| ScLBrak:
				GetBaseIndex(o, size)
		| ScIdent, ScNumber, ScMinus:

				IF sym = ScIdent THEN
					IF obj = NIL THEN OPM.err(500); RETURN END;
					
					IF size = 0 THEN size := obj.size END;		(* don't override the xyz PTR command *)
					
					IF IsRegMode(obj.typ, FALSE) THEN
						o.mode := obj.typ; o.reg := SHORT(obj.val); Get(sym); RETURN
					ELSIF IsSRegMode(obj.typ, FALSE) THEN
						o.mode := obj.typ; o.reg := SHORT(obj.val); Get(sym); RETURN
					ELSIF IsSpecRegMode(obj.typ) THEN
						IF ~(Privileged IN Target) THEN OPM.err(515) END;
						IF ~(Pentium IN Target) & (obj.typ = CRReg) & (obj.val = 4) THEN OPM.err(515) END;
						o.mode := obj.typ; o.reg := SHORT(obj.val); Get(sym); RETURN
					ELSIF IsFRegMode(obj.typ, FALSE) THEN
						o.mode := obj.typ; Get(sym);
						IF sym = ScLPar THEN Expression(size); o.reg := SHORT(size) ELSE o.reg := 0; o.mode := FRegST END;
						RETURN
					ELSIF obj.typ = StLabel THEN
						o.imm := obj.val; o.mode := Rel8; Get(sym); RETURN
					ELSIF obj.typ = StFwdLabel THEN
						o.obj := obj; o.mode := FwdJmp; Get(sym); RETURN
					ELSIF obj.typ = StConst THEN
						o.imm := obj.val; Get(sym);
					ELSIF (obj.typ = StVar) OR (obj.typ = StVarPar) THEN
						IF inline THEN  OPM.err(518)  END;
						o.imm := obj.val; o.obj := obj; Get(sym)
					ELSIF (obj.typ = StGlobal) THEN
						o.disp := 012345678H; o.obj := obj; 
						CASE size OF
						  1: o.mode := M8
						| 2: o.mode := M16
						| 4: o.mode := M32
						| 8: o.mode := M64
						| 10: o.mode := M80
						ELSE o.mode := M32
						END;
						Get(sym); RETURN		(* Global Var *)
					ELSE OPM.err(600); RETURN END
				ELSE Expression(o.imm)
				END;

				CASE size OF
				  1: o.mode := Imm8
				| 2: o.mode := Imm16
				| 4: o.mode := Imm32
				ELSE o.mode := Imm
				END;
				IF sym = ScLBrak THEN GetBaseIndex(o, size) END;
		ELSE
			o.mode := none; OPM.err(511)
		END;  (* CASE sym OF *)
	END GetOperand;
	
(* ------------------------------------------------------------------- *)
(* Fixpoint handling functions *)

	PROCEDURE CheckLabels;
		VAR obj, obj1, obj2: Object;
	BEGIN obj1 := root.next; obj := NIL; (* invert list *)
		WHILE obj1 # NIL DO
			obj2 := obj1.next; obj1.next := obj; obj := obj1; obj1 := obj2
		END;
		WHILE obj # NIL DO
			IF obj.typ = StFwdLabel THEN
				OPM.Mark(128, obj.val)	(* unsatisfied forward reference *)
			END;
			obj := obj.next
		END
	END CheckLabels;

	PROCEDURE InsertFix(VAR obj: Object; pc: LONGINT);
		VAR fix: FixPnt; x: OPT.Node;
	BEGIN
		CASE obj.typ OF
		  StFwdLabel:
			NEW(fix); fix.pc := pc;
			fix.node := last;
			fix.pos := ORD(last.conval.ext[0])-3;	(* displacement position *)
			fix.next := obj.fix; obj.fix := fix
		| StVar, StVarPar, StGlobal:
			IF export & inline THEN  OPM.err(517)  END;
			x := OPT.NewNode(Nfixup);
			x.obj := obj.obj; x.conval := OPT.NewConst();
			x.conval.intval := pc; x.conval.intval2 := OPM.errpos;
			x.link := fixlist; fixlist := x
		ELSE
			OPM.err(607)
		END
	END InsertFix;

	PROCEDURE FixDisp(VAR fix: FixPnt);
		VAR pos, disp: LONGINT;
	BEGIN
		disp := pc - fix.pc;
		FOR pos := fix.pos TO fix.pos+3 DO
			fix.node.conval.ext[pos] := CHR(disp);
			disp := disp DIV 256
		END;
	END FixDisp;
	
(* ------------------------------------------------------------------- *)
(* Code Generation functions *)

PROCEDURE NewNode;
	VAR x: OPT.Node;
BEGIN
	x := OPT.NewNode(Ncode); x.conval := OPT.NewConst();
	x.conval.ext := OPT.NewExt(); x.conval.ext[0] := 0X;	(* Instr length *)
	x.conval.intval := OPM.errpos;
	OPB.Link(first, last, x)
END NewNode;

PROCEDURE PutByte(b: LONGINT);
	VAR pos: INTEGER;
BEGIN
	pos := ORD(last.conval.ext[0]) + 1;
	IF pos > 255 THEN
		NewNode; pos := 1
	END;
	last.conval.ext[pos] := CHR(b);
	last.conval.ext[0] := CHR(pos);
	INC(pc)
END PutByte;

PROCEDURE PutBytes(b, size: LONGINT);
	VAR pos: INTEGER;
BEGIN
	pos := ORD(last.conval.ext[0]);
	IF pos > 255-size THEN
		NewNode; pos := 0
	END;
	WHILE size>0 DO
		INC(pos); last.conval.ext[pos] := CHR(b);
		b := b DIV 256; INC(pc); DEC(size);
	END;
	last.conval.ext[0] := CHR(pos)
END PutBytes;

PROCEDURE ModRM(VAR modrm: LONGINT; VAR op: Operand; mode, regpos: INTEGER; UseSpecReg: BOOLEAN);
	VAR mod: LONGINT;
BEGIN

	IF (IsRegMode(mode,TRUE) & ~UseSpecReg) OR IsSRegMode(mode, FALSE) OR IsSpecRegMode(mode) THEN 
		(* put reg index into the reg/opcode field *)
		ASSERT(op.reg # none);
		IF regpos = OmRMReg THEN	(*add to modrm too*)
			ASSERT(modrm = 0);	(*not set yet*)
			modrm := 3 * 40H + op.reg * 9H	(* R/M and Reg/Opcode set to op.reg *)
		ELSE
			modrm := modrm + op.reg * 8H
		END
	ELSIF IsModRmMode(mode) OR IsMMode(mode) OR (IsRegMode(mode,TRUE) & UseSpecReg) THEN
		IF op.reg # none THEN
			(* put reg index into the r/m field, 3H into the Mod field *)
			modrm := modrm + op.reg + 0C0H;
		ELSE
			(* set the mod field *)
			IF (op.disp = 0) & ~((op.base = 5) & (op.index = none)) THEN 	(* avoid case 0[EBP] *)
				mod := 0
			ELSIF ConstSize(op.disp, TRUE)=1 THEN
				mod := 1
			ELSIF (op.base = none) & (op.index = none) THEN
				mod := 0
			ELSE
				mod := 2
			END;
			modrm := modrm + mod * 40H;
			IF op.index # none THEN
				modrm := modrm + 4		(* use the sib byte *)
			ELSIF op.base # none THEN
				modrm := modrm + op.base
			ELSE 
				modrm := modrm + 5			(* special case: disp32 *)
			END
		END
	ELSE OPM.err(1000)
	END
END ModRM;

PROCEDURE SIB(op: Operand): SHORTINT;
	VAR val: INTEGER;
BEGIN
	IF op.index = 4 THEN 	(* ESP not allowed *)
		OPM.err(501)
	ELSIF op.index # none THEN
		val := op.base + op.index*08H;
		CASE op.scale OF
		  none, 1: 
		|2: val := val + 1 * 40H
		|4: val := val + 2 * 40H
		|8: val := val + 3 * 40H
		END
	ELSE
		val := op.base + 04H*08H;
	END;
	RETURN(SHORT(val))
END SIB;

PROCEDURE GenCode(ind: INTEGER; VAR op: ARRAY OF Operand);
	VAR i: LONGINT; name: Mnemo; fixobj: Object;
		UseRM, UseImm, UseSpecReg, UseSegReg, UseDisp: BOOLEAN; seg, reg, modrm, sib, imm, immSize, disp: LONGINT;
BEGIN
(* Initialisation *)
	disp := 0;
	IF IsRelMode(op[0].mode) THEN		(* compute the size of the rel operand *)
		CASE ConstSize(op[0].imm-2 - pc, TRUE) OF		(* +2 = place for prefix & opcode0 *)
		  1: op[0].mode := Rel8
		| 2, 4: op[0].mode := Rel32
		END
	END;
	name := InstrTab[ind].name;
	
	Match(ind, op);
	


	IF ind < 0 THEN RETURN END;	(* no matching opcode found *)
	
(* Instruction prefix *)
	UseSpecReg := IsSpecRegMode(OpTab[ind].op[0]) OR IsSpecRegMode(OpTab[ind].op[1]);
	UseSegReg := IsSRegMode(OpTab[ind].op[0], FALSE) OR IsSRegMode(OpTab[ind].op[1], FALSE);
	
		IF ~UseSpecReg & ~UseSegReg & 
			(name[0] # "F") & (		(* float instruction always have different opcodes for M16 *)
			((name = "OUT") & (ModeSize(OpTab[ind].op[1]) = 2)) OR
			((name # "OUT") & (ModeSize(OpTab[ind].op[0]) = 2))) THEN	(* 16-bit mode *)
			IF (OpTab[ind].op[0] = Rel16) OR (((name ="LEA")OR(name="OUTS")) & (OpTab[ind].op[1] = RM16)) THEN
				PutByte(67H);	(* operand size prefix *)
			ELSIF (name # "RET") & (name # "ARPL") & (name # "STR") THEN
				PutByte(66H) 
			END
		END;
		
(* prepare the instruction*)
		seg := none; reg := none; modrm := 0; UseRM := FALSE; sib := none;
		UseImm := FALSE; fixobj := NIL;
		UseDisp := FALSE;
		i := 0;
		WHILE (i<3) & (OpTab[ind].op[i] # none) DO
			(* segment prefix *)
			IF op[i].seg # none THEN

				IF seg # none THEN OPM.err(504) ELSE seg := op[i].seg END;
			END;
			(* register to be added to the opcode *)
			IF (OpTab[ind].reg = OmOp) & (IsRegMode(OpTab[ind].op[i], TRUE) OR IsFRegMode(OpTab[ind].op[i], TRUE)) THEN

				reg := op[i].reg
			END;
			(* modrm byte *)
			IF NeedModRM(OpTab[ind].op[i], OpTab[ind].reg) THEN

				ModRM(modrm, op[i], OpTab[ind].op[i], OpTab[ind].reg, UseSpecReg); UseRM := TRUE; 
				IF IsModRmMode(OpTab[ind].op[i]) OR IsMMode(OpTab[ind].op[i]) THEN 
					disp := op[i].disp; fixobj := op[i].obj;
					UseDisp := (disp # 0) OR ((op[i].base = 5) & (op[i].index = none))
				END
			END;
			(* sib byte *)
			IF (op[i].index # none) OR (op[i].base = 4) THEN			(* process the escape ESP *)

				ASSERT (sib = none);
				sib := SIB(op[i])
			END;
			IF IsImmMode(OpTab[ind].op[i]) OR (IsRelMode(OpTab[ind].op[i]) & IsImmMode(op[i].mode)) THEN

				ASSERT( ~UseImm);
				UseImm := TRUE; imm := op[i].imm; immSize := ModeSize(OpTab[ind].op[i]) 
			END;
			INC(i);
		END;


(* segment override *)
		IF seg # none THEN PutByte(seg) END;
		
(* opcode *)
		IF reg = none THEN reg := 0 END;
		IF OpTab[ind].op1 # none THEN
			PutByte(OpTab[ind].op0); PutByte(OpTab[ind].op1 + reg)
		ELSE
			PutByte(OpTab[ind].op0 + reg)
		END;

	(* modr/m *)
		IF OpTab[ind].opc # none THEN
			ASSERT( AND(modrm, 38H) = 0);		(* reg/opcode field not used *)
			modrm := modrm + OpTab[ind].opc * 8H;
			UseRM := TRUE
		END;
		IF UseRM THEN PutByte(modrm) END;
		
	(* sib *)
		IF sib # none THEN PutByte(sib) END;
		
	(* displacement / immediate *)
		IF  UseDisp THEN
			IF fixobj # NIL THEN InsertFix(fixobj, pc) END;
			IF ConstSize(disp, TRUE) = 1 THEN PutByte(disp) ELSE PutBytes(disp, 4) END
		END;
		IF IsRelMode(OpTab[ind].op[0]) & ~IsImmMode(op[0].mode) THEN
			PutBytes(op[0].imm-pc-ModeSize(OpTab[ind].op[0]), ModeSize(OpTab[ind].op[0]));
			IF op[0].mode = FwdJmp THEN InsertFix(op[0].obj, pc) END
		END;
		IF UseImm THEN PutBytes(imm, immSize) END;
END GenCode;


(* ------------------------------------------------------------------- *)
(* Parser functions *)

	PROCEDURE ParseLabel;
		VAR obj: Object; fix: FixPnt;
	BEGIN

		ASSERT(sym = ScLabel);		(* Test done by the caller *)
		insert(ident, obj);
		IF obj.typ = StFwdLabel THEN
			fix := obj.fix;
			WHILE fix # NIL DO
				FixDisp(fix); fix := fix.next
			END;
			obj.typ := StLabel; obj.val := pc
		ELSE OPM.err(512)
		END;
		Get(sym)
	END ParseLabel;

	PROCEDURE ParseInstruction;
		VAR	ind, size: INTEGER; i: LONGINT; op: ARRAY 3 OF Operand; name: Name;
	BEGIN

		(* Read Mnemonic *)
			IF (ident = "DB") OR (ident = "DW") OR (ident = "DD") THEN
				CASE ident[1] OF
				   "B": size := 1
				| "W": size := 2
				| "D": size := 4
				END;
				Get(sym);
				WHILE (sym = ScNumber) OR (sym = ScString) DO
					IF (sym = ScString) & (val = 1) THEN PutBytes(ORD(str[0]), size)
					ELSIF (sym = ScNumber) & (ConstSize(val, FALSE) <= size) THEN PutBytes(val, size)
					ELSE OPM.err(203)
					END;
					Get(sym);
					IF sym = ScComma THEN Get(sym) 
					ELSE RETURN
					END
				END
			ELSIF (ident = "DS") THEN
				Get(sym);
				IF (sym = ScString) THEN
					FOR i := 0 TO val DO PutBytes(ORD(str[i]), 1) END;
					Get(sym)
				ELSE OPM.err(513)
				END
			ELSE
				FOR i := 0 TO 2 DO op[i].mode := none END;
				FindInstruction(ident, ind);	(* index in the hash tab *)
				name := ident;
				errpos := OPM.errpos;
				Get(sym);
				IF ind < 0 THEN OPM.err(502); RETURN END;
				
				name[3] := 0X;
				IF name = "REP" THEN	(* REP/REPE/REPZ/REPNE/REPNZ *)
					GenCode(ind, op);
					IF sym = ScCR THEN Get(sym) END;		(* there should be no label here *)
					FindInstruction(ident, ind);	(* index in the hash tab *)
					errpos := OPM.errpos;
					Get(sym);
					IF ind < 0 THEN OPM.err(502); RETURN END
				END;
				
				i := 0;
				IF sym # ScCR THEN
					LOOP
						GetOperand(op[i]); INC(i);
						IF sym # ScComma THEN EXIT END;
						Get(sym)
					END
				END;
				
				GenCode(ind, op);
			END (* IF DB *)
	END ParseInstruction;

	PROCEDURE ParseTarget;
	VAR obj: Object;
	BEGIN
		LOOP
			IF sym = ScIdent THEN
				Qualident(obj);
				IF (obj = NIL) THEN OPM.err(0)
				ELSIF (obj.typ = StConst) THEN
					Target := Target + TargetTab[obj.val].flag
				ELSE OPM.err(0)
				END
			ELSE OPM.err(40)
			END;
			IF (sym = ScRBrace) THEN Get(sym); EXIT
			ELSIF sym = ScComma THEN Get(sym)
			ELSIF sym # ScIdent THEN OPM.err(24(*rbrace*)); EXIT
			ELSE OPM.err(19(*Comma*))
			END
		END
	END ParseTarget;
	
(* ------------------------------------------------------------------- *)
(* Initialisation functions *)

	PROCEDURE InsertReg(IN name: ARRAY OF CHAR; t, v: INTEGER);
		VAR obj: Object;
	BEGIN
		insert(name, obj); obj.typ := t; obj.val := v; obj.size := 0
	END InsertReg;
	
	PROCEDURE InsertType(IN name: ARRAY OF CHAR; s: INTEGER);
		VAR obj: Object;
	BEGIN
		insert(name, obj); obj.typ := StType; obj.val := none; obj.size := s
	END InsertType;

	PROCEDURE Init;
	BEGIN 
		(* Internal Symbol-Table *)
			root.next := NIL; root.left := NIL; root.right := NIL;
			InsertReg("AL", RegAL, 0); InsertReg("AH", Reg8, 4);
			InsertReg("AX", RegAX, 0); InsertReg("EAX", RegEAX, 0);
			InsertReg("BL", Reg8, 3); InsertReg("BH", Reg8, 7);
			InsertReg("BX", Reg16, 3); InsertReg("EBX", Reg32, 3);
			InsertReg("CL", Reg8, 1); InsertReg("CH", Reg8, 5);
			InsertReg("CX", Reg16, 1); InsertReg("ECX", Reg32, 1);
			InsertReg("DL", Reg8, 2); InsertReg("DH", Reg8, 6);
			InsertReg("DX", Reg16, 2); InsertReg("EDX", Reg32, 2);
			InsertReg("SP", Reg16, 4); InsertReg("ESP", Reg32, 4);
			InsertReg("BP", Reg16, 5); InsertReg("EBP", Reg32, 5);
			InsertReg("SI", Reg16, 6); InsertReg("ESI", Reg32, 6);
			InsertReg("DI", Reg16, 7); InsertReg("EDI", Reg32, 7);
			
			InsertReg("CS", RegCS, 1H); InsertReg("SS", RegSS, 2H);
			InsertReg("DS", RegDS, 3H); InsertReg("ES", RegES, 0H);
			InsertReg("FS", RegFS, 4H); InsertReg("GS", RegGS, 5H);
			
			InsertReg("CR0", CRReg, 0); InsertReg("CR2", CRReg, 2); InsertReg("CR3", CRReg, 3);
			InsertReg("CR4", CRReg, 4);
			InsertReg("DR0", DRReg, 0); InsertReg("DR1", DRReg, 1); InsertReg("DR2", DRReg, 2);
			InsertReg("DR3", DRReg, 3); InsertReg("DR6", DRReg, 6); InsertReg("DR7", DRReg, 7);
			(*InsertReg("TR6", TRReg, 6); InsertReg("TR7", TRReg, 7);*)
			
			InsertReg("ST", FReg, 0);

			InsertType("BYTE", 1);
			InsertType("WORD", 2);
			InsertType("DWORD", 4);
			InsertType("QWORD", 8);
			InsertType("TBYTE", 10);
			
		(* Global variables *)
			pc := 0; Target := {}
	END Init;
	
	PROCEDURE Close;
	BEGIN root.right := NIL;
	END Close;
	
	PROCEDURE InsertTarget(IN name: ARRAY OF CHAR; flag: SET);
	BEGIN
		TargetTab[TargetCount].name := name;
		TargetTab[TargetCount].flag := flag;
		INC(TargetCount);
	END InsertTarget;
	
	PROCEDURE BodyInit;
		VAR i: INTEGER; f: Files.File; r: Files.Rider;
	BEGIN
		OPM.LogWLn; OPM.LogWStr("  using OP2-ASM add-on / prk");
		NEW(root); root.left := NIL; root.right := NIL; root.next := NIL;
		f := Files.Old(FileName);
		IF f # NIL THEN
			Files.Set(r, f, 0);
			Files.ReadInt(r, InstrTabLen);  NEW(InstrTab, InstrTabLen);
			FOR i := 0 TO InstrTabLen-1 DO
				Files.ReadString(r, InstrTab[i].name);
				IF InstrTab[i].name # "" THEN
					Files.ReadInt(r, InstrTab[i].start); Files.ReadInt(r, InstrTab[i].end);
					Files.ReadSet(r, InstrTab[i].target)
				END
			END;
			Files.ReadInt(r, OpTabLen);  NEW(OpTab, OpTabLen);
			FOR i:= 0 TO OpTabLen-1 DO
				Files.ReadInt(r, OpTab[i].op[0]); Files.ReadInt(r, OpTab[i].op[1]); Files.ReadInt(r, OpTab[i].op[2]);
				Files.ReadInt(r, OpTab[i].op0); Files.ReadInt(r, OpTab[i].op1);
				Files.ReadInt(r, OpTab[i].opc); Files.ReadInt(r, OpTab[i].reg);
			END;
			Files.Close(f)
		ELSE
			OPM.LogWLn; OPM.LogWStr(FileName); OPM.LogWStr(" not found, ASM not ready")
		END;
		
		SizeTab[0] := 0; SizeTab[1] := 1; SizeTab[2] := 1; SizeTab[3] := 1;
		SizeTab[4] := 1; SizeTab[5] := 2; SizeTab[6] := 4; SizeTab[7] := 4;
		SizeTab[8] := 8; SizeTab[9] := 4; SizeTab[10] := 4; SizeTab[11] := 4;
		SizeTab[12] := 0; SizeTab[13] := 4; SizeTab[14] := 4; SizeTab[15] := 0;
		SizeTab[16] := 8;

		TargetCount := 0;
		InsertTarget("i386", {i386});
		InsertTarget("i486", {i386, i486});
		InsertTarget("Pentium", {i386, i486, Pentium});
		InsertTarget("PentiumPro", {i386, i486, Pentium, PentiumPro});
		InsertTarget("FPU", {FPU});
		InsertTarget("Privileged", {Privileged});
	END BodyInit;
(* ------------------------------------------------------------------- *)
(* Entry points and exported functions *)

	PROCEDURE Assemble*(VAR x: OPT.Node;  exported, inlined: BOOLEAN);
	BEGIN
		export := exported;  inline := inlined;
		IF FirstTime THEN BodyInit; FirstTime := FALSE END;
		Init; 
		first := NIL; last := NIL; NewNode;
		fixlist := NIL;
		Get(sym);
		IF sym = ScLBrace THEN
			Get(sym);
			ParseTarget
		ELSE
			Get(sym); Target := {}
		END;
		IF Target = {} THEN OPM.err(516); Target := {0..31} END;
		WHILE (sym # ScEnd) & (sym # ScUndef) DO
				IF sym = ScLabel THEN ParseLabel END;
				IF sym = ScIdent THEN ParseInstruction END;
				WHILE (sym # ScEnd) & (sym # ScCR) DO
					Get(sym); OPM.err(510)
				END;
				Get(sym)
		END;

		IF OPM.noerr THEN CheckLabels END;	(* check for undefined forward jumps *)
		Close;
		OPB.Construct(Nassembler, first, fixlist); x := first; x.conval := NIL;
	END Assemble;

BEGIN
	FirstTime := TRUE;	(* the module initialisation is delayed to the first call *)

END OPA.


