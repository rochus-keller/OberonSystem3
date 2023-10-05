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

MODULE FDInstall;	(** non-portable *)	(* pjm *)

IMPORT In, Out, Texts, Oberon, SYSTEM, Files, Diskette, VirtFiles, VirtDisk, CompressUtil, CRC32;

CONST
	BS = 512;
	SS = 2048;
	BootFileName = "OBL.Bin";
	
	CompressBufSize = 32*BS;	(* {multiple of BS} *)
	CompressID = 0FEEDC0DEH;

VAR
	W: Texts.Writer;
	verify: BOOLEAN;
	virtual: Files.File;
	compressRider: Files.Rider;
	compressBuf: POINTER TO ARRAY CompressBufSize OF CHAR;
	compressPos: LONGINT;
	compressSec: INTEGER;

PROCEDURE -Equal4(adr0, adr1, len: LONGINT): BOOLEAN;
CODE {SYSTEM.i386}
	POP ECX
	POP EDI
	POP ESI
	CLD
	REPE CMPSD
	SETE AL
END Equal4;

PROCEDURE PutSectors(start, num: INTEGER;  VAR buf: ARRAY OF SYSTEM.BYTE; ofs: LONGINT);
CONST Size = 32;
VAR
	error: ARRAY 32 OF CHAR;
	verbuf: ARRAY Size*BS OF CHAR;
	n: INTEGER;
	pos, len: LONGINT;
	r: Files.Rider;
BEGIN
	IF virtual = NIL THEN
		Diskette.PutSectors(start, num, buf, ofs);
		IF verify THEN
			REPEAT
				IF num > Size THEN n := Size ELSE n := num END;
				Diskette.GetSectors(start, n, verbuf, 0);
				IF ~Equal4(SYSTEM.ADR(buf[ofs]), SYSTEM.ADR(verbuf[0]), LONG(n)*BS DIV 4) THEN
					error := "Verify error"; HALT(99)
				END;
				INC(start, n);  INC(ofs, LONG(n)*BS);  DEC(num, n)
			UNTIL num = 0
		END
	ELSE
		pos := LONG(start)*BS;  len := Files.Length(virtual);
		IF pos > len THEN	(* fill up the file to the current pos *)
			Files.Set(r, virtual, len);
			WHILE pos > len DO
				Files.Write(r, 0X);  INC(len)
			END
		END;
		Files.Set(r, virtual, pos);
		ASSERT(ofs = 0);	(* restricted implementation good enough for current use *)
		Files.WriteBytes(r, buf, LONG(num)*BS);
		Files.Close(virtual)	(* flush *)
	END
END PutSectors;

PROCEDURE GetSectors(start, num: INTEGER;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
VAR r: Files.Rider;
BEGIN
	IF virtual = NIL THEN
		Diskette.GetSectors(start, num, buf, ofs)
	ELSE
		ASSERT(LONG(start+num)*BS <= Files.Length(virtual));
		Files.Set(r, virtual, LONG(start)*BS);
		ASSERT(ofs = 0);	(* restricted implementation good enough for current use *)
		Files.ReadBytes(r, buf, LONG(num)*BS)
	END
END GetSectors;

(* ScanParams - Scan { env "=" strval {"+" strval} } ch, and add to tab *)

PROCEDURE ScanParams(VAR s: Texts.Scanner;  VAR a: ARRAY OF LONGINT;  tsize: INTEGER;  VAR i: INTEGER);
VAR
	error, name: ARRAY 32 OF CHAR;
	val: ARRAY 256 OF CHAR;
	bi0, bi1: LONGINT;
	j, k: INTEGER;
BEGIN
	Texts.Scan(s);  bi0 := SYSTEM.ADR(a[i])+8;  bi1 := bi0;
	WHILE s.class = Texts.Name DO
		COPY(s.s, name);
		Texts.Scan(s);	(* "=" *)
		IF (s.class # Texts.Char) OR (s.c # "=") THEN error := "config: syntax error";  HALT(99) END;
		Texts.Scan(s);	(* val *)
		IF s.class = Texts.Int THEN s.s[0] := CHR(s.i); s.s[1] := 0X; s.class := Texts.String END;
		IF (s.class # Texts.Name) & (s.class # Texts.String) THEN error := "config: syntax error";  HALT(99) END;
		COPY(s.s, val);
		j := 0;  WHILE val[j] # 0X DO INC(j) END;	(* j = length of val *)
		IF j >= 63 THEN error := "config: string too long; use +";  HALT(99) END;
		Texts.Scan(s);	(* next name, or "+" *)
		WHILE (s.class = Texts.Char) & (s.c = "+") DO
			Texts.Scan(s);	(* val *)
			IF s.class = Texts.Int THEN s.s[0] := CHR(s.i); s.s[1] := 0X; s.class := Texts.String END;
			IF (s.class # Texts.Name) & (s.class # Texts.String) THEN error := "config: syntax error";  HALT(99) END;
			k := 0;  WHILE s.s[k] # 0X DO val[j] := s.s[k]; INC(j); INC(k) END;
			val[j] := 0X;
			IF k >= 63 THEN error := "config: string too long; use +";  HALT(99) END;
			Texts.Scan(s)
		END;
		k := 0;  WHILE name[k] # 0X DO INC(k) END;	(* k = length of name *)
		IF bi1+k+j+3 >= SYSTEM.ADR(a[tsize-1]) THEN error := "Table overflow";  HALT(99) END;
		j := 0;  WHILE name[j] # 0X DO SYSTEM.PUT(bi1, name[j]); INC(bi1); INC(j) END;
		SYSTEM.PUT(bi1, 0X);  INC(bi1);
		j := 0;  WHILE val[j] # 0X DO SYSTEM.PUT(bi1, val[j]); INC(bi1); INC(j) END;
		SYSTEM.PUT(bi1, 0X);  INC(bi1)
	END;
	IF bi1 # bi0 THEN	(* some config strings were added *)
		SYSTEM.PUT(bi1, 0X);  INC(bi1);	(* end of config *)
		WHILE (bi1-bi0) MOD 4 # 0 DO SYSTEM.PUT(bi1, 0X);  INC(bi1) END;
		a[i] := 8 (* patch *);  INC(i);  a[i] := 8+(bi1-bi0);
		INC(i, SHORT(1+(bi1-bi0) DIV 4))
	END;
		(* check syntax *)
	IF s.class # Texts.Char THEN error := "syntax error"; HALT(99) END
END ScanParams;

PROCEDURE Copy(from, to: ARRAY OF CHAR);
	VAR error: ARRAY 32 OF CHAR;
		f: Files.File; g: VirtFiles.File; Rf: Files.Rider; Rg: VirtFiles.Rider; ch: CHAR;
BEGIN
	Texts.WriteString(W, from);
	IF to # from THEN
		Texts.WriteString(W, " => ");  Texts.WriteString(W, to)
	END;
	Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
	f := Files.Old(from);
	IF (f = NIL) THEN
		error := "File not found";  HALT(99)
	END;
	g := VirtFiles.New(to);
	Files.Set(Rf, f, 0); VirtFiles.Set(Rg, g, 0); Files.Read(Rf, ch);
	WHILE ~Rf.eof DO VirtFiles.Write(Rg, ch); Files.Read(Rf, ch) END;
	VirtFiles.Register(g)
END Copy;

PROCEDURE CopyFile(name: ARRAY OF CHAR; VAR S: Texts.Scanner);
BEGIN Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "=") THEN Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = ">") THEN Texts.Scan(S);
			IF S.class = Texts.Name THEN
				Copy(name, S.s);  Texts.Scan(S)
			END
		END
	ELSE Copy(name, name)
	END
END CopyFile;

PROCEDURE CompressRead(VAR ch: CHAR;  VAR eof: BOOLEAN);
BEGIN
	Files.Read(compressRider, ch);
	eof := compressRider.eof
END CompressRead;

PROCEDURE CompressWrite(ch: CHAR);
BEGIN
	compressBuf[compressPos] := ch;  INC(compressPos);
	IF compressPos = CompressBufSize THEN
		PutSectors(compressSec, CompressBufSize DIV BS, compressBuf^, 0);
		INC(compressSec, CompressBufSize DIV BS);
		compressPos := 0
	END
END CompressWrite;

PROCEDURE CompressClose;
BEGIN
	IF compressPos # 0 THEN
		WHILE compressPos MOD BS # 0 DO	(* fill last block with 0X *)
			compressBuf[compressPos] := 0X;  INC(compressPos)
		END;
		PutSectors(compressSec, SHORT(compressPos DIV BS), compressBuf^, 0);
		INC(compressSec, SHORT(compressPos DIV BS))
	END
END CompressClose;

PROCEDURE CopySectors(f: Files.File;  start: INTEGER;  VAR blocksStored: INTEGER);
VAR crc: SET;  size: LONGINT;
BEGIN
	IF compressBuf = NIL THEN NEW(compressBuf) END;
	ASSERT(CompressBufSize MOD BS = 0);
	Files.Set(compressRider, f, 0);
		(* compress the file *)
	compressPos := 12;  compressSec := start;
	CompressUtil.Compress(CompressRead, CompressWrite);
	CompressClose;
	blocksStored := compressSec-start;
		(* compute the CRC *)
	Files.Set(compressRider, f, 0);  crc := CRC32.CRCInit;
	LOOP
		Files.ReadBytes(compressRider, compressBuf^, CompressBufSize);
		size := CompressBufSize-compressRider.res;
		IF size = 0 THEN EXIT END;
		crc := CRC32.CRC32(crc, compressBuf^, size)
	END;
		(* patch the header *)
	GetSectors(start, 1, compressBuf^, 0);
	SYSTEM.PUT(SYSTEM.ADR(compressBuf[0]), CompressID);	(* id *)
	SYSTEM.PUT(SYSTEM.ADR(compressBuf[4]), Files.Length(f));	(* uncompressed size in bytes *)
	SYSTEM.PUT(SYSTEM.ADR(compressBuf[8]), crc);	(* CRC of uncompressed data *)
	PutSectors(start, 1, compressBuf^, 0);
		(* clean up *)
	Files.Set(compressRider, NIL, 0);  compressBuf := NIL
END CopySectors;

PROCEDURE CreateBootFloppy*;	(* [flag] corename { env "=" strval } "\" [ size ] {file [=> file]} ] "~" *)
CONST Size = 4*BS;
VAR
	tsize, rsize0, rsize1, i, j, dsize: INTEGER;
	b: ARRAY Size OF CHAR;
	f: Files.File;  r: Files.Rider;
	tab: ARRAY Size DIV 4 OF LONGINT;
	s: Texts.Scanner;
	sum: LONGINT;
	flag: LONGINT;
BEGIN
	Diskette.drive := 0;  i := 0;
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(s);
	IF s.class = Texts.Int THEN flag := s.i;  Texts.Scan(s)
	ELSE flag := 31
	END;
	IF s.class # Texts.Name THEN Out.String("corename expected");  Out.Ln;  RETURN END;
	f := Files.Old(BootFileName);  Files.Set(r, f, 0);
	IF (f # NIL) & (Files.Length(f) <= Size) THEN
		Files.ReadBytes(r, b, Files.Length(f));
		IF r.res # 0 THEN Out.String("Read error");  Out.Ln;  RETURN END;
			(* get parameters from boot loader *)
		SYSTEM.GET(SYSTEM.ADR(b[0EH]), rsize0);  tsize := ORD(b[10H]);
		IF (rsize0-tsize)*BS # Files.Length(f) THEN Out.String("OBL inconsistent");  Out.Ln;  RETURN END;
		tsize := tsize*BS DIV 4;
			(* write the core image *)
		Texts.WriteString(W, "Writing inner core");  Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf);
		f := Files.Old(s.s);  Files.Set(r, f, 0);	(* open core file *)
		IF f = NIL THEN Out.String("core file not found");  Out.Ln;  RETURN END;
		rsize1 := rsize0;  sum := 0;  dsize := 0;
		LOOP
			Files.ReadBytes(r, b, Size);
			IF r.res = Size THEN EXIT END;
			j := SHORT(Size - r.res);  WHILE j MOD BS # 0 DO b[j] := 0X; INC(j) END;
			PutSectors(rsize1, j DIV BS, b, 0);  INC(rsize1, j DIV BS);
			REPEAT DEC(j); sum := (sum + ORD(b[j])) MOD 100H UNTIL j = 0
		END;
		sum := (-sum) MOD 100H;
		IF rsize1 = rsize0 THEN Out.String("empty core file");  Out.Ln;  RETURN END;
		ScanParams(s, tab, tsize, i);
		IF s.c # Oberon.OptionChar THEN Out.String("\ expected");  Out.Ln;  RETURN END;
		Texts.Scan(s);
		IF s.class = Texts.Int THEN Texts.Scan(s) END;	(* ignore size (old syntax) *)
		IF s.class = Texts.Name THEN	(* at least one file specified *)
			VirtFiles.Init;
			WHILE s.class = Texts.Name DO CopyFile(s.s, s) END;
			ASSERT(Files.Length(VirtDisk.disk) MOD SS = 0);
			Texts.WriteString(W, "Compressing ");
			Texts.WriteInt(W, Files.Length(VirtDisk.disk) DIV 1024, 1);
			Texts.WriteString(W, "k ramdisk");  Texts.Append(Oberon.Log, W.buf);
			CopySectors(VirtDisk.disk, rsize1, dsize);
			Texts.WriteString(W, " to ");  Texts.WriteInt(W, LONG(dsize)*BS DIV 1024, 1);
			Texts.Write(W, "k");  Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf);
			VirtDisk.disk := NIL
		END;
		IF s.c # "~" THEN Out.String("~ expected");  Out.Ln;  RETURN END;
			(* set parameters in boot loader for 1.44Mb floppy *)
		f := Files.Old(BootFileName);  Files.Set(r, f, 0);
		Files.ReadBytes(r, b, Files.Length(f));
		IF r.res # 0 THEN Out.String("Read error");  Out.Ln;  RETURN END;
		SYSTEM.PUT(SYSTEM.ADR(b[13H]), SYSTEM.VAL(INTEGER, rsize1+dsize));	(* total sectors *)
		SYSTEM.PUT(SYSTEM.ADR(b[18H]), SYSTEM.VAL(INTEGER, 18));	(* sectors/track *)
		SYSTEM.PUT(SYSTEM.ADR(b[1AH]), SYSTEM.VAL(INTEGER, 2));	(* heads *)
		SYSTEM.PUT(SYSTEM.ADR(b[1CH]), SYSTEM.VAL(LONGINT, 0));	(* boot sector *)
		SYSTEM.PUT(SYSTEM.ADR(b[24H]), 0X);	(* drive 0 *)
		SYSTEM.PUT(SYSTEM.ADR(b[0EH]), rsize1);	(* new reserved size *)
		b[10] := CHR(flag);
			(* write the boot loader to disk *)
		Texts.WriteString(W, "Writing boot loader");  Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf);
		PutSectors(0, SHORT(Files.Length(f) DIV BS), b, 0);
			(* finish the table *)
		tab[i] := 7 (* frag. kernel *);  INC(i);  tab[i] := 28;  INC(i);
		tab[i] := 1000H;  INC(i);  tab[i] := 1 + ASH(sum, 16);  INC(i);
		tab[i] := 1000H;  INC(i);  tab[i] := 0 (* relative to fs start *);  INC(i);
		tab[i] := rsize1-rsize0;  INC(i);
		IF i >= tsize-1 THEN Out.String("Table overflow");  Out.Ln; RETURN END;
		WHILE i # tsize DO tab[i] := -1; INC(i) END;
		tsize := tsize*4 DIV BS;	(* number of blocks in table *)
		PutSectors(rsize0-tsize, tsize, tab, 0);
		Texts.WriteString(W, "done");  Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END
END CreateBootFloppy;

PROCEDURE FileToDiskette*;	(* name *)
CONST Size = 32*BS;
VAR f: Files.File;  r: Files.Rider;  buf: ARRAY Size OF CHAR;  s: Texts.Scanner;  pos, num: INTEGER;  pc, pr, i, size: LONGINT;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(s);
	IF s.class = Texts.Name THEN
		IF virtual # NIL THEN Out.String("Warning: Still in virtual mode");  Out.Ln END;
		f := Files.Old(s.s);
		IF f # NIL THEN
			Files.Set(r, f, 0);  pos := 0;  Out.String("Copying... ");
			i := 0;  pr := 10;  size := Files.Length(f);
			LOOP
				pc := i*100 DIV size;
				WHILE pc > pr DO
					Out.Int(pr, 1);  Out.String("% ");
					INC(pr, 10)
				END;
				Files.ReadBytes(r, buf, Size);
				num := SHORT((Size-r.res+BS-1) DIV BS);
				INC(i, Size-r.res);
				IF num = 0 THEN EXIT END;
				PutSectors(pos, num, buf, 0);
				INC(pos, num)
			END;
			Out.String("100% ");  Out.Int(pos, 1);  Out.String(" blocks");
			Out.Ln
		END
	END
END FileToDiskette;

PROCEDURE DisketteToFile*;	(* name [numsec] ~ *)	(* assumes 1.44Mb diskette *)
CONST Size = 32*BS;
VAR f: Files.File;  r: Files.Rider;  buf: ARRAY Size OF CHAR;  s: Texts.Scanner;  pos, num, n: INTEGER;  pc, pr, size: LONGINT;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(s);
	IF s.class = Texts.Name THEN
		f := Files.New(s.s);
		IF f # NIL THEN
			Texts.Scan(s);
			IF s.class = Texts.Int THEN num := SHORT(s.i) ELSE num := 2880 END;
			Files.Set(r, f, 0);  pos := 0;  Out.String("Copying... ");
			pr := 10;  size := num;
			WHILE num > 0 DO
				pc := LONG(pos)*100 DIV size;
				WHILE pc > pr DO
					Out.Int(pr, 1);  Out.String("% ");
					INC(pr, 10)
				END;
				IF num > Size DIV BS THEN n := Size DIV BS ELSE n := num END;
				GetSectors(pos, n, buf, 0);
				Files.WriteBytes(r, buf, n*BS);
				INC(pos, n);  DEC(num, n)
			END;
			Files.Register(f);
			Out.String(" 100% ");  Out.Int(pos, 1);  Out.String(" sectors");  Out.Ln
		END
	END
END DisketteToFile;

PROCEDURE CreateInstallFloppy*;	(* label { file [=> file]} ~ *)
CONST
	FileBufSize = 1024;
TYPE
	List = POINTER TO Rec;
	Rec = RECORD
		next: List;  f: Files.File;
		src, dst: ARRAY 32 OF CHAR
	END;
VAR
	notfound, label: ARRAY 32 OF CHAR;  s: Texts.Scanner;  ok: BOOLEAN;
	list, n: List;  r, w: Files.Rider;  start: INTEGER;  crc: SET;  len: LONGINT;
	buf: ARRAY FileBufSize OF CHAR;

	PROCEDURE Insert(n: List);
	VAR error, duplicate: ARRAY 32 OF CHAR;  p: List;  
	BEGIN
		p := list;
		WHILE (p.next # NIL) & (p.next.dst < n.dst) DO p := p.next END;
		IF p.next # NIL THEN
			IF p.next.dst = n.dst THEN COPY(n.dst, duplicate); error := "Duplicate file"; HALT(99) END;	(* duplicate *)
			n.next := p.next;  p.next := n
		ELSE
			n.next := NIL;  p.next := n
		END
	END Insert;
	
	PROCEDURE Open;
	VAR i: LONGINT;  out: ARRAY BS OF CHAR;
	BEGIN
			(* check if boot disk & init buffer *)
		GetSectors(0, 1, out, 0);
		i := 0;  SYSTEM.GET(SYSTEM.ADR(out[510]), SYSTEM.VAL(INTEGER, i));
		out[0] := "x"; out[1] := "x"; out[2] := "x";  out[9] := 0X;
		IF (i = 0AA55H) & (out = "xxxOBERON") THEN	(* valid boot block *)
			SYSTEM.GET(SYSTEM.ADR(out[13H]), compressSec)	(* total sectors *)
		ELSE HALT(99)
		END;
		IF compressBuf = NIL THEN NEW(compressBuf) END;
		compressPos := 0;  start := compressSec
	END Open;
	
	PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
	VAR i: LONGINT;
	BEGIN
		i := 0;  WHILE s[i] # 0X DO INC(i) END;
		RETURN i
	END Length;
	
BEGIN
	NEW(list);  list.next := NIL;
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(s);
	IF s.class = Texts.Name THEN
		COPY(s.s, label);  Texts.Scan(s);  ok := TRUE;
		WHILE (s.class = Texts.Name) & ok DO
			NEW(n);  COPY(s.s, n.src);
			Texts.Scan(s);
			IF (s.class = Texts.Char) & (s.c = "=") THEN
				Texts.Scan(s);
				IF (s.class = Texts.Char) & (s.c = ">") THEN
					Texts.Scan(s);
					IF s.class = Texts.Name THEN
						COPY(s.s, n.dst);  Texts.Scan(s)
					ELSE ok := FALSE
					END
				ELSE ok := FALSE
				END
			ELSE n.dst := n.src
			END;
			IF ok THEN
				n.f := Files.Old(n.src);
				IF n.f = NIL THEN
					COPY(n.src, notfound);  HALT(99)
				END;
				Insert(n)
			END
		END;
		IF ~ok THEN list.next := NIL END
	END;
	list := list.next;
	IF list # NIL THEN
		crc := CRC32.CRCInit;
		Files.Set(w, Files.New(""), 0);
		Files.WriteString(w, label);
		crc := CRC32.CRC32(crc, label, Length(label)+1);
		WHILE list # NIL DO
			Texts.WriteString(W, list.src);
			IF list.dst # list.src THEN
				Texts.WriteString(W, " => ");
				Texts.WriteString(W, list.dst)
			END;
			Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
			Files.WriteString(w, list.dst);
			crc := CRC32.CRC32(crc, list.dst, Length(list.dst)+1);
			len := Files.Length(list.f);
			Files.WriteBytes(w, len, 4);
			crc := CRC32.CRC32(crc, len, 4);
			Files.Set(r, list.f, 0);
			LOOP
				Files.ReadBytes(r, buf, FileBufSize);
				len := FileBufSize-r.res;
				IF len = 0 THEN EXIT END;
				crc := CRC32.CRC32(crc, buf, len);
				Files.WriteBytes(w, buf, len)
			END;
			list := list.next
		END;
		buf := "";
		Files.WriteString(w, buf);
		crc := CRC32.CRC32(crc, buf, 1);
		Files.WriteBytes(w, crc, 4);
			(* now compress the temporary file onto the diskette *)
		Texts.WriteString(W, "Compressing ");
		Texts.WriteInt(W, Files.Length(Files.Base(w)) DIV 1024, 1);
		Texts.WriteString(W, "k");  Texts.Append(Oberon.Log, W.buf);
			(* compress file *)
		Open;
		Files.Set(compressRider, Files.Base(w), 0);
		CompressUtil.Compress(CompressRead, CompressWrite);
		CompressClose;
		Texts.WriteString(W, " to ");  Texts.WriteInt(W, LONG(compressSec-start)*BS DIV 1024, 1);
		Texts.Write(W, "k");  Texts.WriteLn(W);
		Texts.WriteString(W, "done");  Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf);
		Files.Set(w, NIL, 0)
	END
END CreateInstallFloppy;

PROCEDURE Verify*;
VAR s: ARRAY 10 OF CHAR;
BEGIN
	In.Open;  In.String(s);
	IF ~In.Done THEN
	ELSIF s = "on" THEN
		verify := TRUE;
		Out.String("verify on");  Out.Ln
	ELSIF s = "off" THEN
		verify := FALSE;
		Out.String("verify off");  Out.Ln
	END
END Verify;

PROCEDURE Virtual*;	(* [imagefilename] ~ *)
VAR s: ARRAY 32 OF CHAR;  res: INTEGER;
BEGIN
	In.Open;  In.String(s);
	IF In.Done THEN
		Out.String("virtual on - output file ");  Out.String(s);  Out.Ln;
		Files.Delete(s, res);
		virtual := Files.New(s);
		Files.Register(virtual)
	ELSIF virtual # NIL THEN
		Out.String("virtual off, file size ");  Out.Int((Files.Length(virtual)+1023) DIV 1024, 1);
		Out.String("k, free space ");  Out.Int((2880*512-Files.Length(virtual)) DIV 1024, 1);
		Out.Char("k");  Out.Ln;
		virtual := NIL
	END
END Virtual;

BEGIN
	Texts.OpenWriter(W);
	verify := TRUE;  virtual := NIL;
	compressBuf := NIL
END FDInstall.

FDInstall.Virtual t ~
FDInstall.Virtual ~

FDInstall.CreateBootFloppy Native0.Bin
	MouseType="6"  MouseRate="100"  TracePort="1"  TraceBPS="19200"
	Video="38,0F001001"
	/ 100
	Oberon10.Scn.Fnt System.Tool 
 ~
FDInstall.CreateBootFloppy 1 Native.Bin
	MouseType="6"  MouseRate="100"  TracePort="1"  TraceBPS="19200"
	Video="02054F02,0F001001"  Display="S3C805"
	/ ~
FDInstall.CreateInstallFloppy LABEL
	{file [=> file]} ~
~

DOS.Copy c:/gneiss/asm/obl.bin => OBL.Bin c:/gneiss/asm/obl.asm => OBL.Asm ~
!Backup.ReadFiles OBL.BIN OBL.ASM ~
!System.RenameFiles OBL.BIN => OBL.Bin OBL.ASM => OBL.Asm ~
Miscellaneous.MakeOberonText OBL.Asm => OBL.Asm~

FDInstall.Write off
FDInstall.CreateBootFloppy 1 Core0.Bin
	MouseType="6"  Buttons="2"  Init="b81200cd10bb003fb80110cd10"
	Testing="it was a dark and stormy "+"night...  Suddenly a shot "+"rang out"
	\ 550
	Objects.obj VGA.Display.obj=>Display.obj V24.obj Input.obj Viewers.obj
	Fonts.obj Reals.obj Texts.obj Oberon.obj MenuViewers.obj TextFrames.obj
	System.obj NativeIntro.obj In.obj Diskette.obj 
	Backup.obj Oberon10.Scn.Fnt Courier10.Scn.Fnt OBL.Bin Out.obj 
	Empty.Display.obj ATDisk.obj ATFileDir.obj ATFiles.obj Install.obj 
	Trace.Display.obj VirtDisk.obj MemFileDir.obj VirtFiles.obj 
	FDInstall.obj ET.obj Core.Bin=>Native.Bootfile
	Install.Oberon.Text=>Oberon.Text Install.Tool 
~ 

FDInstall.FileToFloppy oberon0.dsk ~
