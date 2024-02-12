(*
	Juice(TM), Version 1.1

	Copyright (c) 1996-1997 Regents of the University of California. 
	All rights reserved.

	This software was developed as part of the Juice project by the research 
	group of Prof. Dr. M. Franz at the University of California, Irvine.
	http://www.ics.uci.edu/~juice

	Redistribution and use in source and binary forms are permitted
	provided that:
	
	(a)	the above copyright notice and this paragraph are duplicated 
			in all such forms and provided that any documentation,
			advertising materials, and other materials related to such
			distribution and use acknowledge that the software was 
			developed by the University of California, Irvine.  
		
	(b)	all interface changes and all conversions of this software to other 
			platforms agree with style and content of Juice. In case of doubt
			juice-request@ics.uci.edu shall be asked for consent.
	
	The name of the University may not be used to endorse or promote products derived
	from this software without specific prior written permission.
	
	THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
	IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
	WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

	"Juice" is a trademark owned by the Regents of the University of California
*)

MODULE JOCM;	(* tk 8/5/96 *)

	(* Juice Compiler - Machine dependent constants needed before code generation *)

	IMPORT
		Texts, Oberon, Files, Fonts, FileDir, Registry, SYSTEM;

	CONST 
		(* basic type sizes *)
		ByteSize* = 1;	(* SYSTEM.BYTE *)
		CharSize* = 1;	(* CHAR *)
		BoolSize* = 1;	(* BOOLEAN *)
		SetSize* = 4;	(* SET *)
		SIntSize* = 1;	(* SHORTINT *)
		IntSize* = 2;	(* INTEGER *)
		LIntSize* = 4;	(* LONGINT *)
		RealSize* = 4;	(* REAL *)
		LRealSize* = 8;	(* LONGREAL *)
		ProcSize* = 8;	(* PROCEDURE type *)
		PointerSize* = 4;	(* POINTER type *)

		(* value of constant NIL *)
		nilval* = 0;
		
		(* target machine minimum values of basic types expressed in host machine format: *)
		MinSInt* = -80H;
		MinInt* = -8000H;
		MinLInt* =  80000000H;	(*-2147483648*)
		MinRealPat = 0FF7FFFFFH;	(* most  negative, 32-bit pattern *)
		MinLRealPatL = 0FFEFFFFFH;	(* most  negative, lower 32-bit pattern *)
		MinLRealPatH = 0FFFFFFFFH;	(* most  negative, higher 32-bit pattern *)
		
		(* target machine maximum values of basic types expressed in host machine format: *)
		MaxSInt* = 7FH;
		MaxInt* = 7FFFH;
		MaxLInt* = 7FFFFFFFH;	(*2147483647*)
		MaxSet* = 31;	(* must be >= 15, else the bootstraped compiler cannot run (IN-tests) *)
		MaxRealPat = 7F7FFFFFH;	(* most positive, 32-bit pattern *)
		MaxLRealPatL = 7FEFFFFFH;	(* most positive, lower 32-bit pattern *)
		MaxLRealPatH = 0FFFFFFFFH;		(* most positive, higher 32-bit pattern *)
		
		(* maximal index value for array declaration: *)
		MaxIndex* = MaxLInt;
		
		(* parametrization of numeric scanner: *)
		MaxHDig* = 8;	(* maximal hexadecimal longint length *)
		MaxRExp* = 38;	(* maximal real exponent *)
		MaxLExp* = 308;	(* maximal longreal exponent *)
		
		(* inclusive range of parameter of standard procedure HALT: *)
		MinHaltNr* = 20;
		MaxHaltNr* = 255;
		
		(* inclusive range of register number of procedures SYSTEM.GETREG and SYSTEM.PUTREG: *)
		MinRegNr* = 0;
		MaxRegNr* = 66;	
				
		(* maximal value of flag used to mark interface structures: *)
		MaxSysFlag* = 1;	
		
		(* maximal condition value of parameter of SYSTEM.CC: *)
		MaxCC* = -1;	
		
		(* initialization of linkadr field in ObjDesc, must be different from any valid link address: *)
		LANotAlloc* = -1;
		
		(* initialization of constant address, must be different from any valid constant address: *)
		ConstNotAlloc* = -1;	
		
		(* initialization of tdadr field in StrDesc, must be different from any valid address: *)
		TDAdrUndef* = -1;
		
		(* maximal number of cases in a case statement: *)
		MaxCases* = 128;
		
		(* maximal range of a case statement (higher label - lower label ~ jump table size): *)
		MaxCaseRange* = 512;
	
		(* whether field leaf of pointer variable p has to be set to FALSE, when NEW(p) or SYSTEM.NEW(p, n) is used: *)
		NEWusingAdr* = FALSE;
		
		(* special character (< " ") returned by procedure Get, if end of text reached *)
		Eot* = 0X;
		
		OFtag = 0BBX;	(* object file tag *)
		OFportable = 088X;	(* portable file tag *)

	VAR
		MinReal*, MaxReal*: REAL;
		MinLReal*, MaxLReal*: LONGREAL;
		noerr*: BOOLEAN;	(* no error found until now *)
		curpos*, errpos*: LONGINT;	(* character and error position in source file *)
		options: SET; 
		errName*: ARRAY 32 OF CHAR; 
		outputPath*: ARRAY 512 OF CHAR;	
						
	VAR
		LRealPat: RECORD L, H: LONGINT END ;
		lastpos, pat: LONGINT;	(* last position error in source file *)
		inR: Texts.Reader;
		Log: Texts.Text; W: Texts.Writer;
		RefF, ObjF, ModF, SymF: Files.Rider;
		RefFile, ObjFile, ModFile, SymFile: Files.File;
		ObjFName: ARRAY 512 OF CHAR;
		nopath: ARRAY 2 OF CHAR;

	PROCEDURE FlipSet* (s: SET): SET;
		VAR d: SET; i: INTEGER; proc: ARRAY 32 OF CHAR;
	BEGIN
		(* on intel based and MC680x0 base machines:
			RETURN s
		*)
		Registry.Get("SystemInfo", "Processor", proc);
		IF proc # "PowerPC" THEN RETURN s
		ELSE
			d := {}; i := 0;
			WHILE i < 32 DO IF i IN s THEN INCL(d, 31-i) END; INC(i) END;
			RETURN d
		END
	END FlipSet;

	PROCEDURE Init* (opt: SET; source: Texts.Reader; log: Texts.Text);
	BEGIN
		inR := source; Log := log; options := opt; 
		noerr := TRUE; curpos := Texts.Pos(inR); errpos := curpos; lastpos := curpos-10
	END Init;
	
	PROCEDURE Get* (VAR ch: CHAR);	(* read next character from source text, Eot if no more *)
	BEGIN	
		REPEAT
			Texts.Read(inR, ch); INC(curpos)
		UNTIL inR.eot OR ((inR.lib#NIL) & (inR.lib IS Fonts.Font))
	END Get;
		
	PROCEDURE SetFileName(VAR path, modName, fileName: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN
		i := 0; ch := path[0];
		WHILE ch # 0X DO fileName[i] := ch; INC(i); ch := path[i] END;
		IF (i # 0) & (path[i-1] # "/") THEN fileName[i] := FileDir.PathChar; INC(i) END;
		j := 0; ch := modName[0];
		WHILE ch # 0X DO fileName[i] := ch; INC(i); INC(j); ch := modName[j] END;
		fileName[i] := "."; fileName[i+1] := "O"; fileName[i+2] := "b"; fileName[i+3] := "j"; fileName[i+4] := 0X
	END SetFileName;
	
	(* ----- Fingerprint calculation ----- *)

	PROCEDURE FPrint*(VAR fp: LONGINT; val: LONGINT);
	BEGIN fp := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, SYSTEM.ROT(fp, 7)) / SYSTEM.VAL(SET, val))
	END FPrint;

	PROCEDURE FPrintSet*(VAR fp: LONGINT; set: SET);
	BEGIN FPrint(fp, SYSTEM.VAL(LONGINT, FlipSet(set)))
	END FPrintSet;

	PROCEDURE FPrintReal*(VAR fp: LONGINT; real: REAL);
	BEGIN FPrint(fp, SYSTEM.VAL(LONGINT, real))
	END FPrintReal;

	PROCEDURE FPrintLReal*(VAR fp: LONGINT; lr: LONGREAL);
		VAR l, h: LONGINT; proc: ARRAY 32 OF CHAR;
	BEGIN
		Registry.Get("SystemInfo", "Processor", proc);
		IF proc = "Intel" THEN
			SYSTEM.GET(SYSTEM.ADR(lr)+4, l); SYSTEM.GET(SYSTEM.ADR(lr), h);
		ELSE
			SYSTEM.GET(SYSTEM.ADR(lr), l); SYSTEM.GET(SYSTEM.ADR(lr)+4, h)
		END;
		FPrint(fp, l); FPrint(fp, h);
	END FPrintLReal;
	
	
	(* ----- auxiliaries ----- *)

	PROCEDURE WString(VAR R: Files.Rider; VAR s: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN	i := 0; ch := s[i];
		IF ch = 0X THEN Files.Write(R, 0X); RETURN END;
		WHILE (ch # 0X) & (ch < 7FX) DO INC(i); ch := s[i] END;
		IF i > 1 THEN Files.WriteBytes(R, s, i-1) END;
		IF ch = 0X THEN Files.Write(R, CHR(ORD(s[i-1])+80H))
		ELSE	
			IF i > 0 THEN Files.Write(R, s[i-1]) END;
			Files.Write(R, 7FX); REPEAT Files.Write(R, ch); INC(i); ch := s[i] UNTIL ch = 0X;
			Files.Write(R, 0X)
		END
	END WString;

	(* ------------------------- Log Output ------------------------- *)
	
	PROCEDURE LogW* (ch: CHAR);
	BEGIN	Texts.Write(W, ch); Texts.Append(Log, W.buf)
	END LogW;
	
	PROCEDURE LogWStr* (s: ARRAY OF CHAR);
	BEGIN	Texts.WriteString(W, s); Texts.Append(Log, W.buf)
	END LogWStr;
	
	PROCEDURE LogWNum* (i, len: LONGINT);
	BEGIN	Texts.WriteInt(W, i, len); Texts.Append(Log, W.buf)
	END LogWNum;

	PROCEDURE LogWLn*;
	BEGIN	Texts.WriteLn(W); Texts.Append(Log, W.buf)
	END LogWLn;
	
	PROCEDURE Mark (n: INTEGER; pos: LONGINT);
		CONST warning = 12;
	BEGIN
		IF n >= 0 THEN
			noerr := FALSE;
			IF (pos < lastpos) OR (lastpos + 9 < pos) OR (n>=450) & (n<=460) OR (n=155) THEN lastpos := pos;
				LogWLn; LogW(9X); LogW(9X);
				IF (n<450) OR (n>460) THEN
					LogWStr("pos"); LogWNum(pos, 6);
					LogWStr("  err"); LogWNum(n, 4)
				ELSE LogWStr(errName);
					IF	n=450	THEN	LogWStr(" is no longer visible")
					ELSIF	n=451	THEN	LogWStr(" is new")
					ELSIF	n=452	THEN	LogWStr(" is redefined")
					END
				END
			END
		ELSIF warning IN options THEN
			LogWLn; LogW(9X); LogW(9X); LogWStr("pos"); LogWNum(pos, 6); LogWStr("  warning"); LogWNum(-n, 4)
		END
	END Mark;
	
	PROCEDURE err* (n: INTEGER);
	BEGIN Mark(n, errpos)
	END err;
		
	(* ----- sym input ------ *)	
	
	PROCEDURE ReadString*(VAR R: Files.Rider; VAR string: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN i := 0;
		LOOP Files.Read(R, ch);
			IF ch = 0X THEN string[i] := 0X; RETURN
			ELSIF ch < 7FX THEN string[i]:=ch; INC(i)
			ELSIF ch > 7FX THEN string[i] := CHR(ORD(ch)-80H); string[i+1] := 0X; RETURN
			ELSE (* ch = 7FX *) EXIT END
		END;
		LOOP Files.Read(R, ch);
			IF ch = 0X THEN string[i]:=0X; RETURN
			ELSE string[i]:=ch; INC(i) END
		END
	END ReadString;
		
	(* ----- sym output ----- *)
	
	PROCEDURE SymW*(b: CHAR);
	BEGIN	Files.Write(SymF, b)
	END SymW;

	PROCEDURE SymWNum*(i: LONGINT);
	BEGIN	Files.WriteNum(SymF, i)
	END SymWNum;

	PROCEDURE SymWPos*():LONGINT;
	BEGIN RETURN Files.Pos(SymF)+Files.Pos(ModF);
	END SymWPos;

	PROCEDURE SymWMod*(VAR name: ARRAY OF CHAR);
	BEGIN  WString(ModF, name)
	END SymWMod;

	PROCEDURE SymWSet*(s: SET);
	BEGIN	Files.WriteNum(SymF, SYSTEM.VAL(LONGINT, FlipSet(s)))
	END SymWSet;

	PROCEDURE SymWReal*(VAR r: LONGREAL);
		VAR sr: REAL;
	BEGIN	sr := SHORT(r); Files.WriteReal(SymF, sr)
	END SymWReal;

	PROCEDURE SymWLReal*(VAR r: LONGREAL);
	BEGIN	Files.WriteLReal(SymF, r)
	END SymWLReal;

	PROCEDURE SymWString*(VAR s: ARRAY OF CHAR);
	BEGIN	WString(SymF, s)
	END SymWString;

	(* ----- obj output ----- *)

	PROCEDURE ObjWNum*(i: LONGINT);
	BEGIN	Files.WriteNum(ObjF, i)
	END ObjWNum;


	(* ----- files ----- *)
	
	PROCEDURE OpenSym*(VAR R: Files.Rider; VAR name: ARRAY OF CHAR; VAR done: BOOLEAN);
		VAR  fileName: ARRAY 512 OF CHAR; ch, ch1: CHAR; symSize: LONGINT; F: Files.File;
	BEGIN
		SetFileName(nopath, name, fileName); done := FALSE;
		F := Files.Old(fileName); 
		IF F # NIL THEN done := TRUE; Files.Set(R, F, 0);
			Files.Read(R, ch);
			IF ch = OFtag THEN Files.Read(R, ch1); Files.ReadNum(R, symSize)
			ELSE done := FALSE
			END
		END
	END OpenSym;

	PROCEDURE Begin*(VAR modName: ARRAY OF CHAR);
	BEGIN	SetFileName(outputPath, modName, ObjFName);
		ObjFile := Files.New(ObjFName); Files.Set(ObjF, ObjFile, 0); Files.Write(ObjF, OFtag);
		ModFile := Files.New(""); Files.Set(ModF, ModFile, 0); 
		SymFile := Files.New(""); Files.Set(SymF, SymFile, 0);
		RefFile := Files.New(""); Files.Set(RefF, RefFile, 0);
		Files.Write(ObjF, OFportable)
	END Begin;

	PROCEDURE Commit(F: Files.File);
		VAR ch: CHAR; R: Files.Rider;
	BEGIN	Files.Set(R, F, 0); Files.Read(R, ch);
		WHILE ~R.eof DO Files.Write(ObjF, ch); Files.Read(R, ch) END
	END Commit;

	PROCEDURE EndSym*;
		VAR sfsize: LONGINT;   
	BEGIN	Files.Write(ModF, 0X); 
		sfsize := Files.Length(SymFile)+Files.Length(ModFile); Files.WriteNum(ObjF, sfsize); 
		Commit(ModFile); Commit(SymFile);
		ModFile := Files.New(""); Files.Set(ModF, ModFile, 0); SymFile := Files.New(""); Files.Set(SymF, SymFile, 0)
	END EndSym;

	PROCEDURE EndObj*;
	BEGIN
		Files.Write(ModF, 0X); Commit(ModFile); Files.Write(SymF, 0X); Commit(SymFile);
		Files.Register(ObjFile)
	END EndObj;

BEGIN
	pat := MinRealPat; SYSTEM.MOVE(SYSTEM.ADR(pat), SYSTEM.ADR(MinReal), 4);	(*-3.40282346E38*)
	pat := MaxRealPat; SYSTEM.MOVE(SYSTEM.ADR(pat), SYSTEM.ADR(MaxReal), 4);	(*3.40282346E38*)
	LRealPat.L := MinLRealPatL; LRealPat.H := MinLRealPatH;
	SYSTEM.MOVE(SYSTEM.ADR(LRealPat), SYSTEM.ADR(MinLReal), 8);	(*-1.7976931348623157D308*)
	LRealPat.L := MaxLRealPatL; LRealPat.H := MaxLRealPatH;
	SYSTEM.MOVE(SYSTEM.ADR(LRealPat), SYSTEM.ADR(MaxLReal), 8);	(*1.7976931348623157D308*)
	Texts.OpenWriter(W); Log := Oberon.Log; 
END JOCM.
