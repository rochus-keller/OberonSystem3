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

MODULE Partition;	(** non-portable *)	(* pjm *)

(* References: 
	MSKB Q69912 MS-DOS Partitioning Summary
	MSKB Q51978 Order in Which MS-DOS and Windows 95 Assigns Drive Letters 
	MSKB Q151414 Windows 95 Partition Types Not Recognized by Windows NT
	MSKB Q93373 Default Drive Letters and Partitions in Windows NT *)

IMPORT SYSTEM, Kernel, Disk, Texts, Fonts, Input, Oberon, In;

CONST
	MaxDrives* = 4;	(* only the first few drives detected *)
	MaxParts* = 32;	(* max number of partitions *)
	BS = 512;	(* disk block size *)
	FreeSpace = 256;
	MinPartSize = 64;	(* absolute minimum number of blocks in Oberon partition (cleared to 0 in Create) *)

	PartInfoURL = "ftp://ftp.inf.ethz.ch/pub/Oberon/System3/Contrib/Misc/";
	
TYPE
	Raw = ARRAY 16 OF CHAR;
	Partition* = RECORD	(** single partition *)
		type*: INTEGER;
		letter*: CHAR;
		drive*: SHORTINT;
		boot*: BOOLEAN;
		primary*: BOOLEAN;
		start*, size*: LONGINT;
		ptsector, ptoffset: LONGINT;
		raw: Raw
	END;
	DiskParam* = RECORD	(** disk parameters *)
		cyls*, hds*, spt*, size*: LONGINT
	END;
	Info* = RECORD	(** all partitions and disk parameters *)
		ok*: BOOLEAN;
		numhd*: SHORTINT;
		hd*: ARRAY MaxDrives OF DiskParam;
		numpar*: SHORTINT;
		par*: ARRAY MaxParts OF Partition
	END;
	DiskBlock = ARRAY BS OF CHAR;

VAR
	verbose*: BOOLEAN;	(** Show detail *)
	parttype*: INTEGER;	(** Oberon partition type for Create *)
	InitViewer*: PROCEDURE;	(** Initialise the partition text viewer *)

(* writers and texts *)
	W, Wn: Texts.Writer;
	T: Texts.Text;

(* Partition table starts at 01BEH in partition table sector and consists
	of 4 records of the type:
	
	00    bootind: Types.Byte;
	01    head: Types.Byte;
	02    sectorcyl: Types.Byte;
	03    cyl: Types.Byte;
	04    type: Types.Byte;
	05    head2: Types.Byte;
	06    sector2cyl: Types.Byte;
	07    cyl2: Types.Byte;
	08    start: Types.DWord;
	12    num: Types.DWord
*)

PROCEDURE WriteHexByte(VAR W: Texts.Writer;  b: CHAR);
	PROCEDURE HexChar(i: INTEGER): CHAR;
	BEGIN
		IF i > 9 THEN RETURN CHR(ORD("A") + i - 10)
		ELSE RETURN CHR(ORD("0") + i)
		END
	END HexChar;
BEGIN
	Texts.Write(W, HexChar(ORD(b) DIV 10H));
	Texts.Write(W, HexChar(ORD(b) MOD 10H))
END WriteHexByte;

(* WriteType - Write partition type *)

PROCEDURE WriteType(type: LONGINT);
VAR s: ARRAY 40 OF CHAR;
BEGIN
(*
	CASE type OF
		1: s := "DOS-FAT12"	(* DOS 12-bit FAT 0-15M *)
		|2: s := "Xenix"	(* Xenix root *)
		|3: s := "Xenix"	(* Xenix usr *)
		|4: s := "DOS-FAT16"	(* DOS 16-bit FAT 16-32M *)
		|5: s := "Extended"	(* DOS extended 0-2G *)
		|6: s := "DOS-FAT16"	(* DOS 16-bit FAT 32M-2G *)
		|7: s := "NTFS/HPFS"	(* OS/2 HPFS or QNX or Advanced UNIX or NT FS *)
		|8: s := "AIX"	(* AIX data *)
		|9: s := "AIX"	(* AIX boot or Coherent *)
		|10: s := "BootMan"	(* OS/2 Boot Manager *)
		|11: s := "W95-FAT32"	(* W95 OSR2 32-bit FAT 512M-2T *)
		|12: s := "W95-FAT32-LBA"	(* W95 OSR2 32-bit FAT 512M-2T *)
		|14: s := "W95-FAT16-LBA"	(* W95 16-bit FAT 32M-2G *)
		|15: s := "Extended-LBA"	(* W95 extended 0-2G *)
		|16: s := "OPUS"
		|17,20,22,23,132: s := "NTFS/HPFS"
		|18: s := "Compaq"
		|19: s := "Xenix"
		|24: s := "AST"
		|25: s := "SCO Unix"
		|33,35,38,49,51,52,54,113,115,116,118,134,161,163,164,166,177,179,180,182,229,230,243,246: s := "Reserved"
		|36: s := "NEC"
		|40,41,56,57: s := "THEOS"
		|60: s := "PQMagic"
		|64: s := "Venix"	(* Venix 80286 *)
		|65: s := "Linux"	(* Linux/MINIX (sharing disk with DRDOS) *)
		|66: s := "LinuxSwp"	(* Linux swap (sharing disk with DRDOS) *)
		|67: s := "Linux"	(* Linux native (sharing disk with DRDOS) *)
		|76: s := "Aos"
		|77: s := "Switcherland"
		|78: s := "Active"
		|79: s := "Oberon"	(* new *)
		|80: s := "Oberon-Alt"	(* DM,Lynx *)
		|81: s := "DM,Novell"
		|82: s := "CP/M,uPort"	(* CP/M or Microport SysV/AT *)
		|83: s := "DM"
		|84: s := "DM,NT"
		|85: s := "EZD"
		|86: s := "GB"
		|93,94: s := "QNX"
		|97,225,228,241,244: s := "SpeedStor"	(* DOS access or SpeedStor 12-bit FAT extended partition *)
		|98,114: s := "Pick"
		|99: s := "Hurd"	(* GNU HURD or Mach or Sys V/386 (such as ISC UNIX) *)
		|100..105: s := "Novell"	(* Novell Netware 286 or 386 *)
		|112: s := "DS"
		|117: s := "PC/IX"
		|128,129: s := "MINIX"	(* MINIX until 1.4a or MINIX since 1.4b, early Linux *)
		|130: s := "Linux-Swap"	(* Linux swap *)
		|131: s := "Linux-FS"	(* Linux native *)
		|135: s := "HPFS"
		|147,148: s := "Amoeba"	(* Amoeba *)
		|153: s := "Mylex"
		|165,181,183,184: s := "BSD"
		|192,205,208,221: s := "CTOS"
		|193,196,198: s := "DR-DOS"
		|199: s := "HPFS,Cyrnix"
		|203,216: s := "CP/M"
		|219: s := "CP/M,CDOS,CTOS"	(* Concurrent CP/M or Concurrent DOS or CTOS *)
		|223: s := "Datafusion"
		|226: s := "Hybrid,Gneiss"
		|227: s := "Oberon (old)"	(* old Native Oberon or DOS R/O or SpeedStor *)
		|242: s := "DOS3"	(* DOS 3.3+ secondary *)
		|254: s := "LANstep"
		|255: s := "Xenix"	(* bad track table *)
		|FreeSpace: s := "*free*"
		ELSE s := ""
	END;
*)
(* list from Linux fdisk, Microsoft Partitioning Summary (Q69912), Hal Landis' list & Jacques Eloff, http://home.global.co.za/~eloffjl/parcodes.html *)
	CASE type OF
		|001H: s := "DOS FAT12"
		|002H: s := "Xenix (root)"
		|003H: s := "Xenix (usr)"
		|004H: s := "DOS FAT16 < 32M"
		|005H: s := "Extended"
		|006H: s := "DOS FAT16 >= 32M"
		|007H: s := "NTFS, HPFS, QNX, Adv. Unix"
		|008H: s := "AIX boot, SplitDrive, QNX qny"
		|009H: s := "AIX data, Coherent swap, QNX qnz"
		|00AH: s := "OS/2 BM, Coherent swap"
		|00BH: s := "Win 95/98, FAT32"
		|00CH: s := "Win 95/98, FAT32 LBA"
		
		|00EH: s := "DOS FAT16 LBA"
		|00FH: s := "Extended LBA"
		|010H: s := "Opus"
		|011H: s := "OS/2 BM: Hidden FAT12"
		|012H: s := "Xenix (SCO), Compaq diag."
		|013H: s := "Xenix (SCO)"
		|014H: s := "OS/2 BM: Hidden FAT16 < 32M"
		
		|016H: s := "OS/2 BM: Hidden FAT16 >= 32M"
		|017H: s := "OS/2 BM: Hidden IFS"
		|018H: s := "AST Windows"
		|019H: s := "Interactive Unix (SCO)"

		|024H: s := "NEC DOS"
		|028H..029H: s := "THEOS"
		
		|038H..039H: s := "THEOS"
		
		|03CH: s := "PQMagic recovery"
		
		|040H: s := "Venix 80286"
		|041H: s := "Linux/Minix (DR-DOS)"
		|042H: s := "SFS, Linux swap (DR-DOS)"
		|043H: s := "Linux fs (DR-DOS)"
		
		|04CH: s := "Aos"
		|04DH: s := "Switcherland or QNX Posix"
		|04EH: s := "Active or QNX Posix"
		|04FH: s := "Native Oberon or QNX Posix"
		|050H: s := "Native Oberon (alt) or Lynx RTOS / DM"
		|051H: s := "Novell Netware, Ontrack Ext, DM6 Aux 1"
		|052H: s := "Microport SysV/AT, CP/M"
		|053H: s := "DM6 Aux 3"
		|054H: s := "NTFS/DM6"
		|055H: s := "EZ-Drive (DM)"
		|056H: s := "Golden Bow (DM)"

		|05CH: s := "Priam EDisk (DM)"
		|05DH..05EH: s := "QNX"
		
		|061H: s := "SpeedStor"
		|062H: s := "Pick"
		|063H: s := "GNU HURD, Mach, Sys V/386 (ISC UNIX)"
		|064H: s := "Novell Netware 286"
		|065H: s := "Novell Netware 386"
		|066H..69H: s := "Novell Netware"
		|070H: s := "Disk Secure Multi-Boot"
		
		|072H: s := "Pick"
		|073H: s := "Unix (SCO)"
		|074H: s := "Novell Netware"
		|075H: s := "PC/IX"
		
		|077H..079H: s := "QNX 4.x"
		|080H: s := "Minix <= 1.4a"
		|081H: s := "Minix > 1.4b, old Linux, Mitax DM"
		|082H: s := "Linux swap"
		|083H: s := "Linux fs"
		|084H: s := "OS/2 Hidden C: drive"
		|085H: s := "Linux ext"
		|086H..087H: s := "NTFS volume"
		
		|093H..094H: s := "Amoeba"

		|0A0H: s := "IBM Thinkpad hibernation"
		
		|0A5H: s := "BSD i386"
		
		|0A7H: s := "NeXTSTEP 486"
		
		|0B5H: s := "FreeBSD"

		|0B7H: s := "BSDI fs"
		|0B8H: s := "BSDI swap"
		
		|0C0H: s := "CTOS"
		|0C1H: s := "DRDOS/sec FAT12"

		|0C4H: s := "DRDOS/sec FAT16 < 32M"
		|0C6H: s := "DRDOS/sec FAT16 >= 32M"
		|0C7H: s := "Syrinx"
		
		|0CBH: s := "CP/M (DR)"

		|0CDH: s := "CTOS (Mem)"
		
		|0D0H: s := "CTOS"
		
		|0DBH: s := "CP/M, Concurrent CP/M, DOS, CTOS"
		
		|0DDH: s := "CTOS (Mem)"
		
		|0DFH: s := "Datafusion"

		|0E1H: s := "DOS access, SpeedStor FAT12 ext"
		|0E2H: s := "Gneiss"
		|0E3H: s := "DOS R/O, SpeedStor, Oberon (old)"
		|0E4H: s := "SpeedStor FAT16 ext"
		
		|0F1H: s := "SpeedStor"
		|0F2H: s := "DOS 3.3 secondary"
		
		|0F4H: s := "SpeedStor large"
		
		|0FEH: s := "SpeedStor > 1024 cyl, LANstep"
		|0FFH: s := "Xenix BBT"
		|FreeSpace: s := "Free space"
		ELSE s := ""
	END;

	IF s # "" THEN
		Texts.WriteString(W, s)
	ELSE
		IF type < 0 THEN Texts.WriteString(W, "*ERROR*")
		ELSIF type # FreeSpace THEN Texts.WriteString(W, "type ");  Texts.WriteInt(W, type, 1)
		END
	END
END WriteType;

(* Consistent - Check if logical and physical numbers are consistent *)

PROCEDURE Consistent(spt, hds, start, len: LONGINT;  VAR raw: Raw): BOOLEAN;
VAR sec, hd, cyl: LONGINT;  ok0: BOOLEAN;
BEGIN
	sec := start MOD spt + 1;  hd := (start DIV spt) MOD hds;
	cyl := start DIV (spt*hds);  ok0 := TRUE;
	IF (hd # ORD(raw[1])) OR (sec # ORD(raw[2]) MOD 64) OR
		(cyl # ASH(ASH(ORD(raw[2]), -6), 8) + ORD(raw[3])) THEN
		ok0 := FALSE
	END;
	sec := (start+len-1) MOD spt + 1;  hd := ((start+len-1) DIV spt) MOD hds;
	cyl := (start+len-1) DIV (spt*hds);
	IF (hd # ORD(raw[5])) OR (sec # ORD(raw[6]) MOD 64) OR
		(cyl # ASH(ASH(ORD(raw[6]), -6), 8) + ORD(raw[7])) THEN
		ok0 := FALSE
	END;
	RETURN ok0
END Consistent;

(* PlaceHolder - Return TRUE iff partition is a placeholder (ends on absolute max) *)

PROCEDURE PlaceHolder(VAR raw: Raw;  VAR d: DiskParam): BOOLEAN;
BEGIN
	RETURN (ASH(ASH(ORD(raw[6]), -6), 8) + ORD(raw[7]) = 1023) &
		(ORD(raw[5]) = d.hds-1) & (ORD(raw[6]) MOD 64 = d.spt)
END PlaceHolder;

(* FindFreeSpace - Find free space on disk *)

PROCEDURE FindFreeSpace(d: SHORTINT;  VAR hd: ARRAY OF DiskParam;  VAR p: ARRAY OF Partition;  VAR n: SHORTINT);
VAR i: SHORTINT;  t, g, start0, start1, end: LONGINT;
BEGIN
	start0 := hd[d].spt;  g := hd[d].hds*hd[d].spt;
	LOOP
		t := MAX(LONGINT);
		FOR i := 0 TO n-1 DO	(* find first partition start after or on start0 *)
			IF p[i].primary & (p[i].drive = d) & (p[i].start >= start0) & (p[i].start < t) THEN
				t := p[i].start
			END
		END;
		IF t = MAX(LONGINT) THEN	(* end of disk minus one cylinder *)
			t := hd[d].size;  DEC(t, hd[d].hds*hd[d].spt)
		END;
			(* {start0..t-1 is free} *)
		IF start0 = hd[d].spt THEN start1 := start0	(* first partition starts first cylinder, second head *)
		ELSE start1 := start0+((-start0) MOD g)	(* other partitions must start on cylinder boundary *)
		END;
			(* {start1..t-1 is free} *)
		t := t - (t MOD g);	(* partition must end on cylinder boundary *)
		IF t-start1 > 0 THEN
			p[n].type := FreeSpace;  p[n].letter := 0X;  p[n].drive := d;  p[n].boot := FALSE;
			p[n].primary := TRUE;  p[n].start := start1;  p[n].size := t-start1;
			p[n].ptsector := 0;  p[n].ptoffset := 0;	(* always sector 0 for primary, but find free ptoffset later *)
			FOR i := 0 TO 15 DO p[n].raw[i] := 0X END;
			INC(n)
		END;
		t := MAX(LONGINT);
		FOR i := 0 TO n-1 DO	(* find first partition end after start0 *)
			IF p[i].primary & (p[i].drive = d) THEN
				end := p[i].start+p[i].size-1;
				IF (end > start0) & (end < t) THEN
					t := end
				END
			END
		END;
		IF t = MAX(LONGINT) THEN
			EXIT	(* no more partitions end after start0 *)
		ELSE
			start0 := t+1
		END
	END
END FindFreeSpace;

(* Lettered - Partition with DOS drive letter? *)

PROCEDURE Lettered(type: LONGINT): BOOLEAN;
BEGIN
	RETURN (type >= 0) & (type < 32) & (type IN {1,4,6,11,12,14})
END Lettered;

(* Extended - Check if a partition is an extended partition *)

PROCEDURE Extended(type: LONGINT): BOOLEAN;
BEGIN
	RETURN (type = 5) OR (type = 15)
END Extended;

PROCEDURE WriteBadSignature(VAR w: Texts.Writer;  d, b: LONGINT;  s1, s2: CHAR);
BEGIN
	Texts.WriteString(w, "Disk ");  Texts.WriteInt(w, d, 1);
	Texts.WriteString(w, ": signature bad (");
	WriteHexByte(w, s1);  Texts.Write(w, ",");  WriteHexByte(w, s2);
	Texts.WriteString(w, " instead of 55,AA) on block ");
	Texts.WriteInt(w, b, 1);  Texts.WriteLn(w)
END WriteBadSignature;

(* ReadPrimary - Read primary partition table entries into p *)

PROCEDURE ReadPrimary(numhd: SHORTINT;  VAR hd: ARRAY OF DiskParam;  VAR p: ARRAY OF Partition;
	VAR n, letter: SHORTINT);
VAR b: DiskBlock;  e, size: LONGINT;  d, i: SHORTINT;  first: BOOLEAN;
BEGIN
	n := 0;
	FOR d := 0 TO numhd-1 DO
		first := TRUE;
		Disk.GetBlocks(d, 0, 1, b, 0);
		IF (b[510] = 055X) & (b[511] = 0AAX) THEN	(* signature ok *)
			FOR i := 0 TO 3 DO
				e := 01BEH + 16*i;  SYSTEM.GET(SYSTEM.ADR(b[e+12]), size);
				IF (b[e+4] # 0X) & (size # 0) THEN
					p[n].type := ORD(b[e+4]);  p[n].letter := 0X;  p[n].drive := d;
					SYSTEM.GET(SYSTEM.ADR(b[e+8]), p[n].start);  p[n].size := size;
					p[n].boot := (b[e] # 0X);  p[n].ptsector := 0;  p[n].ptoffset := e;
					p[n].primary := TRUE;  SYSTEM.MOVE(SYSTEM.ADR(b[e]), SYSTEM.ADR(p[n].raw[0]), 16);
					IF first & Lettered(p[n].type) THEN
						p[n].letter := CHR(letter);  INC(letter);
						first := FALSE
					ELSE
						p[n].letter := 0X
					END;
					INC(n)
				END
			END;
			FindFreeSpace(d, hd, p, n)
		ELSE
			WriteBadSignature(Wn, d, 0, b[510], b[511]);
			Texts.Append(Oberon.Log, Wn.buf)
		END
	END
END ReadPrimary;

(* ReadLogical - Read "logical drive" partitions into p *)

PROCEDURE ReadLogical(d: SHORTINT;  first: LONGINT;  VAR p: ARRAY OF Partition;  VAR n, letter: SHORTINT);
VAR b: DiskBlock;  e, sec, size: LONGINT;  i: SHORTINT;  found: BOOLEAN;
BEGIN
	sec := first;
	REPEAT
		found := FALSE;
		Disk.GetBlocks(d, sec, 1, b, 0);
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
					p[n].size := size;
					p[n].boot := (b[e] # 0X);  p[n].primary := FALSE;
					p[n].ptsector := sec;  p[n].ptoffset := e;
					SYSTEM.MOVE(SYSTEM.ADR(b[e]), SYSTEM.ADR(p[n].raw[0]), 16);
					INC(n)
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
			WriteBadSignature(Wn, d, sec, b[510], b[511]);
			Texts.Append(Oberon.Log, Wn.buf)
		END
	UNTIL ~found
END ReadLogical;

(* GetHDParams - Get hard disk parameters. *)

PROCEDURE GetHDParams(drive: SHORTINT; VAR cyls, hds, spt: LONGINT);
VAR buf: DiskBlock;  p, hd, sec, phd, psec, dsize: LONGINT;  ok: BOOLEAN;  i: SHORTINT;
BEGIN
	Disk.GetParams(drive, cyls, hds, spt);	(* get parameters from driver *)
	dsize := cyls*hds*spt;
	IF dsize # 0 THEN
		Disk.GetBlocks(drive, 0, 1, buf, 0);	(* read sector 0 *)
		ok := TRUE;
		IF (buf[510] = 055X) & (buf[511] = 0AAX) THEN	(* valid partition table *)
			phd := -1;	(* find end head and sector for each valid primary partition *)
			FOR i := 0 TO 3 DO
				p := 01BEH + 16*i;
				IF buf[p+4] # 0X THEN	(* partition i in use *)
					hd := ORD(buf[p+5]); 	(* end head *)
					sec := ORD(buf[p+6]) MOD 64;	(* end sector *)
					IF phd = -1 THEN phd := hd;  psec := sec
					ELSIF (phd = hd) & (psec = sec) THEN (* skip *)
					ELSE ok := FALSE	(* inconsistent table *)
					END
				END
			END;
			IF ok & (phd # -1) THEN	(* modify the parameters to be consistent with the table *)
				cyls := dsize DIV ((phd+1)*psec);
				hds := phd+1;  spt := psec
			ELSIF (cyls > 1024) OR (hds > 255) OR (sec > 63) THEN
				(* modify the parameters to be inside BIOS limits (for boot loader) *)
				(* BIOS limits: 1024 cylinders (0-1023), 255 heads (0-254), 63 sectors (1-63) (max size 8032M) *)
				hds := 8;  spt := 63;
				REPEAT	(* try 16, 32, 64, 128 and 255 heads *)
					hds := hds*2;
					cyls := dsize DIV (hds*spt)
				UNTIL (cyls <= 1023) OR (hds = 256);
				IF hds = 256 THEN hds := 255;  cyls := dsize DIV (hds*spt) END
			ELSE (* skip *)
			END
		ELSE (* skip *)
		END
	END
END GetHDParams;

PROCEDURE CheckDisk(): BOOLEAN;
BEGIN
	IF Disk.GetBlocks = NIL THEN
		Texts.WriteString(W, "Disk driver not configured!");
		Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf);
		RETURN FALSE
	ELSE
		RETURN TRUE
	END
END CheckDisk;

(** GetInfo - Get partition table information. *)

PROCEDURE GetInfo*(VAR di: Info);
VAR pt: ARRAY MaxParts OF Partition;  pn, letter, i: SHORTINT;
BEGIN
	i := 0;
	LOOP
		GetHDParams(i, di.hd[i].cyls, di.hd[i].hds, di.hd[i].spt);
		di.hd[i].size := di.hd[i].cyls*di.hd[i].hds*di.hd[i].spt;
		IF di.hd[i].size = 0 THEN EXIT END;
		INC(i);
		IF i = MaxDrives THEN EXIT END
	END;
	di.numhd := i;  di.numpar := 0;  di.ok := TRUE;
	letter := SHORT(ORD("C"));
	ReadPrimary(di.numhd, di.hd, pt, pn, letter);
	FOR i := 0 TO pn-1 DO
		di.par[di.numpar] := pt[i];  INC(di.numpar);
		IF Extended(pt[i].type) THEN
			ReadLogical(pt[i].drive, pt[i].start, di.par, di.numpar, letter)
		END
	END;
		(* now assign letters to remaining primary partitions (see Q51978) *)
	FOR i := 0 TO di.numpar-1 DO
		IF (di.par[i].letter = 0X) & Lettered(di.par[i].type) THEN
			di.par[i].letter := CHR(letter);  INC(letter)
		END
	END
END GetInfo;

PROCEDURE CheckConsistency(VAR W: Texts.Writer;  VAR di: Info);
VAR d, i, j: SHORTINT;  ok: BOOLEAN;  size, endi, endj: LONGINT;
BEGIN
	ok := TRUE;
	FOR i := 0 TO di.numpar-1 DO
		IF (di.par[i].ptsector = 0) & (di.par[i].type # FreeSpace) THEN	(* primary partition *)
			d := di.par[i].drive;  size := di.hd[d].size;
			IF PlaceHolder(di.par[i].raw, di.hd[d]) THEN
				IF verbose THEN
					Texts.WriteLn(W);
					Texts.WriteString(W, "Note: Partition ");  Texts.WriteInt(W, i, 1);
					Texts.WriteString(W, " is a large disk placeholder.")
				END
			ELSIF ~Consistent(di.hd[d].spt, di.hd[d].hds, di.par[i].start, di.par[i].size, di.par[i].raw) THEN
				Texts.WriteLn(W);
				Texts.WriteString(W, "Error: Partition ");  Texts.WriteInt(W, i, 1);
				Texts.WriteString(W, " has logical/physical inconsistency.");
				ok := FALSE
			ELSE (* skip *)
			END;
			IF (di.par[i].start < 0) OR (di.par[i].start >= size) OR (di.par[i].size < 0) OR (di.par[i].start+di.par[i].size > size) THEN
				Texts.WriteLn(W);
				Texts.WriteString(W, "Error: Partition ");  Texts.WriteInt(W, i, 1);
				Texts.WriteString(W, " bigger than disk.");
				ok := FALSE	(* partition i bigger than disk *)
			END;
			FOR j := 0 TO di.numpar-1 DO
				IF (i # j) & (d = di.par[j].drive) & (di.par[j].ptsector = 0) & (di.par[j].type # FreeSpace) THEN
					endi := di.par[i].start+di.par[i].size-1;  endj := di.par[j].start+di.par[j].size-1;
					IF ((di.par[i].start >= di.par[j].start) & (di.par[i].start <= endj)) OR ((endi >= di.par[j].start) & (endi <= endj)) THEN
						Texts.WriteLn(W);
						Texts.WriteString(W, "Error: Partitions ");  Texts.WriteInt(W, i, 1);
						Texts.WriteString(W, " and ");  Texts.WriteInt(W, j, 1);  Texts.WriteString(W, " overlap.");
						ok := FALSE	(* partition i & j overlap *)
					END
				END
			END
		END
	END;
	IF ~ok THEN
		Texts.WriteLn(W);  Texts.WriteLn(W);
		Texts.WriteString(W, "The existing partition table is inconsistent.  Please reboot and run the");  Texts.WriteLn(W);
		Texts.WriteString(W, "partinfo.exe program to check it, before continuing.  The program is at:");  Texts.WriteLn(W);
		Texts.WriteString(W, PartInfoURL);  Texts.WriteLn(W)
	END
END CheckConsistency;

(** Display - Display the partition tables.  Calls InitViewer to initialise the display. *)

PROCEDURE Display*(VAR di: Info);
VAR i: SHORTINT;  t, count: LONGINT;  detail: BOOLEAN;
BEGIN
	InitViewer;  detail := verbose OR ~di.ok;  count := 0;
	IF di.numhd = 0 THEN
		Texts.WriteString(Wn, "No drives found (driver problem?)");  Texts.WriteLn(Wn)
	ELSE
		FOR i := 0 TO di.numhd-1 DO
			Texts.WriteString(Wn, "Disk ");  Texts.WriteInt(Wn, i, 1);  Texts.WriteString(Wn, ": ");
			t := di.hd[i].size DIV 2+102;	(* k *)
			IF t < 100*1024 THEN
				Texts.WriteInt(Wn, t DIV 1024, 1);
				Texts.Write(Wn, ".");
				Texts.WriteInt(Wn, (t MOD 1024)*10 DIV 1024, 1)
			ELSE Texts.WriteInt(Wn, t DIV 1024, 1)
			END;
			Texts.WriteString(Wn, " Mb");
			IF detail THEN
				Texts.WriteString(Wn, ", ");
				Texts.WriteInt(Wn, di.hd[i].cyls, 1);  Texts.WriteString(Wn, " cylinders, ");  Texts.WriteInt(Wn, di.hd[i].hds, 1);
				Texts.WriteString(Wn, " heads, ");  Texts.WriteInt(Wn, di.hd[i].spt, 1);
				Texts.WriteString(Wn, " sectors per track.")
			END;
			Texts.WriteLn(Wn)
		END;
		Texts.Append(T, Wn.buf);  Texts.WriteLn(W);
		IF detail THEN Texts.WriteString(W, "Num Disk  Mb    Start   Length Typ Description")
		ELSE Texts.WriteString(W, "Num Disk  Mb Typ Description")
		END;
		Texts.WriteLn(W);
		FOR i := 0 TO di.numpar-1 DO
			IF di.par[i].type = parttype THEN INC(count) END;
			Texts.WriteInt(W, i, 2);
			IF di.par[i].boot THEN Texts.Write(W, "*")
			ELSE Texts.Write(W, " ")
			END;
			Texts.WriteInt(W, di.par[i].drive, 3);
			t := di.par[i].size DIV 2+102;	(* k *)
			IF t < 100*1024 THEN
				Texts.WriteInt(W, t DIV 1024, 4);
				Texts.Write(W, ".");
				Texts.WriteInt(W, (t MOD 1024)*10 DIV 1024, 1)
			ELSE Texts.WriteInt(W, t DIV 1024, 6)
			END;
			IF detail THEN
				Texts.WriteInt(W, di.par[i].start, 9);  Texts.WriteInt(W, di.par[i].size, 9)
			END;
			IF di.par[i].type # FreeSpace THEN
				(*Texts.Write(W, " ");  WriteHexByte(W, CHR(di.par[i].type));  Texts.Write(W, "H")*)
				Texts.WriteInt(W, di.par[i].type, 4)
			ELSE
				Texts.WriteString(W, " ---")
			END;
			Texts.Write(W, " ");
			IF ~di.par[i].primary THEN Texts.Write(W, "|") END;
			IF di.par[i].letter # 0X THEN Texts.Write(W, di.par[i].letter);  Texts.Write(W, ":") END;
			WriteType(di.par[i].type);
			(*IF di.par[i].boot THEN Texts.WriteString(W, " boot") END;*)
			Texts.WriteLn(W)
		END;
		Texts.WriteString(W, "  * = bootable");  Texts.WriteLn(W);
		Texts.Append(T, W.buf);
		IF detail THEN
			Texts.WriteLn(W);
			Texts.WriteString(W, "Num hd sec cyl  hd sec cyl  ptsector ofs");  Texts.WriteLn(W);
			FOR i := 0 TO di.numpar-1 DO
				Texts.WriteInt(W, i, 2);
				Texts.WriteInt(W, ORD(di.par[i].raw[1]), 4);
				Texts.WriteInt(W, ORD(di.par[i].raw[2]) MOD 64, 3);
				Texts.WriteInt(W, ASH(ASH(ORD(di.par[i].raw[2]), -6), 8) + ORD(di.par[i].raw[3]), 5);
				Texts.WriteInt(W, ORD(di.par[i].raw[5]), 4);
				Texts.WriteInt(W, ORD(di.par[i].raw[6]) MOD 64, 3);
				Texts.WriteInt(W, ASH(ASH(ORD(di.par[i].raw[6]), -6), 8) + ORD(di.par[i].raw[7]), 5);
				Texts.WriteInt(W, di.par[i].ptsector, 10);  Texts.WriteInt(W, di.par[i].ptoffset, 4);
				(*FOR j := 0 TO 15 DO Texts.Write(W, " ");  WriteHexByte(W, di.par[i].raw[j]) END;*)
				Texts.WriteLn(W)
			END;
			Texts.Append(T, W.buf);
			IF ~di.ok THEN
				Texts.WriteLn(Wn);  Texts.WriteString(Wn, "Error in partition table.");  Texts.Append(T, Wn.buf)
			END
		END;
		IF count > 1 THEN
			Texts.WriteLn(Wn);  Texts.WriteString(Wn, "Warning: More than one Oberon partition.  First one will be used.");
			Texts.WriteLn(Wn);  Texts.Append(T, Wn.buf)
		END;
		CheckConsistency(Wn, di)
	END;
	Texts.Append(T, Wn.buf)
END Display;

(** Partition.Show - Display all partition tables. *)

PROCEDURE Show*;
VAR di: Info;
BEGIN
	IF ~CheckDisk() THEN RETURN END;
	GetInfo(di);
	Display(di)
END Show;

(* SetFlag - Set bootable flag of a primary or extended partition. *)

PROCEDURE SetFlag(VAR di: Info;  i: SHORTINT;  on: BOOLEAN);
VAR b: DiskBlock;  e: LONGINT;  mod: BOOLEAN;
BEGIN
	Disk.GetBlocks(di.par[i].drive, di.par[i].ptsector, 1, b, 0);
	e := di.par[i].ptoffset;
	ASSERT((e >= 01BEH) & (e <= 01BEH+16*3));
	mod := FALSE;
	IF on & (b[e] = 0X) THEN b[e] := 80X; mod := TRUE
	ELSIF ~on & ((b[e] >= 80X) & (b[e] <= 81X)) THEN b[e] := 0X; mod := TRUE
	END;
	IF mod THEN Disk.PutBlocks(di.par[i].drive, di.par[i].ptsector, 1, b, 0) END
END SetFlag;

(** SetActive - Set the active partition(s).  Afterwards, di is updated with GetInfo. *)

PROCEDURE SetActive*(VAR di: Info;  active: SET);
VAR i, n: SHORTINT;
BEGIN
	IF di.ok THEN
		n := di.numpar;  IF n > 32 THEN n := 32 END;
		FOR i := 0 TO n-1 DO
			IF di.par[i].type # FreeSpace THEN
				SetFlag(di, i, i IN active)
			END
		END;
		GetInfo(di)
	END
END SetActive;

(** Partition.Activate {num} ~ - Active the partition(s). *)

PROCEDURE Activate*;	(* {num} ~ *)
VAR num: INTEGER;  di: Info;  active: SET;
BEGIN
	IF ~CheckDisk() THEN RETURN END;
	active := {};  In.Open;  In.Int(num);
	WHILE In.Done DO
		IF (num >= 0) & (num < 32) THEN INCL(active, num) END;
		In.Int(num)
	END;
	IF active # {} THEN
		GetInfo(di);  SetActive(di, active);  Display(di)
	END
END Activate;

(* Random - Pseudo-random number. *)

PROCEDURE Random (VAR seed: LONGINT;  N :LONGINT): LONGINT;
BEGIN
	seed := (seed + 773) * 13 MOD 9999991;
	RETURN seed MOD N
END Random;

(** Partition.Check num - Check partition's sectors for readability. *)

PROCEDURE Check*;	(* num *)
CONST Size = 16;
VAR
	di: Info;  num: INTEGER;  start, size, i, pc, pr, seed, len, ticks, t0, t1, date: LONGINT;  ch: CHAR;
	buf: ARRAY Size OF DiskBlock;
BEGIN
	IF ~CheckDisk() THEN RETURN END;
	GetInfo(di);
	In.Open;  In.Int(num);
	IF ~In.Done THEN
		i := 0;  num := -1;
		WHILE (i < di.numpar) & (num = -1) DO
			IF di.par[i].type = parttype THEN num := SHORT(i)
			ELSE INC(i)
			END
		END
	END;
	IF num >= 0 THEN
		IF di.ok & (num < di.numpar) THEN
			Texts.WriteString(Wn, "Checking partition ");
			Texts.WriteInt(Wn, num, 1);  Texts.WriteString(Wn, "...");  Texts.WriteLn(Wn);
			Texts.Append(Oberon.Log, Wn.buf);
			start := di.par[num].start;  size := di.par[num].size;  seed := 8872365;
			FOR pc := 0 TO 99 DO
				i := Random(seed, size);
				Disk.GetBlocks(di.par[num].drive, start + i, 1, buf, 0)
			END;
			Texts.WriteString(Wn, "%: 0");  Texts.Append(Oberon.Log, Wn.buf);
			i := 0;  pr := 10;  ticks := Kernel.GetTimer();
			Kernel.GetClock(t0, date);
			WHILE (i < size) & (Input.Available() = 0) DO
				pc := i*100 DIV size;
				WHILE pc > pr DO
					Texts.WriteInt(Wn, pr, 3);  Texts.Append(Oberon.Log, Wn.buf);
					INC(pr, 10)
				END;
				len := Size;
				IF len > size-i THEN len := size-i END;
				Disk.GetBlocks(di.par[num].drive, start + i, len, buf, 0);
				INC(i, len)
			END;
			ticks := Kernel.GetTimer() - ticks;
			Kernel.GetClock(t1, date);	(* ignore midnight *)
			WHILE Input.Available() # 0 DO Input.Read(ch) END;
			IF i = size THEN
				Texts.WriteString(Wn, " 100");
				Texts.WriteLn(Wn);  Texts.WriteString(Wn, "No problems detected.")	(* no trap *)
			ELSE
				Texts.WriteString(Wn, " interrupted")
			END;
			IF (ticks # 0) & (i # 0) THEN
				Texts.WriteLn(Wn);  Texts.WriteInt(Wn, i DIV 2, 1);
				Texts.WriteString(Wn, "k read in ");
				Texts.WriteInt(Wn, ticks DIV Kernel.TimeUnit, 1);
				Texts.WriteString(Wn, "s (");
				t0 := (t0 DIV 4096 MOD 32*60 + t0 DIV 64 MOD 64)*60 + t0 MOD 64;	(* s *)
				t1 := (t1 DIV 4096 MOD 32*60 + t1 DIV 64 MOD 64)*60 + t1 MOD 64;	(* s *)
				Texts.WriteInt(Wn, t1 - t0, 1);
				Texts.WriteString(Wn, "s) => ");
				Texts.WriteInt(Wn, (i DIV 2)*Kernel.TimeUnit DIV ticks, 1);
				Texts.WriteString(Wn, "k/s")
			END;
			Texts.WriteLn(Wn);  Texts.Append(Oberon.Log, Wn.buf)
		END
	END
END Check;

(** Partition.ChangeType num from to - Change partition type. *)

PROCEDURE ChangeType*;	(* partition fromtype totype *)
VAR num, from, to: INTEGER;  di: Info;  b: DiskBlock;  e: LONGINT;
BEGIN
	IF ~CheckDisk() THEN RETURN END;
	In.Open;  In.Int(num);  In.Int(from);  In.Int(to);
	IF In.Done & (num >= 0) & (to >= 0) & (to <= 255) THEN
		GetInfo(di);
		IF di.ok & (num < di.numpar) & (di.par[num].type = from) THEN
			Disk.GetBlocks(di.par[num].drive, di.par[num].ptsector, 1, b, 0);
			e := di.par[num].ptoffset;
			ASSERT((e >= 01BEH) & (e <= 01BEH+16*3));
			ASSERT((ORD(b[e+4]) = from) & (b[510] = 055X) & (b[511] = 0AAX));
			b[e+4] := CHR(to);
			Disk.PutBlocks(di.par[num].drive, di.par[num].ptsector, 1, b, 0);
			GetInfo(di)
		ELSE
			Texts.WriteString(Wn, "Bad partition specified");  Texts.WriteLn(Wn);
			Texts.Append(Oberon.Log, Wn.buf)
		END;
		Display(di)
	END
END ChangeType;

(** Partition.Delete num type - Delete primary partition. *)

PROCEDURE Delete*;	(* partition type *)
VAR num, type: INTEGER;  di: Info;  b: DiskBlock;  e, i: LONGINT;
BEGIN
	IF ~CheckDisk() THEN RETURN END;
	In.Open;  In.Int(num);  In.Int(type);
	IF In.Done & (num >= 0) THEN
		GetInfo(di);
		IF di.ok & (num < di.numpar) & (di.par[num].type = type) & di.par[num].primary THEN
			Disk.GetBlocks(di.par[num].drive, di.par[num].ptsector, 1, b, 0);
			e := di.par[num].ptoffset;
			ASSERT((e >= 01BEH) & (e <= 01BEH+16*3));
			ASSERT((ORD(b[e+4]) = type) & (b[510] = 055X) & (b[511] = 0AAX));
			FOR i := 0 TO 15 DO b[e+i] := 0X END;
			Disk.PutBlocks(di.par[num].drive, di.par[num].ptsector, 1, b, 0);
			GetInfo(di)
		ELSE
			Texts.WriteString(Wn, "Bad partition specified");  Texts.WriteLn(Wn);
			Texts.Append(Oberon.Log, Wn.buf)
		END;
		Display(di)
	END
END Delete;

(** Partition.Create num sizeMb - Create primary Oberon partition. *)

PROCEDURE Create*;	(* partition size *)
VAR num: INTEGER;  di: Info;  b: DiskBlock;  e, i, t, r, start, size, end, spt, hds: LONGINT;  ok: BOOLEAN;  drive: SHORTINT;
BEGIN
	IF ~CheckDisk() THEN RETURN END;
	In.Open;  In.Int(num);  In.LongInt(size);
	IF In.Done & (num >= 0) & (size > 0) THEN
		GetInfo(di);
		IF di.ok & (num < di.numpar) & (di.par[num].type = FreeSpace) & di.par[num].primary THEN
			Disk.GetBlocks(di.par[num].drive, di.par[num].ptsector, 1, b, 0);
			ASSERT((b[510] = 055X) & (b[511] = 0AAX));
			ok := FALSE;  i := 0;
			WHILE (i # 4) & ~ok DO
				e := 01BEH + 16*i;
				SYSTEM.GET(SYSTEM.ADR(b[e+12]), t);
				IF t = 0 THEN ok := TRUE
				ELSE INC(i)
				END
			END;
			IF ok THEN
				drive := di.par[num].drive;  start := di.par[num].start;  spt := di.hd[drive].spt;  hds := di.hd[drive].hds;
				size := size*1024*2;	(* number of sectors *)
				IF size > di.par[num].size THEN
					size := di.par[num].size;	(* use max *)
					Texts.WriteString(Wn, "Adjusting size to maximum available");  Texts.WriteLn(Wn);
					Texts.Append(Oberon.Log, Wn.buf)
				END;
				r := (start+size) MOD (hds*spt);
				IF r # 0 THEN	(* round end down to multiple of cylinder *)
					DEC(size, r);
					Texts.WriteString(Wn, "Adjusting size to cylinder boundary");  Texts.WriteLn(Wn);
					Texts.Append(Oberon.Log, Wn.buf)
				END;
				IF (size >= MinPartSize) & (di.par[num].size >= size) THEN
						(* create the partition *)
					end := start+size-1;
					b[e] := 0X;  b[e+1] := CHR((start DIV spt) MOD hds);
					t := start DIV (spt*hds);
					IF t > 1023 THEN t := 1023 END;
					b[e+2] := CHR(ASH(ASH(t, -8), 6) + (start MOD spt) + 1);
					b[e+3] := CHR(t);  b[e+4] := CHR(parttype);
					b[e+5] := CHR((end DIV spt) MOD hds);
					t := end DIV (spt*hds);
					IF t > 1023 THEN t := 1023 END;
					b[e+6] := CHR(ASH(ASH(t, -8), 6) + (end MOD spt) + 1);
					b[e+7] := CHR(t);  SYSTEM.PUT(SYSTEM.ADR(b[e+8]), start);
					SYSTEM.PUT(SYSTEM.ADR(b[e+12]), size);
					Disk.PutBlocks(drive, di.par[num].ptsector, 1, b, 0);	(* update partition sector *)
						(* now clear first part of partition *)
					b[0] := 0EBX;  b[1] := 0FEX;	(* LOOP END *)
					FOR i := 2 TO BS-1 DO b[i] := 0X END;
					Disk.PutBlocks(drive, di.par[num].start, 1, b, 0);	(* overwrite boot sector *)
					b[0] := 0X;  b[1] := 0X;
					FOR i := 1 TO MinPartSize-1 DO
						Disk.PutBlocks(drive, di.par[num].start + i, 1, b, 0)	(* clear first MinPartSize-1 sectors *)
					END
				ELSE
					Texts.WriteString(Wn, "Specified partition size bad");  Texts.WriteLn(Wn);
					Texts.Append(Oberon.Log, Wn.buf)
				END
			ELSE
				Texts.WriteString(Wn, "Primary partition table full");  Texts.WriteLn(Wn);
				Texts.Append(Oberon.Log, Wn.buf)
			END;
			GetInfo(di)
		ELSE
			Texts.WriteString(Wn, "Specified partition not free");  Texts.WriteLn(Wn);
			Texts.Append(Oberon.Log, Wn.buf)
		END;
		Display(di)
	END
END Create;

(** Partition.Verbose on|off - Set state of verbose flag. *)

PROCEDURE Verbose*;
VAR s: ARRAY 10 OF CHAR;
BEGIN
	In.Open;  In.String(s);
	IF ~In.Done THEN
	ELSIF s = "on" THEN
		verbose := TRUE;
		Texts.WriteString(Wn, "Verbose on");  Texts.WriteLn(Wn);  Texts.Append(Oberon.Log, Wn.buf)
	ELSIF s = "off" THEN
		verbose := FALSE;
		Texts.WriteString(Wn, "Verbose off");  Texts.WriteLn(Wn);  Texts.Append(Oberon.Log, Wn.buf)
	END
END Verbose;

(** InitText - Initialise the output text. *)

PROCEDURE InitText*(t: Texts.Text);
BEGIN
	T := t
END InitText;

(* DefaultInitViewer - Initialise the Install viewer V and text T *)

PROCEDURE DefaultInitViewer;
BEGIN
	NEW(T);  Texts.Open(T, "");
	Oberon.OpenText("Partition.Text", T, 384, 200)
END DefaultInitViewer;

PROCEDURE Init;
VAR s: ARRAY 20 OF CHAR;  i: SHORTINT;
BEGIN
	Kernel.GetConfig("PartType", s);
	i := 0;  parttype := 0;
	WHILE (s[i] >= "0") & (s[i] <= "9") DO
		parttype := parttype*10 + (ORD(s[i])-48);
		INC(i)
	END;
	IF parttype = 0 THEN parttype := 79 END
END Init;

BEGIN
	verbose := FALSE;
	Texts.OpenWriter(W);  Texts.SetFont(W, Fonts.This("Courier10.Scn.Fnt"));
	Texts.OpenWriter(Wn);
(*
	Texts.WriteString(Wn, "Partition 07.12.1998");  Texts.WriteLn(Wn);
	Texts.Append(Oberon.Log, Wn.buf);
*)
	InitViewer := DefaultInitViewer;
	Init
END Partition.

Partition.Show
Partition.Activate 0 ~
Partition.Check 0 ~
Partition.ChangeType num from to
Partition.Delete 7 79
Partition.Verbose on
Partition.Verbose ^ on off
Partition.Create 7 100

System.Free DOS FATFiles Partition ~
