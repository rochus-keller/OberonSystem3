(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

(* code generator (back end) *)
(* NM, rml, prk *)


MODULE OPC;	(** non-portable *)
	IMPORT OPT, OPL, OPO, OPM, SYSTEM;


	CONST
		(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
		HInt = 16;
		intSet = {SInt..LInt}; realSet = {Real, LReal};

		(* composite structure forms *)
		Basic = 1; StaticArr = 2; SDynArr = 3; DynArr = 4; OpenArr = 5; Record = 6;
		ArraySet = {StaticArr, SDynArr, DynArr, OpenArr};
		
		(* nodes classes *)
		Nvar = 0; Nvarpar = 1; Nconst = 7; Nproc = 9; Ncall = 13; Nret = 32;
		
		(* item base modes (=object modes) *)
		Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7; CProc = 9; IProc = 10; TProc = 13;
		
		(* item modes for Intel i386 (must not overlap item basemodes,  > 13) *)
		Reg = OPO.Reg; Abs = OPO.Abs; RegRel = OPO.RegRel; Coc = OPO.Coc;

		(*SYSTEM ops*)
		adr = 24; cc = 25; bit = 26; lsh = 27; rot = 28; val = 29;
		get8 = 30; get16 = 31; get32 = 32;

		(*SYSTEM function number*)
		getfn = 24; putfn = 25; getrfn = 26; putrfn = 27; sysnewfn = 30; movefn = 31;

		(* procedure flags (conval^.setval) *)
		hasBody = 1; slNeeded = 3; activeObj = 5; locked =6;

		(* record flags (flags) *)	
		safe = 8;

		(* module visibility of objects *)
		internal = 0; external = 1; externalR = 2;

		(* base type and method offset *)
		BaseTypeOffs = -8; MethodOffs = -72;

		(* POINTER TO ARRAY offset *)
		ArrBlkFirstElem = 8;
		ArrBlkLastDim = 12;
		
		(* static link address *)
		StaticLinkAdr = 8;

		(* relations *)
		eql = 9; neq = 10; lss = 11; leq = 12; gtr = 13; geq = 14;
		
		false = 0; true = 1; nil = 0;

		(* conditions: the same as opcodes je, jne,....  *)
		EQ = OPL.je; NE = OPL.jne; LT = OPL.jl; LE = OPL.jle; GT = OPL.jg; GE = OPL.jge; 
		AB = OPL.ja; AE = OPL.jae; BL = OPL.jb; BE = OPL.jbe;
		CS = OPL.jc; CC = OPL.jnc; always = OPL.jmp; never = -1;

	(* opcode of pseudo RISC processor *)
	(* integer operations *)
	ld = OPL.ld; 	store = OPL.store; 	lea = OPL.lea; 	push = OPL.push; 
	pop = OPL.pop; 	ldProc = OPL.ldProc;	ldXProc = OPL.ldXProc;	ldbdw = OPL.ldbdw; 
	ldwdw = OPL.ldwdw; 	ldbw = OPL.ldbw; (* sign extended load; b: byte; w: word; dw: dword *)
	ldbdwu = OPL.ldbdwu;	ldwdwu = OPL.ldwdwu;	ldbwu = OPL.ldbwu; (* zero extended load *)
	putReg = OPL.putReg;	getReg = OPL.getReg;
	add = OPL.add; 	sub = OPL.sub; 	mul = OPL.mul; 	div = OPL.div; 
	mod = OPL.mod ; 	neg = OPL.neg; 	abs = OPL.abs;	cmp = OPL.cmp; 
	je = OPL.je; 	jne = OPL.jne; 	jl = OPL.jl; 	jle = OPL.jle; 
	jg = OPL.jg; 	jge = OPL.jge;	ja = OPL.ja; 	jae = OPL.jae; 
	jb = OPL.jb; 	jbe = OPL.jbe;	jc = OPL.jc; 	jnc = OPL.jnc; 
	jmp = OPL.jmp; 	jmpReg = OPL.jmpReg;	sete = OPL.sete; 	setne = OPL.setne; 
	setl = OPL.setl; 	setle = OPL.setle; 	setg = OPL.setg; 	setge = OPL.setge;
	seta = OPL.seta; 	setae = OPL.setae; 	setb = OPL.setb; 	setbe = OPL.setbe;
	setc = OPL.setc; 	setnc = OPL.setnc;	te = OPL.te; 	tne = OPL.tne; 
	tle = OPL.tle;	ta = OPL.ta; 	tae = OPL.tae;	to =  OPL.to;
	trap = OPL.trap;	or = OPL.or; 	xor = OPL.xor; 
	and = OPL.and; 	not = OPL.not;	bt = OPL.bt; 	btr = OPL.btr; 	test = OPL.test;
	bts = OPL.bts;	call = OPL.call; 	callReg = OPL.callReg; 	xcall = OPL.xcall; 
	ret = OPL.ret; 	enter = OPL.enter; 	leave = OPL.leave;	sal = OPL.sal; 
	sar = OPL.sar ; 	shr = OPL.shr; 	rol = OPL.rol;	cld = OPL.cld; 
	repMovs = OPL.repMovs; 	cmpString = OPL.cmpString;
	cli = OPL.cli;	sti = OPL.sti;	in = OPL.in;	out = OPL.out;
	assembler = OPL.assembler;
	clear = OPL.clear;
	std = OPL.std;

	(* floating point operations *)
	fload = OPL.fload; 	fstore = OPL.fstore; 	fist = OPL.fist; 	fild = OPL.fild;
	fadd = OPL.fadd; 	fsub = OPL.fsub; 	fmul = OPL.fmul;	fdiv = OPL.fdiv; 
	fabs = OPL.fabs; 	fchs = OPL.fchs; 	fcmp = OPL.fcmp;

	(* special *)
	phi = OPL.phi; 	pushReg = OPL.pushReg;	popReg = OPL.popReg; 	case = OPL.case;
	entier = OPL.entier;	short = OPL.short;	label = OPL.label;

	newStat = OPL.newStat;

	(* predefined registers of the pseudo RISC machine *)
	ESP = OPL.RiscESP; FP = OPL.RiscFP; none = OPL.none;
	
	(* scale factor *)
	noScale = OPO.noScale;
	
	(* sysflag *) (* ejz *)
	notag = 1; stdcall = 2; cdecl = 3; delegate = 5;

	TYPE 
		Item* = RECORD
			mode*, mnolev*, scale*: SHORTINT;	(* mnolev < 0 -> mno (module number) = -mnolev *)
			typ*: OPT.Struct; node*: OPT.Node;
			adr*, offs*, inx*, descReg*, descOffs*: LONGINT
		END;
(*
	mode:	item mode
	mnolev: 	module number or nesting level
	typ: 	type of item
	node: 	link to node -> used for OPL.AbsAccess and alias analysis
	adr, offs, inx:	see below
	descReg: 	descriptor register (dynamic array)
	descOffs: 	descriptor offset (dynamic array)
*)

(* Items: 

	the fields mnolev and typ are set for all modes in OPV.
	mnolev is not valid for non-allocated constants.

Intel i386 :
   mode  | adr    offs     inx    descReg
---------------------------------
 1 Var   | vadr	(adr will be stored in obj.linkadr too. 
         |	Local variables)
 2 VarPar| vadr   	
 3 Con   | val    	(adr: Boolean, Byte..LInt)
         | adr    len(of string)
         | adr   	(LReal, Real)
 6 LProc | adr            
 7 XProc | pno    LinkAdr 	(LinkAdr will be stored in obj.linkadr too)
 9 CProc |     	
10 IProc | adr    LinkAdr	(not implemented yet)
13 TProc | TagAdr Off
         |
15 Reg   | reg          
         | proc                    self   (type.sysflag=delegate)
16 Abs   | vadr            reg	(inx = none: no index register)
17 RegRel| reg    off      reg	(inx = none: no index register)
18 Coc   | CC     Tjmp     Fjmp
*)

		Label* = LONGINT;
		
	CONST
		Nil* = -1;	  (* label nil *)
		BUG = 40;      (* Trap code for Bugs in OP2 *)

	VAR
	level*: SHORTINT; 	(* nesting level *)
	pc*: INTEGER; 	(* pc of pseudo RISC machine *)
	True, False, Stack: Item; 	(* constant items True, False and Stack *)
	ebp: Item; 	(* base pointer item *)
	formTab: ARRAY 16 OF SHORTINT; 
	CCtab: ARRAY 2, (geq-eql+1) OF INTEGER;	(* condition code table, CCtab[0] = integer; CCtab[1] = char *)
	InvCCtab: ARRAY (CC-EQ) DIV 32 + 1 OF INTEGER; (* inverted conditon code table*)
	lastTD: Item;	(*optimizing the method call: TD of the self parameter. Set by Parameter ParRecord, used by call. only set whe a AVR Record is pushed*)
	delegateType: OPT.Struct;	(*delegate type*)

	PROCEDURE DumpItem(VAR x: Item);
	BEGIN
		OPM.LogWNum(x.mode, 2); OPM.LogW("/");
		OPM.LogWNum(x.mnolev, 1); OPM.LogW("/");
		OPM.LogWNum(x.adr, 1); OPM.LogW("/");
		OPM.LogWNum(x.offs, 3); OPM.LogW("/");
		OPM.LogWNum(x.inx, 1); OPM.LogW("/");
		OPM.LogWNum(x.descReg, 1); OPM.LogW("/");
		OPM.LogWNum(x.descOffs, 3); OPM.LogW("/");
		OPM.LogWNum(x.scale, 1); OPM.LogW("/");
	END DumpItem;
	
	PROCEDURE Init*;
	BEGIN
		pc := 0; level := 0
	END Init;

	PROCEDURE IncReg (pReg: LONGINT);
	(* increments field used in the pseudo code where reg was first used *)
	BEGIN
		IF pReg >= 0 THEN INC (OPL.Instr[pReg].used) END (* pReg < 0: special registers  *)
	END IncReg;
	
	PROCEDURE InitInstr (op: INTEGER; mode, form: SHORTINT; node: OPT.Node);
	(* initialize the pseudo instruction at position pc *)
	VAR i: LONGINT;  instr: OPL.InstructionTable;
	BEGIN
		IF pc >= LEN(OPL.Instr) THEN
			NEW(instr, LEN(OPL.Instr)*2);
			FOR i := 0 TO LEN(OPL.Instr)-1 DO instr[i] := OPL.Instr[i] END;
			OPL.Instr := instr
		END;
		ASSERT ((mode >= 0) & (mode <= 3));
		ASSERT ((op MOD 32 = 0) & (op > 0));
		OPL.Instr [pc].op := op + formTab[form] + mode * 8; OPL.Instr [pc].node := node;
		OPL.Instr [pc].src1 := none; OPL.Instr [pc].src2 := none; OPL.Instr [pc].inx := none;
		OPL.Instr [pc].dest := pc; OPL.Instr [pc].used := 0; OPL.Instr [pc].hint := OPL.noHint;
		OPL.Instr [pc].pc := OPL.Nil; OPL.Instr [pc].reg := OPL.Nil; OPL.Instr [pc].abs := FALSE
	END InitInstr;

	PROCEDURE NewStat* (textPos: LONGINT);
	BEGIN
		InitInstr (newStat, 0, 0, NIL);
		OPL.Instr [pc].src1 := textPos;
		OPM.errpos := textPos;
		INC (pc)
	END NewStat;
	
	PROCEDURE GenLoad (op: INTEGER; VAR z, x: Item);
	(* loads x into register; used for: ld, ldbdw, ldwdw, ldbw, lea, fload, fild, ldbdwu, ldwdwu, lbdwu *)
	BEGIN
		CASE x.mode OF
			Abs:
				InitInstr (op, OPO.MemReg, x.typ.form, x.node);
				OPL.Instr[pc].src2 := x.adr; OPL.Instr[pc].inx := x.inx; 
				OPL.Instr[pc].scale := x.scale; OPL.Instr[pc].src1 := none;
				IncReg (x.inx)
		  | Var:
				ASSERT (x.mnolev > 0);
				InitInstr (op, OPO.MemReg, x.typ.form, x.node);
				OPL.Instr[pc].src2 := x.adr; OPL.Instr[pc].inx := none;
				OPL.Instr[pc].scale := x.scale;
				OPL.Instr[pc].src1 := FP
		  | Con:
				ASSERT ( (op # lea) & (op # fload) & (op # fild) & (op # pop) );
				ASSERT ( (op < ldbdw) OR (op > ldbwu) ); 
				InitInstr (op, OPO.ImmReg, x.typ.form, x.node);
				OPL.Instr[pc].src2 := x.adr
		  | Reg:
				ASSERT ((op # lea) & (op # fild));
				InitInstr (op, OPO.RegReg, x.typ.form, x.node);
				OPL.Instr[pc].src1 := x.adr;
				IF op # pop THEN IncReg (x.adr) END
		  | RegRel:
				InitInstr (op, OPO.MemReg, x.typ.form, x.node);
				OPL.Instr[pc].src1 := x.adr; OPL.Instr[pc].src2 := x.offs; OPL.Instr[pc].inx := x.inx;
				OPL.Instr[pc].scale := x.scale;
				IncReg (x.adr); IncReg (x.inx)
		  | Coc:
				MoveCoc (z, x); RETURN	(* don't change pc and z.adr *)
		ELSE HALT (BUG)
		END;
		z.adr := pc; z.mode := Reg;
		INC (pc)
	END GenLoad;
					
	PROCEDURE GenPush (VAR x: Item); 
	(* push x *)
		VAR dummy: Item;
	BEGIN
		ASSERT ((x.mode = Reg) OR (x.mode = Con), 100);
		dummy.node := NIL;
		GenLoad (push, dummy, x)
	END GenPush;

	PROCEDURE GenPop (VAR x: Item); 
	(* pop x *)
		VAR dummy: Item;
	BEGIN
		(* x.typ is initialized by the caller *)
		dummy.node := NIL;
		x.mode := Reg; x.adr := pc; x.node := NIL;
		GenLoad (pop, dummy, x);
	END GenPop;

	PROCEDURE GenLoadProc (op: INTEGER; VAR z: Item; val: LONGINT; node: OPT.Node);
	(* ldProc, ldXProc *)
	BEGIN
		InitInstr (op, OPO.ImmReg, LInt, node);
		z.mode := Reg; z.typ := OPT.ptrtyp; z.adr := pc; 
		OPL.Instr [pc].src1 := val;
		INC (pc)
	END GenLoadProc;
	
	PROCEDURE GenStore (op: INTEGER; VAR z, x: Item); 
	(* z := x; used for: store, fstore, fist *)
	BEGIN
		ASSERT (x.mode = Reg);
		CASE z.mode OF
			Abs:
				InitInstr (op, OPO.RegMem, z.typ.form, z.node); OPL.Instr[pc].dest := x.adr;
				OPL.Instr[pc].src2 := z.adr; OPL.Instr[pc].inx := z.inx; OPL.Instr[pc].scale := z.scale;
				OPL.Instr[pc].src1 := none;
				IncReg (z.inx)
		  | Var:
				ASSERT (z.mnolev > 0);
				InitInstr (op, OPO.RegMem, z.typ.form, z.node); OPL.Instr[pc].dest := x.adr;
				OPL.Instr[pc].src2 := z.adr; OPL.Instr[pc].inx := none;
				OPL.Instr[pc].src1 := FP
		  | RegRel:
				InitInstr (op, OPO.RegMem, z.typ.form, z.node); OPL.Instr[pc].dest := x.adr;
				OPL.Instr[pc].src1 := z.adr; OPL.Instr[pc].src2 := z.offs; OPL.Instr[pc].inx := z.inx;
				OPL.Instr[pc].scale := z.scale;
				IncReg (z.adr); IncReg (z.inx)
		ELSE HALT (BUG)
		END;
		IF op # getReg THEN IncReg (x.adr) END;
		INC (pc)
	END GenStore;

	PROCEDURE GenPopReg (hint, form: SHORTINT); 
	(* popReg *)
	BEGIN
		IF hint = OPL.noHint THEN InitInstr (popReg, 0, 0, NIL)
		ELSE
			InitInstr (popReg, OPO.RegReg, form, NIL);
			OPL.Instr [pc].hint := hint;
		END;
		INC (pc)
	END GenPopReg;

	PROCEDURE Gen0 (op: INTEGER);
	(* used for: cld, pushReg, label *)
	BEGIN
		InitInstr (op, 0, 0, NIL);
		INC (pc)
	END Gen0;

	PROCEDURE Gen1 (op: INTEGER; adr: LONGINT; node: OPT.Node);
	(* used for: je, jne, jl, jle, jg, jge, ja, jae, jb, jbe, jc, jnc, jmp, jmpReg, trap, te, tne, ta, tae, to, ret, enter, leave *)
	BEGIN
		IF op = jmpReg THEN 
			InitInstr (op, OPO.RegReg, LInt, node); IncReg (adr)
		ELSE InitInstr (op, 0, 0, node)
		END;
		OPL.Instr[pc].src2 := adr;
		INC (pc)
	END Gen1;

	PROCEDURE Gen2 (op: INTEGER; VAR z, x: Item);
	(* z := op (x); used for: neg, not, abs, fabs, fchs, short, entier *)
	BEGIN
		ASSERT (x.mode = Reg);
		InitInstr (op, OPO.RegReg, x.typ.form, x.node);
		OPL.Instr[pc].src1 := x.adr;
		IncReg (x.adr);
		z.adr := pc; z.mode := Reg;
		INC (pc)
	END Gen2;
	
	PROCEDURE Gen3 (op: INTEGER; VAR z, x, y: Item);
	(* z := op (x, y); used for: add, sub, mul, div, mod, or, xor, and, btr, bts, sal,sar, shr, rol, fadd, fsub, fmul, fdiv *)
	BEGIN
		IF y.mode = Con THEN InitInstr (op, OPO.ImmReg, x.typ.form, x.node)
		ELSE 
			InitInstr (op, OPO.RegReg, x.typ.form, x.node); IncReg (y.adr)
		END;
		OPL.Instr[pc].src1 := x.adr; OPL.Instr[pc].src2 := y.adr;
		IncReg (x.adr);
		IF (op = div) OR (op = mod) THEN OPL.Instr[x.adr].hint := OPL.tryEAX
		ELSIF (op >= sal) & (op <= rol) & (y.mode # Con) THEN OPL.Instr[y.adr].hint := OPL.useECX
		ELSIF (op = mul) & (x.typ.form = SInt) THEN OPL.Instr [x.adr].hint := OPL.tryEAX
		END;
		z.adr := pc; z.mode := Reg;
		INC (pc)
	END Gen3;

	PROCEDURE PushRegs*;
	(* pushReg *)
	BEGIN
		Gen0 (pushReg);
	END PushRegs;

	PROCEDURE GenCall (op: INTEGER; adr, parSize: LONGINT; node: OPT.Node);
	(* used for call, xcall, callReg *)
	BEGIN
		IF op = callReg THEN
			InitInstr (op, OPO.RegReg, LInt, node); IncReg (adr)
		ELSE
			InitInstr (op, 0, 0, node)
		END;
		OPL.Instr [pc].src1 := parSize; OPL.Instr[pc].src2 := adr;
		INC (pc)
	END GenCall;
	
	PROCEDURE GenFlags (op: INTEGER; VAR x, y: Item);
	(* x op y; used for: cmp, bt, fcmp, cmpString *)
	BEGIN
		ASSERT((x.mode=Reg)&(y.mode IN {Reg, Con}), 100);
		IF y.mode = Con THEN InitInstr (op, OPO.ImmReg, x.typ.form, x.node)
		ELSE
			InitInstr (op, OPO.RegReg, x.typ.form, x.node); IncReg (y.adr)
		END;
		OPL.Instr[pc].src1 := x.adr; OPL.Instr[pc].src2 := y.adr;
		IncReg (x.adr);
		INC (pc)
	END GenFlags;
	
	PROCEDURE GenSetC (op: INTEGER; VAR z: Item); (* set condition *)
	(* used for: sete, setne, setl, setle, setg, setge, seta, setae, setb, setbe, setc, setne *)
	BEGIN
		InitInstr (op, OPO.RegReg, SInt, z.node);
		z.adr := pc; z.mode := Reg;
		INC (pc)
	END GenSetC;

	PROCEDURE GenRepMovs (VAR z, x, nofElem: Item; moveSize: SHORTINT;  reverse: BOOLEAN); (* z := x; block copy *)
	(* used for: repMovs *)
	BEGIN
		InitInstr (repMovs, 0, 0, NIL);
		OPL.Instr [pc].dest := z.adr; (* destination address *)
		OPL.Instr [pc].src1 := x.adr; (* source address *)
		OPL.Instr [pc].src2 := nofElem.adr; (* nofelements *)
		OPL.Instr [pc].inx := moveSize; (* move size: 8, 16 or 32 bit *)
		IF reverse THEN  OPL.Instr[pc].hint := 1  END;
		INC (pc)
	END GenRepMovs;
	
	PROCEDURE GenPhi (reg0, reg1: LONGINT); 
	(* phi *)
	BEGIN
		InitInstr (phi, 0, 0, NIL);
		OPL.Instr [pc].src1 := reg0; OPL.Instr [pc].src2 := reg1;
		OPL.Instr [reg1].hint := SHORT (-1 - reg0);
		INC (pc)
	END GenPhi;
	
	PROCEDURE  MakeCon* (VAR cons: Item; typ: OPT.Struct; val: LONGINT);
	(* makes a constant item cons *)
	BEGIN
		cons.mode := Con; cons.adr := val; cons.offs := 0; cons.typ := typ; cons.node := NIL
	END MakeCon;

	PROCEDURE SetCC (VAR x: Item; cc: LONGINT); 
	(* set condition code *)
	BEGIN
		x.typ := OPT.booltyp; x.mode := Coc; x.adr := cc; x.offs := Nil; x.inx := Nil; x.node := NIL
	END SetCC;

	PROCEDURE DefLabel* (VAR L: Label);
	BEGIN
		L := pc;
		Gen0 (label)
	END DefLabel;
	
	PROCEDURE FixLinkWith (L, val: Label);
		VAR L1: Label;
	(* -2 - Label = position in the pseudo code *)
	BEGIN
		ASSERT ((L < 0) & (val >= 0));
		L := -2 - L;
		WHILE L # Nil DO
			L1 := -2 - OPL.Instr[L].src2;
			OPL.Instr[L].src2 := val;
			L := L1
		END
	END FixLinkWith;
	
	PROCEDURE FixLink* (L: Label);
		VAR L1: Label;
	(* -2 - Label = position in the pseudo code *)
	BEGIN
		ASSERT (L < 0);
		L := -2 - L;
		IF L # Nil THEN
			REPEAT
				L1 := -2 - OPL.Instr[L].src2;
				OPL.Instr[L].src2 := pc;
				L := L1
			UNTIL L = Nil;
			Gen0 (label)
		END
	END FixLink;
	
	PROCEDURE MergedLinks* (L0, L1: Label): Label;
		VAR L2, L3: Label;
	(* -2 - Label = position in the pseudo code *)
	BEGIN
		L2 := -2 - L0;
		IF L2 # Nil THEN
			LOOP 
				L3 := -2 - OPL.Instr[L2].src2;
				IF L3 = Nil THEN EXIT END;
				L2 := L3
			END;
			OPL.Instr[L2].src2 := L1;
			RETURN L0
		ELSE 
			RETURN L1
		END
	END MergedLinks;

	PROCEDURE Jmp* (VAR loc: Label; node: OPT.Node);
	(* jump ; forward jumps are encoded as -2-pc, where pc is the address of the last jump -> fixup chain *)
		VAR pos: Label;
	BEGIN
		IF loc < 0 THEN (* forward jump *)
			pos := loc; loc := -2-pc;
			Gen1 (jmp, pos, node)
		ELSE (* backward jump *)
			Gen1 (jmp, loc, node)
		END
	END Jmp;

	PROCEDURE^ load (VAR x: Item);
	
	PROCEDURE Jcc* (VAR x: Item; VAR loc: Label; node: OPT.Node); 
	(* conditional jump ; forward jumps are encoded as -2-pc, where pc is the address of the last jump -> fixup chain *)
	BEGIN
		IF x.mode # Coc THEN
			ASSERT (x.typ.form = Bool);
			load (x); GenFlags (cmp, x, True);
			SetCC (x, EQ)
		END;
		IF x.adr # never THEN
			IF loc < 0 THEN (* forward jump *)
				Gen1 (SHORT (x.adr), x.offs, node); (* Tjmp *)
				loc := -2-(pc-1)
			ELSE (* backward jump *)
				Gen1 (SHORT (x.adr), loc, node); FixLinkWith (x.offs, loc)
			END
		ELSIF loc>=0 THEN FixLinkWith (x.offs, loc) (* Fjmp *)
		END;
		FixLink (x.inx) (* Fjmp *)
	END Jcc;	
	
	PROCEDURE Jncc* (VAR x: Item; VAR loc: Label; node: OPT.Node); 
	(* conditional jump on false *)
		VAR j: INTEGER;
	BEGIN
		IF x.mode # Coc THEN
			ASSERT (x.typ.form = Bool);
			load (x); GenFlags (cmp, x, True);
			SetCC (x, EQ)
		END;
		IF x.adr # always THEN
			IF x.adr = never THEN j := always ELSE j := InvCCtab [(x.adr - EQ) DIV 32] END;		(* jncc bug *)
			IF loc < 0 THEN (* forward jump *)
				Gen1 (j, x.inx, node); (* Fjmp *)
				loc := -2-(pc-1)
			ELSE (* backward jump *)
				Gen1 (j, loc, node);
				FixLinkWith (x.inx, loc) (* Fjmp *)
			END;
		ELSIF loc>=0 THEN FixLinkWith (x.inx, loc) (* Fjmp *)
		END;
		FixLink (x.offs) (* Tjmp *)
	END Jncc;
				
	PROCEDURE CompleteSL (VAR x: Item); 
	(* complete static link *)
		VAR n: INTEGER; sl: Item;
	BEGIN
		IF x.mnolev > 0 THEN
			n := level - x.mnolev;
			IF (x.mode IN {Var, VarPar}) & (n > 0) THEN
				sl.mode := RegRel; sl.typ := OPT.ptrtyp; sl.mnolev := level; sl.inx := none; 
				sl.adr := FP; sl.offs := StaticLinkAdr; sl.node := NIL;
				IF n > 1 THEN
					load (sl); sl.mode := RegRel; sl.offs := StaticLinkAdr;
					WHILE n > 2 DO
						load (sl); sl.mode := RegRel; sl.offs := StaticLinkAdr;
						DEC (n)
					END
				END;
				load (sl);
				x.mode := RegRel; x.offs := x.adr; x.adr := sl.adr; x.inx := none
			END
		END
 	END CompleteSL;			

	PROCEDURE loadAdr (VAR x: Item); 
	(* load address into a register *)
		VAR typ: OPT.Struct;
	BEGIN
		ASSERT (x.mode IN {Abs, Var, VarPar, RegRel});
		typ := x.typ;
		IF (x.mode = VarPar) OR ((x.mode = Var)&(typ.comp IN {OpenArr, SDynArr})) THEN	(*indirect*)
			CompleteSL (x);
			x.typ := OPT.ptrtyp;
			IF x.mode = VarPar THEN (* x is from the own procedure *)
				x.mode := RegRel; x.offs := x.adr; x.adr := FP; x.inx := none
			END;
			GenLoad (ld, x, x)
		ELSE (* Abs, Var, RegRel *)
			CompleteSL (x);
			x.typ := OPT.ptrtyp;
			GenLoad (lea, x, x)
		END;
		x.offs := 0; x.inx := none; x.scale := noScale; x.typ := typ
		(*Postcodition: x.mode = Reg*)
	END loadAdr;

	PROCEDURE loadf (VAR x: Item); 
	(* load floating point *)
	BEGIN
		IF x.mode # Reg THEN
			IF x.mode = VarPar THEN
				loadAdr (x); x.mode := RegRel
			ELSE CompleteSL (x)
			END;
			GenLoad (fload, x, x)
		END
	END loadf;
	
	PROCEDURE load (VAR x: Item);
	VAR y: Item;
	BEGIN
		IF x.mode # Reg THEN
			IF x.mode = VarPar THEN
				loadAdr (x); x.mode := RegRel
			ELSE CompleteSL (x)
			END;
			IF (x.typ.form = ProcTyp) & (x.typ.sysflag = delegate) THEN	(*procedures loaded through OPC.Procedure*)
				NextWord(y, x);
				GenLoad(ld, x, x);
				GenLoad(ld, y, y);
				x.descReg := y.adr
			ELSE
				GenLoad (ld, x, x)
			END
		END
	END load;
	
	PROCEDURE NextWord(VAR z: Item; y: Item);	(* z := 4[y] *)
	BEGIN  z := y;
		CASE z.mode OF	Reg:  z.adr := y.offs	| Var, Abs: INC(z.adr, 4)	| RegRel: INC(z.offs, 4) 	END;
	END NextWord;
	
	PROCEDURE DeRef* (VAR x: Item);
		VAR btyp: OPT.Struct;
	BEGIN
		btyp := x.typ.BaseTyp;
		load (x);
		x.mode := RegRel; x.offs := 0; x.inx := none; x.scale := noScale;
		IF btyp#NIL THEN
			x.typ := btyp;
			IF btyp.comp=OpenArr THEN 	(*compatibility, point to the first elem in array*)
				x.offs := ArrBlkFirstElem + 8 + 8*((1+btyp.n) DIV 2);
				x.descReg := x.adr; x.descOffs := ArrBlkLastDim + 4*btyp.n
			ELSIF btyp.comp=StaticArr THEN 	(*compatibility, point to the first elem in array*)
				x.offs := ArrBlkFirstElem + 8
			ELSIF btyp.comp = DynArr THEN	(* do nothing! Deref on demand*)
			END
		END
	END DeRef;

	PROCEDURE GetTdAdr* (VAR typ: OPT.Struct; VAR tag: Item);
	(* returns the typedescriptor address (absolute address) *)
	BEGIN
		ASSERT (typ # NIL);
		IF typ.tdadr = OPM.TDAdrUndef THEN OPL.AllocTypDesc(typ) END;
		tag.mode := Abs; tag.mnolev := typ.mno; tag.typ := OPT.ptrtyp; tag.inx := none; tag.adr := 0; tag.node := NIL;
		tag.adr := typ.tdadr
	END GetTdAdr;

	PROCEDURE ^ Mul* (VAR z, x, y: Item; f: INTEGER); (* z := x * y *)

	PROCEDURE TypeTest* (VAR x: Item; testtyp: OPT.Struct; guard, equal, varRec: BOOLEAN);
	(*
		equal = TRUE: the two types must be the same
		guard = TRUE: trap is generated if test fails
		equal, guard = FALSE: only condition codes are set
	*)
		VAR testTag, t0, t1, z: Item;
	BEGIN
		ASSERT (testtyp # NIL);
		IF ~guard OR (OPM.typchk IN OPM.options) THEN
			z := x;
			IF varRec THEN (* type descriptor is on the stack *)
				CompleteSL (z);
				IF z.mode IN {Var, VarPar} THEN
					INC (z.adr, 4); z.mode := Var  (* type descriptor is on the stack (hidden parameter) *)
				ELSE
					ASSERT (z.mode = RegRel);
					INC (z.offs, 4)
				END
			ELSE (* pointer *)
				IF testtyp.form = Pointer THEN
					testtyp := testtyp.BaseTyp;
					DeRef (z)
				END;
				z.offs := -4;
				IF OPM.TDMask # 0 THEN
					t1 := z; load(t1);
					MakeCon(t0, OPT.linttyp, OPM.TDMask);
					Gen3(and, z, t1, t0);
				END;
			END;
			IF ~equal THEN
				DeRef (z);
				z.offs := z.offs + BaseTypeOffs - 4 * testtyp.extlev
			END;
			load (z);
			GetTdAdr (testtyp, testTag); load (testTag);
			GenFlags (cmp, z, testTag);
			IF equal THEN Gen1 (tne, OPL.EqualGuardTrap, NIL)
			ELSIF guard THEN Gen1 (tne, OPL.GuardTrap, NIL)
			ELSE SetCC (x, EQ)
			END
		END
	END TypeTest;

	PROCEDURE Procedure* (VAR proc: Item; n: OPT.Node);
		VAR obj: OPT.Object; index: LONGINT;
	BEGIN
		obj := n.obj;
		proc.mode := obj.mode; proc.node := n; proc.mnolev := obj.mnolev; proc.inx := none; 
		IF ~ (proc.mode IN {TProc, Typ}) THEN (* external, local procedure *)
			IF (proc.mode IN {XProc}) & (proc.mnolev < 0) & (obj.adr DIV 10000H = 0) THEN 
				(* imported procedure and no link entry yet *)
				OPL.NewLink (-obj.mnolev, obj.adr, index);
				obj.adr := index * 10000H + obj.adr (* obj.adr = link index * 10000H + entry number *)
			END;
			proc.adr := obj.adr 
		ELSE (* proc.mode = TProc *)
			proc.offs := MethodOffs - 4 * (obj.adr DIV 10000H);
		END
	END Procedure;
	
	PROCEDURE CheckOverflow (VAR x: Item);
	BEGIN
		IF (OPM.ovflchk IN OPM.options) THEN Gen1 (to, OPL.OverflowTrap, NIL) END
	END CheckOverflow;
			
	PROCEDURE CheckIntRange (VAR x: Item; form: SHORTINT);
	BEGIN
	END CheckIntRange;

	PROCEDURE CheckRealRange (VAR x: Item; form: SHORTINT);
	BEGIN
	END CheckRealRange;

	PROCEDURE CheckIndex (VAR index, len: Item);
	BEGIN
		IF (index.mode=Con)&(len.mode#Con) THEN	(*reversed check*)
			IF (len.mode#Reg) THEN load(len) END;
			GenFlags (cmp, len, index);
			Gen1 (tle, OPL.RangeTrap, NIL)
		ELSE
			IF (index.mode#Reg) THEN load(index) END;
			IF (len.mode#Con) THEN load(len) END;
			GenFlags (cmp, index, len);
			Gen1 (tae, OPL.RangeTrap, NIL)
		END;
	END CheckIndex;
	
	PROCEDURE ChangeType (VAR item: Item; form: SHORTINT);
	BEGIN
		CASE form OF
			Byte: item.typ:= OPT.bytetyp
		  | Bool: item.typ:= OPT.booltyp
		  | Char: item.typ:= OPT.chartyp
		  | SInt: item.typ:= OPT.sinttyp
		  | Int: item.typ:= OPT.inttyp
		  | LInt: item.typ:= OPT.linttyp
		  | Real: item.typ:= OPT.realtyp
		  | LReal: item.typ:= OPT.lrltyp
		  | Set: item.typ:= OPT.settyp
		  | Pointer: item.typ:= OPT.ptrtyp
		  | ProcTyp: item.typ:= OPT.notyp
		ELSE HALT (BUG)
		END
	END ChangeType;
	
	PROCEDURE SetElem* (VAR z, x: Item); (* z := {x} *)
	BEGIN
		MakeCon (z, OPT.settyp, 0);
		load (z);
		IF x.typ.form # LInt THEN Convert (x, LInt)
		ELSE load (x)
		END;
		Gen3 (bts, z, z, x)
	END SetElem;

	PROCEDURE Convert* (VAR x: Item; form: SHORTINT);
		VAR 
			t: Item; 
			xform: SHORTINT;

		PROCEDURE IntToInt (VAR z, x: Item; xform, zform: SHORTINT);
		(* integer to integer convertion *)
		BEGIN
			ASSERT ((xform IN intSet) & (zform IN intSet) & (x.typ.form IN intSet) & (z.typ.form IN intSet));
			IF xform < zform THEN (* smaller to bigger *)
				IF x.mode = VarPar THEN
					loadAdr (x); x.mode := RegRel;
				ELSE CompleteSL (x)
				END;
				ChangeType (x, zform);
				IF x.mode # Con THEN															(* const conversion *)
					IF zform = Int THEN GenLoad (ldbw, z, x)
					ELSIF xform = Int THEN GenLoad (ldwdw, z, x)
					ELSE GenLoad (ldbdw, z, x)
					END
				ELSE z := x
				END
			ELSE (* bigger to smaller *)
				IF x.mode = Reg THEN
					ChangeType (x, zform);
					Gen2 (short, z, x)
				END;
				CheckIntRange (x, zform)
			END
			(* z.typ will be changed by Convert *)
		END IntToInt;
		
		PROCEDURE IntToReal (VAR z, x: Item; xform, zform: SHORTINT);
		(* integer to real convertion *)
			VAR  temp, cons: Item;
		BEGIN
			IF x.mode = VarPar THEN
				loadAdr (x); x.mode := RegRel;
			ELSE CompleteSL (x)
			END;
			ChangeType (x, LInt);
			IF xform = SInt THEN GenLoad (ldbdw, x, x)
			ELSIF xform = Int THEN GenLoad (ldwdw, x, x)
			ELSE load (x)
			END;
			GenPush (x); (* store x on the stack as a temporary variable *)
			temp.mode := RegRel; temp.typ := OPT.linttyp; 
			temp.adr := ESP; temp.offs := 0; temp.inx := none; temp.node := NIL;
			ChangeType (z, zform);
			ChangeType (temp, zform);
			GenLoad (fild, z, temp);
			MakeCon (cons, OPT.linttyp, 4);
			temp := Stack; Gen3 (add, temp, Stack, cons) (* free temporary variable space *)
			(* z.typ will be changed by Convert *)
		END IntToReal;
		
		PROCEDURE IntToCharByte (VAR z, x: Item; form: SHORTINT);
		BEGIN
			IF (x.typ.form # SInt) & (x.mode = Reg) THEN
				ChangeType (x, form);
				Gen2 (short, z, x)
			END;
			CheckIntRange (x, form)
			(* z.typ will be changed by Convert *)
		END IntToCharByte;
		
		PROCEDURE RealToReal (VAR z, x: Item; xform, zform: SHORTINT);
		(* real to real convertion *)
		BEGIN
			IF xform < zform THEN (* smaller to bigger *)
				z := x; loadf (z);
			ELSE (* bigger to smaller *)
				z := x; loadf (z);
				CheckRealRange (x, Real)
			END
			(* z.typ will be changed by Convert *)
		END RealToReal;
		
		PROCEDURE RealToInt (VAR z, x: Item; xform, zform: SHORTINT);
		(* real to integer convertion *)
		BEGIN
			loadf (x); ChangeType (x, LInt);
			Gen2 (entier, z, x)
			(* z.typ will be changed by Convert *) 
		END RealToInt;
		
		PROCEDURE CharToInt (VAR z, x: Item; zform: SHORTINT);
		(* character to integer convertion *)
		BEGIN
			IF x.mode = VarPar THEN
				loadAdr (x); x.mode := RegRel
			ELSE CompleteSL (x)
			END;
			ChangeType (x, zform);
			IF zform = Int THEN GenLoad (ldbwu, z, x)
			ELSIF zform = LInt THEN GenLoad (ldbdwu, z, x)
			ELSE (* ok, char or byte to shortint *)
			END
			(* z.typ will be changed by Convert *)
		END CharToInt;
	
		PROCEDURE ByteToInt (VAR z, x: Item; zform: SHORTINT);
		(* byte to integer convertion *)
		BEGIN
			IF x.mode = VarPar THEN
				loadAdr (x); x.mode := RegRel
			ELSE CompleteSL (x)
			END;
			ChangeType (x, zform);
			IF zform = Int THEN GenLoad (ldbw, z, x)
			ELSIF zform = LInt THEN GenLoad (ldbdw, z, x)
			ELSE (* ok, char or byte to shortint *)
			END
			(* z.typ will be changed by convert *)
		END ByteToInt;
		
	BEGIN (* Convert *)
		IF x.mode = Coc THEN
			t := x; MoveCoc (x, t) 
		END;
		t := x; xform := x.typ.form;
		IF xform IN intSet THEN
			IF form IN intSet THEN IntToInt (x, t, xform, form)
			ELSIF form IN realSet THEN IntToReal (x, t, xform, form)
			ELSIF form IN {Char, Byte} THEN IntToCharByte (x, t, form)
			ELSE HALT (BUG)
			END
		ELSIF xform IN realSet THEN
			IF form IN realSet THEN RealToReal (x, t, xform, form)
			ELSIF form = LInt THEN RealToInt (x, t, xform, form)
			ELSIF form IN {Int, SInt} THEN
				RealToInt (x, t, xform, form); ChangeType (x, LInt); t := x; IntToInt (x, t, LInt, form)
			ELSIF form IN {Char, Byte} THEN
				RealToInt (x, t, xform, LInt); ChangeType (x, LInt); t := x; IntToCharByte (x, t, form)
			ELSE HALT (BUG)
			END
		ELSIF (xform IN {Byte, Char}) & (form IN {Byte,Char}) THEN (* ok, type is changed by OPV *)
		ELSIF xform = Char THEN
			ASSERT (form IN intSet + realSet);											(* shift error *)
			IF form IN intSet THEN CharToInt (x, t, form)
			ELSE	(* form IN realSet *)
				CharToInt(x, t, LInt); t:=x; IntToReal(x, t, LInt, form)
			END
		ELSIF xform = Byte THEN
			IF form IN intSet THEN ByteToInt (x, t, form)
			ELSIF form IN realSet THEN RealToInt (x, t, xform, form)
			ELSE HALT (BUG)
			END
		ELSIF (form = ProcTyp) & (xform # NoTyp) THEN HALT (BUG)
		END;
		ChangeType (x, form)
	END Convert;

	PROCEDURE Include* (VAR z, x: Item; incl: BOOLEAN); (* INCL / EXCL (z, x) *)
		VAR y,  v: Item;

		PROCEDURE exp2 (x: LONGINT): LONGINT;
		(* returns 2^x *)
			VAR i: LONGINT;
		BEGIN
			ASSERT (x >= 0);
			i := 1;
			WHILE x > 0 DO
				i := i * 2;
				DEC  (x)
			END;
			RETURN i
		END exp2;

	BEGIN
		v := z;
		load (v); y := v;
		IF incl THEN
			IF x.mode = Con THEN
				IF x.adr = OPM.MaxSet THEN x.adr := OPM.MinLInt
				ELSE x.adr := exp2 (x.adr)
				END;
				Gen3 (or, v, y, x)
			ELSE
				IF x.typ.form # LInt THEN Convert (x, LInt) END;
				load (x);
				Gen3 (bts, v, y, x)
			END
		ELSE
			IF x.mode = Con THEN
				IF x.adr = OPM.MaxSet THEN x.adr := OPM.MaxLInt
				ELSE x.adr := -1 - exp2 (x.adr)
				END;
				Gen3 (and, v, y, x)
			ELSE
				IF x.typ.form # LInt THEN Convert (x, LInt) END;
				load (x);
				Gen3 (btr, v, y, x)
			END
		END;
		IF z.mode = VarPar THEN
			loadAdr (z); z.mode := RegRel
		ELSE CompleteSL (z)
		END;
		GenStore (store, z, v)
	END Include;

	PROCEDURE MoveCoc (VAR z, y: Item); (* z := Coc (y) *)
		VAR L: Label; phiItem: Item;
	BEGIN
		ASSERT (y.mode = Coc);
		IF (y.offs = Nil) & (y.inx = Nil) THEN (* no jump links *)
			GenSetC (SHORT (sete + y.adr - EQ), z)
		ELSE
			Jncc (y, y.inx, NIL);
			GenLoad (ld, z, True);
			phiItem := z;
			L := Nil;
			Jmp (L, NIL);
			FixLink (y.inx); (* Fjmp fixup *)
			GenLoad (ld, z, False);
			GenPhi (phiItem.adr, z.adr); (* registers in z and phiItem must be the same when generating Intel code *)
			FixLink (L)
		END
	END MoveCoc;	

	PROCEDURE Relation* (VAR x: Item);
		VAR y: Item;
	BEGIN 
		IF x.mode = Coc THEN 
			y := x; MoveCoc (x, y) 
		END
	END Relation;

	PROCEDURE Cmp* (VAR z, x, y: Item; rel: INTEGER); (* z := cmp (x, y) *)
		VAR xform: INTEGER; s, t: Item;
	BEGIN
		xform := x.typ.form;
		IF (xform = ProcTyp) & (x.typ.sysflag = delegate) OR (y.typ.form = ProcTyp) & (y.typ.sysflag = delegate) THEN
			IF (x.mode = Con) THEN
				y.typ.sysflag := 0; load(y); y.typ.sysflag := delegate;	(*don't load self*)
				GenFlags (cmp, y, x)	(* =/# ==> x&y can be swapped*)
			ELSIF y.mode = Con THEN
				x.typ.sysflag := 0; load(x); x.typ.sysflag := delegate;	(*don't load self*)
				GenFlags (cmp, x, y)
			ELSE
				load(x); load(y);
				GenFlags(cmp, x, y);	(*compare procs*)
				SetCC(z, CCtab[1, rel-eql]);
				Gen1(jne, Nil, NIL);
				IF rel = eql THEN
					z.inx := -2-(pc-1);	(*Fchain*)
				ELSIF rel = neq THEN
					z.offs := -2-(pc-1);	(*Tchain*)
				ELSE HALT(99)
				END;
				s := x; s.adr := s.descReg;	(*compare selfs*)
				t := y; t.adr := t.descReg;
				GenFlags(cmp, s, t);
				RETURN	(*avoid SetCC later*)
			END
		ELSIF xform IN {Byte, Char..LInt, Set, NilTyp, Pointer, ProcTyp} THEN
			load (x);
			IF y.mode # Con THEN load (y) END;
			GenFlags (cmp, x, y)
		ELSIF xform IN realSet THEN
			loadf (y); loadf (x); GenFlags (fcmp, x, y)
		ELSIF xform = Bool THEN (* only eq or neq *)
			load (x);
			IF y.mode = Coc THEN
				z := y; MoveCoc (y, z) 
			ELSIF y.mode # Con THEN load (y)
			END;
			GenFlags (cmp, x, y)
		ELSE (* strings *)
			ASSERT ((xform = String) OR (x.typ.comp IN ArraySet));
			loadAdr (x); loadAdr (y);
			GenFlags (cmpString, x, y);
			xform := String;
		END;
		ASSERT (rel IN {eql, neq, lss, leq, gtr, geq});
		IF xform IN {Char, String, Real, LReal} THEN SetCC (z, CCtab [1, rel-eql])
		ELSE SetCC (z, CCtab [0, rel-eql])
		END;
	END Cmp;

	PROCEDURE In* (VAR z, x, y: Item); (* z := x IN y *)
		VAR t: Item;
	BEGIN
		IF (y.mode # Con) & (y.typ.form # Set) THEN
			t := y; SetElem (y, t)
		ELSE load (y)
		END;
		IF x.mode # Con THEN
			IF x.typ.form # LInt THEN Convert (x, LInt)
			ELSE load (x) 
			END;
			GenFlags (bt, y, x);
			SetCC (z, CS)
		ELSE
			x.adr := SYSTEM.LSH(SYSTEM.VAL(LONGINT, 1), x.adr);  x.typ := OPT.linttyp;
			GenFlags (test, y, x);
			SetCC (z, NE)	(*jump on ZF flag*)
		END
	END In;

	PROCEDURE SetRange* (VAR z, x, y: Item); (* z := {x..y} *)
		VAR t, xShifted, yShifted, maxSet, fullSet: Item; val: LONGINT;
	BEGIN
		z.typ := OPT.settyp;
		MakeCon (fullSet, OPT.linttyp, -1);
		MakeCon (maxSet, OPT.linttyp, OPM.MaxSet);
		IF x.mode = Con THEN
			ASSERT (y.mode # Con);
			load (y);
			maxSet.typ := y.typ; load (maxSet);
			t := y; Gen3 (sub, y, maxSet, t);
			load (fullSet);
			Gen3 (shr, z, fullSet,  y);
			IF x.adr # 0 THEN
				IF x.adr = OPM.MaxSet THEN x.adr := MIN (LONGINT)
				ELSE
					val := 2;
					WHILE x.adr > 1 DO
						val := val*2;
						DEC (x.adr)
					END;
					x.adr := -val
				END;
				t := z; Gen3 (and, z, t, x)
			END
		ELSIF y.mode = Con THEN
			load (x);
			load (fullSet);
			Gen3 (sal, z, fullSet, x);
			IF y.adr # OPM.MaxSet THEN
				IF y.adr = OPM.MaxSet-1 THEN y.adr := MAX (LONGINT)
				ELSE
					val := 2;
					WHILE y.adr > 0 DO
						val := val*2;
						DEC (y.adr)
					END;
					y.adr := val-1
				END;
				t := z; Gen3 (and, z, t, y)
			END
		ELSE (* x, y # constant *)
			load (x);
			t := fullSet; load (t);
			xShifted.typ := OPT.linttyp; xShifted.node := NIL;
			Gen3 (sal, xShifted, t, x);
			load (y);
			maxSet.typ := y.typ; load (maxSet);
			t := y; Gen3 (sub, y, maxSet, t);
			load (fullSet);
			yShifted.typ := OPT.linttyp; yShifted.node := NIL;
			Gen3 (shr, yShifted, fullSet, y);
			Gen3 (and, z, xShifted, yShifted)
		END
	END SetRange;

	PROCEDURE Not* (VAR z, x: Item); (* z := NOT (x) *)
		VAR temp: LONGINT;
	BEGIN
		IF x.mode = Coc THEN
			z := x; z.adr := InvCCtab [(z.adr - EQ) DIV 32];
			temp := z.offs; z.offs := z.inx; z.inx := temp; (* permute Fjmp and Tjmp *)
		ELSE
			load (x);
			GenFlags (cmp, x, False);
			SetCC (z, EQ)
		END
	END Not;
	
	PROCEDURE Neg* (VAR z, x: Item); (* z := -x *)
	BEGIN
		ASSERT ( (x.typ.form = Set) OR (x.typ.form IN intSet) OR (x.typ.form IN realSet) );
		IF x.typ.form = Set THEN 
			load (x); Gen2 (not, z, x)
		ELSIF x.typ.form IN intSet THEN
			load (x); Gen2 (neg, z, x)
		ELSE (* x.typ.form = realSet *)
			loadf (x);  Gen2 (fchs, z, x)
		END
	END Neg;
	
	PROCEDURE AbsVal* (VAR z, x: Item); (* z := ABS (x) *)
	BEGIN
		ASSERT ( (x.typ.form IN intSet) OR (x.typ.form IN realSet) );
		IF x.typ.form IN intSet THEN
			load (x);
			Gen2 (abs, z, x);
			IF x.typ.form IN {Int, LInt} THEN OPL.Instr [pc-1].hint := OPL.useEAX END;
		ELSE (* x.typ.form IN realSet *)
			loadf (x);
			Gen2 (fabs, z, x)
		END
	END AbsVal;
	
	PROCEDURE Cap* (VAR z, x: Item); (* z := CAP (x) *)
		VAR c: Item;
	BEGIN
		MakeCon (c, OPT.chartyp, 5FH);
		load (x);
		Gen3 (and, z, x, c)
	END Cap;
	
	PROCEDURE Odd* (VAR z, x: Item); (* z := ODD (x) *)
		VAR c: Item;
	BEGIN
		MakeCon (c, OPT.sinttyp, 1);
		load (x);
		Gen3 (and, z, x, c)
	END Odd;
	
	PROCEDURE Ash* (VAR z, x, y: Item); (* z := ASH (x, y) *)
		VAR L, Lc: Label; t, phiItem: Item;
	BEGIN
		IF y.mode = Con THEN
			IF x.mode = Con THEN
				MakeCon (z, OPT.linttyp, ASH (x.adr, y.adr));
			ELSIF y.adr > 0 THEN
				load (x); Gen3 (sal, z, x, y) 
			ELSIF y.adr < 0 THEN
				y.adr := ABS (y.adr);
				load (x); Gen3 (sar, z, x, y)
			END
		ELSE
			load (x); load (y); z.typ := OPT.linttyp;
			MakeCon (t, OPT.linttyp, 0);
			GenFlags (cmp, y, t);
			Lc := -2-pc; Gen1 (jl, Nil, NIL);
			Gen3 (sal, z, x, y);
			L := -2-pc; Gen1 (jmp, Nil, NIL); 
			phiItem := z;
			FixLink (Lc);
			Gen2 (neg, t, y);
			Gen3 (sar, z, x, t);
			GenPhi (phiItem.adr, z.adr); (* z and phiItem must be in the same register when generating target code *)
			FixLink (L)
		END
	END Ash;

	PROCEDURE Add* (VAR z, x, y: Item; f: INTEGER); (* z := x + y *)
	BEGIN
		ASSERT ( (f IN realSet) OR (f = Set) OR (f IN intSet) );
		IF f IN realSet THEN
			loadf (x); loadf (y); Gen3 (fadd, z, x, y)
		ELSIF f = Set THEN 
			IF x.mode = Con THEN 
				load (y); Gen3 (or, z, y, x)
			ELSE
				load (x);
				IF y.mode # Con THEN load (y) END;
				Gen3 (or, z, x, y)
			END
		ELSE (* f IN intSet *)
			IF x.mode = Con THEN
				load (y); Gen3 (add, z, y, x)
			ELSE
				load (x);
				IF y.mode # Con THEN load (y) END;
				Gen3 (add, z, x, y)
			END;
			CheckOverflow (z)
		END
	END Add;

	PROCEDURE Sub* (VAR z, x, y: Item; f: INTEGER); (* z := x - y *)
		VAR t: Item;
	BEGIN
		ASSERT ( (f IN realSet) OR (f = Set) OR (f IN intSet) );
		IF f IN realSet THEN
			loadf (x); loadf (y);  Gen3 (fsub, z, x, y)
		ELSIF f = Set THEN 
			load (x);
			IF y.mode # Con THEN
				load (y); Gen2 (not, t, y)
			ELSE
				y.adr := -1- y.adr; t := y
			END;
			z := x; Gen3 (and, z, x, t)
		ELSE (* f IN intSet *)
			load (x);
			IF y.mode # Con THEN load (y) END;
			Gen3 (sub, z, x, y);
			CheckOverflow (z)
		END
	END Sub;
	
	PROCEDURE Mul* (VAR z, x, y: Item; f: INTEGER); (* z := x * y *)
		VAR val, exp: LONGINT; shift: Item;
	BEGIN
		ASSERT ( (f = Set) OR (f IN intSet) OR (f IN realSet) );
		IF f IN realSet THEN
			loadf (x); loadf (y); Gen3 (fmul, z, x, y)
		ELSIF f = Set THEN
			IF x.mode = Con THEN
				load (y); Gen3 (and, z, y, x)
			ELSE
				load (x);
				IF (y.mode # Reg) & (y.mode # Con) THEN load (y) END;
				Gen3 (and, z, x, y)
			END
		ELSE (* f IN intSet *) 
		(*  The shift-left check is necessary because several procedures in OPC call Mul directly. *)
			MakeCon (shift, OPT.linttyp, 0);
			IF x.mode = Con THEN
				val := x.adr; exp := 0;
				ASSERT (val # 0);
				WHILE ~ODD (val) DO 
					val := val DIV 2;
					INC (exp)
				END;
				load (y);
				IF (val = 1) & ~(OPM.ovflchk IN OPM.options) THEN (* shift *)
					IF exp # 0 THEN
						shift.adr := exp; Gen3 (sal, z, y, shift)
					ELSE z := y
					END
				ELSE Gen3 (mul, z, y, x)
				END
			ELSIF y.mode = Con THEN
				val := y.adr; exp := 0;
				ASSERT (val # 0);
				WHILE ~ODD (val) DO
					val := val DIV 2;
					INC (exp)
				END;
				load (x);
				IF (val = 1) & ~(OPM.ovflchk IN OPM.options) THEN (* shift *)
					IF exp # 0 THEN
						shift.adr := exp; Gen3 (sal, z, x, shift)
					ELSE z := x
					END
				ELSE Gen3 (mul, z, x, y)
				END
			ELSE
				load (x); load (y);
				Gen3  (mul, z, x, y)
			END;
			CheckOverflow (z)
		END
	END Mul;
	
	PROCEDURE Div* (VAR z, x, y: Item; f: INTEGER); (* z := x DIV y; z := x / y *)
	BEGIN
		ASSERT ( (f IN realSet) OR (f = Set) OR (f IN intSet) );
		IF f IN realSet THEN
			loadf (x); loadf (y); Gen3 (fdiv, z, x, y)
		ELSIF f = Set THEN
			IF x.mode = Con THEN 
				load (y); Gen3 (xor, z, y, x) 
			ELSE
				load (x);
				IF (y.mode # Reg) & (y.mode # Con) THEN load (y) END;
				Gen3 (xor, z, x, y)
			END
		ELSE (* f IN intSet *) (* front end checks for shift right possibilities *)
			load (x);
			IF y.mode # Con THEN load (y) END;
			Gen3 (div, z, x, y)
			(* no overflow check necessary *)
		END
	END Div;

	PROCEDURE Mod* (VAR z, x, y: Item); (* z := x MOD y *)
	BEGIN 
		load (x);
		IF y.mode # Con THEN load (y) END; (* front end checks for shift left possibilities *)
		Gen3 (mod, z, x, y)
		(* no overflow check necessary *)
	END Mod;

	PROCEDURE CondAnd* (VAR x: Item); (* prepares conditional and *)
		VAR jcc: INTEGER;
	BEGIN
		IF x.mode = Coc THEN jcc := InvCCtab [(x.adr - EQ) DIV 32]
		ELSE (* form = Bool, mode # Con *)
			ASSERT ( (x.typ.form = Bool) & (x.mode # Con) );
			load (x); GenFlags (cmp, x, True);
			SetCC (x, NE);
			jcc := jne
		END;
		Gen1 (jcc, x.inx, NIL); (* ... Fjmp *) 
		x.inx := -2-(pc-1);
		FixLink (x.offs) (* Tjmp here *)
	END CondAnd;

	PROCEDURE And* (VAR z, x, y: Item); (* conditional and *)
	BEGIN
		z := x;
		IF y.mode # Coc THEN
			IF y.mode = Con THEN
				IF y.adr = true THEN SetCC (y, always) 
				ELSE SetCC (y, never) 
				END
			ELSE
				load (y); GenFlags (cmp, y, True); 
				SetCC (y, EQ)
			END
		END;
		IF y.inx # Nil THEN z.inx := MergedLinks (z.inx, y.inx) END; (* merge Fjmp *)
		z.adr := y.adr; z.offs := y.offs (* Tjmp *)
	END And;

	PROCEDURE CondOr* (VAR x: Item); (* prepares conditional or *)
		VAR jcc: INTEGER;
	BEGIN
		IF x.mode = Coc THEN jcc := SHORT (x.adr)
		ELSE (* form = Bool, mode # Con *)
			ASSERT ( (x.typ.form = Bool) & (x.mode # Con) );
			load (x); GenFlags (cmp, x, True);
			SetCC (x, EQ);
			jcc := je
		END;
		Gen1 (jcc, x.offs, NIL); (* ... Tjmp *)
		x.offs := -2-(pc-1);
		FixLink (x.inx) (* Fjmp here *)
	END CondOr;

	PROCEDURE Or* (VAR z, x, y: Item); (* conditional or *)
	BEGIN
		z := x;
		IF y.mode # Coc THEN
			IF y.mode = Con THEN
				IF y.adr = true THEN SetCC (y, always) 
				ELSE SetCC (y, never) 
				END
			ELSE
				load (y); GenFlags (cmp, y, True); 
				SetCC (y, EQ)
			END
		END;
		IF y.offs # Nil THEN z.offs := MergedLinks (x.offs, y.offs) END; (* merge Tjmp *)
		z.adr := y.adr; z.inx := y.inx (* Fjmp *)
	END Or;

	PROCEDURE SYSmop* (VAR z, x: Item; subcl: SHORTINT; typ: OPT.Struct);	
	(* implementation of SYSTEM.ADR, CC, VAL *)
		VAR
			xform, typform: SHORTINT;
			t, const: Item;
	BEGIN
		CASE subcl OF
			adr: loadAdr (z)
		  | cc: z := x; OPM.err (200) (* !!later: not implemented *)
		  | val: 
				xform := x.typ.form; typform := typ.form;
				MakeCon (const, OPT.linttyp, 4);
				IF (xform IN  {Byte, Char, SInt, Int, LInt, Set, Pointer, ProcTyp}) & (typform IN realSet) & (x.mode = Reg) THEN
					(* load (x) *); GenPush (x);
					t.mode := RegRel; t.adr := ESP; t.offs := 0; t.inx := none; t.typ := OPT.realtyp; t.node := NIL;
					GenLoad (fload, z, t);
					t := Stack; Gen3 (add, t, t, const)
				ELSIF (xform IN realSet) & (typform IN {Byte, Char, SInt, Int, LInt, Set, Pointer, ProcTyp}) 
						& (x.mode = Reg) THEN
					t := Stack; Gen3 (sub, t, t, const);
					t.mode := RegRel; t.adr := ESP; t.offs := 0; t.inx := none; t.typ := OPT.realtyp; t.node := NIL;
					loadf (x);
					GenStore (fstore, t, x);
					t.typ := typ; GenLoad (ld, z, t);
					t := Stack; Gen3 (add, t, t, const)
				ELSIF (typform = ProcTyp) & (typ.sysflag = delegate) & (xform # ProcTyp) THEN
					z := x; load(z);
					MakeCon(t, OPT.linttyp, 0); load(t);
					z.descReg := t.adr;
					z.typ := typ
				END;
				IF (z.typ.size # typ.size) & ((x.mode # Con) OR (typ.size > 4)) THEN OPM.err(-304) END;
				z.typ := typ
		  | get8, get16, get32:
				load(z); z.mode := RegRel; z.offs := 0; z.inx := none; z.typ := typ;
				load(z);	(*load value in register, otherwise SYSTEM.VAL might change the size of the memory access *)
			END
	END SYSmop;
	
	PROCEDURE Mem (VAR x: Item); (* x := MEM [x] *)
	BEGIN
		IF x.mode = Con THEN 
			x.mode := Abs; x.inx := none
		ELSE
			load (x); x.mode := RegRel; x.offs := 0; x.inx := none
		END
	END Mem;
	
	PROCEDURE SYSdop* (VAR z, x, y: Item; subcl: SHORTINT);	(* implementation of SYSTEM.BIT, LSH, ROT *)
		VAR t, phiItem: Item; L, Lc: Label;
	BEGIN 
		CASE subcl OF
			bit:
				Mem (x); load (x);
				IF y.mode # Con THEN load (y) END;
				GenFlags (bt, x, y);
				GenSetC (setc, z)
		  | lsh:
				IF y.mode = Con THEN
					IF x.mode = Con THEN
						MakeCon (z, OPT.linttyp, SYSTEM.LSH (x.adr, y.adr))										(* shift error *)
					ELSIF y.adr > 0 THEN
						load (x); Gen3 (sal, z, x, y) 
					ELSIF y.adr < 0 THEN
						y.adr := ABS (y.adr);
						load (x); Gen3 (shr, z, x, y)
					END
				ELSE
					load (x); load (y);
					MakeCon (t, OPT.linttyp, 0);
					GenFlags (cmp, y, t);
					Lc := -2-pc; Gen1 (jl, Nil, NIL);
					Gen3 (sal, z, x, y); 
					phiItem := z;
					L := -2-pc; Gen1 (jmp, Nil, NIL);
					FixLink (Lc);
					Gen2 (neg, t, y);
					Gen3 (shr, z, x, t);
					GenPhi (phiItem.adr, z.adr); (* phiItem, z must have the same register when generating targed code *)
					FixLink (L)
				END
		  | rot:
				IF y.mode = Con  THEN
					IF x.mode = Con THEN
						MakeCon (z, x.typ, 0);
						CASE x.typ.form OF
							Byte, Char, SInt:
								z.adr := SYSTEM.ROT (SYSTEM.VAL (SHORTINT, x.adr), SHORT (y.adr))
						  | Int:
								z.adr := SYSTEM.ROT (SYSTEM.VAL (INTEGER, x.adr), SHORT (y.adr))
						  | LInt:
								z.adr := SYSTEM.ROT ( x.adr, SHORT (y.adr))
						END
					ELSE
						load (x); Gen3 (rol,  z, x, y)
					END
				ELSE
					load (x); load (y);
					Gen3 (rol, z, x, y)
				END
		END
	END SYSdop;
	
	PROCEDURE SYSgetput* (VAR z, x: Item; getfn: BOOLEAN);	(* SYSTEM.GET, SYSTEM.PUT *)
		VAR form: SHORTINT; constAddr: BOOLEAN;					(* GetPut *)
	BEGIN
		IF getfn THEN
			constAddr := x.mode = Con;					(* GetPut *)
			Mem (x); x.typ := z.typ; form := z.typ.form
		ELSE
			constAddr := z.mode = Con;					(* GetPut *)
			Mem (z);
			z.typ := x.typ; form := x.typ.form
		END;
		IF form IN realSet THEN loadf (x)
		ELSE load (x)
		END;
		OPL.Instr [pc-1].abs := constAddr & getfn;			(* if x is the address and a constant, no fixup *)	(* GetPut *)
		IF z.mode = VarPar THEN
			loadAdr (z); z.mode := RegRel
		ELSE CompleteSL (z)
		END;
		IF form IN realSet THEN GenStore (fstore, z, x)
		ELSE GenStore (store, z, x)
		END;
		OPL.Instr [pc-1].abs := constAddr & ~getfn			(* if z is the address and a constant, no fixup *)	(* GetPut *)
	END SYSgetput;

	PROCEDURE SYSportio* (VAR z, x: Item; pin: BOOLEAN);	(* SYSTEM.PORTIN, SYSTEM.PORTOUT *)(* New Functions *)
	(*	OUT x, z	/	IN z, x	*)
		 VAR	reg: Item; 
	BEGIN
		reg.mode := Reg; reg.node := NIL;
		IF pin THEN
			IF x.mode # Reg THEN 
				load(x);		(* load x into reg *)
			END;
			OPL.Instr [x.adr].hint := OPL.useEDX;	(* let the reg be DX *)
			ASSERT((x.mode = 15) & (x.typ = OPT.inttyp));
			x.typ := z.typ;		(* generate correct size *)
			GenLoad(in, reg, x);
			OPL.Instr [pc-1].hint := OPL.useEAX;
			IF z.mode = VarPar THEN 
				loadAdr(z); z.mode := RegRel		(* generate 0[Reg] where Reg = Address(par) *)
			ELSE CompleteSL(z)
			END;
			GenStore(store, z, reg)
		ELSE
			IF z.mode # Reg THEN  load(z)		(* load z into reg *)
			END;
			OPL.Instr [z.adr].hint := OPL.useEDX;
			ASSERT( z.mode = Reg );
			IF x.mode = VarPar THEN
				loadAdr(x); x.mode := RegRel		(* generate 0[Reg] where Reg = Address(par) *)
			ELSE CompleteSL(x)
			END;
			IF x.mode # Reg THEN GenLoad(ld, x, x) END;
			OPL.Instr [x.adr].hint := OPL.useEAX;
			ASSERT( x.mode = Reg );	
			GenLoad(out, reg, x);
			OPL.Instr [pc-1].dest := z.adr
		END;
	END SYSportio;

	PROCEDURE SYSgetputReg* (VAR z, x: Item; getrfn: BOOLEAN); (* SYSTEM.PUTREG, SYSTEM.GETREG *)
	(* 
	0	EAX/AX/AL	1	ECX/CX/CL	2	EDX/DX/DL	3	EBX/BX/BL
	4	ESP/SP/AH	5	EBP/BP/CH	6	ESI/SI/DH	7	EDI/DI/DL
	registers size is depending on the type of the variable (2nd argument in PUTREG/GETREG). 
	SHORTINT 	= 8 bit values 	(AL, CL, DL, BL, AH, CH, DH, DL)
	INTEGER  	= 16 bit values 	(AX, CX, DX, BX, SP, BP, SI, DI)
	LONGINT 	= 32 bit values 	(EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI)
	SYTEM.PUTREG (const, const) always access 32 bit register. 	*)
		VAR reg: Item;
	BEGIN
		reg.mode := Reg; reg.node := NIL;
		ASSERT(x.typ # OPT.lrltyp);
		IF getrfn THEN
			IF z.typ = OPT.realtyp THEN z.typ := OPT.linttyp END;		(*real, move 32-bit*)
			reg.adr := x.adr; reg.typ := z.typ;
			IF z.mode = VarPar THEN
				loadAdr (z); z.mode := RegRel
			ELSE CompleteSL (z)
			END;
			GenStore (getReg, z, reg);
			OPL.Instr [pc-1].hint := OPL.useEAX + x.adr
		ELSE (* putrrn *)
			IF x.typ = OPT.realtyp THEN x.typ := OPT.linttyp END;		(*real, move 32-bit*)
			IF x.mode = Con THEN x.typ := OPT.linttyp
			ELSIF x.mode = VarPar THEN
				loadAdr (x); x.mode := RegRel
			ELSE CompleteSL (x)
			END;
			GenLoad (putReg, reg, x);
			OPL.Instr [pc-1].hint := OPL.useEAX + z.adr
		END
	END SYSgetputReg;

	PROCEDURE SYSinterrupt* (clear: BOOLEAN);					(* New Functions *)
	(*		inserts a CLI (clear) or a STI (~clear) instruction	*)
	BEGIN
		IF clear THEN Gen0(cli) ELSE Gen0(sti) END
	END SYSinterrupt;

	PROCEDURE Msk* (VAR z, x, y: Item); (* z := x AND y *)
	BEGIN
		y.adr := -1 - y.adr; (* invert y.adr *)
		load (x);
		Gen3 (and, z, x, y)
	END Msk;

	PROCEDURE Field* (VAR x: Item; offset: LONGINT); (* Record.field *)
	BEGIN
		ASSERT (x.mode IN {Var, VarPar, Abs, RegRel});
		IF x.mode IN {Var, Abs} THEN INC (x.adr, offset)
		ELSIF x.mode = VarPar THEN
			loadAdr (x); x.mode := RegRel; x.offs := offset
		ELSE (* RegRel *)
			INC (x.offs, offset)
		END
	END Field;

	PROCEDURE Method* (VAR x: Item;  obj: OPT.Object);	(* self.Meth *)
			(* x is self, obj is the method *)
	VAR  reg: LONGINT;
	BEGIN
		(* x.typ is the record, because self has been dereferenced to access it *)
		ASSERT(obj.mode = TProc, 201);
		x.typ := OPT.ptrtyp;
		loadAdr(x); reg := x.adr;
		x.mode := RegRel; x.offs := -4; load(x);	(*get the td*)
		OPL.Instr[pc-1].hint := OPL.useEBX;	(*avoid overwriting reg*)
		x.mode := RegRel; x.offs := MethodOffs - 4 * (obj.adr DIV 10000H); load(x);	(*get the method*)
		x.descReg := reg;
		x.typ := delegateType;
	END Method;

	PROCEDURE MakeVar(VAR x: Item; var: OPT.Object);
	BEGIN
		ASSERT(var.mode = Var, 100);
		x.mode := Var; x.adr := var.linkadr; x.offs := 0; x.typ := var.typ; x.node := NIL;
		x.mnolev := var.mnolev; x.inx := none;
		IF x.typ.comp = OpenArr THEN
			x.descReg := FP;  x.descOffs := x.adr + (x.typ.n+1) * OPM.LIntSize
		ELSE
			x.descReg := none
		END;
	END MakeVar;
	
	PROCEDURE ArrayLen(VAR len: Item; arr: Item; n: LONGINT);
	(* return n-th dimension of arr.typ *)
	VAR  typ: OPT.Struct; i: LONGINT;
	BEGIN
		IF arr.typ.sysflag = notag THEN
			OPM.err(200)
		END;
		typ:=arr.typ; i:=n; WHILE i>0 DO  typ := typ.BaseTyp;  DEC(i)  END;
		ASSERT(typ.comp IN ArraySet, 100);
		IF typ.comp = StaticArr THEN
			MakeCon(len, OPT.linttyp, typ.n)
		ELSIF typ.comp = SDynArr THEN
			ASSERT(typ.link#NIL, 101);
			MakeVar(len, typ.link);
		ELSE	(*dynamic size*)
			IF arr.descReg=none THEN
				IF typ.comp=DynArr THEN  loadDynArr(arr) 
				ELSE
					ASSERT(arr.mode IN {Var, VarPar}, 103);
					arr.descReg := FP;  arr.descOffs := arr.adr + (arr.typ.n+1) * OPM.LIntSize;
				END
			END;
			ASSERT(arr.descReg # none, 102);	(*array descriptor must be set*)
			IF arr.descReg = FP THEN
				len.mode := Var; len.adr := arr.descOffs - OPM.LIntSize * n; len.offs := 0
			ELSE
				len.mode := RegRel; len.adr := arr.descReg; len.offs := arr.descOffs - OPM.LIntSize * n
			END;
			len.typ := OPT.linttyp; len.node := NIL; len.mnolev := arr.mnolev; len.inx := none
		END
	END ArrayLen;
	
	PROCEDURE Len* (VAR len, x, y: Item);	(* len := LEN (x, y), where x is a dynamic array and y the dimension *)
	BEGIN
		ASSERT(y.mode = Con, 100);
		ASSERT(x.typ.comp IN {OpenArr, DynArr}, 101);
		ArrayLen(len, x, y.adr)
	END Len;
	
	PROCEDURE ArrayBaseSize(VAR len: Item; arr: Item);
	VAR  typ: OPT.Struct; dim: LONGINT; t, tt: Item;
	BEGIN
		ASSERT(arr.typ.comp IN ArraySet, 100);
		typ := arr.typ.BaseTyp;  dim := 1;
		MakeCon(len, OPT.linttyp, 1);
		WHILE typ.comp IN ArraySet DO
			ArrayLen(t, arr, dim);  
			IF (t.mode=Con)&(len.mode=Con) THEN  len.adr:=len.adr*t.adr  ELSE  tt := len;  Mul(len, t, tt, LInt)  END;
			typ := typ.BaseTyp; INC(dim)
		END;
		MakeCon(t, OPT.linttyp, typ.size); 
		IF (t.mode=Con)&(len.mode=Con) THEN  len.adr:=len.adr*t.adr  ELSE  tt := len;  Mul(len, t, tt, LInt)  END;
	END ArrayBaseSize;

	PROCEDURE TypeSize(x: Item; VAR size: Item; VAR step, scale: SHORTINT);	(*used for moves, returns the scale*)
	VAR  typ: OPT.Struct; dim, rest: LONGINT; t, tt: Item;
	BEGIN
		typ := x.typ; dim := 0;
		MakeCon(size, OPT.linttyp, 1);
		WHILE typ.comp IN ArraySet DO
			ArrayLen(t, x, dim);
			IF (t.mode=Con)&(size.mode=Con) THEN  size.adr:=size.adr*t.adr  ELSE  tt := size;  Mul(size, t, tt, LInt)  END;
			typ := typ.BaseTyp; INC(dim)
		END;
		(*base type has a fixed size*)
		IF typ.size MOD 4 = 0 THEN
			scale := OPO.Scale4; step := OPO.Bit32;  rest := typ.size DIV 4
		ELSIF typ.size MOD 2 = 0 THEN
			scale := OPO.Scale2; step := OPO.Bit16;  rest := typ.size DIV 2
		ELSE
			scale := OPO.Scale1; step := OPO.Bit8;  rest := typ.size
		END;
		IF rest#0 THEN
			IF size.mode=Con THEN  size.adr:=size.adr*rest
			ELSE  MakeCon(t, OPT.linttyp, rest); tt := size;  Mul(size, t, tt, LInt)
			END
		END;
		ASSERT(size.mode IN {Con, Reg}, 110)
	END TypeSize;

	PROCEDURE Length (VAR len, x: Item); (* len := LEN (x) *)
	BEGIN
		IF x.typ.form = String THEN MakeCon (len, OPT.linttyp, x.offs);
		ELSE  ArrayLen(len, x, 0)
		END
	END Length;
	
	PROCEDURE loadDynArr(VAR z: Item);	(*z points to the ArrBlk. make z point to the first elem and set desc*)
	BEGIN
		ASSERT(z.typ.comp = DynArr, 100);
		ASSERT(z.descReg = none, 101);
		load(z);
		z.descReg := z.adr; z.descOffs := ArrBlkLastDim + z.typ.n*4;	(*point to the first dim*)
		z.mode := RegRel; z.offs := ArrBlkLastDim + 4 + 8*((1+z.typ.n) DIV 2);
	END loadDynArr;
	
	PROCEDURE Index* (VAR z, index: Item); (* z := z[index] *)
		VAR
			t, len, size: Item;  typ: OPT.Struct;
			scale, comp, check: LONGINT;
	BEGIN
		check := z.mode;  ASSERT(check IN {Var, VarPar, Abs, RegRel}, 100);
		typ := z.typ;  comp := typ.comp;  ASSERT(comp IN ArraySet, 101);
		IF (*z.mode IN {Var, VarPar, Abs}*)(z.descReg=none) & (comp#StaticArr) THEN	(*first access: load base address, ev. array desc (dym/open/sdyn)*)
			ASSERT(z.mode # Reg, 102);
			IF comp = DynArr THEN
				loadDynArr(z)
			ELSIF (comp = SDynArr) & (z.mode # RegRel) THEN
				ASSERT(z.mode IN {Var, VarPar}, 103);
				z.mode := Var; load(z); z.mode := RegRel; z.offs := 0;
			ELSIF comp = OpenArr THEN
				ASSERT(z.mode IN {Var, VarPar}, 103);
				z.descReg := FP;  z.descOffs := z.adr + (z.typ.n+1) * OPM.LIntSize;
				z.mode := Var; load(z); z.mode := RegRel; z.offs := 0;
			END
		END;
		
		(*load index*)
		IF index.typ.form # LInt THEN  Convert(index, LInt)  END;
		
		(*index check*)
		IF (OPM.inxchk IN OPM.options) & ((index.mode#Con) OR (comp#StaticArr))THEN
			ArrayLen(len, z, 0); CheckIndex(index, len)					(*side effect of CheckIndex: index is loaded*)
		ELSIF ~(index.mode IN {Con, Reg}) THEN  load(index)
		END;
		
		(*perform index*)
		ASSERT(index.mode IN {Con, Reg}, 106);
		ASSERT(z.mode IN {Abs, Var, VarPar, RegRel}, 107);
		IF (z.mode = Var) & (level - z.mnolev > 0 ) THEN (* we need static link *)
			CompleteSL (z);
		END;
		IF (index.mode # Con) OR (index.adr # 0) THEN	(*something to do*)
			ArrayBaseSize(size, z);
			ASSERT(size.mode IN {Con, Reg}, 105);
			IF (size.mode = Con) & (size.adr = 0) THEN
				(*skip*)
			ELSIF (index.mode = Con) & (size.mode=Con) THEN
				index.adr := index.adr*size.adr;
				IF z.mode = Abs THEN  INC(z.adr, index.adr)
				ELSIF z.mode = Var THEN  INC(z.adr, index.adr)
				ELSIF z.mode # RegRel THEN  loadAdr(z);  z.mode := RegRel;  z.offs := index.adr
				ELSE  INC(z.offs, index.adr)
				END;
			ELSE
				IF z.inx = none THEN	(*index.mode = Reg*)
					IF z.mode = Var THEN z.mode := RegRel; z.offs := z.adr; z.adr := FP
					ELSIF z.mode = VarPar THEN  loadAdr(z); z.mode := RegRel
					END;
					z.inx := index.adr; z.scale := SHORT(SHORT(scale))
				ELSE
					loadAdr(z); z.mode := RegRel; z.offs := 0; z.inx := index.adr; z.scale := SHORT(SHORT(scale))
				END;
				IF (size.mode=Con)&(size.adr<=8)&(size.adr IN {1, 2, 4, 8}) THEN
					CASE size.adr OF 1: z.scale := OPO.Scale1 | 2: z.scale := OPO.Scale2 | 4: z.scale := OPO.Scale4 | 8: z.scale := OPO.Scale8 END;
				ELSE Mul(t, size, index, LInt); index := t END;
				z.inx := index.adr
			END
		END;
		z.typ := typ.BaseTyp; DEC(z.descOffs, OPM.LIntSize);
	END Index;

	PROCEDURE MoveBlock (VAR z, x, size: Item; moveSize: SHORTINT);
	(* move 'size' element from x to z, where 'element' has the size 'moveSize' (byte, word, dword *)
	VAR type: OPT.Struct;  src: Item;
	BEGIN
		ASSERT (moveSize IN {OPO.Bit8, OPO.Bit16, OPO.Bit32});
		IF (size.mode = Con) & (moveSize IN {OPO.Bit16, OPO.Bit8})  THEN (* try to optimize *)
			IF (size.adr MOD 4 = 0) & (moveSize = OPO.Bit8) THEN
				size.adr := size.adr DIV 4; moveSize := OPO.Bit32
			ELSIF size.adr MOD 2 = 0 THEN
				size.adr := size.adr DIV 2; DEC (moveSize, 8) (* 8 bit -> 16 bit; 16  bit -> 32 bit *)
			END
		END;
		IF (size.mode = Con) & (size.adr = 1) THEN	(* block size = 1, 2, 4 -> use assignment, do  not loop *)
			ASSERT(moveSize IN {OPO.Bit8, OPO.Bit16, OPO.Bit32});
			IF moveSize = OPO.Bit8 THEN
				type := OPT.sinttyp
			ELSIF moveSize = OPO.Bit16 THEN
				type := OPT.inttyp
			ELSE
				type := OPT.linttyp
			END;
			IF x.mode = Reg THEN
				x.mode := RegRel; x.offs := 0; x.inx := none
			END;
			x.typ := type; load(x);
			IF (z.mode = VarPar) OR ((z.mode = Var) & (level - z.mnolev # 0)) THEN	(*Abs, RegRel handled by Store*)
				loadAdr(z)
			END;
			IF z.mode = Reg THEN
				z.mode := RegRel; z.offs := 0; z.inx := none
			END;
			z.typ := type;
			GenStore(store, z, x)
		ELSIF (size.mode = Con) & (size.adr = 3) & (moveSize = OPO.Bit8) THEN	(* special case, often used *)
			IF x.mode # Reg THEN loadAdr(x) END;
			IF z.mode # Reg THEN loadAdr(z) END;
			x.mode := RegRel; x.offs := 0; x.inx := none; x.typ := OPT.inttyp;
			z.mode := RegRel; z.offs := 0; z.inx := none; z.typ := OPT.inttyp;
			src := x;  load(src); GenStore(store, z, src);
			x.offs := 2; x.typ := OPT.sinttyp;
			z.offs := 2; z.typ := OPT.sinttyp;
			load(x); GenStore(store, z, x)
		ELSE
			IF (size.typ.form # LInt) & (size.mode # Con) THEN
				Convert (size, LInt); OPL.Instr [size.adr].hint := OPL.useECX;
			ELSE
				IF size.mode # Reg THEN
					size.typ := OPT.linttyp; load (size); OPL.Instr [size.adr].hint := OPL.useECX
				ELSIF (size.adr > 0) & (OPL.Instr [size.adr].hint = OPL.noHint)  THEN OPL.Instr [size.adr].hint := OPL.tryECX
				END
			END;
			IF x.mode # Reg THEN
				loadAdr (x); OPL.Instr [x.adr].hint := OPL.useESI
			ELSIF (x.adr >= 0) & (OPL.Instr [x.adr].hint = OPL.noHint) THEN OPL.Instr [x.adr].hint := OPL.tryESI
			END;
			IF z.mode # Reg THEN
				loadAdr (z); OPL.Instr [z.adr].hint := OPL.useEDI
			ELSIF (z.adr >= 0) & (OPL.Instr [z.adr].hint = OPL.noHint) THEN OPL.Instr [z.adr].hint := OPL.tryEDI
			END;
			Gen0 (cld);
			GenRepMovs (z, x, size, moveSize,  FALSE);
			IncReg (size.adr); IncReg (x.adr); IncReg (z.adr)
		END
	END MoveBlock;

	PROCEDURE MoveBlockReversed (VAR z, x, size: Item; moveSize: SHORTINT);
	(* same as MoveBlock, but reversed! *)
	VAR	scale: SHORTINT; t: LONGINT;
	BEGIN
		ASSERT (moveSize IN {OPO.Bit8, OPO.Bit16, OPO.Bit32});
		IF (size.mode = Con) & (moveSize IN {OPO.Bit16, OPO.Bit8})  THEN (* try to optimize *)
			IF (size.adr MOD 4 = 0) & (moveSize = OPO.Bit8) THEN
				size.adr := size.adr DIV 4; moveSize := OPO.Bit32
			ELSIF size.adr MOD 2 = 0 THEN
				size.adr := size.adr DIV 2; DEC (moveSize, 8) (* 8 bit -> 16 bit; 16  bit -> 32 bit *)
			END
		END;
		IF (size.typ.form # LInt) & (size.mode # Con) THEN
			Convert (size, LInt); OPL.Instr [size.adr].hint := OPL.useECX;
		ELSE
			IF size.mode # Reg THEN
				size.typ := OPT.linttyp; load (size); OPL.Instr [size.adr].hint := OPL.useECX
			ELSIF (size.adr > 0) & (OPL.Instr [size.adr].hint = OPL.noHint)  THEN OPL.Instr [size.adr].hint := OPL.tryECX
			END
		END;
		ASSERT(size.mode=Reg);
		CASE moveSize OF  OPO.Bit8: scale:=OPO.Scale1  |OPO.Bit16: scale:=OPO.Scale2  |OPO.Bit32: scale:=OPO.Scale4 END;
		t := ASH(1, scale);
		
		IF x.mode = Reg THEN
			x.mode := RegRel; x.offs := 0
		ELSIF (x.mode # RegRel) OR (x.inx # none) OR (z.typ.form=Comp) THEN
			loadAdr(x); x.mode := RegRel; x.offs := 0
		END;
		ASSERT(x.mode=RegRel);
		x.typ := OPT.linttyp;
		x.inx := size.adr; x.scale := scale; DEC(x.offs, t); loadAdr (x); OPL.Instr [x.adr].hint := OPL.useESI;
		
		IF z.mode = Reg THEN
			z.mode := RegRel; z.offs := 0
		ELSIF (z.mode # RegRel) OR (z.inx # none) OR (z.typ.form=Comp) THEN
			loadAdr(z); z.mode := RegRel; z.offs := 0
		END;
		ASSERT(z.mode=RegRel);
		z.typ := OPT.linttyp;
		z.inx := size.adr; z.scale := scale; DEC(z.offs, t); loadAdr (z); OPL.Instr [z.adr].hint := OPL.useEDI;
		
		Gen0 (std);
		GenRepMovs (z, x, size, moveSize,  TRUE);
		IncReg (size.adr); IncReg (x.adr); IncReg (z.adr);
		Gen0 (cld)
	END MoveBlockReversed;

	PROCEDURE Move (VAR z, x: Item); (* z := x, where the size of x is byte, word or dword *)
	VAR  src, dst: Item;
	BEGIN
		IF z.mode = VarPar THEN
			loadAdr (z); z.mode := RegRel
		ELSE CompleteSL (z)
		END;
		IF (x.typ = OPT.hinttyp) THEN
			x.typ := OPT.linttyp; z.typ := OPT.linttyp;
			IF x.mode = VarPar THEN  loadAdr(x); x.mode := RegRel ; x.inx := none END;
			src := x; dst := z;
			NextWord(x, src); NextWord(z, dst);
			load(src);  GenStore(store, dst, src);	(*assign lower dword first (better caching)*)
		ELSIF (z.typ.form = ProcTyp) & (z.typ.sysflag = delegate) THEN
			x.typ := OPT.linttyp; z.typ := OPT.linttyp;
			IF z.mode = VarPar THEN
				loadAdr(z); z.mode := RegRel; z.offs := 0; z.inx := none
			END;
			IF x.mode = Con THEN
				load(x); src := x
			ELSIF x.mode = Reg THEN
				src := x; src.adr := x.descReg;
			ELSE
				IF x.mode = VarPar THEN  loadAdr(x); x.mode := RegRel; x.offs := 0; x.inx := none END;
				NextWord(src, x);
			END;
			load(src); NextWord(dst, z);
			GenStore(store, dst, src);
		END;
		load (x);
		GenStore (store, z, x)
	END Move;

	PROCEDURE SYSmove* (VAR z, x, nofBytes: Item); (* z := SYSTEM.MOVE (x, y) *)
	BEGIN
		ASSERT ((z.typ.form IN {LInt, Pointer}) & (x.typ.form IN {LInt, Pointer}));
		IF x.mode # Reg THEN
			load (x); OPL.Instr [x.adr].hint := OPL.useESI
		ELSIF OPL.Instr [x.adr].hint = OPL.noHint THEN OPL.Instr [x.adr].hint := OPL.tryESI
		END;
		IF z.mode # Reg THEN
			load (z); OPL.Instr [z.adr].hint := OPL.useEDI
		ELSIF OPL.Instr [z.adr].hint = OPL.noHint THEN OPL.Instr [z.adr].hint := OPL.tryEDI
		END;
		MoveBlock (z, x, nofBytes, OPO.Bit8)
	END SYSmove;
	
	PROCEDURE Copy* (VAR z, x: Item);	(* COPY (x, z) *)
		VAR 
			zLen, xLen, zLen0, xLen0, char0X, len, z0, x0, t: Item;
			Lfix, L: Label;
	BEGIN
		MakeCon (char0X, OPT.chartyp, 0);
		Length (zLen, z); Length (xLen, x);
		IF (zLen.mode = Con) & (xLen.mode = Con) THEN
			IF zLen.adr >= xLen.adr THEN MoveBlock (z, x, xLen, OPO.Bit8)
			ELSE
				DEC (zLen.adr); (* last char is always 0X *)
				MoveBlock (z, x, zLen, OPO.Bit8);
				t.adr := z.adr; t.mode := RegRel; t.offs := 0; t.inx := none; t.typ := OPT.chartyp; t.node := NIL;
				Move (t, char0X) (* write 0X at the end of z *)
			END
		ELSE 
			(* pre-load the addresses (it will be done only once and will free some regs!!) *)
			IF x.mode#Reg THEN loadAdr (x) ELSE x0:=x; MakeCon(len, OPT.linttyp, 0); Add(x, x0, len, LInt) END;
			OPL.Instr [x.adr].hint := OPL.tryESI;
			loadAdr (z); OPL.Instr [z.adr].hint := OPL.tryEDI;
			IF zLen.mode = Con THEN 
				xLen0 := xLen;
				IF xLen.typ.form # LInt THEN Convert (xLen0, LInt)
				ELSE load (xLen0)
				END;
				OPL.Instr [xLen0.adr].hint := OPL.tryECX;
				GenFlags (cmp, xLen0, zLen);
				Lfix := -2-pc;
				Gen1 (jg, Nil, NIL)
			ELSE
				zLen0 := zLen;
				IF zLen0.typ.form # LInt THEN Convert (zLen0, LInt)
				ELSE load (zLen0)
				END;
				OPL.Instr [zLen0.adr].hint := OPL.tryECX;
				xLen0 := xLen;
				IF xLen0.mode # Con THEN
					IF xLen0.typ.form # LInt THEN Convert (xLen0, LInt)
					ELSE load (xLen0)
					END
				END;
				GenFlags (cmp, zLen0, xLen0);
				Lfix := -2-pc;
				Gen1 (jl, Nil, NIL)
			END;
			(* first case: |src| <= |trg|: copy all *)
			z0 := z; x0 := x; MoveBlock (z0, x0, xLen, OPO.Bit8);
			L := -2-pc; Gen1 (jmp, Nil, NIL);
			FixLink (Lfix);
			(* second case: |src| > |trg|: copy |trg|-1 bytes *)
			IF zLen.mode = Con THEN DEC (zLen.adr)
			ELSE
				MakeCon (len, OPT.linttyp, 1);
				load (zLen); OPL.Instr [zLen.adr].hint := OPL.useECX;
				t := zLen; Sub (zLen, t, len, LInt)
			END;
			MoveBlock (z, x, zLen, OPO.Bit8);
			t.mode := RegRel; t.adr := z.adr; t.offs := 0; t.inx := none; t.typ := OPT.chartyp; t.node := NIL;
			Move (t, char0X); (* last char is 0X *)
			FixLink (L)
		END 
	END Copy;

	PROCEDURE Assign* (VAR z, x: Item);	(* z  := x *) 
		VAR 
			zform, xform, step, scale : SHORTINT; 
			temp, zero, sizeItem: Item;
			proc: OPT.Object;
	BEGIN
		zform := z.typ.form; xform := x.typ.form;
		IF (zform IN {Int, LInt, Real, LReal}) & (zform # xform) THEN Convert (x, zform) END;
		CASE zform OF
			Bool:
				IF x.mode = Coc THEN
					temp := x; MoveCoc (x, temp) 
				ELSE load (x) 
				END;
				IF z.mode = VarPar THEN
					loadAdr (z); z.mode := RegRel;
				ELSE CompleteSL (z) 
				END;
				GenStore (store, z, x)
		  | Byte, Char, SInt, Set, Int, LInt, HInt:
				Move (z, x)
		  | Real:
				loadf (x);
				IF z.mode = VarPar THEN
					loadAdr (z); z.mode := RegRel
				ELSE CompleteSL (z) 
				END;
				GenStore (fstore, z, x)
		  | LReal:
				loadf (x);
				IF z.mode = VarPar THEN
					loadAdr (z); z.mode := RegRel
				ELSE CompleteSL (z) 
				END;
				GenStore (fstore, z, x)
		  | Pointer:
				IF xform = NilTyp THEN
					MakeCon (zero, OPT.linttyp, nil);
					load (zero);
					IF z.mode = VarPar THEN
						loadAdr (z); z.mode := RegRel
					ELSE CompleteSL (z) 
					END;
					GenStore (store, z, zero);
				ELSE
					load (x);
					IF z.mode = VarPar THEN
						loadAdr (z); z.mode := RegRel
					ELSE CompleteSL (z) 
					END;
					temp:=z;
					GenStore (store, z, x);
				END
		  | ProcTyp:
				IF (z.typ = x.typ) OR (xform = NilTyp) THEN (* procedure variable assignment *)
					IF xform = NilTyp THEN
						MakeCon (x, OPT.linttyp, nil)
					END;
					Move (z, x)
				ELSIF (x.mode = Reg) THEN
					ASSERT(x.typ = delegateType);	(*coming from OPC.Method*)
					Move(z, x)
				ELSE (* procedure assignment *)
					proc := x.node.obj;
					IF x.mnolev = 0 THEN (* local procedure assignment *)
						GenLoadProc (ldProc, x, proc.adr MOD 10000H, x.node)
					ELSE
						GenLoadProc (ldXProc, x, proc.adr DIV 10000H, x.node)
					END;
					IF z.typ.sysflag = delegate THEN
						MakeCon(zero, OPT.ptrtyp, 0);
						load(zero); x.descReg := zero.adr
					END;
					Move (z, x)
				END
		  | Comp:
				ASSERT ((z.typ.comp=Record) OR ((z.typ.comp IN {StaticArr, DynArr, SDynArr})));	
				IF x.typ.form = String THEN
					Copy(z, x)
				ELSE
					IF (z.typ.comp IN {(*StaticArr,*) SDynArr}) THEN
						TypeSize(z, sizeItem, step, scale);
						temp:=z; MoveBlock (z, x, sizeItem, step)
					ELSIF z.typ.comp = DynArr THEN
						CopyDynArr(z, x)
					ELSIF x.typ.size#4 THEN
						MakeCon (sizeItem, OPT.linttyp, z.typ.size); step:=OPO.Bit8;	(* optimize later in MoveBlock *)
						temp:=z; MoveBlock (z, x, sizeItem, step)
					ELSE temp:=z; Move(z, x)
					END;
				END
		ELSE HALT (BUG)
		END
	END Assign;

	PROCEDURE IncDec* (VAR z, x: Item; increment: BOOLEAN); (* INC / DEC (z, x) *)
		VAR z0, temp: Item;
	BEGIN
		z0 := z; load (z0); temp := z0;
		IF increment THEN Add (z0, temp, x, z.typ.form)
		ELSE Sub (z0, temp, x, z.typ.form)
		END;
		Assign (z, z0)
	END IncDec;

	PROCEDURE MulDim* (VAR nofelem, len: Item); (* nofelem := nofelem * len *)
		VAR t: Item;
	BEGIN
		IF (nofelem.mode = Con) & (len.mode = Con) THEN nofelem.adr := nofelem.adr * len.adr
		ELSE
			t := nofelem; Mul (nofelem, t, len, LInt)
		END
	END MulDim;

	PROCEDURE PushLen* (VAR z: Item); (* push length z -> NEW (dynArr, dim0, dim1,... ) *)
	BEGIN
		IF z.mode # Con THEN
			IF  z.typ.form # LInt THEN 
				IF z.mode=Var THEN load(z) END;
				Convert (z, LInt)
			ELSE load (z)
			END
		END;
		GenPush (z)
	END PushLen;

	PROCEDURE PopLen* (VAR block: Item);
	(* poplength and store it to the dynamic array -> used for NEW (dynArr, dim0, dim1, ...) *)
		VAR reg: Item;
	BEGIN
		reg.typ := OPT.linttyp; (* reg.node := NIL is done in GenPop *)
		GenPop (reg);
		GenStore (store, block, reg)
	END PopLen;

	PROCEDURE NewSys* (VAR z, x: Item); (* SYSTEM.NEW (z, x) *)
	BEGIN
		IF z.mode # Reg THEN loadAdr (z) END;
		GenPush (z);
		IF x.typ.form IN {SInt, Int} THEN
			IF x.mode = Con THEN x.typ := OPT.linttyp
			ELSE Convert(x, LInt)  (* << mh 30.8.94 *)
			END
		END;
		IF x.mode#Con THEN load (x) END; GenPush (x); 
		GenCall (xcall, OPL.NewSysLinkIndex * 10000H + OPL.NewSysEntryNr, 8, NIL);
	END NewSys;
	
	PROCEDURE NewArray* (VAR z, nofelem: Item; nofdim: LONGINT; typ: OPT.Struct; dimUsed: BOOLEAN);
	(* NEW (dynArr, dim0, dim1, ...) *)
		VAR
			cons, tdesc, t: Item;
			nofArrElems: LONGINT;
			o: OPT.Object;
	BEGIN
		nofArrElems:=1;
		WHILE typ.comp=StaticArr DO
			nofArrElems:=nofArrElems*typ.n; typ:=typ.BaseTyp
		END;
		IF nofArrElems#1 THEN
			MakeCon(cons, OPT.linttyp, nofArrElems);  MulDim(nofelem, cons)
		END;
		loadAdr(z); 
		IF dimUsed THEN GenPush(z) END;
		IF (typ.form = Pointer) OR (typ.comp = Record) OR (typ.form = ProcTyp) & (typ.sysflag = delegate) THEN
			t := z; GenPush(t);
			IF typ.form=Pointer THEN
				OPT.FindInScope(OPT.HdPtrStruct, OPT.topScope, o);
				typ := o.typ
			ELSIF typ.form = ProcTyp THEN
				OPT.FindInScope(OPT.Delegate, OPT.topScope, o);
				typ := o.typ
			END;
			GetTdAdr(typ, tdesc); load(tdesc);
			GenPush(tdesc);
			IF nofelem.mode#Con THEN load(nofelem) END;
			GenPush(nofelem);
			MakeCon(cons, OPT.linttyp, nofdim);  GenPush(cons);
			GenCall(xcall, OPL.NewArrayLinkIndex * 10000H + OPL.NewArrayEntryNr, 16, NIL)
		ELSE	(* simple type -> use SYSTEM.NEW (...) *)
			IF nofelem.mode=Con THEN
				nofelem.adr := nofelem.adr*typ.size + ArrBlkFirstElem + 8 + 8*(nofdim DIV 2);	(*rounded!*)
			ELSE
				MakeCon(cons, OPT.linttyp, typ.size); t:=nofelem; Mul(nofelem, t, cons, LInt);
				cons.adr := ArrBlkFirstElem + 8 + 8*(nofdim DIV 2);
				t:=nofelem; Add(nofelem, t, cons, LInt)
			END;
			t := z; NewSys(t, nofelem)
		END;
		IF dimUsed THEN
			GenPop(z); z.mode:=RegRel; z.offs := 0;
			load(z); z.mode:=RegRel; z.typ:=OPT.ptrtyp; z.offs:=ArrBlkFirstElem; z.inx:=none
		END
	END NewArray;

	PROCEDURE NewRec* (VAR z: Item; typ: OPT.Struct); (* NEW (record), NEW (POINTER TO Static ARRAY) *)
		VAR	tag, size: Item; btyp: OPT.Struct; len: LONGINT; o: OPT.Object;
	BEGIN
		IF typ.comp=StaticArr THEN
			len := typ.n; btyp := typ.BaseTyp;
			WHILE btyp.comp = StaticArr DO len := len * btyp.n; btyp := btyp.BaseTyp END;
			MakeCon (size, OPT.linttyp, len);
			IF (btyp.comp = Record) OR (btyp.form = Pointer) OR (btyp.form = ProcTyp) & (btyp.sysflag = delegate) THEN NewArray (z, size, 1, btyp, FALSE)
			ELSE 
				size.adr := typ.size+16; NewSys (z, size)
			END
		ELSE
			loadAdr (z); GenPush (z);
			IF typ.comp=DynArr THEN OPT.FindInScope(OPT.HdPtrStruct, OPT.topScope, o); typ := o.typ  END;
			GetTdAdr (typ, tag);
			load (tag); GenPush (tag);
			GenCall (xcall, OPL.NewLinkIndex * 10000H + OPL.NewEntryNr, 8, NIL)
		END
	END NewRec;

	PROCEDURE CallRecBody*(VAR self, body: Item; typ: OPT.Struct);		(* Active only *)
		VAR con: Item;
			type: LONGINT;
			tag, t0, t1: Item;
		
		PROCEDURE GetBody(curtype, bodytype: OPT.Struct;  VAR body: Item);
		VAR  tag: Item;
		BEGIN
			GetTdAdr(curtype, tag);	(*use indirect access, the record may be invisible!*)
			DeRef(tag);
			IF curtype # bodytype THEN
				tag.mode := RegRel; tag.offs := -8 - 4*bodytype.extlev; tag.inx := none; tag.typ := OPT.ptrtyp;
				load(tag)
			END;
			body.adr := tag.adr; (* x.offs set by OPV.Designator *)	(*body.offs := MethodOffs - 4 * (body.obj.adr DIV 10000H);*)
			body.mode := RegRel; body.typ := OPT.ptrtyp;
		END GetBody;
		
	BEGIN
		IF (typ.strobj # NIL) & (activeObj IN typ.strobj.conval.setval) THEN
			ASSERT(self.typ.form = Pointer);
			GetBody(self.typ.BaseTyp, typ, body);
			load (body);
			GenPush(body);
			MakeCon(con, OPT.sinttyp, typ.strobj.prio); GenPush(con);
			type := 0;
			IF safe IN typ.strobj.conval.setval THEN INC (type, 1)	(* set bit 0 *) END;
			MakeCon (con, OPT.sinttyp, type); GenPush(con);
			load(self); GenPush(self);
			GenCall(xcall, OPL.StartIndex * 10000H + OPL.StartEntryNr, 16, NIL)
		ELSE
			(* typ and self.typ can be different!!!*)
			tag := self;
			loadAdr(tag);
			tag.mode := RegRel; tag.offs := -4; tag.inx := none; tag.typ := OPT.linttyp;
			load(tag);
			IF OPM.TDMask # 0 THEN
				t1 := tag;
				MakeCon(t0, OPT.linttyp, OPM.TDMask);
				Gen3(and, tag, t1, t0);
			END;
			GenPush(tag);
			load(self); GenPush(self);
			GetBody(self.typ.BaseTyp, typ, body);
			load (body);
			GenCall(callReg, body.adr, 4, NIL)
		END;
	END CallRecBody;

	PROCEDURE PushArrLen(fp: OPT.Object; VAR ap, dest: Item; useDest: BOOLEAN);
	VAR  atyp, ftyp: OPT.Struct; depth: LONGINT; len, size, t: Item;
	BEGIN
		atyp := ap.typ; ftyp := fp.typ; depth := 0;
		WHILE ftyp.comp IN {OpenArr, SDynArr} DO
			IF ftyp.BaseTyp = OPT.bytetyp THEN
				IF (atyp.comp = Record) & (ap.mode = VarPar) THEN	(*size is dynamic*)
					len := ap;
					CompleteSL (len);
					IF len.mode IN {Var, VarPar} THEN
						INC (len.adr, 4); len.mode := Var  (* type descriptor is on the stack (hidden parameter) *)
					ELSE
						ASSERT (len.mode = RegRel);
						INC (len.offs, 4)
					END;
					DeRef (len); load (len);
				ELSIF atyp.comp IN {OpenArr, SDynArr, DynArr} THEN 	(*size is dynamic*)
					ArrayLen(len, ap, depth); ArrayBaseSize(size, ap);
					IF (len.mode=Con)&(size.mode=Con) THEN len.adr:=len.adr*size.adr ELSE Mul(t, len, size, LInt); len:=t  END;
				ELSE
					MakeCon(len, OPT.linttyp, atyp.size)
				END;
			ELSIF atyp.form = String THEN
				ASSERT(ap.mode = Abs);
				MakeCon(len, OPT.linttyp, ap.offs)
			ELSE
				ASSERT(atyp.comp IN ArraySet, 100);
				ArrayLen(len, ap, depth);
				(*IF ~(len.mode IN {Con, Reg}) THEN load(len) END*)
			END;
			len.typ := OPT.linttyp;
			IF useDest THEN
				IF len.mode # Reg THEN load(len) END;
				DEC(dest.offs, 4); t := dest; GenStore(store, t, len)
			ELSE
				IF ~(len.mode IN {Con, Reg}) THEN load(len) END;
				GenPush(len)
			END;
			atyp := atyp.BaseTyp; ftyp := ftyp.BaseTyp; INC(depth);
		END;
		IF (ap.mode=RegRel)&(ap.adr=ESP) THEN  INC(ap.offs, 4*depth)  END
	END PushArrLen;
	
	PROCEDURE PushComp(fp: OPT.Object; VAR ap: Item);
		VAR sizeItem, t: Item; size: LONGINT;
	BEGIN
		IF ap.typ.form = String THEN
			size := fp.typ.size; INC(size, (-size) MOD 4);
			MakeCon (sizeItem, OPT.linttyp, size); t:=Stack; Sub(t, Stack, sizeItem, LInt);
			MakeCon (sizeItem, OPT.linttyp, ap.offs); t:=Stack; MoveBlock (t, ap, sizeItem, OPO.Bit8)
		ELSIF ap.typ.size#4 THEN
			size := fp.typ.size; INC(size, (-size) MOD 4);
			MakeCon (sizeItem, OPT.linttyp, size); t:=Stack; Sub(t, Stack, sizeItem, LInt);
			MakeCon (sizeItem, OPT.linttyp, fp.typ.size); t:=Stack; MoveBlock (t, ap, sizeItem, OPO.Bit8)
		ELSE
			load(ap); GenPush(ap)
		END;
	END PushComp;
	
	PROCEDURE ParRecord (fp: OPT.Object; VAR ap: Item; apIsDeref, alwaysRef: BOOLEAN);
		VAR t, t0, t1, tag: Item;  pushtag: BOOLEAN;
	BEGIN
		pushtag := fp.typ.sysflag # notag;
		(*alwaysRef :=  ~pushtag(*callconv # 0*);*)
		IF ap.mode = VarPar THEN
			IF (fp.mode = VarPar) OR alwaysRef THEN (* push tag too -> tag is on the stack as a hidden parameter *)
				IF pushtag THEN
					t.mode := Var; t.adr := ap.adr + 4; t.typ := OPT.ptrtyp; t.node := NIL; 
					t.inx := none; t.offs := 0; t.mnolev := ap.mnolev;
					load (t); GenPush (t);
					lastTD := t;	(*remember the tag, used by Call later*)
					IF (ap.mode=RegRel)&(ap.adr=ESP) THEN  INC(ap.offs, 4)  END;
				END;
				IF ap.mode#Reg THEN loadAdr(ap) END; GenPush(ap)
			ELSE PushComp(fp, ap)
			END
		ELSE
			IF (fp.mode = VarPar) OR alwaysRef THEN (* push {Var, Abs} record *)
				IF pushtag THEN
					IF apIsDeref THEN (* get type descriptor of dynamic type *)
						ASSERT((ap.mode = RegRel) & (ap.offs = 0));
						tag.mode := RegRel; tag.scale := noScale; tag.typ := OPT.ptrtyp;
						tag.offs := -4; tag.adr := ap.adr; tag.inx := none; tag.descReg := none;
						IF OPM.TDMask # 0 THEN
							t1 := tag; load(t1);
							MakeCon(t0, OPT.linttyp, OPM.TDMask);
							Gen3(and, tag, t1, t0)
						END;
					ELSE
						GetTdAdr(ap.typ, tag); (* get typedescriptor address of static type *)
					END;
					load(tag); GenPush(tag);
					IF (ap.mode=RegRel)&(ap.adr=ESP) THEN  INC(ap.offs, 4)  END;
					lastTD := tag;	(*remember the tag, used by Call later*)
				END;
				IF ap.mode#Reg THEN loadAdr(ap) END; GenPush(ap)
			ELSE PushComp(fp, ap)
			END
		END
	END ParRecord;

	PROCEDURE Parameter* (VAR ap: Item; fp: OPT.Object; apIsDeref, alwaysRef: BOOLEAN);
		VAR form, apMode: SHORTINT; temp, cons, stack, tag: Item;
			proc: OPT.Object; apTyp, fpTyp: OPT.Struct;  pushtag: BOOLEAN;
	BEGIN
		fpTyp := fp.typ; apTyp := ap.typ;
		pushtag := (fpTyp.sysflag # notag) & (apTyp.sysflag # notag);
		IF (ap.typ.form = NilTyp) & (~pushtag OR (fp.mode = VarPar)) THEN
			load(ap); GenPush(ap); RETURN
		END;
		IF (apTyp.comp=DynArr) & (fpTyp.comp # DynArr) & (ap.descReg=none) THEN loadDynArr(ap)  END;
		IF (fp.mode = VarPar) OR (fpTyp.comp IN {Record, StaticArr, OpenArr, SDynArr}) THEN
			form := fpTyp.comp;
			IF form = Record THEN ParRecord (fp, ap, apIsDeref, alwaysRef)
			ELSIF (fp.mode=Var) & (fpTyp.comp=StaticArr) & pushtag THEN	(* static arrays *)
				PushComp(fp, ap);
			ELSIF (fpTyp.comp=OpenArr) THEN	(* non static arrays *)
				IF pushtag THEN
					PushArrLen (fp, ap, ap, FALSE)
				END;
				IF ap.mode#Reg THEN loadAdr (ap) END;
				IF ap.typ = OPT.hinttyp THEN ap.typ := OPT.linttyp END;
				GenPush (ap)
			ELSE
				apMode := ap.mode;
				IF apTyp.form = String THEN HALT(100); (* constant *) ap.node := NIL END;	(*not possible: can only be passed to a value par*)
				IF apTyp = OPT.hinttyp THEN ap.typ := OPT.linttyp END;
				IF ap.mode#Reg THEN loadAdr (ap) END;GenPush (ap);
				IF (fpTyp = OPT.ptrtyp) & (apTyp # OPT.ptrtyp) THEN
					(* pass ap static typ to enable run time tests -> hack *)
					IF apTyp.BaseTyp.comp = Record THEN
						GetTdAdr (apTyp.BaseTyp, tag)
					ELSE
						MakeCon (tag, OPT.linttyp, nil)
					END;
					ap.mode := RegRel; Assign (ap, tag);
				ELSIF (fpTyp = OPT.ptrtyp) & (apTyp = OPT.ptrtyp) & (apMode # VarPar) THEN
					(* pass nil to disable runtime tests -> hack *)
					MakeCon (cons, OPT.linttyp, nil);
					ap.mode := RegRel; Assign (ap, cons)
				END
			END
		ELSE
			(*push as value parameter*)
			ASSERT (ap.mode IN {Abs, Var, VarPar, Con, Reg, RegRel, Coc, XProc, LProc});
			form := apTyp.form;
			IF (apTyp # fpTyp) & ~(ap.mode IN {XProc, LProc}) & ~(form  IN {Pointer, ProcTyp, NilTyp, NoTyp}) THEN
				(* convert actual parameter *)
				Convert (ap, fp.typ.form); form := ap.typ.form
			END;
			IF (form IN realSet) & (ap.mode = Reg) THEN (* ap was converted *)
				IF fp.typ.form = Real THEN MakeCon (cons, OPT.linttyp, 4)
				ELSE MakeCon (cons, OPT.linttyp, 8)
				END;
				stack := Stack;
				Gen3 (sub, stack, stack, cons);
				stack.mode := RegRel; stack.offs := 0; stack.inx := none; stack.typ := fp.typ; (* OPT.lrltyp; *)
				GenStore (fstore, stack, ap)
			ELSE
				IF ap.mode IN {XProc, LProc} THEN
					proc := ap.node.obj;
					IF ap.mnolev = 0 THEN (* push global procedure *)
						GenLoadProc (ldProc, ap, proc.adr MOD 10000H, ap.node)
					ELSE (* push external procedure *)
						GenLoadProc (ldXProc, ap, proc.adr DIV 10000H, ap.node)
					END;
					IF (fpTyp.form = ProcTyp) & (fpTyp.sysflag = delegate) THEN
						ap.descReg := 0
					END;
				ELSIF form IN {HInt, LReal} THEN (* push lower 4 bytes -> higher bytes will be pushed later *)
					ap.typ := OPT.linttyp;	(*load lower dword first*)
					temp := ap;
					IF temp.mode = VarPar THEN loadAdr(temp); temp.mode := RegRel; temp.offs := 0 END; (* << mb 15.2.94 *)
					IF temp.mode = RegRel THEN INC (temp.offs, 4)
					ELSIF temp.mode = Reg THEN temp.adr := temp.offs	(*msb*)
					ELSE INC (temp.adr, 4)
					END;
					load (ap);	(*load lower dword first*)
					load (temp); GenPush (temp)
				ELSIF ap.mode = Coc THEN
					temp := ap; MoveCoc (ap, temp)
				END;
				IF ap.mode # Con THEN
					IF ap.typ.form IN realSet+{HInt} THEN ap.typ := OPT.linttyp END;
					load (ap)
				END;
				IF (fpTyp.form = ProcTyp) & (fpTyp.sysflag = delegate) THEN	(*push self*)
					(*ap.typ := OPT.linttyp;*)
					IF ap.descReg = 0 THEN
						MakeCon(temp, OPT.linttyp, 0)
					ELSE
						temp := ap; temp.adr := temp.descReg
					END;
					GenPush(temp)
				END;
				GenPush (ap);
				lastTD := ap
			END
		END
	END Parameter;
	
	PROCEDURE PrepRetDest*(z: Item): LONGINT;
		VAR t, from: Item; size: LONGINT;
	BEGIN
		ASSERT(z.typ.form = Comp);
		size := 4;
		IF z.mode = 0 THEN	(*special for RETURN Call *)
			IF z.typ.comp = Record THEN
				INC(size);
				from.mode:=RegRel; from.adr:=FP; from.offs:=z.offs+4; from.typ:=OPT.linttyp; from.inx:=none;
				load(from); GenPush(from)
			END;
			from.mode:=RegRel; from.adr:=FP; from.offs:=z.offs; from.typ:=OPT.linttyp; from.inx:=none;
			load(from); GenPush(from)
		ELSE
			IF z.typ.comp = Record THEN
				MakeCon(t, OPT.linttyp, z.typ.size);  GenPush(t);  INC(size, 4)
			END;
			IF z.mode IN {Var, VarPar, Abs, RegRel} THEN
				loadAdr(z)
			END;
			GenPush(z)
		END;
		RETURN size
	END PrepRetDest;
	
	PROCEDURE PushRetDesc*(VAR x, tos: Item);	(*push return descriptor!*)
	VAR con: Item;
	BEGIN
		ASSERT((tos.mode=RegRel)&(tos.adr=ESP), 101);
		IF x.typ.comp = Record THEN
			IF (x.mode=RegRel)&(x.adr=ESP) THEN INC(x.offs, 4)  END;
			MakeCon(con, OPT.linttyp, x.typ.size);  GenPush(con);
			INC(tos.offs, 4)
		END;
		loadAdr(x); GenPush(x); INC(tos.offs, 4)
	END PushRetDesc;
	
	PROCEDURE CorrectStackAdr*(VAR x: Item; size, dynblocks: LONGINT);
	VAR oldoff: LONGINT; typ: OPT.Struct;
	BEGIN
		typ := x.typ; x.typ := OPT.linttyp;	(*to ensure that load works fine*)
		IF (dynblocks#0)&(x.mode=RegRel)&(x.adr=ESP) THEN
			oldoff := x.offs; x.offs := size;
			WHILE dynblocks#0 DO
				load(x); x.mode := RegRel; x.offs := 0;
				DEC(dynblocks)
			END;
			x.offs := oldoff
			(*oldoff := x.offs; x := oldsp; x.offs := oldoff*)
		ELSIF (size#0)&(x.mode=RegRel)&(x.adr=ESP) THEN	(*if the item is stack relative, correct the position after the allocation of temporary values*)
			INC(x.offs, size)
		END;
		x.typ := typ
	END CorrectStackAdr;
	
	PROCEDURE ResetStack*(dynblocks: LONGINT);
	VAR t: Item;
	BEGIN
		t := Stack;
		WHILE dynblocks#0 DO
			GenPop(t); OPL.Instr [pc-1].hint := OPL.useESP;
			DEC(dynblocks)
		END
	END ResetStack;
	
	PROCEDURE AllocateStatic*(VAR tos: Item; size: LONGINT);
	VAR	t, con: Item;
	BEGIN
		ASSERT(size >= 0, 100);
		ASSERT(size MOD 4 = 0, 101);
		IF size # 0 THEN
			t := Stack; MakeCon(con, OPT.linttyp, size);
			Sub(t, Stack, con, LInt);
		END;
		tos.mode := RegRel; tos.adr := ESP; tos.offs := 0; tos.inx := none; tos.typ := OPT.linttyp;
	END AllocateStatic;

	PROCEDURE RemoveStatic*(size: LONGINT);
	VAR	t, con: Item;
	BEGIN
		ASSERT(size >= 0, 100);
		ASSERT(size MOD 4 = 0, 101);
		IF size # 0 THEN
			t := Stack; MakeCon(con, OPT.linttyp, size); Add(t, Stack, con, LInt)
		END
	END RemoveStatic;
	
	PROCEDURE CopyDynArr(VAR x, y: Item);
	VAR	dim: LONGINT; yy, xx, size, t: Item; typ: OPT.Struct; step, scale: SHORTINT;
	BEGIN
			(*dimensions of y*)
		IF ~(y.mode IN {Var, VarPar, Abs}) THEN  load(y); GenPush(y)  END;
		yy:=y;
		typ:=y.typ; dim:=0;
		IF y.descReg = none THEN loadDynArr(y) END;
		MakeCon(size, OPT.linttyp, 1);
		WHILE typ.comp=DynArr DO
			ArrayLen(t, y, dim); Mul(size, size, t, LInt); typ:=typ.BaseTyp; INC(dim)
		END;
			(*allocate x*)
		NewArray(x, size, dim, typ, TRUE);
		(*now x points to the first elem field*)
		INC(x.offs, 4);
		xx:=x; INC(x.offs, (dim DIV 2)*8+4);
			(*copy*)
		y:=yy;
		IF ~(y.mode IN {Var, VarPar, Abs}) THEN  GenPop(y)  END;
		IF y.descReg = none THEN loadDynArr(y) END;
		TypeSize(y, size, step, scale);
		MoveBlock(x, y, size, step);	(*copy data*)
		
		y.mode:=RegRel; y.adr:=y.descReg; y.offs:=ArrBlkLastDim; y.typ:=OPT.linttyp;
		x:=xx; x.typ:=OPT.linttyp;
		WHILE dim>0 DO
			xx:=x; yy:=y;
			Move(xx, yy);
			INC(x.offs, 4); INC(y.offs, 4); DEC(dim)
		END
	END CopyDynArr;
	
	PROCEDURE ArgSize(par: OPT.Object): LONGINT; (* ejz *)
		VAR typ: OPT.Struct; size: LONGINT;
	BEGIN
		size := 0;
		WHILE par # NIL DO
			typ := par.typ;
			IF (par.mode = VarPar) OR (typ.form IN {String, Comp}) THEN
				INC(size, 4); (* address *)
				IF (typ.comp IN {DynArr, Record}) & (typ.sysflag # notag) THEN
					INC(size, 4) (* descriptor *)
				END
			ELSIF (typ.size MOD 4) # 0 THEN
				INC(size, typ.size + 4 - (typ.size MOD 4))
			ELSE
				INC(size, typ.size)
			END;
			par := par.link
		END;
		RETURN size
	END ArgSize;

	PROCEDURE EndCall(proc: OPT.Object; typ: OPT.Struct); (* ejz *)
		VAR Z, X, Y: Item;
	BEGIN
		IF ((proc # NIL) & (proc.sysflag = cdecl)) OR ((typ # NIL) & (typ.sysflag = cdecl)) THEN
			Z.mode := Reg; Z.typ := OPT.ptrtyp; Z.node := NIL;
			Z.adr := ESP; Z.offs := 0; Z.inx := none;
			X.mode := Reg; X.typ := OPT.ptrtyp; X.node := NIL;
			X.adr := ESP; X.offs := 0; X.inx := none;
			Y.mode := Con; Y.typ := OPT.ptrtyp; Y.node := NIL;
			IF proc # NIL THEN
				Y.adr := ArgSize(proc.link)
			ELSE 
				Y.adr := ArgSize(typ.link)
			END;
			Y.offs := 0; Y.inx := none;
			Gen3(add, Z, X, Y)
		END
	END EndCall;
	
	PROCEDURE Call* (VAR x: Item; proc: OPT.Object; node: OPT.Node);
		VAR n: INTEGER; sl: Item; param: OPT.Object; tag, t0, t1, self, y, z: Item; label: Label;
	BEGIN
		IF (x.mode IN {LProc, CProc}) OR ((x.mode IN {XProc}) & (x.mnolev >= 0)) THEN (* local procedure *)	(* was active only *)
			IF slNeeded IN proc.conval.setval THEN
				n := level - x.mnolev;
				IF  OPM.traceprocs IN OPM.options THEN
					OPM.LogWLn; OPM.LogWStr("Call/SL ");
					IF x.node.obj # NIL THEN OPM.LogWStr(x.node.obj.name) END;
					OPM.LogWNum(level, 2);
					OPM.LogWStr(" -> "); OPM.LogWNum(x.mnolev, 2)
				END;
				sl.mode := Var; sl.typ := OPT.linttyp; sl.mnolev := level; sl.inx := none; sl.node := NIL;
				IF n = 0 THEN
					sl.mode := Reg; sl.adr := FP;
					GenPush(sl)
				ELSIF n = 1 THEN
					sl.adr := StaticLinkAdr;
					load(sl); GenPush(sl)
				ELSE
					sl.adr := StaticLinkAdr;
					load (sl); sl.mode := RegRel; sl.offs := StaticLinkAdr;
					WHILE n > 2 DO
						load (sl); sl.mode := RegRel; sl.offs := StaticLinkAdr;
						DEC (n)
					END;
					load(sl);
					GenPush(sl)
				END
			END;
			GenCall (call, proc.linkadr, proc.conval.intval - 4, node);
			IF (x.mode # CProc) & (proc.linkadr < 0) THEN (* forward declared procedure -> fixup chain *)
				proc.linkadr := -2 - (pc - 1);
			END;
			EndCall(proc, NIL)
		ELSIF x.mode = XProc THEN (* external procedure *)
			GenCall (xcall, x.adr, proc.conval.intval - 4, node);
			EndCall(proc, NIL)
		ELSIF x.mode IN {TProc, Typ} THEN (* type bound procedure *)
			IF node.left.subcl = 1 THEN (* super call *)
				IF node.right.obj.typ.form = Pointer THEN GetTdAdr (node.right.obj.typ.BaseTyp.BaseTyp, tag)
				ELSE GetTdAdr (node.right.obj.typ.BaseTyp, tag)
				END;
				load(tag)
			ELSE
				IF node.obj.mode = VarPar (* node.left.obj.mode = VarPar *) THEN	(* << mb 21.2.94 *)
					tag := lastTD
				ELSE (* pointer *)
					tag.mode := RegRel; tag.typ := OPT.ptrtyp; tag.node := NIL;
					tag.adr := ESP; tag.offs := 0 (* obj.conval.intval - 12 *); tag.inx := none;
					DeRef(tag); tag.mode := RegRel; tag.offs := -4;
					IF OPM.TDMask # 0 THEN
						t1 := tag; load(t1);
						MakeCon(t0, OPT.linttyp, OPM.TDMask);
						Gen3(and, tag, t1, t0);
					END;
					DeRef(tag);
				END;
			END;
			x.adr := tag.adr; (* x.offs set by OPV.Designator *)
			x.mode := RegRel; x.typ := OPT.ptrtyp; load (x);
			GenCall(callReg, x.adr, proc.conval.intval - 4, node);
			EndCall(proc, NIL)
		ELSE (* procedure variable *)
			IF OPM.WarnUnsafe THEN OPM.err(-1111) END;
			ASSERT (x.typ.form = ProcTyp);
			IF x.typ.sysflag = delegate THEN
				load(x);
				param := x.typ.link;
				label := none;
				self.mode := Reg; self.adr := x.descReg; self.typ := OPT.ptrtyp;
				MakeCon(y, OPT.ptrtyp, 0);
				Cmp(z, self, y, eql);
				Jcc(z, label, NIL);
				GenPush(self);
				FixLink(label);
				IF param = NIL THEN GenCall(callReg, x.adr, 0, node) (* no parameter *)
				ELSE
					GenCall(callReg, x.adr, param.adr, node);
					EndCall(proc, NIL)
				END
			ELSE
				load(x);
				param := x.typ.link; 
				IF param = NIL THEN GenCall(callReg, x.adr, 0, node) (* no parameter *)
				ELSE GenCall(callReg, x.adr, param.adr, node);
					EndCall(proc, NIL)
				END
			END
		END
	END Call;
	
	PROCEDURE PopResult* (n: OPT.Node; VAR z: Item);
	BEGIN
		IF n # NIL THEN (* result into ST(0) or EAX *)
			IF (n.typ.form = ProcTyp) & (n.typ.sysflag = delegate) THEN
				z.typ := delegateType; z.mode := Reg; z.adr := pc; z.descReg := pc-1;
				GenPopReg (OPL.useEAX, OPT.linttyp.form);
				OPL.Instr[pc-1].src1 := z.descReg;
				INC(OPL.Instr[pc-1].op, 5);	(*LInt -> HInt size *)
			ELSIF n.typ.form IN {Byte..LInt, Set, Pointer, ProcTyp} THEN
				z.typ := n.typ; z.mode := Reg; z.adr := pc;
				GenPopReg (OPL.useEAX, z.typ.form)
			ELSIF n.typ.form = HInt THEN
				z.typ := n.typ; z.mode := Reg; z.adr := pc; z.offs := pc-1;
				GenPopReg (OPL.useEAX, OPT.linttyp.form);
				OPL.Instr[pc-1].src1 := z.offs;
				INC(OPL.Instr[pc-1].op, 5);	(*LInt -> HInt size *)
			ELSIF n.typ.comp IN {StaticArr, SDynArr, Record} THEN
				GenPopReg (OPL.noHint, 0) (* no result, already copied *)
			ELSE (* z.typ.form IN realSet *)
				ASSERT (n.typ.form IN realSet);
				z.typ := n.typ; z.mode := Reg; z.adr := pc;
				GenPopReg (OPL.useST, z.typ.form) (* top of stack contains result *)
			END
		ELSE
			GenPopReg (OPL.noHint, 0) (* no result *)
		END
	END PopResult;

	PROCEDURE AllocSDynArr*(VAR proc: OPT.Object);
		VAR locals: OPT.Object; t, t0, size, len, x, adj, shift: Item;
	BEGIN
		locals:=proc.scope.scope;
		WHILE locals#NIL DO
			IF (locals.typ.comp = SDynArr)  THEN
				x.mode := Var; x.typ := locals.typ; x.adr := locals.linkadr; x.node :=  NIL; x.mnolev := locals.mnolev;	(*SDArr*)
				MakeVar(len, locals.typ.link);  GenDimTrap(len);
				ArrayBaseSize(size, x);
				IF (len.mode=Con)&(size.mode=Con) THEN  size.adr:=size.adr*len.adr  ELSE  t := size;  Mul(size, t, len, LInt)  END;
				ASSERT(size.mode IN {Con, Reg}, 130);
				MakeCon(adj, OPT.linttyp, 3); t0:=size; Gen3(add, size, t0, adj);
				MakeCon(shift, OPT.linttyp, 2); t0:=size; Gen3(sar, size, t0, shift);
				Gen0(clear); OPL.Instr[pc-1].src1:=size.adr;			
				t := Stack; Move (x, t)
			END;
			locals:=locals.link
		END
	END AllocSDynArr;
	
	PROCEDURE Enter* (proc: OPT.Object; dataSize: LONGINT; node: OPT.Node);
		VAR par: OPT.Object; x, z, t0, t1, size: Item; step, scale: SHORTINT;  useRef: BOOLEAN;
	BEGIN (* !!later due to a bug this procedure looks no longer very nice *)
		useRef := (proc # NIL) & (proc.sysflag # 0);
		IF proc # NIL THEN 
			OPL.FixupLocalProcCall (proc); (* fixup local procedure calls and assign target pc to procedure *)
			par := proc.link
		ELSE par := NIL;
		END;
		Gen1 (enter, dataSize, node);
		WHILE par # NIL DO (* copy val parameter SDynArr, OpenArr *)
			IF par.mode = Var THEN
				IF (par.typ.comp IN {OpenArr, SDynArr}) THEN
					MakeVar(x, par);
					TypeSize(x, size, step, scale);
					ASSERT(step IN {OPO.Bit8, OPO.Bit16, OPO.Bit32});
					ASSERT(scale IN {OPO.Scale1, OPO.Scale2, OPO.Scale4});
					load(size);
					ASSERT(size.mode=Reg);
					Gen2(neg, t0, size);
					z.mode:=RegRel; z.adr:=ESP; z.inx:=t0.adr; z.scale:=scale; z.typ:=OPT.linttyp;
					loadAdr(z); OPL.Instr [pc-1].hint := OPL.useESP;
					IF step # OPO.Bit32 THEN			(*clear the last 2 bits -> grows down!*)
						z.typ := OPT.linttyp;
						MakeCon(t0, OPT.linttyp, -4);  t1 := z; Gen3 (and, z, t1, t0); OPL.Instr [pc-1].hint := OPL.useESP
					END;
					MoveBlock(z, x, size, step);
					MakeVar(x, par); x.typ := OPT.linttyp;  z.mode:=Reg; z.adr:=ESP; Move(x, z)
				ELSIF par.typ.comp = DynArr THEN
					MakeCon(x, OPT.linttyp, 0); GenPush(x); (*allocate*)
					MakeVar(z, par);
					x.mode:=RegRel; x.adr:=ESP; x.offs:=0; x.inx:=none; x.typ:=par.typ; x.descReg:=none;
					CopyDynArr(x, z);
					GenPop(x);
					MakeVar(z, par); Move(z, x);
				ELSIF useRef & (par.typ.comp IN {StaticArr, Record}) THEN (* copy array, record *)
					z.mode := Var; z.typ := OPT.linttyp; z.node := NIL; z.adr := par.linkadr; z.mnolev := par.mnolev;
					x.mode := VarPar; x.typ := OPT.linttyp; x.adr := par.adr; x.node := NIL; x.mnolev := par.mnolev;
					MakeCon (size, OPT.linttyp, par.typ.size);
					MoveBlock (z, x, size, OPO.Bit8)
				END
			END;
			par := par.link
		END
	END Enter;

	PROCEDURE Return* (VAR res: Item; proc: OPT.Object); (* RETURN res *)
		VAR res1, t, size, negsize: Item; pReg: LONGINT; procform: SHORTINT; typ: OPT.Struct;
			tos, sp, ref, t1: Item; step, scale: SHORTINT;
			savedPC, savedFP, callerTOS: Item;
	BEGIN
		typ := proc.typ;  procform:=typ.form;
		IF res.mode = Coc THEN
			t := res;
			IF (t.offs = Nil) & (t.inx = Nil) THEN
				MoveCoc (res, t); OPL.Instr [res.adr].hint := OPL.useEAX
			ELSE
				MoveCoc (res, t);
				ASSERT (OPL.Instr [pc-2].op = phi);
				pReg := OPL.Instr [pc-2].src1;
				OPL.Instr [pReg].hint := OPL.useEAX
			END
		ELSE
			IF (res.typ.form = NoTyp) OR (res.mode IN {XProc, LProc}) THEN (* RETURN procedure *)
				IF res.mnolev = 0 THEN (* local procedure assignment *)
					GenLoadProc (ldProc, res, res.node.obj.adr MOD 10000H, res.node)
				ELSE
					GenLoadProc (ldXProc, res, res.node.obj.adr DIV 10000H, res.node)
				END;
				IF typ.sysflag = delegate THEN
					MakeCon(t1, OPT.linttyp, 0); load(t1); res.descReg := t1.adr
				END
			ELSIF (procform # res.typ.form) & (res.typ.form # NilTyp) THEN
				ASSERT (procform # Set);
				Convert (res, procform)
			END;
			IF res.typ.form IN realSet THEN loadf (res)
			ELSIF typ.comp IN {OpenArr, SDynArr} THEN
					(* The open array to be returned is copied to the TOS of the caller. (it's a pointer, because it's may be somewhere else)
						stack layout: (!!! place for dim+ref is preallocated by the caller !!!)
							dimensions
							(ref) pointer to data
							data
							(link) link to caller TOS
						for this, the return address and ebp' must be saved and the SP pointer must be set big enough
						to avoid that the temporary data is destroyed.
					*)
					(* prepare callerTOS *)
				callerTOS.mode:=RegRel; callerTOS.adr:=FP; callerTOS.offs:=proc.conval.intval; callerTOS.inx:=none; callerTOS.typ:=OPT.linttyp;
				load(callerTOS); sp:=callerTOS;
					(*push the dimensions at 0[callerTOS] *)
				sp.mode:=RegRel; sp.offs:=0;
				PushArrLen(proc(*formal*), res(*actual*), sp, TRUE);
					(*allocate pointer to the data [ref]*)
				DEC(sp.offs, 4); ref:=sp;
					(*compute array size, align to 4, reserve stack*)
				TypeSize(res, size, step, scale);
				IF size.mode=Con THEN
					MakeCon(negsize, OPT.linttyp, -size.adr - (-size.adr MOD 4));
					INC(sp.offs, negsize.adr);
					IF res.mode#Var THEN load(negsize) END;	(*only if needed!*)
				ELSE
					load(size); negsize.typ:=OPT.linttyp; Gen2(neg, negsize, size);
					IF (step IN {OPO.Bit8, OPO.Bit16}) THEN
						MakeCon(t, OPT.linttyp, -4); t1:=negsize; Gen3(and, negsize, t1, t);	(* negsize AND FFFFFFF7 *)
					END;
					sp.inx:=negsize.adr; sp.scale:=scale;
				END;
					(* if the returned value is not local, allocate stack for it *) 
				IF res.mode#Var THEN
					t:=Stack; t.mode:=RegRel; t.offs:=-12; t.inx:=negsize.adr; t.scale:=scale;	(* LEA SP, -12[SP][size*scale]  -12 to cover the dims, ref and link*)
					loadAdr(t); OPL.Instr[pc-1].hint:=OPL.useESP
				END;
					(* assign pointer to data [ref] *)
				loadAdr(sp); t:=sp; GenStore(store, ref, t);
				sp.mode:=RegRel; sp.offs:=0; sp.inx:=none;	(*load current sp, frees the register with negsize*)
					(* save PC' / EBP' *)
				savedFP.mode:=RegRel; savedFP.adr:=FP; savedFP.offs:=0; savedFP.inx:=none; savedFP.typ:=OPT.linttyp;
				load(savedFP); GenPush(savedFP);
				savedPC.mode:=RegRel; savedPC.adr:=FP; savedPC.offs:=4; savedPC.inx:=none; savedPC.typ:=OPT.linttyp;
				load(savedPC); GenPush(savedPC);
					(* copy the result *)
				t:=sp; MoveBlockReversed(t, res, size, step);
					(* store link to previous block / callerTOS; PC'/EBP' *)
				t:=sp; DEC(t.offs, 4); GenStore(store, t, callerTOS);
				t:=sp; DEC(t.offs, 8); GenPop(savedPC); GenStore(store, t, savedPC);
				t:=sp; DEC(t.offs, 12); GenPop(savedFP); GenStore(store, t, savedFP);
					(* set the new SP *)
				DEC(sp.offs, 12); loadAdr(sp); OPL.Instr[pc-1].hint:=OPL.useESP
				;ASSERT(sp.typ=OPT.linttyp)
			ELSIF typ.comp = DynArr THEN
				t.mode := RegRel; t.adr := FP; t.offs := proc.conval.intval; t.typ := res.typ; t.inx := none;
				load(t); t.mode:=RegRel; t.offs:=0;
				IF res.mode=Var THEN	(*local, no need to copy it, return the var self*)
					Move(t, res)
				ELSE
					CopyDynArr(t, res)
				END
			ELSIF typ.form = Comp THEN
				ASSERT(typ.comp # DynArr);
				t.mode := RegRel;
				t.adr := FP; t.offs := proc.conval.intval; t.typ := res.typ; t.inx := none;
				load(t);
				IF typ.comp = Record THEN
					size.mode := RegRel; size.adr := FP; size.offs := proc.conval.intval+4;
					size.inx := none; size.typ := OPT.linttyp
				ELSE
					MakeCon(size, OPT.linttyp, typ.size)
				END;
				MoveBlock(t, res, size, OPO.Bit8)
			ELSIF typ = OPT.hinttyp THEN
				IF res.mode = Reg THEN
					OPL.Instr[res.adr].hint := OPL.useEAX;
					OPL.Instr[res.offs].hint := OPL.useEDX
				ELSE
					res.typ := OPT.linttyp;
					loadAdr(res); res.mode := RegRel; res1 := res;  INC(res1.offs, 4);
					load(res); OPL.Instr[res.adr].hint := OPL.useEAX;
					load(res1); OPL.Instr[res1.adr].hint := OPL.useEDX
				END
			ELSIF (typ.form = ProcTyp) & (typ.sysflag = delegate) THEN
				IF res.mode = Con THEN
					load(res);
					MakeCon(t1, OPT.linttyp, 0); load(t1); res.descReg := t1.adr
				ELSE
					load(res)
				END;
				OPL.Instr[res.adr].hint := OPL.useEAX;
				OPL.Instr[res.descReg].hint := OPL.useEDX
			ELSE
				load (res);
				OPL.Instr [res.adr].hint := OPL.useEAX
			END
		END
	END Return;
	
	PROCEDURE Exit* (proc: OPT.Object);
		VAR size: LONGINT; ebp: Item;
	BEGIN
		IF proc = NIL THEN (* from module *)
			Gen1 (leave, 0, NIL);
			Gen1 (ret, 0, NIL)
		ELSIF proc.typ.comp IN {OpenArr, SDynArr} THEN
			ebp.typ:=OPT.linttyp;
			GenPop(ebp); OPL.Instr [pc-1].hint := OPL.useEBP;
			Gen1 (ret, 0, NIL);
		ELSE (* procedure *)
			Gen1 (leave, proc.conval.intval2, NIL);
			IF proc.sysflag = cdecl THEN
				size := 0
			ELSIF (proc.mode=5(*Typ*)) OR (proc.typ.form # Comp) THEN size := proc.conval.intval - 8
			ELSIF proc.typ.comp = Record THEN size := proc.conval.intval - 8 + 8
			ELSE size := proc.conval.intval - 8 + 4
			END;
			Gen1 (ret, size, NIL)
		END
	END Exit;

	PROCEDURE Lock*(self, excl: Item);		(* active only *)
	BEGIN
		(* push address of the record *)
		IF self.typ.comp = Record THEN loadAdr (self) ELSE (*pointer*) load (self) END;
		GenPush (self);
		GenPush (excl);	(* -> don't load (excl) because it's a boolean constant. This generates better code *)
		GenCall (xcall, OPL.LockIndex * 10000H + OPL.LockEntryNr, 4, NIL);
	END Lock;
	
	PROCEDURE Unlock*(self, excl: Item);		(* active only *)
	BEGIN
		(* push address of the record *)
		IF self.typ.comp = Record THEN loadAdr (self) ELSE (*pointer*) load (self) END;
		GenPush (self);
		GenPush (excl);	(* -> don't load (excl) because it's a boolean constant. This generates better code *)
		GenCall (xcall, OPL.UnlockIndex * 10000H + OPL.UnlockEntryNr, 4, NIL);
	END Unlock;

	PROCEDURE Await*(z, self, y: Item);	(* active only *)
	BEGIN
		IF z.typ = OPT.niltyp THEN
			MakeCon(z, OPT.linttyp, -1)
		ELSE
			GenLoadProc(ldProc, z, z.node.obj.adr MOD 10000H, z.node);		(* !! z is a local procedure !! *)
		END;
		GenPush(z);
		z.mode := Reg; z.adr := FP; GenPush(z);
		IF self.mode # Con THEN
		(* push address of the record *)
			IF self.typ.comp = Record THEN loadAdr (self) ELSE (*pointer*) load (self) END
		END;
		GenPush(self);
		GenPush(y);
		GenCall(xcall, OPL.AwaitIndex * 10000H + OPL.AwaitEntryNr, 8, NIL);
	END Await;

	PROCEDURE Trap* (n: LONGINT; node: OPT.Node); (* HALT (n) *)
	BEGIN
		Gen1 (trap, n, node)
	END Trap;

	PROCEDURE GenAsm* (n: OPT.Node);		(* iASM *)
	BEGIN
		Gen1(assembler, 0, n)
	END GenAsm;
	
	PROCEDURE GenDimTrap* (VAR len: Item);
		VAR const: Item;
	BEGIN
		IF (OPM.inxchk IN OPM.options) THEN
			MakeCon (const, OPT.linttyp, -1);
			load (len);
			GenFlags (cmp, len, const);
			Gen1 (tle, OPL.DimTrap , NIL)
		END
	END GenDimTrap;

	PROCEDURE Case* (VAR x: Item; low, high: LONGINT; VAR tab: LONGINT; VAR L: Label; node: OPT.Node);
	(* optimize the case where CASE expr and expr is constant! *)
		VAR c, y: Item;
	BEGIN
		MakeCon (c, OPT.linttyp, low);
		IF x.typ.form # LInt THEN
			IF x.mode = Con THEN 
				x.typ := OPT.linttyp;
				load (x)
			ELSE Convert (x, LInt)
			END
		ELSE load (x)
		END;
		IF low # 0 THEN
			Gen3 (sub, x, x, c)
		END;
		c.adr := high-low;
		GenFlags (cmp, x, c);
		L := -2-pc; Gen1 (ja, Nil, node);
		OPL.AllocCaseTab (low, high, tab);
		c.mode := Abs; c.typ := OPT.linttyp; c.adr := tab; c.inx := x.adr; c.scale := OPO.Scale4; c.node := NIL;
		GenLoad (ld, y, c);
		Gen1 (jmpReg, y.adr, node)
	END Case;
	
	PROCEDURE CaseFixup* (tab: LONGINT; elseLabel: Label; len: LONGINT); (* case *)
	BEGIN
		InitInstr (case, 0, 0, NIL);
		OPL.Instr [pc].src1 := tab; OPL.Instr [pc].src2 := elseLabel; OPL.Instr [pc].inx := len * 4;
		INC (pc)
	END CaseFixup;
	
BEGIN
	MakeCon (True, OPT.booltyp, true);
	MakeCon (False, OPT.booltyp, false);
	Stack.mode := Reg; Stack.adr := ESP; Stack.node := NIL; Stack.typ := OPT.linttyp; Stack.offs := 0; Stack.inx := none;
	ebp.mode := Reg; ebp.adr := FP; ebp.node := NIL; ebp.typ := OPT.linttyp;
	formTab[Undef] := 0;
	formTab[Byte] := OPO.Bit8 DIV 8; formTab[Bool] := OPO.Bit8 DIV 8; 
	formTab[Char] := OPO.Bit8 DIV 8; formTab[SInt] := OPO.Bit8 DIV 8;
	formTab[Int] := OPO.Bit16 DIV 8;
	formTab[LInt] := OPO.Bit32; formTab[Set] := OPO.Bit32;
	formTab[Pointer] := OPO.Bit32; formTab[ProcTyp] := OPO.Bit32; 
	formTab[NilTyp] := OPO.Bit32; formTab[Comp] := OPO.Bit32;
	formTab[Real] := 3;
	formTab[LReal] := 4;
	CCtab[0,0] := EQ; CCtab [0,1] := NE; CCtab [0,2] := LT; CCtab [0,3] := LE; CCtab [0,4] := GT; CCtab [0,5] := GE;
	CCtab[1,0] := EQ; CCtab [1,1] := NE; CCtab [1,2] := BL; CCtab [1,3] := BE; CCtab [1,4] := AB; CCtab [1,5] := AE;
	InvCCtab [0] := NE; InvCCtab [1] := EQ; InvCCtab [2] := GE; InvCCtab [3] := GT; InvCCtab [4] := LE; InvCCtab [5] := LT;
	InvCCtab [6] := BE; InvCCtab [7] := BL; InvCCtab [8] := AE; InvCCtab [9] := AB; InvCCtab [10] := CC; InvCCtab [11] := CS;
	delegateType := OPT.NewStr(ProcTyp, Basic); delegateType.BaseTyp := OPT.notyp; delegateType.link := NIL;
	delegateType.sysflag := delegate
END OPC.
