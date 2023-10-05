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

MODULE Backup;	(** portable, except where noted *) (*JG 20.5.94/pm 16.6.94*)

	IMPORT Diskette, Diskette0, Oberon, Texts, TextFrames;

	VAR W: Texts.Writer; diroption: CHAR;

	PROCEDURE MotorOff(me: Oberon.Task);
	BEGIN
		Diskette0.StopMotor(Diskette.drive);
		Oberon.Remove(me)
	END MotorOff;
	
	PROCEDURE Format*;	(** non-portable *)
      VAR R: Texts.Reader; ch: CHAR; t: Oberon.Task;
	BEGIN
      Texts.WriteString(W, "Backup.Format ");
      Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos); Texts.Read(R, ch);
      IF ch = Oberon.OptionChar THEN Texts.Read(R, ch) ELSE ch := "H" END;
      Texts.Write(W, ch); Texts.Append(Oberon.Log, W.buf);
      NEW(t);  t.safe := FALSE;  t.handle := MotorOff;
      Oberon.Install(t);	(* to switch off motor *)
      Diskette0.FormatDisk(Diskette.drive, ch);
      Diskette.InitOberonVol("OBERON");
      Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END Format;

	PROCEDURE InitOberon*;
      VAR S: Texts.Scanner; i: INTEGER;
	BEGIN
      Texts.WriteString(W, "Backup.InitOberon ");
      Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
      IF (S.line = 0) & ((S.class = Texts.Name) OR (S.class = Texts.String)) THEN
        Texts.WriteString(W, S.s)
      ELSE (*init to old format*) i := 0;
        REPEAT S.s[i] := 0FFX; INC(i) UNTIL i = 11;
        S.s[11] := 8X; S.s[12] := 0X
      END;
      Diskette.InitOberonVol(S.s);
      Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END InitOberon;

	PROCEDURE InitDOS*;
      VAR S: Texts.Scanner;
	BEGIN
      Texts.WriteString(W, "Backup.InitDOS ");
      Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
      IF S.class = Texts.Name THEN Texts.WriteString(W, S.s) ELSE S.s[0] := 0X END;
      Diskette.InitDOSVol(S.s);
      Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END InitDOS;

    PROCEDURE ListEntry (name: ARRAY OF CHAR; date, time: LONGINT; size: LONGINT);
    BEGIN
	    Texts.WriteString(W, name);
        IF diroption = "d" THEN
          Texts.WriteDate(W, time, date); Texts.Write(W, " "); Texts.WriteInt(W, size, 1)
        END;
	    Texts.WriteLn(W)
    END ListEntry;

	PROCEDURE Directory*;
		VAR par: Oberon.ParList; T: Texts.Text; R: Texts.Reader;
          freeEntries, freeSpace: INTEGER; ch: CHAR;
	BEGIN
		par := Oberon.Par;
		Texts.OpenReader(R, par.text, par.pos); Texts.Read(R, ch);
		IF ch = Oberon.OptionChar THEN Texts.Read(R, diroption) ELSE diroption := 0X END;
        Diskette.OpenVol(freeEntries, freeSpace);
        Texts.WriteString(W, "free ");
        Texts.WriteInt(W, freeEntries, 1); Texts.WriteString(W, " entries/ ");
        Texts.WriteInt(W, freeSpace, 1); Texts.WriteString(W, " KB");
        Texts.WriteLn(W);
		Diskette.Enumerate(ListEntry);
        Diskette.CloseVol;
        T := TextFrames.Text("");
		Texts.Append(T, W.buf);
		Oberon.OpenText("Directory", T, 300, 300)
	END Directory;

    PROCEDURE ReadFile (VAR name, oname: ARRAY OF CHAR);
    BEGIN
	    Texts.WriteString(W, name);
	    IF name # oname THEN Texts.WriteString(W, " => ");  Texts.WriteString(W, oname) END;
	    Texts.WriteString(W, " reading");
	    Texts.Append(Oberon.Log, W.buf);
        Diskette.ReadFile(name, oname);
        IF Diskette.res # 0 THEN Texts.WriteString(W, " failed") END;
	    Texts.WriteLn(W);
        Texts.Append(Oberon.Log, W.buf)
    END ReadFile;

	PROCEDURE ScanName(VAR S: Texts.Scanner;  VAR name1, name2: ARRAY OF CHAR);
	VAR ok: BOOLEAN;
	BEGIN
		ASSERT(S.class IN {Texts.Name, Texts.String});
		COPY(S.s, name1);  COPY(S.s, name2);  ok := TRUE;
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "=") THEN
			Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = ">") THEN
				Texts.Scan(S);
				IF S.class IN {Texts.Name, Texts.String} THEN COPY(S.s, name2);  Texts.Scan(S)
				ELSE ok := FALSE
				END
			ELSE ok := FALSE
			END
		END;
		IF ~ok THEN COPY("", name1);  COPY("", name2); S.class := Texts.Inval END
	END ScanName;
	
	PROCEDURE ReadFiles*;
		VAR par: Oberon.ParList; S: Texts.Scanner; T: Texts.Text;
        beg, end, time: LONGINT; freeEntries, freeSpace: INTEGER;
        name, oname: ARRAY 32 OF CHAR;
	BEGIN
		Diskette.OpenVol(freeEntries, freeSpace);
		par := Oberon.Par;
		Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
        WHILE S.class IN {Texts.Name, Texts.String} DO
  	      ScanName(S, name, oname);
  	      IF name # "" THEN ReadFile(name, oname) END
        END;
        IF (S.class = Texts.Char) & (S.c = "^") THEN Oberon.GetSelection(T, beg, end, time);
          IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S);
            IF S.class IN {Texts.Name, Texts.String} THEN
            	ScanName(S, name, oname);
  	     	 IF name # "" THEN ReadFile(name, oname) END
  	      END
          END
        END;
        Diskette.CloseVol
	END ReadFiles;

    PROCEDURE ReadEntry (name: ARRAY OF CHAR; date, time: LONGINT; size: LONGINT);
    BEGIN
        IF size # 0 THEN ReadFile(name, name) END
    END ReadEntry;

	PROCEDURE ReadAll*;
      VAR freeEntries, freeSpace: INTEGER;
	BEGIN
 	   Texts.WriteString(W, "Backup.ReadAll"); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf);
		Diskette.OpenVol(freeEntries, freeSpace);
        Diskette.Enumerate(ReadEntry);
        Diskette.CloseVol
	END ReadAll;

    PROCEDURE WriteFile (VAR oname, name: ARRAY OF CHAR);
    BEGIN
		Texts.WriteString(W, oname);
	    IF name # oname THEN Texts.WriteString(W, " => ");  Texts.WriteString(W, name) END;
		Texts.WriteString(W, " writing");
	    Texts.Append(Oberon.Log, W.buf);
        Diskette.WriteFile(oname, name);
        IF Diskette.res # 0 THEN Texts.WriteString(W, " failed") END;
		Texts.WriteLn(W);
        Texts.Append(Oberon.Log, W.buf)
    END WriteFile;

	PROCEDURE WriteFiles*;
		VAR par: Oberon.ParList; S: Texts.Scanner; T: Texts.Text;
           beg, end, time: LONGINT; freeEntries, freeSpace: INTEGER;
           name, oname: ARRAY 32 OF CHAR;
	BEGIN
		Diskette.OpenVol(freeEntries, freeSpace);
		par := Oberon.Par;
		Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
	    WHILE S.class IN {Texts.Name, Texts.String} DO
  	      ScanName(S, oname, name);
  	      IF name # "" THEN WriteFile(oname, name) END
	    END;
        IF (S.class = Texts.Char) & (S.c = "^") THEN Oberon.GetSelection(T, beg, end, time);
          IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S);
            IF S.class IN {Texts.Name, Texts.String} THEN
              ScanName(S, oname, name);
  	    	IF name # "" THEN WriteFile(oname, name) END
            END
          END
        END;
		Diskette.CloseVol
	END WriteFiles;

    PROCEDURE DeleteFile (VAR name: ARRAY OF CHAR);
    BEGIN
		Texts.WriteString(W, name); Texts.WriteString(W, " deleting");
		Texts.Append(Oberon.Log, W.buf);
		Diskette.DeleteFile(name);
        IF Diskette.res # 0 THEN Texts.WriteString(W, " failed") END;
		Texts.WriteLn(W);
        Texts.Append(Oberon.Log, W.buf)
    END DeleteFile;

	PROCEDURE DeleteFiles*;
		VAR par: Oberon.ParList; T: Texts.Text; S: Texts.Scanner;
          beg, end, time: LONGINT; freeEntries, freeSpace: INTEGER;
          b: ARRAY 512 OF CHAR;
	BEGIN
		Diskette.OpenVol(freeEntries, freeSpace);
		Diskette.GetSectors(0, 1, b, 0);  Diskette.PutSectors(0, 1, b, 0);	(* writable? *)
		par := Oberon.Par;
		Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
		WHILE S.class IN {Texts.Name, Texts.String} DO DeleteFile(S.s); Texts.Scan(S) END;
        IF (S.class = Texts.Char) & (S.c = "^") THEN Oberon.GetSelection(T, beg, end, time);
          IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S);
            IF S.class IN {Texts.Name, Texts.String} THEN DeleteFile(S.s) END
          END
        END;
		Diskette.CloseVol
	END DeleteFiles;

    PROCEDURE SetDriveA*;
    BEGIN Diskette.drive := 0
    END SetDriveA;

    PROCEDURE SetDriveB*;
    BEGIN Diskette.drive := 1
    END SetDriveB;

BEGIN Texts.OpenWriter(W)
END Backup.



