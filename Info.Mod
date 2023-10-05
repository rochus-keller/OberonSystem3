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

MODULE Info;	(** non-portable *)	(* pmuller/dewe *)

IMPORT Kernel, Modules, Texts, TextFrames,
		Oberon, SYSTEM, Fonts, Files, Out, Objects;

	CONST
		cMaxDeRefLen = 16384;
		
	TYPE
		Handler = PROCEDURE (name: ARRAY OF CHAR);

	VAR
		W: Texts.Writer;
		T: Texts.Text;

PROCEDURE ShowModules*;
VAR
	T: Texts.Text;
	M, N: Modules.Module;
	size, i: LONGINT;
BEGIN
	T := TextFrames.Text("");
	M := Kernel.modules;
	WHILE M # NIL DO
		SYSTEM.GET(SYSTEM.VAL(LONGINT, M.entries)-24, size);
		Texts.WriteString(W, M.name);  Texts.Write(W, 9X);
		Texts.WriteInt(W, size, 1);  Texts.Write(W, 9X);
		Texts.WriteInt(W, M.refcnt, 1);  Texts.Write(W, 9X);
		Texts.WriteHex(W, SYSTEM.ADR(M.code[0]));
		Texts.WriteString(W, "H");  Texts.Write(W, 9X);
		FOR i := 0 TO LEN(M.imports)-1 DO
			N := M.imports[i];
			Texts.Write(W, " ");  Texts.WriteString(W, N.name)
		END;
		Texts.WriteLn(W);
		M := M.next
	END;
	Texts.Append(T, W.buf);
	Oberon.OpenText("Modules|System.Close System.Free Edit.Store", T, 384, 300)
END ShowModules;

(*
PROCEDURE ShowRanges*;
CONST Max = 100;  Cutoff = 32768;
TYPE T = RECORD start, end: LONGINT END;
VAR
	text: Texts.Text;
	m: Modules.Module;
	n, i, j: INTEGER;
	a: ARRAY Max OF T;
	pos, size: LONGINT;
BEGIN
	n := 0;
	text := TextFrames.Text("");
	m := Kernel.modules;
	WHILE m # NIL DO
		i := 0;  WHILE (i # n) & (SYSTEM.ADR(m.varEntries[0]) >= a[i].start) DO INC(i) END;
		FOR j := n-1 TO i BY -1 DO a[j+1] := a[j] END;
		size := SIZE(LONGINT) * (LEN(m.varEntries)+LEN(m.entries)+LEN(m.ptrTab)+
			LEN(m.tdescs)+LEN(m.imports)) + SIZE(Kernel.Cmd)*LEN(m.cmds) + 
			LEN(m.data)+LEN(m.code);
		IF (SYSTEM.VAL(LONGINT, m.refs) # 0) & (LEN(m.refs) # 0) THEN INC(size, LEN(m.refs)) END;
		a[i].start := SYSTEM.ADR(m.varEntries[0]);  a[i].end := SYSTEM.ADR(m.varEntries[0]) + size - 1;  INC(n);
		m := m.next
	END;
	FOR i := 0 TO n-1 DO
		Texts.WriteHex(W, a[i].start);  Texts.WriteHex(W, a[i].end);  Texts.WriteString(W, "  ");
		Texts.WriteInt(W, a[i].end - a[i].start + 1, 1);  Texts.WriteLn(W)
	END;
	Texts.Append(text, W.buf);  pos := text.len;  Texts.WriteLn(W);
	i := 0;
	WHILE i < n-1 DO
		IF a[i+1].start - a[i].end < Cutoff THEN
			a[i].end := a[i+1].end;
			FOR j := i+1 TO n-2 DO a[j] := a[j+1] END;
			DEC(n)
		ELSE
			INC(i)
		END
	END;
	FOR i := 0 TO n-1 DO
		Texts.WriteHex(W, a[i].start);  Texts.WriteHex(W, a[i].end);  Texts.WriteString(W, "  ");
		Texts.WriteInt(W, a[i].end - a[i].start + 1, 1);  Texts.WriteLn(W)
	END;
	Texts.Append(text, W.buf);
	Oberon.OpenText("Ranges", text, 384, 300)
END ShowRanges;
*)

PROCEDURE ShowModuleNames*;
VAR
	T: Texts.Text;
	M: Modules.Module;
BEGIN
	T := TextFrames.Text("");
	M := Kernel.modules;
	WHILE M # NIL DO
		Texts.WriteString(W, M.name); 
		Texts.WriteLn(W);
		M := M.next
	END;
	Texts.Append(T, W.buf);
	Oberon.OpenText("ModuleNames|System.Close System.Free Edit.Store", T, 384, 300)
END ShowModuleNames;

(* ---------------------------------------------------------- *)
PROCEDURE WriteHex(x, w: LONGINT);
VAR
	buf: ARRAY 9 OF CHAR;
	i, j: LONGINT;
BEGIN
	buf[0] := " ";	buf[1] := 0X;
	IF w >= 0 THEN j := 8 ELSE j := 2; w := -w END;
	FOR i := j+1 TO w DO Texts.WriteString(W, buf) END;
	FOR i := j-1 TO 0 BY -1 DO
		buf[i] := CHR(x MOD 10H + 48);
		IF buf[i] > "9" THEN
			buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10)
		END;
		x := x DIV 10H
	END;
	buf[j] := 0X;
	Texts.WriteString(W, buf)
END WriteHex;

(* ---------------------------------------------------------- *)	
(* Scans for a pointer value after an "=" in the selection. A viewer is opened
	and a hex dump of the memory to which the pointer points is done. If the
	pointer points to a record which contains pointers, these values are
	dumped on a separate line, which can then be dereferenced again by
	Memory.DeRef. *)
PROCEDURE DeRef*;
VAR
	S : Texts.Scanner;
	T : Texts.Text;
	adr, tag, size, i, j, k, idx, offset, val,
	selBeg, selEnd, selTime : LONGINT;
	x: SHORTINT;
	name : ARRAY 32 OF CHAR;
BEGIN
	Oberon.GetSelection(T, selBeg, selEnd, selTime);
	IF (selTime >  0) THEN  (* selection exists? *)
		Texts.OpenScanner(S, T, selBeg)
	ELSE RETURN
    END;
	Texts.Scan(S); i := S.line;
	WHILE ~S.eot & (S.line = i) & ~((S.class = Texts.Char) & (S.c = "=")) DO
		Texts.Scan(S);
	END;
	IF ~((S.class = Texts.Char) & (S.c = "=")) THEN RETURN END;
	Texts.Scan(S);
	IF (S.class = Texts.Int) THEN adr := S.i ELSE RETURN END;
		
	IF (adr = 0) OR ~((adr MOD 32 = 0) OR (adr MOD 32 = 24)) THEN
		Out.String("  invalid address for DeRef"); Out.Ln
	ELSE
		(* Get tag *)
		SYSTEM.GET(adr-4, tag);
		(* Get record/array size *)
		SYSTEM.GET(tag, size);
		(* Check if pointer points to array/block of memory *)
		IF (adr MOD 32 = 24) THEN
			DEC(size, 24)  (* See Kernel.NewSys *)
		ELSE (* pointer to record *)
			SYSTEM.MOVE(tag-168, SYSTEM.ADR(name[0]), 32);
			name[31] := 0X;
			Texts.WriteString(W, "Module : ");
			Texts.WriteString(W, name); Texts.WriteLn(W)
		END;
		IF (size > cMaxDeRefLen) THEN size := cMaxDeRefLen END;
		i := 0;
		idx := 4;
		(* Get first offset *)
		SYSTEM.GET(tag + idx, offset);
		WHILE (i < size) DO
			WriteHex(adr+i, 8);  Texts.WriteString(W, "H: ");
			IF (i = offset) THEN
				SYSTEM.GET(adr+i, val);
				Texts.WriteString(W, "(pointer) = "); WriteHex(val, 8);
				Texts.Write(W, "H"); Texts.WriteLn(W);
				INC(idx, 4);
				SYSTEM.GET(tag + idx, offset);
				INC(i, 4)
			ELSE
				(* Do Hex dump. *)
				j := i;
				WHILE (j < i+8) & (j < size) & (j # offset) DO
					SYSTEM.GET(adr+j, x);
					WriteHex(x, -3);
					INC(j)
				END;
				(* Spaces bewteen Hex dump and ASCII dump. *)
				FOR k := j TO i+7 DO Texts.WriteString(W, "   ") END;
				Texts.WriteString(W, "     ");
				(* Do ASCII dump. *)
				j := i;
				WHILE (j < i+8) & (j < size) & (j # offset) DO
					SYSTEM.GET(adr+j, x);
					IF (x > 01FH) & (x < 07FH) THEN Texts.Write(W, CHR(x))
					ELSE Texts.Write(W, ".") END;
					INC(j)
				END;
				Texts.WriteLn(W);
				IF (j = offset) THEN i := j
				ELSE INC(i, 8)
				END
			END
		END;
		T := TextFrames.Text("");
		Texts.Append(T, W.buf);
    	Texts.ChangeLooks(T, 0, T.len, {0}, Fonts.This("Courier10.Scn.Fnt"), 0, 0);
		Oberon.OpenText("DeRef", T, 384, 300)
	END
END DeRef;

(* ---------------------------------------------------------- *)	
(* Scans for an address value in the selection. A viewer is opened
	and a hex dump of the memory is done. *)
PROCEDURE Memory*;
VAR
	S : Texts.Scanner;
	T : Texts.Text;
	adr, size, i, j, k,
	selBeg, selEnd, selTime : LONGINT;
	x: SHORTINT;
BEGIN
	Oberon.GetSelection(T, selBeg, selEnd, selTime);
	IF (selTime >  0) THEN  (* selection exists? *)
		Texts.OpenScanner(S, T, selBeg)
	ELSE RETURN
    END;
	Texts.Scan(S); i := S.line;
	WHILE ~S.eot & (S.line = i) & (S.class # Texts.Int) DO
		Texts.Scan(S)
	END;
	IF (S.class = Texts.Int) THEN adr := S.i ELSE RETURN END;
		
	size := cMaxDeRefLen;
	i := 0;
	WHILE (i < size) DO
		WriteHex(adr+i, 8);  Texts.WriteString(W, "H: ");
		(* Do Hex dump. *)
		j := i;
		WHILE (j < i+8) & (j < size) DO
			SYSTEM.GET(adr+j, x);
			WriteHex(x, -3);
			INC(j)
		END;
		(* Spaces bewteen Hex dump and ASCII dump. *)
		FOR k := j TO i+7 DO Texts.WriteString(W, "   ") END;
		Texts.WriteString(W, "     ");
		(* Do ASCII dump. *)
		j := i;
		WHILE (j < i+8) & (j < size) DO
			SYSTEM.GET(adr+j, x);
			IF (x > 01FH) & (x < 07FH) THEN Texts.Write(W, CHR(x))
			ELSE Texts.Write(W, ".") END;
			INC(j)
		END;
		Texts.WriteLn(W);
		INC(i, 8);
	END;
	T := TextFrames.Text("");
	Texts.Append(T, W.buf);
    Texts.ChangeLooks(T, 0, T.len, {0}, Fonts.This("Courier10.Scn.Fnt"), 0, 0);
	Oberon.OpenText("Memory", T, 384, 300)
END Memory;

	PROCEDURE HandleNames (handle: Handler);
		VAR text: Texts.Text; beg, end, time: LONGINT; s: Texts.Scanner;
	BEGIN
		(* get parameter text *)
		text := NIL; beg := 0; end := 0;
		Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(s);
		IF s.class = Texts.Name THEN
			text := Oberon.Par.text; beg := Oberon.Par.pos; end := text.len
		ELSIF s.class = Texts.Char THEN
			IF s.c = "^" THEN
				Oberon.GetSelection(text, beg, end, time)
			END
		END;
		
		IF beg < end THEN
			Texts.OpenScanner(s, text, beg);
			Texts.Scan(s);
			WHILE (beg < end) & (s.class = Texts.Name) DO
				handle(s.s);
				beg := Texts.Pos(s);
				Texts.Scan(s)
			END
		END
	END HandleNames;
	
	PROCEDURE listText (name: ARRAY OF CHAR);
		VAR
			text: Texts.Text; beg, end: LONGINT; r: Texts.Reader; lib: Objects.Library;
			ch: CHAR;  obj: Objects.Object;  m: Objects.AttrMsg;  s: ARRAY 32 OF CHAR;
	BEGIN
		Texts.WriteString(W, name);  Texts.WriteLn(W);
		NEW(text);
		Texts.Open(text, name);
		IF text.len > 0 THEN
			beg := 0;
			Texts.OpenReader(r, text, 0);
			Texts.Read(r, ch);
			end := 1;
			lib := r.lib;
			WHILE ~r.eot DO
				IF lib IS Fonts.Font THEN
					Texts.Read(r, ch);
					IF r.lib # lib THEN
						COPY(lib.name, s);  s[6] := 0X;
						IF s # "Oberon" THEN Texts.SetColor(W, 3) END;
						Texts.WriteString(W, "  ");  Texts.WriteString(W, lib.name);  Texts.WriteString(W, "  ");
						Texts.WriteInt(W, beg, 1);  Texts.WriteLn(W);
						IF s # "Oberon" THEN Texts.SetColor(W, 15) END;
						beg := end;
						lib := r.lib
					END
				ELSE
					Texts.WriteString(W, "  Object: index ");  Texts.WriteInt(W, ORD(ch), 1);
					Texts.WriteString(W, " in library ");
					IF lib.name = "" THEN Texts.WriteString(W, "(private)")
					ELSE Texts.WriteString(W, lib.name)
					END;
					Texts.WriteString(W, ", ");
					lib.GetObj(lib, ORD(ch), obj);
					m.id := Objects.get;  m.Enum := NIL;  m.name := "Gen";  m.res := -1;
					obj.handle(obj, m);
					IF m.class = Objects.String THEN Texts.WriteString(W, m.s)
					ELSE Texts.WriteString(W, "(unkown)")
					END;
					Texts.WriteLn(W);
					Texts.Read(r, ch);
					beg := end;  lib := r.lib
				END;
				INC(end)
			END;
		END;
		Texts.Append(T, W.buf)
	END listText;
	
	(* list libraries in a text **)
	PROCEDURE ShowLibraries*;
	BEGIN
		T := TextFrames.Text("");
		Oberon.OpenText("Libraries", T, 384, 300);
		HandleNames(listText);
		T := NIL
	END ShowLibraries;
	
PROCEDURE ScanFilenames*;
VAR
	src, dst: Texts.Text;  
	s: Texts.Scanner;  f: Files.File;
	beg, end, time, pos: LONGINT;
BEGIN
	Oberon.GetSelection(src, beg, end, time);
	IF (src # NIL) & (time > 0) THEN
		dst := TextFrames.Text("");
		Oberon.OpenText("Filenames", dst, 384, 300);
		Texts.OpenScanner(s, src, beg);  
		pos := Texts.Pos(s);  Texts.Scan(s);
		WHILE ~s.eot & (s.class # Texts.Inval) & (pos < end) DO
			IF s.class = Texts.Name THEN
				f := Files.Old(s.s);
				IF f # NIL THEN
					Texts.WriteString(W, s.s);  Texts.WriteLn(W);
					Texts.Append(dst, W.buf)
				END
			END;
			pos := Texts.Pos(s);  Texts.Scan(s)
		END;
		Texts.Write(W, "~");  Texts.WriteLn(W);
		Texts.Append(dst, W.buf)
	END
END ScanFilenames;

PROCEDURE ShowImports*;	(* {objfile} *)
TYPE
	Header = RECORD (* data in object file header *)
		nofDataEntries: INTEGER;
		nofEntries: INTEGER;
		nofCommands: INTEGER;
		nofPointers: INTEGER;
		nofTypes: INTEGER;
		nofImports: INTEGER;
		nofLinks: INTEGER;
		nofDataLinks: INTEGER;
		codeSize, dataSize, refSize: LONGINT;
		constSize: INTEGER
	END;
VAR
	f: Files.File;  r: Files.Rider;  s: Texts.Scanner;
	name: ARRAY 32 OF CHAR;
	head: Header;  key: LONGINT;  i, t: LONGINT;
	tag0, tag1: CHAR;
	T: Texts.Text;

	PROCEDURE Expect(tag: CHAR);
	VAR ch: CHAR;
	BEGIN
		Files.Read(r, ch);
		IF ch # tag THEN HALT(99) END
	END Expect;

	PROCEDURE ReadUnsigned(VAR R: Files.Rider; VAR u: LONGINT);
	(* read unsigned, 16 bit, little endian value *)
	VAR low, high: CHAR;
	BEGIN
		Files.Read(R, low); Files.Read(R, high);
		u := 256*LONG(ORD(high)) + ORD(low);
	END ReadUnsigned;

BEGIN
	T := TextFrames.Text("");
	Oberon.OpenText("Imports", T, 384, 300);
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(s);
	WHILE s.class = Texts.Name DO
		i := 0;  WHILE (s.s[i] # ".") & (s.s[i] # 0X) DO INC(i) END;
		s.s[i] := ".";  s.s[i+1] := "O";  s.s[i+2] := "b";  s.s[i+3] := "j";  s.s[i+4] := 0X;
		Texts.WriteString(W, s.s);
		f := Files.Old(s.s);
		IF f # NIL THEN
			Files.Set(r, f, 0);  Files.Read(r, tag0);  Files.Read(r, tag1);
			IF (tag0 = 0F8X) & (tag1 = 036X) THEN
				Files.ReadLInt(r, head.refSize); Files.ReadInt(r, head.nofDataEntries); Files.ReadInt(r, head.nofEntries);
				Files.ReadInt(r, head.nofCommands);
				Files.ReadInt(r, head.nofPointers); Files.ReadInt(r, head.nofTypes); Files.ReadInt(r, head.nofImports);
				Files.ReadInt(r, head.nofDataLinks); Files.ReadInt(r, head.nofLinks);
				Files.ReadLInt(r, head.dataSize); Files.ReadInt(r, head.constSize);  ReadUnsigned(r, head.codeSize);
				Files.ReadLInt(r, key); Files.ReadString(r, s.s);
				
				(* VarEntries *)
				Expect(08CX);
				i := 0;  WHILE i < head.nofDataEntries DO Files.ReadLInt(r, t);  INC(i) END;
			
				(* EntryBlk *)
				Expect(082X);
				i := 0;  WHILE i < head.nofEntries DO ReadUnsigned(r, t);  INC(i) END;
			
				(* CmdBlk *)
				Expect(083X);  i := 0;
				WHILE i < head.nofCommands DO
					Files.ReadString(r, name);  ReadUnsigned(r, t);  INC(i)
				END;
			
				(* PtrBlk *)
				Expect(084X);
				i := 0;  WHILE i < head.nofPointers DO Files.ReadLInt(r, t);  INC(i) END;
			
				(* Import Block *)
				Expect(085X);
				i := 0;
				WHILE i < head.nofImports DO
					Files.ReadLInt(r, key);  Files.ReadString(r, name);
					IF i = 0 THEN
						Texts.WriteString(W, " IMPORT ")
					ELSE
						Texts.WriteString(W, ", ")
					END;
					Texts.WriteString(W, name);
					INC(i)
				END;
				IF i # 0 THEN Texts.Write(W, ";") END
			ELSE
				Texts.WriteString(W, " not an Obj file")
			END;
			Texts.WriteLn(W)
		ELSE
			Texts.WriteString(W, " not found");  Texts.WriteLn(W)
		END;
		Texts.Append(T, W.buf);
		Texts.Scan(s);
		WHILE s.class = Texts.Int DO Texts.Scan(s) END
	END
END ShowImports;

(* ---------------------------------------------------------- *)	
(* Prints the type descriptors of a module *)

PROCEDURE GetMthName(adr: LONGINT);
VAR
	T: Texts.Text;  refpos, limit, bp, x: LONGINT;  
	ch, ch0: CHAR;  
	mod: Modules.Module;  
	procstart, refstart: LONGINT;
	stackorg: LONGINT;

	PROCEDURE ReadNum (VAR pos: LONGINT; VAR i: LONGINT);
		VAR n: LONGINT; s: SHORTINT; x: CHAR;
	BEGIN
		s := 0; n := 0; SYSTEM.GET(pos, x); INC(pos);
		WHILE ORD(x) >= 128 DO INC(n, ASH(ORD(x) - 128, s)); INC(s, 7); SYSTEM.GET(pos, x); INC(pos) END;
		i := n + ASH(ORD(x) MOD 64 - ORD(x) DIV 64 * 64, s)
	END ReadNum;
	
BEGIN
	mod := Kernel.GetMod(adr);
	IF mod = NIL THEN Texts.WriteString(W, "<not found>")
	ELSE
		IF (SYSTEM.VAL(LONGINT, mod.refs) # 0) & (LEN(mod.refs) # 0) THEN
			refstart := 0;  refpos := SYSTEM.ADR(mod.refs[0]);
			limit := refpos + LEN(mod.refs);
			LOOP
				SYSTEM.GET(refpos, ch); INC(refpos);
				IF refpos >= limit THEN EXIT END;
				IF ch = 0F8X THEN (* start proc *)
					ReadNum(refpos, procstart);
					IF adr < SYSTEM.ADR(mod.code[0]) + procstart THEN EXIT END;
					refstart := refpos;
					REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X; (*skip name*)
				ELSIF ch < 0F8X THEN (* skip object *)
					INC(refpos);	(* skip typeform *)
					ReadNum(refpos, procstart);	(* skip offset *)
					REPEAT SYSTEM.GET(refpos, ch); INC(refpos) UNTIL ch = 0X; (*skip name*)
				END
			END;
			refpos := refstart;
			IF refpos # 0 THEN
				Texts.WriteString(W, mod.name);
				Texts.Write(W, "."); SYSTEM.GET(refpos, ch); INC(refpos); ch0 := ch;
				WHILE ch # 0X DO Texts.Write(W, ch); SYSTEM.GET(refpos, ch); INC(refpos) END
			END;
		ELSE Texts.WriteString(W, "<not found>")
		END
	END;  (* ELSE *)
END GetMthName;

PROCEDURE GetTDName(adr: LONGINT; VAR name: ARRAY OF CHAR);
BEGIN
	SYSTEM.GET(adr-4, adr); SYSTEM.MOVE(adr+16, SYSTEM.ADR(name), 16);
END GetTDName;

PROCEDURE DumpTD(adr: LONGINT);
	VAR base, mth, tdsize, recsize: LONGINT; name: ARRAY 16 OF CHAR;
BEGIN
	SYSTEM.GET(adr-4, base);
	SYSTEM.GET(base, tdsize);  SYSTEM.GET(adr, recsize);
	
	SYSTEM.MOVE(base+16, SYSTEM.ADR(name), 16);
	Texts.Write(W, 9X); Texts.WriteString(W, name); Texts.WriteString(W, " ["); 
	Texts.WriteHex(W, adr); Texts.WriteString(W, "H]"); Texts.WriteLn(W);
	Texts.Write(W, 9X); Texts.WriteString(W, "tdsize: "); Texts.WriteInt(W, tdsize, 8); Texts.WriteLn(W);
	Texts.Write(W, 9X); Texts.WriteString(W, "name:  "); Texts.WriteString(W, name); Texts.WriteLn(W);
	INC(base, 52);
	Texts.Write(W, 9X); Texts.WriteString(W, "methods:  "); Texts.WriteLn(W);
	WHILE base <= adr-72 DO
		SYSTEM.GET(base, mth);
		Texts.Write(W, 9X); Texts.Write(W, 9X); Texts.WriteInt(W, (adr-72-base) DIV 4, 2); Texts.WriteString(W, ": [");
		Texts.WriteHex(W, mth); Texts.WriteString(W, "H]  "); GetMthName(mth); Texts.WriteLn(W);
		INC(base, 4);
	END;
	Texts.Write(W, 9X); Texts.WriteString(W, "tags:  "); Texts.WriteLn(W);
	WHILE base <= adr-8 DO
		SYSTEM.GET(base, mth);
		IF mth # 0 THEN GetTDName(mth, name);
			Texts.Write(W, 9X); Texts.Write(W, 9X); Texts.WriteInt(W, (adr-8-base) DIV 4, 2); Texts.WriteString(W, ": [");
			Texts.WriteHex(W, mth); Texts.WriteString(W, "H]  "); Texts.WriteString(W, name); Texts.WriteLn(W);
		END;
		INC(base, 4);
	END;
	Texts.Write(W, 9X); Texts.WriteString(W, "recsize: "); Texts.WriteInt(W, recsize, 8); Texts.WriteLn(W);
	Texts.Write(W, 9X); Texts.WriteString(W, "pointers:  "); Texts.WriteLn(W);
	base := adr+4;
	REPEAT
		SYSTEM.GET(base, mth);
		Texts.Write(W, 9X); Texts.Write(W, 9X); Texts.WriteHex(W, mth); Texts.WriteString(W, "H"); Texts.WriteLn(W);
		INC(base, 4);
	UNTIL mth < 0;
	Texts.WriteLn(W); Texts.WriteLn(W)
END DumpTD;

PROCEDURE ShowTD*;	(** Info.ShowTD modulename *)
	VAR text: Texts.Text; beg, end, time, i: LONGINT; s: Texts.Scanner;
		m: Modules.Module;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(s);
	IF s.class = Texts.Char THEN
		IF s.c = "^" THEN
			Oberon.GetSelection(text, beg, end, time);
			Texts.OpenScanner(s, text, beg); Texts.Scan(s)
		END
	END;
	IF s.class = Texts.Name THEN
		m := Modules.ThisMod(s.s);
		IF m # NIL THEN
			Texts.SetFont(W, Fonts.This("Courier10.Scn.Fnt"));
			FOR i := 0 TO LEN(m.tdescs)-1 DO DumpTD(m.tdescs[i]) END;
			NEW(text); Texts.Open(text, ""); Texts.Append(text, W.buf);
			Oberon.OpenText("ShowTD", text, 384, 300)
		END
	END;
END ShowTD;

BEGIN
	Texts.OpenWriter(W);
END Info.

Info.ShowModules
Info.DeRef

Info.ShowRanges
Info.ShowImports ~
Info.ShowLibraries ^
Info.ShowTD ^
