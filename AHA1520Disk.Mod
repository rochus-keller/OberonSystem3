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

MODULE AHA1520Disk;	(** non-portable *)	(* Contributed by W. Ibl to the System 3 project *)

(* Adaptec AHA1520 disk driver for Native Oberon *)

IMPORT SYSTEM, SCSI := AHA1520, Disk;

VAR
	requ: SCSI.Command;	(* SCSI command buffer *)
	drives: SHORTINT;	(* amount of drives found on inquiry *)
	tgt: ARRAY SCSI.Targets OF SHORTINT;	(* available disks *)

PROCEDURE -CoreHalt(n: LONGINT);
CODE {SYSTEM.i386}
	INT 3
END CoreHalt;

(* ---- Disk driver ---- *)

PROCEDURE RequestSense(tgt: INTEGER; VAR key,code: INTEGER);
(* request error information for last failed request *)
VAR
	cmd: ARRAY 6 OF CHAR;
	data: ARRAY 14 OF CHAR;
BEGIN
	cmd[0]:= 03X; cmd[1]:= 00X; cmd[2]:= 00X;
	cmd[3]:= 00X; cmd[4]:= 0EX; cmd[5]:= 00X;

	requ.target:= SHORT(tgt); requ.lun:= 00H; requ.clen:= 6;
	requ.cmd:= SYSTEM.ADR(cmd); requ.data:= SYSTEM.ADR(data);
	SCSI.Initiate(requ); WHILE ~requ.done DO END;
		
	IF (requ.status # SCSI.Good) THEN CoreHalt(17); END;
	key:= ORD(data[2]);	(* Sense Key *)
	code:= SYSTEM.LSH(ORD(data[12]),8)+ORD(data[13]);	(* Sense Code *)
END RequestSense;

PROCEDURE Inquiry(tgt: INTEGER): BOOLEAN;
(* inquire device information *)
VAR
	cmd: ARRAY 6 OF CHAR;
	data: ARRAY 1 OF CHAR;
BEGIN
	cmd[0]:= 12X; cmd[1]:= 00X; cmd[2]:= 00X;
	cmd[3]:= 00X; cmd[4]:= 01X; cmd[5]:= 00X;

	requ.target:= SHORT(tgt); requ.lun:= 00H; requ.clen:= 6;
	requ.cmd:= SYSTEM.ADR(cmd); requ.data:= SYSTEM.ADR(data);
	SCSI.Initiate(requ); WHILE ~requ.done DO END;
	IF (requ.status = SCSI.Good) THEN
		RETURN(data[0] = 00X);
	ELSIF (requ.status = SCSI.DriverError) THEN
		IF (SCSI.status = SCSI.drvNoConnect) THEN RETURN(FALSE); END;
	END;
	CoreHalt(17);
END Inquiry;

PROCEDURE TestUnitReady(tgt: INTEGER): BOOLEAN;
(* check, if device is rarrin' to go *)
VAR
	cmd: ARRAY 6 OF CHAR;
BEGIN
	cmd[0]:= 00X; cmd[1]:= 00X; cmd[2]:= 00X;
	cmd[3]:= 00X; cmd[4]:= 00X; cmd[5]:= 00X;

	requ.target:= SHORT(tgt); requ.lun:= 00H; requ.clen:= 6;
	requ.cmd:= SYSTEM.ADR(cmd); requ.data:= 0;
	SCSI.Initiate(requ); WHILE ~requ.done DO END;
	RETURN(requ.status = SCSI.Good);	(* no data transmission *)
END TestUnitReady;

PROCEDURE DiskError();
(* produce a nice trap in case of error occurrence *)
VAR
	target,lun,scsi,driver,key,code: INTEGER;
BEGIN
	key:= 0; code:= 0;
	target:= requ.target; lun:= requ.lun; scsi:= requ.status; driver:= SCSI.status;
	IF (driver = SCSI.Good) & (scsi = SCSI.cmdCheckCondition) THEN
		RequestSense(requ.target,key,code);
	END;
	CoreHalt(17);
END DiskError;

PROCEDURE Interrogate(dev: SET);
(* loop over all targets to get the disks connected,
	non accessible drives (not ready) are skipped without reclaims *)
VAR
	rider: SHORTINT;
	ready: BOOLEAN;
	key,code: INTEGER;
BEGIN
	drives:= 0;
	FOR rider:= 0 TO SCSI.Targets-1 DO
		IF (rider IN dev) & Inquiry(rider) THEN
			ready:= TestUnitReady(rider);
			IF ~ready THEN
				RequestSense(rider,key,code);
				(* UNIT ATTENTION & POWER ON are not really a fault *) 
				IF (key = 06H) & (code = 2900H) THEN
					ready:= TestUnitReady(rider);	(* so try again *)
				END;
			END;
			IF ready THEN tgt[drives]:= rider; INC(drives); END;
		END;
	END;
	FOR rider:= drives TO SCSI.Targets-1 DO tgt[rider]:= -1; END;
END Interrogate;

(** GetBlocks - Read 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0 or 1)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to read into
	"ofs" - offset from start of buf in bytes *)

PROCEDURE GetBlocks*(drive, start,num: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE; ofs: LONGINT);
VAR
	cmd: ARRAY 10 OF CHAR;
BEGIN
	cmd[0]:= 28X;
	cmd[1]:= 00X;
	cmd[2]:= CHR(SYSTEM.LSH(start,-24));
	cmd[3]:= CHR(SYSTEM.LSH(start,-16));
	cmd[4]:= CHR(SYSTEM.LSH(start,-8));
	cmd[5]:= CHR(start);
	cmd[6]:= 00X;
	cmd[7]:= CHR(SYSTEM.LSH(num,-8));
	cmd[8]:= CHR(num);
	cmd[9]:= 00X;

	requ.target:= tgt[drive]; requ.lun:= 00H;
	requ.clen:= 10; requ.dlen:= num * 512;
	requ.cmd:= SYSTEM.ADR(cmd); requ.data:= SYSTEM.ADR(buf) + ofs;

	SCSI.Initiate(requ); WHILE ~requ.done DO END;
	IF (requ.status # SCSI.Good) THEN DiskError(); END;
END GetBlocks;

(** PutBlocks - Write 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0 or 1)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to write from
	"ofs" - offset from start of buf in bytes *)

PROCEDURE PutBlocks*(drive, start,num: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE; ofs: LONGINT);
VAR
	cmd: ARRAY 10 OF CHAR;
BEGIN
	cmd[0]:= 2AX;
	cmd[1]:= 00X;
	cmd[2]:= CHR(SYSTEM.LSH(start,-24));
	cmd[3]:= CHR(SYSTEM.LSH(start,-16));
	cmd[4]:= CHR(SYSTEM.LSH(start,-8));
	cmd[5]:= CHR(start);
	cmd[6]:= 00X;
	cmd[7]:= CHR(SYSTEM.LSH(num,-8));
	cmd[8]:= CHR(num);
	cmd[9]:= 00X;

	requ.target:= tgt[drive]; requ.lun:= 00H;
	requ.clen:= 10; requ.dlen:= num * 512;
	requ.cmd:= SYSTEM.ADR(cmd); requ.data:= SYSTEM.ADR(buf) + ofs;

	SCSI.Initiate(requ); WHILE ~requ.done DO END;
	IF (requ.status # SCSI.Good) THEN DiskError(); END;
END PutBlocks;

(** GetParams - Return parameters of drive (for Install) *)

PROCEDURE GetParams*(drive: LONGINT;  VAR cyls, hds, spt: LONGINT);
VAR
	cmd: ARRAY 6 OF CHAR;
	data: ARRAY 16 OF CHAR;
BEGIN
	IF (drive >= 0) & (drive < drives) THEN
		cmd[0]:= 1AX; cmd[1]:= 08X; cmd[2]:= 03X;
		cmd[3]:= 00X; cmd[4]:= 10X; cmd[5]:= 00X;
	
		requ.target:= tgt[drive]; requ.lun:= 00H; requ.clen:= 6; requ.dlen:= 16;
		requ.cmd:= SYSTEM.ADR(cmd); requ.data:= SYSTEM.ADR(data);
		
		SCSI.Initiate(requ); WHILE ~requ.done DO END;
		IF (requ.status # SCSI.Good) THEN DiskError(); END;
		spt:= SYSTEM.LSH(ORD(data[4+10]),8) + ORD(data[4+11]);
	
		cmd[2]:= 04X; cmd[4]:= 0AX; requ.dlen:= 10;
		
		SCSI.Initiate(requ); WHILE ~requ.done DO END;
		IF (requ.status # SCSI.Good) THEN DiskError(); END;
	
		cyls:= SYSTEM.LSH(LONG(ORD(data[4+2])),16) + SYSTEM.LSH(ORD(data[4+3]),8) + ORD(data[4+4]);
		hds:= ORD(data[4+5])
	ELSE
		cyls := 0;  hds := 0;  spt := 0
	END
END GetParams;

(** Install - Install the driver in the Disk module. *)

PROCEDURE Install*;
BEGIN
	Disk.GetBlocks := GetBlocks;
	Disk.PutBlocks := PutBlocks;
	Disk.GetParams := GetParams
END Install;

BEGIN
	NEW(requ); Interrogate({0..7});
	Install
END AHA1520Disk.
