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

MODULE VirtFiles;	(** portable *)  (* pjm *)

(* Virtual Files for installation program *)

	IMPORT FileDir := VirtFileDir, SYSTEM, Disk := VirtDisk, Kernel;

(** The Files module implements the Oberon file system. *)

	(*A file consists of a sequence of pages. The first page
		contains the header. Part of the header is the page table, an array
		of disk addresses to the pages. A file is referenced through riders.
		A rider indicates a current position and refers to a file*)

	CONST MaxBufs    = 8;
				HS         = FileDir.HeaderSize;
				SS         = FileDir.SectorSize;
				STS        = FileDir.SecTabSize;
				XS         = FileDir.IndexSize;
				InitHint = 200*29;

	TYPE  DiskAdr = LONGINT;
				File*   = POINTER TO Handle;	(** file descriptor *)
				Buffer   = POINTER TO BufferRecord;

				FileHd  = POINTER TO FileDir.FileHeader;
				Index  = POINTER TO IndexRecord;

		Rider* = RECORD 	(** Riders are the access mechanisms for files. *)
				eof*: BOOLEAN;	(** Rider has reached the end of the file. *)
				res*: LONGINT;	(** Rider operation result code. *)
				file: File;
				apos, bpos: INTEGER;
				buf: Buffer
			END ;

		Handle =
			RECORD
				next: File;
				aleng, bleng: INTEGER;
				nofbufs: INTEGER;
				modH, registered: BOOLEAN;
				firstbuf: Buffer;
				sechint: DiskAdr;
				name: FileDir.FileName;
				time, date: LONGINT;
				ext:  ARRAY FileDir.ExTabSize OF Index;
				sec: FileDir.SectorTable
			END ;

		BufferRecord =
			RECORD apos, lim: INTEGER;
				mod: BOOLEAN;
				next: Buffer;
				data: FileDir.DataSector
			END ;

		IndexRecord =
			RECORD adr: DiskAdr;
				mod: BOOLEAN;
				sec: FileDir.IndexSector
			END ;
		
		Bytes4 = ARRAY 4 OF SYSTEM.BYTE;
		Bytes8 = ARRAY 8 OF SYSTEM.BYTE;

		(*aleng * SS + bleng = length (including header)
			apos * SS + bpos = current position
			0 <= bpos <= lim <= SS
			0 <= apos <= aleng < PgTabSize
			(apos < aleng) & (lim = SS) OR (apos = aleng) *)

	VAR root: File;  (*list of open files with dummy first node*)

	(* Copy - Copy size bytes from source to dest.  (No overlap allowed) *)
	
	PROCEDURE Copy(source, dest, size: LONGINT);
	CODE {SYSTEM.i386}
		MOV ESI, source[EBP]
		MOV EDI, dest[EBP]
		MOV ECX, size[EBP]
		CLD
		CMP ECX, 8
		JB bytemove
		XOR EAX, EAX
		SHRD EAX, ESI, 2
		JZ copyd
		TEST EDI, 3
		JZ copyd
		SHRD EAX, EDI, 2
		SHR EAX, 28
		CMP AL, 10
		JZ mov2
		CMP AL, 5
		JZ mov3
		NOT AL
		AND AL, 5
		JNZ copyd
		MOVSB
		DEC ECX
		JMP copyd
	mov3:
		MOVSB
		DEC ECX
	mov2:
		MOVSW
		SUB ECX, 2
	copyd:
		SHRD EAX, ECX, 2
		SHR ECX, 2
		REP MOVSD
		SHLD ECX, EAX, 2
	bytemove:
		REP MOVSB
	END Copy;

	PROCEDURE -CoreHalt(n: LONGINT);
	CODE {SYSTEM.i386}
		INT 3
	END CoreHalt;

	PROCEDURE Check(VAR s: ARRAY OF CHAR;
											VAR name: FileDir.FileName; VAR res: INTEGER);
		VAR i: INTEGER; ch: CHAR;
	BEGIN ch := s[0]; i := 0;
		IF ("A" <= CAP(ch)) & (CAP(ch) <= "Z") THEN
			LOOP name[i] := ch; INC(i); ch := s[i];
				IF ch = 0X THEN
					WHILE i < FileDir.FnLength DO name[i] := 0X; INC(i) END ;
					res := 0; EXIT
				END ;
				IF ~(("A" <= CAP(ch)) & (CAP(ch) <= "Z")
					OR ("0" <= ch) & (ch <= "9") OR (ch = ".")) THEN res := 3; EXIT
				END ;
				IF i = FileDir.FnLength THEN res := 4; EXIT END ;
			END
		ELSIF ch = 0X THEN name[0] := 0X; res := -1
		ELSE res := 3
		END
	END Check;

	PROCEDURE *Cleanup(f: SYSTEM.PTR);
	VAR prev, cur: File;
	BEGIN
		WITH f: File DO
			prev := root;  cur := root.next;
			WHILE cur # NIL DO
				IF cur = f THEN
					prev.next := cur.next
				ELSE
					prev := cur
				END;
				cur := cur.next
			END
		END
	END Cleanup;
	
(** Creates a new file with the specified name. *)
	PROCEDURE New*(name: ARRAY OF CHAR): File;
		VAR i, res: INTEGER;
			f: File;
			buf: Buffer;
			head: FileHd;
			namebuf: FileDir.FileName;
	BEGIN f := NIL; Check(name, namebuf, res);
		IF res <= 0 THEN
			NEW(buf); buf.apos := 0; buf.mod := TRUE; buf.lim := HS; buf.next := buf;
			head := SYSTEM.VAL(FileHd, SYSTEM.ADR(buf.data));
			head.mark := FileDir.HeaderMark;
			head.aleng := 0; head.bleng := HS; head.name := namebuf;
			Kernel.GetClock(head.time, head.date);
			NEW(f); f.aleng := 0; f.bleng := HS; f.modH := TRUE;
			f.time := head.time; f.date := head.date;
			f.firstbuf := buf; f.nofbufs := 1; f.name := namebuf; f.sechint := InitHint;
			f.registered := (f.name[0] = 0X);
			i := 0;
			REPEAT f.ext[i] := NIL; head.ext[i] := 0; INC(i) UNTIL i = FileDir.ExTabSize;
			i := 0;
			REPEAT f.sec[i] := 0; head.sec[i] := 0; INC(i) UNTIL i = STS;
			Kernel.RegisterObject(f, Cleanup, FALSE)
		END ;
		RETURN f
	END New;

	PROCEDURE UpdateHeader(f: File; VAR h: FileDir.FileHeader);
		VAR k: INTEGER;
	BEGIN h.aleng := f.aleng; h.bleng := f.bleng;
		h.sec := f.sec; k := (f.aleng + (XS-STS)) DIV XS;
		WHILE k > 0 DO DEC(k); h.ext[k] := f.ext[k].adr END;
		h.date := f.date; h.time := f.time
	END UpdateHeader;

	PROCEDURE ReadBuf(f: File; buf: Buffer; pos: INTEGER);
		VAR sec: DiskAdr;
	BEGIN
		IF pos < STS THEN sec := f.sec[pos]
		ELSE sec := f.ext[(pos-STS) DIV XS].sec.x[(pos-STS) MOD XS]
		END ;
		Disk.GetSector(sec, buf.data);
		IF pos < f.aleng THEN buf.lim := SS ELSE buf.lim := f.bleng END ;
		buf.apos := pos; buf.mod := FALSE
	END ReadBuf;

	PROCEDURE WriteBuf(f: File; buf: Buffer);
		VAR i, k: INTEGER;
			secadr: DiskAdr; inx: Index;
	BEGIN
		Kernel.GetClock(f.time, f.date);  f.modH := TRUE;
		IF buf.apos < STS THEN
			secadr := f.sec[buf.apos];
			IF secadr = 0 THEN
				Disk.AllocSector(f.sechint, secadr);
				f.modH := TRUE; f.sec[buf.apos] := secadr; f.sechint := secadr
			END ;
			IF buf.apos = 0 THEN
				UpdateHeader(f, SYSTEM.VAL(FileDir.FileHeader, buf.data)); f.modH := FALSE
			END
		ELSE i := (buf.apos - STS) DIV XS; inx := f.ext[i];
			IF inx = NIL THEN
				NEW(inx); inx.adr := 0; inx.sec.x[0] := 0; f.ext[i] := inx; f.modH := TRUE
			END ;
			k := (buf.apos - STS) MOD XS; secadr := inx.sec.x[k];
			IF secadr = 0 THEN
				Disk.AllocSector(f.sechint, secadr);
				f.modH := TRUE; inx.mod := TRUE; inx.sec.x[k] := secadr; f.sechint := secadr
			END
		END ;
		Disk.PutSector(secadr, buf.data); buf.mod := FALSE
	END WriteBuf;

	PROCEDURE Buf(f: File; pos: INTEGER): Buffer;
		VAR buf: Buffer;
	BEGIN buf := f.firstbuf;
		LOOP
			IF buf.apos = pos THEN EXIT END ;
			buf := buf.next;
			IF buf = f.firstbuf THEN buf := NIL; EXIT END
		END ;
		RETURN buf
	END Buf;

	PROCEDURE GetBuf(f: File; pos: INTEGER): Buffer;
		VAR buf: Buffer;
	BEGIN buf := f.firstbuf;
		LOOP
			IF buf.apos = pos THEN EXIT END ;
			IF buf.next = f.firstbuf THEN
				IF f.nofbufs < MaxBufs THEN (*allocate new buffer*)
					NEW(buf); buf.next := f.firstbuf.next; f.firstbuf.next := buf;
					INC(f.nofbufs)
				ELSE (*take one of the buffers*) f.firstbuf := buf;
					IF buf.mod THEN WriteBuf(f, buf) END
				END ;
				buf.apos := pos;
				IF pos <= f.aleng THEN ReadBuf(f, buf, pos) END ;
				EXIT
			END ;
			buf := buf.next
		END ;
		RETURN buf
	END GetBuf;

(** Open an existing file. The same file descriptor is returned if a file is opened multiple times. *)
	PROCEDURE Old*(name: ARRAY OF CHAR): File;
		VAR i, k, res: INTEGER;
			f: File;
			header: DiskAdr;
			buf: Buffer;
			head: FileHd;
			namebuf: FileDir.FileName;
			inxpg: Index;
	BEGIN f := NIL; Check(name, namebuf, res);
		IF res = 0 THEN
			FileDir.Search(namebuf, header);
			IF header # 0 THEN f := root.next;
				WHILE (f # NIL) & (f.sec[0] # header) DO f := f.next END ;
				IF f = NIL THEN
					NEW(buf); buf.apos := 0; buf.next := buf; buf.mod := FALSE;
					
					Disk.GetSector(header, buf.data);
					head := SYSTEM.VAL(FileHd, SYSTEM.ADR(buf.data));

					NEW(f); f.aleng := head.aleng; f.bleng := head.bleng;
					f.time := head.time; f.date := head.date;
					IF f.aleng = 0 THEN buf.lim := f.bleng ELSE buf.lim := SS END ;
					f.firstbuf := buf; f.nofbufs := 1;
					f.name := namebuf;  f.registered := TRUE;
					f.sec := head.sec;
					k := (f.aleng + (XS-STS)) DIV XS; i := 0;
					WHILE i < k DO
						NEW(inxpg); inxpg.adr := head.ext[i]; inxpg.mod := FALSE;
						Disk.GetSector(inxpg.adr, inxpg.sec); f.ext[i] := inxpg; INC(i)
					END ;
					WHILE i < FileDir.ExTabSize DO f.ext[i] := NIL; INC(i) END ;
					f.sechint := header; f.modH := FALSE; f.next := root.next; 
					root.next := f;
					Kernel.RegisterObject(f, Cleanup, FALSE)
				END
			END
		END ;
		RETURN f
	END Old;

	PROCEDURE Unbuffer(f: File);
		VAR i, k: INTEGER;
			buf: Buffer;
			inx: Index;
			head: FileDir.FileHeader;
	BEGIN buf := f.firstbuf;
		REPEAT
			IF buf.mod THEN WriteBuf(f, buf) END ;
			buf := buf.next
		UNTIL buf = f.firstbuf;
		k := (f.aleng + (XS-STS)) DIV XS; i := 0;
		WHILE i < k DO
			inx := f.ext[i]; INC(i);
			IF inx.mod THEN
				IF inx.adr = 0 THEN
					Disk.AllocSector(f.sechint, inx.adr); f.sechint := inx.adr; f.modH := TRUE
				END ;
				Disk.PutSector(inx.adr, inx.sec); inx.mod := FALSE
			END
		END ;
		IF f.modH THEN
			Disk.GetSector(f.sec[0], head); UpdateHeader(f, head);
			Disk.PutSector(f.sec[0], head); f.modH := FALSE
		END
	END Unbuffer;

(** Register a file created with New in the directory, replacing the previous file in the 
directory with the same name. The file is automatically closed. *)
	PROCEDURE Register*(f: File);
	BEGIN
		IF f # NIL THEN
			Unbuffer(f);
			IF ~f.registered & (f.name # "") THEN
				FileDir.Insert(f.name, f.sec[0]); f.registered := TRUE;
				f.next := root.next; root.next := f
			END
		END
	END Register;

(** Flushes the changes made to a file to disk. Register will automatically Close a file. *) 
	PROCEDURE Close*(f: File);
	BEGIN
		IF f # NIL THEN Unbuffer(f) END
	END Close;

(*
(* Special operation to delete a file immediately.  It is the caller's responsibility to ensure that no 
other references exist to the file.  The normal way to delete is file is to use the Delete operation. *)
	PROCEDURE Purge(f: File);
		VAR a, i, j, k: INTEGER;
			ind: FileDir.IndexSector;
	BEGIN
		IF f # NIL THEN a := f.aleng + 1; f.aleng := 0; f.bleng := HS;
			IF a <= STS THEN i := a
			ELSE i := STS; DEC(a, i);
				j := a MOD XS; k := a DIV XS;
				WHILE k >= 0 DO
					Disk.GetSector(f.ext[k].adr, ind);
					REPEAT DEC(j); Disk.FreeSector(ind.x[j])
					UNTIL j = 0;
					Disk.FreeSector(f.ext[k].adr); j := XS; DEC(k)
				END
			END ;
			REPEAT DEC(i); Disk.FreeSector(f.sec[i]); f.sec[i] := 0
			UNTIL i = 0;
			f.nofbufs := 1; f.firstbuf.next := NIL; f.modH := TRUE
		END
	END Purge;
*)

(** Returns the current length of a file. *)
	PROCEDURE Length*(f: File): LONGINT;
	BEGIN RETURN LONG(f.aleng)*SS + f.bleng - HS
	END Length;

(** Returns the time (t) and date (d) when a file was last modified. *)
	PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);
	BEGIN t := f.time; d := f.date
	END GetDate;

(** Sets the modification time (t) and date (d) of a file. *)
	PROCEDURE SetDate*(f: File; t, d: LONGINT);
	BEGIN f.modH := TRUE; f.time := t; f.date := d
	END SetDate;

(** Positions a Rider at a certain position in a file. Multiple Riders can be positioned 
at different locations in a file. A Rider cannot be positioned beyond the end of a file. *)
	PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);
		VAR a, b: INTEGER;
	BEGIN  r.eof := FALSE; r.res := 0;
		IF f # NIL THEN
			IF pos < 0 THEN a := 0; b := HS
			ELSIF pos < LONG(f.aleng)*SS + f.bleng - HS THEN
				a := SHORT((pos + HS) DIV SS); b := SHORT((pos + HS) MOD SS);
			ELSE a := f.aleng; b := f.bleng
			END ;
			r.file := f; r.apos := a; r.bpos := b; r.buf := f.firstbuf
		ELSE r.file:= NIL
		END
	END Set;

(** Returns the offset of a Rider positioned on a file. *)
	PROCEDURE Pos*(VAR r: Rider): LONGINT;
	BEGIN RETURN LONG(r.apos)*SS + r.bpos - HS
	END Pos;

(** Returns the File a Rider is based on. *)
	PROCEDURE Base*(VAR r: Rider): File;
	BEGIN RETURN r.file
	END Base;

(** Read a byte from a file, advancing the Rider one byte further.  R.eof indicates if the end 
of the file has been passed. *)
	PROCEDURE Read*(VAR r: Rider; VAR x: SYSTEM.BYTE);
		VAR buf: Buffer;
	BEGIN
		IF r.apos # r.buf.apos THEN r.buf := GetBuf(r.file, r.apos) END ;
		IF r.bpos < r.buf.lim THEN
			x := r.buf.data.B[r.bpos]; INC(r.bpos)
		ELSIF r.apos < r.file.aleng THEN
			INC(r.apos);
			buf := Buf(r.file, r.apos);
			IF buf = NIL THEN
				IF r.buf.mod THEN WriteBuf(r.file, r.buf) END ;
				ReadBuf(r.file, r.buf, r.apos)
			ELSE r.buf := buf END ;
			x := r.buf.data.B[0]; r.bpos := 1
		ELSE
			x := 0X; r.eof := TRUE
		END
	END Read;

(** Reads a sequence of length n bytes into the buffer x, advancing the Rider. Less bytes 
will be read when reading over the length of the file. r.res indicates the number of unread bytes. 
x must be big enough to hold n bytes. *)
	PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
		VAR src, dst, m: LONGINT; buf: Buffer;
	BEGIN dst := SYSTEM.ADR(x[0]);
		IF LEN(x) < n THEN CoreHalt(19) END ;
		IF r.apos # r.buf.apos THEN r.buf := GetBuf(r.file, r.apos) END ;
		LOOP
			IF n <= 0 THEN EXIT END ;
			src := SYSTEM.ADR(r.buf.data.B[0]) + r.bpos; m := r.bpos + n;
			IF m <= r.buf.lim THEN
				Copy(src, dst, n); r.bpos := SHORT(m); r.res := 0; EXIT
			ELSIF r.buf.lim = SS THEN
				m := r.buf.lim - r.bpos;
				IF m > 0 THEN Copy(src, dst, m); INC(dst, m); DEC(n, m) END ;
				IF r.apos < r.file.aleng THEN
					INC(r.apos); r.bpos := 0; buf := Buf(r.file, r.apos);
					IF buf = NIL THEN
						IF r.buf.mod THEN WriteBuf(r.file, r.buf) END ;
						ReadBuf(r.file, r.buf, r.apos)
					ELSE r.buf := buf
					END
				ELSE r.res := n; r.eof := TRUE; EXIT
				END
			ELSE m := r.buf.lim - r.bpos;
				IF m > 0 THEN Copy(src, dst, m); r.bpos := r.buf.lim END ;
				r.res := n - m; r.eof := TRUE; EXIT
			END
		END
	END ReadBytes;

(**
Portable routines to read the standard Oberon types.
*)

	PROCEDURE ReadInt*(VAR R: Rider; VAR x: INTEGER);
		VAR x0, x1: SHORTINT;
	BEGIN Read(R, x0); Read(R, x1);
		x := LONG(x1) * 100H + LONG(x0) MOD 100H
	END ReadInt;

	PROCEDURE ReadLInt*(VAR R: Rider; VAR x: LONGINT);
	BEGIN ReadBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END ReadLInt;

	PROCEDURE ReadSet*(VAR R: Rider; VAR x: SET);
	BEGIN ReadBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END ReadSet;

	PROCEDURE ReadBool*(VAR R: Rider; VAR x: BOOLEAN);
		VAR s: SHORTINT;
	BEGIN Read(R, s); x := s # 0
	END ReadBool;

	PROCEDURE ReadReal*(VAR R: Rider; VAR x: REAL);
	BEGIN ReadBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END ReadReal;

	PROCEDURE ReadLReal*(VAR R: Rider; VAR x: LONGREAL);
	BEGIN ReadBytes(R, SYSTEM.VAL(Bytes8, x), 8)
	END ReadLReal;

	PROCEDURE ReadString*(VAR R: Rider; VAR x: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN i := 0;
		LOOP
			Read(R, ch); x[i] := ch; INC(i);
			IF ch = 0X THEN EXIT END;
			IF i = LEN(x) THEN x[i-1] := 0X;
				REPEAT Read(R, ch) UNTIL ch = 0X;
				EXIT
			END
		END
	END ReadString;

(** Reads a number in compressed variable length notation using the minimum amount of bytes. *)
	PROCEDURE ReadNum*(VAR R: Rider; VAR x: LONGINT);
		VAR ch: CHAR; n: INTEGER; y: LONGINT;
	BEGIN n := 0; y := 0; Read(R, ch);
		WHILE ch >= 80X DO INC(y, SYSTEM.LSH(LONG(ch) - 128, n)); INC(n, 7); Read(R, ch) END;
		x := ASH(SYSTEM.LSH(LONG(ch), 25), n-25) + y
	END ReadNum;

	PROCEDURE NewExt(f: File);
		VAR i, k: INTEGER; ext: Index;
	BEGIN k := (f.aleng - STS) DIV XS;
		IF k = FileDir.ExTabSize THEN CoreHalt(18) END ;
		NEW(ext); ext.adr := 0; ext.mod := TRUE; f.ext[k] := ext; i := XS;
		REPEAT DEC(i); ext.sec.x[i] := 0 UNTIL i = 0
	END NewExt;

(** Writes a byte into the file at the Rider position, advancing the Rider by one. *)
	PROCEDURE Write*(VAR r: Rider; x: SYSTEM.BYTE);
		VAR f: File; buf: Buffer;
	BEGIN
		IF r.apos # r.buf.apos THEN r.buf := GetBuf(r.file, r.apos) END ;
		IF r.bpos >= r.buf.lim THEN
			IF r.bpos < SS THEN
				INC(r.buf.lim); INC(r.file.bleng); r.file.modH := TRUE
			ELSE f := r.file; WriteBuf(f, r.buf); INC(r.apos); buf := Buf(r.file, r.apos);
				IF buf = NIL THEN
					IF r.apos <= f.aleng THEN ReadBuf(f, r.buf, r.apos)
					ELSE r.buf.apos := r.apos; r.buf.lim := 1; INC(f.aleng); f.bleng := 1; f.modH := TRUE;
						IF (f.aleng - STS) MOD XS = 0 THEN NewExt(f) END
					END
				ELSE r.buf := buf
				END ;
				r.bpos := 0
			END
		END ;
		r.buf.data.B[r.bpos] := x; INC(r.bpos); r.buf.mod := TRUE
	END Write;

(** Writes the buffer x containing n bytes into a file at the Rider position. *)
	PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
		VAR src, dst, m: LONGINT; f: File; buf: Buffer;
	BEGIN src := SYSTEM.ADR(x[0]);
		IF LEN(x) < n THEN CoreHalt(19) END ;
		IF r.apos # r.buf.apos THEN r.buf := GetBuf(r.file, r.apos) END ;
		LOOP
			IF n <= 0 THEN EXIT END ;
			r.buf.mod := TRUE; dst := SYSTEM.ADR(r.buf.data.B[0]) + r.bpos; m := r.bpos + n;
			IF m <= r.buf.lim THEN
				Copy(src, dst, n); r.bpos := SHORT(m); EXIT
			ELSIF m <= SS THEN
				Copy(src, dst, n); r.bpos := SHORT(m);
				r.file.bleng := SHORT(m); r.buf.lim := SHORT(m); r.file.modH := TRUE; EXIT
			ELSE m := SS - r.bpos;
				IF m > 0 THEN Copy(src, dst, m); INC(src, m); DEC(n, m) END ;
				f := r.file; WriteBuf(f, r.buf); INC(r.apos); r.bpos := 0; buf := Buf(f, r.apos);
				IF buf = NIL THEN
					IF r.apos <= f.aleng THEN ReadBuf(f, r.buf, r.apos)
					ELSE r.buf.apos := r.apos; r.buf.lim := 0; INC(f.aleng); f.bleng := 0; f.modH := TRUE;
						IF (f.aleng - STS) MOD XS = 0 THEN NewExt(f) END
					END
				ELSE r.buf := buf
				END
			END
		END
	END WriteBytes;

(**
Portable routines to write the standard Oberon types.
*)

	PROCEDURE WriteInt*(VAR R: Rider; x: INTEGER);
	BEGIN Write(R, SHORT(x)); Write(R, SHORT(x DIV 100H))
	END WriteInt;

	PROCEDURE WriteLInt*(VAR R: Rider; x: LONGINT);
	BEGIN WriteBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END WriteLInt;

	PROCEDURE WriteSet*(VAR R: Rider; x: SET);
	BEGIN WriteBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END WriteSet;

	PROCEDURE WriteBool*(VAR R: Rider; x: BOOLEAN);
	BEGIN
		IF x THEN Write(R, 1) ELSE Write(R, 0) END
	END WriteBool;

	PROCEDURE WriteReal*(VAR R: Rider; x: REAL);
	BEGIN WriteBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END WriteReal;

	PROCEDURE WriteLReal*(VAR R: Rider; x: LONGREAL);
	BEGIN WriteBytes(R, SYSTEM.VAL(Bytes8, x), 8)
	END WriteLReal;

	PROCEDURE WriteString*(VAR R: Rider; x: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN i := 0;
		LOOP ch := x[i]; Write(R, ch); INC(i);
			IF ch = 0X THEN EXIT END;
			IF i = LEN(x) THEN Write(R, 0X); EXIT END
		END
	END WriteString;

(** Writes a number in a compressed format. *)
	PROCEDURE WriteNum*(VAR R: Rider; x: LONGINT);
	BEGIN
		WHILE (x < - 64) OR (x > 63) DO Write(R, CHR(x MOD 128 + 128)); x := x DIV 128 END;
		Write(R, CHR(x MOD 128))
	END WriteNum;

(** Deletes a file. res = 0 indicates success. *)
	PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
		VAR adr: DiskAdr;  namebuf: FileDir.FileName;  head: FileDir.FileHeader;
	BEGIN Check(name, namebuf, res);
		IF res = 0 THEN
			FileDir.Delete(namebuf, adr);
			IF adr # 0 THEN
				Disk.GetSector(adr, head); head.mark := FileDir.HeaderMark+1; Disk.PutSector(adr, head)
			ELSE
				res := 2
			END
		END
	END Delete;

(** Renames a file. res = 0 indicates success. *)
	PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
		VAR adr: DiskAdr;
				oldbuf, newbuf: FileDir.FileName;
				head: FileDir.FileHeader;
				f: File;
	BEGIN Check(old, oldbuf, res);
		IF res = 0 THEN
			Check(new, newbuf, res);
			IF res = 0 THEN
				FileDir.Delete(oldbuf, adr);
				IF adr # 0 THEN
					f := root.next;  WHILE (f # NIL) & (f.sec[0] # adr) DO f := f.next END;
					IF f # NIL THEN f.name := newbuf END;
					FileDir.Insert(newbuf, adr);
					Disk.GetSector(adr, head); head.name := newbuf; Disk.PutSector(adr, head)
				ELSE res := 2
				END
			END
		END
	END Rename;

(** Returns the full name of a file. *)

PROCEDURE GetName*(F: File;  VAR name: ARRAY OF CHAR);
BEGIN
	COPY(F.name, name)
END GetName;

PROCEDURE Init*;
BEGIN
	FileDir.Init;
	root.next := NIL
END Init;

BEGIN
	NEW(root);
	Kernel.DisableTracing(SYSTEM.ADR(root^), SYSTEM.ADR(root.next))
END VirtFiles.

(** Remarks:

1. Oberon uses the little-endian byte ordering for exchanging files between different Oberon platforms.

2. Files are separate entities from directory entries. Files may be anonymous by having no name and not being registered in a
	directory. Files only become visible to other clients of the Files module by explicitly passing a File descriptor or by registering
	a file and then opening it from the other client. Deleting a file of which a file descriptor is still available, results in the file
	becoming anonymous. The deleted file may be re-registered at any time.

3. Files and their access mechanism (Riders) are separated. A file might have more than one rider operating on it at different
	offsets in the file.

4. The garbage collector will automatically close files when they are not required any more. File buffers will be discarded
	without flushing them to disk.  Use the Close procedure to update modified files on disk.

5. Relative and absolute filenames written in the directory syntax of the host operating system are used. By convention, Oberon
	filenames consists of the letters A..Z, a..z, 0..9, and ".". The directory separator is typically / or :. Oberon filenames are
	case sensitive. *)
