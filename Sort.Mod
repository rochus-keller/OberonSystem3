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

MODULE Sort;	(** portable *)	(*SHML 13.11.91 / mf 13.10.94 / tk adapted for System3 1.6.95*)

	IMPORT Oberon, Texts, Objects, Gadgets, TextGadgets, Documents, Desktops;

	CONST NofLines=4000;

	TYPE
		String=ARRAY 256 OF CHAR;
		Array=POINTER TO ARRAY NofLines OF String;

	VAR W: Texts.Writer;

	PROCEDURE WriteMsg(n: LONGINT; str: ARRAY OF CHAR);
		(*Write number n followed by str followed by a newline to the Log*)
	BEGIN
		Texts.WriteInt(W, n, 0);
		IF n=1 THEN Texts.WriteString(W, " line ")
		ELSE Texts.WriteString(W, " lines ")
		END;
		Texts.WriteString(W, str); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END WriteMsg;

	PROCEDURE HSortArray(array: Array; n: INTEGER);	(*Sort n elements of array in ascending order, HeapSort*)
		VAR left, right: INTEGER; a: String;

		PROCEDURE Sift(left, right: INTEGER);
			VAR i, j: INTEGER; a: String;
		BEGIN	i:=left; j:=2*left; a:=array[left];
			IF (j < right) & (array[j] < array[j+1]) THEN INC(j) END;
			WHILE (j <= right) & (a < array[j]) DO
				array[i]:=array[j]; i:=j; j:=2*j;
				IF (j < right) & (array[j] < array[j+1]) THEN INC(j) END
			END;
			array[i]:=a
		END Sift;
		
	BEGIN	left:=n DIV 2+1; right:=n-1;
		WHILE left > 0 DO DEC(left); Sift(left, right) END;
		WHILE right > 0 DO
			a:=array[0]; array[0]:=array[right]; array[right]:=a;
			DEC(right); Sift(left, right)
		END
	END HSortArray;

	PROCEDURE FillArray(array: Array; VAR n: INTEGER; text: Texts.Text; emptyLines: BOOLEAN);
		(*Fill array with lines from text (including empty lines if requested); return number of lines in n*)
		VAR j: INTEGER; len, pos: LONGINT; R: Texts.Reader; ch: CHAR; white: BOOLEAN;
	BEGIN	len:=text.len; IF len=0 THEN RETURN END;
		Texts.OpenReader(R, text, len-1); Texts.Read(R, ch);
		IF ch # 0DX THEN Texts.Write(W, 0DX); Texts.Append(text, W.buf) END;	(*terminate text with a CR*)
		Texts.OpenReader(R, text, 0);
		n:=0; pos:=0; len:=text.len;
		IF emptyLines THEN	(*include empty lines*)
			REPEAT	j:=0;
				REPEAT Texts.Read(R, ch); array[n, j]:=ch; INC(j) UNTIL ch=0DX;
				array[n, j]:=0X; INC(pos, LONG(j));
				INC(n)
			UNTIL pos=len
		ELSE	(*exclude empty lines*)
			REPEAT	j:=0; white:=TRUE;
				REPEAT	Texts.Read(R, ch);
					IF white & (ch > " ") THEN white:=FALSE END;
					array[n, j]:=ch; INC(j)
				UNTIL ch=0DX;
				array[n, j]:=0X; INC(pos, LONG(j));
				IF ~white THEN INC(n) END	(*keep line if not only white-space*)
			UNTIL pos=len
		END
	END FillArray;
	
	PROCEDURE FillText(text: Texts.Text; array: Array; n: INTEGER; reverse, unique: BOOLEAN);
		(*Fill text with n lines from array; in reverse order if requested*)
		VAR i, j, delta: INTEGER; ch: CHAR; last: String;
	BEGIN
		IF reverse THEN i:=n-1; delta:=-1	ELSE i:=0; delta:=1	END;
		IF unique THEN	last[0]:=0X;
			WHILE n > 0 DO
				IF array[i] # last THEN	last:=array[i];
					ch:=last[0]; j:=0;
					WHILE ch # 0X DO Texts.Write(W, ch); INC(j); ch:=last[j] END;
				END;
				INC(i, delta); DEC(n)
			END
		ELSE
			WHILE n > 0 DO	ch:=array[i, 0]; j:=0;
				WHILE ch # 0X DO Texts.Write(W, ch); INC(j); ch:=array[i, j] END;
				INC(i, delta); DEC(n)
			END
		END;
		Texts.Append(text, W.buf)
	END FillText;
	
	PROCEDURE Sort*;	(**("^" | "*" | <name>) ["/" {c}]	where c IN {"r", "e", "u"}**)
		(**Sort a marked viewer, a selection, or a file. Option /r means in reverse order; /e keep empty lines**)
		VAR S: Texts.Scanner; n: INTEGER; text, sel: Texts.Text; beg, end, time: LONGINT;
			buf: Texts.Buffer; array: Array; reverse, empty, unique: BOOLEAN; TF: TextGadgets.Frame; D: Objects.Object;
	BEGIN	
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF S.class=Texts.Char THEN
			IF S.c="*"  THEN	text:=Oberon.MarkedText()
			ELSIF S.c="^" THEN	Oberon.GetSelection(sel, beg, end, time);
				IF time >= 0 THEN	NEW(buf); Texts.OpenBuf(buf); Texts.Save(sel, beg, end, buf);
					NEW(text); Texts.Open(text, ""); Texts.Append(text, buf)
				END
			END
		ELSIF S.class=Texts.Name THEN NEW(text); Texts.Open(text, S.s)
		END;
		Texts.Scan(S);
		reverse:=FALSE; empty:=FALSE; unique:=FALSE;
		IF (S.class=Texts.Char) & (S.c=Oberon.OptionChar) THEN	Texts.Scan(S);
			IF S.class=Texts.Name THEN
				reverse:=(CAP(S.s[0])="R") OR (CAP(S.s[1])="R") OR (CAP(S.s[2])="R");
				empty:=(CAP(S.s[0])="E") OR (CAP(S.s[1])="E") OR (CAP(S.s[2])="E");
				unique:=(CAP(S.s[0])="U") OR (CAP(S.s[1])="U") OR (CAP(S.s[2])="U");
			END
		END;
		NEW(array);
		FillArray(array, n, text, empty); HSortArray(array, n);
		NEW(text); Texts.Open(text, "");
		FillText(text, array, n, reverse, unique); WriteMsg(n, "sorted.");
		D:=Gadgets.CreateObject("TextDocs.NewDoc");
		IF	D#NIL	THEN
			WITH	D: Documents.Document	DO
				NEW(TF); TextGadgets.Init(TF, text, FALSE); D.W:=300; D.name:="Sorted.Text";
				Documents.Init(D, TF);
				Desktops.ShowDoc(D)
			END
		END;
		array:=NIL;
		Oberon.Collect;
	END Sort;

BEGIN	Texts.OpenWriter(W)
END Sort.