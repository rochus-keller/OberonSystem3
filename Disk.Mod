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

MODULE Disk;	(** non-portable *)	(* pjm *)

(* Disk driver base for Native Oberon - also see InstDisk.Mod *)

IMPORT SYSTEM, Kernel;

TYPE
	Sector* = RECORD END;	(** 2k Oberon Sector *)

	TransferProc* = PROCEDURE (drive, start, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
	GetParamsProc* = PROCEDURE (drive: LONGINT;  VAR cyls, hds, spt: LONGINT);

CONST
	SectorSize* = 2048;

	BS = 512;	(* disk block size *)
	SS = SectorSize;	(* Oberon sector size *)
	BPS = SS DIV BS;	(* blocks per sector *)

	MaxDrives = 4;
	MaxPartitions = 32;
	Reserved = 32;	(* sectors reserved for writing during trap handling *)
	
	DefaultCacheSize = 100;	(* default sector cache size *)
	CacheReserved = 8;	(* cache sectors reserved for writing during trap handling *)

TYPE
	Partition = RECORD
		type: LONGINT;
		letter: CHAR;
		drive: LONGINT;
		start, size: LONGINT
	END;

	Node = POINTER TO NodeRec;
	NodeRec = RECORD
		data: ARRAY SS OF CHAR;
		next: Node;
		adr: LONGINT;
		dirty: BOOLEAN
	END;

VAR
(** GetBlocks - Read 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0=first, 1=second, etc.)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to read into
	"ofs" - offset from start of buf in bytes *)
	GetBlocks*: TransferProc;
	SafeGetBlocks: TransferProc;	(* used by GetSector - for host/target in Install *)
	
(** PutBlocks - Write 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0=first, 1=second, etc.)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to write from
	"ofs" - offset from start of buf in bytes *)
	PutBlocks*: TransferProc;
	SafePutBlocks: TransferProc;	(* used by PutSector - for host/target in Install *)
	
(** GetParams - Return parameters of drive (for Install) *)
	GetParams*: GetParamsProc;
	
		(* sector management *)
	file, error: ARRAY 60 OF CHAR;	(* report initialisation errors *)
	numused: LONGINT;	(* number of used Sectors *)
	nummax: LONGINT;	(* total number of Sectors *)
	nummaxdisk: LONGINT;	(* total number of Sectors on real disk *)
	map: ARRAY * OF LONGINT;
	init, trapped: BOOLEAN;

		(* partition *)
	native: BOOLEAN;
	ddrive: LONGINT;
	partitionoffset, partitionlen, rootoffset: LONGINT;
	parttype: LONGINT;

		(* cache *)
	cache: Node;
	Csize, Creads, Cwrites, Creadhits, Cwritehits, Cvirtualreads, Cused, Cdirty: LONGINT;
	writein: BOOLEAN;	(* all writes only go to the cache, not the disk *)
	readin: BOOLEAN;	(* all reads only from the cache, not the disk (primed cache) *)
	
PROCEDURE -Halt(n: LONGINT);
CODE {SYSTEM.i386}
	INT 3
END Halt;

PROCEDURE -Error(err: LONGINT);
CODE {SYSTEM.i386}
	POP EAX	(* for register dump *)
	PUSH 17	(* Disk error *)
	INT 3
END Error;

(* ---- Read partition table ---- *)

(* Partition table starts at 01BEH in partition table sector and consists
	of 4 records of the type:
	
	00    bootind: Types.Byte;
	01    head: Types.Byte;
	02    sector: Types.Byte;
	03    cyl: Types.Byte;
	04    type: Types.Byte;
	05    head2: Types.Byte;
	06    sector2: Types.Byte;
	07    cyl2: Types.Byte;
	08    start: Types.DWord;
	12    num: Types.DWord
*)

PROCEDURE Lettered(type: LONGINT): BOOLEAN;
BEGIN
	RETURN (type >= 0) & (type < 32) & (type IN {1,4,6,11,12,14})
END Lettered;

PROCEDURE Extended(type: LONGINT): BOOLEAN;
BEGIN
	RETURN (type = 5) OR (type = 15)
END Extended;

PROCEDURE WriteBadSignature(d, b: LONGINT;  s1, s2: CHAR);
BEGIN
	Kernel.WriteString("Disk ");  Kernel.WriteInt(d, 1);
	Kernel.WriteString(": signature bad (");
	Kernel.WriteHex(ORD(s1), -2);  Kernel.WriteChar(",");
	Kernel.WriteHex(ORD(s2), -2);
	Kernel.WriteString(" instead of 55,AA) on block ");
	Kernel.WriteInt(b, 1);  Kernel.WriteLn
END WriteBadSignature;

PROCEDURE ReadPrimary(VAR p: ARRAY OF Partition;  VAR n, letter: LONGINT);
VAR b: ARRAY BS OF CHAR;  e, d, i, size, cyls, hds, spt: LONGINT;  first: BOOLEAN;
BEGIN
	n := 0;  d := 0;
	GetParams(d, cyls, hds, spt);
	WHILE cyls * hds * spt # 0 DO
		first := TRUE;
		GetBlocks(d, 0, 1, b, 0);
		(*Kernel.WriteMemory(SYSTEM.ADR(b[0]), BS);*)
		IF (b[510] = 055X) & (b[511] = 0AAX) THEN	(* signature ok *)
			FOR i := 0 TO 3 DO
				e := 01BEH + 16*i;  SYSTEM.GET(SYSTEM.ADR(b[e+12]), size);
				IF (b[e+4] # 0X) & (size # 0) THEN
					p[n].type := ORD(b[e+4]);  p[n].letter := 0X;  p[n].drive := d;
					SYSTEM.GET(SYSTEM.ADR(b[e+8]), p[n].start);  p[n].size := size;
					IF first & Lettered(p[n].type) THEN
						p[n].letter := CHR(letter);  INC(letter);
						first := FALSE
					ELSE
						p[n].letter := 0X
					END;
					INC(n)
				END
			END
		ELSE
			WriteBadSignature(d, 0, b[510], b[511])
		END;
		INC(d);
		GetParams(d, cyls, hds, spt)
	END
END ReadPrimary;

PROCEDURE ReadLogical(d, first: LONGINT;  VAR p: ARRAY OF Partition;  VAR n, letter: LONGINT);
VAR b: ARRAY BS OF CHAR;  e, sec, size, i: LONGINT;  found: BOOLEAN;
BEGIN
	sec := first;
	REPEAT
		found := FALSE;
		GetBlocks(d, sec, 1, b, 0);
		IF (b[510] = 055X) & (b[511] = 0AAX) THEN
			FOR i := 0 TO 3 DO	(* look for partition entry (max one expected) *)
				e := 01BEH + 16*i;  SYSTEM.GET(SYSTEM.ADR(b[e+12]), size);
				IF (b[e+4] # 0X) & ~Extended(ORD(b[e+4])) & (size # 0) THEN
					p[n].type := ORD(b[e+4]);  p[n].drive := d;
					IF Lettered(p[n].type) THEN
						p[n].letter := CHR(letter);  INC(letter)
					ELSE
						p[n].letter := 0X
					END;
					SYSTEM.GET(SYSTEM.ADR(b[e+8]), p[n].start);  INC(p[n].start, sec);
					p[n].size := size;  INC(n)
				END
			END;
			i := 0;
			WHILE (i # 4) & ~found DO	(* look for nested extended entry (max one expected) *)
				e := 01BEH + 16*i;  SYSTEM.GET(SYSTEM.ADR(b[e+12]), size);
				IF Extended(ORD(b[e+4])) & (size # 0) THEN	(* found *)
					SYSTEM.GET(SYSTEM.ADR(b[e+8]), sec);  INC(sec, first);
					i := 4;  found := TRUE
				ELSE
					INC(i)
				END
			END
		ELSE
			WriteBadSignature(d, sec, b[510], b[511])
		END
	UNTIL ~found
END ReadLogical;

PROCEDURE ShowPartitionTable(VAR p: ARRAY OF Partition;  n: LONGINT);
VAR i: LONGINT;  letter: CHAR;
BEGIN
	Kernel.WriteString("Partitions:");  Kernel.WriteLn;
	FOR i := 0 TO n-1 DO
		Kernel.WriteInt(i, 2);
		Kernel.WriteInt(p[i].drive, 2);
		Kernel.WriteInt(p[i].type, 4);  Kernel.WriteChar(" ");
		letter := p[i].letter;
		IF letter = 0X THEN letter := "." END;
		Kernel.WriteChar(letter);
		Kernel.WriteInt(p[i].start, 10);  Kernel.WriteInt(p[i].size, 10);
		Kernel.WriteLn
	END
END ShowPartitionTable;

PROCEDURE ReadPartitionTable(VAR p: ARRAY OF Partition;  VAR n: LONGINT);
VAR pt: ARRAY MaxDrives*4 OF Partition;  pn, letter, i: LONGINT;
BEGIN
	letter := ORD("C");
	ReadPrimary(pt, pn, letter);
	n := 0;
	FOR i := 0 TO pn-1 DO
		IF Extended(pt[i].type) THEN
			ReadLogical(pt[i].drive, pt[i].start, p, n, letter)
		ELSE
			p[n] := pt[i];  INC(n)
		END
	END;
		(* now assign letters to remaining primary partitions (see Q51978) *)
	FOR i := 0 TO n-1 DO
		IF (p[i].letter = 0X) & Lettered(p[i].type) THEN
			p[i].letter := CHR(letter);  INC(letter)
		END
	END
END ReadPartitionTable;

(* ---- Mapping to oberon.dsk ---- *)

(* FindFatPartition - Find the specified FAT partition. Return drive < 0 if not found. *)

PROCEDURE FindFatPartition(letter: CHAR;  VAR drive, offset, len: LONGINT);
VAR pt: ARRAY MaxPartitions OF Partition;  pn, pi, m: LONGINT;
BEGIN
	ReadPartitionTable(pt, pn);
	pi := 0;  m := pn;
	WHILE pi # m DO
		IF (pt[pi].letter = letter) & (pt[pi].type < 32) & (pt[pi].type IN {1,4,6}) THEN m := pi
		ELSE INC(pi)
		END
	END;
	IF pi # pn THEN offset := pt[pi].start;  len := pt[pi].size;  drive := pt[pi].drive
	ELSE drive := -1; ShowPartitionTable(pt, pn)
	END
END FindFatPartition;

PROCEDURE Cap(ch: CHAR): CHAR;
BEGIN
	IF (ch >= "a") & (ch <= "z") THEN RETURN CAP(ch)
	ELSE RETURN ch
	END
END Cap;

(* GetBPB - Read BPB and return parameters. *)

PROCEDURE GetBPB(VAR csize, fatb, rootb, rootsize, datab: LONGINT): BOOLEAN;
VAR b: ARRAY BS OF CHAR;  x, fatsize, numfat: LONGINT;
BEGIN
	GetBlocks(ddrive, partitionoffset, 1, b, 0);
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[0BH]), SYSTEM.VAL(INTEGER, x));
	IF x # BS THEN error := "Bad block size"; RETURN FALSE END;
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[0DH]), SYSTEM.VAL(CHAR, x));
	csize := x*BS;	(* bytes per cluster *)
	numfat := ORD(b[10H]);	(* FAT copies *)
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[16H]), SYSTEM.VAL(INTEGER, x));
	fatsize := x;	(* sectors in FAT *)
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[0EH]), SYSTEM.VAL(INTEGER, x));
	fatb := x;	(* start of FAT *)
	rootb := fatb + numfat*fatsize;
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[11H]), SYSTEM.VAL(INTEGER, x));
	rootsize := (x*32) DIV BS;
	datab := rootb + rootsize;	(* start of data *)
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[13H]), SYSTEM.VAL(INTEGER, x));
	IF x = 0 THEN
		SYSTEM.GET(SYSTEM.ADR(b[20H]), x)	(* big number of sectors *)
	END;
	x := (x-datab) DIV (csize DIV BS);	(* total clusters *)
	IF x <= 4078 THEN error := "~16-bit FAT"; RETURN FALSE
	ELSE RETURN TRUE
	END
END GetBPB;

(* ParseName - Parse one more component of a path, starting at i. *)

PROCEDURE ParseName(VAR file: ARRAY OF CHAR;  VAR i: LONGINT;  VAR name: ARRAY OF CHAR);
VAR j: LONGINT;
BEGIN
	j := 0;
	IF (file[i] = "/") OR (file[i] = "\") THEN
		INC(i);
		WHILE (file[i] = ".") & (j # 2) DO name[j] := file[i]; INC(i); INC(j) END;	(* allow up to 2 leading dots *)
		WHILE (file[i] # 0X) & (file[i] # ".") & (file[i] # "/") & (file[i] # "\") & (j # 8) DO
			file[i] := Cap(file[i]); name[j] := file[i]; INC(i); INC(j)
		END;
		WHILE j # 8 DO name[j] := " "; INC(j) END;
		IF file[i] = "." THEN INC(i) END;
		WHILE (file[i] # 0X) & (file[i] # "/") & (file[i] # "\") & (j # 11) DO
			file[i] := Cap(file[i]); name[j] := file[i]; INC(i); INC(j)
		END;
		WHILE j # 11 DO name[j] := " "; INC(j) END
	END;
	name[j] := 0X
END ParseName;

(* NextCluster - Return next cluster or 0 if eof or -1 if bad block or error. b is 512 byte buffer and 
	cache is block number loaded in b. *)

PROCEDURE NextCluster(VAR b: ARRAY OF CHAR;  VAR cache: LONGINT;  fatb, cluster: LONGINT): LONGINT;
VAR k, x: LONGINT;
BEGIN
	k := cluster DIV (BS DIV 2) + fatb;	(* there are BS DIV 2 next entries per FAT block, indexed by cluster *)
	IF k # cache THEN
		GetBlocks(ddrive, partitionoffset + k, 1, b, 0);
		cache := k
	END;
		(* get next in chain *)
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[(cluster MOD (BS DIV 2))*2]), SYSTEM.VAL(INTEGER, x));
	IF x >= 0FFF8H THEN RETURN 0	(* was last cluster *)
	ELSIF x >= 0FFF0H THEN error := "Bad cluster"; RETURN -1
	ELSE RETURN x
	END
END NextCluster;

(* Equal - Return TRUE iff str1[i1..i1+len-1] = str2[i2..i2+len-1] *)

PROCEDURE Equal(VAR str1, str2: ARRAY OF CHAR;  i1, i2, len: LONGINT): BOOLEAN;
BEGIN
	WHILE len # 0 DO
		IF str1[i1] # str2[i2] THEN RETURN FALSE END;
		INC(i1);  INC(i2);  DEC(len)
	END;
	RETURN TRUE
END Equal;

(* FindName - Find a name in a directory entry. *)

PROCEDURE FindName(VAR b: ARRAY OF CHAR;  name: ARRAY OF CHAR;  VAR attr: SET;  VAR start, size: LONGINT): BOOLEAN;
VAR j: LONGINT;
BEGIN
	j := 0;
	WHILE j # 16 DO
		IF Equal(b, name, j*32, 0, 11) THEN
			start := 0;  attr := {};
			SYSTEM.GET(SYSTEM.ADR(b[j*32+0BH]), SYSTEM.VAL(CHAR, attr));
			SYSTEM.GET(SYSTEM.ADR(b[j*32+1AH]), SYSTEM.VAL(INTEGER, start));
			SYSTEM.GET(SYSTEM.ADR(b[j*32+1CH]), size);
			RETURN TRUE
		ELSE INC(j)
		END
	END;
	RETURN FALSE
END FindName;

(* FindFile - Find a file and return its position and size. *)

PROCEDURE FindFile(VAR file: ARRAY OF CHAR;  csize, fatb, rootb, rootsize, datab: LONGINT;  VAR start, fsize: LONGINT): BOOLEAN;
VAR
	b: ARRAY BS OF CHAR;  disk: ARRAY 12 OF CHAR;
	 i, k, m, n, dir: LONGINT;  found: BOOLEAN;  attr: SET;
BEGIN
	k := 2;  ParseName(file, k, disk);
	i := 0;  found := FALSE;  start := -1;
	WHILE (i # rootsize) & ~found DO
		GetBlocks(ddrive, partitionoffset + rootb + i, 1, b, 0);
		found := FindName(b, disk, attr, start, fsize);
		INC(i)
	END;
	WHILE found & (file[k] # 0X) & (4 IN attr) DO	(* more to come *)
		dir := start;  ParseName(file, k, disk);  found := FALSE;
		LOOP
			m := 0;  n := csize DIV BS;
			WHILE (m # n) & ~found DO
				GetBlocks(ddrive, partitionoffset + (dir-2)*n + datab + m, 1, b, 0);
				found := FindName(b, disk, attr, start, fsize);
				INC(m)
			END;
			IF found THEN EXIT END;
			m := -1;  dir := NextCluster(b, m, fatb, dir);
			IF dir <= 0 THEN
				IF dir = 0 THEN EXIT	(* last cluster *)
				ELSE COPY(file, error); RETURN FALSE	(* error *)
				END
			END
		END
	END;
	IF found & (file[k] = 0X) & (attr * {3,4} = {}) THEN RETURN TRUE
	ELSE COPY(file, error); RETURN FALSE
	END
END FindFile;

(* InitMapping - Initialise sector mapping for file system in a file *)

PROCEDURE InitMapping;
VAR
	b: ARRAY BS OF CHAR;
	i, j, m, csize, fatb, rootb, datab, rootsize, start, fsize, cache: LONGINT;
BEGIN
	file[0] := Cap(file[0]);
	IF (file[0] < "C") OR (file[0] > "Z") OR (file[1] # ":") OR ((file[2] # "\") & (file[2] # "/")) OR (file[3] = 0X) THEN
		error := "Bad drive"; RETURN
	END;
	FindFatPartition(file[0], ddrive, partitionoffset, partitionlen);
	IF ddrive >= 0 THEN
		ASSERT(partitionoffset > 0);
		IF GetBPB(csize, fatb, rootb, rootsize, datab) THEN
			IF FindFile(file, csize, fatb, rootb, rootsize, datab, start, fsize) THEN
				nummax := fsize DIV SS;
				IF (nummax < 8) OR (start = 0) THEN
					error := "File too small"; nummax := 0; RETURN
				END;
				IF csize MOD SS # 0 THEN
					error := "Bad cluster size"; nummax := 0; RETURN
				END;
				NEW(map, nummax+1);
				map[0] := -1;	(* reserve sector 0 (illegal to use) *)
				i := start;  j := 1;  cache := -1;
				LOOP
					FOR m := 0 TO (csize DIV SS)-1 DO	(* the next csize bytes of the file are stored in cluster i *)
						map[j] := (i-2)*(csize DIV BS) + datab + m*BPS;  INC(j);	(* i-2 for 1st 2 FAT entries *)
						IF j > nummax THEN EXIT END	(* done *)
					END;
					i := NextCluster(b, cache, fatb, i);	(* step to next *)
					IF i <= 0 THEN
						IF i = 0 THEN EXIT	(* last cluster *)
						ELSE nummax := 0; RETURN	(* error *)
						END
					END
				END;
				FOR i := 1 TO nummax DO
					ASSERT((map[i] >= datab) & (map[i] < partitionoffset+partitionlen))
				END;
				nummaxdisk := nummax
			END
		END
	ELSE error := "Drive not found"
	END
END InitMapping;

(* InitTable - Initialise sector reservation table *)

PROCEDURE InitTable;
CONST BootDiskette = 0;
VAR s, x, pn, pi: LONGINT;  b: ARRAY BS OF CHAR;  pt: ARRAY MaxPartitions OF Partition;
BEGIN
	native := TRUE;
	GetBlocks(BootDiskette, 0, 1, b, 0);	(* read boot block of first disk to check if diskette *)
	x := 0;  SYSTEM.GET(SYSTEM.ADR(b[510]), SYSTEM.VAL(INTEGER, x));
	b[0] := "x"; b[1] := "x"; b[2] := "x";  b[9] := 0X;
	IF (x = 0AA55H) & (b = "xxxOBERON") & (b[24H] = 0X) THEN	(* diskette with valid boot block *)
		ddrive := BootDiskette;  partitionoffset := 0;
		GetParams(BootDiskette, x, pn, pi);
		partitionlen := x * pn * pi
	ELSE	(* read partition table, finding first Native Oberon partition *)
		ReadPartitionTable(pt, pn);
		pi := 0;  x := pn;
		WHILE pi # x DO
			IF pt[pi].type = parttype THEN x := pi
			ELSE INC(pi)
			END
		END;
		IF pi = pn THEN error := "Partition not found";  ShowPartitionTable(pt, pn); RETURN END;
		partitionoffset := pt[pi].start;  partitionlen := pt[pi].size;
		ddrive := pt[pi].drive;
		GetBlocks(ddrive, partitionoffset, 1, b, 0);	(* read boot block to get offset *)
		x := 0;  SYSTEM.GET(SYSTEM.ADR(b[510]), SYSTEM.VAL(INTEGER, x));
		b[0] := "x"; b[1] := "x"; b[2] := "x";  b[9] := 0X;
		IF (x # 0AA55H) OR (b # "xxxOBERON") THEN error := "Bad boot block";  RETURN END
	END;
	rootoffset := 0;  SYSTEM.GET(SYSTEM.ADR(b[0EH]), SYSTEM.VAL(INTEGER, rootoffset));
	s := 0;  SYSTEM.GET(SYSTEM.ADR(b[13H]), SYSTEM.VAL(INTEGER, s));	(* total size *)
	IF s = 0 THEN SYSTEM.GET(SYSTEM.ADR(b[20H]), s) END;
	IF partitionlen > s THEN partitionlen := s END;	(* limit to size of file system *)
	ASSERT(partitionlen > 0);
		(* total size of file system *)
	nummaxdisk := (partitionlen-rootoffset) DIV BPS;
	nummax := nummaxdisk;
	IF writein & (Csize > nummax) THEN nummax := Csize END;	(* use the full cache *)
		(* set up sector reservation table *)
	s := (nummax+1+31) DIV 32;
	NEW(map, s);
	WHILE s # 0 DO DEC(s); map[s] := 0 END;
	INCL(SYSTEM.VAL(SET, map[0]), 0)	(* reserve sector 0 (illegal to use) *)
END InitTable;

(* ---- Ceres-like interface ---- *)

(** AllocSector - Allocate a new Sector.  "hint" can be previously allocated
	Sector to preserve adjacency, or 0 if previous Sector not known *)

PROCEDURE AllocSector*(hint: LONGINT; VAR sec: LONGINT);
VAR i: LONGINT;
BEGIN
	i := hint+29;
	IF ~init OR (i < 29) OR (i MOD 29 # 0) THEN Halt(15) END;
	IF ~trapped & (nummax - numused <= Reserved) THEN
		trapped := TRUE;  Halt(16)	(* Disk almost full *)
	END;
	i := i DIV 29;  hint := i-1;
	IF hint > nummax THEN hint := 0 END;
	LOOP
		IF i > nummax THEN i := 0 END;
		IF native THEN
			IF (i MOD 32) IN SYSTEM.VAL(SET, map[i DIV 32]) THEN INC(i)	(* in use *)
			ELSE
				sec := i;  INCL(SYSTEM.VAL(SET, map[i DIV 32]), i MOD 32);  INC(numused);
				sec := sec*29;	(* "Encode" sector number. *)
				EXIT
			END
		ELSE
			IF map[i] < 0 THEN INC(i)	(* in use *)
			ELSE
				sec := i;  map[i] := -map[i];  INC(numused);
				sec := sec*29;	(* "Encode" sector number. *)
				EXIT
			END
		END;
		IF i = hint THEN Halt(16) (* Disk full *) END
	END
END AllocSector;

(** MarkSector - Mark an unused Sector as used.  Do not mark already marked sectors. *)

PROCEDURE MarkSector*(sec: LONGINT);
BEGIN
	IF ~init OR (sec MOD 29 # 0) THEN Halt(15) END;
	sec := sec DIV 29;
	IF (sec < 1) OR (sec > nummax) THEN Halt(15) END;
	IF native THEN INCL(SYSTEM.VAL(SET, map[sec DIV 32]), sec MOD 32)
	ELSE map[sec] := -ABS(map[sec])
	END;
	INC(numused)
END MarkSector;

(** FreeSector - Mark a used Sector as unused.  Do not unmark already unmarked sectors. *)

PROCEDURE FreeSector*(sec: LONGINT);
BEGIN
	IF ~init OR (sec MOD 29 # 0) THEN Halt(15) END;
	sec := sec DIV 29;
	IF (sec < 1) OR (sec > nummax) THEN Halt(15) END;
	IF native THEN EXCL(SYSTEM.VAL(SET, map[sec DIV 32]), sec MOD 32)
	ELSE map[sec] := ABS(map[sec])
	END;
	DEC(numused)
END FreeSector;

(** Marked - Test if a sector is marked as used. *)

PROCEDURE Marked*(sec: LONGINT): BOOLEAN;
BEGIN
	IF ~init OR (sec MOD 29 # 0) THEN Halt(15) END;
	sec := sec DIV 29;
	IF (sec < 1) OR (sec > nummax) THEN Halt(15) END;
	IF native THEN RETURN (sec MOD 32) IN SYSTEM.VAL(SET, map[sec DIV 32])
	ELSE RETURN map[sec] < 0
	END
END Marked;

(* Find - Find a sector in the cache *)

PROCEDURE Find(adr: LONGINT): Node;
VAR p, c: Node;
BEGIN
	p := NIL;  c := cache;
	WHILE (c # NIL) & (c.adr # adr) DO p := c; c := c.next END;
	IF c # NIL THEN
		IF p # NIL THEN	(* move to front *)
			p.next := c.next;  c.next := cache;  cache := c
		END
	END;
	RETURN c
END Find;

(* Replace - Replace a sector in the cache.  Never replaces a dirty sector or any sector in a primed cache. *)

PROCEDURE Replace(adr: LONGINT): Node;
VAR p, c: Node;
BEGIN
	IF readin THEN	(* not allowed to replace anything in a primed cache *)
		IF ~trapped & (Csize - Cused <= CacheReserved) THEN
			trapped := TRUE;  Halt(16)	(* Cache almost full *)
		END;
		IF Cused = Csize THEN Halt(16) END	(* Cache full *)
	END;
	p := NIL;  c := cache;
	WHILE (c.next # NIL) & (c.adr # -1) DO p := c; c := c.next END;
	IF c.adr = -1 THEN (* unused sector, use it *)
		INC(Cused);
		IF p # NIL THEN
			p.next := c.next;  c.next := cache;  cache := c
		END
	ELSE	(* replace a node *)
		IF ~trapped & (Csize - Cdirty <= CacheReserved) THEN
			trapped := TRUE;  Halt(16)	(* Cache almost full *)
		END;
		IF ~c.dirty THEN	(* replace last node and move to the front *)
			p.next := NIL;  c.next := cache;  cache := c
		ELSE	(* look for a non-dirty node to replace *)
			p := NIL;  c := cache;
			WHILE (c.next # NIL) & c.dirty DO p := c; c := c.next END;
			IF c.dirty THEN Halt(15) END;	(* there must be enough cache nodes! *)
			IF p # NIL THEN
				p.next := c.next;  c.next := cache;  cache := c
			END
		END
	END;
	c.adr := adr;
	RETURN c
END Replace;

(* StrToInt - Convert a string to an integer *)

PROCEDURE StrToInt(VAR i: LONGINT;  VAR s: ARRAY OF CHAR): LONGINT;
VAR vd, vh, sgn, d: LONGINT;  hex: BOOLEAN;
BEGIN
	vd := 0;  vh := 0;  hex := FALSE;
	IF s[i] = "-" THEN sgn := -1; INC(i) ELSE sgn := 1 END;
	LOOP
		IF (s[i] >= "0") & (s[i] <= "9") THEN d := ORD(s[i])-ORD("0")
		ELSIF (CAP(s[i]) >= "A") & (CAP(s[i]) <= "F") THEN d := ORD(CAP(s[i]))-ORD("A")+10; hex := TRUE
		ELSE EXIT
		END;
		vd := 10*vd + d;  vh := 16*vh + d;
		INC(i)
	END;
	IF CAP(s[i]) = "H" THEN hex := TRUE; INC(i) END;	(* optional H *)
	IF hex THEN vd := vh END;
	RETURN sgn * vd
END StrToInt;

(* InitCache - Initialize the cache.  Return rdin and wrin config. *)

PROCEDURE InitCache(VAR rdin, wrin: BOOLEAN);
VAR n: Node;  i: LONGINT;  s: ARRAY 10 OF CHAR;
BEGIN
	cache := NIL;  rdin := FALSE;  wrin := FALSE;
	Creads := 0;  Cwrites := 0;  Creadhits := 0;  Cwritehits := 0;
	Cvirtualreads := 0;  Cused := 0;  Cdirty := 0;
	Kernel.GetConfig("DiskCache", s);
	IF s = "" THEN
		Csize := DefaultCacheSize
	ELSE
		i := 0;  Csize := StrToInt(i, s);
		ASSERT(Csize >= 0);
		IF s[i] = "," THEN
			INC(i);
			IF CAP(s[i]) = "I" THEN	(* write-in *)
				wrin := TRUE
			ELSIF CAP(s[i]) = "P" THEN	(* write-in-primed *)
				wrin := TRUE;  rdin := TRUE
			END
		END
	END;
	Kernel.WriteString("Disk cache: ");  Kernel.WriteInt(Csize, 1);
	Kernel.WriteString(" sectors");
	IF wrin & rdin THEN Kernel.WriteString(" (ram disk)")
	ELSIF wrin THEN Kernel.WriteString(" (read-only disk)")
	ELSE Kernel.WriteString(" (write-through)")
	END;
	Kernel.WriteLn;
	FOR i := 1 TO Csize DO
		NEW(n);  n.next := cache;  n.adr := -1;  n.dirty := FALSE;  cache := n
	END
END InitCache;

PROCEDURE -CopySector(srcAdr, dstAdr: LONGINT);
CONST SS4 = SectorSize DIV 4;
CODE {SYSTEM.i386}
	CLD
	POP EDI
	POP ESI
	MOV ECX, SS4
	REP MOVSD
END CopySector;

PROCEDURE -ClearSector(dstAdr: LONGINT);
CONST SS4 = SectorSize DIV 4;
CODE {SYSTEM.i386}
	CLD
	XOR EAX, EAX
	POP EDI
	MOV ECX, SS4
	REP STOSD
END ClearSector;

(** GetSector - Read a 2k Sector from disk *)

PROCEDURE GetSector*(src: LONGINT; VAR dest: Sector);
VAR n: Node;
BEGIN
	IF ~init OR (src MOD 29 # 0) THEN Halt(15) END;
	src := src DIV 29;
	IF (src < 1) OR (src > nummax) THEN Halt(15) END;
	INC(Creads);
	n := Find(src);
	IF n = NIL THEN	(* miss *)
		IF writein & (src > nummaxdisk) THEN	(* in virtual disk only *)
			INC(Cvirtualreads);
			ClearSector(SYSTEM.ADR(dest))
		ELSE (* in real disk *)
			IF readin THEN Halt(15) END;	(* cache was primed! *)
			IF native THEN
				SafeGetBlocks(ddrive, partitionoffset + rootoffset+(src-1)*BPS, BPS, dest, 0)
			ELSE
				SafeGetBlocks(ddrive, partitionoffset + ABS(map[src]), BPS, dest, 0)
			END;
			IF cache # NIL THEN
				n := Replace(src);
				CopySector(SYSTEM.ADR(dest), SYSTEM.ADR(n.data[0]))
			END
		END
	ELSE	(* hit *)
		INC(Creadhits);
		CopySector(SYSTEM.ADR(n.data[0]), SYSTEM.ADR(dest))
	END
END GetSector;

(** PutSector - Write a 2k Sector to disk *)

PROCEDURE PutSector*(dest: LONGINT; VAR src: Sector);
VAR n: Node;
BEGIN
	IF ~init OR (dest MOD 29 # 0) THEN Halt(15) END;
	dest := dest DIV 29;
	IF (dest < 1) OR (dest > nummax) THEN Halt(15) END;
	INC(Cwrites);
	IF writein THEN	(* write-in caching *)
		n := Find(dest);
		IF n = NIL THEN	(* miss *)
			ASSERT(cache # NIL);
			n := Replace(dest)	(* get a buffer to write to *)
		ELSE	(* hit *)
			INC(Cwritehits)
		END;
		CopySector(SYSTEM.ADR(src), SYSTEM.ADR(n.data[0]));
		IF ~n.dirty THEN INC(Cdirty) END;
		n.dirty := TRUE	(* not written to disk *)
	ELSE
		n := Find(dest);
		IF n # NIL THEN	(* hit *)
			INC(Cwritehits);
			CopySector(SYSTEM.ADR(src), SYSTEM.ADR(n.data[0]))
		END;
		IF native THEN
			SafePutBlocks(ddrive, partitionoffset + rootoffset+(dest-1)*BPS, BPS, src, 0)
		ELSE
			SafePutBlocks(ddrive, partitionoffset + ABS(map[dest]), BPS, src, 0)
		END
	END
END PutSector;

(* PrimeCache - Prime the cache *)

PROCEDURE PrimeCache;
VAR i: LONGINT;  data: RECORD (Sector) a: ARRAY SS OF CHAR END;
BEGIN
	Kernel.WriteString("Reading ");  Kernel.WriteInt(nummaxdisk, 1);
	Kernel.WriteString(" sectors into cache...");  Kernel.WriteLn;
	IF nummaxdisk > Csize THEN Halt(15) END;	(* not enough space *)
	FOR i := 1 TO nummaxdisk DO GetSector(29*i, data) END;
	GetBlocks := NIL;  SafeGetBlocks := NIL;
	readin := TRUE
END PrimeCache;

(** ResetDisk - Reset the disk driver, re-reading all structures.  Use must be coordinated with filesystem. *)

PROCEDURE ResetDisk*;
VAR s: ARRAY 20 OF CHAR;  i: LONGINT;  rdin: BOOLEAN;
BEGIN
	IF ~init THEN
		SafeGetBlocks := GetBlocks;  SafePutBlocks := PutBlocks;
		error := "";
		InitCache(rdin, writein);
		IF writein THEN PutBlocks := NIL;  SafePutBlocks := NIL END;
		ddrive := -1;  partitionoffset := MIN(LONGINT);  native := FALSE;
		nummax := 0;  nummaxdisk := 0;  numused := 0;  NEW(map, 0);
		Kernel.GetConfig("PartType", s);
		i := 0;  parttype := 0;
		WHILE (s[i] >= "0") & (s[i] <= "9") DO
			parttype := parttype*10 + (ORD(s[i])-48);
			INC(i)
		END;
		IF parttype = 0 THEN parttype := 79 END;
		Kernel.GetConfig("DiskFile", file);
		IF file = "" THEN InitTable	(* native partition *)
		ELSE InitMapping	(* inside FAT file *)
		END;
		IF nummax = 0 THEN
			Kernel.WriteString("Error: ");
			Kernel.WriteString(error);  Kernel.WriteLn	(* error message *)
		ELSE
			init := TRUE;
			IF rdin THEN PrimeCache END
		END
	END
END ResetDisk;

(** Available - Return number of 2k Sectors available (unmarked) on disk *)

PROCEDURE Available*(): LONGINT;
BEGIN
	RETURN nummax - numused
END Available;

(** Size - Return total number of 2k Sectors on disk *)

PROCEDURE Size*(): LONGINT;
BEGIN
	RETURN nummax
END Size;

BEGIN
	init := FALSE;  trapped := FALSE;  parttype := -1;  writein := FALSE;  readin := FALSE
END Disk.
