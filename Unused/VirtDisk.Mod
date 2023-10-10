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

MODULE VirtDisk;	(** non-portable *)	(* pjm *)

(* Virtual disk driver for install program *)

IMPORT Files;

TYPE
	Sector* = RECORD END;	(** 2k Oberon Sector *)

CONST
	SS = 2048;	(* Oberon sector size *)

VAR
	disk*: Files.File;
	allocated: LONGINT;

PROCEDURE AddSector;
VAR i: LONGINT;  r: Files.Rider;
BEGIN
	Files.Set(r, disk, Files.Length(disk));
	FOR i := 0 TO SS-1 DO Files.Write(r, 0X) END
END AddSector;

(** ResetDisk - Initialize the disk with one sector (number 29). *)

PROCEDURE ResetDisk*;
BEGIN
	disk := Files.New("");
	AddSector;
	allocated := 1
END ResetDisk;

(* InSector - Convert a sector number to a file offset. *)

PROCEDURE InSector(VAR sec: LONGINT);                
BEGIN
	IF (sec < 29) OR (sec MOD 29 # 0) THEN HALT(21) (* Illegal sector address *) END;
	sec := (sec DIV 29 - 1) * SS
END InSector;

(** AllocSector - Allocate a new sector.  hint is ignored. *)

PROCEDURE AllocSector*(hint: LONGINT; VAR sec: LONGINT);
BEGIN
	AddSector;
	INC(allocated);  sec := allocated*29
END AllocSector;

(** GetSector - Read from an allocated sector. *)

PROCEDURE GetSector*(src: LONGINT; VAR dest: Sector);
VAR r: Files.Rider;
BEGIN
	InSector(src);
	IF (src < 0) OR (src >= Files.Length(disk)) THEN HALT(20) END;
	Files.Set(r, disk, src);
	Files.ReadBytes(r, dest, SS)
END GetSector;

(** PutSector - Write to an allocated sector. *)

PROCEDURE PutSector*(dest: LONGINT; VAR src: Sector);
VAR r: Files.Rider;
BEGIN
	InSector(dest);
	IF (dest < 0) OR (dest >= Files.Length(disk)) THEN HALT(20) END;
	Files.Set(r, disk, dest);
	Files.WriteBytes(r, src, SS)
END PutSector;

END VirtDisk.
