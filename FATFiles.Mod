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

MODULE FATFiles;	(** non-portable *)  (* pjm 01.05.96/01.09.97 dVdW 08.96 *)

(* FAT file system *)

IMPORT
	SYSTEM, Kernel, Disk, Diskette, Partition;

CONST	(* svr *)
	Numflop = 2;
	SS = 512;	(* sector size *)

	AllocDirMark = 0FFX;
	
	(* DOS file directory attributes *)
	ReadOnly* = 0;
	Hidden* = 1;
	System* = 2;
	VolLabel* = 3;
	SubDir* = 4;
	Archive* = 5;

	purge = 1; new = 2; old = 3; read = 4; write = 5; register = 6; updatedir = 7;
	rename = 8;

	eInvalidVersion = 8900;
	eInvalidOperation = 8901;
	eInvalidDirectory = 8902;
	eFileDoesNotExist = 8903;
	eCannotReuseDirEntry = 8904;
	eRootDirFull = 8905;
	eDiskFull = 8906;
	eClusterOutsideFile = 8907;
	eNoSuchPartition = 8908;
	eInvalidSectorSize = 8909;
	eInvalidDirEntry = 8910;
	eIncorrectBufferSize = 8911;
	eBufferOverflow = 8912;
	eFilePrefixNotaDir = 8913;
	eSubDirFull = 8914;
	eFileIsReadOnlyInServer = 8915;
	eCannotOpenSubDir = 8916;
	eInvalidFirstCluster = 8917;
	eDirEntryAlreadyAllocated = 8918;
	eFileNameAlreadyExists = 8919;
	eNotSameDirectory = 8920;
	eFileErased = 8921;
	eInvalidFileLength = 8922;
	eBadHandle = 8923;
	eBadDriveHandle = 8924;
	eServerOutOfMemory = 8925;
	eDirEntryAlreadyExists = 8926;
	eNameIsWild = 8927;
	eInternalServerError = 8939;

TYPE	(* svr *)
	Filename = ARRAY 96 OF CHAR;
	DirEntryName = ARRAY 12 OF CHAR;
	Drive = POINTER TO DriveDesc;
	DriveDesc = RECORD
		next: Drive;
		num: SHORTINT;	(* logical drive number *)
		part: SHORTINT;	(* partition number, -1 if floppy (num=floppy num) *)
		fat16: BOOLEAN;	(* 16-bit fat *)
		spc, bpc: LONGINT;	(* sectors/bytes per cluster *)
		sres: LONGINT;	(* sectors reserved *)
		fats: LONGINT;	(* number of FATs *)
		dirsize: LONGINT;	(* number of root dir entries *)
		totals: LONGINT;	(* total number of sectors *)
		spf: LONGINT;	(* sectors per FAT *)
		fatsec, rootsec, datasec: LONGINT;	(* fat, root and data start sector (rel. to cluster 0) *)
		fatsize: LONGINT;	(* FAT size = max cluster number+1 *)
		serial: LONGINT;	(* serial number *)
		label: ARRAY 12 OF CHAR;	(* volume label *)
		fatdirty: BOOLEAN;
		fat: POINTER TO ARRAY OF INTEGER;
		dir: POINTER TO ARRAY OF CHAR;
	END;
	Handle0 = RECORD
		aleng, bleng,
		time, date,
		bufSize: LONGINT;
		readOnly: BOOLEAN;	(* depends on readonly bit in .attr field *)
		drive: Drive;	(* drive containing file *)
		firstcl: LONGINT;	(* first cluster *)
		attr: SET ;	(* DOS file attributes *)
		capos, ccl: LONGINT;	(* cache cluster and corresponding apos if ccl # 0 *)
		(* directory info *)
		name: Filename;
		firstdircl, (* first cluster of dir. that contains entry for file, 0 if in root dir;
						   this is necessary to be able to see if 2 files are in same dir.*)
		dircl,	(* absolute cluster in dir. that contains entry for file, 0 if in root dir *)
		dirofs: LONGINT; 	(* offset in cluster of dir. in which entry lies *)
	END;

CONST
	KeepList = FALSE;
	CheckNew = FALSE;
	
	MaxBufs = 4;

	eBufferTooSmallForRequest = 8940;
	eInvalidFileName = 8941;
	eFileIsReadOnly = 8942;
	eOutOfMemory = 8943;
	eInternalError = 8959;

TYPE
	File* = POINTER TO Handle;	(** A file descriptor *)
	Buffer = POINTER TO BufferRecord;

	Rider* = RECORD 	(** Riders are the access mechanisms for files. *)
		eof*: BOOLEAN;	(** Rider has reached the end of the file. *)
		res*: LONGINT;	(** Rider operation result code. *)
		file: File;
		apos, bpos: LONGINT;
		buf: Buffer
	END;
	
	Handle = RECORD
		next: File;
		handle: Handle0;
		registered: BOOLEAN;
		mod: BOOLEAN;
		nofbufs: INTEGER;
		firstbuf: Buffer;
	END;

	BufferRecord = RECORD
		apos, lim: LONGINT;
		mod: BOOLEAN;
		next: Buffer;
		data: POINTER TO ARRAY OF CHAR
	END ;

(** Upcall for Enumerate.  continue may be set to FALSE to stop the Enumerate operation mid-way. *)

	EntryHandler* = PROCEDURE (name: ARRAY OF CHAR; time, date, 
		size: LONGINT; attr: SET; VAR continue: BOOLEAN);

VAR	(* svr *)
	drives: Drive;	(* list of drives *)
	dirbuf: POINTER TO ARRAY OF CHAR;
	info: Partition.Info;
	defdir: ARRAY 4 OF CHAR;
	root: File; (* list of registered, open files, with dummy first node *)

(* -- Shared procedures -- *)

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

(* Cap - Capitalise a character *)

PROCEDURE Cap(ch: CHAR): CHAR;
BEGIN
	IF (ch >= "a") & (ch <= "z") THEN RETURN CAP(ch)
	ELSE RETURN ch
	END
END Cap;

(* Check - check filename.  Return correct name, or empty name if incorrect. *)

PROCEDURE Check(s: ARRAY OF CHAR;  VAR name: Filename; VAR res: LONGINT);
VAR i, j: LONGINT;  ok: BOOLEAN;  ch: CHAR;
BEGIN
	res := 0; i := 0;  ok := FALSE;
	WHILE (s[i] # 0X) & ~ok DO ok := s[i] = ":";  INC(i) END;
	IF ok OR (s[0] = 0X) THEN
		COPY(s, name)
	ELSE
		COPY(defdir, name);  i := 0;
		IF (s[0] = "/") OR (s[0] = "\") THEN	(* rel. to default drive root *)
			j := 3;  i := 1
		ELSE	(* rel. to default dir *)
			j := 0;  WHILE name[j] # 0X DO INC(j) END
		END;
		WHILE s[i] # 0X DO name[j] := s[i];  INC(i);  INC(j) END;
		name[j] := 0X
	END;
	i := 0;
	LOOP
		ch := name[i];  IF ch = 0X THEN EXIT END;
		IF ch = "\" THEN ch := "/" END;
		IF (ch <= " ") OR (ch >= 07FX) THEN i := 0; EXIT END;
		name[i] := Cap(ch);
		INC(i)
	END;
	name[i] := 0X;
	IF ~((name[0] >= "A") & (name[0] <= "Z") & (name[1] = ":") & (name[2] = "/") & (name[3] # 0X)) THEN
		name[0] := 0X; res := eInvalidFileName
	END;
	IF res = 0 THEN
		i := 0;  WHILE (name[i] # 0X) & (name[i] # "?") & (name[i] # "*") DO INC(i) END;
		IF name[i] # 0X THEN res := eNameIsWild END
	END
END Check;

(* -- Svr procedures -- *)

PROCEDURE ^Purge*(f: File; VAR res: LONGINT);
PROCEDURE ^Delete*(name: ARRAY OF CHAR; VAR res: LONGINT);

(* GetUWord - get unsigned word from array of bytes. *)

PROCEDURE GetUWord(VAR buf : ARRAY OF SYSTEM.BYTE; idx : LONGINT): LONGINT;
VAR val: LONGINT;
BEGIN
	val := 0;
	SYSTEM.GET(SYSTEM.ADR(buf[idx]), SYSTEM.VAL(INTEGER, val));
	RETURN val
END GetUWord;

(* ReadSectors - Read sectors from a partition *)

PROCEDURE ReadSectors(d: Drive;  sec, num: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE; VAR res : LONGINT);
BEGIN
	IF d.part >= 0 THEN	(* hard disk *)
		IF d.part < info.numpar THEN
			Disk.GetBlocks(info.par[d.part].drive, info.par[d.part].start + sec, num, buf, 0);
			res := 0
		ELSE
			res := eNoSuchPartition
		END
	ELSE	(* floppy *)
		Diskette.drive := d.num;  res := 0;
		Diskette.GetSectors(SHORT(sec), SHORT(num), buf, 0)
	END
END ReadSectors;

(* WriteSectors - Write sectors in a partition *)

PROCEDURE WriteSectors(d: Drive;  sec, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE; VAR res: LONGINT);
VAR error: ARRAY 32 OF CHAR;
BEGIN
	IF d.part >= 0 THEN	(* hard disk *)
		IF d.part < info.numpar THEN
			ASSERT(info.par[d.part].letter # 0X);
			IF Disk.PutBlocks = NIL THEN error := "Read-only disk" ELSE error := "" END;
			Disk.PutBlocks(info.par[d.part].drive, info.par[d.part].start + sec, num, buf, 0);
			res := 0
		ELSE
			res := eNoSuchPartition
		END
	ELSE	(* floppy *)
		Diskette.drive := d.num;  res := 0;
		Diskette.PutSectors(SHORT(sec), SHORT(num), buf, 0)
	END
END WriteSectors;

(* WriteFAT12 - Write 12-bit FAT *)

PROCEDURE WriteFAT12(d: Drive; copy: LONGINT; VAR res: LONGINT);
VAR
	b: ARRAY 1000H*3 DIV 2 OF CHAR;  i, j, val: LONGINT;
	even: BOOLEAN;
BEGIN
	b[0] := SYSTEM.VAL(CHAR, d.fat[0]);  b[1] := CHR(ASH(d.fat[0], -8));
	b[2] := CHR(d.fat[1]);
	val := 0;  j := 2*3;  even := TRUE;
	FOR i := 2 TO d.fatsize-1 DO
		val := SYSTEM.LSH(SYSTEM.LSH(d.fat[i], 4), -4); (*clear highest 4 bits*)
		IF even THEN even := FALSE
		ELSE val := ASH(val, 4) + (ORD(b[j DIV 2]) MOD 100H); even := TRUE
		END;
		SYSTEM.PUT(SYSTEM.ADR(b[j DIV 2]), SYSTEM.VAL(INTEGER, val));
		INC(j, 3)
	END;
	WriteSectors(d, d.fatsec + copy*d.spf, d.spf, b, res)
END WriteFAT12;

(* FlushDrive - Flush a drive - write its FATs to disk *)

PROCEDURE FlushDrive(d: Drive; VAR res: LONGINT);
VAR i: LONGINT;
BEGIN
	res := 0;
	IF d.fatdirty THEN
		i := 0;
		WHILE (i < d.fats) & (res = 0) DO
			IF d.fat16 THEN WriteSectors(d, d.fatsec + d.spf*i, d.spf, d.fat^, res)
			ELSE WriteFAT12(d, i, res)
			END;
			INC(i)
		END;
		IF res = 0 THEN d.fatdirty := FALSE END
	END
END FlushDrive;

(* ReadFAT12 - read the 12-bit FAT (floppy drives) *)

PROCEDURE ReadFAT12(d: Drive; VAR res: LONGINT);
VAR
	b: ARRAY 1000H*3 DIV 2 OF CHAR; i, j, val: LONGINT;
	even: BOOLEAN;
BEGIN
	ReadSectors(d, d.fatsec, d.spf, b, res);
	IF res = 0 THEN
		NEW(d.fat, d.fatsize);
		d.fat[0] := SHORT(ORD(b[0]) + ASH(ORD(b[1]), 8));
		d.fat[1] := ORD(b[2]); 
		val := 0;  j := 2*3;  even := TRUE;
		FOR i := 2 TO d.fatsize-1 DO
			SYSTEM.GET(SYSTEM.ADR(b[j DIV 2]), SYSTEM.VAL(INTEGER, val));
			IF even THEN val := val MOD 1000H;  even := FALSE
			ELSE val := ASH(val, -4);  even := TRUE
			END;
			IF val > 0FF0H THEN INC(val, 0F000H) END; 
			(* if value > 0FF0H, add 0F000H so that can be handled same as
				entries 0FFF0-0FFFF in a 16-bit FAT - see Read- & WriteCluster *)
			d.fat[i] := SHORT(val);
			INC(j, 3)
		END
	END
END ReadFAT12;

(* OpenDrive - Open a drive, get all partition information, FAT & root dir. *)

PROCEDURE OpenDrive(letter: CHAR; VAR d: Drive; VAR res: LONGINT);
VAR b: ARRAY SS OF CHAR;  i: SHORTINT; n: LONGINT; num: SHORTINT;
BEGIN (* Pre: num is a valid drive number *)
	res := 0;
	num := SHORT(ORD(letter)-ORD("A"));
	d := drives.next;
	WHILE (d # NIL) & (d.num # num) DO d := d.next END;
	IF d = NIL THEN
		NEW(d);  d.num := num;
		IF num >= Numflop THEN	(* hard disk *)
			d.part := 0;
			WHILE (d.part < info.numpar) & (info.par[d.part].letter # CHR(ORD("A")+num)) DO
				INC(d.part)
			END;
			IF d.part >= info.numpar THEN res := eNoSuchPartition END
		ELSE
			d.part := -1
		END;
		IF res = 0 THEN
			ReadSectors(d, 0, 1, b, res);	(* read boot sector *)
			IF res = 0 THEN
				n := GetUWord(b, 0BH); (* bytes per sector *)
				IF n # SS THEN
					d := NIL;
					res := eInvalidSectorSize
				ELSE
					d.spc := ORD(b[0DH]);  d.bpc := d.spc*SS;
					WHILE d.bpc > LEN(dirbuf^) DO NEW(dirbuf, 2*LEN(dirbuf^)) END;	(* enlarge cluster buffer *)
					d.sres := GetUWord(b, 0EH);
					d.fats := ORD(b[10H]);
					d.dirsize := GetUWord(b, 11H);
					d.totals := GetUWord(b, 13H);
					IF d.totals = 0 THEN SYSTEM.GET(SYSTEM.ADR(b[20H]), d.totals) END;
					d.spf := GetUWord(b, 16H);
					SYSTEM.GET(SYSTEM.ADR(b[27H]), d.serial);
					i := 0; WHILE i # 11 DO d.label[i] := b[2BH+i]; INC(i) END;
					d.label[i] := 0X;
					d.fatsec := d.sres;  d.rootsec := d.fatsec + d.fats*d.spf;
					d.datasec := d.rootsec + (d.dirsize*32) DIV SS - 2*d.spc;
					(* first real data sector = d.datasec + 2*d.spc; this simplifies caculation of a file's first sector, since the first FAT entry
						 available to files is number 2 *)
					d.fatsize := 2 + ((d.totals-d.datasec)-2*d.spc) DIV d.spc;  d.fat16 := d.fatsize > 0FF0H;
(*
					Kernel.WriteString("OpenDrive ");  Kernel.WriteInt(num, 1);  Kernel.WriteLn;
					Kernel.WriteString("  part=");  Kernel.WriteInt(d.part, 1);  Kernel.WriteString("  spc=");
					Kernel.WriteInt(d.spc, 1);  Kernel.WriteString("  sres=");  Kernel.WriteInt(d.sres, 1);
					Kernel.WriteString("  fats=");  Kernel.WriteInt(d.fats, 1);  Kernel.WriteString("  dirsize=");
					Kernel.WriteInt(d.dirsize, 1);  Kernel.WriteString("  totals=");  Kernel.WriteInt(d.totals, 1);
					Kernel.WriteString("  spf=");  Kernel.WriteInt(d.spf, 1);  Kernel.WriteLn;
					Kernel.WriteString("  fatsec=");  Kernel.WriteInt(d.fatsec, 1);  Kernel.WriteString("  rootsec=");  
					Kernel.WriteInt(d.rootsec, 1);  Kernel.WriteString("  datasec=");  Kernel.WriteInt(d.datasec, 1);  
					Kernel.WriteString("  fatsize=");  Kernel.WriteInt(d.fatsize, 1);
					IF d.fat16 THEN Kernel.WriteString("  fat16") ELSE Kernel.WriteString("  fat12") END;  Kernel.WriteLn;
					Kernel.WriteString("  serial=");  Kernel.WriteHex(d.serial, 8);  Kernel.WriteString("  label=");
					Kernel.WriteString(d.label);  Kernel.WriteLn;
*)
					IF d.fat16 THEN
						NEW(d.fat, d.spf*SS DIV 2);
						ReadSectors(d, d.fatsec, d.spf, d.fat^, res)
					ELSE
						ReadFAT12(d, res)
					END;
					IF res = 0 THEN
						NEW(d.dir, d.dirsize*32);
						ReadSectors(d, d.rootsec, (d.dirsize*32) DIV SS, d.dir^, res);
						IF res = 0 THEN
							d.fatdirty := FALSE;
							d.next := drives.next;  drives.next := d
						END
					END
				END
			END
		END
	END;
	IF res # 0 THEN d := NIL END
END OpenDrive;

(* FindFile - Find a file in a directory starting at ofs.  num is number of entries in directory.
	name is a dir entry name
	returns offset of found entry or -1 *)

PROCEDURE FindFile(name: DirEntryName;  ofs: LONGINT;  VAR dir: ARRAY OF CHAR;  num: LONGINT): LONGINT;
VAR i, j, p, q: LONGINT;
BEGIN
	ASSERT(name # "");
	(* look for name *)
	i := ofs;  j := num*32;
	WHILE i # j DO
		IF dir[i] # 0X THEN
			p := i;  q := 0;  WHILE (q # 11) & ((dir[p] = name[q]) OR (name[q] = "?")) DO INC(p);  INC(q) END;
			IF q = 11 THEN j := i
			ELSE INC(i, 32)
			END
		ELSE i := j
		END
	END;
	IF i = num*32 THEN i := -1 END;
	RETURN i
END FindFile;

(* SeparateName - separate str into a prefix and a name; the prefix is
	returned in str; If name is invalid, empty str and name is returned. *)
	
PROCEDURE SeparateName(str: ARRAY OF CHAR; VAR prefix: ARRAY OF CHAR; VAR name: DirEntryName);
VAR i, j : LONGINT;
BEGIN
(* Pre: str is result of a Check operation; all "\"s have been changed to "/" *)
	i := 0;  j := -1;
	WHILE str[i] # 0X DO
		IF str[i] = "/" THEN j := i END;
		INC(i)
	END;
	(* now j is position of last / *)
	IF j >= 2 THEN
		str[j] := 0X;
		COPY(str, prefix);
		(* now prefix is original str without last part *)
		INC(j);
		(* convert name to DOS directory format - 11 (name+ext., both zero-padded when shorter than 8,3 resp. *)
		IF str[j] = "." THEN
			IF str[j+1] = 0X THEN (* "." *)
				name := "."; i := 1
			ELSIF (str[j+1] = ".") & (str[j+2] = 0X) THEN (* ".." *)
				name := ".."; i := 2
			ELSE (* funny entry *)
				str[0] := 0X; name[0] := 0X
			END
		ELSE
			i := 0;
			(* copy up to first "." or 0X or first 8 chars. in name *)
			WHILE (str[j] # ".") & (str[j] # 0X) DO
				IF (i # 8) THEN name[i] := Cap(str[j]); INC(i) END;
				INC(j)
			END;
			(* now i = position of "." | 0X in name or i = 8,
				and j = position of "." or 0X in str *)
			WHILE i # 8 DO name[i] := " ";  INC(i) END;
			IF str[j] = "." THEN INC(j) END;
			WHILE str[j] # 0X DO
				IF i # 11 THEN name[i] := Cap(str[j]);  INC(i) END;
				INC(j)
			END
		END;
		WHILE i # 11 DO name[i] := " ";  INC(i) END;
		name[i] := 0X;
		i := 0;  WHILE (i # 8) & (name[i] # "*") DO INC(i) END;	(* find first * in name *)
		WHILE i # 8 DO name[i] := "?";  INC(i) END;
		WHILE (i # 11) & (name[i] # "*") DO INC(i) END;	(* find first * in ext *)
		WHILE i # 11 DO name[i] := "?";  INC(i) END
	ELSE
		prefix[0] := 0X; name[0] := 0X
	END
END SeparateName;

(* GetDir - Get information from a directory entry *)

PROCEDURE GetDir(VAR dir: ARRAY OF CHAR;  ofs: LONGINT; VAR attr : SET;  VAR time, date, firstcl, len: LONGINT);
VAR t: LONGINT;
BEGIN
	t (*attr*) := ORD(dir[ofs+0BH]); attr := SYSTEM.VAL(SET, t);
	t := GetUWord(dir, ofs+16H);
	time := (t MOD 65536)*2;
	t := GetUWord(dir, ofs+18H);
	date := (t MOD 32) + (t DIV 32 MOD 16)*32 + ((t DIV 512) + 80)*512;
	firstcl := GetUWord(dir, ofs+1AH);
	IF (firstcl = 0) & ({VolLabel, SubDir} * attr = {}) THEN
		firstcl := -1 (* empty file, see PutDir *)
	END;
	SYSTEM.GET(SYSTEM.ADR(dir[ofs+1CH]), len)
END GetDir;

(* PutDir - Update information in a directory entry *)

PROCEDURE PutDir(VAR dir: ARRAY OF CHAR; ofs: LONGINT; name: ARRAY OF CHAR; attr : SET;
	time, date, firstcl, len, operation: LONGINT; delete: BOOLEAN;  VAR res: LONGINT);
VAR t: LONGINT; str: DirEntryName; prefix: Filename;
BEGIN
	IF firstcl = -1 THEN firstcl := 0 END;
	IF (operation IN {rename, updatedir}) & (dir[ofs] = 0E5X) THEN
		res := eFileErased
	ELSE
		IF operation IN {register, rename} THEN
			SeparateName(name, prefix, str);
			FOR t := 0 TO 10 DO dir[ofs + t] := str[t] END (* new name *)
		ELSIF (operation = purge) & delete THEN
			dir[ofs] := 0E5X (*mark entry as deleted*)
		END;
		dir[ofs+0BH] := CHR(SHORT(SHORT(SYSTEM.VAL(LONGINT, attr))));
		t :=(time DIV 2)+SYSTEM.LSH(((date MOD 32)+(date DIV 32 MOD 16)*32
			  + ((date DIV 512) - 80)*512), 16);
		SYSTEM.PUT(SYSTEM.ADR(dir[ofs+16H]), t);
		dir[ofs+1AH] := CHR(firstcl MOD 256); dir[ofs+1BH] :=CHR(firstcl DIV 256);
		SYSTEM.PUT(SYSTEM.ADR(dir[ofs+1CH]), len);
		res := 0
	END
END PutDir;

(* Locate the drive, directory and offset in that directory file for file called name.
	Return values: if (d # NIL) then file exist, and the file's attributes are returned. *)

PROCEDURE LocateFile(name: ARRAY OF CHAR;  VAR d: Drive;  VAR firstdircl, dircl, dirofs, 
	time, date, firstcl, len: LONGINT; VAR attr: SET;  VAR res: LONGINT);
VAR
	name1: DirEntryName;
	ddirfirstcl, ddircl, ddirofs, dtime, ddate, dfirstcl, dlen, cl, ofs: LONGINT;
	dattr: SET;
BEGIN (* Pre: name is result of a Check() operation *)
	res := 0;
	SeparateName(name, name, name1);
	IF (name = "") OR (name1 = "") THEN d := NIL
	ELSE
		(* now name1 is last part of original name, and directly comparable
			with directory entries, i.e. name and extension padded with spaces *)
		IF name[2] = 0X THEN
			(* prefix is only a disk name *)
			IF (name[0] >= "A") & (name[0] <= "Z") & (name[1] = ":") THEN
				OpenDrive(name[0], d, res);
				IF (d # NIL) & (res = 0) THEN
					ofs := FindFile(name1, 0, d.dir^, d.dirsize);
					IF ofs # -1 THEN
						GetDir(d.dir^, ofs, attr, time, date, firstcl, len);
						firstdircl := 0; dircl := 0; dirofs := ofs
					ELSE d := NIL
					END
				ELSE d := NIL
				END
			ELSE d := NIL
			END
		ELSE
			(* locate the directory and find the file's entry in it *)
			LocateFile(name, d, ddirfirstcl, ddircl, ddirofs, dtime, ddate, dfirstcl, dlen, dattr, res);
			IF (res = 0) & (d # NIL) & (SubDir IN dattr) THEN
				IF dfirstcl = 0 THEN (* prefix leads back to root dir. of drive, i.e. ends with a ".." *)
					ofs := FindFile(name1, 0, d.dir^, d.dirsize);
					IF ofs # -1 THEN
						GetDir(d.dir^, ofs, attr, time, date, firstcl, len);
						firstdircl := 0; dircl := 0; dirofs := ofs
					ELSE d := NIL
					END
				ELSE
					IF d.bpc > LEN(dirbuf^) THEN
						res := eBufferOverflow; d := NIL
					ELSE
						cl := dfirstcl; (* first cluster of directory file *)
						LOOP
							ReadSectors(d, d.datasec + cl*d.spc, d.spc, dirbuf^, res);
							IF res = 0 THEN
								ofs := FindFile(name1, 0, dirbuf^, d.bpc DIV 32)
							ELSE ofs := -1
							END;
							IF (res # 0) OR (ofs # -1) THEN EXIT END; (*error/found*)
							cl := d.fat[cl];  IF cl < 0 THEN INC(cl, 10000H) END;
							IF cl > 0FFF0H THEN EXIT END (* end of cluster chain *)
						END;
						IF ofs # -1 THEN
							GetDir(dirbuf^, ofs, attr, time, date, firstcl, len);
							firstdircl := dfirstcl; dircl := cl; dirofs := ofs
						ELSE d := NIL
						END
					END;
				END
			ELSE (* (res # 0) OR (d = NIL) OR ~(SubDir in attr) *) d := NIL
			END
		END
	END
END LocateFile;

(* Allocates a directory entry for the file. The disk cluster that contains the
	entry and the byte offset of the entry into that cluster, is returned in f.dircl
	and f.dirofs *)

PROCEDURE AllocEntry(VAR dir: ARRAY OF CHAR; dirSize: LONGINT; VAR dirofs: LONGINT);
VAR i: LONGINT;
BEGIN
	i := 0;
	WHILE (i # dirSize) & (dir[i] # 0E5X) & (dir[i] # 0X) DO
		INC(i, 32) (* not-erased OR used *)
	END;
	IF i < dirSize THEN dir[i] := AllocDirMark END;
	dirofs := i
END AllocEntry;

PROCEDURE AllocateDirEntry(VAR f: Handle0; VAR res: LONGINT);
VAR dir : Filename; tmp: DirEntryName; d: Drive; dircl, i, max, pcl: LONGINT;  attr: SET;
BEGIN
	IF (f.dircl # -1) OR (f.dirofs # -1) OR (f.firstdircl # -1) THEN
		res := eDirEntryAlreadyAllocated
	ELSE
		LocateFile(f.name, d, f.firstdircl, f.dircl, f.dirofs, i, i, i, i, attr, res);
		IF res = 0 THEN
			IF d # NIL THEN (* a dir. entry for name of this file already exists *)
				IF (attr * {ReadOnly,System,VolLabel,SubDir}) # {} THEN (* read-only|system|label|subdir *)
					res := eCannotReuseDirEntry
				ELSE (* else - dir. entry will be re-used *)
					res := eDirEntryAlreadyExists
				END
			ELSE (* d = NIL *)
				SeparateName(f.name, dir, tmp);
				(* if prefix is more than a drive name, check if its a directory *)
				IF (dir[2] # 0X) THEN LocateFile(dir, d, i, i, i, i, i, dircl, i, attr, res) END;
				IF res = 0 THEN
					(* find an empty entry in the directory and assign to file *)
					IF (dir[2] = 0X) (* only a drive name *) 
						OR ((d # NIL) & (d = f.drive) & (SubDir IN attr) & (dircl = 0))
						(* entry in a subdir that leads back to root *) THEN
						(* file is in root dir. *)
						max := f.drive.dirsize*32;
						AllocEntry(f.drive.dir^, max, i);
						IF i # max THEN
							f.firstdircl := 0; f.dircl := 0; f.dirofs := i
						ELSE
							res := eRootDirFull
						END
					ELSIF (d = NIL) OR (d # f.drive) OR ~(SubDir IN attr) THEN
						(* prefix is more than a drive name, but not a valid directory *)
						res := eFilePrefixNotaDir
					ELSE (* file in a subdir. - dircl now = first cluster of dir. file *)
						f.firstdircl := dircl;  pcl := 0;
						LOOP
							(* read a cluster of the directory file *)
							ReadSectors(d, d.datasec + dircl*d.spc, d.spc, dirbuf^, res);
							IF res # 0 THEN EXIT END;
							AllocEntry(dirbuf^, d.bpc, i); (* try to find open entry *)
							IF i < d.bpc THEN EXIT END; (* found *)
							pcl := dircl;  dircl := d.fat[dircl];  IF dircl < 0 THEN INC(dircl, 10000H) END;
							IF dircl > 0FFF0H THEN EXIT END (* end of cluster chain *)
						END;
						IF res = 0 THEN
							IF i < d.bpc THEN
								f.dircl := dircl; f.dirofs := i
								(* write dirbuf back to disk if server becomes concurrent *)
							ELSE
								dircl := pcl+1;	(* look for free cluster, pcl is last dir cluster or 0 *)
								LOOP
									IF dircl >= d.fatsize THEN dircl := 2 END;	(* wrap *)
									IF d.fat[dircl] = 0 THEN EXIT END;	(* found free cluster *)
									INC(dircl);
									IF dircl = pcl THEN res := eDiskFull; EXIT END
								END;
								IF res = 0 THEN
									ASSERT(pcl # 0);	(* we are extending an existing dir *)
									d.fat[pcl] := SHORT(dircl);  d.fat[dircl] := -1;  d.fatdirty := TRUE;
									FOR i := 1 TO d.bpc-1 DO dirbuf[i] := 0X END;
									dirbuf[0] := AllocDirMark;	(* allocate the first entry *)
									WriteSectors(d, d.datasec + dircl*d.spc, d.spc, dirbuf^, res);
									IF res = 0 THEN f.dircl := dircl;  f.dirofs := 0 END
								END
							END
						END
					END
				END
			END
		END;
		IF (res # 0) & (res # eDirEntryAlreadyExists) THEN
			f.dircl := -1;  f.dirofs := -1;  f.firstdircl := -1
		END
	END
END AllocateDirEntry;

(* Length0 - return length in bytes of file. *)

PROCEDURE Length0(VAR f: Handle0): LONGINT;
BEGIN
	RETURN f.aleng*f.bufSize + f.bleng
END Length0;

(* UpdateDirEntry - update the directory entry for the file, on disk. *)

PROCEDURE UpdateDirEntry(VAR f: Handle0; operation: LONGINT; delete: BOOLEAN; VAR res: LONGINT);
VAR buf : ARRAY SS OF CHAR; d : Drive;
BEGIN (* Pre: f is a registered file *)
	IF ReadOnly IN f.attr THEN
		res := eFileIsReadOnlyInServer
	ELSIF (f.dircl < 0) OR (f.dirofs < 0) OR (f.firstdircl < 0) THEN
		res := eInvalidDirEntry
	ELSE
		(*Kernel.GetClock(f.time, f.date);*)
		INCL(f.attr, Archive); (* set archive bit *)
		d := f.drive;
		IF f.dircl = 0 THEN (* in root directory *)
			PutDir(d.dir^, f.dirofs, f.name, f.attr, f.time, f.date, f.firstcl, Length0(f), operation, delete, res);
			(*optimize - only write changed sector*)
			IF res = 0 THEN
				WriteSectors(d, d.rootsec, (d.dirsize*32) DIV SS, d.dir^, res);
			END
		ELSE (* in a subdir *)
			ReadSectors(d, d.datasec + f.dircl*d.spc + (f.dirofs DIV SS), 1, buf, res);
			IF res = 0 THEN
				PutDir(buf, f.dirofs MOD SS, f.name, f.attr, f.time, f.date, f.firstcl, Length0(f), operation, delete, res);
				IF res = 0 THEN
					WriteSectors(d, d.datasec+f.dircl*d.spc+(f.dirofs DIV SS),1, buf,res)
				END
			END
		END;
		IF res = 0 THEN
			FlushDrive(f.drive, res);
			IF (operation = purge) & delete THEN
				f.drive := NIL; f.firstcl := -1; f.dircl := -1; f.name[0] := 0X
			END
		END
	END
END UpdateDirEntry;

(* Purge0 - deallocate clusters in FAT that belongs to file. *)

PROCEDURE Purge0(VAR f: Handle0; delete: BOOLEAN; VAR res: LONGINT);
VAR d: Drive; cl, pcl, r: LONGINT;
BEGIN
	IF ReadOnly IN f.attr THEN
		res := eFileIsReadOnlyInServer
	ELSE
		f.aleng := 0; f.bleng := 0;
		d := f.drive; d.fatdirty := TRUE;
		cl := f.firstcl;
		f.firstcl := -1; f.ccl := -1;
		WHILE (cl < d.fatsize) & (cl # -1) DO
			pcl := cl; cl := d.fat[cl];  IF cl < 0 THEN INC(cl, 10000H) END;
			IF cl > 0FFF0H THEN cl := -1 END;	(* eof *)
			d.fat[pcl] := 0	(* free cluster *)
		END;
		IF f.dircl >= 0 THEN (* registered *)
			UpdateDirEntry(f, purge, delete, res)
		END;
		FlushDrive(d, r);
		IF res = 0 THEN res := r END
	END
END Purge0;

(* Old0 - return a valid file handle if file exists. *)

PROCEDURE Old0(VAR f: Handle0; VAR res: LONGINT);
VAR d: Drive; len: LONGINT;
BEGIN
	LocateFile(f.name, d, f.firstdircl, f.dircl, f.dirofs, f.time, f.date, f.firstcl, len, f.attr, res);
	IF res = 0 THEN
		IF (d = NIL) OR (VolLabel IN f.attr) THEN
			res := eFileDoesNotExist
		ELSIF SubDir IN f.attr THEN
			res := eCannotOpenSubDir
		ELSIF (f.firstcl < 2) & (f.firstcl # -1) THEN
			res := eInvalidFirstCluster
		ELSE
			IF f.firstcl = -1 THEN (* empty file - see PutDir *)
				IF len # 0 THEN
					res := eInvalidFileLength
				ELSE
					f.aleng := 0; f.bleng := 0;
					f.ccl := -1; f.capos := -1
				END
			ELSE (* file has at least one cluster *)
				f.aleng := len DIV d.bpc; f.bleng := len MOD d.bpc;
				f.ccl := f.firstcl; f.capos := 0
			END;
			f.drive := d; f.bufSize := d.bpc;
			f.readOnly := ReadOnly IN f.attr
		END
	END
END Old0;

(* New0 - check that file name prefix is a valid, existing directory; if so,
	initialize the file handle *)

PROCEDURE New0(VAR f: Handle0; VAR res: LONGINT);
VAR t: LONGINT; dirAttr: SET; dir: Filename; tmp: DirEntryName;
BEGIN
	IF CheckNew THEN
		Old0(f, res);
		IF res = 0 THEN res := eFileNameAlreadyExists; RETURN END
	END;
	SeparateName(f.name, dir, tmp);
	IF tmp[0] # " " THEN
		IF dir[2] = 0X THEN (* root dir *)
			OpenDrive(dir[0], f.drive, res)
		ELSE
			LocateFile(dir, f.drive, t, t, t, t, t, t, t, dirAttr, res)
		END
	ELSE
		res := eInvalidFileName
	END;
	IF res = 0 THEN
		IF (f.drive # NIL) & ((dir[2] = 0X) OR (SubDir IN dirAttr)) THEN
			f.bufSize := f.drive.bpc; f.readOnly := FALSE;
			f.firstcl := -1;  f.firstdircl := -1; f.dircl := -1; f.dirofs := -1; f.attr := {};
			f.ccl := -1; f.capos := -1;
			f.aleng := 0; f.bleng := 0;
			Kernel.GetClock(f.time, f.date)
		ELSE
			res := eInvalidDirectory
		END
	END
END New0;

(* ReadCluster - read cluster number *apos* of file from disk. *)

PROCEDURE ReadCluster(drive: Drive; firstcl: LONGINT; VAR ccl, capos: LONGINT;
	VAR data: ARRAY OF SYSTEM.BYTE; apos: LONGINT;  VAR res, rplen: LONGINT);
VAR d: Drive;  cl, p: LONGINT;
BEGIN (* Pre: the file contains a cluster corresponding to apos *)
	res := -1;
	d := drive;
	IF apos < 0 THEN
		res := eClusterOutsideFile
	ELSIF firstcl < 2 THEN
		res := eInvalidFirstCluster
	ELSIF (ccl > 1) & (ccl < d.fatsize) & (apos = capos+1) THEN (* adjacent cluster *)
		cl := d.fat[ccl];  IF cl < 0 THEN INC(cl, 10000H) END;
		IF cl > 0FFF0H THEN res := eClusterOutsideFile END
	ELSE
		p := apos;  cl := firstcl;
		WHILE (p # 0) & (res = -1) DO
			DEC(p);  cl := d.fat[cl];  IF cl < 0 THEN INC(cl, 10000H) END;
			IF cl > 0FFF0H THEN
				res := eClusterOutsideFile
			END
		END
	END;
	IF res = -1 THEN
		IF cl < 2 THEN
			res := eInternalServerError
		ELSE
			ReadSectors(d, d.datasec + d.spc*cl, d.spc, data, res);
			IF res = 0 THEN
				rplen := d.bpc;
				ccl := cl;  capos := apos	(* new cache position *)
			END
(*		consistency check not necessary
			cl := d.fat[cl];  IF cl < 0 THEN INC(cl, 10000H) END;
			IF (apos < aleng-1) OR ((apos = aleng-1) & (bleng > 0)) THEN
				ASSERT(cl <= 0FFF0H, "ReadCluster(4)")
			ELSE
				ASSERT(cl > 0FFF0H, "ReadCluster(5)")
			END
*)
		END
	END
END ReadCluster;

(* WriteCluster - write cluster number *apos* of file to disk. If no clusters have been allocated to the file in the FAT, 
	firstcl returns the new (first) cluster allocated for the file. *)

PROCEDURE WriteCluster(drive: Drive; VAR firstcl: LONGINT; attr: SET;
	VAR data: ARRAY OF SYSTEM.BYTE; apos: LONGINT;  VAR res: LONGINT);
VAR d: Drive;  p, cl, pcl, mcl: LONGINT;
BEGIN
	IF ReadOnly IN attr THEN
		res := eFileIsReadOnlyInServer
	ELSIF apos < 0 THEN
		res := eClusterOutsideFile
	ELSE
		res := -1;
		d := drive;
		p := apos;  cl := firstcl;  pcl := 1;
		WHILE (cl # -1) & (p # 0) DO
			DEC(p);  pcl := cl;
			cl := d.fat[cl];  IF cl < 0 THEN INC(cl, 10000H) END;
			IF cl > 0FFF0H THEN cl := -1 END	(* eof *)
		END;
		IF cl = -1 THEN	(* cluster not allocated yet for apos *)
			IF p # 0 THEN
				res := eClusterOutsideFile
			ELSE
				(* all clusters up to here allocated *)
				mcl := pcl+1;  cl := mcl;
				LOOP
					IF cl >= d.fatsize THEN cl := 2 END;	(* wrap *)
					IF d.fat[cl] = 0 THEN EXIT END;	(* found free cluster *)
					INC(cl);
					IF cl = mcl THEN res := eDiskFull; EXIT END	(* disk full *)
				END;
				IF res = -1 THEN
					IF pcl # 1 THEN d.fat[pcl] := SHORT(cl) END; (*link previous cluster*)
					d.fat[cl] := -1;	(* allocate the cluster *)
					d.fatdirty := TRUE;
					IF firstcl = -1 THEN firstcl := cl END
				END
			END
		END;
		IF res = -1 THEN
			WriteSectors(d, d.datasec + d.spc*cl, d.spc, data, res)
		END
	END
END WriteCluster;

(* Register0 - create and write a directory entry for the file. *)

PROCEDURE Register0(VAR f: Handle0; VAR res: LONGINT);
BEGIN
	res := 0;
	AllocateDirEntry(f, res);
	IF res = eDirEntryAlreadyExists THEN
		f.dircl := -1;  f.dirofs := -1;  f.firstdircl := -1;
		Delete(f.name, res);	(* delete old file (forward reference) *)
		IF res = 0 THEN AllocateDirEntry(f, res) END
	END;
	IF res = 0 THEN
		UpdateDirEntry(f, register, FALSE, res)
	END
END Register0;

PROCEDURE Rename0(VAR old, new: Filename; VAR res: LONGINT);
VAR
	dir: Filename; f: Handle0; d: Drive; firstdircl, t: LONGINT;
	attr: SET; tmp: DirEntryName;
BEGIN
	COPY(old, f.name);
	Old0(f, res);
	IF res = 0 THEN
		IF ReadOnly IN f.attr THEN
			res := eFileIsReadOnlyInServer
		ELSE
			(* Check if in same partition and directory *)
			SeparateName(new, dir, tmp);
			IF dir[2] = 0X THEN (* root dir *)
				OpenDrive(dir[0], d, res)
			ELSE
				LocateFile(dir, d, t, t, t, t, t, firstdircl, t, attr, res)
			END;
			IF res = 0 THEN
				IF (d # NIL) & (d = f.drive) & (* same drive? *)
				(((dir[2] = 0X) & (f.firstdircl = 0) & (f.dircl = 0)) (* both in root? *)
				  OR ((dir[2] # 0X) & (SubDir IN attr) & (f.firstdircl=firstdircl))) (* both in same subdir. *)
				THEN
					LocateFile(new, d, t, t, t, t, t, t, t, attr, res);
					IF res = 0 THEN
						IF d # NIL THEN
							res := eFileNameAlreadyExists
						ELSE
							COPY(new, f.name);
							UpdateDirEntry(f, rename, FALSE, res)
						END
					END
				ELSE
					res := eNotSameDirectory
				END
			END
		END
	END
END Rename0;

PROCEDURE Low(ch: CHAR): CHAR;
BEGIN
	IF (ch >= "A") & (ch <= "Z") THEN RETURN CHR(ORD(ch)+32)
	ELSE RETURN ch
	END
END Low;

PROCEDURE ExtractName(VAR dir: ARRAY OF CHAR;  ofs: LONGINT;  VAR name: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
	j := 0;
	IF (dir[ofs] # 0E5X) & (dir[ofs] # 0X) THEN
		i := ofs;  WHILE (j # 8) & (dir[i] # " ") DO name[j] := Low(dir[i]);  INC(i);  INC(j) END;
		i := ofs+8;
		IF dir[i] # " " THEN
			name[j] := ".";  INC(j);
			name[j] := Low(dir[i]);  INC(j);  INC(i);
			IF dir[i] # " " THEN
				name[j] := Low(dir[i]);  INC(j);  INC(i);
				IF dir[i] # " " THEN
					name[j] := Low(dir[i]);  INC(j);  INC(i)
				END
			END
		END
	END;
	name[j] := 0X
END ExtractName;

PROCEDURE GetFreeDiskSpace*(drive: CHAR; VAR size, res: LONGINT);
VAR d: Drive; cl, space: LONGINT;
BEGIN
	OpenDrive(Cap(drive), d, res);
	IF (res = 0) THEN
		(* d # NIL *)
		space := 0;
		FOR cl := 2 TO d.fatsize-1 DO
			IF d.fat[cl] = 0 THEN INC(space) END
		END;
		size := space * d.bpc					   (* clusters * bytes/cluster *)
	END
END GetFreeDiskSpace;

(** Enumerate a directory.  path must be a full path specification with a 8.3-style wildcard. *)

PROCEDURE Enumerate*(path: ARRAY OF CHAR;  handler: EntryHandler;  VAR res: LONGINT);
CONST Ext = {ReadOnly..VolLabel};
VAR
	name: Filename;  mask: DirEntryName;  d: Drive;  attr: SET;  continue: BOOLEAN;
	firstdircl, dircl, dirofs, time, date, firstcl, len: LONGINT;  fname: ARRAY 13 OF CHAR;
BEGIN
	Check(path, name, res);
	IF (res = 0) OR (res = eNameIsWild) THEN
		LocateFile(name, d, firstdircl, dircl, dirofs, time, date, firstcl, len, attr, res);
		IF (dirofs = -1) OR (d = NIL) THEN res := eFileDoesNotExist END;
		IF res = 0 THEN
			(* read the dircluster (or root) & match name; call handler; continue until end*)
			SeparateName(name, name, mask);
			continue := TRUE;
			IF dircl = 0 THEN	(* root *)
				dirofs := FindFile(mask, dirofs, d.dir^, d.dirsize);
				WHILE continue & (dirofs # -1) DO
					GetDir(d.dir^, dirofs, attr, time, date, firstcl, len);
					ExtractName(d.dir^, dirofs, fname);
					IF (fname[0] # 0X) & (attr # Ext) THEN handler(fname, time, date, len, attr, continue) END;
					IF continue THEN dirofs := FindFile(mask, dirofs+32, d.dir^, d.dirsize) END
				END
			ELSE	(* ~root *)
				LOOP
					ReadSectors(d, d.datasec + dircl*d.spc, d.spc, dirbuf^, res);
					IF res # 0 THEN EXIT END;	(* ### *)
					dirofs := FindFile(mask, dirofs, dirbuf^, d.bpc DIV 32);
					WHILE continue & (dirofs # -1) DO
						GetDir(dirbuf^, dirofs, attr, time, date, firstcl, len);
						ExtractName(dirbuf^, dirofs, fname);
						IF (fname[0] # 0X) & (attr # Ext) THEN handler(fname, time, date, len, attr, continue) END;
						IF continue THEN dirofs := FindFile(mask, dirofs+32, dirbuf^, d.bpc DIV 32) END
					END;
					dircl := d.fat[dircl];  IF dircl < 0 THEN INC(dircl, 10000H) END;
					IF dircl > 0FFF0H THEN EXIT END; (* ### *)
					dirofs := 0	(* start of next dir cluster *)
				END
			END
		END
	END
END Enumerate;

PROCEDURE Initialize;
VAR i: SHORTINT;  type: INTEGER;
BEGIN
	NEW(dirbuf, 16384);
	NEW(drives);  drives.next := NIL;  drives.num := -1;
	Partition.GetInfo(info);
	FOR i := 0 TO info.numpar-1 DO
		type := info.par[i].type;
		IF (type # 1) & (type # 4) & (type # 6) THEN info.par[i].letter := 0X END	(* only allow DOS partitions *)
	END
END Initialize;

(* -- Client procedures -- *)

PROCEDURE SameFile(VAR h0, h1: Handle0): BOOLEAN;
BEGIN
	RETURN (h0.dircl # -1) & (h0.dircl = h1.dircl) & (h0.dirofs = h1.dirofs) & (h0.drive = h1.drive)
END SameFile;

(** New - Creates a new file with the specified name. Returns a valid File if successful, otherwise NIL. *)

PROCEDURE New*(name: ARRAY OF CHAR; VAR res: LONGINT): File;
VAR f: File; buf: Buffer; namebuf: Filename; handle: Handle0;
BEGIN
	f := NIL;
	Check(name, namebuf, res);
	IF res = 0 THEN
		COPY(namebuf, handle.name);
		New0(handle, res);
		IF res = 0 THEN
			NEW(f); f.handle := handle;
			NEW(buf);  buf.apos := 0;  buf.lim := 0;  buf.mod := FALSE;  
			buf.next := buf;
			NEW(buf.data, f.handle.bufSize);
			f.nofbufs := 1;
			f.firstbuf := buf;
			f.registered := FALSE; f.mod := TRUE
		END
	END;
	RETURN f
END New;

(* ReadBuf - Read data into a buffer *)

PROCEDURE ReadBuf(f: File;  buf: Buffer; apos: LONGINT; VAR res: LONGINT);
VAR rplen: LONGINT;
BEGIN
	(* Pre: the file contains a cluster corresponding to apos, or trying to
		read last cluster that is still empty, therefore not on disk *)
	IF (apos = f.handle.aleng) & (f.handle.bleng = 0) THEN
		res := 0
	ELSE
		ReadCluster(f.handle.drive, f.handle.firstcl, f.handle.ccl, f.handle.capos, buf.data^, apos, res, rplen);
		ASSERT(rplen <= LEN(buf.data^))
	END;
	IF res = 0 THEN
		IF apos < f.handle.aleng THEN
			buf.lim := f.handle.bufSize
		ELSE
			buf.lim := f.handle.bleng
		END;
		buf.apos := apos
	ELSE
		buf.apos := -1; buf.lim := 0
	END;
	buf.mod := FALSE
END ReadBuf;

(* WriteBuf - Write a modified buffer *)

PROCEDURE WriteBuf(f: File; buf: Buffer; VAR res: LONGINT);
BEGIN
	WriteCluster(f.handle.drive, f.handle.firstcl, f.handle.attr, buf.data^, buf.apos, res);
	Kernel.GetClock(f.handle.time, f.handle.date);  f.mod := TRUE;
	IF res = 0 THEN buf.mod := FALSE END
END WriteBuf;

(* Buf - Return a buffer containing the specified position, if already present *)

PROCEDURE Buf(f: File;  apos: LONGINT): Buffer;
VAR buf: Buffer;
BEGIN
	buf := f.firstbuf;
	LOOP
		IF buf.apos = apos THEN EXIT END;
		buf := buf.next;
		IF buf = f.firstbuf THEN buf := NIL;  EXIT END
	END;
	RETURN buf
END Buf;

(* GetBuf - Return a buffer containing the specified position, loading it if necessary. *)

PROCEDURE GetBuf(f: File;  apos: LONGINT; VAR res: LONGINT): Buffer;
VAR buf: Buffer;
BEGIN
	res := 0;
	buf := f.firstbuf;
	LOOP
		IF buf.apos = apos THEN EXIT END;
		IF buf.next = f.firstbuf THEN
			IF (f.nofbufs < MaxBufs) THEN (*allocate new buffer*)
				NEW(buf);  buf.next := f.firstbuf.next;  f.firstbuf.next := buf;
				NEW(buf.data, f.handle.bufSize);
				INC(f.nofbufs)
			ELSE (*reuse one of the buffers*)
				f.firstbuf := buf;
				IF buf.mod THEN WriteBuf(f, buf, res) END
			END;
			IF res = 0 THEN
				buf.apos := apos;
				IF apos <= f.handle.aleng THEN ReadBuf(f, buf, apos, res)
				ELSE res := eInternalError
				END;
			END;
			EXIT
		END;
		buf := buf.next
	END;
	IF res # 0 THEN buf := NIL END;
	RETURN buf
END GetBuf;

(** Old - Open an existing file. The same file descriptor is returned if a file is opened multiple times. *)

PROCEDURE Old*(name: ARRAY OF CHAR; VAR res: LONGINT): File;
VAR f: File; handle: Handle0; buf: Buffer; namebuf: Filename;
BEGIN
	res := 0;
	f := NIL;
	Check(name, namebuf, res);
	IF res = 0 THEN
		COPY(namebuf, handle.name);
		Old0(handle, res);
		IF res = 0 THEN
			IF KeepList THEN
				f := root.next;
				WHILE (f # NIL) & ~SameFile(f.handle, handle) DO f := f.next END
			ELSE
				f := NIL
			END;
			IF f = NIL THEN
				NEW(f); f.handle := handle;
				NEW(buf); buf.next := buf; 
				NEW(buf.data, f.handle.bufSize);
				IF (f.handle.aleng = 0) & (f.handle.bleng = 0) THEN
					buf.apos := 0; buf.lim := 0; buf.mod := FALSE
				ELSE (* file is not empty *)
					ReadBuf(f, buf, 0, res)
				END;
				IF res # 0 THEN
					f := NIL
				ELSE
					f.firstbuf := buf;  f.nofbufs := 1;
					f.registered := TRUE; f.mod := FALSE;
					IF KeepList THEN
						f.next := root.next; root.next := f
					END
				END
			END
		END
	END;
	RETURN f
END Old;

(* Unbuffer - write all modified buffers of file to disk, possibly updating the directory entry. *)

PROCEDURE Unbuffer(f: File; VAR res: LONGINT);
VAR buf: Buffer;
BEGIN
	res := 0;
	buf := f.firstbuf;
	REPEAT
		IF buf.mod THEN WriteBuf(f, buf, res) END;
		buf := buf.next
	UNTIL (res # 0) OR (buf = f.firstbuf);
	IF (res = 0) & f.registered & f.mod THEN
		UpdateDirEntry(f.handle, updatedir, FALSE, res)
	END;
	IF res = 0 THEN f.mod := FALSE END
END Unbuffer;

(** Register - register a file created with New in the directory, replacing the previous entry in the directory 
	with the same name. The file is automatically closed. *)

PROCEDURE Register*(f: File; VAR res: LONGINT);
VAR ignore: LONGINT;
BEGIN
	res := 0;
	IF f # NIL THEN
		Unbuffer(f, res);
		IF (res = 0) & ~f.registered THEN
			Register0(f.handle, res);
			IF res = 0 THEN
				f.registered := TRUE;
				IF KeepList THEN
					f.next := root.next; root.next := f
				END
			ELSE
				Purge(f, ignore)	(* forward *)
			END
		END
	END
END Register;

(** Close - flushes the changes made to a file to disk, and updates directory entry if registered. 
	Does NOT Register a new file automatically. *)

PROCEDURE Close*(f: File; VAR res: LONGINT);
BEGIN
	res := 0;
	IF f # NIL THEN Unbuffer(f, res) END
END Close;

(* PurgeFile - deallocate all file's clusters in FAT, and depending on the
	value of *delete*, delete the file name from the directory. *)
	
PROCEDURE PurgeFile(f: File; delete: BOOLEAN; VAR res: LONGINT);
BEGIN
	res := 0;
	IF f # NIL THEN
		f.nofbufs := 1; f.firstbuf.next := f.firstbuf; f.firstbuf.apos := 0;
		f.firstbuf.lim := 0; f.firstbuf.mod := FALSE;
		f.mod := TRUE;			(* so that dir. entry will be updated if registered *)
		Purge0(f.handle, delete, res)	(* deallocate sectors in FAT *)
	END
END PurgeFile;

(** Purge - special operation to delete a file immediately.  It is the caller's responsibility to ensure that no 
	other references exist to the file.  All disk clusters belonging to the file are marked as available in the FAT.
	The directory entry for the file is NOT deleted. *)

PROCEDURE Purge*(f: File; VAR res: LONGINT);
BEGIN
	PurgeFile(f, FALSE, res)
END Purge;

(** Length - Returns the current length of a file. *)

PROCEDURE Length*(f: File): LONGINT;
BEGIN
	RETURN f.handle.aleng*f.handle.bufSize + f.handle.bleng
END Length;

(** GetDate - Returns the time (t) and date (d) of a file. *)

PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);
BEGIN
	t := f.handle.time;  d := f.handle.date
END GetDate;

(** SetDate - Sets the time (t) and date (d) of a file. *)

PROCEDURE SetDate*(f: File; t, d: LONGINT);
BEGIN
	f.handle.time := t; f.handle.date := d;
	f.mod := TRUE
END SetDate;

(** Set - Positions a Rider at a certain position in a file. Multiple Riders can be positioned at different locations 
	in a file. A Rider cannot be positioned beyond the end of a file. *)

PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);
VAR bufSize: LONGINT;
BEGIN
	r.eof := FALSE;  r.res := 0;  r.file := f;
	IF f # NIL THEN
		bufSize := f.handle.bufSize;
		IF pos < 0 THEN r.apos := 0; r.bpos := 0;
		ELSIF pos < f.handle.aleng*bufSize + f.handle.bleng THEN
			r.apos := pos DIV bufSize; r.bpos := pos MOD bufSize
		ELSE r.apos := f.handle.aleng; r.bpos := f.handle.bleng
		END;
		r.buf := f.firstbuf
	ELSE
		r.buf := NIL
	END
END Set;

(** Pos - Returns the offset of a Rider positioned on a file. *)

PROCEDURE Pos*(VAR r: Rider): LONGINT;
BEGIN
	IF r.file # NIL THEN RETURN r.apos*r.file.handle.bufSize + r.bpos ELSE RETURN MAX(LONGINT) END
END Pos;

(** Base - Returns the File a Rider is based on. *)

PROCEDURE Base*(VAR r: Rider): File;
BEGIN
	RETURN r.file
END Base;

(** Read - Read a byte from a file, advancing the Rider one byte further.  R.eof indicates if the end of the 
	file has been reached. *)

PROCEDURE Read*(VAR r: Rider; VAR x: SYSTEM.BYTE; VAR res: LONGINT);
VAR buf: Buffer; old: Rider;
BEGIN
	res := 0;
	old := r;
	IF r.apos # r.buf.apos THEN r.buf := GetBuf(r.file, r.apos, res) END;
	IF res = 0 THEN
		IF r.bpos < r.buf.lim THEN	    (* lucky - buffer contains byte looked for *)
			x := r.buf.data[r.bpos];  INC(r.bpos)
		ELSIF r.apos < r.file.handle.aleng THEN (* last buffer in file? *)
			INC(r.apos); buf := Buf(r.file, r.apos);      (* try one of existing buffers *)
			IF buf = NIL THEN			       (* none of existing buffers contain byte *)
				IF r.buf.mod THEN WriteBuf(r.file, r.buf, res) END;
				IF res = 0 THEN
					ReadBuf(r.file, r.buf, r.apos, res)	(* refresh buffer *)
				END
			ELSE r.buf := buf
			END;
			x := r.buf.data[0]; r.bpos := 1
		ELSE
			x := 0X;  r.eof := TRUE
		END
	END;
	IF res # 0 THEN r := old END					(* restore rider to state at entry *)
END Read;

(** ReadBytes - Reads a sequence of length n bytes into the buffer x, advancing the Rider. Less bytes will 
	be read when reading over the length of the file. r.res indicates the number of unread bytes. *)

PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT;  VAR res: LONGINT);
VAR src, dst, m: LONGINT;  buf: Buffer; old: Rider;
BEGIN
	res := 0;
	old := r;
	dst := SYSTEM.ADR(x[0]);
	IF LEN(x) < n THEN res := eBufferTooSmallForRequest END;
	IF (res = 0) & (r.apos # r.buf.apos) THEN r.buf := GetBuf(r.file, r.apos, res) END;
	IF res = 0 THEN
		LOOP
			IF (n <= 0) OR (res # 0) THEN EXIT END;
			src := SYSTEM.ADR(r.buf.data[0]) + r.bpos;  m := r.bpos + n;
			IF m <= r.buf.lim THEN
				Copy(src, dst, n);  r.bpos := m;  r.res := 0;  EXIT
			ELSIF r.buf.lim = r.file.handle.bufSize THEN
				m := r.buf.lim - r.bpos;
				IF m > 0 THEN Copy(src, dst, m);  INC(dst, m);  DEC(n, m) END;
				IF r.apos < r.file.handle.aleng THEN
					INC(r.apos); r.bpos := 0; buf := Buf(r.file, r.apos);
					IF buf = NIL THEN
						IF r.buf.mod THEN WriteBuf(r.file, r.buf, res) END;
						IF res = 0 THEN ReadBuf(r.file, r.buf, r.apos, res) END
					ELSE
						r.buf := buf
					END
				ELSE
					r.res := n;  r.eof := TRUE;  EXIT
				END
			ELSE
				m := r.buf.lim - r.bpos;
				IF m > 0 THEN Copy(src, dst, m);  r.bpos := r.buf.lim END;
				r.res := n - m;  r.eof := TRUE;  EXIT
			END
		END (* LOOP *)
	END;
	IF res # 0 THEN r := old END					(* restore rider to state at entry *)
END ReadBytes;

(**
Portable routines to read the standard Oberon types.
*)

	PROCEDURE ReadInt*(VAR R: Rider; VAR x: INTEGER; VAR res: LONGINT);
		VAR x0, x1: SHORTINT;
	BEGIN Read(R, x0, res); IF res = 0 THEN Read(R, x1, res) END;
		x := LONG(x1) * 100H + LONG(x0) MOD 100H
	END ReadInt;

	PROCEDURE ReadLInt*(VAR R: Rider; VAR x: LONGINT; VAR res: LONGINT);
	BEGIN ReadBytes(R, x, 4, res)
	END ReadLInt;

	PROCEDURE ReadSet*(VAR R: Rider; VAR x: SET; VAR res: LONGINT);
	BEGIN ReadBytes(R, x, 4, res)
	END ReadSet;

	PROCEDURE ReadBool*(VAR R: Rider; VAR x: BOOLEAN; VAR res: LONGINT);
		VAR s: SHORTINT;
	BEGIN Read(R, s, res); x := s # 0
	END ReadBool;

	PROCEDURE ReadReal*(VAR R: Rider; VAR x: REAL; VAR res: LONGINT);
	BEGIN ReadBytes(R, x, 4, res)
	END ReadReal;

	PROCEDURE ReadLReal*(VAR R: Rider; VAR x: LONGREAL; VAR res: LONGINT);
	BEGIN ReadBytes(R, x, 8, res)
	END ReadLReal;

	PROCEDURE ReadString*(VAR R: Rider; VAR x: ARRAY OF CHAR; VAR res: LONGINT);
		VAR i: INTEGER; ch: CHAR;
	BEGIN i := 0;
		LOOP
			Read(R, ch, res); x[i] := ch; INC(i);
			IF (ch = 0X) OR (res # 0) THEN EXIT END;
			IF i = LEN(x) THEN x[i-1] := 0X;
				REPEAT Read(R, ch, res) UNTIL (res # 0) OR (ch = 0X);
				EXIT
			END
		END
	END ReadString;

(** Reads a number in compressed variable length notation using the minimum amount of bytes. *)

	PROCEDURE ReadNum*(VAR R: Rider; VAR x: LONGINT; VAR res: LONGINT);
		VAR ch: CHAR; n: INTEGER; y: LONGINT;
	BEGIN n := 0; y := 0; Read(R, ch, res);
		WHILE (res = 0) & (ch >= 80X) DO
			INC(y, SYSTEM.LSH(LONG(ch) - 128, n)); INC(n, 7); Read(R, ch, res)
		END;
		x := ASH(SYSTEM.LSH(LONG(ch), 25), n-25) + y
	END ReadNum;

(** Writes a byte into the file at the Rider position, advancing the Rider by one. *)

PROCEDURE Write*(VAR r: Rider; x: SYSTEM.BYTE; VAR res: LONGINT);
VAR f: File; buf: Buffer; oldR: Rider; oldH: Handle0;
BEGIN
	IF r.file.handle.readOnly THEN
		res := eFileIsReadOnly
	ELSE
		res := 0;
		oldR := r; oldH := r.file.handle;
		IF r.apos # r.buf.apos THEN r.buf := GetBuf(r.file, r.apos, res) END ;
		IF (res = 0) & (r.bpos >= r.buf.lim) THEN
			IF r.bpos < r.file.handle.bufSize THEN
				INC(r.buf.lim); INC(r.file.handle.bleng)
			ELSE
				f := r.file; WriteBuf(f, r.buf, res);
				IF res = 0 THEN
					INC(r.apos); buf := Buf(r.file, r.apos);
					IF buf = NIL THEN
						IF r.apos <= f.handle.aleng THEN ReadBuf(f, r.buf, r.apos, res)
						ELSE r.buf.apos := r.apos; r.buf.lim := 1;
							INC(f.handle.aleng); f.handle.bleng := 1
						END
					ELSE r.buf := buf
					END;
					r.bpos := 0
				END
			END
		END ;
		IF res = 0 THEN
			r.buf.data[r.bpos] := SYSTEM.VAL(CHAR, x); INC(r.bpos); r.buf.mod := TRUE
		ELSE
			r := oldR; r.file.handle := oldH (* restore entry states *)
		END
	END
END Write;

(** Writes the buffer x containing n bytes into a file at the Rider position. *)

PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT;  VAR res: LONGINT);
VAR src, dst, m: LONGINT; f: File; buf: Buffer; oldR: Rider; oldH: Handle0;
BEGIN
	IF r.file.handle.readOnly THEN
		res := eFileIsReadOnly
	ELSE
		res := 0;
		oldR := r; oldH := r.file.handle;
		src := SYSTEM.ADR(x[0]);
		IF LEN(x) < n THEN res := eBufferTooSmallForRequest END ;
		IF (res = 0) & (r.apos # r.buf.apos) THEN r.buf := GetBuf(r.file, r.apos, res) END;
		IF res = 0 THEN
			LOOP
				IF (n <= 0) OR (res # 0) THEN EXIT END ;
				r.buf.mod := TRUE; dst := SYSTEM.ADR(r.buf.data[0]) + r.bpos;
				m := r.bpos + n;
				IF m <= r.buf.lim THEN
					Copy(src, dst, n); r.bpos := m; EXIT
				ELSIF m <= r.file.handle.bufSize THEN
					Copy(src, dst, n); r.bpos := m;
					r.file.handle.bleng := m; r.buf.lim := m; EXIT
				ELSE m := r.file.handle.bufSize - r.bpos;
					IF m > 0 THEN Copy(src, dst, m); INC(src, m); DEC(n, m) END ;
					f := r.file; WriteBuf(f, r.buf, res);
					IF res = 0 THEN
						INC(r.apos); r.bpos := 0; buf := Buf(f, r.apos);
						IF buf = NIL THEN
							IF r.apos <= f.handle.aleng THEN ReadBuf(f, r.buf, r.apos, res)
							ELSE r.buf.apos := r.apos; r.buf.lim := 0; INC(f.handle.aleng); f.handle.bleng := 0
							END
						ELSE r.buf := buf
						END
					END
				END
			END (* LOOP *)
		END;
		IF res # 0 THEN r := oldR; r.file.handle := oldH END (* restore entry states *)
	END
END WriteBytes;

(*
Portable routines to write the standard Oberon types.
*)

	PROCEDURE WriteInt*(VAR R: Rider; x: INTEGER; VAR res: LONGINT);
	BEGIN Write(R, SHORT(x), res);
		IF res = 0 THEN Write(R, SHORT(x DIV 100H), res) END
	END WriteInt;

	PROCEDURE WriteLInt*(VAR R: Rider; x: LONGINT; VAR res: LONGINT);
	BEGIN WriteBytes(R, x, 4, res)
	END WriteLInt;

	PROCEDURE WriteSet*(VAR R: Rider; x: SET; VAR res: LONGINT);
	BEGIN WriteBytes(R, x, 4, res)
	END WriteSet;

	PROCEDURE WriteBool*(VAR R: Rider; x: BOOLEAN; VAR res: LONGINT);
	BEGIN
		IF x THEN Write(R, 1, res) ELSE Write(R, 0, res) END
	END WriteBool;

	PROCEDURE WriteReal*(VAR R: Rider; x: REAL; VAR res: LONGINT);
	BEGIN WriteBytes(R, x, 4, res)
	END WriteReal;

	PROCEDURE WriteLReal*(VAR R: Rider; x: LONGREAL; VAR res: LONGINT);
	BEGIN WriteBytes(R, x, 8, res)
	END WriteLReal;

	PROCEDURE WriteString*(VAR R: Rider; x: ARRAY OF CHAR; VAR res: LONGINT);
		VAR i: INTEGER; ch: CHAR;
	BEGIN i := 0;
		LOOP ch := x[i]; Write(R, ch, res); INC(i);
			IF (ch = 0X) OR (res # 0) THEN EXIT END;
			IF i = LEN(x) THEN Write(R, 0X, res); EXIT END
		END
	END WriteString;

(** Writes a number in a compressed format. *)

	PROCEDURE WriteNum*(VAR R: Rider; x: LONGINT; VAR res: LONGINT);
	BEGIN
		res := 0;
		WHILE (res = 0) & ((x < - 64) OR (x > 63)) DO
			Write(R, CHR(x MOD 128 + 128), res); x := x DIV 128
		END;
		IF res = 0 THEN Write(R, CHR(x MOD 128), res) END
	END WriteNum;

(** Delete - deletes a file. res = 0 indicates success. *)

PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: LONGINT);
VAR f, p, c: File;
BEGIN
	f := Old(name, res);
	IF res = 0 THEN
		IF f.handle.readOnly THEN
			res := eFileIsReadOnly
		ELSE
			IF KeepList THEN
				p := root; c := root.next;
				WHILE (c # NIL) & ~SameFile(c.handle, f.handle) DO
					p := c; c := c.next
				END;
				c.registered := FALSE;
				p.next := c.next (* remove from list *)
			END;
			PurgeFile(f, TRUE, res)
		END
	END
END Delete;

(** Rename - renames a file. res = 0 indicates success. *)

PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: LONGINT);
VAR oldbuf, newbuf: Filename;
BEGIN
	Check(old, oldbuf, res);
	IF res = 0 THEN
		Check(new, newbuf, res);
		IF res = 0 THEN
			Rename0(oldbuf, newbuf, res);
			IF res = eFileIsReadOnlyInServer THEN res := eFileIsReadOnly END;
		END
	END
END Rename;

(** Reset - Invalidate all removable disk cache entries immediately (diskette changed). *)

PROCEDURE Reset*;
VAR p, c: Drive;
BEGIN
	p := drives;  c := p.next;
	WHILE c # NIL DO
		IF (c.num >= 0) & (c.num < Numflop) THEN p.next := c.next
		ELSE p := c
		END;
		c := c.next
	END
END Reset;

BEGIN
	Initialize;
	defdir := "C:/";
	IF KeepList THEN NEW(root); root.next := NIL END
END FATFiles.

ToDo:
	o check for valid names, check for ?/*
	o VFAT
	o create directory
	
!Backup.WriteFiles FATFiles.Mod TestFATFiles.Mod Partition.Mod ~
