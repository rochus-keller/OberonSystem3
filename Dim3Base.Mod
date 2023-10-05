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

MODULE Dim3Base;	(** portable *)	(* David Ulrich Nov  95 - März 96 *)
(* This module contains not portable procedures for the Native version **)

IMPORT S := SYSTEM, Pictures;
CONST Black* = 15; White* = 0;	(** black and white of the windows color table **)
VAR
	baseAdr, lineW, height: LONGINT;

(** correct color table for Native version **)
PROCEDURE CheckColorTab*(VAR R, G, B: ARRAY OF INTEGER);
BEGIN
	(* nothing to do *)
END CheckColorTab;

(** convert color number to Dim3 color palette **)
PROCEDURE GetRealColor*(color: INTEGER):INTEGER;
BEGIN
	RETURN color
END GetRealColor;

(** calculate picture addresses **)
PROCEDURE SetPicture*(P: Pictures.Picture);
BEGIN
	baseAdr := P.address;
	lineW := P.width; height := P.height;
END SetPicture;

(** get address of position X in current scanline Y of actual picture **)
PROCEDURE GetAddress*(X, Y: INTEGER): LONGINT;
BEGIN
	RETURN baseAdr + lineW * Y + X;
END GetAddress;

(** ReplConst in previosly set picture with mode replace, H = 1 **)
PROCEDURE ReplConst*(col, X, Y, W: INTEGER);
VAR col4: SET; color: CHAR; pictAdr: LONGINT; color4: ARRAY 4 OF CHAR;
BEGIN
	color := CHR(col);
	color4[0] := color; color4[1] := color; color4[2] := color; color4[3] := color; 
	col4 := S.VAL(SET, color4);
	pictAdr := baseAdr + lineW * Y + X;
	WHILE W > 4 DO S.PUT(pictAdr, col4); DEC(W, 4); INC(pictAdr, 4) END;
	WHILE W > 0 DO S.PUT(pictAdr, color); DEC(W); INC(pictAdr) END;
END ReplConst;

END Dim3Base.