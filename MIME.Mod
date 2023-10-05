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

MODULE MIME; (** portable *)
	IMPORT Streams, TextStreams, Files, Dates, Strings, Fonts, Texts, Display, Display3,
		Objects, Attributes, Gadgets, BasicFigures, Out, Oberon;

	CONST
		BufLen = 1024;
		MaxLine = BufLen-1;
		MaxSMTPLine = 1000;
		MimeVersion* = "Mime-Version: 1.0";
		TextMime* = "text/plain"; ISOVer* = "ISO-8859-1";
		OberonMime* = "application/compressed/oberon";
		EncAuto* = -1; EncBin* = 0; Enc8Bit* = 1; Enc7Bit* = 2; EncQuoted* = 3; EncBase64* = 4; EncAsciiCoder* = 5;
		EncAsciiCoderC* = 6; EncAsciiCoderCPlain* = 7;
		ContEncQuoted* = "Content-Transfer-Encoding: quoted-printable"; (* EncQuoted *)
		ContEnc7Bit* = "Content-Transfer-Encoding: 7bit"; (* Enc7Bit *)
		ContEnc8Bit* = "Content-Transfer-Encoding: 8bit"; (* EncBin, Enc8Bit*)
		ContEncBase64* = "Content-Transfer-Encoding: Base64"; (* EncBase64 *)

	TYPE
		OpenString* = POINTER TO ARRAY OF CHAR;
		Header* = POINTER TO HeaderDesc;
		HeaderDesc* = RECORD
			fields*: OpenString
		END;
	(** A list of the mime content-types supported.
			The mime-types supported by Oberon are described in the "MIME" section of oberon.ini.
			The syntax of a mime entry is:

				mimedef = mime "=" [ suffix [ prefix ] ] .

				mime	The mime type, e.g: "text/html", "image/gif", ...
				suffix	Suffix to be used for temporary files.
				prefix	Prefix to be used for temporary files .
					e.g. "c:/temp/" writes the temporary files in the c:/temp directory *)
		ContentType* = POINTER TO ContentTypeDesc;
		ContentTypeDesc* = RECORD
			typ*: ARRAY 32 OF CHAR;
			subTyp*: ARRAY 64 OF CHAR;
			suffix*: ARRAY 8 OF CHAR;
			prefix*: ARRAY 128 OF CHAR;
			support*: BOOLEAN;
			next: ContentType
		END;
		Content* = POINTER TO ContentDesc;
		ContentDesc* = RECORD
			h: Header;
			pos, len*: LONGINT;
			typ*: ContentType;
			encoding*: LONGINT (* 0: binary; 1: 8 bit; 2: 7 bit; 3: 7 bit, quoted; 4: Base64; 5: AsciiCoder; 6: AsciiCoder % *)
		END;
		Part = POINTER TO PartDesc;
		PartDesc = RECORD
			name: ARRAY 64 OF CHAR;
			no: LONGINT;
			next: Part
		END;

	VAR
		contTypes*: ContentType; (** Root of the content-typ list. *)
		textCont*: Content;

	PROCEDURE ReadHeader*(S, echo: Streams.Stream; VAR h: Header; VAR len: LONGINT);
		VAR
			buf: OpenString;
			bufLen, bufPos, begPos, begLen: LONGINT;
			ch, eolc: CHAR;
			end, eol, field, anyField, white: BOOLEAN;
		PROCEDURE Read();
		BEGIN
			IF (ch # Strings.LF) & (echo # NIL) THEN
				TextStreams.Write(echo, ch)
			END;
			Streams.Read(S, ch); INC(len)
		END Read;
	BEGIN
		len := 0; begLen := 0; anyField := FALSE;
		NEW(h); bufLen := 1024; NEW(h.fields, bufLen); bufPos := 0;
		ch := Strings.LF; Read(); eol := FALSE;
		REPEAT
			end := TRUE; field := FALSE; white := FALSE; begPos := bufPos;
			WHILE ~S.eos & ~eol DO
				IF bufPos >= (bufLen-3) THEN
					h.fields[bufPos] := 0X;
					INC(bufLen, 1024); NEW(buf, bufLen);
					COPY(h.fields^, buf^); h.fields := buf
				END;
IF (ch = ":") & ~field THEN
					end := FALSE; field := ~white; anyField := anyField OR field
				ELSIF ch <= " " THEN
					ch := " "; white := TRUE
				END;
				h.fields[bufPos] := ch; INC(bufPos);
				Read();
				IF (ch = Strings.CR) OR (ch = Strings.LF) THEN
					eolc := ch; Read();
					IF eolc # Strings.LF THEN
						IF ch # Strings.LF THEN
							eolc := Strings.CR
						ELSE
							Read(); eolc := Strings.LF
						END
					END;
					IF ch > " " THEN
						eol := TRUE
					ELSE
						WHILE ~S.eos & (ch <= " ") & (ch # eolc) DO
							Read()
						END;
						eol := ch = eolc;
						IF ~eol THEN
							h.fields[bufPos] := " "; INC(bufPos)						
						END
					END
				ELSE
					eol := FALSE 
				END
			END;
			end := end OR (bufPos <= begPos) OR (ch = Strings.CR) OR (ch = Strings.LF);
			IF field THEN
				begLen := len-1;
				IF S.eos & ~((ch = Strings.CR) OR (ch = Strings.LF)) THEN
					INC(begLen)
				ELSIF ~S.eos THEN
					DEC(begLen)
				END
			END;
			h.fields[bufPos] := 0X; field := FALSE; INC(bufPos);
			eol := FALSE
		UNTIL end;
		len := begLen; h.fields[bufPos] := 0X;
IF ~anyField THEN
	h.fields[0] := 0X; h.fields[1] := 0X
END
	END ReadHeader;

	PROCEDURE FindFieldPos*(h: Header; field: ARRAY OF CHAR; VAR pos: LONGINT);
		VAR len, i: LONGINT;
	BEGIN
		len := LEN(h.fields^);
		WHILE pos < len DO
			i := 0;
			WHILE (pos < len) & (CAP(field[i]) = CAP(h.fields[pos])) & (field[i] # 0X) DO
				INC(i); INC(pos)
			END;
			IF (field[i] = 0X) & ((h.fields[pos] <= " ") OR (h.fields[pos] = ":")) THEN
				WHILE (pos < len) & (h.fields[pos] # ":") & (h.fields[pos] # 0X) DO
					INC(pos)
				END;
				IF h.fields[pos] = ":" THEN
					INC(pos);
					WHILE (pos < len) & (h.fields[pos] <= " ") & (h.fields[pos] # 0X) DO
						INC(pos)
					END
				END;
				RETURN
			ELSE
				WHILE (pos < len) & (h.fields[pos] # 0X) DO
					INC(pos)
				END
			END;
			INC(pos)
		END;
		pos := -1
	END FindFieldPos;

	PROCEDURE FindField*(h: Header; field: ARRAY OF CHAR): LONGINT;
		VAR pos: LONGINT;
	BEGIN
		pos := 0; FindFieldPos(h, field, pos);
		RETURN pos
	END FindField;

	PROCEDURE NextValue*(h: Header; VAR pos: LONGINT);
		VAR len: LONGINT;
	BEGIN
		len := LEN(h.fields^);
		IF (pos < 0) OR (pos >= len) THEN
			RETURN
		END;
		WHILE (pos < len) & (h.fields[pos] # 0X) & (h.fields[pos] # ";") DO
			INC(pos)
		END;
		IF h.fields[pos] = ";" THEN
			INC(pos)
		END;
		WHILE (pos < len) & (h.fields[pos] # 0X) & (h.fields[pos] <= " ") DO
			INC(pos)
		END
	END NextValue;

	PROCEDURE HexVal(ch: CHAR): LONGINT;
	BEGIN
		IF (ch >= "0") & (ch <= "9") THEN
			RETURN ORD(ch)-ORD("0")
		ELSIF (ch >= "A") & (ch <= "F") THEN
			RETURN ORD(ch)-ORD("A")+10
		ELSIF (ch >= "a") & (ch <= "f") THEN
			RETURN ORD(ch)-ORD("a")+10
		END
	END HexVal;

	PROCEDURE DecodeValue(VAR value: ARRAY OF CHAR);
		VAR
			i, j, l: LONGINT;
			quoted: BOOLEAN;
			ch: CHAR;
	BEGIN
		quoted := FALSE;
		i := 0; j := 0; l := LEN(value);
		ch := value[i];
		WHILE ch # 0X DO
			ch := Strings.ISOToOberon[ORD(ch)];
			IF ch = "=" THEN
				IF ~quoted & ((i+14) < l) & (value[i+1] = "?") & (value[i+12] = "?") & (value[i+14] = "?") THEN
					quoted := TRUE; INC(i, 14)
				ELSIF quoted & Strings.IsHexDigit(value[i+1]) & Strings.IsHexDigit(value[i+2]) THEN
					value[j] := Strings.ISOToOberon[HexVal(value[i+1])*16+HexVal(value[i+2])]; INC(j);
					INC(i, 2)
				ELSE
					value[j] := ch; INC(j)
				END
			ELSIF (ch = "?") & quoted & (value[i+1] = "=") THEN
				quoted := FALSE; INC(i)
			ELSE
				value[j] := ch; INC(j)
			END;
			INC(i); ch := value[i]
		END;
		value[j] := 0X
	END DecodeValue;

	PROCEDURE ExtractValue*(h: Header; pos: LONGINT; VAR val: ARRAY OF CHAR);
		VAR len, i, vlen: LONGINT;
	BEGIN
		COPY("", val);
		len := LEN(h.fields^);
		IF (pos < 0) OR (pos >= len) THEN
			RETURN
		END;
		WHILE (pos < len) & (h.fields[pos] # 0X) & (h.fields[pos] <= " ") DO
			INC(pos)
		END;
		vlen := LEN(val)-1; i := 0;
		WHILE (pos < len) & (h.fields[pos] # 0X) & (i < vlen) DO
			val[i] := h.fields[pos]; INC(i); INC(pos)
		END;
		val[i] := 0X; DEC(i);
		WHILE (i > 0) & (val[i] <= " ") DO
			val[i] := 0X; DEC(i)
		END;
		DecodeValue(val)
	END ExtractValue;

	PROCEDURE FindParam*(h: Header; pos: LONGINT; param: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
		VAR len, i, vlen: LONGINT;
	BEGIN
		COPY("", val);
		len := LEN(h.fields^);
		IF (pos < 0) OR (pos >= len) THEN
			RETURN
		END;
		WHILE (pos < len) & (h.fields[pos] # 0X) & (h.fields[pos] <= " ") DO
			INC(pos)
		END;
		vlen := LEN(val)-1;	
		WHILE (pos < len) & (h.fields[pos] # 0X) DO
			i := 0;
			WHILE (pos < len) & (param[i] # 0X) & (CAP(param[i]) = CAP(h.fields[pos])) DO
				INC(i); INC(pos)
			END;
			IF param[i] = 0X THEN
				WHILE (pos < len) & (h.fields[pos] # 0X) & (h.fields[pos] <= " ") DO
					INC(pos)
				END;
				IF h.fields[pos] = "=" THEN
					INC(pos);
					WHILE (pos < len) & (h.fields[pos] # 0X) & (h.fields[pos] <= " ") DO
						INC(pos)
					END;
					IF h.fields[pos] = 022X THEN
						INC(pos)
					END;
					vlen := LEN(val)-1; i := 0;
					WHILE (pos < len) & (h.fields[pos] # 0X) & (h.fields[pos] # 022X) & (h.fields[pos] # ";") & (i < vlen) DO
						val[i] := h.fields[pos]; INC(i); INC(pos)
					END;
					val[i] := 0X; DEC(i);
					WHILE (i > 0) & (val[i] <= " ") DO
						val[i] := 0X; DEC(i)
					END
				END;
				RETURN
			END;
			NextValue(h, pos)
		END
	END FindParam;

	PROCEDURE ExtractEMail*(h: Header; pos: LONGINT; VAR email: ARRAY OF CHAR);
		VAR
			len, i, len2: LONGINT;
			end: CHAR;
	BEGIN
		COPY("", email);
		len := LEN(h.fields^);
		IF (pos < 0) OR (pos >= len) THEN
			RETURN
		END;
		WHILE (pos < len) & (h.fields[pos] # 0X) & (h.fields[pos] # "@") DO
			INC(pos)
		END;
		IF h.fields[pos] = "@" THEN
			WHILE (pos >= 0) & (h.fields[pos] > " ") & (h.fields[pos] # "<") DO
				DEC(pos)
			END;
			IF h.fields[pos] <= " " THEN
				INC(pos)
			END;
			IF h.fields[pos] = "<" THEN
				INC(pos); end := ">"
			ELSE
				end := 0X
			END;
			len2 := LEN(email)-1; i := 0;
			WHILE (i < len2) & (pos < len) & (h.fields[pos] > " ") & (h.fields[pos] # end) DO
				email[i] := h.fields[pos]; INC(i); INC(pos)
			END;
			email[i] := 0X
		END
	END ExtractEMail;

	PROCEDURE StrToMonth(VAR str: ARRAY OF CHAR): LONGINT;
	BEGIN
		CASE CAP(str[0]) OF
			"A": IF (CAP(str[1]) = "P") OR (CAP(str[1]) = "V") THEN (* April, Aprile, Avril *)
						RETURN 4
					ELSE (* August, Agosto, Aout *)
						RETURN 8
					END
			|"D": RETURN 12 (* December, Dezember, Dicembre, Decembre *)
			|"F": RETURN 2 (* February, Febbbraio, Fevrier *)
			|"G": IF CAP(str[1]) = "E" THEN (* Gennaiv *)
						RETURN 1
					ELSE (* Giugno *)
						RETURN 6
					END
			|"J": IF CAP(str[1]) = "A" THEN (* January, Januar, Janvier *)
						RETURN 1
					ELSIF CAP(str[2]) = "L" THEN (* July, Juli, Juillet *)
						RETURN 7
					ELSE (* June, Juni, Juin *)
						RETURN 6
					END
			|"L": RETURN 7 (* Luglio *)
			|"M": IF CAP(str[2]) = "R" THEN (* March, März, Mars *)
						RETURN 3
					ELSIF CAP(str[2]) = "Z" THEN (* Mazzo *)
						RETURN 3
					ELSE (* May, Mai, Maggio *)
						RETURN 5
					END
			|"N": RETURN 11(* November, Novembre *)
			|"O": RETURN 10 (* October, Oktober, Ottobre, Octobre *)
			|"S": RETURN 9 (* September, Seltombre, Septembre *)
		ELSE
		END;
		RETURN 0
	END StrToMonth;

	PROCEDURE GMTTime(h, m, s: LONGINT; zone: ARRAY OF CHAR; VAR time, date: LONGINT): BOOLEAN;
		VAR dH, dM, i: LONGINT;
	BEGIN
		IF (zone[0] = "+") OR (zone[0] = "-") THEN
			Strings.StrToInt(zone, dH);
			IF dH < 0 THEN i := -1 ELSE i := 1 END;
			dM := i*ABS(dH MOD 100);
			dH := i*ABS(dH DIV 100)
		ELSE
			dH := 0; dM := 0;
			Strings.Upper(zone, zone);
			IF (zone = "UT") OR (zone = "GMT") OR (zone = "AM") THEN
				(* nix *)
			ELSIF zone = "EST" THEN
				dH := -5
			ELSIF zone = "EDT" THEN
				dH := -4
			ELSIF zone = "CST" THEN
				dH := -6
			ELSIF zone = "CDT" THEN
				dH := -5
			ELSIF zone = "MST" THEN
				dH := -7
			ELSIF zone = "MDT" THEN
				dH := -6
			ELSIF zone = "PST" THEN
				dH := -8
			ELSIF zone = "PDT" THEN
				dH := -7
			ELSIF zone = "MET" THEN
				dH := +2
			ELSIF (zone[1] <= " ") & (zone[0] >= "A") & (zone[0] <= "Y") & (zone[0] # "J") THEN (* military *)
				IF zone[0] >= "N" THEN
					dH := ORD(zone[0])-ORD("N")+1
				ELSIF zone[0] < "J" THEN
					dH := -(ORD(zone[0])-ORD("A")+1)
				ELSE
					dH := -(ORD(zone[0])-ORD("A"))
				END
			ELSIF zone = "PM" THEN
				dH := +12
			ELSE (* local time *)
				dH := Dates.TimeDiff DIV 60;
				dM := Dates.TimeDiff MOD 60
			END
		END;
		h := h-dH; m := m-dM;
		WHILE m < 0 DO
			DEC(h); INC(m, 60)
		END;
		h := h+(m DIV 60); m := m MOD 60;
		date := Dates.AddDay(date, SHORT(h DIV 24)); h := h MOD 24;
		time := h*1000H + m*40H + s;
		RETURN TRUE
	END GMTTime;

	PROCEDURE GetClock*(VAR time, date: LONGINT);
	BEGIN
		Oberon.GetClock(time, date);
		Dates.AddTime(time, date, -Dates.TimeDiff * 60)	(* convert to GMT *)
	END GetClock;

	PROCEDURE ExtractGMTDate*(h: Header; pos: LONGINT; VAR time, date: LONGINT);
		VAR
			len, i, day, year, month, hour, min, sec: LONGINT;
			mo, zone: ARRAY 16 OF CHAR;
			j: INTEGER;
	BEGIN
		time := 0; date := 0;
		len := LEN(h.fields^);
		IF (pos < 0) OR (pos >= len) THEN
			RETURN
		END;
		i := pos;
		WHILE (i < len) & (h.fields[i] # 0X) & (h.fields[i] # ",") DO
			INC(i)
		END;
		IF h.fields[i] = "," THEN
			pos := i+1
		END;
		(* date *)
		j := SHORT(pos); Strings.StrToIntPos(h.fields^, day, j); pos := j;
		WHILE (pos < len) & (h.fields[pos] # 0X) & (h.fields[pos] <= " ") DO
			INC(pos)
		END;
		i := 0;
		WHILE (pos < len) & (h.fields[pos] > " ") DO
			mo[i] := h.fields[pos]; INC(i); INC(pos)
		END;
		mo[i] := 0X; month := StrToMonth(mo);
		IF (month >= 1) & (month <= 12) THEN
			j := SHORT(pos); Strings.StrToIntPos(h.fields^, year, j);
			IF year >= 100 THEN
				date := (year-1900)*200H + month*20H + day
			ELSE
				date := year*200H + month*20H + day
			END;
			(* time *)
			Strings.StrToIntPos(h.fields^, hour, j);
			WHILE (j < len) & (h.fields[j] # 0X) & (h.fields[j] # ":") DO
				INC(j)
			END;
			IF h.fields[j] = ":" THEN
				INC(j); Strings.StrToIntPos(h.fields^, min, j)
			ELSE
				min := 0
			END;
			WHILE (j < len) & (h.fields[j] # 0X) & (h.fields[j] <= " ") DO
				INC(j)
			END;
			IF h.fields[j] = ":" THEN
				INC(j); Strings.StrToIntPos(h.fields^, sec, j)
			ELSE
				sec := 0
			END;
			WHILE (j < len) & (h.fields[j] # 0X) & (h.fields[j] <= " ") DO
				INC(j)
			END;
			i := 0;
			WHILE (j < len) & (h.fields[j] > " ") DO
				zone[i] := h.fields[j]; INC(i); INC(j)
			END;
			zone[i] := 0X;
			IF GMTTime(hour, min, sec, zone, time, date) THEN
				RETURN
			END
		END;
		GetClock(time, date)
	END ExtractGMTDate;

	PROCEDURE *EnumMIME(key, value: ARRAY OF CHAR);
		VAR
			contType: ContentType;
			i, j: LONGINT;
	BEGIN
		NEW(contType); contType.next := contTypes; contTypes := contType; contType.support := TRUE;
		i := 0;
		WHILE (key[i] # 0X) & (key[i] # "/") DO
			contType.typ[i] := key[i]; INC(i)
		END;
		contType.typ[i] := 0X; Strings.Lower(contType.typ, contType.typ);
		IF key[i] = "/" THEN
			INC(i)
		END;
		j := 0;
		WHILE key[i] # 0X DO
			contType.subTyp[j] := key[i]; INC(j); INC(i)
		END;
		contType.subTyp[j] := 0X; Strings.Lower(contType.subTyp, contType.subTyp);
		i := 0;
		WHILE value[i] > " " DO
			contType.suffix[i] := value[i]; INC(i)
		END;
		contType.suffix[i] := 0X;
		WHILE (value[i] # 0X) & (value[i] <= " ") DO
			INC(i)
		END;
		j := 0;
		WHILE value[i] > " " DO
			contType.prefix[j] := value[i];
			INC(j); INC(i)
		END;
		contType.prefix[j] := 0X;
		WHILE (value[i] # 0X) & (value[i] <= " ") DO
			INC(i)
		END
	END EnumMIME;

(** Find a content-type description. *) 
	PROCEDURE GetContentType*(fullTyp: ARRAY OF CHAR): ContentType;
		VAR
			contType: ContentType;
			typ: ARRAY 32 OF CHAR;
			subTyp: ARRAY 64 OF CHAR;
			i, j: LONGINT;
	BEGIN
		i := 0;
		WHILE (fullTyp[i] # 0X) & (fullTyp[i] # "/") DO
			typ[i] := fullTyp[i]; INC(i)
		END;
		typ[i] := 0X; Strings.Lower(typ, typ);
		IF fullTyp[i] = "/" THEN
			INC(i)
		END;
		j := 0;
		WHILE fullTyp[i] # 0X DO
			subTyp[j] := fullTyp[i]; INC(j); INC(i)
		END;
		subTyp[j] := 0X; Strings.Lower(subTyp, subTyp);
		IF typ = "" THEN
			typ := "text"
		END;
		IF subTyp = "" THEN
			subTyp := "plain"
		END;
		contType := contTypes;
		WHILE (contType # NIL) & ~((contType.typ = typ) & (contType.subTyp = subTyp)) DO
			contType := contType.next
		END;
		IF contType = NIL THEN
			NEW(contType); contType.next := contTypes; contTypes := contType; contType.support := FALSE;
			COPY(typ, contType.typ); COPY(subTyp, contType.subTyp);
			contType.prefix := ""; contType.suffix := ""
		END;
		RETURN contType
	END GetContentType;

	PROCEDURE LoadTypes();
		VAR S: Texts.Scanner; key: ARRAY 64 OF CHAR;
	BEGIN
		contTypes := NIL;
		Oberon.OpenScanner(S, "MIME");
		IF S.class = Texts.Inval THEN
			Out.String("Oberon.Text - MIME not found");  Out.Ln
		END;
		WHILE S.class IN {Texts.Name, Texts.String} DO
			COPY(S.s, key); Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "=") THEN
				Texts.Scan(S);
				IF S.class IN {Texts.Name, Texts.String} THEN
					EnumMIME(key, S.s); Texts.Scan(S)
				END
			ELSE S.class := Texts.Inval
			END
		END;
		NEW(textCont); textCont.typ := GetContentType("text/plain"); textCont.encoding := Enc8Bit
	END LoadTypes;

(** Create a temporary file name for contType. *)
	PROCEDURE MakeTempName*(contType: ContentType; VAR tempName: ARRAY OF CHAR);
	BEGIN
		COPY(contType.prefix, tempName);
		Strings.Append(tempName, "Temp.");
		Strings.Append(tempName, contType.suffix)
	END MakeTempName;

	PROCEDURE ExtractContentType*(h: Header; pos: LONGINT; VAR cont: Content);
		VAR
			len, i: LONGINT;
			fullTyp: ARRAY 32+64 OF CHAR;
	BEGIN
		NEW(cont); cont.typ := GetContentType(TextMime); cont.encoding := EncBin;
		cont.h := h; cont.pos := pos;
		len := LEN(h.fields^);
		IF (pos < 0) OR (pos >= len) THEN
			RETURN
		END;
		WHILE (pos < len) & (h.fields[pos] # 0X) & (h.fields[pos] <= " ") DO
			INC(pos)
		END;
		i := 0;
		WHILE (pos < len) & (h.fields[pos] > " ") & (h.fields[pos] # ";")DO
			fullTyp[i] := h.fields[pos]; INC(i); INC(pos)
		END;
		fullTyp[i] := 0X; cont.typ := GetContentType(fullTyp);
		cont.pos := pos; cont.len := MAX(LONGINT)
	END ExtractContentType;

	PROCEDURE ReadText*(in: Streams.Stream; VAR W: Texts.Writer; cont: Content; mail: BOOLEAN);
		VAR
			buffer: ARRAY BufLen OF CHAR;
			len, rlen, i, offs, maxLen: LONGINT;
			ch, ch1: CHAR;
			iso, quoted: BOOLEAN;
	BEGIN
		iso := cont.encoding IN {Enc8Bit, Enc7Bit, EncQuoted}; quoted := cont.encoding = EncQuoted;
		IF cont.h # NIL THEN
			FindParam(cont.h, cont.pos, "charset", buffer); iso := iso OR (buffer # "")
		END;
		ch := 0X; offs := 0; maxLen := cont.len;
		in.mode := Streams.binary; len := in.Available(in);
		WHILE (maxLen > 0) & ((len > 0) OR (~in.eos & in.buffer)) DO
			IF len > (BufLen-2) THEN
				rlen := BufLen-2
			ELSE
				rlen := len
			END;
			IF rlen > maxLen THEN
				rlen := maxLen
			END;
			in.ReadBytes(in, buffer, rlen); DEC(maxLen, rlen);
			i := 0;
			WHILE i < rlen DO
				IF buffer[i] = Strings.CR THEN
					(* ignore CR *)
				ELSIF buffer[i] = Strings.LF THEN
					Texts.WriteLn(W);
					IF mail & (offs = 1) & (ch = ".") THEN
						RETURN
					END;
					offs := 0
				ELSIF iso THEN
					ch := buffer[i];
					IF ~quoted OR (ch # "=") THEN
						ch := Strings.ISOToOberon[ORD(ch)];
						IF ~mail OR (offs > 0) OR (ch # ".") THEN
							Texts.Write(W, ch)
						END
					ELSE
						INC(i);
						IF i < rlen THEN
							ch := buffer[i]; INC(i)
						ELSE
							Streams.Read(in, ch); INC(rlen); DEC(maxLen)
						END;
						IF i < rlen THEN
							ch1 := buffer[i]
						ELSE
							Streams.Read(in, ch1); INC(rlen); DEC(maxLen)
						END;
						IF Strings.IsHexDigit(ch) & Strings.IsHexDigit(ch1) THEN
							ch := Strings.ISOToOberon[HexVal(ch)*16+HexVal(ch1)];
							Texts.Write(W, ch); ch := 0X
						ELSIF (ch1 = Strings.LF) OR (ch = Strings.LF) THEN
							(* Texts.WriteLn(W); offs := 0 *)
						ELSE
							Texts.Write(W, "=");
							Texts.Write(W, ch); Texts.Write(W, ch1);
							INC(offs, 2); ch := ch1
						END
					END;
					INC(offs)
				ELSE
					ch := buffer[i];
					IF ~mail OR (offs > 0) OR (ch # ".") THEN
						Texts.Write(W, ch)
					END;
					INC(offs)
				END;
				INC(i)
			END;
			DEC(len, rlen);
			IF len <= 0 THEN
				len := in.Available(in)
			END
		END
	END ReadText;

	PROCEDURE SearchBoundary(F: Files.File; VAR boundary: ARRAY OF CHAR; VAR pos: LONGINT): BOOLEAN;
		CONST
			MaxPatLen = 128;
		VAR
			sPat: ARRAY MaxPatLen OF CHAR;
			sDv: ARRAY MaxPatLen + 1 OF LONGINT;
			i, l, sPatLen: LONGINT;
			R: Files.Rider;
			prev, ch: CHAR;
		PROCEDURE CalcDispVec();
			VAR i, j, d: LONGINT;
		BEGIN
			i := 1; d := 1;
			WHILE i <= sPatLen DO
				j := 0; 
				WHILE (j + d < sPatLen) & (sPat[j] = sPat[j + d]) DO
					INC(j)
				END;
				WHILE i <= j + d DO
					sDv[i] := d; INC(i)
				END;
				INC(d)
			END
		END CalcDispVec;
	BEGIN
		COPY(boundary, sPat);
		sPatLen := Strings.Length(sPat);
		CalcDispVec(); prev := 0X;
		IF sPatLen > 0 THEN
			Files.Set(R, F, pos); prev := ch; Files.Read(R, ch);
			INC(pos); l := Files.Length(F); i := 0;
			WHILE (i # sPatLen) & (pos <= l) DO
				IF (i = 0) & (prev >= " ") THEN
					prev := ch; Files.Read(R, ch); INC(pos)
				ELSE
					IF ch = sPat[i] THEN
						INC(i);
						IF i < sPatLen THEN
							prev := ch; Files.Read(R, ch); INC(pos)
						END
					ELSIF i = 0 THEN
						prev := ch; Files.Read(R, ch); INC(pos)
					ELSE
						i := i - sDv[i]
					END
				END
			END
		ELSE
			i := -1
		END;
		RETURN i = sPatLen
	END SearchBoundary;

	PROCEDURE TextEncoding*(h: Header; pos: LONGINT; cont: Content);
		VAR
			val: ARRAY 64 OF CHAR;
			i: LONGINT;
	BEGIN
		ExtractValue(h, pos, val);
		i := 0; Strings.CAPSearch("quoted", val, i);
		IF i >= 0 THEN
			cont.encoding := EncQuoted
		ELSE
			i := 0; Strings.Search("7", val, i);
			IF i > 0 THEN
				cont.encoding := Enc7Bit
			ELSE
				cont.encoding := Enc8Bit
			END
		END;
		cont.len := MAX(LONGINT)
	END TextEncoding;

	PROCEDURE HorzRule(VAR W: Texts.Writer; name: ARRAY OF CHAR);
		VAR f: BasicFigures.Figure;
	BEGIN
		NEW(f); BasicFigures.InitRect3D(f, Display.Width, 2);
		Gadgets.NameObj(f, name);
		Texts.WriteObj(W, f); Texts.WriteLn(W)
	END HorzRule;
	
	PROCEDURE DecodePart(F: Files.File; beg, end: LONGINT; T: Texts.Text; VAR W: Texts.Writer; VAR parts: Part; mail: BOOLEAN);
		VAR
			R: Files.Rider;
			S, wS: Streams.Stream;
			h: Header;
			cont: Content;
			pos, begPart, n, oldBeg: LONGINT;
			val: ARRAY 64 OF CHAR;
			part: Part;
			ch: CHAR;
	BEGIN
		Files.Set(R, F, beg);
		Files.Read(R, ch); INC(beg);
		WHILE (ch <= " ") & (beg <= end) DO
			Files.Read(R, ch); INC(beg)
		END;
		IF ch = "-" THEN
			RETURN
		END;
		NEW(part);
		IF parts = NIL THEN
			part.no := 0
		ELSE
			part.no := parts.no+1
		END;
		part.next := parts; parts := part;
		S := Streams.OpenFileReader(F, beg-1); S.mode := Streams.iso8859; oldBeg := beg-1;
		Texts.Append(T, W.buf);
		wS := TextStreams.OpenWriter(T); begPart := T.len;
		ReadHeader(S, wS, h, n);
		IF (n > 0) & ~((h.fields[0] = 0X) & (h.fields[1] = 0X)) THEN
			wS.Flush(wS); INC(beg, n)
		ELSE
			DEC(beg)
		END;
		pos := FindField(h, "Content-Type"); ExtractContentType(h, pos, cont);
		FindParam(h, pos, "name", part.name);
		Strings.IntToStr(part.no, val); HorzRule(W, val);
		Texts.Insert(T, begPart, W.buf);
		S := Streams.OpenFileReader(F, beg); S.mode := Streams.binary;
		pos := FindField(h, "Content-Disposition");
		IF pos > 0 THEN
			pos := FindField(h, "Content-Transfer-Encoding");
			IF pos > 0 THEN
				ExtractValue(h, pos, val);
				IF Strings.CAPPrefix("Base64", val) THEN
					Texts.WriteString(W, "Base64.Decode ");
					pos := FindField(h, "Content-Disposition");
					FindParam(h, pos, "filename", val);
					IF part.name = "" THEN
						COPY(val, part.name)
					END;
					Texts.WriteString(W, val); Texts.WriteString(W, " ~"); Texts.WriteLn(W);
					Texts.Append(T, W.buf); cont.encoding := EncBase64
				ELSIF cont.typ.typ = "text" THEN
					TextEncoding(h, pos, cont)
				ELSIF Strings.CAPPrefix("Quoted", val) THEN
					Texts.WriteString(W, "QuotedPrintable.DecodeFile ");
					pos := FindField(h, "Content-Disposition");
					FindParam(h, pos, "filename", val);
					IF part.name = "" THEN
						COPY(val, part.name)
					END;
					Texts.WriteString(W, val); Texts.WriteString(W, " ~"); Texts.WriteLn(W);
					Texts.Append(T, W.buf); cont.encoding := EncBin
				ELSE
					cont.encoding := EncBin
				END
			ELSE
				cont.encoding := EncBin
			END
		ELSE
			pos := FindField(h, "Content-Transfer-Encoding");
			TextEncoding(h, pos, cont)
		END;
		IF part.name = "" THEN
			COPY(cont.typ.typ, part.name);
			Strings.AppendCh(part.name, "/");
			Strings.Append(part.name, cont.typ.subTyp)
		END;
		Texts.Insert(T, begPart, W.buf); (*Texts.WriteLn(W);*)
		cont.len := end-beg; ReadText(S, W, cont, mail); (*Texts.WriteLn(W)*)
	END DecodePart;

	PROCEDURE DecodeMultipartFile(F: Files.File; VAR T: Texts.Text; boundary: ARRAY OF CHAR; mail: BOOLEAN);
		VAR
			W: Texts.Writer;
			last, next, parts: Part;
			obj: Objects.Object;
			cmd: ARRAY 64 OF CHAR;
			pos, beg, end, len: LONGINT;
	BEGIN
		NEW(T); Texts.Open(T, ""); Texts.OpenWriter(W);
		pos := 0; end := 0; len := Files.Length(F); parts := NIL;
		IF SearchBoundary(F, boundary, pos) THEN
			WHILE end < len DO
				beg := pos;
				IF SearchBoundary(F, boundary, pos) THEN
					end := pos-Strings.Length(boundary)-2
				ELSE
					end := len+1
				END;
				DecodePart(F, beg, end, T, W, parts, mail)
			END
		END;
		Texts.Append(T, W.buf);
		last := NIL;
		WHILE parts # NIL DO
			next := parts.next; parts.next := last;
			last := parts; parts := next
		END;
		Texts.WriteLn(W);
		parts := last;
		WHILE parts # NIL DO
			Texts.WriteString(W, "[ ");
			Texts.SetColor(W, SHORT(Display3.blue));
			Texts.WriteString(W, parts.name);
			Texts.SetColor(W, SHORT(Display3.textC));
			obj := Gadgets.CreateObject("TextGadgets.NewControl");
			cmd := "HTMLDocs.Locate '";
			Strings.IntToStr(parts.no, boundary);
			Strings.Append(cmd, boundary);
			Attributes.SetString(obj, "Cmd", cmd);
			Texts.WriteObj(W, obj);
			Texts.WriteString(W, " ] ");
			parts := parts.next
		END;
		Texts.WriteLn(W); Texts.WriteLn(W);
		Texts.Insert(T, 0, W.buf)
	END DecodeMultipartFile;

	PROCEDURE ReadMultipartText*(in: Streams.Stream; VAR T: Texts.Text; cont: Content; mail: BOOLEAN);
		VAR
			h: Header;
			F: Files.File;
			R: Files.Rider;
			buffer: ARRAY BufLen OF CHAR;
			boundary: ARRAY 128 OF CHAR;
			len, rlen, i, state, maxLen: LONGINT;
	BEGIN
		maxLen := cont.len; state := 1; h := cont.h;
		F := Files.New(""); Files.Set(R, F, 0);
		in.mode := Streams.binary; len := in.Available(in);
		WHILE (maxLen > 0) & ((len > 0) OR ~in.eos) DO
			IF len > BufLen THEN
				rlen := BufLen
			ELSE
				rlen := len
			END;
			IF rlen > maxLen THEN
				rlen := maxLen
			END;
			in.ReadBytes(in, buffer, rlen); DEC(maxLen, rlen);
			IF mail THEN
				i := 0;
				WHILE (i < rlen) & (state # 2) DO
					IF (buffer[i] = Strings.CR) OR (buffer[i] = Strings.LF) THEN
						state := 1
					ELSIF (state > 0) & (buffer[i] = ".") THEN
						INC(state);
						IF (i < (rlen-1)) & (buffer[i+1] = ".") THEN
							INC(i); INC(state)
						END
					ELSE
						state := 0
					END;
					INC(i)
				END;
				IF state = 2 THEN
					maxLen := 0
				END
			END;
			Files.WriteBytes(R, buffer, rlen);
			len := in.Available(in)
		END;
		FindParam(h, cont.pos, "boundary", buffer);
		boundary := "--"; Strings.Append(boundary, buffer);
		DecodeMultipartFile(F, T, boundary, mail)
	END ReadMultipartText;

	PROCEDURE HexDigit(i: LONGINT): CHAR;
	BEGIN
		IF i < 10 THEN
			RETURN CHR(i+ORD("0"))
		ELSE
			RETURN CHR(i-10+ORD("A"))
		END
	END HexDigit;

	PROCEDURE WriteText*(T: Texts.Text; beg, end: LONGINT; out: Streams.Stream; cont: Content; mail, crlf: BOOLEAN);
		VAR
			buffer: ARRAY BufLen OF CHAR;
			R: Texts.Reader;
			i, j, offs: LONGINT;
			ch: CHAR;
			iso, quoted: BOOLEAN;
	BEGIN
		iso := cont.encoding IN {Enc8Bit, Enc7Bit, EncQuoted}; quoted := cont.encoding = EncQuoted;
		Texts.OpenReader(R, T, beg);
		offs := 0; i := 0; out.mode := Streams.binary;
		Texts.Read(R, ch); INC(beg);
		WHILE ~R.eot & (beg <= end) DO
			IF R.lib IS Fonts.Font THEN
				IF ch = Strings.CR THEN
					out.WriteBytes(out, buffer, i);
					out.WriteBytes(out, Strings.CRLF, 2);
					offs := 0; i := 0
				ELSIF mail & (ch = ".") & (offs = 0) THEN
					IF i > (MaxLine-3) THEN
						out.WriteBytes(out, buffer, i); i := 0
					END;
					buffer[i] := ch; buffer[i+1] := ch; INC(offs, 2); INC(i, 2)
				ELSIF ch # Strings.LF THEN
					IF iso THEN
						ch := Strings.OberonToISO[ORD(ch)];
						IF ~quoted OR ((ch < CHR(128)) & (ch # "=")) THEN
							buffer[i] := ch
						ELSE
							IF i > (MaxLine-3) THEN
								out.WriteBytes(out, buffer, i); i := 0
							END;
							buffer[i] := "=";
							buffer[i+1] := HexDigit((ORD(ch) DIV 16) MOD 16);
							buffer[i+2] := HexDigit(ORD(ch) MOD 16);
							INC(i, 2); INC(offs, 2)
						END
					ELSE
						buffer[i] := ch
					END;
					INC(i);
					IF mail & (offs >= (MaxSMTPLine-5)) THEN
						j := i-1;
						WHILE (j > 0) & (buffer[j] > " ") DO
							DEC(j)
						END;
						IF j > 0 THEN
							INC(j);
							out.WriteBytes(out, buffer, j);
							out.WriteBytes(out, Strings.CRLF, 2);
							IF j < i THEN
								offs := i-j;
								FOR i := j TO offs DO
									out.WriteBytes(out, buffer[i], 1)
								END
							ELSE
								offs := 0
							END
						ELSE
							out.WriteBytes(out, buffer, i);
							out.WriteBytes(out, Strings.CRLF, 2); offs := 0
						END;
						i := 0
					ELSIF i >= MaxLine THEN
						out.WriteBytes(out, buffer, i); i := 0
					END;
					INC(offs)
				END
			END;
			Texts.Read(R, ch); INC(beg)
		END;
		out.WriteBytes(out, buffer, i);
		IF crlf THEN
			out.WriteBytes(out, Strings.CRLF, 2)
		END
	END WriteText;

	PROCEDURE WriteISOMime*(S: Streams.Stream; cont: Content);
	BEGIN
		S.mode := Streams.iso8859;
		TextStreams.WriteString(S, MimeVersion); TextStreams.WriteLn(S);
		TextStreams.WriteString(S, "Content-Type: "); TextStreams.WriteString(S, TextMime);
		TextStreams.WriteString(S, "; charset="); TextStreams.WriteString(S, ISOVer);
		TextStreams.WriteLn(S);
		IF cont.encoding = EncQuoted THEN
			TextStreams.WriteString(S, ContEncQuoted)
		ELSIF cont.encoding = Enc7Bit THEN
			TextStreams.WriteString(S, ContEnc7Bit)
		ELSE
			TextStreams.WriteString(S, ContEnc8Bit)
		END;
		TextStreams.WriteLn(S);
		IF (cont.len > 0) & (cont.len < MAX(LONGINT)) THEN
			TextStreams.WriteString(S, "Content-Length: "); TextStreams.WriteInt(S, cont.len, 0); TextStreams.WriteLn(S)
		END
	END WriteISOMime;

BEGIN
	LoadTypes()
END MIME.
