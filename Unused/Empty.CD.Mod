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

MODULE CD;	(** non-portable *)

VAR
	devID*: INTEGER;

PROCEDURE Error;
VAR error: ARRAY 32 OF CHAR;
BEGIN
	error := "No CD configured";  HALT(99)
END Error;
	
PROCEDURE Eject*;
BEGIN
	Error
END Eject;

PROCEDURE Stop*;
BEGIN
	Error
END Stop;

PROCEDURE Load*;
BEGIN
	Error
END Load;

PROCEDURE Pause*;
BEGIN
	Error
END Pause;

PROCEDURE Resume*;
BEGIN
	Error
END Resume;

PROCEDURE ReadTocHdr*(VAR first, last: INTEGER);
BEGIN
	Error
END ReadTocHdr;

PROCEDURE ReadTocEntry*(track: INTEGER; VAR min, sec, frame: INTEGER);
BEGIN
	Error
END ReadTocEntry;

PROCEDURE Play*(min0, sec0, frame0, min1, sec1, frame1: INTEGER);
BEGIN
	Error
END Play;

PROCEDURE ReadLen*(VAR len: LONGINT);
BEGIN
	Error
END ReadLen;

PROCEDURE Sense*(VAR acs, acsq: CHAR);
BEGIN
	Error
END Sense;

PROCEDURE GetPosition*(VAR track, minute, second: INTEGER);
BEGIN
	Error
END GetPosition;

PROCEDURE MediumType*(VAR medtyp: CHAR);
BEGIN
	Error
END MediumType;

BEGIN
	devID := -1
END CD.

