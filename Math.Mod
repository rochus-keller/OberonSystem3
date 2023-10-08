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

MODULE Math;	(** portable *)

IMPORT P := ObxPal;

(**
	Commonly needed Math for REALs.
*)

CONST
	e* = 2.7182818284590452354E0;
	pi* = 3.14159265358979323846E0;
	
PROCEDURE sin*(x: REAL): REAL;
  RETURN SHORT(P.sin(x))
END sin;

PROCEDURE cos*(x: REAL): REAL;
  RETURN SHORT(P.cos(x))
END cos;

PROCEDURE arctan*(x: REAL): REAL;
  RETURN SHORT(P.arctan(x))
END arctan;

PROCEDURE sqrt*(x: REAL): REAL;
  RETURN SHORT(P.sqrt(x))
END sqrt;

PROCEDURE ln*(x: REAL): REAL;
  RETURN SHORT(P.ln(x))
END ln;

PROCEDURE exp*(x: REAL): REAL;
  RETURN SHORT(P.exp(x))
END exp;

END Math.
