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

MODULE Prefix;	(** non-portable *)

(* 01.11.94 pmuller - Set FileDir prefix. for bootstrapping. use carefully! *)

IMPORT In, FileDir, Out;

PROCEDURE Set*;
VAR prefix: ARRAY 10 OF CHAR;
BEGIN
	In.Open; In.Name(prefix);
	IF In.Done THEN
		COPY(prefix, FileDir.prefix);
		Out.String("Prefix.Set "); Out.Char(22X); Out.String(FileDir.prefix); 
		Out.Char(22X); Out.Ln
	END
END Set;

PROCEDURE Clear*;
BEGIN
	FileDir.prefix := "";
	Out.String("Prefix.Clear"); Out.Ln
END Clear;

PROCEDURE Show*;
BEGIN
	Out.String("Prefix.Show ");
	Out.Char(22X); Out.String(FileDir.prefix); Out.Char(22X); Out.Ln
END Show;

END Prefix.

Prefix.Show
Prefix.Clear
Prefix.Set Test.
