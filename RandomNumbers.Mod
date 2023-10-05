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

MODULE RandomNumbers;	(** portable *)
(* Random Number Generator, page 12 *)
IMPORT Math;

VAR Z: LONGINT;

(** Return a uniform random number r, with 0 < r < 1. *)

PROCEDURE Uniform*(): REAL;
CONST
a = 16807;	m = 2147483647; 
q = m DIV a;	r = m MOD a;
VAR g: LONGINT;
BEGIN
	g := a*(Z MOD q) - r*(Z DIV q);
	IF g > 0 THEN Z := g ELSE Z := g + m END;
	RETURN SHORT(Z*1.0D0/m)	(* must compute this in double precision, e.g. (m-1)/m *)
END Uniform;

(** Return an exponentially distributed random number r. *)

PROCEDURE Exp*(mu: REAL): REAL;
BEGIN
	RETURN -Math.ln(Uniform())/mu
END Exp;

(** Initialize the random number seed. *)

PROCEDURE InitSeed*(seed: LONGINT);
BEGIN
	Z := seed
END InitSeed;

BEGIN
	Z := 1
END RandomNumbers.	(* Copyright M. Reiser, 1992 *)