(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE Kernel;	(** non-portable *)	(* rc/ard/nm/jm/jdv/pjm/rml*)

IMPORT ObxPal;

(** Module Kernel is responsible for memory allocation, garbage collection and other run-time 
support for the Oberon language, as well as interfacing to the underlying machine.  Using features 
exported from module Kernel may result in an unportable module, as not all Oberon Kernels are the same. 
This module is of little importance to most Oberon programmers. *)

CONST
		
		(* timer *)
	TimeUnit* = 1000;	(** timer ticks per second, returned by GetTimer *)
	
TYPE
	ADDRESS = LONGINT;
	PTR* = POINTER TO ANYREC;
	Name* = ARRAY 32 OF CHAR;	(* module name *)
	Proc* = PROCEDURE;
	Cmd* = RECORD
		name*: Name;
		adr*: ADDRESS;
	END;
	Module* = POINTER TO ModuleDesc;	(* module descriptor *)
	ExportPtr* = POINTER TO ExportDesc;
	ExportDesc* = RECORD
		fp*: LONGINT; adr*: LONGINT;
		nofExp*: INTEGER; 
		dsc*: POINTER TO ARRAY OF ExportDesc
	END;
	ArrayPtr* = POINTER TO ARRAY OF LONGINT;
	ModuleDesc* = RECORD	(* Note: if this is changed, also update the static Linker *)
		next*: Module;
		name*: Name;
		init*, trapped*: BOOLEAN;
		refcnt*, sb*: LONGINT;
		entries*: POINTER TO ARRAY OF ADDRESS;
		cmds*: POINTER TO ARRAY OF Cmd;
		ptrTab*, tdescs*: POINTER TO ARRAY OF ADDRESS;
		imports*: POINTER TO ARRAY OF Module;
		data*, code*, refs*: POINTER TO ARRAY OF CHAR;
		publics*, privates*: LONGINT;	(* for slim binaries *)
		nofimp*: INTEGER; import*: ArrayPtr;
		nofstrc*: INTEGER; struct*: ArrayPtr;
		nofreimp*: INTEGER; reimp*: ArrayPtr;
		export*: ExportDesc;
		term*: Proc
	END;

		(* type descriptors *)
	Tag = POINTER TO TypeDesc;
	TypeDesc = RECORD
		size: LONGINT;
		ptroff: LONGINT
	END;

		(* interrupt handling *)
	TrapHandler* = PROCEDURE (err, fp, pc, pf: LONGINT);

		(* heap/GC *)
	FreeBlock = RECORD
		(* off-4 *) tag: Tag;
		(* off0 *) size: LONGINT;	(* field size aligned to 8-byte boundary, size MOD B = B-4 *)
		(* off4 *) next: ADDRESS
	END;
	BlockPtr = POINTER TO Block;
	Block = RECORD
		lastElemToMark, currElem, firstElem: BlockPtr
	END;
	Blockm4 = RECORD
		tag: Tag;
		lastElemToMark, currElem, firstElem: LONGINT
	END;
	InitPtr = POINTER TO RECORD tag: Tag; z0, z1, z2, z3, z4, z5, z6, z7: LONGINT END;
		(* the following type is used indirectly in InitHeap *)
	
	Finalizer* = PROCEDURE (obj: PTR);
	FinObj = POINTER TO FinObjNode;
	FinObjNode = RECORD
		next: FinObj;
		obj: LONGINT;
		marked: BOOLEAN;
		fin: Finalizer;
	END;

		(* memory management *)
	GateDescriptor = RECORD
		offsetBits0to15: INTEGER;
		selector: INTEGER;
		gateType: INTEGER;
		offsetBits16to31: INTEGER
	END;
	SegmentDescriptor = RECORD
		limit0to15: INTEGER;
		base0to15: INTEGER;
		base16to23: CHAR;
		accessByte: CHAR;
		granularityByte: CHAR;
		base24to31: CHAR
	END;

	MilliTimer* = RECORD target: LONGINT END;

VAR
		(* exported variables *)
	version*: ARRAY 64 OF CHAR;
	modules* : Module;	(** list of modules, patched by Linker *)
	StackOrg* : ADDRESS;	(** highest address on stack (single-process system) *)
	bt*: ADDRESS;	(** boot table *)
	tspeed*: LONGINT;	(** <=0: no V24 tracing, >0: tspeed = speed of com output *)
	break* : BOOLEAN;	(** has ctrl-break been pressed? *)
	copro*: BOOLEAN;	(** is a coprocessor present? *)
	inGC*: BOOLEAN;	(** executing inside GC? *)
	EnableGC*, DisableGC*: Proc;	(** Enable or Disable the GC *)
	timer*: Proc;	(** for internal use *)
	runtime*: ARRAY 3 OF ADDRESS;	(** for internal use *)
	traceConsole*: BOOLEAN;	(** trace on console? *)
	shutdown*: LONGINT;	(** system shutdown code 0=running, 1=powering off, 2=rebooting *)
	tlpt: LONGINT;

	  (* heap/GC *)
	memTop, heapTop: ADDRESS;
	
		(* interrupt handling/memory management *)
	handler: TrapHandler;	(* trap handlers *)
	loop: Proc;	(* main loop *)
	traceBufAdr: LONGINT;
	
		(* misc. *)
	pspeed: LONGINT;	(* previous trace speed *)
	pageheap, pageheap0, pageheap1: ADDRESS;
	displayPos: LONGINT;
	kpar: ARRAY 2 OF LONGINT;


(** WriteString - Write a string *)
PROCEDURE WriteString*(IN s: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
	i := 0;  WHILE s[i] # 0X DO WriteChar(s[i]);  INC(i) END
END WriteString;

(** WriteInt - Write "x" as a decimal number.  "w" is the field width. *)
PROCEDURE WriteInt*(x, w: LONGINT);
VAR i: LONGINT;  x0: LONGINT;  a: ARRAY 12 OF CHAR;  s: ARRAY 2 OF CHAR;
BEGIN
	IF x < 0 THEN
		IF x = MIN(LONGINT) THEN
			WriteString("-2147483648");
			RETURN
		ELSE
			DEC(w); x0 := -x
		END
	ELSE
		x0 := x
	END;
	i := 0;
	REPEAT
		a[i] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(i)
	UNTIL x0 = 0;
	s[0] := " ";  s[1] := 0X;
	WHILE w > i DO WriteString(s); DEC(w) END;
	s[0] := "-";
	IF x < 0 THEN WriteString(s) END;
	REPEAT DEC(i); s[0] := a[i]; WriteString(s) UNTIL i = 0
END WriteInt;

(** WriteHex - Write "x" as a hexadecimal number. The absolute value of "w" is the field width.  
If "w" is negative, two hex digits are printed (x MOD 100H), otherwise 8 digits are printed. *)
PROCEDURE WriteHex*(x, w: LONGINT);
VAR
	buf: ARRAY 10 OF CHAR;
	i, j: LONGINT;
BEGIN
	IF w >= 0 THEN j := 8 ELSE j := 2; w := -w END;
	FOR i := j+1 TO w DO WriteChar(" ") END;
	FOR i := j-1 TO 0 BY -1 DO
		buf[i] := CHR(x MOD 10H + 48);
		IF buf[i] > "9" THEN
			buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10)
		END;
		x := x DIV 10H
	END;
	buf[j] := 0X;
	WriteString(buf)
END WriteHex;

(** WriteChar - Write a character to the trace output (not reentrant). *)
PROCEDURE WriteChar*(c: CHAR);
BEGIN
  ObxPal.printChar(c)
END WriteChar;

(** WriteLn - Skip to the next line on trace output *)
PROCEDURE WriteLn*;
BEGIN
	WriteChar(0DX);  WriteChar(0AX)
END WriteLn;

(** InstallTermHandler - Install a procedure to execute when a module is freed.  Normally used to 
uninstall interrupt handlers or tasks and perform other cleanup duties.  Never perform upcalls in proc, 
because the upcalled module will no longer be in memory! *)
PROCEDURE InstallTermHandler* (h: Proc);	(* can also be used by modules below Modules, e.g. FileDir *)
// TODO
END InstallTermHandler;

(** GetConfig - Return value of configuration string.  Returns empty val if name not found. *)
PROCEDURE GetConfig*(IN name: ARRAY OF CHAR;  VAR val: ARRAY OF CHAR);
// TODO
END GetConfig;

(** Used - Return the size in bytes of the amount of memory currently in use in the heap. *) 
PROCEDURE Used*(): LONGINT;
BEGIN
	RETURN 0 // TODO
END Used;

(** SetTimer - Set timer to expire in approximately "ms" milliseconds. *)
PROCEDURE SetTimer*(VAR t: MilliTimer;  ms: LONGINT);
// TODO
END SetTimer;

(** Expired - Test if a timer has expired.  Interrupts must be on. *)
PROCEDURE Expired*(VAR t: MilliTimer): BOOLEAN;
BEGIN
	RETURN FALSE // TODO
END Expired;

(** RegisterObject - Register an object (POINTER TO RECORD or POINTER TO ARRAY, not SysBlk) for 
finalization.  Never perform upcalls in the fin procedure! basic = FALSE *)
PROCEDURE RegisterObject* (obj: PTR;  fin: Finalizer;  basic: BOOLEAN);
// TODO
END RegisterObject;

(** GetTimer - Return "ticks" since initialisation (Kernel.TimeUnit ticks per second) *)
PROCEDURE GetTimer*(): LONGINT;
BEGIN
	RETURN ObxPal.time()
END GetTimer;

(** InstallLoop - Install procedure to which control is transferred after a trap *)
PROCEDURE InstallLoop*(p: Proc);
BEGIN
	loop := p
END InstallLoop;

(** InstallTrap - Install the trap handler *)
PROCEDURE InstallTrap*(p: TrapHandler);
BEGIN
	handler := p
END InstallTrap;

(** GetLog - Return characters from trace log. *)
PROCEDURE GetLog*(VAR val: ARRAY OF CHAR);
END GetLog;

(** Shutdown - Terminate Oberon after executing all module terminators.  If code = 1, 
perform an APM power-down, if code = 2, perform a soft reboot, or else just switch off 
interrupts and loop endlessly. *)
PROCEDURE Shutdown*(code: LONGINT);
// TODO
END Shutdown;

(** GetMod - Return the loaded module that contains code address pc. *)
PROCEDURE GetMod*(pc : LONGINT): Module;
  RETURN modules// TODO
END GetMod;

(** LargestAvailable - Return the size in bytes of the largest free available memory block. 
Allocating objects with a size greater than this size will cause the memory allocation to fail. *) 
PROCEDURE LargestAvailable*(): LONGINT;
RETURN 0 // TODO
END LargestAvailable;

(** Available - Return the size in bytes of the remaining free heap space *)
PROCEDURE Available*(): LONGINT;
RETURN 0 // TODO
END Available;

(** Idle - Called to save power when system is idle. *)
PROCEDURE Idle*(code: LONGINT);	(* code currently unused *)
// TODO
END Idle;

(** GC - Immediately activate the garbage collector. *)
PROCEDURE GC*;
// TODO
END GC;

(** GetClock - Return current time and date *)
(** day = d MOD 32, month = d DIV 32 MOD 16, year = 1900+d DIV 512,
	  hour = t DIV 4096 MOD 32, minute = t DIV 64 MOD 64, second = t MOD 64 *)
PROCEDURE GetClock*(VAR time, date: LONGINT);
VAR hour, minute, second, day, month: CARRAY 1 OF BYTE; year: CARRAY 1 OF INTEGER;
BEGIN
  ObxPal.clock(hour,minute,second);
  ObxPal.date(year,month,day);
  time := hour[0] * 4096 + minute[0] * 64 + second[0];
  date := (year[0]-1900) * 512 + month[0] * 32 + day[0];
END GetClock;

(** SetClock - Set current time and date *)
PROCEDURE SetClock*(time, date: LONGINT);
// TODO
END SetClock;

(* Init code called from OBL.  EAX = boot table offset.  2k stack is available. *)
BEGIN
	//SYSTEM.GETREG(0, bt);	(* EAX from bootstrap loader *)
	//SYSTEM.GETREG(6, kpar[0]);  SYSTEM.GETREG(7, kpar[1]);	(* par0 & par1 *)
	tspeed := 0;  pspeed := 0;  displayPos := 0;  traceBufAdr := 0;  timer := NIL;
	traceConsole := FALSE;  shutdown := 0;  tlpt := 0;
	//ReadBootTable;	(* set memTop, pageheap, configadr *)
	//CheckMemory;	(* adjust memTop *)
	pageheap0 := pageheap;  pageheap1 := 0;  heapTop := memTop;
	//InitTracing(heapTop);
	version := "OBX PAL / based on PC Native 2.3.6";
	WriteString("ETH Oberon / ");  WriteString(version);  WriteLn;
	//InitProcessor;  InitInterrupts;  InitTrapHandling;
	//InitMemory;  InitHeap;
		(* switch to level 3 (after InitHeap inits StackOrg) *)
	//SwitchToLevel3(UserStackSel, StackOrg, UserCodeSel);
		(* on new stack *)
	//InitTimer;  (*InitBeeps;*)
	//InitClock;  InitRuntime
END Kernel.

(*
TraceHeap:
0	1	NEW record
1	2	NEW array
2	4	SYSTEM.NEW
3	8	deallocate record
4	16	deallocate array
5	32	deallocate sysblk
6	64	finalisation
7	128	free pages
8	256	show free blocks
9	512	NewDMA
10	1024	before/after memory
11	2048	live/dead
16	65536	termhandlers
*)

