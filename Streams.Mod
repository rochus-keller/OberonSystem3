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

MODULE Streams;	(** portable *)
	IMPORT Files;

	CONST
		closed* = 0; error* = 1; in* = 2; out* = 3; inout* = 4;
		binary* = 0; oberon* = 1; iso8859* = 2;

	TYPE
		Stream* = POINTER TO StreamDesc;
		StreamDesc* = RECORD
			ReadBytes*, WriteBytes*: PROCEDURE (S: Stream; VAR x: ARRAY OF BYTE; n: LONGINT);
			Available*: PROCEDURE (S: Stream): LONGINT; (** returns the number of bytes which may read without blocking *)
			State*: PROCEDURE (S: Stream): INTEGER; (** closed, error, in, out, inout *)
			Flush*: PROCEDURE (S: Stream); (** flush all buffers of the stream *)
			Close*: PROCEDURE (S: Stream); (** close the stream *)
			res*: LONGINT; (** bytes requested but not read/written *)
			mode*: INTEGER; (** binary, oberon, iso8859 *)
			eos*, buffer*: BOOLEAN (** set, when either the end of the stream is reached or the stream is closed. *)
		END;
		FileStream* = POINTER TO FileStreamDesc;
		FileStreamDesc = RECORD (StreamDesc)
			R: Files.Rider;
			state: INTEGER;
			ch: CHAR
		END;

	VAR
		NULL*: Stream; (** a stream which does nothing *)

(** on any streams *)

	PROCEDURE Read*(S: Stream; VAR x: CHAR);
	VAR tmp: ARRAY 1 OF BYTE;
	BEGIN
		S.ReadBytes(S, tmp, 1);
		x := CHR(tmp[0])
	END Read;

	PROCEDURE Write*(S: Stream; x: CHAR);
	VAR tmp: ARRAY 1 OF BYTE;
	BEGIN
  	tmp[0] := ORD(x);
		S.WriteBytes(S, tmp, 1)
	END Write;

(** on binary streams *)
(** Portable routines to write and read the standard Oberon types. Each procedure is provided in a read and write pair. *)

	PROCEDURE ReadBool*(S: Stream; VAR x: BOOLEAN);
	VAR tmp: ARRAY 1 OF BYTE;
	BEGIN
		S.ReadBytes(S, tmp, 1);
		x := tmp[0] # 0
	END ReadBool;

	PROCEDURE ReadInt*(S: Stream; VAR x: INTEGER);
	VAR tmp: ARRAY 2 OF BYTE;
	BEGIN
		S.ReadBytes(S, tmp, 2);
		NUMBER(x,tmp)
	END ReadInt;

	PROCEDURE ReadLInt*(S: Stream; VAR x: LONGINT);
	VAR tmp: ARRAY 4 OF BYTE;
	BEGIN
		S.ReadBytes(S, tmp, 4);
		NUMBER(x,tmp)
	END ReadLInt;

	PROCEDURE ReadLReal*(S: Stream; VAR x: LONGREAL);
	VAR tmp: ARRAY 8 OF BYTE;
	BEGIN
		S.ReadBytes(S, tmp, 8);
		NUMBER(x,tmp)
	END ReadLReal;

	PROCEDURE ReadNum*(S: Stream; VAR x: LONGINT);
		VAR
			s, n: LONGINT;
			ch: CHAR;
	BEGIN
		s := 0; n := 0;
		Read(S, ch);
		WHILE ORD(ch) >= 128 DO
			INC(n, ASH(ORD(ch) - 128, s)); INC(s, 7); Read(S, ch)
		END;
		x := n + ASH(ORD(ch) MOD 64 - ORD(ch) DIV 64 * 64, s)
	END ReadNum;

	PROCEDURE ReadReal*(S: Stream; VAR x: REAL);
	VAR tmp: ARRAY 4 OF BYTE;
	BEGIN
		S.ReadBytes(S, tmp, 4);
		NUMBER(x,tmp)
	END ReadReal;

	PROCEDURE ReadSet*(S: Stream; VAR x: SET);
	VAR tmp: ARRAY 4 OF BYTE;
	BEGIN
		S.ReadBytes(S, tmp, 4);
		NUMBER(x,tmp)
	END ReadSet;

	PROCEDURE ReadString*(S: Stream; VAR x: ARRAY OF CHAR);
		VAR
			i: LONGINT;
			ch: CHAR;
	BEGIN
		i := 0;
		REPEAT
			Read(S, ch); x[i] := ch; INC(i)
		UNTIL ch = 0X
	END ReadString;

	PROCEDURE ReadFixString*(S: Stream; VAR x: ARRAY OF CHAR; len: LONGINT);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE i < len DO Read(S,x[i]); INC(i) END;
	END ReadFixString;

	PROCEDURE WriteBool*(S: Stream; x: BOOLEAN);
	VAR ch: CHAR;
	BEGIN
  	ch := 0X;
  	IF x THEN ch := 1X END;
		Write(S, ch)
	END WriteBool;

	PROCEDURE WriteInt*(S: Stream; x: INTEGER);
	VAR tmp: ARRAY 2 OF BYTE;
	BEGIN
  	BYTES(tmp,x);
		S.WriteBytes(S, tmp, 2)
	END WriteInt;

	PROCEDURE WriteLInt*(S: Stream; x: LONGINT);
	VAR tmp: ARRAY 4 OF BYTE;
	BEGIN
  	BYTES(tmp,x);
		S.WriteBytes(S, tmp, 4)
	END WriteLInt;

	PROCEDURE WriteLReal*(S: Stream; x: LONGREAL);
	VAR tmp: ARRAY 8 OF BYTE;
	BEGIN
  	BYTES(tmp,x);
		S.WriteBytes(S, tmp, 8)
	END WriteLReal;

	PROCEDURE WriteNum*(S: Stream; x: LONGINT);
	BEGIN
		WHILE (x < - 64) OR (x > 63) DO
			Write(S, CHR(x MOD 128 + 128)); x := x DIV 128
		END;
		Write(S, CHR(x MOD 128))
	END WriteNum;

	PROCEDURE WriteReal*(S: Stream; x: REAL);
	VAR tmp: ARRAY 4 OF BYTE;
	BEGIN
  	BYTES(tmp,x);
		S.WriteBytes(S, tmp, 4)
	END WriteReal;

	PROCEDURE WriteSet*(S: Stream; x: SET);
	VAR tmp: ARRAY 4 OF BYTE;
	BEGIN
  	BYTES(tmp,x);
		S.WriteBytes(S, tmp, 4)
	END WriteSet;

	PROCEDURE WriteString*(S: Stream; IN x: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE x[i] # 0X DO Write(S,x[i]); INC(i) END;
		Write(S, 0X)
	END WriteString;

	PROCEDURE WriteFixString*(S: Stream; IN x: ARRAY OF CHAR; len: LONGINT);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE i < len DO Write(S,x[i]); INC(i) END;
	END WriteFixString;

	PROCEDURE *NULLReadBytes(S: Stream; VAR x: ARRAY OF BYTE; n: LONGINT);
	BEGIN
	END NULLReadBytes;

	PROCEDURE *NULLWriteBytes(S: Stream; VAR x: ARRAY OF BYTE; n: LONGINT);
	BEGIN
	END NULLWriteBytes;

	PROCEDURE *NULLAvailable(S: Stream): LONGINT;
	BEGIN
		RETURN 0
	END NULLAvailable;

	PROCEDURE *NULLState(S: Stream): INTEGER;
	BEGIN
		RETURN error
	END NULLState;

	PROCEDURE *NULLFlush(S: Stream);
	BEGIN
	END NULLFlush;

	PROCEDURE *NULLClose(S: Stream);
	BEGIN
	END NULLClose;

	PROCEDURE *ReadFileBytes(S: Stream; VAR x: ARRAY OF BYTE; n: LONGINT);
		VAR pos: LONGINT;
	BEGIN
		WITH S: FileStream DO
			pos := 0;
			WHILE ~S.eos & (n > 0) DO
				x[pos] := ORD(S.ch); INC(pos); DEC(n);
				Files.ReadChar(S.R, S.ch); S.eos := S.R.eof
			END;
			S.res := n
		END
	END ReadFileBytes;

	PROCEDURE *WriteFileBytes(S: Stream; VAR x: ARRAY OF BYTE; n: LONGINT);
	BEGIN
		WITH S: FileStream DO
			Files.WriteBytes(S.R, x, n);
			S.eos := FALSE; S.res := 0
		END
	END WriteFileBytes;

	PROCEDURE *FileAvailable(S: Stream): LONGINT;
	BEGIN
		WITH S: FileStream DO
			RETURN Files.Length(Files.Base(S.R)) - Files.Pos(S.R)
		END
	END FileAvailable;

	PROCEDURE *FileState(S: Stream): INTEGER;
	BEGIN
		WITH S: FileStream DO
			RETURN S.state
		END
	END FileState;

	PROCEDURE *FileFlush(S: Stream);
	BEGIN
		WITH S: FileStream DO
			Files.Close(Files.Base(S.R))
		END
	END FileFlush;

	PROCEDURE *FileClose(S: Stream);
	BEGIN
		WITH S: FileStream DO
			S.Flush(S);
			Files.Set(S.R, NIL, 0);
			S.eos := TRUE; S.state := closed
		END
	END FileClose;

(** Opens a stream reading on file F starting at postion pos. *)
	PROCEDURE OpenFileReader*(F: Files.File; pos: LONGINT): Stream;
		VAR S: FileStream;
	BEGIN
		NEW(S); S.mode := binary; S.state := out;
		S.res := 0; Files.Set(S.R, F, pos); S.buffer := FALSE;
		S.ReadBytes := ReadFileBytes; S.eos := Files.Length(F) <= 0;
		Files.ReadChar(S.R, S.ch);
		S.WriteBytes := NULL.WriteBytes;
		S.Available := FileAvailable;
		S.State := FileState;
		S.Flush := FileFlush;
		S.Close := FileClose;
		RETURN S
	END OpenFileReader;

(** Opens a stream writeing on file F starting at postion pos. *)
	PROCEDURE OpenFileWriter*(F: Files.File; pos: LONGINT): Stream;
		VAR S: FileStream;
	BEGIN
		NEW(S); S.mode := binary; S.state := in; S.buffer := FALSE;
		S.res := 0; Files.Set(S.R, F, pos); S.eos := FALSE;
		S.ReadBytes := NULL.ReadBytes; 
		S.WriteBytes := WriteFileBytes;
		S.Available := FileAvailable;
		S.State := FileState;
		S.Flush := FileFlush;
		S.Close := FileClose;
		RETURN S
	END OpenFileWriter;

	PROCEDURE FilePos*(S: FileStream): LONGINT;
	BEGIN
		RETURN Files.Pos(S.R)
	END FilePos;

	PROCEDURE Copy*(src, dest: Stream);
		VAR
			buf: ARRAY 128 OF CHAR;
			len: LONGINT;
	BEGIN
		WHILE ~src.eos DO
			len := src.Available(src);
			IF len > 128 THEN len := 128 END;
			ReadFixString(src, buf, len);
			WriteFixString(dest, buf, len-src.res)
		END;
		dest.Flush(dest)
	END Copy;

BEGIN
	NEW(NULL); NULL.mode := binary; NULL.eos := FALSE; NULL.res := MAX(INTEGER);
	NULL.ReadBytes := NULLReadBytes; NULL.WriteBytes := NULLWriteBytes;
	NULL.Available := NULLAvailable; NULL.State := NULLState;
	NULL.Flush := NULLFlush; NULL.Close := NULLClose; NULL.buffer := FALSE
END Streams.
