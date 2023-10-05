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

MODULE Centronics;	(** non-portable *)	(* pjm 07.08.95 *)

(* Native version *)

IMPORT Kernel, Input;

CONST 
	LPT1* = 0;
	LPT2* = 1;
	LPT3* = 2;
	

(** Start - Open parallel port. *)

PROCEDURE Start*(port: INTEGER);

END Start;

(** Reset - Reset parallel port. *)

PROCEDURE Reset*(port: INTEGER);

END Reset;

(** Stop - Close parallel port. *)

PROCEDURE Stop*(port: INTEGER);
(* nop in current implementation *)
END Stop;

(** Send - Send byte to parallel port, waiting until it is ready. *)

PROCEDURE Send*(port: INTEGER; x: CHAR);

END Send;

(** SendPoll - Send byte to parallel port.  done indicates success or failure. *)

PROCEDURE SendPoll*(port: INTEGER;  x: CHAR;  VAR done: BOOLEAN);

END SendPoll;

(** Available - Returns number of bytes available for reading (implementation optional). *)

PROCEDURE Available*(port: INTEGER): LONGINT;

END Available;

(** Receive - Read a byte from the parallel port (implementation optional). *)

PROCEDURE Receive*(port: INTEGER; VAR x: CHAR);

END Receive;

BEGIN
END Centronics.
