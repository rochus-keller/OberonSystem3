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

MODULE Files;	(** portable *)  (*NW 11.1.86 / 28.8.92 / pjm 17.04.97 *)

(* Native file system.  Note: InstFiles contains a copy of this module *)

	IMPORT FileDir, Kernel, SYSTEM;

(** The Files module implements the Oberon file system. *)

	(*A file consists of a sequence of pages. The first page
		contains the header. Part of the header is the page table, an array
		of disk addresses to the pages. A file is referenced through riders.
		A rider indicates a current position and refers to a file*)

TYPE
    File* = POINTER TO RECORD END;
		Rider* = RECORD 	(** Riders are the access mechanisms for files. *)
				eof*: BOOLEAN;	(** Rider has reached the end of the file. *)
				res*: LONGINT;	(** Rider operation result code. *)
				file: File;
			END ;
	
		Bytes4 = ARRAY 4 OF BYTE;
		Bytes8 = ARRAY 8 OF BYTE;

		(*aleng * SS + bleng = length (including header)
			apos * SS + bpos = current position
			0 <= bpos <= lim <= SS
			0 <= apos <= aleng < PgTabSize
			(apos < aleng) & (lim = SS) OR (apos = aleng) *)

	PROCEDURE *Cleanup(f: Kernel.PTR);

	END Cleanup;
	
(** Creates a new file with the specified name. *)
	PROCEDURE New*(name: ARRAY OF CHAR): File;

	END New;

(** Open an existing file. The same file descriptor is returned if a file is opened multiple times. *)
	PROCEDURE Old*(name: ARRAY OF CHAR): File;

	END Old;

(** Register a file created with New in the directory, replacing the previous file in the 
directory with the same name. The file is automatically closed. *)
	PROCEDURE Register*(f: File);

	END Register;

(** Flushes the changes made to a file to disk. Register will automatically Close a file. *) 
	PROCEDURE Close*(f: File);

	END Close;


(** Returns the current length of a file. *)
	PROCEDURE Length*(f: File): LONGINT;

	END Length;

(** Returns the time (t) and date (d) when a file was last modified. *)
	PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);

	END GetDate;

(** Sets the modification time (t) and date (d) of a file. *)
	PROCEDURE SetDate*(f: File; t, d: LONGINT);

	END SetDate;

(** Positions a Rider at a certain position in a file. Multiple Riders can be positioned 
at different locations in a file. A Rider cannot be positioned beyond the end of a file. *)
	PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);

	END Set;

(** Returns the offset of a Rider positioned on a file. *)
	PROCEDURE Pos*(VAR r: Rider): LONGINT;

	END Pos;

(** Returns the File a Rider is based on. *)
	PROCEDURE Base*(VAR r: Rider): File;
	BEGIN RETURN r.file
	END Base;

(** Read a byte from a file, advancing the Rider one byte further.  R.eof indicates if the end 
of the file has been passed. *)
	PROCEDURE Read*(VAR r: Rider; VAR x: BYTE);

	END Read;

(** Reads a sequence of length n bytes into the buffer x, advancing the Rider. Less bytes 
will be read when reading over the length of the file. r.res indicates the number of unread bytes. 
x must be big enough to hold n bytes. *)
	PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF BYTE; n: LONGINT);

	END ReadBytes;

(**
Portable routines to read the standard Oberon types.
*)

	PROCEDURE ReadInt*(VAR R: Rider; VAR x: INTEGER);
		VAR x0, x1: SHORTINT;
	BEGIN Read(R, x0); Read(R, x1);
		x := LONG(x1) * 100H + LONG(x0) MOD 100H
	END ReadInt;

	PROCEDURE ReadLInt*(VAR R: Rider; VAR x: LONGINT);
	BEGIN ReadBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END ReadLInt;

	PROCEDURE ReadSet*(VAR R: Rider; VAR x: SET);
	BEGIN ReadBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END ReadSet;

	PROCEDURE ReadBool*(VAR R: Rider; VAR x: BOOLEAN);
		VAR s: SHORTINT;
	BEGIN Read(R, s); x := s # 0
	END ReadBool;

	PROCEDURE ReadReal*(VAR R: Rider; VAR x: REAL);
	BEGIN ReadBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END ReadReal;

	PROCEDURE ReadLReal*(VAR R: Rider; VAR x: LONGREAL);
	BEGIN ReadBytes(R, SYSTEM.VAL(Bytes8, x), 8)
	END ReadLReal;

	PROCEDURE ReadString*(VAR R: Rider; VAR x: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN i := 0;
		LOOP
			Read(R, ch); x[i] := ch; INC(i);
			IF ch = 0X THEN EXIT END;
			IF i = LEN(x) THEN x[i-1] := 0X;
				REPEAT Read(R, ch) UNTIL ch = 0X;
				EXIT
			END
		END
	END ReadString;

(** Reads a number in compressed variable length notation using the minimum amount of bytes. *)
	PROCEDURE ReadNum*(VAR R: Rider; VAR x: LONGINT);
		VAR ch: CHAR; n: INTEGER; y: LONGINT;
	BEGIN n := 0; y := 0; Read(R, ch);
		WHILE ch >= 80X DO INC(y, SYSTEM.LSH(LONG(ORD(ch)) - 128, n)); INC(n, 7); Read(R, ch) END;
		x := ASH(SYSTEM.LSH(LONG(ORD(ch)), 25), n-25) + y
	END ReadNum;

(** Writes a byte into the file at the Rider position, advancing the Rider by one. *)
	PROCEDURE Write*(VAR r: Rider; x: BYTE);

	END Write;

(** Writes the buffer x containing n bytes into a file at the Rider position. *)
	PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF BYTE; n: LONGINT);

	END WriteBytes;

(**
Portable routines to write the standard Oberon types.
*)

	PROCEDURE WriteInt*(VAR R: Rider; x: INTEGER);
	BEGIN Write(R, SHORT(x)); Write(R, SHORT(x DIV 100H))
	END WriteInt;

	PROCEDURE WriteLInt*(VAR R: Rider; x: LONGINT);
	BEGIN WriteBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END WriteLInt;

	PROCEDURE WriteSet*(VAR R: Rider; x: SET);
	BEGIN WriteBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END WriteSet;

	PROCEDURE WriteBool*(VAR R: Rider; x: BOOLEAN);
	BEGIN
		IF x THEN Write(R, 1) ELSE Write(R, 0) END
	END WriteBool;

	PROCEDURE WriteReal*(VAR R: Rider; x: REAL);
	BEGIN WriteBytes(R, SYSTEM.VAL(Bytes4, x), 4)
	END WriteReal;

	PROCEDURE WriteLReal*(VAR R: Rider; x: LONGREAL);
	BEGIN WriteBytes(R, SYSTEM.VAL(Bytes8, x), 8)
	END WriteLReal;

	PROCEDURE WriteString*(VAR R: Rider; x: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN i := 0;
		LOOP ch := x[i]; Write(R, ch); INC(i);
			IF ch = 0X THEN EXIT END;
			IF i = LEN(x) THEN Write(R, 0X); EXIT END
		END
	END WriteString;

(** Writes a number in a compressed format. *)
	PROCEDURE WriteNum*(VAR R: Rider; x: LONGINT);
	BEGIN
		WHILE (x < - 64) OR (x > 63) DO Write(R, CHR(x MOD 128 + 128)); x := x DIV 128 END;
		Write(R, CHR(x MOD 128))
	END WriteNum;

(** Deletes a file. res = 0 indicates success. *)
	PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);

	END Delete;

(** Renames a file. res = 0 indicates success. *)
	PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);

	END Rename;

(** Returns the full name of a file. *)

PROCEDURE GetName*(F: File;  VAR name: ARRAY OF CHAR);
BEGIN
	// name := F.name
END GetName;

BEGIN

END Files.

(** Remarks:

1. Oberon uses the little-endian byte ordering for exchanging files between different Oberon platforms.

2. Files are separate entities from directory entries. Files may be anonymous by having no name and not being registered in a
	directory. Files only become visible to other clients of the Files module by explicitly passing a File descriptor or by registering
	a file and then opening it from the other client. Deleting a file of which a file descriptor is still available, results in the file
	becoming anonymous. The deleted file may be re-registered at any time.

3. Files and their access mechanism (Riders) are separated. A file might have more than one rider operating on it at different
	offsets in the file.

4. The garbage collector will automatically close files when they are not required any more. File buffers will be discarded
	without flushing them to disk.  Use the Close procedure to update modified files on disk.

5. Relative and absolute filenames written in the directory syntax of the host operating system are used. By convention, Oberon
	filenames consists of the letters A..Z, a..z, 0..9, and ".". The directory separator is typically / or :. Oberon filenames are
	case sensitive. *)
