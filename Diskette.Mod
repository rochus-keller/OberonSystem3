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

MODULE Diskette;	(** non-portable *) (*JG 11.8.94/pjm 4.7.95 *)

  IMPORT SYSTEM, Diskette0, Files, Input, Oberon, Modules;

(* driver functionality factored out to Diskette0 for re-use in Oberon-0 *)

  (*HALT(52) = hardware error in GetSector
     HALT(53) = hardware error in PutSector (diskette write protected?)
     HALT(54) = format error*)

  CONST
    maxBlocks = 2880; maxBlockSize = 1024; maxSecSize = 512;
    maxFATSize = 9*maxSecSize;
    entrySize = 32; maxEntries = maxSecSize DIV entrySize;

   (*BIOS Parameterblock (2DD, 2HD)
      11  bytes/sector (512, 512)
      13  sectors/block (2, 1)
      14  reserved sectors (1, 1) 
      16  FATs (2, 2)
      17  directory entries (112, 224)
      19  sectors (1440, 2880)
      21  media descriptor (F9H, F0H)
      22  sectors/FAT (3, 9)
      24  sectors/track (9, 18)
      26  heads (2, 2)

     sector allocation
       boot sector (0, 0)
       primary FAT (1, 1)
       secondary FAT (4, 10)
       directory (7, 19)
       file data (14, 33)*)

  TYPE
    FileDesc = RECORD (*image of dir entry*)
      name: ARRAY 22 OF CHAR;
      time, date, start: INTEGER;
      size: LONGINT
    END;

    File = POINTER TO FileHandle;
    FileHandle = RECORD
      prev, next: File;
      attributes: CHAR;
      start: INTEGER;
      time, date, size: LONGINT;
      name: ARRAY 32 OF CHAR
    END;

    Volume = POINTER TO VolDesc;
    VolDesc = RECORD
      code, mediaDesc: CHAR;
      secSize, secPerTrack, nofSecs, nofHeads: INTEGER;
      resSecs, nofFATs, FATStart, secPerFAT: INTEGER;
      dirStart, nofEntries, entriesPerSec, secPerDir: INTEGER;
      dataStart, secPerBlock, blockSize, nofBlocks: INTEGER;
      freeEntries, freeBlocks: INTEGER;
      dir: File; modified: BOOLEAN;
      name: ARRAY 32 OF CHAR;
      FAT: ARRAY maxBlocks OF INTEGER
    END;

    EntryHandler* = PROCEDURE (name: ARRAY OF CHAR; date, time, size: LONGINT);

VAR
	res*: INTEGER;
	drive*: SHORTINT;
	vol: Volume;
	
	offtask: Oberon.Task;

(* MotorOff - Switch off motor *)

PROCEDURE MotorOff(me: Oberon.Task);
BEGIN
	Diskette0.StopMotor(drive);
	Oberon.Remove(offtask);  offtask := NIL
END MotorOff;

(* SetupMotorTask - Arrange to stop the motor in time *)

PROCEDURE SetupMotorTask;
BEGIN
	IF offtask = NIL THEN
		NEW(offtask);  offtask.safe := FALSE;  offtask.handle := MotorOff;  Oberon.Install(offtask)
	END;
	offtask.time := Input.Time() + 3*Input.TimeUnit;	(* switch off after 3s *)
END SetupMotorTask;

PROCEDURE GetSectors*(start, num: INTEGER;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
BEGIN
	SetupMotorTask;
	Diskette0.GetSectors(drive, start, num, buf, ofs)
END GetSectors;

PROCEDURE PutSectors*(start, num: INTEGER;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
BEGIN
	SetupMotorTask;
	Diskette0.PutSectors(drive, start, num, buf, ofs)
END PutSectors;

(* -- driver end -- *)

  PROCEDURE Open* (secPerTrack, nofHeads: INTEGER);
  BEGIN vol.secPerTrack := secPerTrack; vol.nofHeads := nofHeads
  END Open;

  (*Volume management*)

  PROCEDURE GetVolDesc;
    VAR buf: ARRAY maxSecSize OF CHAR;
  BEGIN
    GetSectors(0, 1, buf, 0);
    IF buf[21] < 0F0X THEN HALT(54) END;
    NEW(vol);
    IF ORD(buf[11]) + ORD(buf[12])*256 # 512 THEN
      (*invalid parameter block*)
      vol.secSize := 512; vol.secPerBlock := 2; vol.resSecs := 1; vol.nofFATs := 2;
      vol.nofEntries := 112; vol.nofSecs := 1440; vol.mediaDesc := 0F9X;
      vol.secPerFAT := 3; vol.secPerTrack := 9; vol.nofHeads := 2
    ELSE
      vol.secSize := ORD(buf[11]) + ORD(buf[12])*256;
      vol.secPerBlock := ORD(buf[13]);
      vol.resSecs := ORD(buf[14]) + ORD(buf[15])*256;
      vol.nofFATs := ORD(buf[16]);
      vol.nofEntries := ORD(buf[17]) + ORD(buf[18])*256;
      vol.nofSecs := ORD(buf[19]) + ORD(buf[20])*256;
      vol.mediaDesc := buf[21];
      vol.secPerFAT := ORD(buf[22]) + ORD(buf[23])*256;
      vol.secPerTrack := ORD(buf[24]) + ORD(buf[25])*256;
      vol.nofHeads := ORD(buf[26]) + ORD(buf[27])*256
    END;
    vol.FATStart := vol.resSecs;
    vol.dirStart := vol.FATStart + vol.nofFATs*vol.secPerFAT;
    vol.entriesPerSec := vol.secSize DIV entrySize;
    vol.secPerDir := (vol.nofEntries + vol.entriesPerSec - 1) DIV vol.entriesPerSec;
    vol.dataStart := vol.dirStart + vol.secPerDir - 2*vol.secPerBlock;
    vol.nofBlocks := (vol.nofSecs - vol.dataStart) DIV vol.secPerBlock;
    vol.blockSize := vol.secPerBlock * vol.secSize;
    IF vol.secSize # 512 THEN HALT(54) END
  END GetVolDesc;

  PROCEDURE Blocks (size: LONGINT): INTEGER;
  BEGIN RETURN SHORT((size + vol.blockSize - 1) DIV vol.blockSize)
  END Blocks;

  PROCEDURE Locate (name: ARRAY OF CHAR; VAR f: File);
    VAR s: ARRAY 32 OF CHAR;
  BEGIN f := vol.dir.prev; 
    WHILE f.name > name DO f := f.prev END
  END Locate;

  PROCEDURE ReadFAT;
    VAR n: LONGINT; i, j, n0, n1, off: INTEGER;
      buf: ARRAY maxFATSize OF CHAR;
  BEGIN 
    GetSectors(vol.FATStart, vol.secPerFAT, buf, 0);
    vol.FAT[0] := 4095; vol.FAT[1] := 4095;
    i := 2; j := 3;
    REPEAT
      n :=     ORD(buf[j+2]); n := n*256;
      n := n + ORD(buf[j+1]); n := n*256;
      n := n + ORD(buf[j]);
      n0 := SHORT(n MOD 4096); n1 := SHORT(n DIV 4096);
      vol.FAT[i] := n0; vol.FAT[i+1] := n1;
      i := i + 2; j := j + 3
    UNTIL i >= vol.nofBlocks
  END ReadFAT;

  PROCEDURE WriteFAT;
    VAR n: LONGINT; i, j, n0, n1, off: INTEGER;
      buf: ARRAY maxFATSize OF CHAR;
  BEGIN
    buf[0] := vol.mediaDesc; buf[1] := 0FFX; buf[2] := 0FFX;
    i := 2; j := 3;
    REPEAT
      n0 := vol.FAT[i]; n1 := vol.FAT[i+1];
      n := n1; n := n*4096 + n0;
      buf[j] := CHR(SHORT(n MOD 256)); n := n DIV 256;
      buf[j+1] := CHR(SHORT(n MOD 256)); n := n DIV 256;
      buf[j+2] := CHR(SHORT(n));
      i := i + 2; j := j + 3
    UNTIL i >= vol.nofBlocks;
    i := vol.FATStart;  j := vol.nofFATs;
    WHILE j # 0 DO
    	PutSectors(i, vol.secPerFAT, buf, 0);
    	INC(i, vol.secPerFAT);  DEC(j)
    END
  END WriteFAT;

  (*Oberon format support*)

  PROCEDURE InEntry (VAR f: FileDesc; VAR g: File);
  BEGIN COPY(f.name, g.name);
    g.time := LONG(f.time)*2; g.date := LONG(f.date) + 80*512;
    g.start := f.start; g.size := f.size
  END InEntry;

  PROCEDURE OutEntry (VAR f: File; VAR g: FileDesc);
  BEGIN COPY(f.name, g.name);
    g.time := SHORT(f.time DIV 2); g.date := SHORT(f.date - 80*512);
    g.start := f.start; g.size := f.size
  END OutEntry;

  PROCEDURE ReadOberonDir (VAR buf: ARRAY OF FileDesc);
    VAR f, g: File; s, i: INTEGER;
  BEGIN (*buf[0] ready*)
    s := vol.dirStart; i := 0;
    NEW(vol.dir); InEntry(buf[0], vol.dir);
    COPY(vol.dir.name, vol.name); vol.dir.name[0] := 0X;
    vol.dir.next := vol.dir; vol.dir.prev := vol.dir;
    LOOP
      DEC(vol.freeEntries); INC(i);
      IF i = vol.entriesPerSec THEN INC(s);
        IF s = vol.dirStart + vol.secPerDir THEN EXIT END;
        GetSectors(s, 1, buf, 0); i := 0
      END;
      IF buf[i].name[0] = 0X THEN EXIT END;
      NEW(g); InEntry (buf[i], g);
      Locate(g.name, f);
      g.next := f.next; f.next := g; g.next.prev := g; g.prev := f;
      vol.freeBlocks := vol.freeBlocks - Blocks(g.size)
    END
  END ReadOberonDir;

  PROCEDURE WriteOberonDir;
    VAR f: File; s, i: INTEGER;
      buf: ARRAY maxEntries OF FileDesc;
  BEGIN s := vol.dirStart;
    COPY(vol.name, vol.dir.name);
    OutEntry(vol.dir, buf[0]); buf[0].name[21] := "o";
    i := 1; f := vol.dir.next;
    WHILE f # vol.dir DO
      IF i = vol.entriesPerSec THEN PutSectors(s, 1, buf, 0); INC(s); i := 0 END;
      OutEntry(f, buf[i]); INC(i); f := f.next
    END;
    WHILE s # vol.dirStart + vol.secPerDir DO
      IF i = vol.entriesPerSec THEN PutSectors(s, 1, buf, 0); INC(s); i := 0 END;
      buf[i].name[0] := 0X; INC(i)
    END
  END WriteOberonDir;

  PROCEDURE InitOberonVol* (name: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN GetVolDesc;
    COPY(name, vol.name); vol.code := "o"; 
    NEW(vol.dir); vol.dir.name[0] := 0X;
    Oberon.GetClock(vol.dir.time, vol.dir.date); vol.dir.size := 0;
    vol.dir.next := vol.dir; vol.dir.prev := vol.dir;
    vol.FAT[0] := 4095; vol.FAT[1] := 4095; i := 2;
    REPEAT vol.FAT[i] := 0; vol.FAT[i+1] := 0; i := i+2 UNTIL i >= vol.nofBlocks;
    WriteFAT; WriteOberonDir;
    vol := NIL
  END InitOberonVol;

  (*DOS format support*)

  PROCEDURE InDOSEntry (VAR f: FileDesc; VAR g: File);
    VAR i, j: INTEGER; ch: CHAR;
  BEGIN i := 0;
    WHILE (i # 8) & (f.name[i] # " ") DO ch := f.name[i];
      IF ("A" <= ch) & (ch <= "Z") OR ("0" <= ch) & (ch <= "9") THEN g.name[i] := ch
      ELSIF ("a" <= ch) & (ch <= "z") THEN g.name[i] := CAP(ch)
      ELSE g.name[i] := "X"
      END;
      INC(i)
    END;
    j := i; i := 8;
    IF f.name[i] # " " THEN g.name[j] := "."; INC(j);
      REPEAT g.name[j] := f.name[i]; INC(i); INC(j) UNTIL (i = 11) OR (f.name[i] = " ")
    END;
    g.name[j] := 0X;
    g.attributes := f.name[11];
    g.time := LONG(f.time)*2; g.date := LONG(f.date) + 80*512;
    g.start := f.start; g.size := f.size
  END InDOSEntry;

  PROCEDURE OutDOSEntry (VAR f: File; VAR g: FileDesc);
    VAR i, j: INTEGER;
  BEGIN i := 0;
    WHILE (f.name[i] # ".") & (f.name[i] # 0X) DO g.name[i] := f.name[i]; INC(i) END;
    j := i;
    WHILE j # 8 DO g.name[j] := " "; INC(j) END;
    IF f.name[i] = "." THEN INC(i);
      WHILE f.name[i] # 0X DO g.name[j] := f.name[i]; INC(i); INC(j) END
    END;
    WHILE j # 11 DO g.name[j] := " "; INC(j) END;
    g.name[11] := f.attributes;
    g.time := SHORT(f.time DIV 2); g.date := SHORT(f.date - 80*512);
    g.start := f.start; g.size := f.size
  END OutDOSEntry;

  PROCEDURE ReadDOSDir (VAR buf: ARRAY OF FileDesc);
    VAR f, g: File; s, i: INTEGER;
  BEGIN (*buf[0] ready*)
    NEW(vol.dir); vol.dir.name[0] := 0X;
    vol.dir.next := vol.dir; vol.dir.prev := vol.dir;
    s := vol.dirStart; i := 0;
    LOOP
      IF buf[i].name[0] = 0X THEN EXIT END;
      IF buf[i].name[0] # 0E5X THEN
        IF ORD(buf[i].name[11]) MOD 16 DIV 8 = 1 THEN (*volume label*)
          InDOSEntry(buf[i], vol.dir);
          COPY(vol.dir.name, vol.name); vol.dir.name[0] := 0X
        ELSE NEW(g); InDOSEntry(buf[i], g);
          Locate(g.name, f);
          g.next := f.next; f.next := g; g.next.prev := g; g.prev := f;
          vol.freeBlocks := vol.freeBlocks - Blocks(g.size)
        END;
        DEC(vol.freeEntries)
      END;
      INC(i);
      IF i = vol.entriesPerSec THEN INC(s);
        IF s = vol.dirStart + vol.secPerDir THEN EXIT END;
        GetSectors(s, 1, buf, 0); i := 0
      END
    END
  END ReadDOSDir;

  PROCEDURE WriteDOSDir;
    VAR f: File; s, i: INTEGER;
      buf: ARRAY maxEntries OF FileDesc;
  BEGIN
    s := vol.dirStart; i := 0;
    IF ORD(vol.dir.attributes) MOD 16 DIV 8 = 1 THEN (*volume*)
      COPY(vol.name, vol.dir.name); OutDOSEntry(vol.dir, buf[0]); INC(i)
    END;
    f := vol.dir.next;
    WHILE f # vol.dir DO
      IF i = vol.entriesPerSec THEN PutSectors(s, 1, buf, 0); INC(s); i := 0 END;
      OutDOSEntry(f, buf[i]); INC(i); f := f.next
    END;
    WHILE s # vol.dirStart + vol.secPerDir DO
      IF i = vol.entriesPerSec THEN PutSectors(s, 1, buf, 0); INC(s); i := 0 END;
      buf[i].name[0] := 0X; INC(i)
    END
  END WriteDOSDir;

  PROCEDURE InitDOSVol* (name: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN GetVolDesc;
    COPY(name, vol.name); vol.code := 0X;
    NEW(vol.dir); vol.dir.name[0] := 0X; vol.dir.attributes := 28X; (*archive & volume*)
    Oberon.GetClock(vol.dir.time, vol.dir.date); vol.dir.size := 0;
    vol.dir.next := vol.dir; vol.dir.prev := vol.dir;
    vol.FAT[0] := 4095; vol.FAT[1] := 4095; i := 2;
    REPEAT vol.FAT[i] := 0; vol.FAT[i+1] := 0; i := i+2 UNTIL i >= vol.nofBlocks;
    WriteFAT; WriteDOSDir;
    vol := NIL
  END InitDOSVol;

  PROCEDURE OpenVol* (VAR freeEntries, freeSpace: INTEGER);
    VAR f, g: File; buf: ARRAY maxEntries OF FileDesc;
  BEGIN GetVolDesc;
    vol.freeEntries := vol.nofEntries;
    vol.freeBlocks := vol.nofBlocks - 2;
    GetSectors(vol.dirStart, 1, buf, 0);
    IF buf[0].name[0] = 0FFX THEN
      buf[0].name[1] := 0X; buf[0].name[21] := "o"
    END;
    vol.code := buf[0].name[21];
    IF vol.code = "o" THEN ReadOberonDir(buf)
      ELSE ReadDOSDir(buf)
    END;
    ReadFAT;
    vol.modified := FALSE;
    freeEntries := vol.freeEntries;
    freeSpace := SHORT(vol.freeBlocks*LONG(vol.blockSize) DIV 1024)
  END OpenVol;

  PROCEDURE CloseVol*;
  BEGIN
    IF vol.modified THEN WriteFAT;
      IF vol.code = "o" THEN WriteOberonDir ELSE WriteDOSDir END
    END;
    vol := NIL
  END CloseVol;

  (*File management*)

  PROCEDURE NormName (VAR name, nname: ARRAY OF CHAR);
    VAR i, j, j1: INTEGER; ch: CHAR;
  BEGIN
    IF vol.code = "o" THEN i := 0;
      WHILE i # 20 DO nname[i] := name[i]; INC(i) END;
      nname[i] := 0X
    ELSE (*make DOS name*) i := 0;
      WHILE (i # 8) & (name[i] # ".") & (name[i] # 0X) DO ch := name[i];
        IF ("a" <= ch) & (ch <= "z") THEN ch := CAP(ch) END;
        nname[i] := ch; INC(i)
      END;
      j := i;
      WHILE (name[i] # ".") & (name[i] # 0X) DO INC(i) END;
      IF name[i] = "." THEN
        nname[j] := "."; INC(i); INC(j); j1 := j + 3;
        WHILE (j # j1) & (name[i] # 0X) DO ch := name[i];
          IF ("a" <= ch) & (ch <= "z") THEN ch := CAP(ch) END;
          nname[j] := ch; INC(i); INC(j)
        END
      END;
      nname[j] := 0X
    END
  END NormName;

	PROCEDURE readFile(f: File; g: Files.File);
	CONST
		Size = 30*maxBlockSize DIV 512;
	VAR
		Wg: Files.Rider;  size: LONGINT;  i, inbuf, start: INTEGER;
		buf: ARRAY Size*512 OF CHAR;
	BEGIN
		Files.Set(Wg, g, 0);  size := f.size;
		IF size # 0 THEN
			i := f.start;
			LOOP
				inbuf := vol.secPerBlock;  start := i;
				WHILE (vol.FAT[i] < 0FF8H) & (vol.FAT[i] = i+vol.secPerBlock) & (inbuf+vol.secPerBlock <= Size) DO
					i := vol.FAT[i];  INC(inbuf, vol.secPerBlock)
				END;
				GetSectors(vol.dataStart + vol.secPerBlock*start, inbuf, buf, 0);
				IF vol.FAT[i] >= 0FF8H THEN EXIT END;
				Files.WriteBytes(Wg, buf, inbuf*512);
				DEC(size, LONG(inbuf)*512);
				i := vol.FAT[i]
			END;
			Files.WriteBytes(Wg, buf, size)
		END
	END readFile;
	
  PROCEDURE deleteFile (f: File);
    VAR i, j: INTEGER;
  BEGIN
    f.prev.next := f.next; f.next.prev := f.prev;
    i := f.start;
    REPEAT j := vol.FAT[i]; vol.FAT[i] := 0; i := j UNTIL i >= 0FF8H
  END deleteFile;

  PROCEDURE addFile (f: Files.File; g, h: File);
    VAR Rf: Files.Rider; remSize: LONGINT; off, i, j, k: INTEGER;
      buf: ARRAY maxBlockSize OF CHAR;
  BEGIN
    IF h.size # 0 THEN remSize := h.size;
      Files.Set(Rf, f, 0); j := 2;
      WHILE vol.FAT[j] # 0 DO INC(j) END;
      h.start := j;
      LOOP i := j;
        Files.ReadBytes(Rf, buf, vol.blockSize);
        PutSectors(vol.dataStart + vol.secPerBlock*i, vol.secPerBlock, buf, 0);
        remSize := remSize - vol.blockSize;
        IF remSize <= 0 THEN EXIT END;
        INC(j);
        WHILE vol.FAT[j] # 0 DO INC(j) END;
        vol.FAT[i] := j
      END;
      vol.FAT[i] := 4095
    END;
    h.next := g.next; g.next := h; h.next.prev := h; h.prev := g
  END addFile;

  PROCEDURE ReadFile* (name, oname: ARRAY OF CHAR);
    VAR f: File; g: Files.File; nname: ARRAY 32 OF CHAR;
  BEGIN
    NormName(name, nname); Locate(nname, f);
    IF f.name = nname THEN
      g := Files.New(oname); readFile(f, g); Files.Register(g); res := 0
    ELSE res := 1
    END
  END ReadFile;

  PROCEDURE WriteFile* (oname, name: ARRAY OF CHAR);
    VAR f: Files.File; g, h: File; size: LONGINT; need: INTEGER;
      nname: ARRAY 32 OF CHAR;
  BEGIN
    res := 0; f := Files.Old(oname);
    IF f # NIL THEN size := Files.Length(f);
      NormName(name, nname); Locate(nname, g);
      IF g.name = nname THEN
        need := Blocks(size) - Blocks(g.size);
        IF vol.freeBlocks - need >= 0 THEN
          deleteFile(g);
          Oberon.GetClock(g.time, g.date); g.size := size;
          addFile(f, g.prev, g);
          vol.freeBlocks := vol.freeBlocks - need;
          vol.modified := TRUE
        ELSE res := 2
        END
      ELSE need := Blocks(size);
        IF (vol.freeEntries > 0) & (vol.freeBlocks - need >= 0) THEN
          NEW(h); COPY(nname, h.name);
          Oberon.GetClock(h.time, h.date); h.size := size;
          addFile(f, g, h);
          DEC(vol.freeEntries);
          vol.freeBlocks := vol.freeBlocks - need;
          vol.modified := TRUE
        ELSE res := 2
        END
      END
    ELSE res := 1
    END
  END WriteFile;

  PROCEDURE DeleteFile* (name: ARRAY OF CHAR);
    VAR g: File; nname: ARRAY 32 OF CHAR;
  BEGIN
    NormName(name, nname); Locate(nname, g);
    IF g.name = nname THEN deleteFile(g);
      INC(vol.freeEntries);
      vol.freeBlocks := vol.freeBlocks + Blocks(g.size);
      vol.modified := TRUE;
      res := 0
    ELSE res := 1
    END
  END DeleteFile;

  PROCEDURE Enumerate* (proc: EntryHandler);
    VAR f: File;
  BEGIN
    proc(vol.name, vol.dir.date, vol.dir.time, 0);
    f := vol.dir.next;
    WHILE f # vol.dir DO
      proc(f.name, f.date, f.time, f.size); f := f.next
    END
  END Enumerate;

PROCEDURE *Cleanup;
BEGIN
	IF offtask # NIL THEN MotorOff(offtask) END
END Cleanup;

BEGIN drive := 0;  offtask := NIL;  Modules.InstallTermHandler(Cleanup)
END Diskette.

System.Free Backup Diskette ~
