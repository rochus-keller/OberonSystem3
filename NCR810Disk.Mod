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

MODULE NCR810Disk;	(** non-portable *)	(* Contributed by P. Ryser to the System 3 project *)

(* NCR 810 SCSI Disk driver for Native Oberon *)

	IMPORT Kernel, SYSTEM, ASPI, Disk;

	CONST
		chsdebug = FALSE;	readdebug = FALSE;
		
		MaxDevices = 10;
		
		BS = 512;	(* disk block size *)
		
	TYPE
		Part = POINTER TO PartDesc;
		PartDesc = RECORD
			bootind, head, sector, cyl, type, head2, sector2, cyl2: CHAR;
			start, num: LONGINT
		END;
	
		DeviceDesc = RECORD
			ha, target, lun: CHAR;
			cylinders, cylinders0: LONGINT;	(* number of cylinders *)
			heads, heads0: LONGINT;	(* number of heads *)
			sectrack: LONGINT;	(* sectors/track *)
			writePreComp: LONGINT;
			capacity, blocksize: LONGINT;
			obstart, obend: LONGINT;
		END;

	VAR
		devs: ARRAY MaxDevices OF DeviceDesc;
		numdevs: LONGINT;	(* number of physical devices *)

	PROCEDURE LogInt(i: LONGINT);
	BEGIN
		Kernel.WriteInt(i, 1)
	END LogInt;
	
	PROCEDURE -CoreHalt(n: LONGINT);
	CODE {SYSTEM.i386}
		INT 3
	END CoreHalt;
	
	PROCEDURE -Error(err: LONGINT);
	CODE {SYSTEM.i386}
		POP EAX	(* for register dump *)
		PUSH 17	(* Disk error *)
		INT 3
	END Error;

(* ReadBlocks - Read disk blocks *)

	PROCEDURE ReadBlocks(drive, sec, num, adr, offset: LONGINT): LONGINT;
	VAR srb: ASPI.ExecIOCmdSRB; err: LONGINT;
	BEGIN
		err := 0;
		NEW(srb);
		INC(sec, offset);
		IF (sec < 0) OR (num >= 256*256) THEN HALT(100) END;
		IF readdebug & ~((sec >= devs[drive].obstart) & (sec+num <= devs[drive].obend)) THEN
			Kernel.WriteString("Read on block:"); LogInt(sec); Kernel.WriteString("   length:"); LogInt(num); Kernel.WriteLn
		END;
		srb.HaId := devs[drive].ha; srb.Flags := {ASPI.FlagsDirIn}; srb.Target := devs[drive].target; srb.Lun := devs[drive].lun;
		srb.BufLen := BS*num; srb.BufPointer := adr; srb.SenseLen := 0X;
		srb.CDBLen := 0AX;
		srb.CDB[0] := 28X; srb.CDB[1] := SYSTEM.LSH(devs[drive].lun, 5);
		srb.CDB[2] := CHR(sec DIV 1000000H); srb.CDB[3] := CHR((sec DIV 10000H) MOD 100H);
		srb.CDB[4] := CHR((sec DIV 100H) MOD 100H); srb.CDB[5] := CHR(sec MOD 100H);
		srb.CDB[6] := 0X;
		srb.CDB[7] := CHR(num DIV 100H); srb.CDB[8] := CHR(num MOD 100H);
		srb.CDB[9] := 0X;
		srb.meas := NIL;
		srb.Status := 55X;
		ASPI.SendASPICommand(srb);
		WHILE srb.Status = ASPI.SSPending DO END;
		ASSERT(srb.Status = ASPI.SSComp);
		RETURN err;
	END ReadBlocks;

(* WriteBlocks - Write disk blocks *)

	PROCEDURE WriteBlocks(drive, sec, num, adr, offset: LONGINT): LONGINT;
	VAR srb: ASPI.ExecIOCmdSRB; err: LONGINT;
	BEGIN
		err := 0;
		NEW(srb);
		INC(sec, offset);
		IF (sec < 0) OR (num >= 256*256) THEN HALT(100) END;
		IF readdebug & ~((sec >= devs[drive].obstart) & (sec+num <= devs[drive].obend)) THEN
			Kernel.WriteString("Write on block:"); LogInt(sec); Kernel.WriteString("   length:"); LogInt(num); Kernel.WriteLn;
			IF (sec # 0) OR (num > 1) THEN HALT(101) END;
		END;
		srb.HaId := devs[drive].ha; srb.Flags := {ASPI.FlagsDirOut}; srb.Target := devs[drive].target; srb.Lun := devs[drive].lun;
		srb.BufLen := BS*num; srb.BufPointer := adr; srb.SenseLen := 0X;
		srb.CDBLen := 0AX;
		srb.CDB[0] := 2AX; srb.CDB[1] := SYSTEM.LSH(devs[drive].lun, 5);
		srb.CDB[2] := CHR(sec DIV 1000000H); srb.CDB[3] := CHR((sec DIV 10000H) MOD 100H);
		srb.CDB[4] := CHR((sec DIV 100H) MOD 100H); srb.CDB[5] := CHR(sec MOD 100H);
		srb.CDB[6] := 0X;
		srb.CDB[7] := CHR(num DIV 100H); srb.CDB[8] := CHR(num MOD 100H);
		srb.CDB[9] := 0X;
		srb.meas := NIL;
		srb.Status := 55X;
		ASPI.SendASPICommand(srb);
		WHILE srb.Status = ASPI.SSPending DO END;
		ASSERT(srb.Status = ASPI.SSComp);
		RETURN err
	END WriteBlocks;


(* ---- Calculate disk geometry ---- *)

	PROCEDURE Partsize(drive: LONGINT; VAR res: LONGINT);
	VAR
		p, cyl, lcyl, cyl2, sector2, head2, extpend, extcyl, lend, pend, i: LONGINT;
		pp, lpp: Part;
		pd: ARRAY 512 OF CHAR;
	BEGIN
		res := ReadBlocks(drive, 0, 1, SYSTEM.ADR(pd[0]), 0); ASSERT(res = 0);
		res := -1; devs[drive].obstart := -1; devs[drive].obend := -1;
		IF (pd[510] = 055X) &  (pd[511] = 0AAX) THEN
			p := 1BEH+SYSTEM.ADR(pd[0]); lcyl := -1;
			FOR i := 0 TO 3 DO
				IF chsdebug THEN Kernel.WriteString("Partition"); LogInt(i); Kernel.WriteLn END;
				pp := SYSTEM.VAL(Part, p);
				IF pp.type # 0X THEN
					IF pp.type = 4FX THEN
						devs[drive].obstart := pp.start; devs[drive].obend := pp.start+pp.num
					END;
					cyl := ORD(pp.cyl) + ORD(SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, pp.sector)*{6,7}))*4;
					IF cyl > lcyl THEN lpp := pp; lcyl := cyl END;
					IF chsdebug THEN
						Kernel.WriteString("   BootInd:"); LogInt(ORD(pp.bootind)); Kernel.WriteLn;
						Kernel.WriteString("   Type:"); LogInt(ORD(pp.type)); Kernel.WriteLn;
						Kernel.WriteString("   Start:"); LogInt(pp.start); Kernel.WriteLn;
						Kernel.WriteString("   Num:"); LogInt(pp.num); Kernel.WriteLn;
						Kernel.WriteString("   Head:"); LogInt(ORD(pp.head)); Kernel.WriteLn;
						Kernel.WriteString("   Sector:"); LogInt(ORD(pp.sector)); Kernel.WriteLn;
						Kernel.WriteString("   cyl:"); LogInt(ORD(pp.cyl)); Kernel.WriteLn;
						Kernel.WriteString("   Head2:"); LogInt(ORD(pp.head2)); Kernel.WriteLn;
						Kernel.WriteString("   Sector2:"); LogInt(ORD(pp.sector2)); Kernel.WriteLn;
						Kernel.WriteString("   cyl2:"); LogInt(ORD(pp.cyl2)); Kernel.WriteLn;
						Kernel.WriteString("   cyl:"); LogInt(cyl); Kernel.WriteLn;
					END
				END;
				INC(p, 16)
			END;
			IF lcyl # -1 THEN
				cyl2 := ORD(lpp.cyl2) + ORD(SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, lpp.sector2)*{6,7}))*4;
				head2 := ORD(lpp.head2);
				sector2 := ORD(lpp.sector2) MOD 40H;
				pend := cyl2*(head2 + 1)*sector2+head2*sector2+sector2;
				lend := lpp.start+lpp.num;
				
				extcyl := (lend-(head2*sector2+sector2)) DIV (head2 + 1) DIV sector2;
				extpend := extcyl*(head2+1)*sector2+head2*sector2+sector2;
				
				IF chsdebug THEN
					Kernel.WriteString("   head2:"); LogInt(head2); Kernel.WriteLn;
					Kernel.WriteString("   cyl2:"); LogInt(cyl2); Kernel.WriteLn;
					Kernel.WriteString("   sector2:"); LogInt(sector2); Kernel.WriteLn;
					Kernel.WriteString("   lend:"); LogInt(lend); Kernel.WriteLn;
					Kernel.WriteString("   pend:"); LogInt(pend); Kernel.WriteLn;
					Kernel.WriteString("   extpend:"); LogInt(extpend); Kernel.WriteLn;
					Kernel.WriteString("   extcyl:"); LogInt(extcyl); Kernel.WriteLn
				END;

				IF (lend = pend) OR ((cyl2 = 1023) & (extpend = lend)) THEN
					devs[drive].sectrack := sector2;
					devs[drive].heads0 := head2+1;
					devs[drive].cylinders0 := devs[drive].capacity DIV ((head2 + 1) * sector2);
					res := 0;
					IF chsdebug THEN
						Kernel.WriteString("Partsize:"); Kernel.WriteLn;
						Kernel.WriteString("   secs:"); LogInt(devs[drive].sectrack); Kernel.WriteLn;
						Kernel.WriteString("   hds:"); LogInt(devs[drive].heads0); Kernel.WriteLn;
						Kernel.WriteString("   cyls:"); LogInt(devs[drive].cylinders0); Kernel.WriteLn
					END
				END;
			END
		END
	END Partsize;
	
	PROCEDURE Setsize(drive: LONGINT; VAR res: LONGINT);
	VAR cylinders, temp, heads, sectors, capacity: LONGINT;
	BEGIN
		cylinders := 1024; sectors := 62;
		temp := cylinders*sectors;
		capacity := devs[drive].capacity;
		heads := capacity DIV temp;
		
		IF capacity MOD temp # 0 THEN
			INC(heads);
			temp := cylinders*heads;
			sectors := capacity DIV temp;
			IF capacity MOD temp # 0 THEN
				INC(sectors);
				temp := heads*sectors;
				cylinders := capacity DIV temp
			END
		END;
		IF cylinders = 0 THEN res := -1 ELSE res := 0 END;
		devs[drive].sectrack := sectors;
		devs[drive].heads0 := heads;
		devs[drive].cylinders0 := cylinders;
		IF chsdebug THEN
			Kernel.WriteString("Setsize:"); Kernel.WriteLn;
			Kernel.WriteString("   secs:"); LogInt(devs[drive].sectrack); Kernel.WriteLn;
			Kernel.WriteString("   hds:"); LogInt(devs[drive].heads0); Kernel.WriteLn;
			Kernel.WriteString("   cyls:"); LogInt(devs[drive].cylinders0); Kernel.WriteLn
		END
	END Setsize;

	PROCEDURE GetGeo(drive: LONGINT);
	VAR res: LONGINT;
	BEGIN
		devs[drive].heads := 0; devs[drive].heads0 := 0;
		devs[drive].cylinders := 0; devs[drive].cylinders0 := 0;
		devs[drive].sectrack := 0;
		res := -1;
		Partsize(drive, res);
		IF res # 0 THEN Setsize(drive, res) END;
		IF res # 0 THEN Kernel.WriteString("GetGeo: Could not get disk geometry"); Kernel.WriteLn END
(*		ASSERT(res = 0); *)
	END GetGeo;
	
(* ---- Get disk capacity and block size ---- *)
	
	PROCEDURE GetCapacity(drive: LONGINT);
	VAR srb: ASPI.ExecIOCmdSRB; buf: ARRAY 8 OF CHAR; i: LONGINT;
	BEGIN
		NEW(srb);
		srb.HaId := devs[drive].ha; srb.Flags := {ASPI.FlagsDirIn}; srb.Target := devs[drive].target; srb.Lun := devs[drive].lun;
		srb.BufLen := 8; srb.BufPointer := SYSTEM.ADR(buf[0]); srb.SenseLen := 0X;
		srb.CDBLen := 0AX;
		srb.CDB[0] := 25X; srb.CDB[1] := SYSTEM.LSH(devs[drive].lun, 5); srb.CDB[2] := 0X; srb.CDB[3] := 0X;
		srb.CDB[4] := 0X; srb.CDB[5] := 0X; srb.CDB[6] := 0X; srb.CDB[7] := 0X; srb.CDB[8] := 0X; srb.CDB[9] := 0X;
		srb.meas := NIL;
		srb.Status := 55X;
		ASPI.SendASPICommand(srb);
		WHILE srb.Status = ASPI.SSPending DO END;
		ASSERT(srb.Status = ASPI.SSComp);
		devs[drive].capacity := 0; devs[drive].blocksize := 0;
		FOR i := 0 TO 3 DO
			devs[drive].capacity := devs[drive].capacity*100H + ORD(buf[i]);
			devs[drive].blocksize := devs[drive].blocksize*100H + ORD(buf[i+4])
		END;
		ASSERT(devs[drive].blocksize=BS)
	END GetCapacity;

(** GetBlocks - Read 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0 or 1)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to read into
	"ofs" - offset from start of buf in bytes *)

PROCEDURE GetBlocks*(drive, start, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
VAR err: LONGINT;
BEGIN
	err := ReadBlocks(drive, start, num, SYSTEM.ADR(buf[ofs]), 0);
	IF err # 0 THEN Error(err) END
END GetBlocks;

(** PutBlocks - Write 512-byte disk blocks.  Low-level interface to driver.
	"drive" - hard disk number (0 or 1)
	"start" - start sector number
	"num" - number of sectors
	"buf" - buffer to write from
	"ofs" - offset from start of buf in bytes *)

PROCEDURE PutBlocks*(drive, start, num: LONGINT;  VAR buf: ARRAY OF SYSTEM.BYTE;  ofs: LONGINT);
VAR err: LONGINT;
BEGIN
	err := WriteBlocks(drive, start, num, SYSTEM.ADR(buf[ofs]), 0);
	IF err # 0 THEN Error(err) END
END PutBlocks;

(** GetParams - Return parameters of drive  *)

	PROCEDURE GetParams*(drive: LONGINT;  VAR cyls, hds, spt: LONGINT);
	BEGIN
		IF (drive >= 0) & (drive < numdevs) THEN
			cyls := devs[drive].cylinders0;  hds := devs[drive].heads0;  spt := devs[drive].sectrack
		ELSE
			cyls := 0;  hds := 0;  spt := 0
		END
	END GetParams;
	
	PROCEDURE Init;
	VAR res, ha, targ, lun: LONGINT; srb: ASPI.GetDevTypeSRB;
	BEGIN
		numdevs := 0;
		res := ASPI.GetASPISupportInfo();
		IF CHR(SYSTEM.LSH(res, -8)) = ASPI.SSComp THEN
			res := res MOD 100H;
			NEW(srb); ha := 0;
			WHILE ha < res DO
				targ := 0;
				WHILE targ < 7 DO
					lun := 0; srb.Status := ASPI.SSComp;
					WHILE (lun < 8) & (srb.Status = ASPI.SSComp) DO 
						Kernel.WriteString("Init: ha:"); LogInt(ha); Kernel.WriteString("  target:"); LogInt(targ); Kernel.WriteString("  lun:"); LogInt(lun); Kernel.WriteLn;
						srb.HaId := CHR(ha); srb.Flags := {};
						srb.Target := CHR(targ); srb.Lun := CHR(lun);
						ASPI.SendASPICommand(srb);
						Kernel.WriteString("DevType: "); LogInt(ORD(srb.DevType)); Kernel.WriteLn;
						IF (srb.Status = ASPI.SSComp) & (srb.DevType = 0X) THEN (* only support direct access devices *)
							devs[numdevs].ha := CHR(ha); devs[numdevs].target := CHR(targ);
							devs[numdevs].lun := CHR(lun);
							devs[numdevs].writePreComp := 0;
							GetCapacity(numdevs);
							GetGeo(numdevs);
							INC(numdevs)
						END;
						INC(lun)
					END;
					INC(targ)
				END;
				INC(ha)
			END
		ELSE
			Kernel.WriteString("NCR810Disk: no host adapter found"); Kernel.WriteLn
		END
	END Init;
		
	(** Install - Install the driver in the Disk module. *)
	
	PROCEDURE Install*;
	BEGIN
		Disk.GetBlocks := GetBlocks;
		Disk.PutBlocks := PutBlocks;
		Disk.GetParams := GetParams
	END Install;

BEGIN
	Init;  Install
END NCR810Disk.

ASPI.Stop
SCSIDisk.ShowPartitions
System.Free SCSIDisk ASPI ~
