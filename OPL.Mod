(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

(* OPL - Low-Level Code Generator (translation from Pseudo RISC to i80386) (back end) *)
(* NM, rml, prk *)


MODULE OPL;	(** non-portable *)
	IMPORT OPT, OPO, OPM, SYSTEM;
	
	CONST
		NewRef = TRUE;
		Experimental = TRUE;
		
		Reg= OPO.Reg; Abs = OPO.Abs; RegRel =OPO.RegRel; Coc = OPO.Coc;
(*
Opcodes of the pseudo risc machine
 
	    op size: op MOD 8:	0	DWord (= Bit32 DIV 8)
	  	1	Word (= Bit16 DIV 8)
		2	Byte (= Bit8 DIV 8)
		3	Float
		4	DFloat
		5	QWord ( = Bit64 DIV 8)

	    op mode: (op DIV 8) MOD 4:	0	Register to Register (RegReg)
		1	Register to Memory (RegMem)
		2	Memory to Register (MemReg)
		3	Immediate to Register (ImmReg)

opcode < 0: dead code

 Code	Meaning	op	dest	src1	src2	inx

ld z,x	mov z,x	32	reg	base/reg	const/disp/adr	reg
ldbdw z,x	movsx z,x byte to dword sign ext.	64	reg	base/reg	disp/adr	reg
ldwdw z,x	movsx z,x word to dword sign ext.	96	reg	base/reg	disp/adr	reg
ldbw z,x	movsx z,x byte to word sign ext.	128	reg	base/reg	disp/adr	reg
ldbdwu z,x	movzx z,x byte to dword zero ext.	160	reg	base/reg	disp/adr	reg
ldwdwu z,x	movzx z,x word to dword zero ext.	192	reg	base/reg	disp/adr	reg
ldbwu z,x	movzx z,x byte to word zero ext.	224	reg	base/reg	disp/adr	reg
getReg z,x	mov z,x used for SYSTEM.GETREG	256	reg	base	disp/adr	reg
putReg z,x	mov z,x used for SYSTEM.PUTREG	288	reg	base/reg	const/disp/adr	reg
ldProc z,x	mov z,x load procedure	320	reg      entry number * 10000H   -	-
ldXProc z,x	mov z,x load external procedure	352	reg      link index * 10000H -	-
lea z,x	z := ADR (x)	384	reg	base	disp/adr	reg
store z,x	mov z,x	416	reg	base	disp/adr	reg

push z	push z	448	-	reg/const	-	-
pop z	pop z	480	reg	-	-	-

add z,x,y	z := x+y (integer addition)	512	reg	reg	reg/const	-
sub z,x,y	z := x-y (integer subtraction)	544	reg	reg	reg/const	-
mul z,x,y	z := x*y (integer multiplication)	576	reg	reg	reg/const	-
div z,x,y	z := x DIV y	608	reg	reg	reg/const	-
mod z,x,y	z := x MOD y	640	reg	reg	reg/const	-
neg z,x	z :=  -x (integer uniary -)	960	reg	reg	-	-
abs z,x	z := ABS (x)	992	reg	reg	-	-

or z,x,y	z := x OR y	672	reg	reg	reg/const	-
xor z,x,y	z := x XOR y	704	reg	reg	reg/const	-
and z,x,y	z := x AND y	736	reg	reg	reg/const	-
not z,x	z := NOT x	1024	reg	reg	-	-

bt x,y	bit test: y bit in x	1088	-	reg	reg/const	-
btr z,x,y	bit test and reset: z := x clear bit y	768	reg	reg	reg/const	-
bts z,x,y	bit test and set: z := x set bit y	800	reg	reg	reg/const	-
test x,y	x and y, affects condition flags	3424	-	reg	reg/const	-

sal z,x,y	z := x shift arithmetic left y times	832	reg	reg	reg/const	-
sar z,x,y	z := x shift arithmetic right y times	864	reg	reg	reg/const	-
shr z,x,y	z := x shift right y times	896	reg	reg	reg/const	-
rol z,x,y	z := x rotate left (y MOD 32) times	928	reg	reg	reg/const	-

cmp x,y	x-y, only condition flags are affected	1056	-	reg	reg/const	-
je pc	jump if equal	1504	-	-	pc	-
jne pc	jump if not equal	1536	-	-	pc	-
jl pc	jump if less	1568	-	-	pc	-
jle pc	jump if less or equal	1600	-	-	pc	-
jg pc	jump if greater	1632	-	-	pc	-
jge pc	jump if greater or equal	1664	-	-	pc	-
ja pc	jump if above	1696	-	-	pc	-
jae pc	jump if above or equal	1728	-	-	pc	-
jb pc	jump if below	1760	-	-	pc	-
jbe pc	jump if below or equal	1792	-	-	pc	-
jc pc	jump if carry flag set	1824	-	-	pc	-
jnc pc	jump if carry flag cleared	1856	-	-	pc	-
jmp pc	jump always	1888	-	-	pc	-
jmpReg reg	jump indirect	1920	-	-	reg	-

sete z	set z on equal	1120	reg	-	-	-
setne z	set z on not equal	1152	reg	-	-	-
setl z	set z on less	1184	reg	-	-	-
setle z	set z on less or equal	1216	reg	-	-	-
setg z	set z on greater 	1248	reg	-	-	-
setge z	set z on greater or equal	1280	reg	-	-	-
seta z	set z on above	1312	reg	-	-	-
setae z	set z on above or equal	1344	reg	-	-	-
setb z	set z on below	1376	reg	-	-	-
setbe z	set z on below or equal	1408	reg	-	-	-
setc z	set z on carry flag set	1440	reg	-	-	-
setnc z	set z on carry flag cleared	1472	reg	-	-	-
te num	trap if equal	1952	-	-	num	-
tne num	trap if not equal	1984	-	-	num	-
tl num	trap if less		-	-	num	-
tle num	trap if less or equal	2944	-	-	num	-
tg num	trap if greater		-	-	num	-
tge num	trap if greater of equal		-	-	num	-
ta num	trap if above	2016	-	-	num	-
tae num	trap if above or equal	2880	-	-	num	-
to num	trap if overflow	2912	-	-	num	-
trap num	trap always	2048	-	-	num	-

call pc	call procedure	2080	-	parSize	pc	-
callReg reg	call indirect (method call)	2112	-	parSize	reg	-
xcall link-index	call external procedure	2144	-	parSize	link index	-
ret parSize	return from subroutine	2176	-	-	parSize	-
enter locSize	procedure prolog	2208	-	-	locSize	-
leave locSize	procedure epilog	2240	-	-	locSize	-

cld	clear direction flag	2272	-	-	-	-
repMovs	move strings	2304	destAdr	srcAdr	nofElem	size
cmpString z,x	compare string	2336	-	src1Adr	src2Adr	-
pushReg 	save register	2368	reg	-	-	-
popReg	restore register	2400	reg	-	-	-
case	end of case statement	2432	-	TabAdr	ElsePC	size
short z, x		2976	reg	reg	-	-
entier z,x	z := ENTIER (x)	3104	reg	freg	-	-
phi	src1 and src2 to the same registers	2464	-	reg	reg	-
label		2496	-	-	-	-
cli	clear interrupt	3168	-	-	-
sti	set interrupt	3200	-	-	-
in	port in	3232	-	-	-
out	port out	3264	-	-	-
assembler	assembler code	3296
clear	clearing sdyn array	3328
std	set direction flag	3392	-	-	-	-

fload z,x	floating point load	2528	freg	base	disp/adr	reg
fstore z,x	floating point store	2560	freg	base	disp/adr	reg
fist z,x	z := ENTIER (x)	2592	freg (x)	base	disp/adr	reg
fild z,x	load integer z := x	2624	freg (x)	base	disp/adr	reg
fadd z,x,y	z := x+y floating point addition	2656	freg	freg	freg	-
fsub z,x,y	z := x-y floating point subtraction	2688	freg	freg	freg	-
fmul z,x,y	z := x*y floating point multiplication	2720	freg	freg	freg	-
fdiv z,x,y	z := x/y	2752	freg	freg	freg	-
fabs z,x	z := ABS (x)	2784	freg	freg	-	-
fchs z,x	z := -x	2816	freg	freg	-	-
fcmp x,y	floating point compare	2848	-	freg	freg	-
newStat	begin of a new statement	3136	-	text pos	-	-
*)	

	ld* = 32;	ldbdw* = 64;	ldwdw* = 96;	ldbw* = 128;	
	ldbdwu* = 160;	ldwdwu* = 196;	ldbwu* = 224;	getReg* = 256 ;
	putReg* = 288;	ldProc* = 320;	ldXProc* = 352;	lea* = 384;	
	store* = 416;	push* = 448;	pop* = 480;	add* = 512;	
	sub* = 544;	mul* = 576;	div* = 608;	mod* = 640;	
	neg*= 960;	abs* = 992;	cmp* = 1056;	je* = 1504;	
	jne* = 1536;	jl* = 1568;	jle* = 1600;	jg* = 1632;	
	jge* = 1664;	ja* = 1696;	jae* = 1728;	jb* = 1760;	
	jbe* = 1792;	jc* = 1824;	jnc* = 1856;	jmp* = 1888;	
	jmpReg* = 1920;	sete* = 1120;	setne* = 1152;	setl* = 1184;	
	setle* = 1216;	setg* = 1248;	setge* = 1280;	seta* = 1312;	
	setae* = 1344;	setb* = 1376;	setbe* = 1408;	setc* = 1440;	
	setnc* = 1472;	te* = 1952;	tne* = 1984;	tle* = 2944;
	ta* = 2016;	tae* = 2880;	to* = 2912;	
	trap* = 2048;	or* = 672;	xor* = 704;	and* = 736;	
	not* = 1024;	bt* = 1088;	btr* = 768;	bts* = 800;	test* = 3424;
	call* = 2080;	callReg* = 2112;	xcall* = 2144;	ret* = 2176;	
	enter* = 2208;	leave* = 2240;	sal* = 832;	sar* = 864;	
	shr* = 896;	rol* = 928;	cld* = 2272;	repMovs* = 2304;	
	cmpString* = 2336;	pushReg* = 2368;	popReg* = 2400;	case* = 2432;	
	short* = 2976;	phi* = 2464;	label* = 2496;	entier* = 3104;
	cli* = 3168;	sti* = 3200;	in* = 3232;	out* = 3264;
	assembler* = 3296;
	clear*= 3328;	std*= 3392;

	(* floating point *)
	fload*= 2528;	fstore* = 2560;	fist*= 2592;	fild* = 2624;
	fadd* = 2656;	fsub* = 2688;	fmul* = 2720;	fdiv* = 2752;
	fabs* = 2784;	fchs* = 2816;	fcmp* = 2848;

	newStat* = 3136;
	
	(* short form *)
	Ld = ld DIV 32;	Ldbdw = ldbdw DIV 32;	Ldwdw = ldwdw DIV 32;	Ldbw = ldbw DIV 32;	
	Ldbdwu* = ldbdwu DIV 32;	Ldwdwu* = ldwdwu DIV 32;   Ldbwu* = ldbwu DIV 32;	GETreg* = getReg DIV 32;
	PUTreg* = putReg DIV 32;	LdProc = ldProc DIV 32;	LdXProc = ldXProc DIV 32;	Lea = lea DIV 32;	
	Sto = store DIV 32;	Push = push DIV 32;	Pop = pop DIV 32;	Add = add DIV 32;	
	Sub = sub DIV 32;	Mul = mul DIV 32;	Div = div DIV 32;	Mod = mod DIV 32;	
	Neg= neg DIV 32;	Abso = abs DIV 32;	Cmp = cmp DIV 32;	Je = je DIV 32;	
	Jne = jne DIV 32;	Jl = jl DIV 32;	Jle = jle DIV 32;	Jg = jg DIV 32;	
	Jge = jge DIV 32;	Ja = ja DIV 32;	Jae = jae DIV 32;	Jb = jb DIV 32;	
	Jbe = jbe DIV 32;	Jc = jc DIV 32;	Jnc = jnc DIV 32;	Jmp = jmp DIV 32;	
	JmpReg = jmpReg DIV 32;	Sete = sete DIV 32;	Setne = setne DIV 32;	Setl = setl DIV 32;	
	Setle = setle DIV 32;	Setg = setg DIV 32;	Setge = setge DIV 32;	Seta = seta DIV 32;	
	Setae = setae DIV 32;	Setb = setb DIV 32;	Setbe = setbe DIV 32;	Setc = setc DIV 32;	
	Setnc = setnc DIV 32;	Te = te DIV 32;	Tne = tne DIV 32;	Tle = tle DIV 32;
	Ta = ta DIV 32;	Tae = tae DIV 32;	To = to DIV 32;
	Trap = trap DIV 32;	oR = or DIV 32;	Xor = xor DIV 32;	And = and DIV 32;	
	Not = not DIV 32;	Bt = bt DIV 32;	Btr = btr DIV 32;	Bts = bts DIV 32;	Test = test DIV 32;
	Call = call DIV 32;	CallReg = callReg DIV 32;	Xcall = xcall DIV 32;	Ret = ret DIV 32;	
	Enter = enter DIV 32;	Leave = leave DIV 32;	Sal = sal DIV 32;	Sar = sar DIV 32;	
	Shr= shr DIV 32;	Rol = rol DIV 32;	Cld = cld DIV 32;	RepMovs = repMovs DIV 32; 
	CmpString = cmpString DIV 32; PushReg = pushReg DIV 32;	PopReg = popReg DIV 32;	Case= case DIV 32;
	Short* = short DIV 32;	Phi = phi DIV 32 ;	Label = label DIV 32;	Entier = entier DIV 32;
	Cli = cli DIV 32;	Sti = sti DIV 32;	In = in DIV 32;	Out = out DIV 32;
	Assembler = assembler DIV 32;
	Clear = clear DIV 32; Std = std DIV 32;

	(* floating point *)
	FLoad= fload DIV 32;	FStore = fstore DIV 32;	Fist= fist DIV 32;	Fild = fild DIV 32;
	Fadd = fadd DIV 32;	Fsub = fsub DIV 32;	Fmul = fmul DIV 32;	Fdiv = fdiv DIV 32;
	Fabs= fabs DIV 32;	Fchs = fchs DIV 32;	Fcmp = fcmp DIV 32;

	NewStat = newStat DIV 32;
	(*
	Intel Oberon-2 Objectfile Format 

	ObjectFile 	=	Header VarEntries Entries Commands Pointers Imports VarConsLinks Links
			Data Code Types References.
	Header	=	ObjectTag Version refadr32 nofVarEntries16 nofCommands16 nofPointers16 
			nofTypes16 nofImports16 nofVarConsLinks16 nofLinks16 datasize16 constsize16 
			codesize16 key32 modulenamestring.
	VarEntries	=	VarEntryTag {offset32}.
	Entries	=	EntryTag {entry16}.
	Commands	=	CommandTag {Command}.
	Command	=	namestring entry16.
	Pointers	=	PointerTag {offset32}.
	Imports	=	ImportTag {Import}.
	Import	=	{key4 namestring}.
	VarConsLinks	=	VarConsLinkTag {VarConsLink}.
	VarConsLink	=	modulenumber8 entrynumber16 noffixups16 {offset16}.
	Links	=	modulenumber8 entrynumber16 offset16.
	Data	=	DataTag {byte8}.
	Code	=	CodeTag {byte8}.
	Types	=	recordsize32 typedescEntryNr16 basetypmod16 basetypeEntryNr16 
			nofmthods16 nofinhmethods16 nofnewmethods16 nofpointers16 
			namestring {NewMethod} {pointeroffset32}.
	References	=	ReferenceTag {ProcRef}.
	ProcRef	=	ProcTag offsetnum namestring {VarRef}.
	VarRef	=	(VarTag | VarParTag) TypeForm offsetnum namestring.
	TypeForm	=	ByteTag | BoolTag | CharTag | SIntTag | IntTag | LIntTag | RealTag |
			LRealTag | SetTag | PointerTag | ArrayTag.
	ObjectTag	=	0F8X8.
	ProcTag	=	0F8X8.
	Version	=	036X8.
	EntryTag	=	082X8.
	CommandTag	=	083X8.
	PointerTag	=	084X8.
	ImportTag	=	085X8.
	LinkTag	=	086X8.
	DataTag	=	087X8.
	CodeTag	=	088X8.
	TypeTag	=	089X8.
	ReferenceTag	=	08BX8.
	VarEntryTag	=	08CX8.
	VarConsLinkTag	=	08DX8.
	VarTag	=	1X8.
	VarParTag	=	3X8.
	ByteTag	=	1X8.
	BoolTag	=	2X8.
	CharTag	=	3X8.
	SIntTag	=	4X8.
	IntTag	=	5X8.
	LIntTag	=	6X8.
	RealTag	=	7X8.
	LRealTag	=	8X8.
	SetTag	=	9X8.
	PointerTag	=	0DX8.
	ArrayTag	=	0FX8.

Notes All numbers are unsigned values! 
Header: 
	datasize, constsize and codesize are measured in bytes.

VarConsLinks:noffixups contains the number of offsets which follows immediatly. Module number refers to the modules in the import list, where the first imported module is number 1. The number 0 is the compiled module itself. The following entry is predefined:

modulenumber    entrynumber     meaning
	00	0FFFFH	global variables and constants in the compiled module

Links:Modulenumber refers to the modules in the import list, where the first imported module is number 1. The number 0 is the compiled module itself. Five entry-numbers are predefined:modulenumber    entrynumber	meaning
	00	255 (0FFH)	case table fixup in the constant area. Insert absolute address!
	00	254 (0FEH)	local procedure assignment. Insert absolute address!
	00	253 (0FDH)	Kernel.New: NEW (pointer to record)
	00	252 (0FCH)	Kernel.NewSys: SYSTEM.NEW (pointer, nofBytes)
	00	251 (0FBH)	Kernel.NewArr: NEW (pointer to array of Type, dim0, ..., dimn-1 ) 

Data:
	This section is called Data section for historical reasons. It corresponds tho the constant area of an Oberon module.

Types:
basetypemod, basetypeEntryNr refer to the module in which the base type is declared and the entrynumber of that type, respectively. The number 0FFFFH (-1) is used if the type does not have a base type.

References:
	The format num is the portable compactified integer format supported by Files.Read and Files.Write respectivly. 
	The name $$dentifies the body of a module.
*)
	(* Object File Tags *)
		VarEntryTag = 8CX;
		EntryTag = 82X;
		commandTag = 83X;
		pointerTag = 84X;
		importTag = 85X;
		VarConsLinkTag = 8DX;
		LinkTag = 86X;
		DataTag = 87X;

		ExportTag = 88X;
		CodeTag = 89X;
		UseTag = 8AX;
		TypeTag = 8BX;
		RefTag = 8CX;

	(* hints for the pseudo machine *)
		noHint* = -1;
		useEAX* = 0; useECX* = 1; useEDX* = 2; useEBX* = 3; useESP* = 4; useEBP* = 5; useESI* = 6; useEDI* = 7;
		useST* = 8;
		tryEAX* = 16; tryECX* = 17; tryEDX* = 18; tryEBX* = 19; tryESI* = 22; tryEDI* = 23;
 
		useReg = {useEAX, useECX, useEDX, useEBX, useESP, useEBP, useESI, useEDI};
		tryReg = {tryEAX, tryECX, tryEDX, tryEBX, tryESI, tryEDI};

	(* pseudo register *)
		none* = -1; RiscFP* = -2; RiscESP* = -3;
	noScale = OPO.noScale; Scale1 = OPO.Scale1; Scale2 = OPO.Scale2; Scale4 = OPO.Scale4; 
	RegReg 	= OPO.RegReg;	(* register to register *)
	RegMem 	= OPO.RegMem;	(* register to memory *)
	MemReg 	= OPO.MemReg;	(* memory to register *)
	ImmReg 	= OPO.ImmReg;	(* immediate to register *)
	ImmMem 	= OPO.ImmMem;	(* immediate to memory *)
	Nil*	= OPM.LANotAlloc;	(* for Instr[..].pc initialization *)

	(* Traps *)
		WithTrap* = 1; CaseTrap* = 2; FuncTrap* = 3; EqualGuardTrap* = 5; GuardTrap* = 6;
		OverflowTrap* = 4; RangeTrap* = 7; DimTrap* = 9;
		nofTrapFixups = 10;	(* highest trap number + 1 *)

	(* option *)
		PtrInit = 5;

	(* predefined Entry numbers and Link indices. EntrNr = EntryNr - 1 -> EntryNr = 0 does not exist *)
		CaseTabelIndex = 0;	CaseTableEntryNr = 255;
		LocProcAssIndex = 1;	LocProcAssEntryNr = 254;
		NewLinkIndex* = 2;	NewEntryNr* = 253;
		NewSysLinkIndex* = 3;	NewSysEntryNr* = 252;
		NewArrayLinkIndex* = 4;	NewArrayEntryNr* = 251;
		StartIndex* = 5;	StartEntryNr* = 250;
		AwaitIndex* = 6;	AwaitEntryNr* = 249;
		
		LockIndex* = 7;	LockEntryNr* = 247;
		UnlockIndex* = 8;	UnlockEntryNr* = 246;
		InitLinks = 9;	(* Number of special links *)

	TYPE
		Instruction* = RECORD 
			scale*, reg*: SHORTINT;
			op*: INTEGER;
			dest*, src1*, src2*, inx*, pc*, hint*: LONGINT; (* pc: PC on the target machine, used for jumps *)
			link*, used*: INTEGER;
			node*: OPT.Node;
			abs*: BOOLEAN;	(* absolute address, should not be fixed. Def = FALSE. *)		(* GetPut *)
		END;
		InstructionTable* = POINTER TO ARRAY OF Instruction;

		Map* = POINTER TO MapDesc;
		MapDesc* = ARRAY OF RECORD
			pos*, pc* : LONGINT
		END;
		
	VAR
		Instr*:  InstructionTable; (* Pseudo Code *)
		mapSize* : LONGINT;
		map* : Map;

(* Target Code i386 definitions *)

	CONST
		MaxCommands 	= 128;	(* maximum commands in a Module *)
		MaxNewMethods	= 16;	(* maximum new methods *)

		MaxExtensions	= 15;	(* maximum extensions *)

		MaxEntry* = 128;
			(* maximum imported (global) variables and constants allocated in the Const area *)
		LinkLength 	= 512;	(* link length for procedures *)
		MaxSaveLevel	= 32;	(* maximum register pops *)

		(* object modes *)
		Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7; CProc = 9; IProc = 10; TProc = 13;

		(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
		HInt = 16;
		
		(* composite structure forms *)
		Basic = 1; StaticArr = 2; SDynArr = 3; DynArr = 4; OpenArr = 5; Record = 6;

		(* module visibility of objects *)
		internal = 0; external = 1; externalR = 2;
		
		(* object type *)
		hasBody = 1; slNeeded = 3; activeObj = 5;
		
		false = 0; true = 1;
		
		noEntry = -1; (* used in varConsTab and varConsLink *)
		BUG = 41;

		(* i386 Register *)
		EAX = OPO.EAX; ECX = OPO.ECX; EDX = OPO.EDX; EBX = OPO.EBX; 
		ESP = OPO.ESP; EBP = OPO.EBP; ESI = OPO.ESI; EDI = OPO.EDI;  (* 32 bit register *)
		AX = OPO.AX; CX = OPO.CX; DX = OPO.DX; BX = OPO.BX; 
		SP =  OPO.SP; BP = OPO.BP; SI = OPO.SI; DI = OPO.DI;  (* 16 bit register *)
		AL = OPO.AL; CL = OPO.CL; DL = OPO.DL; BL = OPO.BL; 
		AH = OPO.AH; CH = OPO.CH; DH = OPO.DH; BH = OPO.BH;  (* 8 bit register *)

		SplittableReg = {EAX, ECX, EDX, EBX, AX, CX, DX, BX};

		noDisp = OPO.noDisp; Disp8 = OPO.Disp8; Disp32 = OPO.Disp32; 

		(* modes used for code generationg, RegReg, RegMem, MemReg, ImmReg, ImmMem already defined above *)
		RegSt = OPO.RegSt; 	(* floating point st, reg *)
		StReg = OPO.StReg; 	(* floating point reg, st *)
		StRegP = OPO.StRegP;	(* floating point ...p reg, st (with pop *)
		MemSt = OPO.MemSt; 	(* floating point st, mem *)
		(* aliases used for codes with one field like not, neg etc. *)
		Regs = RegReg;
		Mem = MemReg;
		Imme = ImmReg;

		(* register/memory size (8,16, 32 or 64 bit) *)
		Bit8 = OPO.Bit8; Bit16 = OPO.Bit16; Bit32 = OPO.Bit32 (* must be 0 *); Bit64 = OPO.Bit64;

		(* i387 *)
		sReal = OPO.sReal; 	(* short real 32 bit = Bit32 *)
		lReal = OPO.lReal; 	(* long real 64 bit *)
		eReal = OPO.eReal;	(* extended real 80 bit, only valid in GenFLD, GenFSTP *)
		sInt = OPO.sInt;	(* short integer 32 bit *)

		noBase = OPO.noBase; noInx = OPO.noInx; noImm = OPO.noImm;
		free = -1; Occupied = MIN (INTEGER); Splitted = Occupied + 1; (* Register *) 

	(* opcodes used for generating i386 code *)

		(*  GenShiftRot *)
		ROR= OPO.ROR; ROL = OPO.ROL; RCL = OPO.RCL; RCR = OPO.RCR; 
		SHL = OPO.SHL; SAL = OPO.SAL; SHR = OPO.SHR; SAR = OPO.SAR;

		(*  GenString, GenRepString, GenRepCmpsScas *)
		CMPS = OPO.CMPS; INS = OPO.INS; LODS = OPO.LODS; MOVS = OPO.MOVS; 
		OUTS = OPO.OUTS; SCAS = OPO.SCAS; STOS = OPO.STOS;

		(* GenJcc *)
		JO = OPO.JO; JNO = OPO.JNO; JB = OPO.JB; JC = OPO.JC; JNAE = OPO.JNAE;  JNB = OPO.JNB; 
		JNC = OPO.JNC; JAE = OPO.JAE; JE = OPO.JE; JZ = OPO.JZ; JNE = OPO.JNE; JNZ = OPO.JNZ;
		JBE = OPO.JBE; JNA = OPO.JNA; JNBE =OPO.JNBE; JA = OPO.JA; JS = OPO.JS; JNS = OPO.JNS; 
		JP = OPO.JP; JPE = OPO.JPE; JNP = OPO.JNP; JPO = OPO.JPO; JL = OPO.JL;  JNGE = OPO.JNGE; 
		JNL = OPO.JNL; JGE = OPO.JGE; JLE = OPO.JLE; JNG = OPO.JNG; JNLE = OPO.JNLE; JG = OPO.JG;

		(* GenSetcc *)
		SETO = 0; SETNO = 1; SETB = 2; SETNAE = 2; SETAE = 3; SETNB = 3; SETE = 4; SETZ = 4; SETNE = 5; SETNZ = 5;
		SETBE = 6; SETNA = 6; SETNBE = 7; SETA = 7; SETS = 8; SETNS = 9; SETP = 10; SETPE = 10;
		SETNP = 11; SETPO = 11; SETL = 12; SETNGE = 12; SETNL = 13; SETGE = 13; SETLE = 14; SETNG = 14;
		SETNLE = 15; SETG = 15;

		(* GenTyp1 *)
		ADD = OPO.ADD; ADC = OPO.ADC; SUB = OPO.SUB; SBB = OPO.SBB; CMP = OPO.CMP; 
		AND = OPO.AND; Or = OPO.Or; XOR = OPO.XOR;

		(* GenFop1 *)
		FCOMPP = OPO.FCOMPP; FTST = OPO.FTST; FLDZ = OPO.FLDZ; FLD1 = OPO.FLD1; FABS = OPO.FABS; 
		FCHS = OPO.FCHS; FSTSW = OPO.FSTSW; FINCSTP = OPO.FINCSTP; FDECSTP = OPO.FDECSTP;
		
		(* general *)
		SAHF = OPO.SAHF; CLD = OPO.CLD; STD = OPO.STD; CBW = OPO.CBW; CWD = OPO.CWD (* = CDQ *);
		CLI = OPO.CLI; STI = OPO.STI;
		

		(* Export/Use Section *)
		EUEnd = 0X; EURecord = 1X; EUProcFlag = 080000000H;

		(* sysflag *) (* ejz *)
		notag = 1; stdcall = 2; cdecl = 3; untraced = 4; delegate = 5;

	TYPE
		LinkRec = RECORD
			offset, mod, entry: INTEGER;
		END;

		VarConsRec = RECORD
			mod, entry, noflinks, index: INTEGER
		END;
		VarConsTable = POINTER TO ARRAY OF VarConsRec;

		VarConsLinkRec = RECORD
			offset, next: INTEGER
		END;
		VarConsLinkTable = POINTER TO ARRAY OF VarConsLinkRec;
		
		SavedRegRec = RECORD
			reg, sreg, freg: ARRAY 8 OF INTEGER
		END;
		
		PtrTable = POINTER TO ARRAY OF LONGINT;
		RecTable = POINTER TO ARRAY OF OPT.Struct;
		EntryTable = POINTER TO ARRAY OF INTEGER;
		ExpTable = POINTER TO ARRAY OF LONGINT;

	VAR
	ptrTab: PtrTable;	(* pointer table *)
	recTab: RecTable;	(* record table *)
	entry: EntryTable;	(* entry table *)

	varConsLink: VarConsTable;	(* variable / constant link table *)
	link: ARRAY LinkLength OF LinkRec;	(* link table *)
	varConsTab: VarConsLinkTable;	(* variable / constant table *)
	nofVarCons, noVarEntries, nofEntries, (*nofptrs,*) nofVarConsLinks, nofLinks, nofrecs: INTEGER;
	nofptrs: LONGINT;
	ConstErr, RegErr, VarEntryErr, LinkErr: BOOLEAN;

	(* i386 code generator *)
	regTab, sregTab, fregTab: ARRAY 8 OF LONGINT; (* regTab: 32/16 bit; sregTab: 8 Bit; fregTab: floating points *)
	savedRegs: ARRAY MaxSaveLevel OF SavedRegRec;
	nofSavedLevel: INTEGER;	(* number of saved register sets *)	
	ftop: SHORTINT;	(* floating point top of stack *)
	trapFixupTab: ARRAY nofTrapFixups OF LONGINT;
	JmpConvert: ARRAY Jnc-Je+1 OF SHORTINT;
	SetccConvert: ARRAY Setnc - Sete + 1 OF SHORTINT;
	FreeRegDisp: SHORTINT;

	nofStr: INTEGER;
	linkTable*: LONGINT;
	gVarLink*: LONGINT;

	explist: ExpTable; exppos: LONGINT;	(*list of fp. To check for duplicates*)

	PROCEDURE Init*;
	BEGIN
		OPO.CodeErr := FALSE; ConstErr := FALSE;
		VarEntryErr := FALSE; LinkErr := FALSE;
		OPO.dsize := 0; OPO.csize := 0; OPO.pc := 0; noVarEntries := 0; nofptrs := 0; nofVarConsLinks := 0;
		nofrecs := 0; nofEntries := 0; nofSavedLevel := 0;
		OPO.csize := 4;		(*module.SELF*)
		varConsLink [0].noflinks := 0; varConsLink [0].entry := -1; varConsLink [0].noflinks := 0; 
		varConsLink [0].index := noEntry;
		nofVarCons := 1;
		link [0].mod := 0; link [0].entry := CaseTableEntryNr; link [0].offset := Nil;  (* Case table fixup chain *)
		link [1].mod := 0; link [1].entry := LocProcAssEntryNr; link [1].offset := Nil; (* Fixup chain for procedure assignments *)
		link [2].mod := 0; link [2].entry := NewEntryNr; link [2].offset := Nil;           (* Kernel.NewRec (VAR ptr, tag) *)
		link [3].mod := 0; link [3].entry := NewSysEntryNr; link [3].offset := Nil;      (* Kernel.NewSys (VAR ptr, size)  *)
		link [4].mod := 0; link [4].entry := NewArrayEntryNr; link [4].offset := Nil; (* Kernel.NewArray (VAR ptr, nofelems, nofdims, baseTag) *)
		link [5].mod := 0; link [5].entry := StartEntryNr; link [5].offset := Nil; (* Kernel.Start *)
		link [6].mod := 0; link [6].entry := AwaitEntryNr; link [6].offset := Nil; (* Kernel.Await *)
		link [7].mod := 0; link [7].entry := LockEntryNr; link [7].offset := Nil; (* Kernel.Lock *)
		link [8].mod := 0; link [8].entry := UnlockEntryNr; link [8].offset := Nil; (* Kernel.Unlock *)
		nofLinks := InitLinks;
	END Init;

(* register part *)

(* i386 Register *)

	PROCEDURE^ GetThisReg (this: SHORTINT);
	
	PROCEDURE GetReg8 (VAR reg: SHORTINT);
		VAR i: SHORTINT;
	BEGIN
		i := EBX;
		WHILE (i >= EAX) & ~((regTab[i] = Splitted) & ((sregTab[i] = free) OR (sregTab[i+4] = free))) DO DEC (i) END;
		IF i < EAX THEN (* in splitted registers are no 8 bit registers free *)
			i := EBX;
			WHILE (i >= EAX) & (regTab [i] # free) DO DEC (i) END; (* search a free splittable register *)
			IF i < EAX THEN (* no free splittable register *)
				i := EBX; (* look for a splittable register which is unsplitted *)
				WHILE (i >= EAX) & (regTab [i] = Splitted) DO DEC (i) END;
				IF i < EAX THEN
					OPM.err (215); RegErr := TRUE;
					reg := AL; 
					RETURN
				END;
			END;
			GetThisReg (i);
			regTab [i] := Splitted
		ELSIF sregTab [i] # free THEN INC (i,4)
		END;
		sregTab [i] := Occupied;
		reg := i+AL
	END GetReg8;
	
	PROCEDURE GetThisReg8 (this: SHORTINT);
	(* this IN {AL..BH} *)
		VAR i, reg: SHORTINT;
	BEGIN
		ASSERT (this IN {AL..BH});
		reg := this MOD 4; (* = splitted 32/16 bit register *)
		IF (regTab [reg] = Splitted) & (sregTab [this-AL] = free) THEN sregTab [this-AL] := Occupied
		ELSIF regTab [reg] # free THEN
			IF regTab [reg] = Splitted THEN (* 8 bit register is occupied -> move value to another register *)
				GetReg8 (i);
				ASSERT (sregTab [this - AL] >= 0);
				Instr [sregTab [this-AL]].reg := i;
				OPO.GenMOV (RegReg, i, this, noInx, noScale, noDisp, noImm);
				sregTab [i - AL] := sregTab [this-AL];
				sregTab [this-AL] := Occupied
			ELSE
				GetThisReg (reg);
				regTab [reg] := Splitted;	(*regTab [i] := Splitted;		, bug found by C.Steindl, fix by prk *)
				sregTab [this-AL] := Occupied
			END
		ELSE
			regTab [reg] := Splitted;
			sregTab [this-AL] := Occupied
		END
	END GetThisReg8;
	
	PROCEDURE GetSplittableReg (VAR reg: SHORTINT);
	(* returns any splittable register -> EBX, EDX, ECX, EAX *)
		VAR r: SHORTINT;
	BEGIN
		r := EBX;
		WHILE (r >= EAX) & (regTab [r] # free) DO DEC (r) END;
		IF r < EAX THEN
			r := EBX;
			WHILE (r >= EAX) & (regTab [r] = Splitted) DO DEC (r) END;
			IF r < EAX THEN
				OPM.err (215); RegErr := TRUE;
				reg := EAX;
				RETURN
			END;
			GetThisReg (r)
		END;
		regTab [r] := Occupied;
		reg := r
	END GetSplittableReg;
	
	PROCEDURE GetReg (VAR reg: SHORTINT);
	(* returns any free 32 bit register and marks it as occupied *)
		VAR r: SHORTINT;
	BEGIN
		r := EBX;
		WHILE (r >= EAX) & (regTab [r] # free) DO DEC (r) END;
		IF r < EAX THEN
			IF regTab [EDI] = free THEN r := EDI
			ELSIF regTab [ESI] = free THEN r := ESI
			END
		END;
		IF r < EAX THEN
			OPM.err (215); RegErr := TRUE;
			reg := EAX;
			RETURN
		END;
		regTab [r] := Occupied;
		reg := r
	END GetReg;

	PROCEDURE GetThisReg (this: SHORTINT);
	(* marks 'this' as occupied. If the register is not free it will be moved to any free one (with pReg if necessary) *)
		VAR 
			r, reg, r0, r1: SHORTINT;
			pReg: LONGINT;
	BEGIN
		ASSERT (this IN {EAX..DI});
		reg := this MOD 8;
		IF regTab [reg] = Splitted THEN
			regTab [reg] := Occupied;	(*prevent reallocation of the free part of the register, if any*)
			IF (sregTab [reg] = free) OR (sregTab [reg + 4] = free) THEN
				IF sregTab [reg] = free THEN 
					r0 := reg + AL + 4; r1 := reg + 4
				ELSE 
					r0 := reg + AL; r1 := reg
				END;
				GetReg8 (r); OPO.GenMOV (RegReg, r, r0, noInx, noScale, noDisp, noImm);
				sregTab [r - AL] := sregTab [r1]; Instr [sregTab [r1]].reg := r; sregTab [r1] := free
			ELSE
				r := EBX;
				WHILE (r >= EAX) & (regTab [r] # free) DO DEC (r) END; (* search any free, splittable register *)
				IF r < EAX THEN (* no free splittable register *)
					GetReg8 (r0); OPO.GenMOV (RegReg, r0, reg + AL, noInx, noScale, noDisp, noImm); (* move lower 8 bit *)
					GetReg8 (r1); OPO.GenMOV (RegReg, r1, reg + AL + 4, noInx, noScale, noDisp, noImm); 
						(* move higher 8 bit *)
				ELSE
					OPO.GenMOV (RegReg, r, reg, noInx, noScale, noDisp, noImm);
					r0 := r + AL; r1 := r0 + 4; regTab [r] := Splitted;
				END;
				sregTab [r0 - AL] := sregTab [reg + AL]; Instr [sregTab [reg + AL]].reg := r0; sregTab [r0 - AL] := free;
				sregTab [r1 - AL] := sregTab [reg + AL + 4]; Instr [sregTab [reg + AL + 4]].reg := r1; sregTab [r1 - AL] := free
			END;
			(*regTab [reg] := Occupied*)
		ELSIF regTab [reg] # free THEN (* conflict *)
			pReg := regTab [reg];
			ASSERT (pReg >= 0);
			GetReg (r); 
			regTab [r] := pReg;
			INC (r, SHORT ((Instr[pReg].op MOD 8) * 8));
			Instr [pReg].reg := r; (* Instr [regTab [reg]].reg = new register *)
			OPO.GenMOV (RegReg, r, reg, noInx, noScale, noDisp, noImm)
		END;
		regTab [reg] := Occupied
	END GetThisReg;

	PROCEDURE AssignNewReg (pReg: LONGINT);
	(* assigns pReg to any free register *)
		VAR reg: SHORTINT; size: LONGINT;
	BEGIN
		size := Instr [pReg].op MOD 8;
		IF size = 2 THEN (* Byte *)
			GetReg8 (reg);
			sregTab [reg-AL] := pReg
		ELSE
			GetReg (reg);
			regTab [reg] := pReg;
			IF size = 1 THEN (* Word *) INC (reg, AX) END
		END;
		Instr [pReg].reg := reg
	END AssignNewReg;
	
	PROCEDURE AssignThisReg (pReg: LONGINT; this: SHORTINT);
	(* assigns pReg to the register 'this'. 'this' will be moved to another register if it is occupied *)
	BEGIN
		IF this IN {AL..BH} THEN
			GetThisReg8 (this);
			sregTab [this-AL] := pReg
		ELSIF ~(this IN {ESP, SP, EBP, BP}) THEN
			GetThisReg (this);
			regTab [this MOD 8] := pReg
		END;
		Instr [pReg].reg := this
	END AssignThisReg;
	
	PROCEDURE^ LastUse (reg: SHORTINT): BOOLEAN;
	
	PROCEDURE AssignReg (pReg: LONGINT; VAR reg, base, inx: SHORTINT);
		VAR
			hint, size, pRegBase, pRegInx, pRegReg: LONGINT;
	BEGIN
		hint := Instr[pReg].hint; size:= (Instr[pReg].op MOD 8) * 8;
		ASSERT ((reg = none) OR ((size = Bit8) & (reg >= AL)) OR  
			((size = Bit16) & (reg >= AX)) OR ((size = Bit32) & (reg >= EAX)));
		IF hint >= tryEAX THEN
			IF size = Bit8 THEN
				IF sregTab [hint - tryEAX] = free THEN
					AssignThisReg (pReg, SHORT (SHORT (hint-tryEAX+Bit8)));
					RETURN
				END
			ELSIF regTab [hint - tryEAX] = free THEN
				AssignThisReg (pReg, SHORT (SHORT (hint - tryEAX + size)));
				RETURN
			END;
			hint:= noHint
		END;
		IF hint <= noHint THEN
			IF (reg = none) OR ~LastUse (reg) THEN AssignNewReg (pReg)
			ELSE Instr[pReg].reg := reg
			END
		ELSE
			IF reg >= AL THEN pRegReg := sregTab [reg - AL]
			ELSIF reg # none THEN pRegReg := regTab [reg MOD 8]
			END;
			IF inx >= AL THEN pRegInx := sregTab [inx - AL]
			ELSIF inx # noInx THEN pRegInx := regTab [inx MOD 8]
			END;
			IF base >= AL THEN pRegBase := sregTab [base - AL]
			ELSIF base # noBase THEN pRegBase := regTab [base MOD 8]
			END;
			AssignThisReg (pReg, SHORT (SHORT (hint + size)));
			IF (reg # none) & (pRegReg >= 0) THEN reg := Instr [pRegReg].reg END;
			IF (inx # none) & (pRegInx >= 0) THEN inx := Instr [pRegInx].reg END;
			IF (base # none) & (pRegBase >= 0) THEN base := Instr [pRegBase].reg END
		END
	END AssignReg;
	
	PROCEDURE FreeReg (reg: SHORTINT);
	(* releases register reg *)
		VAR i: SHORTINT;
	BEGIN
		IF (reg > none) & ~(reg IN {ESP, SP, EBP, BP}) THEN
			IF reg IN {AL..BH} THEN
				i := reg-AL;
				IF sregTab [i] >= 0 THEN Instr [sregTab [i]].reg := -2-reg END;
				sregTab [i] := free;
				IF i < 4 THEN
					IF sregTab [i+4] = free THEN regTab [i] := free (* release 32/16 bit register *) END
				ELSIF sregTab [i-4] = free THEN regTab [i MOD 4] := free (* release 32/16 bit register *)
				END;
			ELSE
				i := reg MOD 8;
				IF regTab [i] >= 0 THEN Instr [regTab [i]].reg := -2-reg END;
				IF i IN {ESP, SP, EBP, BP} THEN regTab [i] := Occupied
				ELSE regTab [i] := free
				END
			END
		END
	END FreeReg;
	
	PROCEDURE DecReg (reg: SHORTINT); (* only used by DecCheckReg, Store, GenPush, Gen0, GenFlags *)
		VAR pReg: LONGINT;
	BEGIN
		IF reg > none THEN
			IF reg >= AL THEN pReg := sregTab [reg-AL]
			ELSE pReg := regTab [reg MOD 8]
			END;
			IF pReg > none THEN
				DEC (Instr [pReg].used);
				IF (Instr [pReg].used = 0) & (Instr [pReg].reg > Nil) THEN FreeReg (Instr [pReg].reg) END
			END
		END
	END DecReg;
	
	PROCEDURE DecCheckReg (pReg: LONGINT; src, base, inx: SHORTINT);
		VAR reg, r: SHORTINT;
		
		PROCEDURE ReleaseReg (reg: SHORTINT);
			VAR pReg: LONGINT;
		BEGIN
			IF reg > none THEN
				IF reg >= AL THEN pReg := sregTab [reg-AL]
				ELSE pReg := regTab [reg MOD 8]
				END;
				IF pReg > none THEN Instr [pReg].reg := -2-reg END
			END
		END ReleaseReg;

		PROCEDURE CheckRegister (reg, src: SHORTINT);
			VAR s: SHORTINT;
		BEGIN
			IF src IN {AL..BH} THEN s := src MOD 4
			ELSE s := src MOD 8
			END;
			IF reg IN {AL..BH} THEN
				IF src IN {AL..BH} THEN
					IF reg = src THEN ReleaseReg (src)
					ELSE DecReg (src)
					END
				ELSIF reg MOD 4 = s THEN ReleaseReg (src)
				ELSE DecReg (src)
				END
			ELSIF reg MOD 8 = s THEN ReleaseReg (src)
			ELSE DecReg (src)
			END
		END CheckRegister;
		
	BEGIN
		reg:= Instr[pReg].reg; 
		CheckRegister (reg, src);
		CheckRegister (reg, base);
		CheckRegister (reg, inx);
		IF reg >= AL THEN
			regTab [reg MOD 4] := Splitted;
			sregTab [reg - AL] := pReg
		ELSIF (reg # none) & ~(reg IN {ESP, EBP, SP, BP}) THEN
			r := reg MOD 8;
			regTab [r] := pReg;
			IF reg IN SplittableReg THEN
				sregTab [r] := free; sregTab [r+4] := free
			END
		END
	END DecCheckReg;
			
	PROCEDURE loaded (pReg: LONGINT): BOOLEAN;
	BEGIN
		IF pReg > none THEN RETURN (Instr [pReg].reg > none)
		ELSE RETURN ((pReg = RiscESP) OR (pReg = RiscFP))
		END
	END loaded;

	PROCEDURE^ Load (VAR instr: Instruction);
	
	PROCEDURE FindReg (pReg: LONGINT; VAR reg: SHORTINT);
	BEGIN
		ASSERT (loaded (pReg));
		IF pReg > none THEN reg := Instr [pReg].reg
		ELSIF pReg = RiscESP THEN reg := ESP
		ELSE reg := EBP
		END
	END FindReg;
	
	PROCEDURE FindLoadReg (pReg: LONGINT; VAR reg: SHORTINT);
	BEGIN
		IF pReg > none THEN
			IF ~loaded (pReg) THEN Load (Instr [pReg]) END;
			reg := Instr [pReg].reg
		ELSIF pReg = RiscESP THEN reg := ESP
		ELSIF pReg = RiscFP THEN reg := EBP
		ELSE reg := none
		END
	END FindLoadReg; 
		
(* general *)
	
	PROCEDURE LastUse (reg: SHORTINT): BOOLEAN;
		VAR pReg: LONGINT;
	BEGIN
		ASSERT (reg IN {EAX..BH});
		IF reg >= AL THEN pReg := sregTab [reg-AL]
		ELSE pReg := regTab [reg MOD 8]
		END;
		IF pReg > none THEN  RETURN Instr[pReg].used = 1
		ELSE 
			ASSERT (reg IN {ESP, SP, EBP, BP});
			RETURN TRUE
		END
	END LastUse;
	
(* Risc Code -> i386 Code *)

	PROCEDURE FindMemReg (VAR instr: Instruction; VAR mode, scale, size, base, inx: SHORTINT; VAR disp: LONGINT);
	BEGIN
		size := SHORT (instr.op MOD 8) * 8; mode := SHORT((instr.op DIV 8) MOD 4); scale := instr.scale;
		IF mode IN {MemReg, RegMem} THEN
			FindLoadReg (instr.src1, base); disp := instr.src2;
			FindLoadReg (instr.inx, inx)
		ELSIF mode = RegReg THEN
			FindLoadReg (instr.src1, base);
			disp := noDisp; inx := none
		ELSE (* mode = ImmReg *)
			ASSERT (mode = ImmReg);
			base := noBase; disp := noDisp; inx := none
		END
	END FindMemReg;
	
	PROCEDURE Load (VAR instr: Instruction);
	(* ld, lea, ldbdw, ldbw, ldwdw, ldProc, ldXProc *)
		VAR
			mode, scale, size, base, inx, dummy: SHORTINT;
			disp: LONGINT;
			
		PROCEDURE AssignReg (pReg: LONGINT; VAR baseReg, inxReg: SHORTINT);
			VAR
				hint, size, pRegBase, pRegInx: LONGINT;
				base, inx, op: SHORTINT;  (* NM 7.6.94; workaround for sign-extended bug *)
		BEGIN
			hint := Instr[pReg].hint; size:= (Instr[pReg].op MOD 8) * 8;
			IF hint >= tryEAX THEN
				IF size = Bit8 THEN
					IF (sregTab [hint - tryEAX] = free) & (regTab [hint - tryEAX] = free) THEN
						AssignThisReg (pReg, SHORT (SHORT (hint-tryEAX+Bit8)));
						RETURN
					END
				ELSIF regTab [hint - tryEAX] = free THEN
					AssignThisReg (pReg, SHORT (SHORT (hint - tryEAX + size)));
					RETURN
				END;
				hint:= noHint
			END;
			base:= baseReg; inx:= inxReg;
			IF hint <= noHint THEN
				op := SHORT (instr.op DIV 32);
				IF (op = Ldbdw) OR (op = Ldbw) OR (op = Ldwdw) OR (op = Ldbdwu) OR 
					(op = Ldbwu) OR (op = Ldwdwu) THEN AssignNewReg (pReg)
				ELSIF (base = none) OR (base IN {ESP, EBP}) OR ~LastUse (base) OR 
					((size = Bit8) & (base IN {EDI, ESI, ESP, EBP, DI, SI, SP, BP})) THEN (* base can't be reused *)
						IF (inx = none) OR (inx IN {ESP, EBP}) OR ~LastUse (inx) OR 
						((size = Bit8) & (inx IN {EDI, ESI, ESP, EBP, DI, SI, SP, BP})) THEN 
						(* inx can't be reused *)
							AssignNewReg (pReg)
						ELSE Instr[pReg].reg := inx MOD 8 + SHORT (SHORT (size))
						END
				ELSE Instr[pReg].reg := base MOD 8 + SHORT (SHORT (size))
				END
			ELSE
				IF inx >= AL THEN pRegInx := sregTab [inx - AL]
				ELSIF inx # noInx THEN pRegInx := regTab [inx MOD 8]
				END;
				IF base >= AL THEN pRegBase := sregTab [base - AL]
				ELSIF base # noBase THEN pRegBase := regTab [base MOD 8]
				END;
				AssignThisReg (pReg, SHORT (SHORT (hint + size)));
				IF (inx # none) & (pRegInx >= 0) THEN inxReg := Instr [pRegInx].reg END;
				IF (base # none) & (pRegBase >= 0) THEN baseReg := Instr [pRegBase].reg END
			END
		END AssignReg;

	BEGIN
		FindMemReg (instr, mode, scale, size, base, inx, disp);
		ASSERT ((size = Bit8) OR (size = Bit16) OR (size = Bit32));
		IF instr.op DIV 32 # PUTreg THEN AssignReg (instr.dest, base, inx) END;
		CASE instr.op DIV 32 OF
			Ld:
				ASSERT ((mode # RegReg) OR ((mode = RegReg) & (instr.reg # base)));
				OPO.GenMOV (mode, instr.reg, base, inx, scale, disp, instr.src2)
		  | Lea: 
				ASSERT ((mode # RegReg) OR ((mode = RegReg) & (instr.reg # base)));
				OPO.GenLEA (instr.reg, base, inx, scale, disp)
		  | Ldbdw, Ldbw: OPO.GenMOVSX (mode, 0, instr.reg, base, inx, scale, disp)
		  | Ldwdw: OPO.GenMOVSX (mode, 1, instr.reg, base, inx, scale, disp)
		  | Ldbdwu, Ldbwu: OPO.GenMOVZX (mode, 0, instr.reg, base, inx, scale, disp)
		  | Ldwdwu: OPO.GenMOVZX (mode, 1, instr.reg, base, inx, scale, disp)
		  | PUTreg: OPO.GenMOV (mode, SHORT (instr.hint + size), base, inx, scale, disp, instr.src2)
		ELSE HALT (BUG)
		END;
		dummy:=  none;
		DecCheckReg (instr.dest, dummy, base, inx);
		IF (mode IN {RegMem, MemReg}) & (base = noBase) & ~instr.abs THEN (* absolute *)		(* GetPut *)
			AbsAccess (instr.node, OPO.pc - 4)
		END
	END Load;

	PROCEDURE LoadProc (VAR instr: Instruction);
		VAR dummy: SHORTINT;

		PROCEDURE AssignReg (pReg: LONGINT);
			VAR
				hint, size: LONGINT;
		BEGIN
			hint := Instr[pReg].hint; size:= (Instr[pReg].op MOD 8) * 8;
			IF hint >= tryEAX THEN
				IF size = Bit8 THEN
					IF sregTab [hint - tryEAX] = free THEN
						AssignThisReg (pReg, SHORT (SHORT (hint-tryEAX+Bit8)));
						RETURN
					END
				ELSIF regTab [hint - tryEAX] = free THEN
					AssignThisReg (pReg, SHORT (SHORT (hint - tryEAX + size)));
					RETURN
				END;
				hint:= noHint
			END;
			IF hint = noHint THEN AssignNewReg (instr.dest)
			ELSE
				ASSERT (hint > noHint);
				AssignThisReg (pReg, SHORT (SHORT (hint + size)));
			END
		END AssignReg;

	BEGIN (* LoadProc *)
		AssignReg (instr.dest);
		IF instr.op DIV 32 = LdProc THEN (* procedure in the compiled module *)
			OPO.GenMOV (ImmReg, instr.reg, noBase, noInx, noScale, noDisp, instr.src1 MOD 10000H);
			(* lower 16 bit contains entry number -> loader must insert absolute address *)
			AddLink (LocProcAssIndex, OPO.pc - 4)
		ELSE (* instr.op DIV 32 = LdXProc *)
			OPO.GenMOV (ImmReg, instr.reg, noBase, noInx, noScale, noDisp, 0FFFFH);
				(* 0FFFFH-> loader must insert absolute address *)
			AddLink (instr.src1 MOD 10000H, OPO.pc - 4)
		END;
		dummy := none;
		DecCheckReg (instr.dest, dummy, dummy, dummy)
	END LoadProc;

	
	PROCEDURE Store (VAR instr: Instruction);
	(* store, getReg *)
		VAR
			mode, scale, size, reg, base, inx: SHORTINT;
			disp, delta: LONGINT;
	BEGIN
		FindMemReg (instr, mode, scale, size, base, inx, disp);
		IF instr.op DIV 32 = GETreg THEN
			OPO.GenMOV (mode, SHORT (instr.hint + size), base, inx, scale, disp, noImm);
			reg := none; delta := 0
		ELSIF ~loaded (instr.dest) & ((Instr [instr.dest].op DIV 8) MOD 4 = ImmReg) THEN
			OPO.GenMOV (ImmMem, size, base, inx, scale, disp, Instr [instr.dest].src2);
			mode := ImmMem;
			IF OPO.lastImmSize = Bit8 THEN delta := 1
			ELSIF OPO.lastImmSize = Bit16 THEN delta := 2
			ELSE (* lastImmSize = Bit 32 *)
				delta := 4
			END
		ELSE
			delta := 0;
			FindLoadReg (instr.dest, reg);
			ASSERT (((size = Bit8) & ((reg IN SplittableReg) OR (reg IN {AL..BH}))) OR (size # Bit8));
			OPO.GenMOV (mode, (reg MOD 8) + size, base, inx, scale, disp, noImm)
		END;
		DecReg (reg); DecReg (base); DecReg (inx);
		IF (mode IN {ImmMem, RegMem, MemReg}) & (base = noBase) & ~instr.abs THEN (* absolute access *)
			AbsAccess (instr.node, OPO.pc - delta - 4)
		END
	END Store;
	
	PROCEDURE GenPortIO (VAR instr: Instruction);					(* New Functions *)
			VAR size: INTEGER; pin : BOOLEAN;
	BEGIN
		size := instr.op MOD 8 * 8; pin := instr.op DIV 32 = In;
		IF pin THEN
			(* FindMemReg(instr, dummy, dummy, reg, dummy, dummy, ldummy); *)
ASSERT(~loaded(instr.dest));
			IF size = Bit8 THEN AssignThisReg( instr.dest, AL)
			ELSIF size = Bit16 THEN AssignThisReg( instr.dest, AX)
			ELSIF size = Bit32 THEN AssignThisReg( instr.dest, EAX)
			ELSE HALT(BUG) END
;ASSERT(loaded(instr.dest));
		ELSE
			ASSERT(loaded(instr.src1));
			FreeReg(Instr[instr.src1].reg)
		END;
		IF pin THEN OPO.GenIN(size) ELSE OPO.GenOUT(size) END;	(* Bug1 *)
		FreeReg( DX );
	END GenPortIO;
	
	PROCEDURE GenPush (VAR instr: Instruction);
		VAR reg, i: SHORTINT;
	BEGIN
		ASSERT ((instr.op DIV 8) MOD 4 IN {Imme, Regs});
		IF (instr.op DIV 8) MOD 4 = Imme THEN OPO.GenPUSH (Imme, Bit32, noBase, noInx, noScale, noDisp, instr.src2)
		ELSE (* first load and then push -> faster on i486 based machines *)
			FindLoadReg (instr.src1, reg);
			IF reg IN {AH, CH, DH, BH} THEN
				i := EBX;
				WHILE (i >= EAX) & ~((regTab [i] = Splitted) & (sregTab [i] = free)) DO DEC (i) END;
				IF i < EAX THEN (* none of the 8 bit registers AL, CL, DL, BL are free *)
					i := EBX;
					WHILE (i >= EAX) & (regTab [i] # free) DO DEC (i) END; (* search a splittable register *)
					IF i < EAX THEN GetReg (i) END
				END;
				IF i IN SplittableReg THEN
					GetThisReg8 (i + AL);
					OPO.GenMOV (RegReg, i+AL, reg, noInx, noScale, noDisp, noImm);
					OPO.GenPUSH (Regs, i, noBase, noInx, noScale, noDisp, noImm)
				ELSE (* move sign extended *)
					OPO.GenMOVSX (Regs, 0, i, reg, noInx, noScale, noDisp);
					OPO.GenPUSH (Regs, i, noBase, noInx, noScale, noDisp, noImm)
				END;
				FreeReg (i)
			ELSE
				IF reg IN {AL, CL, DL, BL} THEN i := reg MOD 4 (* we can't push a byte *)
				ELSE i := reg MOD 8 (* only push 32 bit register *)
				END;
				OPO.GenPUSH (Regs, i, noBase, noInx, noScale, noDisp, noImm)
			END;
			DecReg (reg)
		END
	END GenPush;
	
	PROCEDURE GenPop (VAR instr: Instruction);
		VAR reg, dummy: SHORTINT;
	BEGIN
		dummy := noBase; (* = noInx *)
		AssignReg (instr.dest, dummy, dummy, dummy); reg := instr.reg;
		ASSERT (((instr.op DIV 8) MOD 4 = Regs) & ~(reg IN {AL..BH})); (* 8 bit pop is not allowed *)
		reg := reg MOD 8; (* only pop 32 bit register *)
		OPO.GenPOP (Regs, reg, noBase, noInx, noScale, noDisp)
	END GenPop;
	
	PROCEDURE Gen1 (VAR instr: Instruction; RiscPC: LONGINT);
	(* je, jne, jl, jle, jg, jge, ja, jae, jb, jbe, jc, jnc, jmp, jmpReg *)
		VAR
			op, mode, scale, size, reg, base, inx: SHORTINT; disp: LONGINT;
	BEGIN
		op := SHORT (instr.op DIV 32);
		IF op = JmpReg THEN
			IF ~loaded (instr.src2) THEN
				FindMemReg (Instr[instr.src2], mode, scale, size, base, inx, disp);
				OPO.GenJMP (Mem, 0, base, inx, scale, disp);
				DecReg (base); DecReg (inx)
			ELSE
				FindReg (instr.src2, reg);
				OPO.GenJMP (Regs, reg, noBase, noInx, noScale, noDisp);
				DecReg (reg)
			END
		ELSIF op = Jmp THEN
			IF RiscPC >= instr.src2 THEN (* backward jump *)
				disp := Instr [instr.src2].pc - (OPO.pc+2);
				IF disp < -128 THEN DEC (disp, 3) END; (* 32 bit displacement *)
				OPO.GenJMP (Imme, none, noBase, noInx, noScale, disp)
			ELSE (* link with fixup chain *)
				(* always 32 bit displacement *)
				OPO.GenJMP (Imme, none, noBase, noInx, noScale, -2 - Instr [instr.src2].pc - 10000H);
				Instr [instr.src2].pc := RiscPC
			END
		ELSE
			ASSERT ((op >= Je) & (op <= Jnc));
			op := JmpConvert [op-Je];
			IF RiscPC >= instr.src2 THEN (* backward jump *)
				disp := Instr [instr.src2].pc - (OPO.pc+2);
				IF disp < -128 THEN DEC (disp, 4) END; (* 32 bit displacement *)
				OPO.GenJcc (op, disp)
			ELSE (* link with fixup chain *)
				(* always 32 bit displacement *)
				OPO.GenJcc (op, -2 - Instr [instr.src2].pc - 10000H);
				Instr [instr.src2].pc := RiscPC
			END
		END
	END Gen1;
	
	PROCEDURE Gen2 (VAR instr: Instruction);
	(* neg, not *)
		VAR src, dummy: SHORTINT;
	BEGIN
		ASSERT ((instr.op DIV 32 = Neg) OR (instr.op DIV 32 = Not));
		dummy := noInx;
		FindLoadReg (instr.src1, src);
		AssignReg (instr.dest, src, dummy, dummy);
		IF instr.reg # src THEN OPO.GenMOV (RegReg, instr.reg, src, noInx, noScale, noDisp, noImm) END;
		IF instr.op DIV 32 = Neg THEN OPO.GenNEG (RegReg, instr.reg, noBase, noInx, noScale, noDisp)
		ELSE OPO.GenNOT (RegReg, instr.reg, noBase, noInx, noScale, noDisp)
		END;
		DecCheckReg (instr.dest, src, dummy, dummy)
	END Gen2;
	
	PROCEDURE Gen3 (VAR instr: Instruction);
	(* add, sub, or, xor, and, btr, bts, sal, sar, shl, shr, rol *)
		VAR
			op, mode, scale, size, base, inx, src, dummy, shiftReg: SHORTINT;
			disp: LONGINT;
	BEGIN
		op := SHORT (instr.op DIV 32); mode := SHORT ((instr.op DIV 8) MOD 4); size := SHORT (instr.op MOD 8) * 8;
		IF mode = ImmReg THEN
			FindLoadReg (instr.src1, src); base := noBase; inx := noInx; scale := noScale; disp := noDisp
		ELSIF  ~loaded (instr.src1) THEN
			IF  ~loaded (instr.src2) THEN
				FindLoadReg (instr.src1, src);
				FindMemReg (Instr [instr.src2], dummy, scale, dummy, base, inx, disp);
				mode := MemReg
			ELSIF ((op = Add) OR (op = oR) OR (op = Xor) OR (op = And)) THEN
				FindReg (instr.src2, src);
				FindMemReg (Instr [instr.src1], dummy, scale, dummy, base, inx, disp);
				mode := MemReg
			ELSE
				FindLoadReg (instr.src1, src);
				FindReg (instr.src2, base); inx := none; scale := noScale; disp := noDisp;
				mode := RegReg
			END
		ELSIF ~loaded (instr.src2) THEN
			mode := MemReg;
			FindReg (instr.src1, src);
			FindMemReg (Instr [instr.src2], dummy, scale, dummy, base, inx, disp)
		ELSE
			mode := RegReg;
			FindReg (instr.src1, src); FindReg (instr.src2, base);
			inx := noInx; scale := noScale; disp := noDisp
		END;
		src := src MOD 8 + size;			(* bug fix *)
		AssignReg (instr.dest, src, base, inx);
		IF instr.reg # src THEN OPO.GenMOV (RegReg, instr.reg, src, noInx, noScale, noDisp, noImm) END;
		IF op <= And THEN (* !!later: optimize add, 1 -> INC, sub, 1 -> DEC *)
			CASE op OF
				Add: op := ADD
			  | Sub: op := SUB
			  | oR: op := Or
			  | Xor: op := XOR
			  | And: op := AND
			ELSE HALT (BUG)
			END;
			OPO.GenTyp1 (op, mode, instr.reg, base, inx, scale, disp, instr.src2)
		ELSIF op = Bts THEN OPO.GenBTS (mode, instr.reg, base, inx, scale, disp, instr.src2)
		ELSIF op = Btr THEN OPO.GenBTR (mode, instr.reg, base, inx, scale, disp, instr.src2)
		ELSE (* op <= Rol *)
			ASSERT (op <= Rol);
			IF (mode = RegReg) & ~(base IN {ECX, CX, CL}) THEN
				shiftReg := ECX + (base DIV 8) * 8;
				AssignThisReg (instr.src2, shiftReg);
				OPO.GenMOV (RegReg, shiftReg, base, noInx, noScale, noDisp, noImm);
				IF base IN {AL..BH} THEN
					sregTab [base-AL] := Occupied; FreeReg (base)
				ELSE regTab [base MOD 8] := free
				END;
				base := shiftReg
			END;
			CASE op OF
				Sal: op := SAL
			  | Sar: op := SAR
			  | Shr: op := SHR
			  | Rol: op := ROL
			ELSE HALT (BUG)
			END;
			OPO.GenShiftRot (op, mode, instr.reg, base, inx, scale, disp, instr.src2)
		END;
		DecCheckReg (instr.dest, src, base, inx)
	END Gen3;
	
	PROCEDURE Flags (VAR instr: Instruction);
	(* cmp, bt *)
		VAR
			op, mode, scale, size, base, inx, reg, dummy: SHORTINT;
			disp: LONGINT;
	BEGIN
		op := SHORT (instr.op DIV 32); mode := SHORT ((instr.op DIV 8) MOD 4); size := SHORT (instr.op MOD 8) * 8;
		IF mode # ImmReg THEN
			IF ~loaded (instr.src1) THEN
				IF ~loaded (instr.src2) THEN
					FindLoadReg (instr.src1, reg);
					FindMemReg (Instr [instr.src2], dummy, scale, dummy, base, inx, disp);
					mode := MemReg
				ELSE
					FindReg (instr.src2, reg);
					FindMemReg (Instr [instr.src1], dummy, scale, dummy, base, inx, disp);
					mode := RegMem
				END
			ELSE
				FindReg (instr.src1, reg);
				IF ~loaded (instr.src2) THEN
					FindMemReg (Instr [instr.src2], dummy, scale, dummy, base, inx, disp);
					mode := RegMem
				ELSE
					FindReg (instr.src2, base); inx := noInx; disp := noDisp; mode := RegReg
				END
			END
		ELSIF ~loaded (instr.src1) THEN
			FindMemReg (Instr [instr.src1], dummy, scale, dummy, base, inx, disp);
			reg := size; mode := ImmMem
		ELSE
			FindReg (instr.src1, reg); base := noBase; inx := noInx; disp := noDisp
		END;
		IF op = Cmp THEN OPO.GenTyp1 (CMP, mode, reg, base, inx, scale, disp, instr.src2)
		ELSIF op = Test THEN OPO.GenTEST (mode, reg, base, inx, scale, disp, instr.src2)
		ELSE OPO.GenBT (mode, reg, base, inx, scale, disp, instr.src2)
		END;
		DecReg (reg); DecReg (base); DecReg (inx)
	END Flags;

	PROCEDURE GenAbs (VAR instr: Instruction);
	(* abs *)
		VAR size, src, reg, dummy: SHORTINT;
	BEGIN
		size := SHORT ((instr.op MOD 8) * 8);
		FindLoadReg (instr.src1, src);
		IF size = Bit8 THEN
			IF instr.hint IN useReg THEN
				IF LastUse (src) & (src MOD 4 = instr.hint) THEN
					IF src IN {AL, CL, DL, BL} THEN GetThisReg8 (src + 4)
					ELSE GetThisReg8 (src - 4)
					END;
					reg := src MOD 4
				ELSE
					reg := SHORT (SHORT (instr.hint));
					GetThisReg (reg)
				END
			ELSE
				IF (instr.hint IN tryReg) & (regTab [instr.hint - tryEAX] = free) THEN reg:= SHORT (SHORT (instr.hint - tryEAX))
				ELSE
					reg := EBX;
					WHILE (reg >= EAX) & (regTab [reg] # free) DO DEC (reg) END;
					IF LastUse (src) & (((src IN {AL, CL, DL, BL}) & (sregTab [src - AL + 4] = free)) OR 
				 	   ((src IN {AH, CH, DH, BH}) & (sregTab [src+AL-4] = free))) THEN 
						reg := src MOD 4
					ELSIF reg < EAX THEN GetSplittableReg (reg)
					END
				END
			END;
			OPO.GenMOVSX (RegReg, 0, reg, src, noInx, noScale, noDisp);
			IF LastUse (src) THEN
				FreeReg (src); src:= none
			END;
			regTab [reg] := Splitted; sregTab [reg] := instr.dest; sregTab [reg + 4] := free;
			INC (reg, AL); instr.reg := reg;
			OPO.GenTyp1 (XOR, RegReg, reg, reg + 4, noInx, noScale, noDisp, noImm);
			OPO.GenTyp1 (SUB, RegReg, reg, reg + 4, noInx, noScale, noDisp, noImm)
		ELSE (* Bit16 / Bit32 *)
			IF regTab [EDX] = free THEN regTab [EDX] := Occupied END;
			IF ~LastUse (src) & (src IN {EAX, AX}) THEN (* conflict *)
				AssignNewReg (instr.src1); regTab [EAX] := Occupied;
				OPO.GenMOV (RegReg, Instr [instr.src1].reg, EAX, noInx, noScale, noDisp, noImm)
			ELSIF ~(src IN {EAX, AX}) THEN
				GetThisReg (EAX);
				OPO.GenMOV (RegReg, EAX, src, noInx, noScale, noDisp, noImm);
				IF LastUse (src) THEN
					FreeReg (src); src := none
				END
			ELSE
				FreeReg (src); src := none; GetThisReg (EAX)
			END;
			instr.reg := EAX + size; regTab [EAX] := instr.dest;
			IF regTab [EDX] # Occupied THEN GetThisReg (EDX) END;
			OPO.Prefix (size, dummy); OPO.PutByte (CWD);
			OPO.GenTyp1 (XOR, RegReg, EAX + size, EDX + size, noInx, noScale, noDisp, noImm);
			OPO.GenTyp1 (SUB, RegReg, EAX + size, EDX + size, noInx, noScale, noDisp, noImm);
			FreeReg (EDX)
		END;
		DecReg (src);
		IF (instr.hint IN useReg) & (instr.reg MOD 8 # instr.hint) THEN (* result is in the wrong register *)
			src := instr.reg;
			AssignThisReg (instr.dest, SHORT (SHORT (instr.hint)) + size);
			OPO.GenMOV (RegReg, instr.reg, src, noInx, noScale, noDisp, noImm);
			FreeReg (src)
		END
	END GenAbs;
	
	PROCEDURE GenDivMod (VAR instr: Instruction);
		VAR
			size, mode, src, base, inx, scale, dummy: SHORTINT;
			disp, pRegBase, pRegInx: LONGINT;
	BEGIN
		size := SHORT (instr.op MOD 8) * 8; mode := SHORT ((instr.op DIV 8) MOD 4);
		IF (size # Bit8) & (regTab [EDX] = free) THEN regTab [EDX] := Occupied END; (* reserve EDX *)
		IF mode # ImmReg THEN
			IF loaded (instr.src2) THEN
				FindReg (instr.src2, base); inx := noInx; scale := noScale; disp := noDisp
			ELSE
				mode := MemReg;
				FindMemReg (Instr[instr.src2], dummy, scale, dummy, base, inx, disp)
			END
		ELSE
			inx := noInx; base := noBase
		END;
		IF ~loaded (instr.src1) THEN 
			Instr [instr.src1].hint := useEAX;
			FindLoadReg (instr.src1, src)
		ELSE FindReg (instr.src1, src)
		END;
		IF base >= AL THEN pRegBase := sregTab [base-AL]
		ELSIF base # none THEN pRegBase := regTab [base MOD 8]
		END;
		IF inx # none THEN
			ASSERT (inx IN {EAX..EDI});
			pRegInx := regTab [inx]
		END;
		IF size = Bit8 THEN
			IF LastUse (src) & (src IN {AL, AH}) THEN
				IF src = AL THEN GetThisReg8 (AH)
				ELSE GetThisReg8 (AL)
				END;
				regTab [EAX] := Occupied
			ELSE GetThisReg (EAX)
			END;
			OPO.GenMOVSX (RegReg, 0, AX, src, noInx, noScale, noDisp);
			IF LastUse (src) THEN
				FreeReg (src); src := none
			END;
			IF mode = ImmReg THEN (* immediate division not allowed *)
				mode := RegReg; inx := noInx; scale := noScale; disp := noDisp;
				GetReg8 (base);
				OPO.GenMOV (ImmReg, base, noBase, noInx, noScale, noDisp, instr.src2)
			END
		ELSE (* Bit16 / Bit32 *)
			IF ~LastUse (src) & (src IN {EAX, AX}) THEN (* conflict *)
				AssignNewReg (instr.src1); src := Instr [instr.src1].reg;
				OPO.GenMOV (RegReg, src, EAX, noInx, noScale, noDisp, noImm);
				regTab [EAX] := Occupied
			ELSIF ~(src IN {EAX, AX}) THEN
				GetThisReg (EAX);
				OPO.GenMOV (RegReg, EAX+size, src, noInx, noScale, noDisp, noImm);
				IF LastUse (src) THEN
					FreeReg (src); src := none
				END
			ELSE
				FreeReg (src); src := none;
				regTab [EAX] := Occupied
			END;
			IF regTab [EDX] # Occupied THEN GetThisReg (EDX) END;
			IF mode = ImmReg THEN (* immediate division not allowed *)
				GetReg (base); INC (base, size); inx := noInx;
				OPO.GenMOV (ImmReg, base, noBase, noInx, noScale, noDisp, instr.src2);
				mode := RegReg
			END;
			OPO.Prefix (size, dummy); OPO.PutByte (CWD);
		END;
		IF (base # none) & ((instr.op DIV 8) MOD 4 # ImmReg) THEN base := Instr [pRegBase].reg END;
		IF inx # none THEN inx := Instr [pRegInx].reg END;
		IF mode = RegReg THEN OPO.GenIDIV (RegReg, base, noBase, noInx, noScale, noDisp)
		ELSE OPO.GenIDIV (mode, size, base, inx, scale, disp)
		END;
		IF (size = Bit8) THEN OPO.GenTyp1 (CMP, ImmReg, AH, noBase, noInx, noScale, noDisp, 0)
		ELSE OPO.GenTyp1 (CMP, ImmReg, EDX+size, noBase, noInx, noScale, noDisp, 0)
		END;
		IF instr.op DIV 32 = Div THEN
			IF size = Bit32 THEN OPO.GenJcc (JGE, 1)
			ELSE OPO.GenJcc (JGE, 2)
			END;
			OPO.GenDEC (ImmReg, EAX+size, noBase, noInx, noScale, noDisp);
			instr.reg := EAX+size;
			IF size = Bit8 THEN
				regTab [EAX] := Splitted; sregTab [AL-AL] := instr.dest; sregTab [AH-AL] := free		
			ELSE 
				regTab [EAX] := instr.dest;
				FreeReg (EDX)
			END
		ELSE (* MOD *)
			ASSERT (instr.op DIV 32 = Mod);
			IF size = Bit16 THEN OPO.GenJcc (JGE, 3)
			ELSE OPO.GenJcc (JGE, 2)
			END;
			IF (size = Bit8) THEN
				OPO.GenTyp1 (ADD, mode, AH, base, inx, scale, disp, noImm);
				instr.reg := AH; regTab [EAX] := Splitted; sregTab [AH-AL] := instr.dest; sregTab [AL-AL] := free
			ELSE
				OPO.GenTyp1 (ADD, mode, EDX+size, base, inx, scale, disp, noImm);
				instr.reg := EDX+size; regTab [EDX] := instr.dest;
				FreeReg (EAX)
			END
		END;
		IF (instr.op DIV 8) MOD 4 = ImmReg THEN
			FreeReg (base); base := none
		END;
		DecCheckReg (instr.dest, src, base, inx);
		IF (instr.hint IN useReg) & (instr.reg MOD 8 # instr.hint) THEN (* result is in the wrong register *)
			src := instr.reg;
			AssignThisReg (instr.dest, SHORT (SHORT (instr.hint)) + size);
			OPO.GenMOV (RegReg, instr.reg, src, noInx, noScale, noDisp, noImm);
			FreeReg (src)
		END
	END GenDivMod;
	
	PROCEDURE GenMul (VAR instr: Instruction);
		VAR
			size, mode, src, base, inx, scale, dummy:  SHORTINT;
			disp, pRegBase, pRegInx: LONGINT;
	BEGIN
		size := SHORT ((instr.op MOD 8) * 8); mode := SHORT ((instr.op DIV 8) MOD 4);
		IF mode # ImmReg THEN
			IF loaded (instr.src2) THEN
				FindReg (instr.src2, base); inx := noInx; scale := noScale; disp := noDisp
			ELSE
				mode := RegMem;
				FindMemReg (Instr [instr.src2], dummy, scale, dummy, base, inx, disp)
			END
		END;
		IF ~loaded (instr.src1) THEN
			IF size = Bit8 THEN Instr [instr.src1].hint := useEAX END;
			FindLoadReg (instr.src1, src)
		ELSE FindReg (instr.src1, src)
		END;
		IF (mode = ImmReg) & (size # Bit8) THEN (* imul reg, src, immediate *)
			inx := none; base := none;
			AssignReg (instr.dest, src, base, inx);
			OPO.GenIMUL (ImmReg, FALSE, instr.reg(*+size*), src, noInx, noScale, noDisp, instr.src2)		(* mul bug *)
		ELSE
			IF size = Bit8 THEN (* imul reg/mem *)
				IF mode # ImmReg THEN
					IF base >= AL THEN pRegBase := sregTab [base - AL]
					ELSIF base # none THEN pRegBase := regTab [base MOD 8]
					END;
					IF inx # none THEN
						ASSERT (inx < AL);
						pRegInx := regTab [inx MOD 8] 
					END
				END;
				IF LastUse (src) & (src IN {AL, AH}) THEN
					IF src = AL THEN
						IF ~((mode = RegReg) & LastUse (base)) THEN GetThisReg8 (AH) END;
					ELSE
						GetThisReg8 (AL);
						OPO.GenMOV (RegReg, AL, src, noInx, noScale, noDisp, noImm)
					END
				ELSE
					GetThisReg (EAX); src := Instr [instr.src1].reg;
					OPO.GenMOV (RegReg, AL, src, noInx, noScale, noDisp, noImm)
				END;
				IF LastUse (src) THEN
					FreeReg (src); src:= none
				END;
				instr.reg := AL; regTab [EAX] := Splitted; sregTab [AL-AL] := instr.dest; sregTab [AH - AL] := free;
				IF mode = ImmReg THEN (* immediate mul not allowed *)
					mode := RegReg; GetReg8 (base); inx := noInx; scale := noScale; disp := noDisp;
					OPO.GenMOV (ImmReg, base, noBase, noInx, noScale, noDisp, instr.src2);
					OPO.GenIMUL (mode, TRUE, instr.reg, base, inx, scale, disp, noImm);
					FreeReg (base); base := none
				ELSE
					IF base # none THEN base := Instr [pRegBase].reg END;
					IF inx # none THEN inx := Instr [pRegInx].reg END;
					OPO.GenIMUL (mode, TRUE, instr.reg, base, inx, scale, disp, noImm)
				END
			ELSE
				ASSERT (size IN {Bit16, Bit32});
				AssignReg (instr.dest, src, base, inx);
				IF instr.reg # src THEN OPO.GenMOV (RegReg, instr.reg, src, noInx, noScale, noDisp, noImm) END;
				IF (instr.reg IN {AX, EAX}) & (regTab [EDX] = free) THEN (* use short form *)
					OPO.GenIMUL (mode, TRUE, instr.reg, base, inx, scale, disp, noImm)
				ELSE OPO.GenIMUL (mode, FALSE, instr.reg, base, inx, scale, disp, noImm)
				END
			END
		END;
		DecCheckReg (instr.dest, src, base, inx)
	END GenMul;
	
	PROCEDURE GenRepMovs (VAR instr: Instruction);
	(* repMovs *)
		VAR
			src, dest, nofElem, tmp: SHORTINT;
	BEGIN
		FindLoadReg (instr.dest, dest);
		ASSERT (dest IN {EAX..EDI});
		IF dest # EDI THEN
			IF instr.dest >= 0 THEN AssignThisReg (instr.dest, EDI)
			ELSE GetThisReg (EDI)
			END;
			OPO.GenMOV (RegReg, EDI, dest, noInx, noScale, noDisp, noImm);
			IF ~(dest IN {ESP, EBP}) THEN regTab [dest] := free END;
		END;
		FindLoadReg (instr.src1, src);
		ASSERT (src IN {EAX..EDI});
		IF src # ESI THEN
			IF instr.src1 >= 0 THEN AssignThisReg (instr.src1, ESI)
			ELSE GetThisReg (ESI)
			END;
			OPO.GenMOV (RegReg, ESI, src, noInx, noScale, noDisp, noImm);
			IF ~(src IN {ESP, EBP}) THEN regTab [src] := free END;
		END;
		FindLoadReg (instr.src2, nofElem);
		ASSERT (nofElem IN {EAX..EDI});
		IF nofElem # ECX THEN
			IF instr.src2 >= 0 THEN AssignThisReg (instr.src2, ECX)
			ELSE GetThisReg (ECX)
			END;
			OPO.GenMOV (RegReg, ECX, nofElem, noInx, noScale, noDisp, noImm);
			IF ~(nofElem IN {ESP, EBP}) THEN regTab [nofElem] := free END;
		END;
		IF (instr.inx = AL) & (instr.hint = noHint) THEN (*8-bit move, forward move*)
			 GetReg8(tmp);
			OPO.GenMOV(RegReg, tmp, CL, noInx, noScale, noDisp, noImm);
			OPO.GenShiftRot(SHR, ImmReg, ECX, noBase, noInx, noScale, noDisp, 2);
			OPO.GenTyp1(AND, ImmReg, tmp, noBase, noInx, noScale, noDisp, 3);
			OPO.GenRepString(MOVS, EAX);
			OPO.GenMOV(RegReg, CL, tmp, noInx, noScale, noDisp, noImm);
			OPO.GenRepString(MOVS, AL);
			FreeReg(tmp)
		ELSE
			OPO.GenRepString (MOVS, SHORT (instr.inx))
		END;
		IF regTab [ECX] = Occupied THEN FreeReg (ECX)
		ELSE DecReg (ECX) (* nofElem *)
		END;
		IF regTab [ESI] = Occupied THEN FreeReg (ESI)
		ELSE DecReg (ESI) (* src *)
		END;
		IF regTab [EDI] = Occupied THEN FreeReg (EDI)
		ELSE DecReg (EDI) (* dest *)
		END
	END GenRepMovs;
					
	PROCEDURE GenCmpString (VAR instr: Instruction);
	(* cmpString *)
		VAR 
			src, srcAdr, src2Adr: SHORTINT;
			Lfix, L0, L1: LONGINT;
	BEGIN
		Lfix := OPO.pc;
		FindLoadReg (instr.src1, srcAdr); FindLoadReg (instr.src2, src2Adr);
		GetReg8 (src);
		OPO.GenMOV (MemReg, src, srcAdr, noInx, noScale, 0, noImm);
		OPO.GenTyp1 (CMP, MemReg, src, src2Adr, noInx, noScale, 0, noImm);
		OPO.GenJcc (JNE, 0); L0 := OPO.pc-1;
		OPO.GenTyp1 (CMP, ImmReg, src, noBase, noInx, noScale, noDisp, 0);
		OPO.GenJcc (JE, 0); L1 := OPO.pc-1;
		OPO.GenINC (ImmReg, srcAdr, noBase, noInx, noScale, noDisp);
		OPO.GenINC (ImmReg, src2Adr, noBase, noInx, noScale, noDisp);
		OPO.GenJMP (Imme, none, noBase, noInx, noScale, Lfix - (OPO.pc + 2));
		OPO.PutByteAt (L0, SHORT (OPO.pc - (L0+1))); OPO.PutByteAt (L1, SHORT (OPO.pc - (L1+1)));
		FreeReg (src);
		DecReg (srcAdr); DecReg (src2Adr)
	END GenCmpString;

	PROCEDURE Setcc (VAR instr: Instruction);
	(* sete, setne, setl, setle, setg, setge, setc, setnc *)
		VAR dummy: SHORTINT;
	BEGIN
		dummy := none;
		AssignReg (instr.dest, dummy, dummy, dummy);
		OPO.GenSetcc (SetccConvert [(instr.op DIV 32) - Sete], Regs, instr.reg, noInx, noScale, noDisp)
	END Setcc;

	PROCEDURE GenTrap (trapNr: LONGINT);
	BEGIN
		OPO.GenPUSH(Imme, 0, noBase, noInx, noScale, noDisp, trapNr);	(* PUSH TrapNr *)
		OPO.PutByte(0CCH);		(* INT 3 *)
	END GenTrap;
	
	PROCEDURE GenIntpt (Instr: Instruction);
	BEGIN
		OPO.PutByte(0CDH); OPO.PutByte(SHORT(SHORT(Instr.src2)));
		FreeReg(EAX); FreeReg(EBX); FreeReg(ECX); FreeReg(EDX)
	END GenIntpt;

	PROCEDURE GenTrapCC (VAR instr: Instruction);
		VAR op: SHORTINT;
	BEGIN
		IF instr.op DIV 32 = To THEN
			OPO.PutByte (0CEH)
		ELSE
			CASE instr.op DIV 32 OF
				Te: op := JNE
			  | Tne: op := JE
			  | Tle: op := JNLE
			  | Ta: op := JNA
			  | Tae: op := JNAE
			ELSE HALT (BUG)
			END;
			OPO.GenJcc (op, 3);
			OPO.GenPUSH(Imme, 0, noBase, noInx, noScale, noDisp, instr.src2);	(* PUSH TrapNr *)
			OPO.PutByte(0CCH);		(* INT 3 *)
		END;
	END GenTrapCC;
	
	PROCEDURE FixupAndGenTrap;
		VAR i, fixuppos, pos, next: LONGINT;
	BEGIN
		i := 0;
		WHILE i < nofTrapFixups DO
			IF trapFixupTab [i] # Nil THEN
				fixuppos := OPO.pc;
				pos := trapFixupTab [i];
				REPEAT
					OPO.GetDWord (pos, next);
					OPO.PutDWordAt (pos, fixuppos - (pos + 4));
					pos := -2 - next - 10000H
				UNTIL pos = Nil;
				GenTrap (i)
			END;
			INC (i)
		END
	END FixupAndGenTrap;

	PROCEDURE GenShort (VAR instr: Instruction);
		VAR src, reg, hint: SHORTINT;
	BEGIN
		FindReg (instr.src1, src);
		hint := SHORT (SHORT (instr.hint));
		ASSERT (LastUse (src));
		IF (instr.op MOD 8) * 8 = Bit16 THEN
			ASSERT (src IN {EAX..EDI});
			IF (hint IN useReg) & (src # hint) THEN
				AssignThisReg (instr.dest, hint + AX);
				OPO.GenMOV (RegReg, instr.reg, src, noInx, noScale, noDisp, noImm);
				FreeReg (src)
			ELSE 
				FreeReg (src);
				AssignThisReg (instr.dest, src + AX)
			END
		ELSE
			ASSERT (((instr.op MOD 8) * 8 = Bit8) & (src IN {EAX..DI}));
			IF (hint IN useReg) & (src MOD 8 # hint) THEN
				ASSERT (hint IN {EAX, ECX, EDX, EBX});
				AssignThisReg (instr.dest, hint + AL);
				IF src IN SplittableReg THEN 
					OPO.GenMOV (RegReg, instr.reg, (src MOD 8) + AL, noInx, noScale, noDisp, noImm)
				ELSE (* 16/32 bit register must be copied *)
					GetThisReg8 (instr.reg + 4); FreeReg (instr.reg + 4);
					OPO.GenMOV (RegReg, instr.reg MOD 4, src, noInx, noScale, noDisp, noImm)
				END;
				FreeReg (src) 
			ELSIF src IN SplittableReg THEN
				FreeReg (src);
				AssignThisReg (instr.dest, src MOD 8 + AL)
			ELSE
				GetSplittableReg (reg);
				OPO.GenMOV (RegReg, reg, src, noInx, noScale, noDisp, noImm);
				FreeReg (src); FreeReg (reg);
				AssignThisReg (instr.dest, reg MOD 8 + AL)
			END
		END;
	END GenShort;
		
	PROCEDURE GenPhi (VAR instr: Instruction);
		VAR src1, src2: SHORTINT;
	BEGIN
		ASSERT ((Instr [instr.src2].reg >= 0) & (Instr [instr.src1].reg # none));
		IF Instr [instr.src1].reg < 0 THEN src1 := -2 - Instr [instr.src1].reg
		ELSE
			src1 := Instr [instr.src1].reg;
			FreeReg (src1)
		END;
		src2 := Instr [instr.src2].reg;
		IF src1 # src2 THEN (* src1, src2 must be the same register *)
			AssignThisReg (instr.src2, src1); 
			OPO.GenMOV (RegReg, src1, src2, noInx, noScale, noDisp, noImm);
			IF src2 >= AL THEN
				DEC (src2, AL);
				sregTab [src2] := free;
				IF src2 < 4 THEN
					IF sregTab [src2 + 4] = free THEN regTab [src2] := free END
				ELSIF sregTab [src2 - 4] = free THEN regTab [src2 MOD 4] := free
				END
			ELSE regTab [src2 MOD 8] := free
			END
		END
	END GenPhi;

(* i387 Register *)

	PROCEDURE GetFreg (VAR freg: SHORTINT);
	(* returns any free floating point register *)
	BEGIN
		ftop := (ftop -1) MOD 8;
		IF fregTab [ftop] # free THEN
			OPM.err (216); RegErr := TRUE;
			freg := ftop;
			RETURN
		END;
		fregTab [ftop] := Occupied;
		freg := ftop
	END GetFreg;
	
	PROCEDURE FreeFreg (freg: SHORTINT);
	BEGIN
		IF freg > none THEN
			IF fregTab [freg] > free THEN Instr [fregTab [freg]].reg := -2-freg END;
			fregTab [freg] := free;
			IF freg = ftop THEN
				ftop := (ftop + 1) MOD 8;
				WHILE (FreeRegDisp > 0) & (fregTab [ftop] = free) DO
					ftop := (ftop + 1) MOD 8;
					DEC (FreeRegDisp)
				END
			ELSE OPO.GenFFREE ((freg-ftop) MOD 8); INC (FreeRegDisp)
			END
		END
	END FreeFreg;

	PROCEDURE ReleaseFreg (freg: SHORTINT);
	BEGIN
		IF freg > none THEN
			IF fregTab [freg] > free THEN Instr [fregTab [freg]].reg := -2-freg END;
			fregTab [freg] := free;
			ftop := (ftop + 1) MOD 8
		END
	END ReleaseFreg;

	PROCEDURE AssignFreg (pReg: LONGINT);
		VAR freg: SHORTINT;
	BEGIN
		GetFreg (freg);
		fregTab [freg] := pReg;
		Instr [pReg].reg := freg
	END AssignFreg;
	
	PROCEDURE TakeFreg (pReg: LONGINT; freg: SHORTINT);
	BEGIN
		ASSERT (fregTab[freg] = free);
		fregTab [freg] := pReg; Instr [pReg].reg := freg
	END TakeFreg;
	
	PROCEDURE FindFreg (pReg: LONGINT; VAR freg: SHORTINT);
	BEGIN
		ASSERT ((pReg >= 0) & (Instr [pReg].reg >= 0));
		freg := Instr [pReg].reg;
	END FindFreg;
	
	PROCEDURE LastUseF (freg: SHORTINT): BOOLEAN;
	BEGIN
		ASSERT ((freg IN {0..7}) & (fregTab [freg] >= 0));
		RETURN Instr[fregTab [freg]].used = 1
	END LastUseF;
	
	PROCEDURE DecCheckFreg (freg: SHORTINT);
		VAR pReg: LONGINT;
	BEGIN
		IF freg > none THEN
			pReg := fregTab [freg];
			DEC (Instr [pReg].used);
			IF Instr [pReg].used = 0 THEN FreeFreg (freg) END
		END
	END DecCheckFreg;

(* Risc Code -> i387 Code *)

	PROCEDURE Fload (VAR instr: Instruction);
		VAR
			mode, scale, size, base, inx: SHORTINT;
			disp: LONGINT;
	BEGIN
		FindMemReg (instr, mode, scale, size, base, inx, disp); size := ((size DIV 8)-3)*2;
		ASSERT (mode # RegReg);
		AssignFreg (instr.dest);
		IF instr.op DIV 32 = Fild THEN OPO.GenFLD (mode, OPO.sInt, base, inx, scale, disp)
		ELSE OPO.GenFLD (mode, size, base, inx, scale, disp)
		END;
		DecReg (base); DecReg (inx);
		IF (mode IN {RegMem, MemReg}) & (base = noBase) & ~instr.abs THEN (* absolute access *)
			AbsAccess (instr.node, OPO.pc - 4)
		END
	END Fload;
	
	PROCEDURE Fstore (VAR instr: Instruction);
		VAR
			mode, scale, size, base, inx, src: SHORTINT;
			disp: LONGINT;
	BEGIN
		FindMemReg (instr, mode, scale, size, base, inx, disp); size := ((size DIV 8)-3)*2;
		IF instr.op DIV 32 = Fist THEN size := sInt END;
		FindFreg (instr.dest, src);
		ASSERT (LastUseF (src) & (src = ftop));
		OPO.GenFSTP (mode, size, base, inx, scale, disp);
		DecCheckFreg (src); DecReg (base); DecReg (inx);
		IF (mode IN {RegMem, MemReg}) & (base = noBase) & ~instr.abs THEN (* absolute access *)
			AbsAccess (instr.node, OPO.pc - 4)
		END;
		OPO.PutByte (OPO.WAIT)
	END Fstore;
	
	PROCEDURE FloatGen1 (VAR instr: Instruction);
		VAR src: SHORTINT;
	BEGIN
		FindFreg (instr.src1, src);
		ASSERT (LastUseF (src) & (src = ftop));
		ReleaseFreg (src); AssignFreg (instr.dest);
		IF instr.op DIV 32 = Fabs THEN OPO.GenFop1 (FABS)
		ELSE
			ASSERT (instr.op DIV 32 = Fchs);
			OPO.GenFop1 (FCHS)
		END;
	END FloatGen1;
	
	PROCEDURE FloatGen3 (VAR instr: Instruction);
		VAR
			mode, size, src, src1, src2: SHORTINT;
			reverse, r2: BOOLEAN;
	BEGIN
		size := SHORT (((instr.op MOD 8) -3) *2);
		FindFreg (instr.src1, src1); FindFreg (instr.src2, src2);
		r2 := FALSE;
		IF ~LastUseF (src1) & ~ LastUseF (src2) THEN
			(* copy src1->ST *)
			OPO.GenFLD (Regs, size, (src1 - ftop) MOD 8, noInx, noScale, noDisp);
			(* src := src2, ST := src1 *)
			src := src2;
			mode := RegSt;
			reverse := FALSE;
		ELSIF src1 = ftop THEN
			reverse := TRUE;
			IF LastUseF (src1) THEN
				IF LastUseF (src2) THEN mode := StRegP ELSE mode := RegSt; reverse := FALSE END
			ELSE mode := StReg
			END;
			(* src := src2, ST := src1 *)
			src := src2;
		ELSIF src2 = ftop THEN
			(* REVERSE *)
			reverse := FALSE; r2 := TRUE;
			IF LastUseF (src2) THEN
				IF LastUseF (src1) THEN mode := StRegP ELSE mode := RegSt; reverse := TRUE END
			ELSE mode := StReg
			END;
			(* src := src1, ST := src2 *)
			src := src1
		ELSE
			(* copy src1->ST *)
			OPO.GenFLD (Regs, size, (src1 - ftop) MOD 8, noInx, noScale, noDisp);
			IF LastUseF (src1) THEN FreeFreg (src1); src1 := none END;
			IF LastUseF (src2) THEN mode := StRegP; reverse := TRUE ELSE mode := RegSt; reverse := FALSE END;
			(* src := src2, ST := src1 *)
			src := src2
		END;
		CASE instr.op DIV 32 OF
			Fadd: OPO.GenFADD (mode, size, (src - ftop) MOD 8, noInx, noScale, noDisp)
		  | Fsub:
				IF reverse THEN OPO.GenFSUBR (mode, size, (src - ftop) MOD 8, noInx, noScale, noDisp)
				ELSE OPO.GenFSUB (mode, size, (src - ftop) MOD 8, noInx, noScale, noDisp)
				END
		  | Fmul: OPO.GenFMUL (mode, size, (src - ftop) MOD 8, noInx, noScale, noDisp)
		  | Fdiv:
				IF reverse THEN OPO.GenFDIVR (mode, size, (src - ftop) MOD 8, noInx, noScale, noDisp)
				ELSE OPO.GenFDIV (mode, size, (src - ftop) MOD 8, noInx, noScale, noDisp)
				END
		ELSE HALT (BUG)
		END;
		IF r2 THEN DecCheckFreg (src2); DecCheckFreg (src1) ELSE DecCheckFreg (src1); DecCheckFreg (src2) END;
		IF mode = RegSt THEN AssignFreg (instr.dest)
		ELSIF (mode = StRegP) & ((src+1)MOD 8 = ftop) THEN AssignFreg (instr.dest)
		ELSE TakeFreg (instr.dest, src) END
	END FloatGen3;

	PROCEDURE FloatCmp (VAR instr: Instruction);
		VAR size, src1, src2, reg: SHORTINT; stackOK: BOOLEAN;
	BEGIN
		size := SHORT (((instr.op MOD 8) -3)*2);
		FindFreg (instr.src1, src1); FindFreg (instr.src2, src2);
		ASSERT (LastUseF (src1) & LastUseF (src2));
		IF src1 = ftop THEN
			IF src2 = (ftop + 1) MOD 8 THEN
				OPO.GenFop1 (FCOMPP); stackOK := TRUE
			ELSE
				OPO.GenFCOMP (Regs, size, (src2 - ftop) MOD 8, noInx, noScale, noDisp);
				stackOK := FALSE
			END
		ELSE
			stackOK := FALSE;
			GetFreg (reg);
			OPO.GenFLD (Regs, size, (src1-ftop-1) MOD 8, noInx, noScale, noDisp);
			OPO.GenFCOMP (Regs, size, (src2-ftop) MOD 8, noInx, noScale, noDisp);
			ReleaseFreg (reg)
		END;
		GetThisReg (EAX);
		OPO.GenFop1 (FSTSW); (* flags into AX *)
		OPO.PutByte (SAHF); (* store ah into flags *);
		IF stackOK THEN
			DecCheckFreg (src1); DecCheckFreg (src2)
		ELSE
			DecCheckFreg (src1); DecCheckFreg (src2);
			OPO.GenFFREE (0)
		END;
		FreeReg (EAX)
	END FloatCmp;

	PROCEDURE GenEntier (VAR instr: Instruction);
		VAR dest, src, reg, dummy: SHORTINT;
	(*
		sub esp, 8
		fstcw 0[esp]
		wait
		mov dest, 0[esp]
		and dest, 1111001111111111B (* !!later -> can be removed ? *)
		or dest, 0000010000000000B
		mov 0[esp], dest
		fldcw 0[esp]
		fist 4[esp] or fistp 4[esp] or fld src, fistp 4[esp]
		wait
		fstcw 0[esp]
		wait
		and 0[esp], 1111001111111111B
		fldcw 0[esp]
		mov dest, 4[esp]
		add esp, 8
	*)
	BEGIN
		FindFreg (instr.src1, src);
		dummy := none; AssignReg (instr.dest, dummy, dummy, dummy);
		dest := instr.reg;
		ASSERT (dest  IN {EAX..EDI});
		OPO.GenTyp1 (OPO.SUB, ImmReg, ESP, noBase, noInx, noScale, noDisp, 8);
		OPO.GenFSTCW (ESP, noInx, noScale, 0);
		OPO.PutByte (OPO.WAIT);
		OPO.GenMOV (MemReg, dest, ESP, noInx, noScale, 0, noImm);
		(*OPO.GenTyp1 (OPO.AND, ImmReg, dest, noBase, noInx, noScale, noDisp, 0F3FFH);*)	(*prk removed*)
		OPO.GenTyp1 (OPO.Or, ImmReg, dest, noBase, noInx, noScale, noDisp, 0400H);
		OPO.GenMOV (RegMem, dest, ESP, noInx, noScale, 4, noImm);
		OPO.GenFLDCW (ESP, noInx, noScale, 4);
		IF ~LastUseF (src) THEN 
			IF src # ftop THEN (* can only store ftop *)
				GetFreg (reg);
				OPO.GenFLD (Regs, reg, src, noInx, noScale, noDisp);
				OPO.GenFSTP (RegMem, OPO.sInt, ESP, noInx, noScale, 4);
				ReleaseFreg (reg)
			ELSE OPO.GenFST (RegMem, OPO.sInt, ESP, noInx, noScale, 4)
			END
		ELSE OPO.GenFSTP (RegMem, OPO.sInt, ESP, noInx, noScale, 4)
		END;
		OPO.PutByte (OPO.WAIT);
(*	(*prk removed*)
		OPO.GenFSTCW (ESP, noInx, noScale, 0);
		OPO.PutByte (OPO.WAIT);
		OPO.GenTyp1 (OPO.AND, ImmMem, Bit32, ESP, noInx, noScale, 0, 0F3FFH);
*)
		OPO.GenFLDCW (ESP, noInx, noScale, 0);
		OPO.GenMOV (MemReg, dest, ESP, noInx, noScale, 4, noImm);
		OPO.GenTyp1 (OPO.ADD, ImmReg, ESP, noBase, noInx, noScale, noDisp, 8);
		DecCheckFreg (src)
	END GenEntier;

	PROCEDURE ClearSDynArr(VAR instr: Instruction);
		VAR L: LONGINT; reg: SHORTINT;
	BEGIN
		FindReg(instr.src1, reg);
		OPO.GenTyp1 (XOR, RegReg, EAX, EAX, noInx, noScale, noDisp, noImm);
		L := OPO.pc;
		OPO.GenPUSH (Regs, EAX, noBase, noInx, noScale, noDisp, noInx);
		OPO.GenDEC (ImmReg, reg, noBase, noInx, noScale, noDisp);
		OPO.GenJcc (JG, L - (OPO.pc + 2));
		FreeReg(reg);
	END ClearSDynArr;

(* general *)

	PROCEDURE GenEnter (locSize: LONGINT; locals: OPT.Object; sysflag: SHORTINT);
		VAR first: BOOLEAN; enoff, ensize: LONGINT;

			last: LONGINT;		(*static local for ClearStack: last offset touched*)

		PROCEDURE ClearStack(off, size: LONGINT);
			VAR L: LONGINT;
		BEGIN
			IF first THEN
				OPO.GenTyp1 (XOR, RegReg, EAX, EAX, noInx, noScale, noDisp, noImm);
				first := FALSE;
				last := 0;
			END;
			WHILE last - off-size > 4096 DO
				DEC(last, 4096);
				OPO.GenMOV (RegMem, EAX, EBP, noInx, noScale, last, noImm);
			END;
			last := off;
			IF size <= 5*4 THEN
				WHILE size >= 4 DO
					DEC(size, 4);
					OPO.GenMOV (RegMem, EAX, EBP, noInx, noScale, off+size, noImm);	(*offsets are negative, reverse traversal*)
				END
			ELSE
				OPO.GenMOV (ImmReg, ECX, noBase, noInx, noScale, noDisp, size DIV 4);
				OPO.GenLEA (EBX, EBP, noInx, noScale, off);
				L := OPO.pc;
				OPO.GenDEC (ImmReg, ECX, noBase, noInx, noScale, noDisp);
				OPO.GenMOV (RegMem, EAX, EBX, ECX, Scale4, noDisp, noImm);
				OPO.GenJcc (JNZ, L - (OPO.pc + 2))
			END
		END ClearStack;
		
		PROCEDURE TraverseLocals(offset: LONGINT; obj: OPT.Object);
			(*!!! The locals are traversed in descending order (list traversal), the recfields are traversed
				using a recursive postfix traversal to reverse the list !!!*)
			VAR	size, adr, oldoff, oldsize: LONGINT; t: OPT.Struct;
			
			PROCEDURE TraverseRecord(offset: LONGINT; t: OPT.Struct);
			BEGIN
				IF t.BaseTyp # NIL THEN TraverseRecord(offset, t.BaseTyp) END;
				TraverseLocals(offset, t.link)
			END TraverseRecord;
		BEGIN
			WHILE obj # NIL DO
				WHILE (obj#NIL) & ~(obj.mode IN {Var, Fld}) DO obj := obj.link END;
				IF obj # NIL THEN
					IF obj.mode = Fld THEN	TraverseLocals(offset, obj.link)	END;	(*rec-fields: first traverse the rest of list*)
					t := obj.typ;  size := 0;
					IF obj.mode = Var THEN  adr := obj.linkadr  ELSE adr := offset+obj.adr  END;
					IF (t.form = Pointer) OR (t.form = ProcTyp) OR (obj.name = OPT.HdPtrName) THEN	size := 4
					ELSIF t.comp = Record THEN
						WHILE t # NIL DO
							TraverseLocals(adr, t.link);  t := t.BaseTyp
						END;
						size := 0
					ELSIF t.comp = StaticArr THEN
						WHILE t.comp = StaticArr DO  t := t.BaseTyp  END;
						IF (t.form = Pointer) OR (t.form = ProcTyp) THEN
							size := obj.typ.size
						ELSIF t.comp = Record THEN
							oldoff := enoff; oldsize := ensize; enoff := 0; ensize := 0;
							TraverseLocals(10000, t.link);
							IF ensize # 0 THEN	(*contains pointers*)
								size := obj.typ.size
							END;
							enoff := oldoff; ensize := oldsize;
						END
					END;
					INC(size, (-size) MOD 4);		(* round-up*)
					IF size = 0 THEN	(*no pointers*)
					ELSIF (offset <= 0) & (enoff # adr+size) THEN	(*new entry*)
						IF ensize # 0 THEN ClearStack(enoff, ensize) END;
						enoff := adr;  ensize := size;
					ELSE
						INC(ensize, size);
						enoff := adr;
					END;
					IF obj.mode = Var THEN obj := obj.link ELSE obj := NIL  END;		(*vars: traverse the rest of the list, list tail-recursion*)
				END;
			END;
		END TraverseLocals;
		
		PROCEDURE FullClearStack(size: LONGINT);		(*size in doublewords*)
			VAR  i: LONGINT;
		BEGIN
			ASSERT(size > 0, 100);
			IF size < 8 THEN
				OPO.GenTyp1 (XOR, RegReg, EAX, EAX, noInx, noScale, noDisp, noImm);
				WHILE size > 0 DO
					OPO.GenPUSH(Regs, EAX, noBase, noInx, noScale, noDisp, noImm);  DEC(size)
				END
			ELSE
				OPO.GenMOV(ImmReg, ECX, noBase, noInx, noScale, noDisp, size DIV 4);
				OPO.GenTyp1 (XOR, RegReg, EAX, EAX, noInx, noScale, noDisp, noImm);
				i := size MOD 4;
				WHILE i > 0 DO
					OPO.GenPUSH(Regs, EAX, noBase, noInx, noScale, noDisp, noImm);  DEC(i)
				END;
				OPO.GenDEC(Imme, ECX, noBase, noInx, noScale, noDisp);
				OPO.GenPUSH(Regs, EAX, noBase, noInx, noScale, noDisp, noImm);
				OPO.GenPUSH(Regs, EAX, noBase, noInx, noScale, noDisp, noImm);
				OPO.GenPUSH(Regs, EAX, noBase, noInx, noScale, noDisp, noImm);
				OPO.GenPUSH(Regs, EAX, noBase, noInx, noScale, noDisp, noImm);
				OPO.GenJcc(OPO.JNZ, -7)
			END
		END FullClearStack;
		
	BEGIN
		ASSERT (locSize MOD 4 = 0);
		OPO.GenPUSH (Regs, EBP, noBase, noInx, noScale, noDisp, noImm);
		OPO.GenMOV (RegReg, EBP, ESP, noInx, noScale, noDisp, noImm);
		IF (locSize # 0) THEN
			IF (OPM.ptrinit IN OPM.options) THEN
				first := TRUE;
				IF (OPM.fullstackinit IN OPM.options) THEN
					FullClearStack(locSize DIV 4)
				ELSE
					OPO.GenTyp1 (SUB, ImmReg, ESP, noBase, noInx, noScale, noDisp, locSize);
					enoff := 0; ensize := 0;
					TraverseLocals(0, locals);
					IF ensize # 0 THEN ClearStack(enoff, ensize) END;
					ClearStack(-locSize, 0);		(*force touch of the whole remaining stack*)
				END
			ELSE
				OPO.GenTyp1 (SUB, ImmReg, ESP, noBase, noInx, noScale, noDisp, locSize);
				ClearStack(-locSize, 0)		(*force touch of the whole remaining stack*)
			END
		END;
		IF (sysflag = stdcall) OR (sysflag = cdecl) THEN
			OPO.GenPUSH (Regs, EBX, noBase, noInx, noScale, noDisp, noImm);
			OPO.GenPUSH (Regs, ESI, noBase, noInx, noScale, noDisp, noImm);
			OPO.GenPUSH (Regs, EDI, noBase, noInx, noScale, noDisp, noImm)
		END
	END GenEnter;
					
	PROCEDURE GenLeave (sysflag: SHORTINT); (* ejz *)
	BEGIN
		IF (sysflag = stdcall) OR (sysflag = cdecl) THEN
			OPO.GenPOP (Regs, EDI, noBase, noInx, noScale, noDisp);
			OPO.GenPOP (Regs, ESI, noBase, noInx, noScale, noDisp);
			OPO.GenPOP (Regs, EBX, noBase, noInx, noScale, noDisp)
		END;
		OPO.GenMOV (RegReg, ESP, EBP, noInx, noScale, noDisp, noImm);
		OPO.GenPOP (Regs, EBP, noBase, noInx, noScale, noDisp)
	END GenLeave;
					
	PROCEDURE PushRegs;
		VAR i: SHORTINT; disp: LONGINT;
	BEGIN
		IF nofSavedLevel > MaxSaveLevel THEN OPM.err (251)
		ELSE
			i := 0;
			WHILE i < 8 DO
				savedRegs [nofSavedLevel].sreg [i] := SHORT (sregTab [i]);
				savedRegs [nofSavedLevel].reg [i] := SHORT (regTab [i]);
				IF (regTab [i] # free) & ~(i IN {ESP, EBP}) THEN
					OPO.GenPUSH (Regs, i, noBase, noInx, noScale, noDisp, noImm);
					regTab [i] := free
				END;
				INC (i)
			END;
			disp := 0; i := 0;
			WHILE i < 8 DO
				IF fregTab [i] # free THEN INC (disp, 8) END;
				INC (i)
			END;
			i := 0;
			IF disp > 0 THEN
				OPO.GenTyp1 (SUB, ImmReg, ESP, noBase, noInx, noScale, noDisp, disp);
				disp := disp - 8;
				WHILE disp >= 0 DO
					IF fregTab [ftop] # free THEN
						OPO.GenFSTP (RegMem, lReal, ESP, noInx, noScale, disp);
						savedRegs [nofSavedLevel].freg [i] := SHORT (fregTab [ftop]);
						INC (i);
						fregTab [ftop] := free;
						DEC (disp, 8);
					ELSE OPO.GenFop1(OPO.FINCSTP) (* increment stack top *)
					END;
					ftop := (ftop + 1) MOD 8;
				END;
				OPO.PutByte (OPO.WAIT);
			END;
			WHILE i < 8 DO
				savedRegs [nofSavedLevel].freg [i] := free;
				INC (i)
			END;
			INC (nofSavedLevel)
		END
	END PushRegs;
	
	PROCEDURE PopRegs (VAR instr: Instruction);
		VAR 
			i, j, size, freg: SHORTINT; 
			Eax: INTEGER;
			disp: LONGINT;
	BEGIN
		DEC (nofSavedLevel);
		IF instr.hint # noHint THEN
			size := SHORT ((instr.op MOD 8) * 8) (* procedure with result *)
		ELSE size := -1;
		END;
		i := 7;
		WHILE (i >= 0) & (savedRegs [nofSavedLevel].freg[i] = free) DO DEC (i) END;
		IF (instr.hint = useST) & (i >= 0) THEN (* save result *)
			disp := 8;
			OPO.GenTyp1 (SUB, ImmReg, ESP, noBase, noInx, noScale, noDisp,  8);
			OPO.GenFSTP (RegMem, lReal, ESP, noInx, noScale, 0);
			OPO.PutByte (OPO.WAIT);
			fregTab [ftop] := free;
			ftop := (ftop + 1) MOD 8
		ELSE disp := 0
		END;
		j := i;
		WHILE j >= 0 DO
			GetFreg (freg); OPO.GenFLD (Mem, lReal, ESP, noInx, noScale, disp);
			fregTab [freg] := savedRegs [nofSavedLevel].freg [j];
			Instr [fregTab [freg]].reg := freg;
			INC (disp, 8);
			DEC (j) 
		END;
		IF instr.hint = useST THEN
			size := -1;
			IF i >= 0 THEN (* load result *)
				GetFreg (freg); OPO.GenFLD (Mem, lReal, ESP, noInx, noScale, 0);
				fregTab [freg] := instr.dest; instr.reg := freg;
			ELSE
				fregTab [ftop] := instr.dest;
				instr.reg := ftop (* result already on the stack *)
			END
		END;
		IF disp > 0 THEN OPO.GenTyp1 (ADD, ImmReg, ESP, noBase, noInx, noScale, noDisp, disp) END;
		IF size = Bit8 THEN
			regTab[EAX] := Splitted; sregTab [0] := instr.dest; sregTab [4] := free;
			instr.reg := EAX + size
		ELSIF (size = Bit16) OR (size = Bit32) THEN
			regTab[EAX] := instr.dest;
			instr.reg := EAX + size (* result in EAX, AX, AL *)
		ELSIF (size = Bit64) THEN
			regTab[EAX] := instr.dest; regTab[EDX] := instr.src1;
			instr.reg := EAX;  Instr[instr.src1].reg := EDX
		END;
		
		i := EDI;
		WHILE i >= EAX DO
			IF (savedRegs [nofSavedLevel].reg[i] = free) THEN
				(* nothing to do *)
			ELSIF (i IN {ESP, EBP}) THEN
				sregTab [i] := savedRegs [nofSavedLevel].sreg[i];	(* restore only *)
				regTab [i] := savedRegs [nofSavedLevel].reg [i];
			ELSIF regTab [i] = free THEN
				sregTab [i] := savedRegs [nofSavedLevel].sreg[i];	(* restore *)
				regTab [i] := savedRegs [nofSavedLevel].reg [i];
				OPO.GenPOP (Regs, i, noBase, noInx, noScale, noDisp)
			ELSE		(* troubles, already in use *)
				(* find free register *)
				j := EBX; WHILE (j > i) & (regTab[j] # free) DO DEC(j) END;
				IF j = i THEN
					j := EBX; WHILE (j > i) & (regTab[j] # Splitted) DO DEC(j) END;
					IF j = i THEN  OPM.err (215); RegErr := TRUE; RETURN  END
				END;
				GetThisReg(j);
				OPO.GenPOP(Regs, j, noBase, noInx, noScale, noDisp);
				sregTab[j] := savedRegs[nofSavedLevel].sreg[i];
				regTab[j] := savedRegs [nofSavedLevel].reg[i];
				
				IF regTab[j] = Splitted THEN
					IF sregTab[j] >= 0 THEN Instr[sregTab[j]].reg := j + AL END;
					IF sregTab[j+4] >= 0 THEN Instr[sregTab [j+4]].reg := j+4 + AL END
				ELSIF (Instr[regTab[j]].op MOD 8 = 1) THEN	(*size = Bit16*)
					Instr[regTab[j]].reg := j+AX
				ELSE
					Instr[regTab[j]].reg := j
				END
(*												
				IF regTab[j] # Splitted THEN
					Instr[regTab[j]].reg := j 
				ELSE
					IF sregTab[j] >= 0 THEN Instr[sregTab[j]].reg := j + AL END;
					IF sregTab[j+4] >= 0 THEN Instr[sregTab [j+4]].reg := j+4 + AL END
				END
*)
			END;
			DEC(i)
		END;
(*		
		i := EDI;
		WHILE i > EAX DO
			sregTab [i] := savedRegs [nofSavedLevel].sreg[i];
			regTab [i] := savedRegs [nofSavedLevel].reg [i];
			IF (regTab [i] # free) & ~(i IN {ESP, EBP}) THEN OPO.GenPOP (Regs, i, noBase, noInx, noScale, noDisp) END;
			DEC (i)
		END;
		sregTab [0] := savedRegs [nofSavedLevel].sreg[0];
		Eax := savedRegs [nofSavedLevel].reg [EAX];
		IF size # -1 THEN (* procedure with integer result *)
			IF Eax # free THEN (* conflict with the pushed EAX *)
				IF Eax = Splitted THEN
					regTab [EAX] := Splitted;
					i := EBX; WHILE (i > EAX) & (regTab [i] # free) DO DEC (i) END;
					IF i = EAX THEN
						i := EBX; WHILE (i > EAX) & (regTab [i] # Splitted) DO DEC (i) END;
						IF i = EAX THEN
							OPM.err (215); RegErr := TRUE;
							RETURN
						END
					END;
					GetThisReg (i);
					OPO.GenPOP (Regs, i, noBase, noInx, noScale, noDisp);
					regTab [i] := Splitted;
					sregTab [i] := sregTab [0];
					IF sregTab [0] >= 0 THEN Instr [sregTab [0]].reg := i + AL END;
					INC (i, 4);
					sregTab [i] := sregTab [4];
					IF sregTab [4] >= 0 THEN Instr [sregTab [4]].reg := i + AL END;
				ELSE
					regTab [EAX] := Eax;
					AssignNewReg (Eax);
					OPO.GenPOP (Regs, Instr [regTab [EAX]].reg MOD 8, noBase, noScale, noInx, noDisp)
				END
			END;
			IF size = Bit8 THEN
				regTab [EAX] := Splitted; sregTab [0] := instr.dest; sregTab [4] := free
			ELSE regTab [EAX] := instr.dest
			END;
			instr.reg := EAX + size (* result in EAX, AX, AL *)
		ELSE
			regTab [EAX] := Eax;
			IF Eax # free THEN OPO.GenPOP (Regs, EAX, noBase, noInx, noScale, noDisp) END
		END
*)
	END PopRegs;
				
	PROCEDURE FixupJcc (label: LONGINT);
		VAR pos, nextLabel: LONGINT;
	BEGIN
		WHILE label # Nil DO
			IF Instr [label].op = jmp THEN pos := Instr [label].pc + 1
			ELSE (* jcc *) pos := Instr [label].pc + 2
			END;
			OPO.GetDWord (pos, nextLabel);
			OPO.PutDWordAt (pos, OPO.pc - (pos + 4));
			label := -2 - nextLabel - 10000H
		END
	END FixupJcc;
	
	PROCEDURE FixupCaseTab (VAR instr: Instruction);
		VAR elseLabel, from, to, val, caseFixup: LONGINT;
	BEGIN
		caseFixup := link [0].offset;
		elseLabel := Instr [instr.src2].pc;
		from := instr.src1; to := instr.src1 + instr.inx - 4; (* instr.inx = length *)
		WHILE from <= to DO
			OPO.GetConsDWord (from, val);
			IF val = Nil THEN val := elseLabel
			ELSE val := Instr [val].pc
			END;
			IF from = to THEN (* last case table entry *)
				IF caseFixup >= 32768 THEN val := (caseFixup - 10000H) * 10000H + val
				ELSE val := caseFixup * 10000H + val
				END
			ELSE
				IF from + 4 >= 32768 THEN val := (from + 4 - 10000H) * 10000H + val
				ELSE val := (from + 4) * 10000H + val
				END
			END;
			OPO.PutConsDWord (from, val);
			from := from + 4
		END;
		link [0].offset := SHORT (instr.src1)
	END FixupCaseTab;

	PROCEDURE EncodeFixup (i: LONGINT);
		VAR 
			L, L1: LONGINT;
			node: OPT.Node;
	BEGIN
		node := Instr [i].node;
		node.left.obj.linkadr := -2 - Instr[i].pc - 10000H;
		L := i;
		WHILE L > Nil DO
			OPO.GetDWord (Instr[L].pc + 1, L1);
			IF (L1 > -10000H) & (-2 - L1 > Nil) THEN
				L1 := -2 - L1;
				OPO.PutDWordAt (Instr[L].pc + 1, -2 - Instr[L1].pc - 10000H) 
			END;
			L := L1
		END
	END EncodeFixup;

	PROCEDURE GenAsm ( instr: Instruction );
		VAR n, code, fix: OPT.Node; pc: LONGINT;
	BEGIN
		pc := OPO.pc; n := instr.node;
		code := n.left;
		WHILE code # NIL DO
			OPO.InlineCode (code.conval.ext^, 0); code := code.link
		END;
		fix := n.right;
		WHILE fix # NIL DO
			IF (fix.obj.mode = Var) & (fix.obj.mnolev <=0) THEN
				OPO.PutDWordAt(pc + fix.conval.intval, fix.obj.linkadr);
				AbsAccess (fix, pc + fix.conval.intval)
			ELSIF (fix.obj.linkadr <= MAX(SHORTINT)) & (fix.obj.linkadr >= MIN(SHORTINT)) THEN
				OPO.PutByteAt(pc + fix.conval.intval, SHORT(SHORT(fix.obj.linkadr)))
			ELSE
				OPM.Mark(600,SHORT(fix.conval.intval2))
			END;
			fix := fix.link
		END
	END GenAsm;

	PROCEDURE GenCode* (pSize: INTEGER);
		VAR 
			obj, list: OPT.Object;
			i, k: LONGINT;
			op, reg, ret, sysflag: SHORTINT;
			node: OPT.Node;
			
		PROCEDURE MarkPos;
		VAR j : LONGINT;
		BEGIN
			IF mapSize < LEN(map^) THEN
				map[mapSize].pos := Instr[i].src1;
				map[mapSize].pc := OPO.pc;
				j := mapSize-1;
				WHILE (j>= 0) & (map[j].pos < 0) DO
					map[j].pos := map[mapSize].pos; DEC(j)
				END;
				INC(mapSize)
			ELSE
				map[mapSize-1].pos := -1; map[mapSize-1].pc := -1
			END
		END MarkPos;

	BEGIN
		ftop := 7; FreeRegDisp := 0;
		i := 0;
		WHILE i < nofTrapFixups DO
			trapFixupTab [i] := Nil;
			INC (i)
		END;
		i := 0;
		WHILE i < 8 DO
			regTab [i] := free; sregTab [i] := free; fregTab [i] := free;
			INC (i)
		END;
		regTab [ESP] := Occupied; regTab [EBP] := Occupied; (* stack and base pointer are always used *)
		RegErr := FALSE;
		i := 0;
		WHILE ~OPO.CodeErr & ~RegErr & (i < pSize) DO
(*
			IF (Label = SHORT (Instr [i].op DIV 32)) THEN
				WHILE (OPO.pc MOD 16) # 15 DO
					IF ~ODD(OPO.pc) THEN OPO.PutByte(90H)  ELSE  OPO.PutByte(89H); OPO.PutByte(0E4H)  END
				END;
			END;
*)
			node := Instr [i].node;
			FixupJcc (Instr [i].pc);
			Instr [i].pc := OPO.pc;
			op := SHORT (Instr [i].op DIV 32);
			IF op > 0 THEN (* no dead code *)
(*
				OPM.LogWLn; OPM.LogWNum(i, 3); OPM.LogWNum(op, 4);
				OPM.LogWNum(Instr[i].op MOD 8, 2);
				OPM.LogWNum(Instr[i].op DIV 8 MOD 4, 2);
				OPM.LogWNum(Instr[i].dest, 4);
				OPM.LogWNum(Instr[i].src1, 4);
				OPM.LogWNum(Instr[i].src2, 4);
				OPM.LogWNum(Instr[i].inx, 4);
				OPM.LogWNum(Instr[i].hint, 4);
*)
				CASE op OF
					NewStat: OPM.errpos := Instr [i].src1;
						IF map # NIL THEN MarkPos END;
				  | Ld, Lea, Ldbdw, Ldwdw, Ldbw, Ldbdwu, Ldwdwu, Ldbwu, PUTreg: Load (Instr [i])
				  | LdProc, LdXProc: LoadProc (Instr [i])
				  | Sto, GETreg: Store (Instr [i])
				  | Push: GenPush (Instr [i])
				  | Pop: GenPop (Instr [i])
				  | Add, Sub, oR..Rol: Gen3 (Instr [i])
				  | Div, Mod: GenDivMod (Instr [i])
				  | Mul: GenMul (Instr [i])
				  | Neg, Not: Gen2 (Instr [i])
				  | Abso: GenAbs (Instr [i])
				  | Cmp, Bt, Test: Flags (Instr [i])
				  | Sete..Setnc: Setcc (Instr [i])
				  | Je..JmpReg: Gen1 (Instr [i], i)
				  | Te..Ta, To, Tae, Tle: GenTrapCC (Instr [i])
				  | Trap: GenTrap (Instr[i].src2)
				  | Call:
						node := Instr [i].node;
						obj := node.left.obj;
						IF obj.mode = CProc THEN (* code procedure, inline expansion *)
							HALT(99)
						ELSIF Instr [i].src2 >= 0 THEN (* backward call *)
							OPO.GenCALL (Imme, none, noBase, noInx, noScale, Instr [i].src2 - (OPO.pc+5))
						ELSE (* forward call *)
							OPO.GenCALL (Imme, none, noBase, noInx, noScale, Instr [i].src2);
							IF -2 - node.left.obj.linkadr = i THEN (* last call in the pseudo code *)
								EncodeFixup (i)
							END (* ELSE fixup follows later *)
						END
				  | Xcall:
						OPO.GenCALL (Imme, none, noBase, noInx, noScale, 0);
						AddLink (Instr [i].src2 DIV 10000H, Instr [i].pc + 1)
				  | CallReg: (* !!later optimize *)
						FindReg (Instr [i].src2, reg);
						OPO.GenCALL (Regs, reg, noBase, noInx, noScale, noDisp);
						DecReg (reg)
				  | Enter:
				  	  IF map # NIL THEN MarkPos END;
				  	  IF node # NIL THEN
				  	  	list := node.obj.scope.scope;
				  	  	sysflag := node.obj.sysflag
				  	  ELSE
				  	  	list := NIL;
				  	  	sysflag := 0
				  	  END;
				  	  GenEnter(Instr[i].src2, list, sysflag);
				  | Leave: (* !!later optmize if ESP = EBP *)
						GenLeave(sysflag)
				  | Ret:
						k := EAX; ret := -1;
						WHILE k <= EDI DO
							IF ~(k IN {ESP, EBP}) & (regTab [k] # free) THEN
								IF ret = -1 THEN ret := SHORT(SHORT(k))
								ELSIF (ret = EAX) & (k = EDX) THEN  FreeReg(EDX)		(* 8Byte, special *)
								ELSE OPM.err (200);
								END
							END;
							INC (k)
						END;
						IF ret # -1 THEN (* copy from ret to AX, free ret *)
							IF (regTab [ret] = Splitted) & (sregTab [ret+4] # free) THEN (* using AH/BH/CH/DH *)
									OPO.GenMOV(RegReg, AL, AH+ret, noInx, noScale, noDisp, noImm)
							ELSIF ret # EAX THEN OPO.GenMOV(RegReg, EAX, ret, noInx, noScale, noDisp, noImm)
							END;
							IF regTab[ret] = Splitted THEN FreeReg (ret + Bit8); FreeReg (ret + Bit8 + 4)
							ELSIF regTab [ret] # free THEN FreeReg (ret)
							END
						END;
						IF fregTab [ftop] # free THEN FreeFreg (ftop) END;
						k := 0;
						WHILE k < 8 DO 
							IF fregTab[k] # free THEN OPM.err (-1001); 
								(* OPM.LogWStr ("  "); OPM.LogWNum (k, 6); OPM.LogWNum (fregTab [k], 8) *)
							END; 
							INC (k)
						END;
						IF FreeRegDisp # 0 THEN OPM.LogWLn; OPM.LogWStr ("Error FreeReg"); OPM.LogWLn END;
						IF sysflag = cdecl THEN
							OPO.GenRET (0)
						ELSE
							OPO.GenRET (Instr [i].src2)
						END
				  | RepMovs: GenRepMovs (Instr [i])
				  | CmpString: GenCmpString (Instr [i])
				  | Cld: OPO.PutByte (CLD)
				  | Std: OPO.PutByte(STD)
				  | PushReg: PushRegs
				  | PopReg: PopRegs (Instr [i]) 
				  | Case: FixupCaseTab (Instr [i])
				  | Phi: GenPhi (Instr [i])
				  | Short: GenShort (Instr [i])
				  | Entier: GenEntier (Instr [i])
				  | Label: (* only used for jumps *)
				  | FLoad, Fild: Fload (Instr [i])
				  | FStore, Fist: Fstore (Instr [i])
				  | Fabs, Fchs: FloatGen1 (Instr [i])
				  | Fadd, Fsub, Fmul, Fdiv: FloatGen3 (Instr [i])
				  | Fcmp: FloatCmp (Instr [i])
				  | Cli: OPO.PutByte(CLI)
				  | Sti: OPO.PutByte(STI)
				  | In, Out: GenPortIO(Instr [i])
				  | Assembler: GenAsm(Instr[i])
				  | Clear: ClearSDynArr(Instr[i])
				ELSE HALT (BUG)
				END
			END;
			INC (i)
		END;
		FixupAndGenTrap (* fixups traps and generate code for them *)
	END GenCode;

(* fixups *)
	
	PROCEDURE FixupLocalProcCall* (proc: OPT.Object);
		VAR L, L1, entryNr: LONGINT;
	BEGIN
		IF (proc.linkadr < 0) & ~(proc.mode IN {TProc, Typ}) THEN 
			L := -2 - proc.linkadr - 10000H;
			WHILE L > Nil DO
				OPO.GetDWord (L+1, L1);
				OPO.PutDWordAt (L+1, OPO.pc - (L + 5));
				L := -2 - L1 - 10000H
			END
		END;
		proc.linkadr := OPO.pc;
		IF (proc.mode IN {XProc, TProc, Typ}) THEN
			IF proc.mode IN {TProc, Typ} THEN entryNr := proc.adr MOD 10000H
			ELSE entryNr := proc.adr
			END;
			IF OPO.pc > 32767 THEN
				entry [entryNr] := SHORT (OPO.pc - 65536)
			ELSE entry [entryNr] := SHORT (OPO.pc)
			END
		END
	END FixupLocalProcCall;

(* object file *)

	PROCEDURE NewVarCons* (mod, entry: INTEGER; VAR index: LONGINT);
	VAR i: LONGINT;  var: VarConsTable;
	BEGIN
		IF nofVarCons >= LEN(varConsLink) THEN
			NEW(var, LEN(varConsLink)*2);
			FOR i := 0 TO LEN(varConsLink)-1 DO var[i] := varConsLink[i] END;
			varConsLink := var
		END;
		varConsLink[nofVarCons].mod := mod; varConsLink[nofVarCons].entry := entry;
		varConsLink[nofVarCons].noflinks := 0; varConsLink[nofVarCons].index := noEntry;
		index := nofVarCons;
		INC (nofVarCons)
	END NewVarCons;

	PROCEDURE VarConsLink (index, offset: LONGINT);
	VAR i: LONGINT;  var: VarConsLinkTable;
	BEGIN
		IF nofVarConsLinks >= LEN(varConsTab) THEN
			NEW(var, LEN(varConsTab)*2);
			FOR i := 0 TO LEN(varConsTab)-1 DO var[i] := varConsTab[i] END;
			varConsTab := var
		END;
		INC (varConsLink[index].noflinks);
		IF varConsLink[index].noflinks = 1 THEN
			varConsLink[index].index := nofVarConsLinks
		ELSE
			index := varConsLink[index].index;
			WHILE varConsTab[index].next # noEntry DO index := varConsTab[index].next END;
			varConsTab[index].next := nofVarConsLinks
		END;
		varConsTab[nofVarConsLinks].offset := SHORT (offset);
		varConsTab[nofVarConsLinks].next := noEntry;
		INC (nofVarConsLinks)
	END VarConsLink;

	PROCEDURE AbsAccess (node: OPT.Node; offset: LONGINT);
	BEGIN
		IF OPM.noerr THEN
			IF (node # NIL) & (node.link = NIL) & (node.obj = NIL) & (node.left = NIL) & (node.right = NIL) THEN 
				(* type descriptor *)
				VarConsLink (0, offset)
			ELSE
				WHILE (node # NIL) & (node.left # NIL) DO node := node.left END;
				IF (node = NIL) OR (node.obj.mnolev = 0) THEN (* constant, variable in the compiled module *)
					VarConsLink (0, offset)
				ELSE (* imported variable *)
					VarConsLink (node.obj.adr DIV 10000H, offset)
				END
			END
		END
	END AbsAccess;
	
	PROCEDURE NewEntry* (VAR entryNr: LONGINT);
		VAR table: EntryTable; i: LONGINT;
	BEGIN
		IF nofEntries >= LEN(entry) THEN
			NEW(table, LEN(entry)*2);
			FOR i:=0 TO LEN(entry)-1 DO  table[i]:=entry[i]  END;
			entry:=table
		END;
		entry [nofEntries] := Nil;
		entryNr := nofEntries;
		INC (nofEntries)
	END NewEntry;
	
	PROCEDURE NewLink* (mod, entry: LONGINT; VAR index: LONGINT);
	BEGIN
		IF nofLinks >= LinkLength THEN
			IF ~LinkErr THEN
				OPM.err (231); LinkErr := TRUE;
				index := 0
			END
		ELSE
			link [nofLinks].mod := SHORT (mod); link [nofLinks].entry := SHORT (entry); link [nofLinks].offset := Nil;
			index := nofLinks;
			INC (nofLinks)
		END
	END NewLink;

	PROCEDURE AddLink (index, offset: LONGINT);
		VAR old: LONGINT;
	BEGIN
		IF ~LinkErr THEN
			OPO.GetDWord (offset, old);
			IF link [index].offset = Nil THEN
				OPO.PutDWordAt (offset, -10000H + old MOD 10000H)
			ELSE
				IF link [index].offset >= 8000H THEN
					OPO.PutDWordAt (offset, (link [index].offset -10000H) * 10000H + old MOD 10000H)
				ELSE
					OPO.PutDWordAt (offset, link [index].offset * 10000H + old MOD 10000H)
				END
			END;
			link [index].offset := SHORT (offset)
		END
	END AddLink;
	
	PROCEDURE AllocConst* (VAR s: ARRAY OF SYSTEM.BYTE; len, align: LONGINT; VAR adr: LONGINT);
		VAR fill: LONGINT; table: OPO.ConstArray;
	BEGIN
		IF ~ConstErr THEN
			adr := OPO.csize;
			OPO.csize := OPO.csize + len;
			fill := (-len) MOD align;
			IF OPO.csize + fill > OPO.MaxConstLength THEN
				OPM.err (230); ConstErr := TRUE
			ELSE
				IF OPO.csize + fill >= LEN(OPO.constant) THEN 
					NEW(table, LEN(OPO.constant)*2);
					SYSTEM.MOVE(SYSTEM.ADR(OPO.constant[0]), SYSTEM.ADR(table[0]), adr);
					OPO.constant:=table
				END;
				WHILE fill > 0 DO
					OPO.constant [OPO.csize] := 0X; INC (OPO.csize);
					DEC (fill)
				END;
				SYSTEM.MOVE (SYSTEM.ADR (s[0]), SYSTEM.ADR (OPO.constant [adr]), len)
			END
		ELSE adr := 0
		END
	END AllocConst;
	
	PROCEDURE AllocCaseTab* (low, high: LONGINT; VAR tab: LONGINT);
		VAR len, i: LONGINT; table: OPO.ConstArray;
	BEGIN
		IF ~ConstErr THEN
			len := 4 * (high - low + 1);
			tab := OPO.csize;
			OPO.csize := OPO.csize + len;
			IF OPO.csize > OPO.MaxConstLength THEN
				OPM.err (230);
				ConstErr := TRUE
			ELSE
				IF OPO.csize >= LEN(OPO.constant) THEN 
					NEW(table, LEN(OPO.constant)*2);
					SYSTEM.MOVE(SYSTEM.ADR(OPO.constant[0]), SYSTEM.ADR(table[0]), tab);
					OPO.constant:=table
				END;
				i := tab; WHILE i < OPO.csize DO OPO.constant [i] := CHR (255); (* = -1 *) INC (i) END
			END
		ELSE tab := 0
		END;
	END AllocCaseTab;
	
	PROCEDURE AllocTypDesc* (typ: OPT.Struct);
	(* typ.tdadr = entryNr adr *)
		VAR nil: LONGINT; table: RecTable; i: LONGINT; tmp: ARRAY 4 OF SYSTEM.BYTE;
	BEGIN
		IF typ.comp = Record THEN
			nil := 0; BYTES(tmp,nil); AllocConst (tmp, 4, 4, typ.tdadr);
			IF typ.extlev > MaxExtensions THEN OPM.err (233)
			ELSIF (typ.mno = 0) THEN
				IF nofrecs>=LEN(recTab) THEN
					NEW(table, LEN(recTab)*2);
					FOR i:=0 TO LEN(recTab)-1 DO  table[i]:=recTab[i]  END;
					recTab:=table
				END;
				recTab [nofrecs] := typ; INC (nofrecs)
			END
		END (* no typ desc for arrays *)
	END AllocTypDesc;

	PROCEDURE CaseJump* (Label, tab, from, to: LONGINT);
	BEGIN
		IF ~ConstErr THEN
			from := tab + 4 * from; to := tab + 4 * to;
			WHILE from <= to DO
				(* !!later use this:  SYSTEM.MOVE (SYSTEM.ADR (Label), SYSTEM.ADR (OPO.constant [from]), 4); *)
				OPO.PutConsDWord (from, Label);
				from := from + 4
			END
		END
	END CaseJump;
	
	PROCEDURE OutRefPoint* (proc: OPT.Object);
		VAR obj: OPT.Object; n: LONGINT;
	BEGIN
		IF proc = NIL THEN (* Module Body *)
			OPM.RefW (RefTag);
			OPM.RefW (0F8X);
			OPM.RefWNum (0); (* offset *)
		ELSE (* procedure *)
			IF NewRef THEN
				OPM.RefW(0F9X);
				OPM.RefWNum(proc.linkadr); (* offset *)
				obj := proc.link; n := 0;
				WHILE obj # NIL DO
					INC(n); obj := obj.link
				END;
				OPM.RefWNum(n);	(* nofPars *)
				n := proc.typ.form;
				IF n IN {Undef, NilTyp, NoTyp} THEN n := 0
				ELSIF n = Comp THEN  n := 10H + proc.typ.comp
				END;
				OPM.RefW(CHR(n));
				OPM.RefW(CHR(proc.mnolev));
				IF slNeeded IN proc.conval.setval THEN
					OPM.RefW(1X)
				ELSE
					OPM.RefW(0X)
				END
			ELSE
				OPM.RefW (0F8X);
				OPM.RefWNum (proc.linkadr) (* offset *)
			END
		END
	END OutRefPoint;
	
	PROCEDURE OutRefName* (name: ARRAY OF CHAR);
		VAR
			ch: CHAR;
			i: INTEGER;
	BEGIN
		i := 0;
		REPEAT
			ch := name [i]; OPM.RefW (ch);
			INC (i)
		UNTIL ch = 0X
	END OutRefName;

	PROCEDURE OutRefs* (obj: OPT.Object);
		VAR f: INTEGER;
	BEGIN
		IF obj # NIL THEN
			OutRefs (obj.left);
			IF obj.mode IN {Var, VarPar} THEN
				f := obj.typ.form;
				IF NewRef THEN
					IF (f IN {Byte..Set, Pointer, ProcTyp, HInt}) OR (obj.typ.comp = Record) OR
							(obj.typ.comp IN {StaticArr, OpenArr}) & (obj.typ.BaseTyp.form IN {Byte..Set, Pointer, ProcTyp}) THEN
						IF (obj.mode = Var) & (obj.typ.comp # OpenArr) THEN OPM.RefW (1X)	(* direct *)
						ELSE OPM.RefW (3X)	(* indirect *)
						END;
						IF obj.typ.comp = StaticArr THEN
							OPM.RefW (CHR (80H + obj.typ.BaseTyp.form));
							OPM.RefWNum (obj.typ.n)
						ELSIF obj.typ.comp = OpenArr THEN
							OPM.RefW (CHR (80H + obj.typ.BaseTyp.form));
							OPM.RefWNum (0)
						ELSIF obj.typ.comp = Record THEN
							OPM.RefW(CHR(10H+Record));
							OPM.RefWNum(obj.typ.tdadr)
						ELSIF (f = Pointer) & (obj.typ.BaseTyp # NIL) & (obj.typ.BaseTyp.comp = Record) THEN
							OPM.RefW(CHR(10H+Pointer));
							OPM.RefWNum(obj.typ.BaseTyp.tdadr)
						ELSE
							OPM.RefW (CHR (f))
						END;
						OPM.RefWNum (obj.linkadr);
						OutRefName (obj.name)
					END
				ELSE
					IF (f IN {Byte..Set, Pointer, ProcTyp}) OR 
							(obj.typ.comp IN {StaticArr, OpenArr}) & (obj.typ.BaseTyp.form IN {Byte..Set, Pointer, ProcTyp}) THEN
						IF (obj.mode = Var) & (obj.typ.comp # OpenArr) THEN OPM.RefW (1X)	(* direct *)
						ELSE OPM.RefW (3X)	(* indirect *)
						END;
						IF obj.typ.comp = StaticArr THEN
							OPM.RefW (CHR (80H + obj.typ.BaseTyp.form));
							OPM.RefWNum (obj.typ.n)
						ELSIF obj.typ.comp = OpenArr THEN
							OPM.RefW (CHR (80H + obj.typ.BaseTyp.form));
							OPM.RefWNum (0)
						ELSE
							OPM.RefW (CHR (f))
						END;
						OPM.RefWNum (obj.linkadr);
						OutRefName (obj.name)
					END
				END
			END;
			OutRefs (obj.right)
		END
	END OutRefs;

	PROCEDURE LSW (x: LONGINT): LONGINT;
	BEGIN (* least significant word (unsigned) *)
		RETURN SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, x) * SYSTEM.VAL(SET, 0FFFFH))
	END LSW;
	
	PROCEDURE Export(obj: OPT.Object; VAR nofExp: INTEGER);
		VAR typ: OPT.Struct; i: LONGINT; tmp: ExpTable;

		PROCEDURE ExportMeth(fld: OPT.Object; basetyp: OPT.Struct; VAR noFld: INTEGER);
		BEGIN
			IF fld#NIL THEN ExportMeth(fld.left, basetyp, noFld);
				IF (fld.mode=TProc) & (fld.vis#internal) THEN 
					INC(noFld); OPM.ObjWNum(fld.fp);	(* mfix *)
				END;
				ExportMeth(fld.right, basetyp, noFld)
			END;
		END ExportMeth;

		PROCEDURE ExportRecord(typ: OPT.Struct);
			VAR fld: OPT.Object; pos: LONGINT; nofld: INTEGER;
		BEGIN 
			IF typ.mno=0 THEN
				OPM.ObjW(EURecord);
				IF typ.oref#0 THEN OPM.ObjWNum(-typ.oref);	(* old Type *)
				ELSE INC(nofStr); typ.oref:=nofStr;
					OPM.ObjWNum(typ.tdadr); 
					OPT.FPrintTyp(typ); 
					pos:=OPM.ObjAllocInt();
					nofld:=2; 
					IF (typ.BaseTyp#NIL) & (typ.mno=OPT.modNo) THEN ExportRecord(typ.BaseTyp) END;
					OPM.ObjWNum(typ.pbfp); OPM.ObjWNum(typ.pvfp);
					ExportMeth(typ.link, typ.BaseTyp, nofld);
					fld:=typ.link;
					WHILE (fld#NIL) & (fld.mode#TProc) DO
						IF fld.vis#internal THEN
							INC(nofld); 
							OPM.ObjWNum(fld.fp);
							typ:=fld.typ;
							WHILE (typ#NIL) & ((typ.form=Comp) & (typ.comp#Record) OR (typ.form=Pointer)) DO typ:=typ.BaseTyp END;
							IF (typ#NIL) & (typ.form=Comp) & (typ.comp=Record) THEN ExportRecord(typ) END;
						END;
						fld:=fld.link;
					END;
					OPM.ObjW(EUEnd); OPM.ObjFillInt(pos, nofld);
				END;
			END;
		END ExportRecord;

	BEGIN 
		IF obj#NIL THEN
			IF obj.prio=127 THEN Export(obj.link2, nofExp); Export(obj.left, nofExp); Export(obj.right, nofExp)
			ELSE
				Export(obj.left, nofExp);
				IF (obj.vis#internal) THEN
					OPT.FPrintObj(obj); 
					OPM.ObjWNum(obj.fp);
					i := 0;
					WHILE i < exppos DO
						IF obj.fp = explist[i] THEN OPM.Mark(280, obj.txtpos) END;
						INC(i)
					END;
					IF exppos = LEN(explist) THEN	(*grow*)
						NEW(tmp, 32+LEN(explist));
						SYSTEM.MOVE(SYSTEM.ADR(explist[0]), SYSTEM.ADR(tmp[0]), 4*LEN(explist));
						explist := tmp
					END;
					explist[exppos] := obj.fp; INC(exppos);
					IF obj.mode = Var THEN OPM.ObjWNum(obj.linkadr);
					ELSIF obj.mode = XProc THEN OPM.ObjWNum(LSW(entry[obj.adr]));
					ELSE OPM.ObjW(0X);
					END;
					INC(nofExp);
					IF (obj.mode=Typ) OR (obj.mode=Var) THEN
						typ:=obj.typ; 
						WHILE (typ#NIL) & ((typ.form=Comp) & (typ.comp#Record) OR (typ.form=Pointer)) DO typ:=typ.BaseTyp END;
						IF (typ#NIL) & (typ.form=Comp) & (typ.comp=Record) THEN ExportRecord(typ) END;
					END;
				END;
				Export(obj.right, nofExp)
			END	
		END
	END Export;

	PROCEDURE Use(obj: OPT.Object);
		VAR typ: OPT.Struct; alias: BOOLEAN; tmp: ARRAY 4 OF SYSTEM.BYTE;

		PROCEDURE UseRecord(typ: OPT.Struct);
			VAR name: ARRAY 32 OF CHAR;
		BEGIN
			IF (typ.oref=0) & (typ.mno=OPT.modNo) THEN
				OPM.ObjW(EURecord); 
				IF	(typ.tdadr=OPM.TDAdrUndef) OR (typ.tdadr=-2)	THEN	OPM.ObjWNum(0)
				ELSE	OPM.ObjWNum(-typ.tdadr)
				END;
				OPT.FPrintTyp(typ); typ.oref:=-1; 
				IF typ.pvused THEN	name:="@"; OPM.ObjWNum(typ.pvfp); OPM.ObjWString(name)	
				ELSIF typ.pbused THEN	name:="@"; OPM.ObjWNum(typ.pbfp); OPM.ObjWString(name)
				END;
				OPM.ObjW(EUEnd);
			END;
		END UseRecord;

	BEGIN
		IF obj#NIL THEN
			IF obj.prio=127 THEN Use(obj.link2); Use(obj.left); Use(obj.right)
			ELSE
				Use(obj.left);
				alias := FALSE;
				IF ~obj.used & (obj.mode = Typ) & (obj.vis#internal) & (obj.typ.strobj # obj) &
					(obj.typ.strobj.vis=internal) & obj.typ.strobj.used THEN
					alias := TRUE;
					(*OPM.LogWLn; OPM.LogWStr("  OPL.Use, (strobj) "); OPM.LogWStr(obj.name)*)
				END;
				IF alias OR obj.used & (obj.vis#internal)
				& ((obj.mode#XProc) OR (obj.adr DIV 10000H # 0) & (link[obj.adr DIV 10000H].offset # Nil)) 
				& ((obj.mode#Var) OR (obj.adr#0)) THEN 
					OPT.FPrintObj(obj);
					OPM.ObjWNum(obj.fp); OPM.ObjWString(obj.name);
					IF obj.mode = Var THEN OPM.ObjWNum(obj.adr DIV 10000H);
					ELSIF obj.mode = XProc THEN OPM.ObjWNum(LSW(link[obj.adr DIV 10000H].offset) + EUProcFlag);
					ELSE OPM.ObjW(0X);
					END;
					IF (obj.mode=Typ) OR (obj.mode=Var) THEN
						typ:=obj.typ; 
						WHILE (typ#NIL) & ((typ.form=Comp) & (typ.comp#Record) OR (typ.form=Pointer)) DO typ:=typ.BaseTyp END;
						IF (typ#NIL) & (typ.form=Comp) & (typ.comp=Record) THEN UseRecord(typ);
							IF typ.strobj.fp = 0 THEN typ.strobj.fp := obj.fp END
						END;
					END;
				END;
				Use(obj.right);
			END					
		END
	END Use;

	PROCEDURE OutCode*(VAR modName: ARRAY OF CHAR);
		VAR
			i, k, pos: LONGINT;
			nofcmds, nofnewmth, nofinhmth, linkCorrection, nofExp: INTEGER;
			obj: OPT.Object;
			typ, btyp: OPT.Struct;
			commandTab: ARRAY MaxCommands OF OPT.Object;
			newMthTab: ARRAY MaxEntry OF OPT.Object;
			tmp: ARRAY 4 OF SYSTEM.BYTE;
	
		PROCEDURE WriteName (VAR name: ARRAY OF CHAR);
			VAR i: INTEGER; ch: CHAR;
		BEGIN
			i := 0;
			REPEAT
				ch := name[i]; 
				OPM.ObjW (ch);
				INC (i)
			UNTIL ch = 0X
		END WriteName;
		
		PROCEDURE FindPtrs (typ: OPT.Struct; adr: LONGINT);
			VAR
				fld: OPT.Object;
				i, n, s: LONGINT;
				btyp: OPT.Struct;
				
				PROCEDURE Add(adr: LONGINT);
				VAR  table: PtrTable;
				BEGIN
					IF nofptrs >= LEN(ptrTab) THEN
						NEW(table, LEN(ptrTab)*2);
						FOR i:=0 TO LEN(ptrTab)-1 DO  table[i]:=ptrTab[i]  END;
						ptrTab:=table
					END;
					ptrTab[nofptrs] := adr; INC (nofptrs)
				END Add;
		BEGIN
			IF typ.form = Pointer THEN
				IF (typ.sysflag=0) THEN Add(adr) END
			ELSIF (typ.form = ProcTyp) & (typ.sysflag = delegate) THEN Add(adr+4)
			ELSIF typ.comp = Record THEN
				btyp := typ.BaseTyp;
				IF btyp # NIL THEN FindPtrs (btyp, adr) END;
				fld := typ.link;
				WHILE (fld # NIL) & (fld.mode = Fld) DO
					IF (fld.name = OPT.HdPtrName) THEN Add(adr)
					ELSIF fld.sysflag # untraced THEN FindPtrs (fld.typ, fld.adr + adr)
					END;
					fld := fld.link
				END
			ELSIF typ.comp = StaticArr THEN
				btyp := typ.BaseTyp; n := typ.n;
				WHILE btyp.comp = StaticArr DO
					n := btyp.n * n;
					btyp := btyp.BaseTyp
				END;
				IF (btyp.form = Pointer) OR (btyp.comp IN {Record, DynArr}) OR ((btyp.form = ProcTyp) & (btyp.sysflag = delegate)) THEN
					i := 0; s := btyp.size;
					WHILE i < n DO  FindPtrs (btyp, i * s + adr); INC (i)  END
				END
			ELSIF typ.comp = DynArr THEN
				Add(adr)
			END
		END FindPtrs;
		
		PROCEDURE traverse (obj: OPT.Object);
		BEGIN
			IF obj # NIL THEN
				IF obj.mode = XProc THEN
					IF obj.vis # internal THEN	(* exported proc *)
						IF (obj.link = NIL) & (obj.typ = OPT.notyp) THEN (* command *)
							IF nofcmds <= MaxCommands THEN
								commandTab[nofcmds] := obj;
								INC (nofcmds)
							ELSE OPM.err (232)
							END
						ELSIF (obj.typ = OPT.ptrtyp) & (obj.link # NIL) & (obj.link.typ = OPT.ptrtyp) & (obj.link.link = NIL) THEN	(* parameter command *)
							IF nofcmds <= MaxCommands THEN
								commandTab[nofcmds] := obj;
								INC (nofcmds)
							ELSE OPM.err (232)
							END
						END
					END
				ELSIF (obj.mode = Var) & (obj.sysflag # untraced) THEN FindPtrs (obj.typ, obj.linkadr)
				END;
				traverse (obj.left); traverse (obj.right)
			END
		END traverse;
		
		PROCEDURE FindNewMths (obj: OPT.Object);
		BEGIN
			IF obj # NIL THEN
				IF (obj.mode = TProc) OR ((obj.mode = Typ) & (obj.conval # NIL) & (hasBody IN obj.conval.setval)) THEN 
					newMthTab[nofnewmth] := obj; 
					INC (nofnewmth)
			 	END;
			 	IF obj.mode = Typ THEN FindNewMths (obj.typ.link)
			 	ELSE FindNewMths (obj.left); FindNewMths (obj.right)
			 	END
			 END
		END FindNewMths;

	BEGIN (*  OutCode *)
		linkCorrection := 0; i := 0;
		WHILE i < nofLinks DO
			IF (link[i].offset = Nil) OR (link[i].mod > 0) THEN INC (linkCorrection) END;
			INC (i)
		END;
		i :=  (-OPO.csize) MOD 4;
		WHILE i > 0 DO
			OPO.constant[OPO.csize] := 0X; INC (OPO.csize);
			DEC (i)
		END;
		nofcmds := 0;
		traverse (OPT.topScope.right); (* collect commands and pointers *)
		i := 0;
	(* header block *)
		OPM.ObjWInt (nofEntries); OPM.ObjWInt (nofcmds);
		IF nofptrs > MAX(INTEGER) THEN OPM.err(222) END;
		OPM.ObjWInt (SHORT(nofptrs)); OPM.ObjWInt (nofrecs);
		OPM.ObjWInt (OPT.nofmod-1);
		OPM.ObjWInt (nofVarCons); OPM.ObjWInt (nofLinks-linkCorrection);
		BYTES(tmp,OPO.dsize); OPM.ObjWBytes (tmp, 4); OPM.ObjWInt (SHORT (OPO.csize)); OPM.ObjWInt (SHORT (OPO.pc));
		WriteName (modName);
	(* entry block *)
		OPM.ObjW (EntryTag);
		i := 0; WHILE i < nofEntries DO OPM.ObjWInt (entry[i]); INC (i) END;
	(* command block *)
		OPM.ObjW (commandTag);
		i := 0; (* write command names and entry addresses *)
		WHILE i < nofcmds DO
			obj := commandTab[i];
			IF obj.link # NIL THEN OPM.ObjW("$") END;	(* flag for command with parameter *)
			WriteName (obj.name); OPM.ObjWInt (entry [obj.adr MOD 10000H]);
			INC (i)
		END;
	(* pointer block *)
		OPM.ObjW (pointerTag);
		i := 0; 
		WHILE i < nofptrs DO
  		BYTES(tmp, ptrTab[i]);
			OPM.ObjWBytes (tmp, 4);
			INC (i)
		END;
	(* import block *)
		OPM.ObjW (importTag);
		i := 1;
		WHILE i < OPT.nofmod DO
			obj := OPT.modules[i];
			WriteName (obj.name); (* name *)
			INC (i)
		END;
	(* VarConsLink block *)
		OPM.ObjW (VarConsLinkTag);
		i := 0;
		WHILE i < nofVarCons DO
			OPM.ObjW (CHR (varConsLink[i].mod));
			OPM.ObjWInt (varConsLink[i].entry); OPM.ObjWInt (varConsLink[i].noflinks);
			k := varConsLink[i].index;
			WHILE k # noEntry DO
				OPM.ObjWInt (varConsTab[k].offset);
				k := varConsTab[k].next
			END;
			INC (i)
		END;
	(* link block *)
		OPM.ObjW (LinkTag);
		i := 0;
		WHILE i < nofLinks DO
			IF (link[i].offset # Nil) & (link[i].mod <= 0) THEN
				OPM.ObjW (CHR (link[i].mod)); OPM.ObjW (CHR (link[i].entry)); OPM.ObjWInt (link[i].offset)
			END;
			INC (i)
		END;
	(* data block *)
		OPM.ObjW (DataTag);
		i := 0; WHILE i < OPO.csize DO OPM.ObjW (OPO.constant[i]); INC (i) END;
	(* export block *)
		OPM.ObjW (ExportTag);
		pos := OPM.ObjAllocInt();
		nofExp := 0; nofStr := 0; OPT.modNo := 0;
		IF Experimental THEN exppos := 0 END;
		Export(OPT.topScope.right, nofExp);
		OPM.ObjW(EUEnd); OPM.ObjFillInt(pos, nofExp);
	(* code size *)
		OPM.ObjW (CodeTag);
		i := 0;
		WHILE i < OPO.pc DO
			OPM.ObjW (OPO.code[i]);
			INC (i)
		END;
	(* use block *)
		OPM.ObjW(UseTag);
		i := 1;
		WHILE i < OPT.nofmod DO
			IF OPT.modules[i].used THEN
				OPM.ObjWString(OPT.modules[i].name);
				OPT.modNo := SHORT(i);
				Use(OPT.modules[i].right);
				OPM.ObjW(EUEnd)
			END;
			INC(i)
		END;
		OPM.ObjW(EUEnd);
	(* type block *)
		OPM.ObjW (TypeTag);
		i := 0;
		WHILE i < nofrecs DO
			typ := recTab [i];
			nofptrs := 0;
			FindPtrs (typ, 0);
			BYTES(tmp, typ.size);
			OPM.ObjWBytes (tmp, 4); (* record size *)
			OPM.ObjWInt (SHORT (typ.tdadr));	(* td adr *)
			btyp := typ.BaseTyp;
			IF btyp = NIL THEN 
				nofinhmth := 0;
				OPM.ObjWInt (-1); OPM.ObjWLInt (-1)
			ELSE
				nofinhmth := SHORT (btyp.n);
				OPM.ObjWInt (btyp.mno);
				IF btyp.mno = 0 THEN BYTES(tmp, btyp.tdadr); OPM.ObjWBytes(tmp, 4)
				ELSE OPM.ObjWLInt(btyp.strobj.fp)
				END
			END;
			OPM.ObjWInt (SHORT (typ.n)); (* total number of methods *)
			OPM.ObjWInt (nofinhmth);  (* number of inherited methods *)
			nofnewmth := 0;
			FindNewMths (typ.strobj);
			OPM.ObjWInt (nofnewmth);
			IF nofptrs > MAX(INTEGER) THEN OPM.err(221) END;
			OPM.ObjWInt (SHORT(nofptrs));
			IF (typ.strobj # NIL) & (typ.strobj.mnolev = 0) THEN
				IF typ.ptr # NIL THEN
					IF typ.ptr.strobj = NIL THEN WriteName(typ.strobj.name) ELSE WriteName(typ.ptr.strobj.name) END
				ELSE WriteName (typ.strobj.name) END
			ELSE OPM.ObjW (0X)
			END;
			WHILE nofnewmth > 0 DO
				DEC (nofnewmth);
				OPM.ObjWInt (SHORT (newMthTab[nofnewmth].adr DIV 10000H)); (* method number *)
				OPM.ObjWInt (SHORT (newMthTab[nofnewmth].adr MOD 10000H)) (* entry number *)
			END;
			k := 0;
			WHILE k < nofptrs DO
  			BYTES(tmp, ptrTab[k]);
				OPM.ObjWBytes (tmp, 4);
				INC (k)
			END;
			INC (i)
		END;
	(* ref block *)
		(* written in OPM.CloseRefObj *)
		OPM.CloseObj
	END OutCode;
	
	PROCEDURE Close*;
		VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO LEN(Instr)-1 DO Instr[i].node := NIL END;	(* GC can now collect the nodes *)
		i := 0; WHILE i < LEN(recTab) DO recTab[i] := NIL; INC(i) END
	END Close;
	
BEGIN
	NEW(ptrTab, 512);  NEW(recTab, 64);  NEW(entry, 128);
	NEW(Instr, 500);  NEW(varConsLink, 100);  NEW(varConsTab, 500);
	NEW(explist, 32);
	JmpConvert [0] := JE; JmpConvert [1] := JNE; JmpConvert [2] := JL; JmpConvert [3] := JLE; JmpConvert [4] := JG;
	JmpConvert [5] := JGE; JmpConvert [6] := JA; JmpConvert [7] := JAE; JmpConvert [8] := JB; JmpConvert [9] := JBE;
	JmpConvert [10] := JC; JmpConvert [11] := JNC;
	SetccConvert [0] := SETE; SetccConvert [1] := SETNE; SetccConvert [2] := SETL; SetccConvert [3] := SETLE;
	SetccConvert [4] := SETG; SetccConvert [5] := SETGE; SetccConvert [6] := SETA; SetccConvert [7] := SETAE;
	SetccConvert [8] := SETB; SetccConvert [9] := SETBE; SetccConvert [10] := SETB; SetccConvert [11] := SETNB;
END OPL.
