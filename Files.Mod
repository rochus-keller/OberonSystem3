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

IMPORT P := ObxPal;

(** The Files module implements the Oberon file system. *)

	(*A file consists of a sequence of pages. The first page
		contains the header. Part of the header is the page table, an array
		of disk addresses to the pages. A file is referenced through riders.
		A rider indicates a current position and refers to a file*)

TYPE
    File* = POINTER TO RECORD
            name: ARRAY 32 OF CHAR;
            id, t, d: LONGINT;
            next: File;
           END;
		Rider* = RECORD 	(** Riders are the access mechanisms for files. *)
				eof*: BOOLEAN;	(** Rider has reached the end of the file. *)
				res*, pos: LONGINT;	(** Rider operation result code. *)
				file: File;
			END ;
	
		Bytes4 = ARRAY 4 OF BYTE;
		Bytes8 = ARRAY 8 OF BYTE;
VAR
  root: File;
  
(** Creates a new file with the specified name. *)
	PROCEDURE New*(IN name: ARRAY OF CHAR): File;
	  VAR f: File; id: LONGINT
  BEGIN
    id := P.file_new();
    NEW(f);
    f.name := name;
    f.id := id;
    RETURN f
	END New;

(** Open an existing file. The same file descriptor is returned if a file is opened multiple times. *)
	PROCEDURE Old*(IN name: ARRAY OF CHAR): File;
	  VAR f: File; id: LONGINT;
  BEGIN
    f := root;
    WHILE f # NIL DO
      IF f.name = name THEN RETURN f END;
      f := f.next
    END;
    id := P.file_open(name);
    IF id < 0 THEN RETURN NIL END;
    NEW(f);
    f.name := name;
    f.id := id;
    IF root = NIL THEN root := f ELSE f.next := root; root := f END;
    RETURN f
	END Old;

(** Register a file created with New in the directory, replacing the previous file in the 
directory with the same name. The file is automatically closed. *)
	PROCEDURE Register*(f: File);
	  VAR res: BOOLEAN;
  BEGIN
	  P.file_save(f.name, f.id);
	  Close(f)
	END Register;

(** Flushes the changes made to a file to disk. Register will automatically Close a file. *) 
	PROCEDURE Close*(f: File);
	VAR ff: File;
  BEGIN
    P.file_free(f.id);
    f.id := -1;
    ff := root
    WHILE ff # NIL DO
      IF ff.next = f THEN ff.next := f.next; RETURN END;
      ff := ff.next
    END
	END Close;


(** Returns the current length of a file. *)
	PROCEDURE Length*(f: File): LONGINT;
    RETURN P.file_length(f.id)
	END Length;

(** Returns the time (t) and date (d) when a file was last modified. *)
	PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);
  BEGIN
    t := f.t;
    d := f.d;
	END GetDate;

(** Sets the modification time (t) and date (d) of a file. *)
	PROCEDURE SetDate*(f: File; t, d: LONGINT);
  BEGIN
    f.t := t; f.d := d
	END SetDate;

(** Positions a Rider at a certain position in a file. Multiple Riders can be positioned 
at different locations in a file. A Rider cannot be positioned beyond the end of a file. *)
	PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);
  VAR a, b: INTEGER;
  BEGIN  r.eof := FALSE; r.res := 0;
    IF f # NIL THEN
      r.file := f; r.pos := pos
    ELSE r.file:= NIL
    END
	END Set;

(** Returns the offset of a Rider positioned on a file. *)
	PROCEDURE Pos*(VAR r: Rider): LONGINT;
  BEGIN RETURN r.pos
	END Pos;

(** Returns the File a Rider is based on. *)
	PROCEDURE Base*(VAR r: Rider): File;
	BEGIN RETURN r.file
	END Base;

(** Read a byte from a file, advancing the Rider one byte further.  R.eof indicates if the end 
of the file has been passed. *)
	PROCEDURE Read*(VAR r: Rider; VAR x: BYTE);
	VAR pos: LONGINT;
  BEGIN
    x := 0;
    IF r.file # NIL THEN
      IF P.file_seek(r.file.id, r.pos) # 0 THEN 
	      r.res := 0; r.eof := FALSE;
	      IF P.file_eof(r.file.id) # 0 THEN r.eof := TRUE; r.res := 1
	      ELSE
	        x := P.file_read_byte(r.file.id)
	        pos := P.file_pos(r.file.id)
	        IF pos = r.pos THEN r.res := 1 ELSE r.pos := pos END
	      END
	    ELSE r.res := 1 
  	  END
    END
	END Read;

(** Reads a sequence of length n bytes into the buffer x, advancing the Rider. Less bytes 
will be read when reading over the length of the file. r.res indicates the number of unread bytes. 
x must be big enough to hold n bytes. *)
	PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF BYTE; n: LONGINT);
  VAR b: BYTE; i: LONGINT;
  BEGIN
    FOR i := 0 TO n-1 DO 
      Read(r,b); x[i] := b; IF r.res # 0 THEN RETURN END 
    END
	END ReadBytes;

	PROCEDURE ReadFixString*(VAR r: Rider; VAR x: ARRAY OF CHAR; n: LONGINT);
  VAR b: BYTE; i: LONGINT;
  BEGIN
    FOR i := 0 TO n-1 DO 
      Read(r,b); x[i] := CHR(b); IF r.res # 0 THEN RETURN END 
    END
	END ReadFixString;

(**
Portable routines to read the standard Oberon types.
*)

	PROCEDURE ReadChar*(VAR R: Rider; VAR x: CHAR);
	VAR b: BYTE;
	BEGIN Read(R, b); x := CHR(b)
	END ReadChar;

	PROCEDURE ReadSInt*(VAR R: Rider; VAR x: SHORTINT);
	VAR b: BYTE;
	BEGIN Read(R, b); x := CAST(SHORTINT,b)
	END ReadSInt;

	PROCEDURE ReadInt*(VAR R: Rider; VAR x: INTEGER);
	VAR x0, x1: SHORTINT;
	BEGIN ReadSInt(R, x0); ReadSInt(R, x1);
		x := LONG(x1) * 100H + LONG(x0) MOD 100H
	END ReadInt;

  PROCEDURE ReadLInt*(VAR r: Rider; VAR x: LONGINT);
  VAR tmp: Bytes4;
  BEGIN
  	ReadBytes(r, tmp, 4);
  	NUMBER(x,tmp);
  END ReadLInt;

  PROCEDURE ReadSet*(VAR r: Rider; VAR x: SET);
  VAR tmp: Bytes4; 
  BEGIN
  	ReadBytes(r, tmp, 4);
  	NUMBER(x,tmp);
  END ReadSet;

	PROCEDURE ReadBool*(VAR R: Rider; VAR x: BOOLEAN);
		VAR b: BYTE;
	BEGIN Read(R, b); x := b # 0
	END ReadBool;

  PROCEDURE ReadReal*(VAR r: Rider; VAR x: REAL);
  VAR tmp: Bytes4;
  BEGIN
  	ReadBytes(r, tmp, 4);
  	NUMBER(x,tmp);
  END ReadReal;
  
  PROCEDURE ReadLReal*(VAR r: Rider; VAR x: LONGREAL);
  VAR tmp: Bytes8;
  BEGIN
  	ReadBytes(r, tmp, 8);
  	NUMBER(x,tmp);
  END ReadLReal;

	PROCEDURE ReadString*(VAR R: Rider; VAR x: ARRAY OF CHAR);
  VAR i: INTEGER; ch: BYTE;
	BEGIN i := 0;
		LOOP
			Read(R, ch); x[i] := CHR(ch); INC(i);
			IF ch = 0 THEN EXIT END;
			IF i = LEN(x) THEN x[i-1] := 0X;
				REPEAT Read(R, ch) UNTIL ch = 0;
				EXIT
			END
		END
	END ReadString;

(** Reads a number in compressed variable length notation using the minimum amount of bytes. *)
	PROCEDURE ReadNum*(VAR R: Rider; VAR x: LONGINT);
		VAR ch: CHAR; n: INTEGER; y: LONGINT;
	BEGIN 
  	n := 0; y := 0; ReadChar(R, ch);
		WHILE ch >= 80X DO 
  		INC(y, LSL(LONG(ORD(ch)) - 128, n)); 
  		INC(n, 7); 
  		ReadChar(R, ch) 
  	END;
    x := ASH(LSL(LONG(ORD(ch)), 25), n-25) + y
	END ReadNum;

(** Writes a byte into the file at the Rider position, advancing the Rider by one. *)
	PROCEDURE Write*(VAR r: Rider; x: BYTE);
  VAR pos: LONGINT
  BEGIN
    IF r.file # NIL THEN
      IF P.file_seek(r.file.id, r.pos) # 0 THEN 
	      r.res := 0; r.eof := FALSE;
	      IF P.file_write_byte(r.file.id,x) # 0 THEN
	        pos := P.file_pos(r.file.id);
	        IF pos = r.pos THEN r.res := r.res + 1 ELSE r.pos := pos END
	      ELSE r.res := r.res + 1
	      END
	   ELSE r.res := r.res + 1 
	   END
    END
	END Write;

(** Writes the buffer x containing n bytes into a file at the Rider position. *)
	PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF BYTE; n: LONGINT);
  VAR i: LONGINT;
  BEGIN i := 0; 
    WHILE i < n DO Write(r, x[i]); INC(i) END
	END WriteBytes;

	PROCEDURE WriteFixString*(VAR r: Rider; VAR x: ARRAY OF CHAR; n: LONGINT);
  VAR i: LONGINT;
  BEGIN i := 0; 
    WHILE i < n DO Write(r, ORD(x[i])); INC(i) END
	END WriteFixString;


(**
Portable routines to write the standard Oberon types.
*)

	PROCEDURE WriteInt*(VAR R: Rider; x: INTEGER);
	BEGIN Write(R, SHORT(x)); Write(R, SHORT(x DIV 100H))
	END WriteInt;

  PROCEDURE WriteLInt*(VAR r: Rider; x: LONGINT);
  VAR tmp:Bytes4;
  BEGIN
    BYTES(tmp,x);
  	WriteBytes(r, tmp, 4)
  END WriteLInt;
  
  PROCEDURE WriteSet*(VAR r: Rider; x: SET);
  VAR tmp:Bytes4;
  BEGIN
    BYTES(tmp, x);
  	WriteBytes(r, tmp, 4)
  END WriteSet;

	PROCEDURE WriteBool*(VAR R: Rider; x: BOOLEAN);
	BEGIN
		IF x THEN Write(R, 1) ELSE Write(R, 0) END
	END WriteBool;

	PROCEDURE WriteChar*(VAR R: Rider; x: CHAR);
	BEGIN
  	Write(R, ORD(x))
	END WriteChar;

  PROCEDURE WriteReal*(VAR r: Rider; x: REAL);
  VAR tmp:Bytes4;
  BEGIN
    BYTES(tmp,x);
  	WriteBytes(r, tmp, 4)
  END WriteReal;
  
  PROCEDURE WriteLReal*(VAR r: Rider; x: LONGREAL);
  VAR tmp:Bytes8;
  BEGIN
    BYTES(tmp,x);
  	WriteBytes(r, tmp, 8)
  END WriteLReal;

	PROCEDURE WriteString*(VAR R: Rider; IN x: ARRAY OF CHAR);
		VAR i: INTEGER; ch: BYTE;
	BEGIN i := 0;
		LOOP ch := ORD(x[i]); Write(R, ch); INC(i);
			IF ch = 0 THEN EXIT END;
			IF i = LEN(x) THEN Write(R, 0); EXIT END
		END
	END WriteString;

(** Writes a number in a compressed format. *)
	PROCEDURE WriteNum*(VAR R: Rider; x: LONGINT);
	BEGIN
		WHILE (x < - 64) OR (x > 63) DO 
  		WriteChar(R, CHR(x MOD 128 + 128)); 
  		x := x DIV 128 
  	END;
		WriteChar(R, CHR(x MOD 128))
	END WriteNum;

(** Deletes a file. res = 0 indicates success. *)
	PROCEDURE Delete*(IN name: ARRAY OF CHAR; VAR res: INTEGER);
	VAR f: File;
	BEGIN
	  IF P.file_remove(name) # 0 THEN 
  	  res := 0 
      f := root;
      WHILE f # NIL DO
        IF f.name = name THEN Close(f); RETURN END;
        f := f.next
      END;
  	ELSE res := 1 
  	END
	END Delete;

(** Renames a file. res = 0 indicates success. *)
	PROCEDURE Rename*(IN old, new: ARRAY OF CHAR; VAR res: INTEGER);
	VAR f: File;
  BEGIN
	  IF P.file_rename(old, new) # 0 THEN 
  	  res := 0 
      f := root;
      WHILE f # NIL DO
        IF f.name = old THEN f.name := new; RETURN END;
        f := f.next
      END;
  	ELSE res := 1 
  	END
	END Rename;

(** Returns the full name of a file. *)

  PROCEDURE GetName*(F: File;  VAR name: ARRAY OF CHAR);
  BEGIN
  	name := F.name
  END GetName;

END Files.

(** Remarks:

1. Oberon uses the little-endian byte ordering for exchanging files between different Oberon platforms.

2. Files are separate entities from directory entries. Files may be anonymous by having no name and not 
  being registered in a
	directory. Files only become visible to other clients of the Files module by explicitly passing a File 
	descriptor or by registering
	a file and then opening it from the other client. Deleting a file of which a file descriptor is still 
	available, results in the file
	becoming anonymous. The deleted file may be re-registered at any time.

3. Files and their access mechanism (Riders) are separated. A file might have more than one rider operating 
  on it at different
	offsets in the file.

4. The garbage collector will automatically close files when they are not required any more. File buffers 
  will be discarded
	without flushing them to disk.  Use the Close procedure to update modified files on disk.

5. Relative and absolute filenames written in the directory syntax of the host operating system are used. By 
  convention, Oberon
	filenames consists of the letters A..Z, a..z, 0..9, and ".". The directory separator is typically / or :. 
	Oberon filenames are
	case sensitive. *)
