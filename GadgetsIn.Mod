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

MODULE GadgetsIn;	(** portable *)	(* pjm 15.04.96 *)

IMPORT Texts, Oberon, Objects, Gadgets, Strings;

VAR
	s: Texts.Scanner;
	w: Texts.Writer;
	done: BOOLEAN;

(* OpenPar - Initialise input from the command parameter.  If a "^" follows 
the command, start input from the latest selection.  If a "*" follows the 
command, start input from the marked viewer.  Otherwise, start input from 
the text following the command. *)

PROCEDURE OpenPar;
VAR t: Texts.Text;  beg, end, time: LONGINT;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(s);
	IF (s.class = Texts.Char) & (s.c = "^") THEN
		Oberon.GetSelection(t, beg, end, time);
		IF time >= 0 THEN Texts.OpenScanner(s, t, beg);  done := TRUE
		ELSE done := FALSE
		END
	ELSIF (s.class = Texts.Char) & (s.c = "*") THEN
		t := Oberon.MarkedText();
		IF t # NIL THEN Texts.OpenScanner(s, t, 0); done := TRUE
		ELSE done := FALSE
		END
	ELSE
		Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);  done := TRUE
	END
END OpenPar;

(* OpenGadget - Initialise input from a list of Gadgets in the current context.
The syntax for gadgetlist in BNF is:  name ["." attr] { "," name ["." attr] }.  
The default attr is "Value". *)

PROCEDURE OpenGadget(gadgetlist: ARRAY OF CHAR);
VAR
	t: Texts.Text;  i, j: LONGINT;  str: ARRAY 128 OF CHAR;
	a: Objects.AttrMsg;  field: Objects.Object;
BEGIN
	i := 0;
	WHILE gadgetlist[i] # 0X DO
		j := 0;
		WHILE (gadgetlist[i] # 0X) & (gadgetlist[i] # ",") & (gadgetlist[i] # ".") DO
			str[j] := gadgetlist[i];  INC(i);  INC(j)
		END;
		str[j] := 0X;
		IF gadgetlist[i] = "." THEN INC(i) END;
		j := 0;
		WHILE (gadgetlist[i] # 0X) & (gadgetlist[i] # ",") DO
			a.name[j] := gadgetlist[i];  INC(i);  INC(j)
		END;
		IF j = 0 THEN a.name := "Value"	(* default attribute *)
		ELSE a.name[j] := 0X
		END;
			(* find the field *)
		field := Gadgets.FindObj(Gadgets.context, str);
			(* get the attribute *)
		a.id := Objects.get;  a.res := -1;  field.handle(field, a);
		IF a.res = 0 THEN
			CASE a.class OF
				Objects.String: COPY(a.s, str)
				|Objects.Int: Strings.IntToStr(a.i, str)
				|Objects.Bool: Strings.BoolToStr(a.b, str)
				|Objects.Real: Strings.RealToStr(a.x, str)
				|Objects.LongReal: Strings.RealToStr(a.y, str)
				|Objects.Char: str[0] := a.c;  str[1] := 0X
			ELSE str := ""
			END
		ELSE str := ""
		END;
			(* look for whitespace *)
		j := 0;  WHILE (str[j] # 0X) & (str[j] # 9X) & (str[j] # " ") DO INC(j) END;
			(* write out field attribute value, assume value does not contain "'s *)
		IF (str[j] # 0X) OR (j = 0) THEN
			Texts.Write(w, 22X);  Texts.WriteString(w, str);  Texts.Write(w, 22X)
		ELSE
			Texts.WriteString(w, str)
		END;
		Texts.Write(w, " ");
		IF gadgetlist[i] = "," THEN INC(i) END
	END;
		(* create a text for scanning *)
	NEW(t);  Texts.Open(t, "");
	Texts.Append(t, w.buf);
	Texts.OpenScanner(s, t, 0);  done := TRUE
END OpenGadget;

(** Open - Initialise input from a list of Gadgets in the current context.
The syntax for gadgetlist in BNF is:  name ["." attr] { "," name ["." attr] }.  
The default attr is "Value".  If the list is empty, start input from the command 
parameter.  If a "^" follows the command, start input from the latest selection.  
If a "*" follows the command, start input from the marked viewer.  Otherwise, 
start input from the text following the command. *)

PROCEDURE Open*(gadgetlist: ARRAY OF CHAR);
BEGIN
	IF gadgetlist = "" THEN OpenPar
	ELSE OpenGadget(gadgetlist)
	END
END Open;

(** Char - Input a single character token. *)

PROCEDURE Char*(VAR x: CHAR);
BEGIN
	IF done THEN
		IF s.eot THEN done := FALSE;  x := 0X
		ELSE Texts.Scan(s);
			IF s.class = Texts.Char THEN x:= s.c
			ELSE done:= FALSE; x:= 0X
			END
		END
	ELSE x := 0X
	END
END Char;

(** Int - Input an integer. *)

PROCEDURE Int*(VAR x: LONGINT);
BEGIN
	IF done THEN
		Texts.Scan(s);
		IF s.class = Texts.Int THEN x := s.i
		ELSE done := FALSE;  x := 0
		END
	ELSE x := 0
	END
END Int;

(** Real - Input a real number. *)

PROCEDURE Real*(VAR x: REAL);
BEGIN
	IF done THEN
		Texts.Scan(s);
		IF s.class = Texts.Real THEN x := s.x
		ELSIF s.class = Texts.Int THEN x := s.i
		ELSE done := FALSE; x := 0
		END
	ELSE x := 0
	END
END Real;

(** LongReal - Input a long real number. *)

PROCEDURE LongReal*(VAR x: LONGREAL);
BEGIN
	IF done THEN
		Texts.Scan(s);
		IF s.class = Texts.LongReal THEN x := s.y
		ELSIF s.class = Texts.Real THEN x := s.x
		ELSIF s.class = Texts.Int THEN x := s.i
		ELSE done := FALSE; x := 0
		END
	ELSE x := 0
	END
END LongReal;

(** Name - Input a name (max 32 characters). *)

PROCEDURE Name*(VAR x: ARRAY OF CHAR);
BEGIN
	IF done THEN
		Texts.Scan(s);
		IF s.class = Texts.Name THEN COPY(s.s, x)
		ELSE done := FALSE; COPY("", x)
		END
	ELSE COPY("", x)
	END
END Name;

(** String - Input a string (max 32 characters). *)

PROCEDURE String*(VAR x: ARRAY OF CHAR);
BEGIN
	IF done THEN
		Texts.Scan(s);
		IF (s.class = Texts.String) OR (s.class = Texts.Name) THEN COPY(s.s, x)
		ELSE done := FALSE; COPY("", x)
		END
	ELSE COPY("", x)
	END
END String;

(** Boolean - Input a boolean (Yes/No or True/False). *)

PROCEDURE Boolean*(VAR x: BOOLEAN);
VAR s: ARRAY 32 OF CHAR;
BEGIN
	String(s);
	IF done THEN
		IF (CAP(s[0]) = "Y") OR (CAP(s[0]) = "T") THEN x := TRUE
		ELSIF (CAP(s[0]) = "N") OR (CAP(s[0]) = "F") THEN x := FALSE
		ELSE done := FALSE; x := FALSE
		END
	ELSE x := FALSE
	END
END Boolean;

(** Done - Return TRUE iff all input since the last Open call was successful. *)

PROCEDURE Done*(): BOOLEAN;
BEGIN
	RETURN done
END Done;

BEGIN
	Texts.OpenWriter(w)
END GadgetsIn.

