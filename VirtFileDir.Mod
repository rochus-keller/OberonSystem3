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

MODULE VirtFileDir; (** non-portable *)   (* pjm *)
	IMPORT SYSTEM, Disk := VirtDisk, Kernel;

(* FileDir for installation program - Startup/Cleanup removed and Init simplified. *)

(** The FileDir module implements the naming of files in directories. *)

	(*File Directory is a B-tree with its root page at DirRootAdr.
		Each entry contains a file name and the disk address of the file's head sector*)

	CONST FnLength*    = 32;
				SecTabSize*   = 64;
				ExTabSize*   = 12;
				SectorSize*   = 2048;	(* Disk.SectorSize *)
				IndexSize*   = SectorSize DIV 4;
				HeaderSize*  = 352;
				DirRootAdr*  = 29;
				DirPgSize*   = 50;
				N = DirPgSize DIV 2;
				DirMark*    = 9B1EA38DH;
				HeaderMark* = 9BA71D86H;
				FillerSize = 36;
				MapIndexSize = (SectorSize-4) DIV 4;
				MapSize = SectorSize DIV 4;	(* {MapSize MOD 32 = 0} *)
				MapMark = 9C2F977FH;

	TYPE
		DiskAdr      = LONGINT;
		FileName*       = ARRAY FnLength OF CHAR;
		SectorTable*    = ARRAY SecTabSize OF DiskAdr;
		ExtensionTable* = ARRAY ExTabSize OF DiskAdr;
(* An EntryHandler is used by the Enumerate operation.  name contains the name of the file.
time, date and size are only used if the detail flag was specified in Enumerate.  continue may
be set to FALSE to stop the Enumerate operation mid-way. *)
		EntryHandler* = PROCEDURE (name: ARRAY OF CHAR; time, date, size: LONGINT; VAR continue: BOOLEAN);

		FileHeader* =
			RECORD (Disk.Sector)   (*allocated in the first page of each file on disk*)
				mark*: LONGINT;
				name*: FileName;
				aleng*, bleng*: INTEGER;
				date*, time*: LONGINT;
				ext*:  ExtensionTable;
				sec*: SectorTable;
				fill: ARRAY SectorSize - HeaderSize OF CHAR;
			END ;

		IndexSector* =
			RECORD (Disk.Sector)
				x*: ARRAY IndexSize OF DiskAdr
			END ;

		DataSector* =
			RECORD (Disk.Sector)
				B*: ARRAY SectorSize OF SYSTEM.BYTE
			END ;

		DirEntry* =  (*B-tree node*)
			RECORD
				name*: FileName;
				adr*:  DiskAdr; (*sec no of file header*)
				p*:    DiskAdr  (*sec no of descendant in directory*)
			END ;

		DirPage*  =
			RECORD (Disk.Sector)
				mark*:  LONGINT;
				m*:     INTEGER;
				p0*:    DiskAdr;  (*sec no of left descendant in directory*)
				fill:  ARRAY FillerSize OF CHAR;
				e*:  ARRAY DirPgSize OF DirEntry
			END ;

		MapIndex = 
			RECORD (Disk.Sector)
				mark: LONGINT;
				index: ARRAY MapIndexSize OF DiskAdr
			END ;
			
		MapSector =
			RECORD (Disk.Sector)
				map: ARRAY MapSize OF SET
			END ;
			
	VAR
		prefix*: ARRAY 10 OF CHAR;
		PathChar*: CHAR;
		pat: ARRAY 32 OF CHAR;
		pos: INTEGER;
		init: BOOLEAN;
		hp: POINTER TO FileHeader;	(* ptr so as not to take inner core space *)

	PROCEDURE AddStr(s1, s2: ARRAY OF CHAR;  VAR s3: ARRAY OF CHAR);
		VAR i, j, l: LONGINT;
	BEGIN j := 0; l := LEN(s3)-1; i := 0;
		WHILE (s1[i] # 0X) & (j # l) DO s3[j] := s1[i]; INC(i); INC(j) END;
		i := 0;
		WHILE (s2[i] # 0X) & (j # l) DO s3[j] := s2[i]; INC(i); INC(j) END;
		s3[j] := 0X
	END AddStr;

	(*Exported procedures: Search, Insert, Delete, Enumerate, Init*)

	PROCEDURE Search*(VAR name: FileName; VAR A: DiskAdr);
		VAR i, L, R: INTEGER; dadr: DiskAdr;
			a: DirPage; n: FileName; first: BOOLEAN;
	BEGIN IF ~init THEN HALT(99) END; first := TRUE;
		LOOP
			IF first THEN AddStr(prefix, name, n) ELSE COPY(name, n) END;
			dadr := DirRootAdr;
			LOOP Disk.GetSector(dadr, a);
				L := 0; R := a.m; (*binary search*)
				WHILE L < R DO
					i := (L+R) DIV 2;
					IF n <= a.e[i].name THEN R := i ELSE L := i+1 END
				END ;
				IF (R < a.m) & (n = a.e[R].name) THEN
					A := a.e[R].adr; EXIT (*found*)
				END ;
				IF R = 0 THEN dadr := a.p0 ELSE dadr := a.e[R-1].p END ;
				IF dadr = 0 THEN A := 0; EXIT  (*not found*) END
			END;
			IF (A # 0) OR ~first OR (prefix = "") THEN EXIT END;
			first := FALSE
		END
	END Search;

	PROCEDURE insert(VAR name: FileName;
									 dpg0:  DiskAdr;
									 VAR h: BOOLEAN;
									 VAR v: DirEntry;
									 fad:     DiskAdr);
		(*h = "tree has become higher and v is ascending element"*)
		VAR ch: CHAR;
			i, j, L, R: INTEGER;
			dpg1: DiskAdr;
			u: DirEntry;
			a: DirPage;

	BEGIN (*~h*) Disk.GetSector(dpg0, a);
		L := 0; R := a.m; (*binary search*)
		WHILE L < R DO
			i := (L+R) DIV 2;
			IF name <= a.e[i].name THEN R := i ELSE L := i+1 END
		END ;
		IF (R < a.m) & (name = a.e[R].name) THEN
			a.e[R].adr := fad; Disk.PutSector(dpg0, a)  (*replace*)
		ELSE (*not on this page*)
			IF R = 0 THEN dpg1 := a.p0 ELSE dpg1 := a.e[R-1].p END ;
			IF dpg1 = 0 THEN (*not in tree, insert*)
				u.adr := fad; u.p := 0; h := TRUE; j := 0;
				REPEAT ch := name[j]; u.name[j] := ch; INC(j)
				UNTIL ch = 0X;
				WHILE j < FnLength DO u.name[j] := 0X; INC(j) END
			ELSE
				insert(name, dpg1, h, u, fad)
			END ;
			IF h THEN (*insert u to the left of e[R]*)
				IF a.m < DirPgSize THEN
					h := FALSE; i := a.m;
					WHILE i > R DO DEC(i); a.e[i+1] := a.e[i] END ;
					a.e[R] := u; INC(a.m)
				ELSE (*split page and assign the middle element to v*)
					a.m := N; a.mark := DirMark;
					IF R < N THEN (*insert in left half*)
						v := a.e[N-1]; i := N-1;
						WHILE i > R DO DEC(i); a.e[i+1] := a.e[i] END ;
						a.e[R] := u; Disk.PutSector(dpg0, a);
						Disk.AllocSector(dpg0, dpg0); i := 0;
						WHILE i < N DO a.e[i] := a.e[i+N]; INC(i) END
					ELSE (*insert in right half*)
						Disk.PutSector(dpg0, a);
						Disk.AllocSector(dpg0, dpg0); DEC(R, N); i := 0;
						IF R = 0 THEN v := u
						ELSE v := a.e[N];
							WHILE i < R-1 DO a.e[i] := a.e[N+1+i]; INC(i) END ;
							a.e[i] := u; INC(i)
						END ;
						WHILE i < N DO a.e[i] := a.e[N+i]; INC(i) END
					END ;
					a.p0 := v.p; v.p := dpg0
				END ;
				Disk.PutSector(dpg0, a)
			END
		END
	END insert;

	PROCEDURE Insert*(VAR name: FileName; fad: DiskAdr);
		VAR  oldroot: DiskAdr;
			h: BOOLEAN; U: DirEntry;
			a: DirPage; n: FileName;
	BEGIN IF ~init THEN HALT(99) END;
		h := FALSE; AddStr(prefix, name, n);
		insert(n, DirRootAdr, h, U, fad);
		IF h THEN (*root overflow*)
			Disk.GetSector(DirRootAdr, a);
			Disk.AllocSector(DirRootAdr, oldroot); Disk.PutSector(oldroot, a);
			a.mark := DirMark; a.m := 1; a.p0 := oldroot; a.e[0] := U;
			Disk.PutSector(DirRootAdr, a)
		END
	END Insert;


	PROCEDURE underflow(VAR c: DirPage;  (*ancestor page*)
											dpg0:  DiskAdr;
											s:     INTEGER;  (*insertion point in c*)
											VAR h: BOOLEAN); (*c undersize*)
		VAR i, k: INTEGER;
				dpg1: DiskAdr;
				a, b: DirPage;  (*a := underflowing page, b := neighbouring page*)
	BEGIN Disk.GetSector(dpg0, a);
		(*h & a.m = N-1 & dpg0 = c.e[s-1].p*)
		IF s < c.m THEN (*b := page to the right of a*)
			dpg1 := c.e[s].p; Disk.GetSector(dpg1, b);
			k := (b.m-N+1) DIV 2; (*k = no. of items available on page b*)
			a.e[N-1] := c.e[s]; a.e[N-1].p := b.p0;
			IF k > 0 THEN
				(*move k-1 items from b to a, one to c*) i := 0;
				WHILE i < k-1 DO a.e[i+N] := b.e[i]; INC(i) END ;
				c.e[s] := b.e[i]; b.p0 := c.e[s].p;
				c.e[s].p := dpg1; DEC(b.m, k); i := 0;
				WHILE i < b.m DO b.e[i] := b.e[i+k]; INC(i) END ;
				Disk.PutSector(dpg1, b); a.m := N-1+k; h := FALSE
			ELSE (*merge pages a and b, discard b*) i := 0;
				WHILE i < N DO a.e[i+N] := b.e[i]; INC(i) END ;
				i := s; DEC(c.m);
				WHILE i < c.m DO c.e[i] := c.e[i+1]; INC(i) END ;
				a.m := 2*N; h := c.m < N
			END ;
			Disk.PutSector(dpg0, a)
		ELSE (*b := page to the left of a*) DEC(s);
			IF s = 0 THEN dpg1 := c.p0 ELSE dpg1 := c.e[s-1].p END ;
			Disk.GetSector(dpg1, b);
			k := (b.m-N+1) DIV 2; (*k = no. of items available on page b*)
			IF k > 0 THEN
				i := N-1;
				WHILE i > 0 DO DEC(i); a.e[i+k] := a.e[i] END ;
				i := k-1; a.e[i] := c.e[s]; a.e[i].p := a.p0;
				(*move k-1 items from b to a, one to c*) DEC(b.m, k);
				WHILE i > 0 DO DEC(i); a.e[i] := b.e[i+b.m+1] END ;
				c.e[s] := b.e[b.m]; a.p0 := c.e[s].p;
				c.e[s].p := dpg0; a.m := N-1+k; h := FALSE;
				Disk.PutSector(dpg0, a)
			ELSE (*merge pages a and b, discard a*)
				c.e[s].p := a.p0; b.e[N] := c.e[s]; i := 0;
				WHILE i < N-1 DO b.e[i+N+1] := a.e[i]; INC(i) END ;
				b.m := 2*N; DEC(c.m); h := c.m < N
			END ;
			Disk.PutSector(dpg1, b)
		END
	END underflow;

	PROCEDURE delete(VAR name: FileName;
									 dpg0: DiskAdr;
									 VAR h: BOOLEAN;
									 VAR fad: DiskAdr);
	(*search and delete entry with key name; if a page underflow arises,
		balance with adjacent page or merge; h := "page dpg0 is undersize"*)

		VAR i, L, R: INTEGER;
			dpg1: DiskAdr;
			a: DirPage;

		PROCEDURE del(dpg1: DiskAdr; VAR h: BOOLEAN);
			VAR dpg2: DiskAdr;  (*global: a, R*)
					b: DirPage;
		BEGIN Disk.GetSector(dpg1, b); dpg2 := b.e[b.m-1].p;
			IF dpg2 # 0 THEN del(dpg2, h);
				IF h THEN underflow(b, dpg2, b.m, h); Disk.PutSector(dpg1, b) END
			ELSE
				b.e[b.m-1].p := a.e[R].p; a.e[R] := b.e[b.m-1];
				DEC(b.m); h := b.m < N; Disk.PutSector(dpg1, b)
			END
		END del;

	BEGIN (*~h*) Disk.GetSector(dpg0, a);
		L := 0; R := a.m; (*binary search*)
		WHILE L < R DO
			i := (L+R) DIV 2;
			IF name <= a.e[i].name THEN R := i ELSE L := i+1 END
		END ;
		IF R = 0 THEN dpg1 := a.p0 ELSE dpg1 := a.e[R-1].p END ;
		IF (R < a.m) & (name = a.e[R].name) THEN
			(*found, now delete*) fad := a.e[R].adr;
			IF dpg1 = 0 THEN  (*a is a leaf page*)
				DEC(a.m); h := a.m < N; i := R;
				WHILE i < a.m DO a.e[i] := a.e[i+1]; INC(i) END
			ELSE del(dpg1, h);
				IF h THEN underflow(a, dpg1, R, h) END
			END ;
			Disk.PutSector(dpg0, a)
		ELSIF dpg1 # 0 THEN
			delete(name, dpg1, h, fad);
			IF h THEN underflow(a, dpg1, R, h); Disk.PutSector(dpg0, a) END
		ELSE (*not in tree*) fad := 0
		END
	END delete;

	PROCEDURE Delete*(VAR name: FileName; VAR fad: DiskAdr);
		VAR h: BOOLEAN; newroot: DiskAdr;
			a: DirPage; n: FileName;
	BEGIN IF ~init THEN HALT(99) END;
		h := FALSE; AddStr(prefix, name, n);
		delete(n, DirRootAdr, h, fad);
		IF h THEN (*root underflow*)
			Disk.GetSector(DirRootAdr, a);
			IF (a.m = 0) & (a.p0 # 0) THEN
				newroot := a.p0; Disk.GetSector(newroot, a);
				Disk.PutSector(DirRootAdr, a) (*discard newroot*)
			END
		END
	END Delete;

	PROCEDURE match(VAR name: ARRAY OF CHAR): BOOLEAN;
	VAR i0, i1, j0, j1: INTEGER;  f: BOOLEAN;
	BEGIN
		i0 := pos;  j0 := pos;  f := TRUE;
		LOOP
			IF pat[i0] = "*" THEN
				INC(i0);
				IF pat[i0] = 0X THEN EXIT END
			ELSE
				IF name[j0] # 0X THEN f := FALSE END;
				EXIT
			END;
			f := FALSE;
			LOOP
				IF name[j0] = 0X THEN EXIT END;
				i1 := i0;  j1 := j0;
				LOOP
					IF (pat[i1] = 0X) OR (pat[i1] = "*") THEN f := TRUE; EXIT END;
					IF pat[i1] # name[j1] THEN EXIT END;
					INC(i1);  INC(j1)
				END;
				IF f THEN j0 := j1; i0 := i1; EXIT END;
				INC(j0)
			END;
			IF ~f THEN EXIT END
		END;
		RETURN f & (name[0] # 0X)
	END match;

	PROCEDURE enumerate(VAR prefix:   ARRAY OF CHAR;
											dpg:          DiskAdr;
											detail: BOOLEAN;
											proc:         EntryHandler;
											VAR continue: BOOLEAN);
		VAR i, j, diff: INTEGER; dpg1: DiskAdr;
				a: DirPage;  time, date, size: LONGINT;
	BEGIN Disk.GetSector(dpg, a); i := 0;
		WHILE (i < a.m) & continue DO
			j := 0;
			LOOP
				IF prefix[j] = 0X THEN diff := 0; EXIT END ;
				diff := ORD(a.e[i].name[j]) - ORD(prefix[j]);
				IF diff # 0 THEN EXIT END ;
				INC(j)
			END ;
			IF i = 0 THEN dpg1 := a.p0 ELSE dpg1 := a.e[i-1].p END ;
			IF diff >= 0 THEN (*matching prefix*)
				IF dpg1 # 0 THEN enumerate(prefix, dpg1, detail, proc, continue) END ;
				IF diff = 0 THEN
					IF continue & ((pos = -1) OR match(a.e[i].name)) THEN
						IF detail THEN
							Disk.GetSector(a.e[i].adr, hp^);
							time := hp.time;  date := hp.date;
							size := LONG(hp.aleng)*SectorSize + hp.bleng - HeaderSize
						ELSE
							time := 0; date := 0; size := MIN(LONGINT)
						END;
						proc(a.e[i].name, time, date, size, continue)
					END
				ELSE continue := FALSE
				END
			END ;
			INC(i)
		END ;
		IF continue & (i > 0) & (a.e[i-1].p # 0) THEN
			enumerate(prefix, a.e[i-1].p, detail, proc, continue)
		END
	END enumerate;

	PROCEDURE Enumerate*(prefix: ARRAY OF CHAR; detail: BOOLEAN; proc: EntryHandler);
		VAR b: BOOLEAN;
	BEGIN
		IF ~init THEN HALT(99) END;
		COPY(prefix, pat);
		pos := 0;  WHILE (pat[pos] # 0X) & (pat[pos] # "*") DO INC(pos) END;
		IF pat[pos] # "*" THEN	(* no * found *)
			pos := -1
		ELSIF (pat[pos] = "*") & (pat[pos+1] = 0X) THEN	(* found * at end *)
			prefix[pos] := 0X;  pos := -1
		ELSE
			prefix[pos] := 0X
		END;
		b := TRUE; enumerate(prefix, DirRootAdr, detail, proc, b)
	END Enumerate;

	PROCEDURE Init*;
	BEGIN
		Disk.ResetDisk;
		prefix := "";  init := TRUE;  PathChar := "/";
	END Init;

BEGIN
	init := FALSE;  NEW(hp)
END VirtFileDir.
