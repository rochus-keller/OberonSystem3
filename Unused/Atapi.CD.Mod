(* OBERON System 3, Release 2.2.

Copyright 1997 Team of the Institute of Computer Systems of ETH Zuerich,
ETH Center, CH-8092 Zuerich, e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract.  The full text can be requested from the 
above-mentioned address, or downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE CD;	(** non-portable *)	(* fbogsany 06.01.96, driver support based on Disk.Mod - pmuller 06.06.95 *)
(* changes for InitDriver - SA96, tburri 06.96 *)

IMPORT Oberon, Texts, Kernel, Modules, Out;

VAR
	devID*: INTEGER;

PROCEDURE Eject*;

END Eject;

PROCEDURE Stop*;

END Stop;

PROCEDURE Load*;

END Load;

PROCEDURE Pause*;

END Pause;

PROCEDURE Resume*;

END Resume;

PROCEDURE ReadTocHdr*(VAR first, last: INTEGER);

END ReadTocHdr;

PROCEDURE ReadTocEntry*(track: INTEGER; VAR min, sec, frame: INTEGER);

END ReadTocEntry;

PROCEDURE Play*(min0, sec0, frame0, min1, sec1, frame1: INTEGER);

END Play;

PROCEDURE ReadLen*(VAR len: LONGINT);

END ReadLen;

PROCEDURE Sense*(VAR acs, acsq: CHAR);

END Sense;

PROCEDURE GetPosition*(VAR track, minute, second: INTEGER);

END GetPosition;

PROCEDURE MediumType*(VAR medtyp: CHAR);

END MediumType;

BEGIN
END CD.

