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

MODULE GadgetsOut;	(** portable *)	(* pjm 15.04.96 *)

IMPORT Texts, Objects, Gadgets, Oberon;

VAR
	w: Texts.Writer;
	text, temp: Texts.Text;
	outobj: Objects.Object;
	outattr: ARRAY 32 OF CHAR;
	
(** Open - Open output to the named gadget (in the current context).
	If the name contains a ".", the part before the dot specifies the gadget name,
	and the part after the dot specifies the string attribute where output should 
	go (default "Value").  Otherwise, if the gadget has a text model, output is 
	sent to the model.  If gadget = "", output is sent to Oberon.Log. *)

PROCEDURE Open*(gadget: ARRAY OF CHAR);
VAR obj: Objects.Object;  m: Objects.LinkMsg;  a: Objects.AttrMsg;  i, j: INTEGER;
BEGIN
	IF gadget = "" THEN
		text := Oberon.Log;  outobj := NIL
	ELSE
		j := 0;  i := 0;  WHILE (gadget[i] # 0X) & (gadget[i] # ".") DO INC(i) END;
		IF gadget[i] = "." THEN	(* attribute name was specified *)
			gadget[i] := 0X;  INC(i);
			WHILE gadget[i] # 0X DO outattr[j] := gadget[i];  INC(i);  INC(j) END
		END;
		outattr[j] := 0X;  m.obj := NIL;
		obj := Gadgets.FindObj(Gadgets.context, gadget);  ASSERT(obj # NIL);
		IF outattr = "" THEN	(* check for text model if no attribute specified *)
			m.id := Objects.get;  m.name := "Model";  m.res := -1;  obj.handle(obj, m)
		END;
		IF (m.obj # NIL) & (m.obj IS Texts.Text) THEN
			text := m.obj(Texts.Text);  outobj := NIL
		ELSE
			IF outattr = "" THEN outattr := "Value" END;	(* default attr *)
			a.id := Objects.get;  a.res := -1;  COPY(outattr, a.name);
			obj.handle(obj, a);  ASSERT((a.res = 0) & (a.class = Objects.String));
			text := NIL;  outobj := obj
		END
	END
END Open;

(** Clear - Clear the output text or string. *)

PROCEDURE Clear*;
VAR a: Objects.AttrMsg;
BEGIN
	IF text = NIL THEN
		ASSERT(outobj # NIL);
		Objects.Stamp(a);  a.id := Objects.set;  a.res := -1;  COPY(outattr, a.name);  
		a.class := Objects.String;  a.s := "";  outobj.handle(outobj, a);
		Gadgets.Update(outobj)
	ELSE
		Texts.Delete(text, 0, text.len)
	END
END Clear;

(** Append - Append the internal buffer to the output text or string.  In the case 
	of output to a string attribute, the string is always overwritten. *)

PROCEDURE Append*;
VAR a: Objects.AttrMsg;  r: Texts.Reader;  i, pos: LONGINT;
BEGIN
	IF text = NIL THEN
		ASSERT(outobj # NIL);
		Objects.Stamp(a);  a.id := Objects.set;  a.res := -1;  COPY(outattr, a.name);
		a.class := Objects.String;
		pos := temp.len;  Texts.Append(temp, w.buf);
		Texts.OpenReader(r, temp, pos);  i := 0;  Texts.Read(r, a.s[i]);
		WHILE ~r.eot & (i # 63) DO INC(i); Texts.Read(r, a.s[i]) END;
		a.s[i] := 0X;  outobj.handle(outobj, a);
		Texts.Delete(temp, 0, temp.len);
		Gadgets.Update(outobj)
	ELSE
		Texts.Append(text, w.buf)
	END
END Append;

(** Char/Date/Int etc. - Write value to buffer, exactly like Texts.WriteX *)

PROCEDURE Char*(x: CHAR);
BEGIN
	Texts.Write(w, x)
END Char;

PROCEDURE Date*(t, d: LONGINT);
BEGIN
	Texts.WriteDate(w, t, d)
END Date;

PROCEDURE Int*(x, n: LONGINT);
BEGIN
	Texts.WriteInt(w, x, n)
END Int;

PROCEDURE IntHex*(x: LONGINT);
BEGIN
	Texts.WriteHex(w, x)
END IntHex;

PROCEDURE Real*(x: REAL;  n: LONGINT);
BEGIN
	Texts.WriteReal(w, x, n)
END Real;

PROCEDURE RealFix*(x: REAL;  n, f, E: LONGINT);
BEGIN
	Texts.WriteRealFix(w, x, n, f, E)
END RealFix;

PROCEDURE RealHex*(x: REAL);
BEGIN
	Texts.WriteRealHex(w, x)
END RealHex;

PROCEDURE LongReal*(x: LONGREAL;  n: LONGINT);
BEGIN
	Texts.WriteLongReal(w, x, n)
END LongReal;

PROCEDURE LongRealFix*(x: LONGREAL;  n, f, E: LONGINT);
BEGIN
	Texts.WriteLongRealFix(w, x, n, f, E)
END LongRealFix;

PROCEDURE LongRealHex*(x: LONGREAL);
BEGIN
	Texts.WriteLongRealHex(w, x)
END LongRealHex;

PROCEDURE Obj*(x: Objects.Object);
BEGIN
	Texts.WriteObj(w, x)
END Obj;

PROCEDURE String*(x: ARRAY OF CHAR);
BEGIN
	Texts.WriteString(w, x)
END String;

(** Ln - End a line of output and do an implicit Append. *)

PROCEDURE Ln*;
BEGIN
	IF text # NIL THEN Texts.WriteLn(w) END;
	Append
END Ln;

BEGIN
	NEW(temp);  Texts.Open(temp, "");  Texts.OpenWriter(w)
END GadgetsOut.
