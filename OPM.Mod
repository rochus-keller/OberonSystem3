(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE OPM;	(** non-portable *)

(* Machine dependent constants needed before code generation *)
(* Host interface *)
(* RC, NM, pjm, prk *)

	IMPORT
		Fonts, Texts, Oberon, Files, SYSTEM;

	CONST (* i386 *)

		(* basic type sizes *)
		ByteSize* = 1;	(* SYSTEM.BYTE *)
		CharSize* = 1;	(* CHAR *)
		BoolSize* = 1;	(* BOOLEAN *)
		SetSize* = 4;	(* SET *)
		SIntSize* = 1;	(* SHORTINT *)
		IntSize* = 2;	(* INTEGER *)
		LIntSize* = 4;	(* LONGINT *)
		HIntSize* = 8;	(* HUGEINT *)
		RealSize* = 4;	(* REAL *)
		LRealSize* = 8;	(* LONGREAL *)
		ProcSize* = 4;	(* PROCEDURE type *)
		PointerSize* = 4;	(* POINTER type *)

		(* value of constant NIL *)
		nilval* = 0;
		
		(* target machine minimum values of basic types expressed in host machine format: *)
		MinSInt* = -80H;
		MinInt* = -8000H;
		MinLInt* =  80000000H;	(* i386: -2147483648*)
		MinRealPat = 0FF7FFFFFH;	(* most  negative, 32-bit pattern *)
		MinLRealPatL = 0FFFFFFFFH;	(* most  negative, lower 32-bit pattern *)
		MinLRealPatH = 0FFEFFFFFH;	(* most  negative, higher 32-bit pattern *)
		
		(* target machine maximum values of basic types expressed in host machine format: *)
		MaxSInt* = 7FH;
		MaxInt* = 7FFFH;
		MaxLInt* = 7FFFFFFFH;	(* i386: 2147483647*)
		MaxSet* = 31;	(* must be >= 15, else the bootstraped compiler cannot run (IN-tests) *)
		MaxRealPat = 7F7FFFFFH;	(* most positive, 32-bit pattern *)
		MaxLRealPatL = 0FFFFFFFFH;	(* most positive, lower 32-bit pattern *)
		MaxLRealPatH = 7FEFFFFFH;		(* most positive, higher 32-bit pattern *)
		
		(* maximal index value for array declaration: *)
		MaxIndex* = MaxLInt;

		(* parametrization of numeric scanner: *)
		MaxHDig* = 8;	(* maximal hexadecimal longint length *)
		MaxRExp* = 38;	(* maximal real exponent *)
		MaxLExp* = 308;	(* maximal longreal exponent *)
		
		(* inclusive range of parameter of standard procedure HALT: *)
		MinHaltNr* = 20;
		MaxHaltNr* = MAX(LONGINT);

		(* inclusive range of register number of procedures SYSTEM.GETREG and SYSTEM.PUTREG: *)
		MinRegNr* = 0;	(* interpretation is left to the back-end, e.g. for i386: *)
		MaxRegNr* = 31;	(* F0-F7 if second parameter is REAL or LONGREAL, R0-R7 else *)
		
		(* maximal value of flag used to mark interface structures: *)
		MaxSysFlag* = 0;	(* i386: only 0 is valid, not used *)
		
		(* maximal condition value of parameter of SYSTEM.CC: *)
		MaxCC* = -1;	(* not implemented interpretation is left to the back-end *)
		
		(* initialization of linkadr field in ObjDesc, must be different from any valid link address: *)
		LANotAlloc* = -1;
		
		(* initialization of constant address, must be different from any valid constant address: *)
		ConstNotAlloc* = -1;	(* i386: only strings are allocated *)
		
		(* initialization of tdadr field in StrDesc, must be different from any valid address: *)
		TDAdrUndef* = -1;
		
		(* maximal number of cases in a case statement: *)
		MaxCases* = 128;
		
		(* maximal range of a case statement (higher label - lower label ~ jump table size): *)
		MaxCaseRange* = 512;

		(* whether field leaf of pointer variable p has to be set to FALSE, when NEW(p) or SYSTEM.NEW(p, n) is used: *)

		NEWusingAdr* = FALSE;

		(* mask for the TD associated with an object instance: mask away GC information *)
		TDMask* = 0 (*0FFFFFFF8H*);	(* set to 0 to disable masking *)

		(*Configuration -- temp *)
		OptimizeSelf* = TRUE;	(* if possible, make self pointer-based in methods *)
		WarnUnsafe* = FALSE;	(* generate warnings for "unsafe" language features *)

		(* special character (< " ") returned by procedure Get, if end of text reached *)
		Eot* = 0X;
		SetLen = MAX(SET)+1;
		NumErrors = (912+SetLen) DIV SetLen * SetLen;

		PathChar = "/";
		
		(** Compiler Options *)
		inxchk* = 0;	(** index check *)
		ovflchk* = 1;	(** overflow check *)
		typchk* = 3;	(** type checking *)
		ptrinit* = 5;	(** pointer initialization *)
		assert* = 6;	(** assert evaluation *)
		findpc* = 7;	(** find text position of breakpc *)
		systemchk* = 8;	(** prevent compilation of modules that import SYSTEM *) (* jm *)
		nofiles* = 9;	(** don't create any files (dVdW) *)
		newsf* = 10;	(** generation of new symbol file allowed *)
		extsf* = 11;	(** generation of extended symbol file allowed *)
		warning* = 12;	(** display warnings *)
		prefix* = 18;	(** X - retain filename prefix on .Sym & .Obj file (Native) *)
		oberon2* = 19; 	(** 2 - compile oberon-2 programs *)
		fullstackinit* = 20;	(** zero all the stack (only if ptrinit)*)
		oberon1* = 21;	(** compile oberon-1 programs *)
		trace* = 22;	(** trace procedure usage *)
		aos* = 23;	(** aos, different objfile *)
		traceprocs* = 24;	(** trace procedure calls *)	(* temp *)

		DefOpt* = {inxchk, typchk, ptrinit, fullstackinit, assert};
		
	VAR
		MinReal*, MaxReal*: REAL;
		MinLReal*, MaxLReal*: LONGREAL;
		noerr*: BOOLEAN;	(* no error found until now *)
		curpos*, errpos*: LONGINT;	(* character and error position in source file *)
		breakpos*: LONGINT;	(* set by Mark *)
		breakpc*: LONGINT;	(*set by OPV.Init*)
		errors: ARRAY NumErrors DIV SetLen OF SET;
		outputPath*: ARRAY 32 OF CHAR;	(* for reading and writing obj files. must include any trailing "/" or ":" *)
		outputPrefix*: ARRAY 32 OF CHAR;	(* for writing obj files (in addition to outputPath). *)
		options*: SET;
		errName*: ARRAY 32 OF CHAR;
		first: BOOLEAN;
		extension*: ARRAY 8 OF CHAR;	(** object file extension *)

	CONST
		OFtag = 0BBX;	(* object file tag *)
		OFnative = 0AFX;
		OFportable = 088X;
		OFaos = 01X;

	VAR
		LRealPat: RECORD L, H: LONGINT END ;
		lastpos, pat: LONGINT;	(* last position error in source file *)
		refpatch: LONGINT;	(* OM: last position error in source file *)
		inR: Texts.Reader;
		Log: Texts.Text;
		W: Texts.Writer;
		oldSymF, newSymF, ObjF, RefF, ModF: Files.Rider;
		RefFile, ObjFile, ModFile, oldSymFile, newSymFile: Files.File;
		
	PROCEDURE Init*(opt: SET; source: Texts.Reader; log: Texts.Text);
		VAR i: SHORTINT;
	BEGIN inR := source; Log := log; options := opt;
		noerr := TRUE; curpos := Texts.Pos(inR); errpos := curpos; lastpos := curpos-10;
		FOR i := 0 TO NumErrors DIV SetLen - 1 DO errors[i] := {} END;
		Oberon.Collect
	END Init;
	
	PROCEDURE Close*;
	BEGIN
		Files.Set(oldSymF, NIL, 0); Files.Set(newSymF, NIL, 0); Files.Set(ObjF, NIL, 0); Files.Set(RefF, NIL, 0);
		oldSymFile := NIL; newSymFile := NIL; ObjFile := NIL;  RefFile := NIL;
	END Close;
	
	PROCEDURE Get*(VAR ch: CHAR);	(* read next character from source text, Eot if no more *)
	BEGIN
		(* System3 get: skip embedded objects *)
		REPEAT
			Texts.Read(inR, ch); INC(curpos)
		UNTIL inR.eot OR ((inR.lib # NIL) & (inR.lib IS Fonts.Font))
	END Get;
	
	PROCEDURE MakeFileName(VAR path, prefix, modName, fileName: ARRAY OF CHAR; ext: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN	i:=0; ch:=path[0];
		WHILE	ch#0X	DO	fileName[i]:=ch; INC(i); ch:=path[i]	END;
(*
		IF (i # 0) & (path[i-1] # PathChar) & (path[i-1] # ":") THEN fileName[i] := PathChar; INC(i) END;
*)
		j := 0;  ch := prefix[0];
		WHILE ch # 0X DO fileName[i] := ch;  INC(i);  INC(j);  ch := prefix[j] END;
		j:=0; ch:=modName[0];
		WHILE	ch#0X	DO	fileName[i]:=ch; INC(i); INC(j); ch:=modName[j]	END;
		j := -1; REPEAT	INC(j); fileName[i] := ext[j]; INC(i)	UNTIL ext[j] = 0X
	END MakeFileName;

	(* ----- Fingerprint calculation ----- *)

	PROCEDURE FPrint*(VAR fp: LONGINT; val: LONGINT);
	BEGIN fp:=SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, SYSTEM.ROT(fp, 7)) / SYSTEM.VAL(SET, val))
	END FPrint;

	PROCEDURE FPrintSet*(VAR fp: LONGINT; set: SET);
	BEGIN FPrint(fp, SYSTEM.VAL(LONGINT, set))
	END FPrintSet;

	PROCEDURE FPrintReal*(VAR fp: LONGINT; real: REAL);
	BEGIN FPrint(fp, SYSTEM.VAL(LONGINT, real))
	END FPrintReal;

	PROCEDURE FPrintLReal*(VAR fp: LONGINT; lr: LONGREAL);
		VAR l, h: LONGINT;
	BEGIN
		SYSTEM.GET(SYSTEM.ADR(lr)+4, l); SYSTEM.GET(SYSTEM.ADR(lr), h);
		FPrint(fp, l); FPrint(fp, h);
	END FPrintLReal;
	
	(* ----- auxiliaries ----- *)

	PROCEDURE WString(VAR R: Files.Rider; VAR s: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN	i:=0; ch:=s[i];
		IF	ch=0X	THEN	Files.Write(R, 0X); RETURN	END;
		WHILE	(ch#0X) & (ch<7FX)	DO	INC(i); ch:=s[i]	END;
		IF	i>1	THEN	Files.WriteBytes(R, s, i-1)	END;
		IF	ch=0X	THEN	Files.Write(R, CHR(ORD(s[i-1])+80H))
		ELSE	
			IF	i>0	THEN	Files.Write(R, s[i-1])	END;
			Files.Write(R, 7FX); REPEAT	Files.Write(R, ch); INC(i); ch:=s[i]	UNTIL ch=0X;
			Files.Write(R, 0X)
		END
	END WString;

	(* ------------------------- Log Output ------------------------- *)
	
	PROCEDURE LogW*(ch: CHAR);
	BEGIN
		Texts.Write(W, ch); Texts.Append(Log, W.buf)
	END LogW;
	
	PROCEDURE LogWStr*(s: ARRAY OF CHAR);
	BEGIN
		Texts.WriteString(W, s); Texts.Append(Log, W.buf)
	END LogWStr;
	
	PROCEDURE LogWNum*(i, len: LONGINT);
	BEGIN
		Texts.WriteInt(W, i, len); Texts.Append(Log, W.buf)
	END LogWNum;

	PROCEDURE LogWHex*(i: LONGINT);
	BEGIN	Texts.WriteHex(W, i); Texts.Write(W, "H"); Texts.Append(Log, W.buf)
	END LogWHex;

	PROCEDURE LogWLn*;
	BEGIN
		Texts.WriteLn(W); Texts.Append(Log, W.buf)
	END LogWLn;
	
	PROCEDURE ErrorMsg(n: INTEGER);
	VAR s: Texts.Scanner; ch: CHAR;  e: ARRAY 127 OF CHAR;  i: SHORTINT;
	BEGIN
		IF (n >= NumErrors) OR ~((n MOD SetLen) IN errors[n DIV SetLen]) THEN
			IF (n < NumErrors) THEN INCL(errors[n DIV SetLen], n MOD SetLen) END;
			Oberon.OpenScanner(s, "OP2.Errors");
			IF s.class # Texts.Inval THEN
				REPEAT Texts.Scan(s) UNTIL s.eot OR (s.class = Texts.Int) & (s.i = 0);
				WHILE ~s.eot & ((s.class # Texts.Int) OR (s.i # n)) DO Texts.Scan(s) END;
				IF ~s.eot THEN Texts.Read(s, ch);  Texts.Write(W, 9X);  i := 0;
					WHILE ~s.eot & (ch # 0DX) DO e[i] := ch; INC(i); Texts.Read(s, ch) END;
					e[i] := 0X;  LogWStr(e)
				END
			ELSE
				IF first THEN
					LogWStr("Oberon.Text - OP2.Errors not found");  LogWLn;
					first := FALSE
				END
			END
		END
	END ErrorMsg;
	
	PROCEDURE Mark*(n: INTEGER; pos: LONGINT);
	BEGIN
		IF n >= 0 THEN
			noerr := FALSE;
			IF (pos < lastpos) OR (lastpos + 9 < pos) OR (n>=450) & (n<=460) OR (n=155) THEN lastpos := pos;
				LogWLn; LogW(9X); LogW(9X);
				IF (n<450) OR (n>460) THEN
					LogWStr("pos"); LogWNum(pos, 7);
					IF n = 255 THEN LogWStr("  pc "); LogWHex(breakpc); breakpos := pos
					ELSIF n = 254 THEN LogWStr("  pc not found")
					ELSE LogWStr("  err"); LogWNum(n, 4); ErrorMsg(n)
					END
				ELSE LogWStr(errName);
					IF	n=450	THEN	LogWStr(" is no longer visible")
					ELSIF	n=451	THEN	LogWStr(" is new")
					ELSIF	n=452	THEN	LogWStr(" is redefined")
					END
				END
			END
		ELSIF warning IN options THEN
			LogWLn; LogW(9X); LogW(9X); LogWStr("pos"); LogWNum(pos, 7); LogWStr("  warning"); LogWNum(-n, 4);
			ErrorMsg(-n)
		END
	END Mark;
	
	PROCEDURE err*(n: INTEGER);
	BEGIN Mark(n, errpos)
	END err;

	(* ------------------------- Write Symbol File ------------------------- *)
	
	PROCEDURE SymW*(b: CHAR);
	BEGIN	Files.Write(newSymF, b)
	END SymW;

	PROCEDURE SymWCh*(ch: CHAR);
	BEGIN Files.Write(newSymF, ch)
	END SymWCh;

	PROCEDURE SymWTag*(k: INTEGER);
	BEGIN Files.Write(newSymF, CHR(k))
	END SymWTag;

	PROCEDURE SymWInt*(k: LONGINT);
	BEGIN Files.WriteInt(newSymF, SHORT(k))
	END SymWInt;

	PROCEDURE SymWLInt*(k: LONGINT);
	BEGIN Files.WriteLInt(newSymF, k)
	END SymWLInt;

	PROCEDURE SymWNum*(i: LONGINT);
	BEGIN	Files.WriteNum(newSymF, i)
	END SymWNum;

	PROCEDURE SymWPos*():LONGINT;
	BEGIN RETURN Files.Pos(newSymF)+Files.Pos(ModF);
	END SymWPos;

	PROCEDURE SymWMod*(VAR name: ARRAY OF CHAR);
	BEGIN  WString(ModF, name)
	END SymWMod;

	PROCEDURE SymWSet*(s: SET);
	BEGIN	Files.WriteNum(newSymF, SYSTEM.VAL(LONGINT, s))
	END SymWSet;

	PROCEDURE SymWReal*(r: REAL);
	BEGIN Files.WriteReal(newSymF, r)
	END SymWReal;
	
	PROCEDURE SymWLReal*(lr: LONGREAL);
	BEGIN Files.WriteLReal(newSymF, lr)
	END SymWLReal;
	
	PROCEDURE SymWString*(VAR s: ARRAY OF CHAR);
	BEGIN	WString(newSymF, s)
	END SymWString;

	(* ------------------------- Write Reference & Object Files ------------------------- *)

	PROCEDURE RefW*(ch: CHAR);
	BEGIN Files.Write(RefF, ch)
	END RefW;

	PROCEDURE RefWNum* (i: LONGINT);
	BEGIN
		Files.WriteNum (RefF, i)
	END RefWNum;

	PROCEDURE ObjW*(ch: CHAR);
	BEGIN Files.Write(ObjF, ch)
	END ObjW;

	PROCEDURE ObjWInt*(i: INTEGER);
	BEGIN Files.WriteInt(ObjF, i)
	END ObjWInt;

	PROCEDURE ObjWLInt*(i: LONGINT);
	BEGIN Files.WriteLInt(ObjF, i)
	END ObjWLInt;

	PROCEDURE ObjWBytes*(VAR bytes: ARRAY OF SYSTEM.BYTE; n: LONGINT);
	BEGIN Files.WriteBytes(ObjF, bytes, n)
	END ObjWBytes;

	PROCEDURE ObjWNum*(i: LONGINT);
	BEGIN	Files.WriteNum(ObjF, i)
	END ObjWNum;

	PROCEDURE ObjWString*(VAR s: ARRAY OF CHAR);
	BEGIN	WString(ObjF, s)
	END ObjWString;

	PROCEDURE ObjAllocInt*(): LONGINT;
		VAR pos: LONGINT;
	BEGIN	pos:=Files.Pos(ObjF); Files.WriteInt(ObjF, SYSTEM.VAL(INTEGER, 0));
		RETURN pos;
	END ObjAllocInt;

	PROCEDURE ObjFillInt*(pos: LONGINT; int: INTEGER);
		VAR savepos: LONGINT;
	BEGIN	savepos:=Files.Pos(ObjF);
		Files.Set(ObjF, ObjFile, pos); Files.WriteBytes(ObjF, int, 2);
		Files.Set(ObjF, ObjFile, savepos);
	END ObjFillInt;

	(* ----- files ----- *)

	PROCEDURE OpenSym*(VAR R: Files.Rider; VAR name: ARRAY OF CHAR; self: BOOLEAN; VAR done: BOOLEAN);
		VAR  fileName: ARRAY 512 OF CHAR; ch, ch1: CHAR; symSize: LONGINT; F: Files.File; empty: ARRAY 1 OF CHAR;
	BEGIN
		empty[0] := 0X;
		MakeFileName(outputPath, empty, name, fileName, extension); 
		done := FALSE;
		F := Files.Old(fileName);
		IF F # NIL THEN done := TRUE; Files.Set(R, F, 0);
			Files.Read(R, ch);
			IF ch=OFtag THEN Files.Read(R, ch1); Files.ReadNum(R, symSize);
				IF ((aos IN options) & (ch1 # OFaos)) OR (~(aos IN options) & (ch1 # OFnative)) THEN
					err(151); done := FALSE
				END
			ELSE (* eb, 30.11.95 err(511); *) done := FALSE
			END
		END
	END OpenSym;
	
	PROCEDURE Begin*(VAR modName: ARRAY OF CHAR);
		VAR ObjFName: ARRAY 512 OF CHAR;
	BEGIN
		MakeFileName(outputPath, outputPrefix, modName, ObjFName, extension);
		ObjFile:=Files.New(ObjFName);
		IF ObjFile = NIL THEN  err(153);  RETURN  END;
		Files.Set(ObjF, ObjFile, 0); Files.Write(ObjF, OFtag);
		ModFile:=Files.New(""); Files.Set(ModF, ModFile, 0); 
		newSymFile:=Files.New(""); Files.Set(newSymF, newSymFile, 0);
		RefFile := Files.New(""); Files.Set(RefF, RefFile, 0);
		IF aos IN options THEN
			Files.Write(ObjF, OFaos)
		ELSE
			Files.Write(ObjF, OFnative);
		END;
	END Begin;

	PROCEDURE Commit(F: Files.File);
		VAR ch: CHAR; R: Files.Rider;
	BEGIN	Files.Set(R, F, 0); Files.Read(R, ch);
		WHILE	~R.eof	DO	Files.Write(ObjF, ch); Files.Read(R, ch)	END
	END Commit;

	PROCEDURE EndSym*;
		VAR sfsize: LONGINT;  
	BEGIN	Files.Write(ModF, 0X); 
		sfsize:=Files.Length(newSymFile)+Files.Length(ModFile); Files.WriteNum(ObjF, sfsize);
		Commit(ModFile); Commit(newSymFile);
		refpatch:=Files.Pos(ObjF); ObjWInt(0); ObjWInt(0)
	END EndSym;

	PROCEDURE EndObj*;
		VAR refsize: LONGINT;
	BEGIN
		refsize:=Files.Length(RefFile); ObjW(8DX); Commit(RefFile); 
		Files.Set(ObjF, ObjFile, refpatch); ObjWBytes(refsize, 4); 
		Files.Register(ObjFile); 
	END EndObj;
	
	PROCEDURE CloseObj*;
		VAR refsize: LONGINT; ch: CHAR; ref: Files.Rider;
	BEGIN (*ref block*)
		refsize:=Files.Length(RefFile);
		Files.Set(ref, RefFile, 0); Files.Read(ref, ch); WHILE ~ref.eof DO ObjW(ch); Files.Read(ref, ch) END;
		Files.Set(ObjF, ObjFile, refpatch); ObjWBytes(refsize, 4);
		Files.Register(ObjFile)
	END CloseObj;

BEGIN
	pat := MinRealPat; SYSTEM.MOVE(SYSTEM.ADR(pat), SYSTEM.ADR(MinReal), 4);	(*i386: -3.40282346E38*)
	pat := MaxRealPat; SYSTEM.MOVE(SYSTEM.ADR(pat), SYSTEM.ADR(MaxReal), 4);	(*i386: 3.40282346E38*)
	LRealPat.L := MinLRealPatL; LRealPat.H := MinLRealPatH;
	SYSTEM.MOVE(SYSTEM.ADR(LRealPat), SYSTEM.ADR(MinLReal), 8);	(*i386: -1.7976931348623157D308*)
	LRealPat.L := MaxLRealPatL; LRealPat.H := MaxLRealPatH;
	SYSTEM.MOVE(SYSTEM.ADR(LRealPat), SYSTEM.ADR(MaxLReal), 8);	(*i386: 1.7976931348623157D308*)
	Texts.OpenWriter(W); Log := Oberon.Log;
	outputPath := ""; outputPrefix := "";	(* extension is initialized in Compiler *)
	first := TRUE
END OPM.
