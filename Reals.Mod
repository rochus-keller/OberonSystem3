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

MODULE Reals;	(** portable *)

(** Implementation of the non-portable components of IEEE REAL and 
LONGREAL manipulation. The routines here are required to do conversion 
of reals to strings and back. 
Implemented by Bernd Moesli, Seminar for Applied Mathematics, 
Swiss Federal Institute of Technology Zürich.
*)

IMPORT Kernel, P := ObxPal;

(* Bernd Moesli
	Seminar for Applied Mathematics
	Swiss Federal Institute of Technology Zurich
	Copyright 1993

	Support module for IEEE floating-point numbers

	Please change constant definitions of H, L depending on byte ordering
	Use bm.TestReals.Do for testing the implementation.

	Expo, ExpoL return the shifted binary exponent (0 <= e < 256 (2048 resp.))
	SetExpo, SetExpoL set the shifted binary exponent
	Real, RealL convert hexadecimals to reals
	Int, IntL convert reals to hexadecimals
	Ten returns 10^e (e <= 308, 308 < e delivers NaN)

	1993.4.22	IEEE format only, 32-bits LONGINTs only
	30.8.1993	mh: changed RealX to avoid compiler warnings;
	7.11.1995	jt: dynamic endianess test
	22.01.97	pjm: NaN stuff (using quiet NaNs only to avoid traps)
	05.01.98	prk: NaN with INF support
*)

VAR
	DefaultFCR*: SET; // only used by System Trap

(** Returns the shifted binary exponent (0 <= e < 256). *)
PROCEDURE Expo* (x: REAL): LONGINT;
BEGIN
	RETURN 0 // TODO
END Expo;

(** Returns the shifted binary exponent (0 <= e < 2048). *)
PROCEDURE ExpoL* (x: LONGREAL): LONGINT;
	VAR i: LONGINT;
BEGIN
	RETURN 0 // TODO
END ExpoL;

(** Sets the shifted binary exponent. *)
PROCEDURE SetExpoL* (e: LONGINT; VAR x: LONGREAL);
	VAR i: LONGINT;
BEGIN
	// TODO
END SetExpoL;

(** Convert hexadecimal to REAL. *)
PROCEDURE Real* (h: LONGINT): REAL;
	VAR x: REAL;
BEGIN RETURN 0 // TODO
END Real;

(** Convert hexadecimal to LONGREAL. h and l are the high and low parts.*)
PROCEDURE RealL* (h, l: LONGINT): LONGREAL;
	VAR x: LONGREAL;
BEGIN RETURN 0 // TODO
END RealL;

(** Convert REAL to hexadecimal. *)
PROCEDURE Int* (x: REAL): LONGINT;
	VAR i: LONGINT;
BEGIN RETURN 0 // TODO
END Int;

(** Convert LONGREAL to hexadecimal. h and l are the high and low parts. *)
PROCEDURE IntL* (x: LONGREAL; VAR h, l: LONGINT);
BEGIN // TODO
END IntL;

(** Returns 10^e (e <= 308, 308 < e delivers IEEE-code +INF). *)
PROCEDURE Ten* (e: LONGINT): LONGREAL;
BEGIN
	RETURN P.pow(10.0,FLT(e))
END Ten;

(** Returns the NaN code (0 <= c < 8399608) or -1 if not NaN/Infinite. *)
PROCEDURE NaNCode* (x: REAL): LONGINT;
BEGIN
	RETURN 0 // TODO
END NaNCode;

(** Returns the NaN code (0 <= h < 1048576, MIN(LONGINT) <= l <= MAX(LONGINT)) or (-1,-1) if not NaN/Infinite. *)
PROCEDURE NaNCodeL* (x: LONGREAL;  VAR h, l: LONGINT);
BEGIN
	// TODO
END NaNCodeL;

(** Returns NaN with specified code (0 <= h < 1048576, MIN(LONGINT) <= l <= MAX(LONGINT)). *)
PROCEDURE NaNL* (h, l: LONGINT): LONGREAL;
VAR x: LONGREAL;
BEGIN
	RETURN 0 // TODO
END NaNL;

(** Return state of the floating-point control register. *)
PROCEDURE FCR*(): SET;
BEGIN
	RETURN DEFAULT(SET) // TODO
END FCR;

(** Set state of floating-point control register.  Traps reset this to the default & ENTIER resets the rounding mode. *)
PROCEDURE SetFCR*(s: SET);
BEGIN
	// TODO
END SetFCR;

END Reals.