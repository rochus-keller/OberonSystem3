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

MODULE BootLinker;	(** non-portable *)	(** JdV / dVdW / pjm / prk *)

(*
	13.02.97 \prk (found by pjm)
		error in the ModDescAdr (it pointed to the td of module) +4 added.

	Static linker for Native Oberon for OM Files.
	This module is based on the BootLinker for Native Oberon by
		- by De Villiers de Wet, Stellenbosch University (dewe@cs.sun.ac.za)
		- and Johan de Villiers, Datafusion (devil@dfs.stb.co.za)
		- Native Oberon version by Pieter Muller, ETH (muller@inf.ethz.ch)
	and on the module loader for OM files by
		- Thomas Kistler (kistler@inf.ethz.ch)

	Original version for the Eamon system:
		- Patrik Reali (prk), ETH Zürich (reali@inf.ethz.ch)
		
	This version for the Femto system:
		- Patrik Reali (prk), ETH Zürich (reali@inf.ethz.ch)
	
	Eamon -> Femto:
		- remove lock optimization: \check, \curproc are not used anymore. (also the magic offset)
		- remove the OBJECT base type for protection
		
	Generated File:
	
		the generated file is an image of the memory after loading and linking the core modules. Every
		module is loaded at the address ".base" and the whole has size ".imageSize".
		
	m.base	Entries
		Commands
		Pointers
		Tdescs
		Imports
		Data
	m.sb	Code
		References
		ModuleDesc
	+m.imageSize
		
	Changes:
		integration of the OberonX changes (fixups 243, 242)
		( arrHdr, new format and size (16->24)), moved to the global declarations
*)

IMPORT
	S := SYSTEM, Modules, Files, Texts, Fonts, Oberon;

CONST
	Boundary = 32;	(* boundaries on which Oberon GC allocates blocks (=32) *)
	
	Trace = TRUE;
	TraceMore = FALSE;

	(* SysFix constants *)
	MaxSF = 17; 	
	newSF = 0; sysnewSF = 1; newarrSF = 2; StartSF = 3; PassivateSF = 4; ActivateSF = 5; LockSF = 6;
	UnlockSF = 7; (*CheckSF = 8; newsysarrSF = 9;*) copyarraySF = 10;
	CurProcSF = 11; commandSF = 12; listSF = 13; modDescSF = 14; expDescSF = 15; objectSF = 16;

	(* FindAdr modes *)
	Proc = 0; Var = 1;
	
	OFVersion = 0AFX;

	PaddingSize = 64;
	PageSize = 4096;
	hiddenTD = 20;

	(* res codes *)
	done = 0;
	fileNotFound = 1;
	invalidObjFile = 2;
	corruptedObjFile = 4;
	cmdNotFound = 5;
	moduleNotFound = 6;
	notEnoughSpace = 7;
	refCntNotZero = 8;
	cyclicImport = 9;
	incompImport = 16;

	(* structures affecting the format of the static image *)
TYPE
	ArrayDesc = RECORD a, b, c, (*lb,*) len(*, empty*): LONGINT END;	(* lb, empty used by OberonX *)
CONST
	ArrayDescSize = 16(*24*);	(* without the tag *)
	TagSize = 4;

TYPE
	String = ARRAY 256 OF CHAR;
	Name = ARRAY 32 OF CHAR; ModuleName = Name;	(* alias for the lader/linker *)

	CommandDesc = RECORD
		name: Name;
		adr: LONGINT
	END;
	Commands = POINTER TO ARRAY OF CommandDesc;

	Command = PROCEDURE;

	NewMethod = RECORD
		mthNo, entryNo: INTEGER;
	END;
	
	ArrayPtr = POINTER TO ARRAY OF LONGINT;

	Type = POINTER TO TypeDesc;
	Module = POINTER TO ModuleDesc;
	
	ExportPtr = POINTER TO ExportDesc;
	ExportDesc = RECORD
		fp: LONGINT; adr: LONGINT;
		nofExp: INTEGER;
		dsc: POINTER TO ARRAY OF ExportDesc;
		Adr: LONGINT; done: BOOLEAN; type: Type;
	END;
	
	DumpExportDesc = RECORD
		fp: LONGINT; adr: LONGINT;
		nofExp: LONGINT;
		dsc: LONGINT;
	END;

	TerminationHandler = PROCEDURE;
	
	TypeDesc = RECORD
		size, nofMethods, nofNewMethods, nofPtrs, tdAdr, tdEntry, tdSize, padSize, baseMod, baseEntry: LONGINT;
		name: Name;
		newMethods: POINTER TO ARRAY OF NewMethod;
		ptrOffset: POINTER TO ARRAY OF LONGINT;
		baseType: Type;
		extlev: LONGINT;
		initialized: BOOLEAN;
		module: Module;
	END;
	
	ModuleDesc = RECORD
		(* Normal Module Data *)
		link: Module;
		name: Name;
		init: BOOLEAN;
		refcnt, sb: LONGINT;
		(*dataSize, conSize, codeSize, refSize: LONGINT;
		nofEntries, nofCmds, nofImps, nofTds, nofPtrs: LONGINT;*)
		entries: POINTER TO ARRAY OF LONGINT;
		cmds: POINTER TO ARRAY OF CommandDesc;
		ptrTab: POINTER TO ARRAY OF LONGINT;
		tdescs: POINTER TO ARRAY OF Type;
		imports: POINTER TO ARRAY OF	Module;
		data, code: POINTER TO ARRAY OF CHAR;
		refs: POINTER TO ARRAY OF CHAR;
		publics, privates: LONGINT;
		nofimp: LONGINT; import: ArrayPtr;
		nofstrc: LONGINT; struct: ArrayPtr;
		nofreimp: LONGINT; reimp: ArrayPtr;
		export: ExportDesc;
		term: TerminationHandler;
		(* Additional Module Data -> for the linker only *)
		base, imageSize: LONGINT;
		codeBase, refBase: LONGINT;
		expAdr, expSize, expPadding: LONGINT;
		typeTableSize, typeTableAdr, typeTablePadding: LONGINT;
		modDescAdr: LONGINT;
		dataSize, conSize, codeSize, refSize: LONGINT;
		nofEntries, nofCmds, nofImps, nofTds, nofPtrs: LONGINT;
	END;

	DumpModule = POINTER TO DumpModuleDesc;
	DumpModuleDesc = RECORD

		(* Normal Module Data *)
		link:	(* Module *) LONGINT;
		name: Name;
		init, trapped: BOOLEAN;
		refcnt, sb: LONGINT;
		(*dataSize, conSize, codeSize, refSize: LONGINT;
		nofEntries, nofCmds, nofImps, nofTds, nofPtrs: LONGINT;*)
		entries, cmds, ptrTab, tdescs, imports, data, code, refs: LONGINT	(* POINTER TO ARRAY OF LONGINT *);
		publics, privates: LONGINT;
		nofimp: LONGINT; import: (*ArrayPtr*) LONGINT;
		nofstrc: LONGINT; struct: (*ArrayPtr*) LONGINT;
		nofreimp: LONGINT; reimp: (*ArrayPtr*) LONGINT;
		export: DumpExportDesc;
		term: TerminationHandler;
	END;

	InitPoint = POINTER TO InitPointNode;
	InitPointNode = RECORD
		entryPoint: LONGINT;
		object: Module;
		next: InitPoint
	END;

CONST
	EUEnd = 0; EURecord = 1; EUobjScope = 0; EUrecScope = 1; EUerrScope =-1; EUProcFlag = 80000000H;

	ExtTabWordSize = 16;
	Tag0WordOffset =-2;
	Mth0WordOffset = Tag0WordOffset-ExtTabWordSize;

	DefMaxImport = 64; DefMaxStruct = 32; DefMaxReimp = 32;

TYPE
	LinkTab = ARRAY 256 OF RECORD	(* For the loader *)
		mod, entry: CHAR;
		link: LONGINT
	END;

	DataLinkTab = ARRAY 128 OF RECORD	(* For the loader *)
		mod: CHAR;
		entry: INTEGER;
		nofFixups: INTEGER;
		offset: POINTER TO ARRAY OF LONGINT
	END;

	Cmd = CommandDesc;	(* Alias for the loader *)

VAR
	SysFix: ARRAY MaxSF OF RECORD name, module, command: Name; adr: LONGINT END;
	protObj: Type;
	objectList: Module;
	includeRefs: BOOLEAN;
	imageBase, imageSize: LONGINT;
	moduleDescSize, mDescPadSize: LONGINT;
	moduleTag: LONGINT;

	nofEntryPoints: LONGINT;
	initPointList: InitPoint;

	padding: ARRAY PaddingSize OF S.BYTE;

	logName: Name;
	logWriter: Texts.Writer;

	res: INTEGER;	(* last loader error *)

	extension: ARRAY 8 OF CHAR;
	
	W: Texts.Writer;
	
	(* ---------------------------------------------------------- *)
	(* String Handling Procedures *)

PROCEDURE Length (VAR str(** in *): ARRAY OF CHAR): LONGINT;
	VAR i, l: LONGINT;
BEGIN
	l := LEN(str); i := 0;
	WHILE (i < l) & (str[i] # 0X) DO
		INC(i)
	END;
	RETURN i
END Length;

PROCEDURE Concat (s1, s2: ARRAY OF CHAR; VAR s3: ARRAY OF CHAR);
VAR i, len, max: INTEGER;
BEGIN	(* Pre: s1[i] := 0X, 0 <= i < LEN(s1)
						s2[j] := 0X, 0 <= j < LEN(s2) *)
	max := SHORT (LEN (s3))-1;
	len := 0;
	WHILE s1[len] # 0X DO s3[len] := s1[len]; INC (len) END;
	s3[len] := 0X;
	i := 0;
	WHILE ((len+i) < max) & (s2[i] # 0X) DO
		s3[len+i] := s2[i]; INC (i)
	END;
	s3[len+i] := 0X
END Concat;

PROCEDURE LogOpen (name: ARRAY OF CHAR);
	VAR font: Fonts.Font;
BEGIN
	COPY (name, logName); Texts.OpenWriter (logWriter);
	font := Fonts.This("Courier10.Scn.Fnt"); Texts.SetFont(logWriter, font)
END LogOpen;

PROCEDURE LogClose;
VAR
	len: LONGINT; res: INTEGER; text: Texts.Text; file: Files.File;
BEGIN
	Files.Delete (logName, res);
	file := Files.New (logName);
	NEW (text); Texts.Open (text, "");
	Texts.Append (text, logWriter.buf);
	Texts.Store (text, file, 0, len);
	Files.Register (file);
	file := NIL;
	text := NIL
END LogClose;

PROCEDURE LogPreempt;
BEGIN
	Texts.WriteLn (logWriter);
	Texts.Append (Oberon.Log, logWriter.buf)
END LogPreempt;

PROCEDURE LogCh (ch: CHAR);
BEGIN
	Texts.Write (logWriter, ch)
END LogCh;

PROCEDURE LogHex (i: LONGINT);
BEGIN
	Texts.WriteHex (logWriter, i);
	Texts.Write (logWriter, "H")
END LogHex;

PROCEDURE LogInt (i: LONGINT);
BEGIN
	Texts.WriteInt (logWriter, i, 2);
END LogInt;

PROCEDURE LogBool (b: BOOLEAN);
BEGIN
	IF b THEN Texts.WriteString(logWriter, "TRUE") ELSE Texts.WriteString(logWriter, "FALSE") END
END LogBool;

PROCEDURE LogLn;
BEGIN
	Texts.WriteLn (logWriter)
END LogLn;

PROCEDURE LogStr (s: ARRAY OF CHAR);
BEGIN
	Texts.WriteString(logWriter, s)
END LogStr;

PROCEDURE Dump(next: LONGINT; msg: ARRAY OF CHAR);
BEGIN
	LogHex (next); LogStr (" -- +"); LogInt (next MOD 32); LogStr ("  "); LogStr (msg); LogLn
END Dump;

PROCEDURE ErrMsg (n: INTEGER; name: ARRAY OF CHAR);
BEGIN
	IF (res = done) & (n # 0) THEN
		res := n;
		LogStr (name);
		IF (n = fileNotFound) OR (n = moduleNotFound) THEN LogStr (" not found")
		ELSIF n = invalidObjFile THEN LogStr (" not an obj-file")
		ELSIF n = corruptedObjFile THEN LogStr (" corrupted obj file")
		ELSIF n = notEnoughSpace THEN LogStr (" not enough space")
		ELSIF n = refCntNotZero THEN LogStr (" reference count not zero")
		ELSIF n = cyclicImport THEN LogStr (" imported cyclic")
		ELSIF n = cmdNotFound THEN LogStr (" not found")	(* assumes importing = procedure name *)
		ELSE LogStr (" unknown error code")
		END;
		LogLn
	END
END ErrMsg;

PROCEDURE Halt (msg: ARRAY OF CHAR);
BEGIN
	LogClose;
	Texts.WriteLn(W);
	Texts.WriteString(W, "BootLinker Error: "); Texts.WriteString(W, msg); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf);
	HALT (100)
END Halt;

PROCEDURE ExtractNames (string: ARRAY OF CHAR; VAR module, procedure: ARRAY OF CHAR);
(* Extracts the module and procedure from a <module>.<procedure> string.
	Can also be used to extract the name and extension from a file name. *)
VAR
	i, length, mlength: INTEGER;
BEGIN
	i := 0;
	length := SHORT (Length (string));
	WHILE (i < length) & (string[i] # ".") DO module[i] := string[i]; INC (i) END	(* WHILE *);
	mlength := i+1;
	module[i] := 0X;	(* terminate string *)
	INC (i);	(* skip over "." *)
	WHILE (i < length) DO procedure[i-mlength] := string[i]; INC (i) END	(* WHILE *);
	procedure[i-mlength] := 0X
END ExtractNames;

(* ---------------------------------------------------------- *)
(* Module Handling Procedures *)

PROCEDURE Loaded (VAR name: ARRAY OF CHAR): BOOLEAN;
VAR p: Module;
BEGIN
	p := objectList;
	WHILE (p # NIL) & (p.name # name) DO p := p.link END;
	RETURN p # NIL
END Loaded;

PROCEDURE Insert (o: Module);
VAR t: Module;
BEGIN	(* the modules must be sorted by the base address *)
	IF objectList = NIL THEN objectList := o; o.link := NIL
	ELSE
		t := objectList;
		WHILE (t.link # NIL) & (t.link.base < o.base) DO t := t.link END;
		o.link := t.link; t.link := o
	END;
END Insert;

PROCEDURE FindModule (name: ARRAY OF CHAR): Module;
VAR t: Module;
BEGIN
	t := objectList;
	WHILE (t # NIL) & (t.name # name) DO t := t.link END;
	IF t # NIL THEN RETURN t
	ELSE RETURN NIL
	END
END FindModule;


(* ---------------------------------------------------------- *)
PROCEDURE PutDWord (VAR code: ARRAY OF S.BYTE; idx, value: LONGINT);
BEGIN
	S.PUT (S.ADR (code[idx]), value)
END PutDWord;

(* ---------------------------------------------------------- *)
PROCEDURE AddInitPoint (entryPoint: LONGINT; object: Module);
VAR
	new, p: InitPoint;
BEGIN
	NEW (new);
	new.entryPoint := entryPoint; new.object := object;
	IF initPointList = NIL THEN
		new.next := initPointList; initPointList := new;
	ELSE
		p := initPointList;
		WHILE p.next # NIL DO p := p.next END;
		new.next := NIL; p.next := new
	END;
	INC (nofEntryPoints)
END AddInitPoint;

(*-----------------------------------------------------------*)
(* Returns num rounded up to the nearest multiple of boundary *)
PROCEDURE Align (num, boundary: LONGINT): LONGINT;
BEGIN RETURN num+(-num) MOD boundary
END Align;

(* ---------------------------------------------------------- *)
(* The Module Loader. This part is very close to the module "Modules". The
	only differences are:
	- The fixups are done relative to the imageBase address
	- The modules are not inserted in the module list
*)
PROCEDURE LSW (x: LONGINT): LONGINT;
BEGIN	(* least significant word (unsigned) *)
	RETURN S.VAL (LONGINT, S.VAL (SET, x)*S.VAL (SET, 0FFFFH))
END LSW;

PROCEDURE MSW (x: LONGINT): LONGINT;
BEGIN	(* most significant word (unsigned) *)
	RETURN S.LSH (x,-16)
END MSW;

PROCEDURE And (x, y: LONGINT): LONGINT;
BEGIN RETURN S.VAL (LONGINT, S.VAL (SET, x)*S.VAL (SET, y));
END And;

PROCEDURE ReadString (VAR R: Files.Rider; VAR string: ARRAY OF CHAR);
VAR i: INTEGER; ch: CHAR;
BEGIN i := 0;
	LOOP Files.Read (R, ch);
		IF ch = 0X THEN string[i] := 0X; RETURN
		ELSIF ch > 7FX THEN string[i] := CHR (ORD (ch)-80H); string[i+1] := 0X; RETURN
		ELSE string[i] := ch; INC (i) END
	END
END ReadString;

PROCEDURE ReadUnsigned (VAR R: Files.Rider; VAR u: LONGINT);
(* read unsigned, 16 bit, little endian value *)
VAR low, high: CHAR;
BEGIN
	Files.Read (R, low); Files.Read (R, high);
	u := 256*LONG (ORD (high))+ORD (low);
END ReadUnsigned;

(*---- module loading ---- *)

PROCEDURE^ Load (VAR m: Module; name: ARRAY OF CHAR; VAR base: LONGINT);

PROCEDURE LoadModule (VAR R: Files.Rider; m: Module; VAR base: LONGINT);
	TYPE TDesc = POINTER TO RECORD word: ARRAY 32000 OF LONGINT END;
	VAR
		ch: CHAR;
		tmp, nofDataLinks, nofLinks: INTEGER;
		i, mno, j, symSize, e, k, t: LONGINT;
		imp: Module; mname: ModuleName;
		body: Command; linkTab: LinkTab; dataLinks: DataLinkTab;
		(*
		types: ARRAY 128 OF RECORD
			initialized: BOOLEAN;
			tdesc: TDesc;
			entry, root, nofMeth, nofInhMeth, baseMod: INTEGER;
			baseEntry: LONGINT
		END;
		*)
	
	PROCEDURE FixupCall (codeNow, codeImg, link, fixval: LONGINT);
	VAR instr, nextlink, jmp: LONGINT;
	BEGIN
		REPEAT
			S.GET (codeNow+link, instr);
			nextlink := MSW (instr);
			S.GET (codeNow+link-1, jmp);
			IF LSW (jmp) MOD 100H = 0E8H THEN
				S.PUT (codeNow+link, fixval-(codeImg+link+4))	(* + 4: to next instruction *)
			ELSE
				S.PUT (codeNow+link, fixval)
			END;
			link := nextlink
		UNTIL link = 0FFFFH
	END FixupCall;
	
	PROCEDURE FixupVar (code, link, fixval: LONGINT);
	VAR nofFixups: INTEGER; i, val: LONGINT;
	BEGIN
		nofFixups := dataLinks[link].nofFixups;
		i := 0;
		WHILE i < nofFixups DO
			S.GET (code+dataLinks[link].offset[i], val);
			S.PUT (code+dataLinks[link].offset[i], val+fixval);
			INC (i)
		END
	END FixupVar;
	
	PROCEDURE Fixup (m: Module; VAR link: LinkTab);
	VAR i, val, offs: LONGINT;
		modNo, nofFixups: INTEGER;
		codebase, database: LONGINT;
	BEGIN
		codebase := S.ADR (m.code[0]);
		database := S.ADR (m.data[0]) + m.dataSize;	(* -> real address of sb *)
(*
		(* global variables *)
		modNo := ORD (dataLinks[0].mod); nofFixups := dataLinks[0].nofFixups;
		IF modNo = 0 THEN
			i := 0;
			WHILE i < nofFixups DO
				S.GET (codebase+dataLinks[0].offset[i], val);
				S.PUT (codebase+dataLinks[0].offset[i], val+m.sb);
				INC (i)
			END
		END;
*)
		(* Kernel.NewRec, Kernel.NewSys, Kernel.NewArr, local Procedure assignments, case table and imported procedures *)
		i := 0;
		WHILE i < nofLinks DO
			IF ORD (link[i].mod) = 0 THEN
				(* Kernel.NewRec, Kernel.NewSys, Kernel.NewArr, local Procedure assignments, case table *)
				CASE ORD (link[i].entry) OF
						255:	(* case table fixup in constant area *)
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET ((*m.sb*) database+offs, val); S.PUT ((*m.sb*) database+offs, (*codebase*)m.codeBase+LSW (val));
							IF TraceMore THEN LogStr ("Fix case at"); LogHex (offs); LogLn  END;
							offs := MSW (val);
						END;
					 | 254:	(* local procedure assignment *)
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET (codebase+offs, val); S.PUT (codebase+offs, m.entries[LSW (val)]);
							IF TraceMore THEN LogStr ("Fix proc:= at"); LogHex (offs); LogLn  END;
							offs := MSW (val);
						END;
					 | 253:	(* Kernel.NewRec *)
						(*offs := 12345678;*)
						ASSERT (SysFix[newSF].adr # 0);
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET (codebase+offs, val);
							S.PUT (codebase+offs, SysFix[newSF].adr-((*codebase*)m.codeBase+offs+4));
							IF TraceMore THEN 
								LogStr ("Fix new at"); LogHex (m.codeBase+offs); LogStr (" call to "); LogHex (SysFix[newSF].adr);
								LogStr (" ("); LogHex (SysFix[newSF].adr-((*codebase*)m.codeBase+offs+4)); LogStr (")"); LogHex (offs); LogLn
							END;
							offs := MSW (val);
						END;
					 | 252:	(* Kernel.NewSys *)
						ASSERT (SysFix[sysnewSF].adr # 0);
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET (codebase+offs, val); S.PUT (codebase+offs, SysFix[sysnewSF].adr-((*codebase*)m.codeBase+offs+4));
							IF TraceMore THEN 
								LogStr ("Fix newsys at"); LogHex (m.codeBase+offs); LogStr (" call to "); LogHex (SysFix[sysnewSF].adr);
								LogStr (" ("); LogHex (SysFix[sysnewSF].adr-((*codebase*)m.codeBase+offs+4)); LogStr (")"); LogHex (offs); LogLn
							END;
							offs := MSW (val);
						END;
					 | 251:	(* Kernel.NewArr *)
						ASSERT (SysFix[newarrSF].adr # 0);
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET (codebase+offs, val); S.PUT (codebase+offs, SysFix[newarrSF].adr-((*codebase*)m.codeBase+offs+4));
							IF TraceMore THEN 
								LogStr ("Fix newarr at"); LogHex (m.codeBase+offs); LogStr (" call to "); LogHex (SysFix[newarrSF].adr);
								LogStr (" ("); LogHex (SysFix[newarrSF].adr-((*codebase*)m.codeBase+offs+4)); LogStr (")"); LogHex (offs); LogLn
							END;
							offs := MSW (val);
						END
					|  250: (* Kernel.Start *)
						ASSERT (SysFix[StartSF].adr # 0);
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET (codebase+offs, val); S.PUT (codebase+offs, SysFix[StartSF].adr - (m.codeBase + offs + 4)); 
							IF TraceMore THEN LogStr ("Fix start at"); LogHex (offs); LogLn  END;
							offs := MSW(val)
					 	END
					|  249: (* Kernel.Passivate *)
						ASSERT (SysFix[PassivateSF].adr # 0);
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET (codebase+offs, val); S.PUT (codebase+offs, SysFix[PassivateSF].adr - (m.codeBase + offs + 4)); 
							IF TraceMore THEN LogStr ("Fix passivate at"); LogHex (offs); LogLn  END;
							offs := MSW(val)
					 	END
					|  248: (* Kernel.Activate *)	(* OBSOLETE pjm *)
						ASSERT (SysFix[ActivateSF].adr # 0);
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET (codebase+offs, val); S.PUT (codebase+offs, SysFix[ActivateSF].adr - (m.codeBase + offs + 4)); 
							IF TraceMore THEN LogStr ("Fix activate at"); LogHex (offs); LogLn END;
							offs := MSW(val)
					 	END
					|  247: (* Kernel.Lock *)
						ASSERT (SysFix[LockSF].adr # 0);
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET (codebase+offs, val); S.PUT (codebase+offs, SysFix[LockSF].adr - (m.codeBase + offs + 4)); 

							IF TraceMore THEN LogStr ("Fix lock at"); LogHex (offs); LogLn END;
							offs := MSW(val)
					 	END
					|  246: (* Kernel.Unlock *)
						ASSERT (SysFix[UnlockSF].adr # 0);
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET (codebase+offs, val); S.PUT (codebase+offs, SysFix[UnlockSF].adr - (m.codeBase + offs + 4)); 
							IF TraceMore THEN LogStr ("Fix unlock at"); LogHex (offs); LogLn END;
							offs := MSW(val)
					 	END

(*
					|  244: (* Kernel.HeapCopyArr *)
						ASSERT (SysFix[copyarraySF].adr # 0);
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET (codebase+offs, val); S.PUT (codebase+offs, SysFix[copyarraySF].adr - (m.codeBase + offs + 4)); 
							offs := MSW(val)
					 	END
					|  243: (* Kernel.NewSysArr *)
						ASSERT (SysFix[newsysarrSF].adr # 0);
						offs := link[i].link;
						WHILE offs # 0FFFFH DO
							S.GET (codebase+offs, val); S.PUT (codebase+offs, SysFix[newsysarrSF].adr - (m.codeBase + offs + 4)); 
							offs := MSW(val)
					 	END
*)
					ELSE
						Texts.WriteString(W, "Unknown fixup "); 
						Texts.WriteInt(W, ORD (link[i].entry), 4); Texts.WriteLn(W);
						Texts.Append(Oberon.Log, W.buf);
						HALT (98)
				END
			ELSE	(* imported procedure from module from *)
				HALT (99)	(* this case should never occure *)
			END;
			INC (i)
		END
	END Fixup;

	PROCEDURE CheckUseBlock (VAR R: Files.Rider; M: Module);
	VAR mod: Module; name: ModuleName;
			tab: LONGINT;
		PROCEDURE Tab;
			VAR j: LONGINT;
		BEGIN
			j := tab;
			WHILE j > 0 DO LogCh (9X); DEC (j) END;
		END Tab;
	
		PROCEDURE Err;
		BEGIN
			HALT (MAX(INTEGER));
			IF res = 0 THEN LogStr (M.name); LogStr (" imports incompatible version of "); LogStr (mod.name); LogStr (": "); res := incompImport
			ELSE LogCh (9X) END
		END Err;
		
		PROCEDURE CheckScope (scope: ExportDesc; level: INTEGER);
		VAR fp, link, i, tdadr: LONGINT; tadr: ExportPtr; tmpErr: BOOLEAN;
		BEGIN tmpErr := (level = EUerrScope);
			IF TraceMore THEN Tab; LogStr ("-> CheckScope at "); LogInt (level); LogLn; INC (tab) END;
			i := 0;
			Files.ReadNum (R, fp);
			WHILE fp # EUEnd DO
				IF fp = EURecord THEN Files.ReadNum (R, link);
					IF TraceMore THEN Tab; LogStr ("(EURecord) link = "); LogInt (link); LogStr (" i = "); LogInt (i); LogLn END;
					IF tmpErr THEN CheckScope (scope.dsc[i], EUerrScope)
					ELSE
						IF scope.dsc[i].dsc # NIL THEN
							IF link # 0 THEN tadr := S.VAL (ExportPtr, S.ADR (scope.dsc[i].dsc[0]));
								IF TraceMore THEN 
									LogStr ("Fixup from "); LogStr (mod.name); LogStr (" ("); LogHex (mod.sb+tadr.adr);
									LogStr (")  to "); LogStr (M.name); LogStr (" ("); LogHex (M.sb-link); LogStr (")"); LogLn;
								END;
								S.GET (S.ADR(mod.data[0])+mod.dataSize+tadr.adr, tdadr); S.PUT (S.ADR(M.data[0])+M.dataSize-link, tdadr)	(* tdadr at tadr[0] *)
							END
						END;
						CheckScope (scope.dsc[i], EUrecScope)
					END
				ELSE
					ReadString (R, name);
					IF TraceMore THEN Tab; LogStr ("(ELSE) name = "); LogStr (name) END;
					IF level >= EUobjScope THEN tmpErr := FALSE;
						IF level = EUobjScope THEN Files.ReadNum (R, link) END;
						IF TraceMore THEN LogStr (" link = "); LogInt (link); LogStr ("  fp = "); LogInt (fp); LogLn END;
						i := 0;
						WHILE (i < scope.nofExp) & (scope.dsc[i].fp # fp) DO INC (i) END;
						IF i >= scope.nofExp THEN Err; tmpErr := TRUE; LogLn; LogCh (9X);
							IF name = "@" THEN LogStr ("RECORD ")
							ELSE LogStr (name)
							END;
							LogStr (" incompatible");
							DEC (i)
						ELSIF (level = EUobjScope) & (link # 0) THEN
							IF And (link, EUProcFlag) = 0 THEN
								FixupVar (S.ADR (M.code[0]), link, mod.sb+scope.dsc[i].adr)
							ELSE
								FixupCall (S.ADR (M.code[0]), M.codeBase, link-EUProcFlag, scope.dsc[i].adr+ mod.codeBase)
							END
						END
					END
				END;
				Files.ReadNum (R, fp)
			END;
			IF TraceMore THEN DEC(tab); Tab; LogStr ("<- CheckScope"); LogLn END
		END CheckScope;
		
	BEGIN ReadString (R, name);
		WHILE (name # "") & (res = 0) DO
			mod := FindModule (name);
			IF mod = NIL THEN HALT (99); Load (mod, name, imageSize) END;
			IF res = 0 THEN CheckScope (mod.export, EUobjScope) END;
			ReadString (R, name)
		END
	END CheckUseBlock;
	
	PROCEDURE SetTDescAdr (M: Module; entry: LONGINT; t: Type);
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE (i < M.export.nofExp) & 
				((M.export.dsc[i].dsc = NIL) OR ((M.export.dsc[i].dsc # NIL) & (M.export.dsc[i].dsc[0].adr # entry))) DO 
			INC (i)
		END;
		IF i < M.export.nofExp THEN M.export.dsc[i].dsc[0].type := t;
		END
	END SetTDescAdr;
	
	PROCEDURE FindTDescAdr (M: Module; fp: LONGINT; VAR t: Type);
	VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE (i < M.export.nofExp) & (M.export.dsc[i].fp # fp) DO INC (i) END;
		IF i < M.export.nofExp THEN t := M.export.dsc[i].dsc[0].type
		(*IF i < M.export.nofExp THEN adr := M.export.dsc[i].dsc[0].adr*)
		ELSE HALT (99)
		END
	END FindTDescAdr;

	PROCEDURE InitType (i: LONGINT);
	VAR j, t, baseType, tag, entry, baseModNo: LONGINT; extlev, n, root: INTEGER; td: TDesc; baseMod: Module;
	BEGIN
		ASSERT (m.tdescs # NIL);
		ASSERT (i < m.nofTds);
		IF ~m.tdescs[i].initialized THEN
			SetTDescAdr (m, m.tdescs[i].tdEntry, m.tdescs[i]);
			baseModNo := m.tdescs[i].baseMod; m.tdescs[i].extlev := 0;
			IF baseModNo #-1 THEN	(* extended type *)
				IF baseModNo = 0 THEN	(* base type in this module, initialize first! *)
					j := 0;
					WHILE (j < m.nofTds) & (m.tdescs[j].tdEntry # m.tdescs[i].baseEntry) DO INC (j) END;
					InitType (j);
					m.tdescs[i].baseType := m.tdescs[j]

				ELSIF baseModNo > 0 THEN
					baseMod := m.imports[baseModNo-1];
					FindTDescAdr (baseMod, m.tdescs[i].baseEntry, m.tdescs[i].baseType);
					ASSERT (m.tdescs[i].baseType # NIL);
				ELSE
					HALT (99)
				END;
				ASSERT (m.tdescs[i].baseType # NIL);
				m.tdescs[i].extlev := m.tdescs[i].baseType.extlev + 1;
			END;
			m.tdescs[i].initialized := TRUE;
		END
	END InitType;
	
	PROCEDURE InitTypes;
	VAR i: LONGINT;
	BEGIN i := 0;
		WHILE i < m.nofTds DO InitType (i); INC (i) END
	END InitTypes;
	
	PROCEDURE Expect (tag: CHAR);
	VAR ch: CHAR;
	BEGIN Files.Read (R, ch);
		IF ch # tag THEN ErrMsg (corruptedObjFile, m.name) END
	END Expect;
	
	PROCEDURE ReadHeader (VAR m: Module; VAR R: Files.Rider);
		VAR dummy: INTEGER;
	BEGIN
		Files.ReadLInt (R, m.refSize);
		Files.ReadInt (R, tmp); m.nofEntries := tmp;
		Files.ReadInt (R, tmp); m.nofCmds := tmp;
		Files.ReadInt (R, tmp); m.nofPtrs := tmp;
		Files.ReadInt (R, tmp); m.nofTds := tmp;
		Files.ReadInt (R, tmp); m.nofImps := tmp;
		Files.ReadInt (R, nofDataLinks);
		Files.ReadInt (R, nofLinks);
		Files.ReadLInt (R, m.dataSize);
		Files.ReadInt (R, tmp); m.conSize := tmp;
		ReadUnsigned (R, m.codeSize);
		Files.ReadString (R, m.name);
(*
		Files.ReadInt (R, dummy); IF dummy # -1 THEN Texts.WriteString(W, "no active module allowed"); Texts.WriteLn(W); HALT (99) END;
		Files.ReadInt (R, dummy); IF dummy # -1 THEN Texts.WriteString(W, "no module initialiser allowed"); Texts.WriteLn(W); HALT (99) END;
*)
		IF Trace THEN
			LogStr ("refsize = "); LogHex (m.refSize); LogLn;
			LogStr ("nofEntries = "); LogHex (m.nofEntries); LogLn;
			LogStr ("nofCmds  = "); LogHex (m.nofCmds); LogLn;
			LogStr ("nofPtrs  = "); LogHex (m.nofPtrs); LogLn;
			LogStr ("nofTds  = "); LogHex (m.nofTds); LogLn;
			LogStr ("nofImps  = "); LogHex (m.nofImps); LogLn;
			LogStr ("nofDataLinks  = "); LogHex (nofDataLinks); LogLn;
			LogStr ("nofLinks  = "); LogHex (nofLinks); LogLn;
			LogStr ("dataSize  = "); LogHex (m.dataSize); LogLn;
			LogStr ("conSize  = "); LogHex (m.conSize); LogLn;
			LogStr ("codeSize  = "); LogHex (m.codeSize); LogLn;
			LogStr ("name  = "); LogStr (m.name); LogLn
		END;
	END ReadHeader;
	
	PROCEDURE ReadEntry (VAR m: Module; VAR R: Files.Rider);
	BEGIN
		IF m.nofEntries > 0 THEN NEW (m.entries, m.nofEntries) END;
		Expect (082X); i := 0;
		WHILE i < m.nofEntries DO ReadUnsigned (R, m.entries[i]); INC (i) END;
	END ReadEntry;
	
	PROCEDURE FixEntry (VAR m: Module);
	BEGIN
		e := m.codeBase;
		i := 0; WHILE i < m.nofEntries DO INC (m.entries[i], e); INC (i) END;
	END FixEntry;
	
	PROCEDURE ReadCmd (VAR m: Module; VAR R: Files.Rider);
	BEGIN
		IF m.nofCmds > 0 THEN NEW (m.cmds, m.nofCmds) END;
		Expect (083X); i := 0;
		WHILE i < m.nofCmds DO
			Files.ReadString (R, m.cmds[i].name); ReadUnsigned (R, m.cmds[i].adr);
			INC (i)
		END;
	END ReadCmd;
	
	PROCEDURE FixCmd (VAR m: Module);
	BEGIN
		e := m.codeBase;
		i := 0; WHILE i < m.nofCmds DO INC (m.cmds[i].adr, e); INC (i) END;
	END FixCmd;
	
	PROCEDURE ReadPtr (VAR m: Module; VAR R: Files.Rider);
	BEGIN
		IF m.nofPtrs > 0 THEN NEW (m.ptrTab, m.nofPtrs) END;
		Expect (084X);
		i := 0; WHILE i < m.nofPtrs DO
			Files.ReadLInt (R, m.ptrTab[i]);
			DEC(m.ptrTab[i], m.ptrTab[i] MOD 4);	(* strip deep copy flag *)
			INC (i)
		END;
	END ReadPtr;
	
	PROCEDURE FixPtr (VAR m: Module);
	BEGIN
		e := m.sb; i := 0; WHILE i < m.nofPtrs DO INC (m.ptrTab[i], e); INC (i) END;
	END FixPtr;
	
	PROCEDURE ReadImport (VAR m: Module;  VAR R: Files.Rider);
	BEGIN
		IF m.nofImps > 0 THEN NEW (m.imports, m.nofImps) END;
		Expect (085X);  mno := 0;
		WHILE (mno < m.nofImps) & (res = done) DO
			ReadString (R, mname);
			imp := FindModule (mname);
			IF imp = NIL THEN Halt("Imported module not loaded") END;
			IF res = done THEN
				INC (imp.refcnt);
				m.imports[mno] := imp;
				INC (mno)
			END
		END;
	END ReadImport;
	
	PROCEDURE ReadDataLink (VAR m: Module; VAR R: Files.Rider);
	BEGIN
		Expect (08DX); i := 0;
		WHILE i < nofDataLinks DO
			Files.Read (R, dataLinks[i].mod);
			Files.ReadInt (R, dataLinks[i].entry);
			Files.ReadInt (R, dataLinks[i].nofFixups);
			IF dataLinks[i].nofFixups > 0 THEN
				NEW (dataLinks[i].offset, dataLinks[i].nofFixups);
				j := 0;
				WHILE j < dataLinks[i].nofFixups DO
					ReadUnsigned (R, dataLinks[i].offset[j]);
					INC (j)
				END
			ELSE dataLinks[i].offset := NIL
			END;
			INC (i)
		END;
		(* data link doesn't change the image size, this are just fixup informations *)
	END ReadDataLink;
	
	PROCEDURE FixDataLinks (VAR m: Module);
		VAR modNo, nofFixups: INTEGER; codebase, i, val: LONGINT;
	BEGIN
		(* global variables *)
		codebase := S.ADR (m.code[0]);
		modNo := ORD (dataLinks[0].mod); nofFixups := dataLinks[0].nofFixups;
		IF modNo = 0 THEN
			i := 0;
			WHILE i < nofFixups DO
				S.GET (codebase+dataLinks[0].offset[i], val);
				S.PUT (codebase+dataLinks[0].offset[i], val+m.sb);
				INC (i)
			END
		END;
	END FixDataLinks;
	
	PROCEDURE ReadLink (VAR m: Module; VAR R: Files.Rider);
	BEGIN
		Expect (086X); i := 0;
		WHILE i < nofLinks DO
			Files.Read (R, linkTab[i].mod); Files.Read (R, linkTab[i].entry); ReadUnsigned (R, linkTab[i].link);
			INC (i)
		END;
		(* link doesn't change the image size, this are just fixup informations *)
	END ReadLink;
	
	PROCEDURE ReadDataConst (VAR m: Module; VAR R: Files.Rider);
	BEGIN
		m.dataSize := Align (m.dataSize, 8);
		IF (m.dataSize+m.conSize) > 0 THEN NEW (m.data, m.dataSize+m.conSize) END;
		i := 0;
		WHILE i < m.dataSize DO m.data[i] := 0X; INC (i) END;
		Expect (087X); i := 0; t := m.dataSize;	(* insert after the data *)
		WHILE i < m.conSize DO Files.Read (R, ch); m.data[t] := ch; INC (t); INC (i) END;
	END ReadDataConst;
	
	PROCEDURE ReadExport (VAR m: Module; VAR R: Files.Rider);
		VAR struct: ARRAY 1024 OF ExportPtr; nofStr: INTEGER;
			i: LONGINT;
		PROCEDURE Tab;
			VAR j: LONGINT;
		BEGIN
			j := i;
			WHILE j > 0 DO LogCh (9X); DEC (j) END;
		END Tab;
		
		PROCEDURE LoadScope (VAR scope: ExportDesc; level: INTEGER; adr: LONGINT);
			VAR no, no2: INTEGER; fp, off: LONGINT;
		BEGIN
			Files.ReadBytes (R, scope.nofExp, 2); no := 0; no2 := 0;
			IF TraceMore THEN Tab; LogStr ("-> NewScope at "); LogInt (level); LogStr("/"); LogInt (adr); LogStr("/"); LogInt (scope.nofExp); LogLn; INC (i) END;
			IF scope.nofExp # 0 THEN
				NEW (scope.dsc, scope.nofExp);
				scope.dsc[0].adr := adr
			END;
			IF level = EUrecScope THEN INC (nofStr); struct[nofStr] := S.VAL (ExportPtr, S.ADR (scope)) END;
			IF TraceMore & (level = EUrecScope) THEN Tab; LogStr("new struct "); LogInt (nofStr); LogLn END;
			Files.ReadNum (R, fp);
			WHILE fp # EUEnd DO
				IF fp = EURecord THEN Files.ReadNum (R, off);
					IF TraceMore THEN
						Tab; LogStr("(EURecord), off ="); LogInt (off); LogStr(" no2 ="); LogInt (no2); LogLn;
						IF (off<0) & (struct[-off]=NIL) THEN LogClose END
					END;
					IF off < 0 THEN scope.dsc[no2].nofExp := struct[-off].nofExp; scope.dsc[no2].dsc := struct[-off].dsc;	(* old type *)
					ELSE LoadScope (scope.dsc[no2], EUrecScope, off)
					END;
				ELSE
					IF level = EUobjScope THEN Files.ReadNum (R, scope.dsc[no].adr) END;
					IF TraceMore THEN
						Tab; LogStr("(EUobjScope), dsc["); LogInt (no); LogStr ("].adr ="); LogInt (scope.dsc[no].adr);
						LogStr("dsc[no].fp ="); LogInt (fp); LogLn
					END;
					scope.dsc[no].fp := fp; no2 := no; INC (no)
				END;
				Files.ReadNum (R, fp)
			END;
			IF TraceMore THEN
				Tab; DEC (i); LogStr ("<- End of scope "); LogLn
			END
		END LoadScope;
		
	BEGIN
		i := 0;
		Expect (088X);
		nofStr := 0; LoadScope (m.export, EUobjScope, 0);
	END ReadExport;
		
	PROCEDURE ReadCode (VAR m: Module; VAR R: Files.Rider);
	BEGIN
		IF m.codeSize > 0 THEN NEW (m.code, m.codeSize) END;
		Expect (089X); Files.ReadBytes (R, m.code^, m.codeSize);
	END ReadCode;
	
	PROCEDURE ReadUse (VAR m: Module; VAR R: Files.Rider);
	BEGIN
		Expect (08AX);
		CheckUseBlock (R, m);
	END ReadUse;
	
	PROCEDURE ReadType (VAR m: Module; VAR R: Files.Rider);
		VAR dummy: INTEGER; i, j: LONGINT;
	BEGIN
		IF m.nofTds > 0 THEN NEW (m.tdescs, m.nofTds) END;
		Expect (08BX); IF res # done THEN RETURN END;
		(* ReadTypes (R); *)
		i := 0;
		WHILE i < m.nofTds DO
			NEW (m.tdescs[i]);
			m.tdescs[i].initialized := FALSE; m.tdescs[i].module := m;
			Files.ReadLInt (R, m.tdescs[i].size);
			Files.ReadInt (R, dummy); m.tdescs[i].tdEntry := dummy;
			Files.ReadInt (R, dummy); m.tdescs[i].baseMod := dummy;
			Files.ReadLInt (R, m.tdescs[i].baseEntry);
			Files.ReadInt (R, dummy); m.tdescs[i].nofMethods := dummy;
			Files.ReadInt (R, dummy (* nofInhMeth *));
			Files.ReadInt (R, dummy); m.tdescs[i].nofNewMethods := dummy;
			Files.ReadInt (R, dummy); m.tdescs[i].nofPtrs := dummy;
			Files.ReadString (R, m.tdescs[i].name);
			IF TraceMore THEN 
				LogStr ("name = "); LogStr (m.tdescs[i].name); LogLn;
				LogStr ("size = "); LogInt (m.tdescs[i].size); LogLn;
				LogStr ("tdEntry = "); LogInt (m.tdescs[i].tdEntry); LogLn;
				LogStr ("baseMod = "); LogInt (m.tdescs[i].baseMod); LogLn;
				LogStr ("baseEntry = "); LogInt (m.tdescs[i].baseEntry); LogLn;
				LogStr ("-------------------------------------------------"); LogLn
			END;
			IF m.tdescs[i].nofNewMethods > 0 THEN NEW (m.tdescs[i].newMethods, m.tdescs[i].nofNewMethods) END;
			j := 0;
			WHILE j < m.tdescs[i].nofNewMethods DO
				Files.ReadInt (R, m.tdescs[i].newMethods[j].mthNo); Files.ReadInt (R, m.tdescs[i].newMethods[j].entryNo);
				INC (j)
			END;
			IF m.tdescs[i].nofPtrs > 0 THEN NEW (m.tdescs[i].ptrOffset, m.tdescs[i].nofPtrs) END;
			j := 0;
			WHILE j < m.tdescs[i].nofPtrs DO Files.ReadLInt (R, m.tdescs[i].ptrOffset[j]); INC (j) END;
			
			(* td size *)
			ASSERT ((m.typeTableAdr+m.typeTableSize+4) MOD Boundary = 0);	(* type must aligned *)
			m.tdescs[i].tdSize := 13 (* fields tdsize..mdesc *) + m.tdescs[i].nofMethods + ExtTabWordSize + 1 (* tag *);
			INC (m.tdescs[i].tdSize, (-m.tdescs[i].tdSize+2) MOD 4);	(* ADR(td.word[root]) MOD 16 = 8 *)
			m.tdescs[i].tdAdr := m.tdescs[i].tdSize*4 + m.typeTableAdr+m.typeTableSize+4;	(* <-- skip the td *)
			ASSERT (m.tdescs[i].tdAdr MOD 16 = 8);	(* type alignment *)
			m.tdescs[i].tdSize := (m.tdescs[i].tdSize + 1 (*recsize*) + m.tdescs[i].nofPtrs + 1 (*sentinel*)) * 4;
			
			(* write the td address in the constants section *)
			S.PUT (S.ADR (m.data[0])+m.dataSize+m.tdescs[i].tdEntry, m.tdescs[i].tdAdr);
			
			m.tdescs[i].padSize := (-m.tdescs[i].tdSize-4(*tag*)) MOD Boundary;
			INC(m.typeTableSize, 4(*tag*) + m.tdescs[i].tdSize + m.tdescs[i].padSize);
			
			ASSERT (m.typeTableSize MOD 32 = 0);
			IF (SysFix[modDescSF].module = m.name) & (SysFix[modDescSF].command = m.tdescs[i].name) THEN
				SysFix[modDescSF].adr := m.tdescs[i].tdAdr
			END;
			IF (SysFix[expDescSF].module = m.name) & (SysFix[expDescSF].command = m.tdescs[i].name) THEN
				SysFix[expDescSF].adr := m.tdescs[i].tdAdr
			END;

			INC (i)
		END;
		
		IF res # done THEN RETURN END;
	END ReadType;

	PROCEDURE ReadRef (VAR m: Module; VAR R: Files.Rider);
	BEGIN
		IF m.refSize > 0 THEN NEW (m.refs, m.refSize) END;
		Expect (08CX); Files.ReadBytes (R, m.refs^, m.refSize);
	END ReadRef;
	
	PROCEDURE FindAdr (VAR m: Module; VAR pat: Name; type: LONGINT): LONGINT;
		VAR pos, x, y: LONGINT; n: LONGINT;
		
		PROCEDURE Find (beg: LONGINT);
			CONST MaxPat = 128;
			VAR
				len, i, j, b, e, srclen: LONGINT;
				ch: CHAR;
				ref: ARRAY MaxPat OF CHAR;
		BEGIN
			srclen := m.refSize; len := Length (pat);
			ch := m.refs[pos]; INC(pos); ref[0] := ch;
			i := 0; j := 0; b := 0; e := 1;
			WHILE (pos <= srclen) & (i < len) DO
				IF pat[i] = ch THEN	INC(i); j := (j + 1) MOD MaxPat
				ELSE	i := 0; b := (b + 1) MOD MaxPat; j := b
				END;
				IF j # e THEN ch := ref[j]
				ELSE
					IF pos >= srclen THEN	ch := 0X	ELSE	ch := m.refs[pos]	END;
					INC(pos); ref[j] := ch; e := (e + 1) MOD MaxPat; INC(beg);
				END
			END;
			IF i = len THEN pos := beg-len ELSE pos := -1 END
		END Find;
		
	BEGIN
		y := 0; n := 0; pos := 0; Find (pos);
		ASSERT(pos # -1);	(* name found *)
		IF pos = -1 THEN RETURN 0
		ELSE
			IF type = Proc THEN
				DEC (pos); 	(* last byte of the number *)
				WHILE m.refs[pos-1] >= 80X DO DEC(pos) END;
				INC (pos);
			ELSIF type = Var THEN
				(* (1X | 3X) (1X ..15X) Num Name *)
				DEC (pos); 	(* last byte of the number *)
				WHILE m.refs[pos-1] >= 80X DO DEC(pos) END
			ELSE
				HALT (99)
			END;
			WHILE m.refs[pos] >= 80X DO INC(y, S.LSH(LONG(m.refs[pos]) - 128, n)); INC(n, 7); INC (pos) END;
			x := ASH(S.LSH(LONG(m.refs[pos]), 25), n-25) + y;
			RETURN x
		END
	END FindAdr;
	
	PROCEDURE AssignExportSizes (VAR exp: ExportDesc; m: Module);
		VAR size, i: LONGINT;
	BEGIN
		exp.done := TRUE; size := exp.nofExp;
		IF (size = 0) OR exp.dsc[0].done THEN RETURN END;
		exp.dsc[0].Adr := m.expAdr + m.expSize + 4;
		IF TraceMore THEN
			LogStr ("AssignExport, new array at "); LogHex (exp.dsc[0].Adr); LogStr ("->");
			LogHex (exp.dsc[0].Adr); LogLn;
		END;
		ASSERT (exp.dsc[0].Adr MOD 32 = 0);
		INC (m.expSize, 32 * ((size*16 + TagSize+ArrayDescSize + 31) DIV 32));
		FOR i := 0 TO size-1 DO	AssignExportSizes (exp.dsc[i], m)	END
	END AssignExportSizes;

BEGIN	(* LoadModule *)
	m.init := FALSE; m.refcnt := 0; m.term := NIL;
	(* Skip sym file *)
	Files.ReadNum (R, symSize); Files.Set (R, Files.Base (R), Files.Pos (R)+symSize);
		
	ReadHeader (m, R);
	ReadEntry (m, R);
	ReadCmd (m, R);
	ReadPtr (m, R);
	ReadImport (m, R);		(* <- this changes the base !!! *)
	ReadDataLink (m, R);
	ReadLink (m, R);
	ReadDataConst (m, R);
	ReadExport (m, R);
	ReadCode (m, R);
	
	(* compute sizes *)

	m.base := base; m.imageSize := 28; (* hidden td *)
	Insert (m);
	INC (m.imageSize, 16 * ((m.nofEntries*4 + ArrayDescSize +4	(* no tag here *) + 15) DIV 16));
	INC (m.imageSize, 16 * ((m.nofCmds*36 + TagSize+ArrayDescSize + 15) DIV 16));
	INC (m.imageSize, 16 * ((m.nofPtrs*4 + TagSize+ArrayDescSize + 15) DIV 16));
	INC (m.imageSize, 16 * ((m.nofImps*4 + TagSize+ArrayDescSize + 15) DIV 16));
	m.sb := m.base + m.imageSize + ArrayDescSize + m.dataSize;
	INC (m.imageSize, ((TagSize+ArrayDescSize + m.dataSize + m.conSize + 15) DIV 16) * 16);
	m.codeBase := m.base + m.imageSize + ArrayDescSize;
	INC (m.imageSize, ((TagSize+ArrayDescSize + m.codeSize + 15) DIV 16) * 16);
	INC (m.imageSize, 16 * ((m.nofTds*4 + TagSize+ArrayDescSize + 15) DIV 16));
	m.refBase := m.base + m.imageSize + ArrayDescSize;
	INC (m.imageSize, ((m.refSize + TagSize+ArrayDescSize + 15) DIV 16) * 16);
	INC (m.imageSize, ((DefMaxImport*4 + TagSize+ArrayDescSize + 15) DIV 16) * 16);
	INC (m.imageSize, ((DefMaxStruct*4 + TagSize+ArrayDescSize + 15) DIV 16) * 16);
	INC (m.imageSize, DefMaxReimp*4 + TagSize+ArrayDescSize);
(*	INC (m.imageSize, ((DefMaxReimp*4 + 35) DIV 16) * 16);	*)
	m.expAdr := Align (m.base + m.imageSize + 4, Boundary) - 4;		(* +4, place for the tag *)
	IF Trace THEN
		Dump (m.base, m.name); Dump (m.base+m.imageSize+ArrayDescSize, "entries");
		IF TraceMore THEN
			LogStr ("--------- "); LogHex (m.nofEntries); LogStr (" nofEntries"); LogLn
		END;
		Dump (m.base+m.imageSize+ArrayDescSize, "cmds");
		Dump (m.base+m.imageSize+ArrayDescSize, "ptrs");
		Dump (m.base+m.imageSize+ArrayDescSize, "imports");
		Dump (m.base+m.imageSize+ArrayDescSize, "data");
		Dump (m.sb, "const");
	END;
	
	ASSERT (m.expAdr MOD 32 = 28);
	m.expPadding := m.expAdr - m.base - m.imageSize; m.expSize := 0;
	INC (m.imageSize, m.expPadding);
	AssignExportSizes (m.export, m);
	INC (m.imageSize, m.expSize);
	
	ReadUse (m, R);		(* <- size informations used here *)
	
	(* tds fixed in the ReadType section, because they don't belong to the big block here !! *)
	
	(* prepare for types *)
	(* already aligned on the 32-b boundary by the AssignExportSizes procedure *)
	m.typeTableAdr := m.base + m.imageSize;
	m.typeTableSize := 0;
	ASSERT ((m.imageSize+m.base+4) MOD Boundary = 0);
	ReadType (m, R);
	
	INC (m.imageSize, m.typeTableSize);
	ASSERT ((m.imageSize+m.base+4) MOD Boundary = 0);
	
	ReadRef (m, R);
	
	ASSERT ((m.imageSize+m.base+4) MOD Boundary = 0);
	m.modDescAdr := m.imageSize + m.base + 4;
	INC (m.imageSize, moduleDescSize);

	IF res = done THEN
		FOR i := newSF TO copyarraySF DO
			IF SysFix[i].module = m.name THEN SysFix[i].adr := m.codeBase + FindAdr (m, SysFix[i].command, Proc) END
		END;
		IF SysFix[CurProcSF].module = m.name THEN
			SysFix[CurProcSF].adr := m.sb + FindAdr (m, SysFix[CurProcSF].command, Var);
		END;
		IF SysFix[listSF].module = m.name THEN
			t := FindAdr (m, SysFix[listSF].command, Var);
			SysFix[listSF].adr := (*m.sb + t*)S.ADR (m.data[m.dataSize + t]);
			S.PUT (S.ADR (m.data[m.dataSize + t]), objectList.modDescAdr (*+4*) (*tag*));	(* <- fix list of modules *)
		END;
		FixEntry (m);
		FixCmd (m);
		FixPtr (m);
		FixDataLinks (m);
		Fixup (m, linkTab);

		S.PUT (S.ADR (m.data[m.dataSize]), m.modDescAdr (*+4*));		(*SELF*)

		InitTypes;
		m.init := TRUE;
		AddInitPoint (m.codeBase, m);
		base := base + m.imageSize;
	ELSE
		LogClose; HALT (99);
	END
END LoadModule;

PROCEDURE Load (VAR m: Module;  name: ARRAY OF CHAR;  VAR base: LONGINT);
VAR f: Files.File;  R: Files.Rider;  fname: ARRAY 64 OF CHAR;  tag: CHAR;  imp: Module;
BEGIN
	m := FindModule (name);
	IF m = NIL THEN
		COPY (name, fname);  Concat (fname, extension, fname);
		f := Files.Old (fname);
		IF f = NIL THEN
			ErrMsg (fileNotFound, name);
			RETURN
		END;
		Files.Set (R, f, 0);  Files.Read (R, tag);
		IF tag # 0BBX THEN
			LogStr (fname);  LogStr (" is not an object file");  LogLn;  ErrMsg (invalidObjFile, name);
			RETURN
		END;
		NEW (m);  NEW (m.import, DefMaxImport);  NEW (m.struct, DefMaxStruct);
		NEW (m.reimp, DefMaxReimp);  m.nofImps :=-1;
		Files.Read (R, tag);
		IF tag # OFVersion THEN
			LogStr (fname);  LogStr (": wrong object file version");  LogLn;  ErrMsg (invalidObjFile, name);
			RETURN
		END;
		LoadModule (R, m, base)
	ELSE
		IF ~m.init THEN
			LogStr ("cyclic import not allowed");  ErrMsg (cyclicImport, name);
			RETURN
		END
	END
END Load;

(* ---------------------------------------------------------- *)
(* Dumps a pointer header of 28 bytes, like Kernel.NewSys would do 
	 during dynamic memory allocation *)
PROCEDURE DumpPtrHeader (VAR rider: Files.Rider; address, size: LONGINT; VAR adrPad, sizePad: LONGINT);
VAR header: ARRAY 7 OF LONGINT;	(* 28 bytes = 7 words *)
BEGIN
	adrPad := Align (address+4, Boundary)-4-address;
	sizePad := Align (size+28, Boundary)-size;
	header[0] := (address+adrPad)+4;	(* tag field *)
	header[1] := (size+sizePad)-4;	(* size *)
	header[2] :=-4;	(* sentinel *)
	header[3] := 0;
	header[4] := 0;
	header[5] := 0;
	header[6] := header[0];	(* tag *)
	IF adrPad > 0 THEN
		Files.WriteBytes (rider, padding, adrPad);
	END;
	Files.WriteBytes (rider, header, 28);
	DEC (sizePad, 28)	(* header already dumped - was included *)
END DumpPtrHeader;

PROCEDURE DumpInitCalls (VAR rider: Files.Rider; VAR entry: LONGINT);
VAR
	i: InitPoint;
	code: ARRAY 5 OF CHAR;
	relCallValue, adrPad, sizePad, base: LONGINT;
BEGIN
	LogStr ("Init block at ");
	LogHex (entry); LogLn;
	(* header like Kernel.NewSys *)
	ASSERT ((entry+4) MOD Boundary = 0);
	DumpPtrHeader (rider, entry, nofEntryPoints*5+4, adrPad, sizePad);
	INC (entry, 28);	(* skip header *)
	ASSERT (adrPad = 0);

	LogStr ("Init code at "); LogHex (entry); LogLn;
	i := initPointList; base := entry;
	code[0] := 0E8X;	(* CALL *)
	WHILE (i # NIL) DO
		LogStr ("Body at "); LogHex (i.entryPoint); LogLn;
		relCallValue := (i.entryPoint-(base+5));
		PutDWord (code, 1, relCallValue);
		Files.WriteBytes (rider, code, 5);	(* CALL <initcode> *)
		INC (base, 5);
		IF (i.next = NIL) THEN
			LogStr ("Main code at ");
			LogHex (i.entryPoint); LogLn
		END;
		i := i.next
	END;
	code[0] := 0FBX;	(* STI *)
	code[1] := 090X;	(*0F4X;*)	(* HLT *)
	code[2] := 0EBX;	(* JMP *)
	code[3] := 0FDX;	(* -3 *)
	Files.WriteBytes (rider, code, 4);
	IF sizePad > 0 THEN
		Files.WriteBytes (rider, padding, sizePad)
	END
END DumpInitCalls;

PROCEDURE PatchHeader (f: Files.File; base, entry, size: LONGINT);
VAR r: Files.Rider;
BEGIN
	Files.Set (r, f, 0); Files.Write (r, 0E8X); Files.WriteLInt (r, entry-(base+5));
	Files.Set (r, f, 6); Files.WriteLInt (r, base);	(* LinkBase *)
	Files.Set (r, f, 22); Files.WriteLInt (r, base+size);	(* HeapStart *)
	Files.Set (r, f, 30); Files.WriteLInt (r, 0);	(* PatchSize *)
	LogLn; LogStr ("PatchHeaders:"); LogLn;
	LogStr ("  link base: "); LogHex (base); LogLn;
	LogStr ("  image size: "); LogHex (size); LogLn;
	LogStr ("  heap start: "); LogHex (base+size); LogLn;
	LogStr ("  entry point: "); LogHex (entry-(base+5)); LogLn;
	LogStr ("  heap start: "); LogHex (base+size); LogLn; LogLn;
END PatchHeader;

PROCEDURE InsertPad (VAR rider: Files.Rider; VAR pos: LONGINT; size, alignTo: LONGINT);
VAR padSize: LONGINT;
BEGIN
	padSize := (-size) MOD alignTo;
	Files.WriteBytes (rider, padding, padSize);
	INC (pos, size+padSize);
END InsertPad;

(* ---------------------------------------------------------- *)
PROCEDURE DumpTypes (VAR rider: Files.Rider; m: Module; VAR next: LONGINT);
	VAR t: Type; i, j, tag: LONGINT;
	
		PROCEDURE GetMethodAddress (n: LONGINT; t: Type): LONGINT;
			VAR	i: LONGINT;
		BEGIN
			IF t = NIL THEN LogClose END;
			i := 0;
			WHILE (i < t.nofNewMethods) & (t.newMethods[i].mthNo # n) DO INC (i) END;
			IF i = t.nofNewMethods THEN RETURN GetMethodAddress (n, t.baseType)
			ELSE RETURN t.module.entries[t.newMethods[i].entryNo]
			END
		END GetMethodAddress;
		
		PROCEDURE WriteTags (t: Type);
		BEGIN
			Files.WriteLInt (rider, t.tdAdr);
			IF t.extlev # 0 THEN WriteTags (t.baseType) END
		END WriteTags;
		
BEGIN
	FOR i := 0 TO m.nofTds-1 DO
		ASSERT (next MOD Boundary = 28);	(* <- already points to the next one *)
		t := m.tdescs[i]; tag := next + 4;
		Files.WriteLInt (rider, tag);	(* <-- tag of the TDesc *)
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = next + 4);
		Files.WriteLInt (rider, t.tdSize);
		Files.WriteLInt (rider, -4);
		Files.WriteLInt (rider, t.tdAdr);
		Files.WriteLInt (rider, t.extlev);
		Files.WriteBytes (rider, t.name, 32);
		Files.WriteLInt (rider, m.modDescAdr (*+ 4*));
		INC (next, 13*4 + 4 (*tag*));	(* tdsize .. mdesc *)
		INC (next, t.nofMethods*4 + 16*4(*tags*));
		
		(* padding for methods *)
		IF (-next-12) MOD 16 # (-next+4) MOD 16 THEN HALT (99) END;
		j := (-next - 12) MOD 16; INC (next, j);			(* next should point to the tag *)
		ASSERT (next MOD 16 = 4);
		
		j := j DIV 4;
		WHILE j > 0 DO Files.WriteLInt (rider, 0); DEC (j) END;
		
		(* write methods *)
		j := t.nofMethods;
		WHILE j > 0 DO
			DEC (j);
			Files.WriteLInt (rider, GetMethodAddress(j, t));
		END;
		
		(* padding for tags *)
		FOR j := t.extlev+1 TO 15 DO Files.WriteLInt (rider, 0) END;
		
		(* tags *)
		WriteTags (t);
		
		ASSERT (next MOD 16 = 4);
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = next);
		Files.WriteLInt (rider, tag);
		INC (next, 4);
		ASSERT (next MOD 16 = 8);
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = next);
		ASSERT (next = t.tdAdr);
		
		Files.WriteLInt (rider, t.size);
		j := 0;
		WHILE j < t.nofPtrs DO Files.WriteLInt (rider, t.ptrOffset[j]); INC (j) END;
		Files.WriteLInt (rider, -4 * (j+1));
		Files.WriteBytes (rider, padding, t.padSize);
		INC (next, 4 (*size*) + t.nofPtrs*4 + 4(*sentinel*) + t.padSize);
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = next);
	END
END DumpTypes;

PROCEDURE DumpExport (VAR rider: Files.Rider; VAR exp: ExportDesc; VAR next: LONGINT; tag: LONGINT);
	VAR i, num: LONGINT; arrHdr: ArrayDesc;
BEGIN
	ASSERT (next MOD 32 = 0);
	num := exp.nofExp; (*arrHdr.len := num;*) exp.done := FALSE;
	IF (num = 0) OR ~exp.dsc[0].done THEN RETURN END;	(* don't traverse it *)
	
	(* write the array *)
	ASSERT (exp.dsc[0].Adr = next);
	Files.WriteLInt (rider, tag);	(* <- next already updated *)
	IF TraceMore THEN LogStr (" --------          ExpArray at"); LogHex (exp.dsc[0].Adr); LogLn END;
	ASSERT (Files.Length (Files.Base (rider)) + imageBase = exp.dsc[0].Adr);
	ASSERT (num > 0);
	arrHdr.a := exp.dsc[0].Adr + (num-1)*16 + ArrayDescSize;		(* <- last element to mark *)
	arrHdr.b := 0; 														(* <- reserved *)
	arrHdr.c := exp.dsc[0].Adr + ArrayDescSize; 							(* <- First Element *)
	arrHdr.len := num;																	(* <- dim *)
	(*arrHdr.lb := 0;
	arrHdr.empty := 0;*)
	Files.WriteBytes (rider, arrHdr, ArrayDescSize);
	ASSERT ((exp.dsc[0].Adr + ArrayDescSize) MOD 8 = 0);
	FOR i := 0 TO num-1 DO
		Files.WriteLInt (rider, exp.dsc[i].fp); Files.WriteLInt (rider, exp.dsc[i].adr);
		Files.WriteInt (rider, exp.dsc[i].nofExp); Files.WriteInt (rider, 0);	(* <- padding *)

		IF TraceMore & (exp.dsc[i].nofExp # 0) THEN	LogStr (" --------           -------- "); LogHex (i); LogStr (": "); LogHex (exp.dsc[i].dsc[0].Adr); LogLn; END;
		IF exp.dsc[i].nofExp = 0 THEN Files.WriteLInt (rider, 0) ELSE Files.WriteLInt (rider, exp.dsc[i].dsc[0].Adr) END
	END;
	InsertPad (rider, next, TagSize+ArrayDescSize+num*16, 32);
	FOR i := 0 TO num-1 DO
		DumpExport (rider, exp.dsc[i], next, tag)
	END;
END DumpExport;

PROCEDURE DumpModules (VAR rider: Files.Rider);
VAR img: DumpModule; size, next, num, tag: LONGINT;
	m, n: Module; i, j: LONGINT;
	arrHdr: ArrayDesc;
	keepbase, keepsb, keepcode: LONGINT;
	prevmod: LONGINT;
BEGIN
	i := 0; j := 0;
	arrHdr.a := 0; arrHdr.b := 0; arrHdr.c := 0; (*arrHdr.lb:=0; arrHdr.empty:=0;*)
	prevmod:=0;
	IF SysFix[listSF].adr # 0 THEN
		m := objectList;
		WHILE m.link#NIL DO  m:=m.link  END;
		S.PUT (SysFix[listSF].adr, m.modDescAdr);	(* <- fix list of modules *)
	END;
	m := objectList;
	WHILE m # NIL DO
		(* Module: header data *)
		NEW (img);

		(*IF m.link # NIL THEN img.link := m.link.modDescAdr (*+4*) ELSE img.link := 0 END;*)
		img.link := prevmod; prevmod := m.modDescAdr;
		img.name := m.name;
		img.init := m.init;
		img.refcnt := m.refcnt;
		IF img.refcnt = 0 THEN img.refcnt := 1 END;	(* disallow unloading of bootlinked modules, e.g. drivers *)
		img.sb := m.sb;
		img.term := NIL;

		next := m.base; tag := next+4;

		LogLn; LogStr ("--------- MODULE "); LogStr (m.name); LogLn;
		keepbase := next;
		Dump(next, "Base");
		ASSERT ((next+4) MOD Boundary = 0);
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = m.base);
		size := m.imageSize-moduleDescSize-m.typeTableSize-m.expSize-28;
		LogStr ("--------- "); LogHex (m.imageSize); LogStr (" image size "); LogLn;
		LogStr ("--------- "); LogHex (moduleDescSize); LogStr (" moduleDesc size "); LogLn;
		LogStr ("--------- "); LogHex (m.typeTableSize); LogStr (" typeTable size "); LogLn;
		LogStr ("--------- "); LogHex (m.expSize); LogStr (" exp size "); LogLn;
		LogStr ("--------- "); LogHex (size); LogStr (" size "); LogLn;
		DumpPtrHeader (rider, next, size, i, j);
		LogStr ("--------- "); LogStr (" sys block td header (28 bytes) "); LogLn;
		INC (next, 28);	(* sys block td size *)
		ASSERT ((i = 0) & (j = 0));

		(* Entries *)
		ASSERT (Files.Length (Files.Base (rider)) + imageBase = next);
		ASSERT (next MOD 16 = 8);
		img.entries := next; num := m.nofEntries; arrHdr.len := num;
		Dump (next+ArrayDescSize, "entries");
		Files.WriteBytes (rider, arrHdr, ArrayDescSize);	(* hidden header *)
		IF num > 0 THEN Files.WriteBytes (rider, m.entries^, num*4) END;
		InsertPad (rider, next, TagSize+ArrayDescSize+num*4, 16);	(* <-- 4 bytes left out for the tag *)

		(* Cmds *)
		Files.WriteLInt (rider, tag);	(* <- next already upadted *)
		ASSERT (Files.Length (Files.Base (rider)) + imageBase = next);
		ASSERT (next MOD 16 = 8);
		img.cmds := next; num := m.nofCmds; arrHdr.len := num;
		Dump (next+ArrayDescSize, "cmds");
		Files.WriteBytes (rider, arrHdr, ArrayDescSize);	(* hidden header *)
		IF num > 0 THEN Files.WriteBytes (rider, m.cmds^, num*36) END;
		InsertPad (rider, next, TagSize+ArrayDescSize+num*36, 16);

		(* Ptrs *)
		Files.WriteLInt (rider, tag);	(* <- next already upadted *)
		ASSERT (Files.Length (Files.Base (rider)) + imageBase = next);
		ASSERT (next MOD 16 = 8);
		img.ptrTab := next; num := m.nofPtrs; arrHdr.len := num;
		Dump (next+ArrayDescSize, "ptrs");
		 Files.WriteBytes (rider, arrHdr, ArrayDescSize);	(* hidden header *)
		IF num > 0 THEN Files.WriteBytes (rider, m.ptrTab^, num*4) END;
		InsertPad (rider, next, TagSize+ArrayDescSize+num*4, 16);

		(* Imports *)
		Files.WriteLInt (rider, tag);	(* <- next already updated *)
		ASSERT (Files.Length (Files.Base (rider)) + imageBase = next);
		ASSERT (next MOD 16 = 8);
		img.imports := next; num := m.nofImps; arrHdr.len := num;
		Dump (next+ArrayDescSize, "imports");
		Files.WriteBytes (rider, arrHdr, ArrayDescSize);	(* hidden header *)
		i := 0; WHILE i < m.nofImps DO
			Files.WriteLInt (rider, m.imports[i].modDescAdr (*+ 4*)); INC (i)
		END;
		InsertPad (rider, next, TagSize+ArrayDescSize+num*4, 16);

		(* Data *)(* Consts *)
		Files.WriteLInt (rider, tag);	(* <- next already updated *)
		ASSERT (Files.Length (Files.Base (rider)) + imageBase = next);
		ASSERT (next MOD 16 = 8);
		img.data := next; num := m.dataSize;
		arrHdr.len := m.dataSize + m.conSize;
		Dump (next+ArrayDescSize, "data");
		Files.WriteBytes (rider, arrHdr, ArrayDescSize);	(* hidden header *)
		keepsb := m.sb;
		Dump (m.sb, "SB");
		Dump (next + ArrayDescSize + m.dataSize, "const");
		ASSERT (m.sb = next + ArrayDescSize + m.dataSize);
		Files.WriteBytes (rider, m.data^, m.dataSize + m.conSize);
		InsertPad (rider, next, TagSize+ArrayDescSize + m.dataSize + m.conSize, 16);
		
		(* Code *)
		Files.WriteLInt (rider, tag);	(* <- next already updated *)
		ASSERT (Files.Length (Files.Base (rider)) + imageBase = next);
		ASSERT (next MOD 16 = 8);
		img.code := next; num := m.codeSize; arrHdr.len := num;
		keepcode := next+ArrayDescSize;
		Dump (next+ArrayDescSize, "code");
		Dump (m.codeBase, "codeadr");
		ASSERT (m.codeBase = next + ArrayDescSize);
		Files.WriteBytes (rider, arrHdr, ArrayDescSize);	(* hidden header *)
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = m.codeBase);
		Files.WriteBytes (rider, m.code^, num);
		InsertPad (rider, next, TagSize+ArrayDescSize+num, 16);
		
		(* TDescs *)
		Files.WriteLInt (rider, tag);	(* <- next already updated *)
		ASSERT (Files.Length (Files.Base (rider)) + imageBase = next);
		ASSERT (next MOD 16 = 8);
		img.tdescs := next; num := m.nofTds; arrHdr.len := num;
		Dump (next+ArrayDescSize, "tdescs");
		Files.WriteBytes (rider, arrHdr, ArrayDescSize);	(* hidden header *)
		i := 0;
		WHILE i < num DO
			Files.WriteLInt (rider, m.tdescs[i].tdAdr); INC (i)
		END;
		InsertPad (rider, next, TagSize+ArrayDescSize+num*4, 16);

		(* Refs *)
		Files.WriteLInt (rider, tag);	(* <- next already updated *)
		ASSERT (Files.Length (Files.Base (rider)) + imageBase = next);
		ASSERT (next MOD 16 = 8);
		img.refs := next; num := m.refSize; arrHdr.len := num;
		Dump (next+ArrayDescSize, "refs");
		Dump (m.refBase, "refBase");
		ASSERT (m.refBase = next + ArrayDescSize);
		Files.WriteBytes (rider, arrHdr, ArrayDescSize);	(* hidden header *)
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = m.refBase);
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = next + ArrayDescSize);
		IF num > 0 THEN Files.WriteBytes (rider, m.refs^, num) END;
		InsertPad (rider, next, TagSize+ArrayDescSize+num, 16);
		
		(* import *)
		Files.WriteLInt (rider, tag);
		ASSERT (next MOD 16 = 8);
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = next);
		img.import := next; num := DefMaxImport; arrHdr.len := num; img.nofimp := m.nofimp;
		Dump (next+ArrayDescSize, "import");
		Files.WriteBytes (rider, arrHdr, ArrayDescSize);	(* hidden header *)
		FOR i := 0 TO num-1 DO Files.WriteLInt (rider, 0) END;
		InsertPad (rider, next, TagSize+ArrayDescSize+num*4, 16);

		(* struct *)
		Files.WriteLInt (rider, tag);
		ASSERT (next MOD 16 = 8);
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = next);
		img.struct := next; num := DefMaxStruct; arrHdr.len := num; img.nofstrc := m.nofstrc;
		Dump (next+ArrayDescSize, "struct");
		Files.WriteBytes (rider, arrHdr, ArrayDescSize);	(* hidden header *)
		FOR i := 0 TO num-1 DO Files.WriteLInt (rider, 0) END;
		InsertPad (rider, next, TagSize+ArrayDescSize+num*4, 16);

		(* reimp *)
		Files.WriteLInt (rider, tag);
		ASSERT (next MOD 16 = 8);
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = next);
		img.reimp := next; num := DefMaxReimp; arrHdr.len := num; img.nofreimp := m.nofreimp;
		Dump (next+ArrayDescSize, "reimp");
		Files.WriteBytes (rider, arrHdr, ArrayDescSize);	(* hidden header *)
		FOR i := 0 TO num-1 DO Files.WriteLInt (rider, 0) END;
		(*InsertPad (rider, next, 20+num*4, 16);*)
		INC (next, TagSize+ArrayDescSize + num*4);

		
		(* export *)
		(* align to word boundary - 4 *)
		Dump (next, "padding");
		Dump (Files.Length(Files.Base(rider)) + imageBase, "effective");
		Files.WriteBytes (rider, padding, m.expPadding+4);		(* <- +4 compensate the tag *)
		INC (next, m.expPadding+4);
		
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = next - 4);
		ASSERT (next MOD 32 = 0);
		Dump (Files.Length(Files.Base(rider)) + imageBase, "effective");
		Dump (m.expAdr, "expAdr");
		ASSERT(SysFix[expDescSF].adr # 0);
		DumpExport (rider, m.export, next, S.VAL (LONGINT, S.VAL (SET, SysFix[expDescSF].adr) + {1}) (* a bit *));
		img.export.fp := m.export.fp; img.export.adr := m.export.adr;
		img.export.nofExp := m.export.nofExp;
		IF img.export.nofExp = 0 THEN img.export.dsc := 0 ELSE img.export.dsc := m.export.dsc[0].Adr END;
		
		(* align to word boundary - 4 *)
		(* tdescs *)
		Dump (next, "tds");
		Dump (m.typeTableAdr, "m.typeTableAdr");
		Dump (Files.Length(Files.Base(rider)) + imageBase, "effective");
		DEC (next, 4);
		ASSERT (next MOD Boundary = 28);
		ASSERT (m.typeTableAdr = next);
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = next );
		DumpTypes (rider, m, next);
		
		(* Module Descr *)
		Dump (next, "mdesc");
		Dump (m.modDescAdr, "desc Adr");
		ASSERT (next MOD Boundary = 28);
		ASSERT (next = m.modDescAdr - 4);
		ASSERT(SysFix[modDescSF].adr # 0);
		Files.WriteLInt (rider, SysFix[modDescSF].adr);
		ASSERT (Files.Length(Files.Base(rider)) + imageBase = m.modDescAdr (*+4*));
		Files.WriteBytes (rider, img^, moduleDescSize - mDescPadSize - 4);
		Files.WriteBytes (rider, padding, mDescPadSize);
		INC (next, moduleDescSize);
		ASSERT (m.imageSize +m.base = next);
		LogStr ("--------- END "); LogStr (m.name); LogHex(keepbase); LogHex(keepsb); 
		LogHex(keepcode); LogHex(next); LogLn;
		m := m.link
	END;
END DumpModules;

(* ---------------------------------------------------------- *)
PROCEDURE BuildImage (fileName: ARRAY OF CHAR; entryPoint, imageBase: LONGINT);
VAR
	OutputFile: Files.File;
	rider: Files.Rider;
BEGIN
	ASSERT (SysFix[modDescSF].adr # 0);
	ASSERT (SysFix[listSF].adr # 0);
	LogStr ("Building image : ");
	LogStr (fileName); LogStr ("  "); LogLn;
	LogHex (imageBase); LogStr (" image start, 28+32 bytes for alignment and header"); LogLn; LogLn;
	OutputFile := Files.New (fileName);
	Files.Set (rider, OutputFile, 0);
	Files.WriteBytes (rider, padding, 28+32);	(* for Oberon GC aligment & header *)
	(* modules *)
	DumpModules (rider);
	(* calls to module init procedures *)
	DumpInitCalls (rider, entryPoint);	(* entryPoint VAR *)
	PatchHeader (OutputFile, imageBase, entryPoint, Files.Length (OutputFile));
	Files.Register (OutputFile);
	Texts.Write(W, " ");
	Texts.WriteInt(W, Files.Length (OutputFile), 0); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf);
	LogStr ("new is "); LogStr (SysFix[newSF].module); LogStr ("."); LogStr (SysFix[newSF].command); LogHex (SysFix[newSF].adr); LogLn;
	LogStr ("sysnew is "); LogStr (SysFix[sysnewSF].module); LogStr ("."); LogStr (SysFix[sysnewSF].command); LogHex (SysFix[sysnewSF].adr); LogLn;
	LogStr ("newarr is "); LogStr (SysFix[newarrSF].module); LogStr ("."); LogStr (SysFix[newarrSF].command); LogHex (SysFix[newarrSF].adr); LogLn;
	LogStr ("list is "); LogStr (SysFix[listSF].module); LogStr ("."); LogStr (SysFix[listSF].command); LogHex (SysFix[listSF].adr); LogLn;
	LogStr ("modDesc is "); LogStr (SysFix[modDescSF].module); LogStr ("."); LogStr (SysFix[modDescSF].command); LogHex (SysFix[modDescSF].adr); LogLn;
	LogStr ("expDesc is "); LogStr (SysFix[expDescSF].module); LogStr ("."); LogStr (SysFix[expDescSF].command); LogHex (SysFix[expDescSF].adr); LogLn;
(*
	LogStr ("HeapCopyArr is "); LogStr (SysFix[copyarraySF].module); LogStr ("."); LogStr (SysFix[copyarraySF].command); LogHex (SysFix[modDescSF].adr); LogLn;
	LogStr ("NewSysArr is "); LogStr (SysFix[newsysarrSF].module); LogStr ("."); LogStr (SysFix[newsysarrSF].command); LogHex (SysFix[expDescSF].adr); LogLn;
*)
END BuildImage;

PROCEDURE InitSysFix(i: LONGINT;  name, module, command: ARRAY OF CHAR);
BEGIN
	COPY(name, SysFix[i].name);
	COPY(module, SysFix[i].module);
	COPY(command, SysFix[i].command);
	SysFix[i].adr := 0
END InitSysFix;

(*-----------------------------------------------------------*)
PROCEDURE Initialise;
VAR i: LONGINT;
BEGIN
	objectList := NIL; includeRefs := TRUE; protObj := NIL; res := done;
	FOR i := 0 TO MaxSF-1 DO SysFix[i].module := ""; SysFix[i].command := ""; SysFix[i].adr := 0 END;
	InitSysFix(newSF, "new", "Kernel", "NewRec");
	InitSysFix(sysnewSF, "sysnew", "Kernel", "NewSys");
	InitSysFix(newarrSF, "newarr", "Kernel", "NewArr");
	InitSysFix(StartSF, "start", "", "");
	InitSysFix(PassivateSF, "passivate", "", "");
	InitSysFix(ActivateSF, "activate", "", "");
	InitSysFix(LockSF, "lock", "", "");
	InitSysFix(UnlockSF, "unlock", "", "");
	InitSysFix(CurProcSF, "", "", "");
	InitSysFix(commandSF, "command", "", "");
	InitSysFix(listSF, "list", "Kernel", "modules");
	InitSysFix(modDescSF, "mdesc", "Kernel", "ModuleDesc");
	InitSysFix(expDescSF, "expdesc", "Kernel", "ExportDesc");
	InitSysFix(objectSF, "", "", "");

	nofEntryPoints := 0;
	moduleDescSize := SIZE (DumpModuleDesc)+4;	(* 4 = size of pointer block tag *)
	mDescPadSize := Align (moduleDescSize, Boundary)-moduleDescSize;
	INC(moduleDescSize, mDescPadSize);
	initPointList := NIL;
	FOR i := 0 TO PaddingSize-1 DO
		padding[i] := 0
	END
END Initialise;

PROCEDURE Link*;
VAR
	outputFile, logFile, tmp: String;
	base, i: LONGINT;
	S: Texts.Scanner;
	object: Module;
BEGIN
	Texts.WriteString(W, " linking ");
	Texts.Append(Oberon.Log, W.buf);
	Initialise;
	imageSize := 0; imageBase :=-1;
	Texts.OpenScanner (S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan (S);
	(* Output filename *)
	IF (S.class = Texts.Name) THEN
		COPY (S.s, outputFile);
		Texts.Scan (S);
		Texts.WriteString(W, outputFile); Texts.Write(W, " ");
		Texts.Append(Oberon.Log, W.buf);
		Concat (outputFile, ".Link", logFile);
		LogOpen (logFile)
	ELSE
		Texts.WriteString(W, " Couldn't read output file name");
		Texts.Append(Oberon.Log, W.buf);
		RETURN
	END;
	(* Read options, if any *)
	WHILE (S.class = Texts.Char) & (S.c = Oberon.OptionChar) DO
		Texts.Scan (S);
		IF (S.class = Texts.Name) & (S.s # "integrate") THEN
			IF (S.s = "refs") THEN
				includeRefs := TRUE; Texts.Scan (S)
			ELSE
				i := 0;
				WHILE (S.s # SysFix[i].name) & (i < MaxSF) DO INC (i) END;
				IF i = MaxSF THEN
					tmp := "Unknown option on command line \"; Concat (tmp, S.s, tmp); Halt (tmp)
				ELSE
					Texts.Scan (S);
					IF S.class = Texts.Name THEN
						ExtractNames (S.s, SysFix[i].module, SysFix[i].command);
						Texts.Scan (S)
					ELSE
						tmp := "Couldn't read '"; Concat (tmp, SysFix[i].name, tmp);
						Concat (tmp, "' parameter", tmp); Halt (tmp)
					END	(* IF *)
				END
			END	(* IF *)
		ELSIF (S.s # "integrate") THEN
			Halt ("Wrong symbol after '/'")
		END	(* IF *)
	END	(* WHILE *);
	IF (S.class = Texts.Name) & (S.s = "integrate") THEN
		Texts.Scan (S);
		(* Link base address *)
		IF (S.class = Texts.Int) THEN
			imageBase := S.i;
			Texts.Scan (S);
			IF (imageBase MOD PageSize # 0) THEN
				Halt ("Image base must be a multiple of machine memory page size")
			END
		ELSE
			Halt ("Couldn't read 'integrate' parameter (link base)")
		END;
		base := imageBase+28+32;	(* for Oberon GC aligment & header *)
		WHILE (S.class = Texts.Name) DO
			(* load Modules in Memory *)
			Load (object, S.s, base);
			Texts.Scan (S)
		END;
	END;
	IF ~((S.class = Texts.Char) & (S.c = "~") OR S.eot) THEN
		Halt ("Error in parameter list.")
	END;
	IF SysFix[commandSF].module # "" THEN
		object := FindModule (SysFix[commandSF].module);
		IF object # NIL THEN
			i := 0;
			WHILE (i < object.nofCmds) & (object.cmds[i].name # SysFix[commandSF].command) DO INC (i) END;
			IF i < object.nofCmds THEN AddInitPoint (object.cmds[i].adr, NIL)
			ELSE Halt ("Procedure in 'command' option not found")
			END
		ELSE Halt ("Module in 'command' option not included in image")
		END
	END;
	BuildImage (outputFile, base, imageBase);
	LogClose;
	objectList := NIL; initPointList := NIL	(* so that memory can be reclaimed by GC *)
END Link;

PROCEDURE ReadHex(VAR R: Texts.Reader;  VAR x: LONGINT);
VAR ch: CHAR;
BEGIN
	REPEAT Texts.Read(R, ch) UNTIL R.eot OR (ch # " ");
	x := 0;
	LOOP
		IF R.eot THEN EXIT END;
		IF (ch >= "0") & (ch <= "9") THEN
			x := 16*x + (ORD(ch)-ORD("0"))
		ELSIF (ch >= "a") & (ch <= "f") THEN
			x := 16*x + (ORD(ch)-ORD("a")+10)
		ELSIF (ch >= "A") & (ch <= "F") THEN
			x := 16*x + (ORD(ch)-ORD("A")+10)
		ELSE
			EXIT
		END;
		Texts.Read(R, ch)
	END
END ReadHex;

PROCEDURE Find*;	(* logname ^ (selection is hex EIP) *)
VAR
	adr, sb, base, beg, end, time: LONGINT;
	S: Texts.Scanner;  T: Texts.Text;  R: Texts.Reader;
	name: ARRAY 32 OF CHAR;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(S);
	IF S.class = Texts.Name THEN
		COPY(S.s, name);  Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			Oberon.GetSelection(T, beg, end, time);
			IF time >= 0 THEN
				Texts.OpenReader(R, T, beg);  ReadHex(R, adr);
				NEW(T);  Texts.Open(T, name);
				IF T.len # 0 THEN
					Texts.OpenScanner(S, T, 0);
					WHILE ~S.eot DO
						Texts.Scan(S);
						IF (S.class = Texts.Name) & (S.s = "END") THEN
								(* "END xxxx yyyyyyyyH zzzzzzzzH" *)
							Texts.Scan(S);  COPY(S.s, name);
							Texts.Scan(S);
							IF S.class = Texts.Int THEN
								base := S.i;  Texts.Scan(S);
								sb := S.i;  Texts.Scan(S);
								beg := S.i;  Texts.Scan(S);
								end := S.i;
								IF (adr >= beg) & (adr < end) THEN
									Texts.WriteString(W, name);  Texts.WriteString(W, ".Mod");
									Texts.WriteString(W, "  PC = ");  Texts.WriteInt(W, adr-beg, 1); Texts.WriteLn(W);
									Texts.Append(Oberon.Log, W.buf);
									RETURN
								ELSIF (adr >= base) & (adr < end) THEN
									Texts.WriteString(W, name);  Texts.WriteString(W, ".Mod");
									Texts.WriteString(W, "  PC = SB + ");  Texts.WriteInt(W, adr-sb, 1);  Texts.WriteLn(W);
									Texts.Append(Oberon.Log, W.buf);
									RETURN
								END
							END
						END
					END
				END
			END
		END
	END
END Find;

PROCEDURE SetObjSuffix*;	(** usage: BootLinker.SetObjSuffix <suffix including dot> *)
VAR S: Texts.Scanner;  t: Texts.Text; pos, end, time: LONGINT;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "^") THEN
		Oberon.GetSelection(t, pos, end, time);
		IF time >= 0 THEN
			Texts.OpenScanner(S, t, pos);  Texts.Scan(S)
		END
	END;
	IF (S.class = Texts.Char) & (S.c = "~") THEN	(* default *)
		S.class := Texts.Name;  COPY(Modules.extension, S.s)
	END;
	IF S.class = Texts.Name THEN
		COPY(S.s, extension);
		Texts.WriteString(W, "Object file suffix set to ");
		Texts.WriteString(W, extension)
	ELSE
		Texts.WriteString(W, "Parameter not found")
	END;
	Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
END SetObjSuffix;

BEGIN
	Texts.OpenWriter(W);
	COPY(Modules.extension, extension);
	Texts.WriteString(W, "Static BootLinker for OM Object Files / prk"); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf)
END BootLinker.
