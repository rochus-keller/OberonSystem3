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

MODULE DBF; (* ejz   *)
	IMPORT Files, Dates, Strings;

	(** Read dBASE III data files. *)

	CONST
		Done* = 0; CorruptedFile* = 1; OutOfRange* = 2; RecordDeleted* = 3; TypeNotSupported* = 4;
		Character* = ORD("C"); Date* = ORD("D"); Logical* = ORD("L"); Numeric* = ORD("N");

	TYPE
		Field* = POINTER TO FieldDesc;
		FieldDesc* = RECORD
			name*: ARRAY 12 OF CHAR;
			type*: LONGINT; (** Character, Date, Logical, Numeric *)
			address: LONGINT;
			width: LONGINT;
			digits*: LONGINT;
			next*: Field
		END;

		FieldValue* = RECORD
			character*: ARRAY 256 OF CHAR;
			date*: LONGINT;
			logical*: BOOLEAN;
			numeric*: LONGREAL			
		END;

		Reader* = RECORD
			R: Files.Rider;
			firstRecord, thisRecord: LONGINT;
			nRecords*: LONGINT;
			sizeRecord: LONGINT;
			fields*: Field;
			res*: INTEGER (** Done, CorruptedFile, OutOfRange, RecordDeleted *)
		END;

	PROCEDURE ReadDate(VAR R: Reader; VAR date: LONGINT);
		VAR y, m, d: CHAR;
	BEGIN
		Files.Read(R.R, y); Files.Read(R.R, m); Files.Read(R.R, d);
		date := Dates.ToDate(ORD(y)+1900, ORD(m), ORD(d))
	END ReadDate;

	PROCEDURE ReadLInt(VAR R: Reader; VAR i: LONGINT);
		VAR ch: CHAR;
	BEGIN
		Files.Read(R.R, ch); i := ORD(ch);
		Files.Read(R.R, ch); i := ASH(ORD(ch), 8) + i;
		Files.Read(R.R, ch); i := ASH(ORD(ch), 16) + i;
		Files.Read(R.R, ch); i := ASH(ORD(ch), 24) + i
	END ReadLInt;

	PROCEDURE ReadInt(VAR R: Reader; VAR i: INTEGER);
		VAR ch: CHAR;
	BEGIN
		Files.Read(R.R, ch); i := ORD(ch);
		Files.Read(R.R, ch); i := 256*ORD(ch) + i
	END ReadInt;

	PROCEDURE Open*(VAR R: Reader; F: Files.File; pos: LONGINT);
		VAR
			field: Field;
			i, nFields, address, width: LONGINT;
			sizeHead, sizeRecord: INTEGER;
			ch: CHAR;
		PROCEDURE Error();
		BEGIN
			R.fields := NIL; R.nRecords := 0; R.res := CorruptedFile
		END Error;
	BEGIN
		R.fields := NIL;
		Files.Set(R.R, F, pos);
		Files.Read(R.R, ch); ReadDate(R, i);
		ReadLInt(R, R.nRecords);
		ReadInt(R, sizeHead); ReadInt(R, sizeRecord);
		IF (ch # 03X) OR (R.nRecords <= 0) OR (sizeHead <= 0) OR (sizeRecord <= 0) THEN
			Error(); RETURN
		END;
		IF ((sizeHead-32-1) MOD 32) # 0 THEN
			Error(); RETURN
		END;
		R.sizeRecord := sizeRecord;
		nFields := (sizeHead-32-1) DIV 32;
		address := 1; width := 0;
		NEW(R.fields); field := R.fields; field.next := NIL; pos := Files.Pos(R.R)+20;
		Files.Set(R.R, F, pos);
		WHILE nFields > 0 DO
			NEW(field.next); field := field.next; field.next := NIL;
			Files.ReadBytes(R.R, field.name, 11);
			Files.Read(R.R, ch); field.type := ORD(ch);
			ReadLInt(R, field.address);
			IF field.address = 0 THEN
				field.address := address+width
			END;
			Files.Read(R.R, ch); field.width := ORD(ch);
			Files.Read(R.R, ch); field.digits := ORD(ch);
			address := field.address; width := field.width;
			pos := Files.Pos(R.R)+14; Files.Set(R.R, F, pos);
			DEC(nFields)
		END;
		R.fields := R.fields.next;
		Files.Read(R.R, ch);
		IF ch # 0DX THEN
			Error()
		ELSE
			R.res := Done
		END;
		R.firstRecord := sizeHead; R.thisRecord := -1
	END Open;

	PROCEDURE Set*(VAR R: Reader; record: LONGINT);
		VAR ch: CHAR;
	BEGIN
		R.thisRecord := -1;
		IF (record >= R.nRecords) OR (record < 0) THEN
 			R.res := OutOfRange; RETURN
 		END;
 		Files.Set(R.R, Files.Base(R.R), R.firstRecord + record*R.sizeRecord);
 		Files.Read(R.R, ch);
 		IF ch = " " THEN
	 		R.thisRecord := Files.Pos(R.R)-1; R.res := Done
	 	ELSIF ch = CHR(27) THEN
	 		R.res := RecordDeleted
	 	ELSE
	 		R.res := CorruptedFile
	 	END
	END Set;

	PROCEDURE ToDate(VAR R: Reader; VAR value: FieldValue);
		VAR y, m, d: INTEGER;
	BEGIN
		d := ORD(value.character[6])-ORD("0");
		d := 10*d+ORD(value.character[7])-ORD("0");
		m := ORD(value.character[4])-ORD("0");
		m := 10*m+ORD(value.character[5])-ORD("0");
		y := ORD(value.character[0])-ORD("0");
		y := 10*y+ORD(value.character[1])-ORD("0");
		y := 10*y+ORD(value.character[2])-ORD("0");
		y := 10*y+ORD(value.character[3])-ORD("0");
		value.date := Dates.ToDate(y, m, d)
	END ToDate;

	PROCEDURE ToLogical(VAR R: Reader; VAR value: FieldValue);
	BEGIN
		IF value.character = "T" THEN
			value.logical := TRUE
		ELSIF value.character = "F" THEN
			value.logical := FALSE
		ELSE
			R.res := CorruptedFile
		END
	END ToLogical;

	PROCEDURE Read*(VAR R: Reader; field: Field; VAR value: FieldValue);
		VAR i: LONGINT;
	BEGIN
		Files.Set(R.R, Files.Base(R.R), R.thisRecord+field.address);
		Files.ReadBytes(R.R, value.character, field.width); value.character[field.width] := 0X;
		R.res := Done;
		CASE field.type OF
			Character: i := field.width-1;
							WHILE (i >= 0) & (value.character[i] <= " ") DO
								value.character[i] := 0X; DEC(i)
							END
			|Date: ToDate(R, value)
			|Logical: ToLogical(R, value)
			|Numeric: Strings.StrToReal(value.character, value.numeric)
		ELSE
			R.res := TypeNotSupported
		END
	END Read;

END DBF.
