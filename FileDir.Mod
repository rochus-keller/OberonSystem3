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

MODULE FileDir; (** non-portable *)   (*NW 12.1.86 / 23.8.90 / pjm 09.02.96 *)

  IMPORT P := ObxPal;
  
(* Note: InstFileDir module contains copy of this module *)

(** The FileDir module implements the naming of files in directories. *)

	(*File Directory is a B-tree with its root page at DirRootAdr.
		Each entry contains a file name and the disk address of the file's head sector*)

	CONST FnLength*    = 32;

	TYPE
		FileName*       = ARRAY FnLength OF CHAR;

(* An EntryHandler is used by the Enumerate operation.  name contains the name of the file.
time, date and size are only used if the detail flag was specified in Enumerate.  continue may
be set to FALSE to stop the Enumerate operation mid-way. *)
		EntryHandler* = PROCEDURE (IN name: ARRAY OF CHAR; time, date, size: LONGINT; VAR continue: BOOLEAN);

	VAR
		prefix*: ARRAY 10 OF CHAR;
		PathChar*: CHAR;

	(*Exported procedures: Search, Insert, Delete, Enumerate, Init*)

	PROCEDURE Enumerate*(IN mask: ARRAY OF CHAR; detail: BOOLEAN; proc: EntryHandler);
  VAR n,i,time,date: LONGINT;
	    continue: BOOLEAN;
	    str: ARRAY 64 OF CHAR;
	    data: ARRAY 7 OF LONGINT;
  BEGIN
    continue := TRUE;
    IF mask # "" THEN
      n := P.file_list_masked(mask);
    ELSE
  		n := P.file_list();
  	END;
		FOR i := 0 TO n-1 DO
  		IF detail THEN
  		  str := P.file_list_detail(i,data);
        time := data[4] * 4096 + data[5] * 64 + data[6];
        date := (data[1]-1900) * 512 + data[2] * 32 + data[3];
  		  proc(str,time,date,data[0],continue); 
  		ELSE
  		  str := P.file_list_item(i);
  		  proc(str,0,0,0,continue); 
		  END;
		  IF ~continue THEN RETURN END;
		END
	END Enumerate;

	PROCEDURE Init*;
  // NOP
	END Init;

  PROCEDURE *Cleanup;
  // NOP
  END Cleanup;

BEGIN
END FileDir.
