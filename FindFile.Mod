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

MODULE FindFile; (** portable *)	(* ejz   *)

(* Native version *)

	IMPORT FileDir, Files, Objects, Strings, Texts, Oberon, Attributes, Links, Gadgets, Documents;

	CONST
		MaxPatLen = 512;

	VAR
		recursive, matchCase, matchWord: BOOLEAN;
		filePat: FileDir.FileName;
		begDate, endDate, minSize, maxSize: LONGINT;
		fileMode: LONGINT;
		sPat: ARRAY MaxPatLen OF CHAR;
		sDv: ARRAY MaxPatLen + 1 OF LONGINT;
		sPatLen: LONGINT;
		W: Texts.Writer;

	PROCEDURE CalcDispVec();
		VAR i, j, d: LONGINT;
	BEGIN
		i := 1; d := 1;
		IF ~matchCase THEN
			Strings.Upper(sPat, sPat)
		END;
		sPatLen := Strings.Length(sPat);
		WHILE i <= sPatLen DO
			j := 0;
			WHILE (j + d < sPatLen) & (sPat[j] = sPat[j + d]) DO INC(j) END;
			WHILE i <= j + d DO sDv[i] := d; INC(i) END;
			INC(d)
		END
	END CalcDispVec;

	PROCEDURE SearchFile(VAR name: ARRAY OF CHAR; F: Files.File);
		VAR
			R: Files.Rider;
			p, l, i: LONGINT;
			ch: CHAR; found: BOOLEAN;
	BEGIN
		l := Files.Length(F);
		p := 0; Files.Set(R, F, 0);
		REPEAT
			Files.Read(R, ch); INC(p);
			i := 0;
			WHILE (i # sPatLen) & (p <= l) DO
				IF (ch = sPat[i]) OR (~matchCase & (Strings.UpperCh(ch) = sPat[i])) THEN
					INC(i); IF i < sPatLen THEN Files.Read(R, ch); INC(p) END
				ELSIF i = 0 THEN Files.Read(R, ch); INC(p)
				ELSE DEC(i, sDv[i])
				END
			END;
			IF i = sPatLen THEN
				IF matchWord THEN
					Files.Read(R, ch); found := (~Strings.IsAlpha(ch) & ~Strings.IsDigit(ch)) OR R.eof;
					IF found & (p > sPatLen) THEN
						Files.Set(R, F, p-sPatLen-1);
						Files.Read(R, ch); found := ~Strings.IsAlpha(ch) & ~Strings.IsDigit(ch)
					END;
					Files.Set(R, F, p)
				ELSE
					found := TRUE
				END;
				IF found THEN
					Texts.WriteString(W, name); Texts.Write(W, 09X); Texts.WriteInt(W, p, 0); Texts.WriteLn(W)
				END
			END
		UNTIL i # sPatLen
	END SearchFile;

	PROCEDURE SearchText(VAR name: ARRAY OF CHAR; F: Files.File; pos: LONGINT);
		VAR
			T: Texts.Text;
			R: Texts.Reader;
			p, l, i: LONGINT;
			ch: CHAR; found: BOOLEAN;
	BEGIN
		NEW(T); Texts.Load(T, F, pos, l); l := T.len;
		p := 0; Texts.OpenReader(R, T, 0);
		REPEAT
			Texts.Read(R, ch); INC(p);
			i := 0;
			WHILE (i # sPatLen) & (p <= l) DO
				IF (ch = sPat[i]) OR (~matchCase & (Strings.UpperCh(ch) = sPat[i])) THEN
					INC(i); IF i < sPatLen THEN Texts.Read(R, ch); INC(p) END
				ELSIF i = 0 THEN Texts.Read(R, ch); INC(p)
				ELSE DEC(i, sDv[i])
				END
			END;
			IF i = sPatLen THEN
				IF matchWord THEN
					Texts.Read(R, ch); found := (~Strings.IsAlpha(ch) & ~Strings.IsDigit(ch)) OR R.eot;
					IF found & (p > sPatLen) THEN
						Texts.OpenReader(R, T, p-sPatLen-1);
						Texts.Read(R, ch); found := ~Strings.IsAlpha(ch) & ~Strings.IsDigit(ch)
					END;
					Texts.OpenReader(R, T, p)
				ELSE
					found := TRUE
				END;
				IF found THEN
					Texts.WriteString(W, name); Texts.Write(W, 09X); Texts.WriteInt(W, p, 0); Texts.WriteLn(W)
				END
			END
		UNTIL i # sPatLen
	END SearchText;

	PROCEDURE SearchInFile(VAR name: ARRAY OF CHAR);
		VAR
			F: Files.File; R: Files.Rider;
			gen: ARRAY 64 OF CHAR;
			len: LONGINT; i: INTEGER; ch: CHAR;
	BEGIN
		IF sPatLen > 0 THEN
			F := Files.Old(name);
			IF fileMode = 2 THEN (* binary *)
				SearchFile(name, F)
			ELSE
				Files.Set(R, F, 0); Files.Read(R, ch);
				IF ch = Texts.TextBlockId THEN (* text *)
					SearchText(name, F, 1)
				ELSE
					Files.Set(R, F, 0); Files.ReadInt(R, i);
					IF i = Documents.Id THEN
						Files.ReadString(R, gen);
						Files.ReadInt(R, i); Files.ReadInt(R, i); Files.ReadInt(R, i); Files.ReadInt(R, i);
						Files.Read(R, ch);
						IF ch = 0F7X THEN
							Files.Read(R, ch);
							IF ch = 08X THEN
								Files.ReadLInt(R, len); Files.Set(R, F, Files.Pos(R) + len); Files.Read(R, ch)
							END
						END;
						IF ch = Texts.TextBlockId THEN (* text *)
							SearchText(name, F, Files.Pos(R));
							RETURN
						END
					END;
					IF fileMode = 0 THEN (* binary *)
						SearchFile(name, F)
					END
				END
			END
		ELSE
			Texts.WriteString(W, name); Texts.WriteLn(W)
		END
	END SearchInFile;

(*
	PROCEDURE *EnumFiles(path, name: ARRAY OF CHAR; time, date, size: LONGINT; isdir: BOOLEAN);
		VAR fullname: FileDir.FileName;
	BEGIN
		COPY(path, fullname); Strings.AppendCh(fullname, FileDir.PathChar); Strings.Append(fullname, name);
		IF ~isdir & (size >= minSize) & (size <= maxSize) & (date >= begDate) & (date <= endDate) THEN
			SearchInFile(fullname)
		ELSIF isdir & recursive THEN
			FileDir.EnumerateFiles(fullname, filePat, TRUE, EnumFiles)
		END
	END EnumFiles;
*)
	PROCEDURE EnumFiles(name: ARRAY OF CHAR;  time, date, size: LONGINT;  VAR continue: BOOLEAN);
	BEGIN
		IF (size >= minSize) & (size <= maxSize) & (date >= begDate) & (date <= endDate) THEN
			SearchInFile(name)
		END
	END EnumFiles;	
	
	PROCEDURE Search*;
		VAR
			obj: Objects.Object;
			path: FileDir.FileName;
			i, j: LONGINT;
			T: Texts.Text;
	BEGIN
		recursive := FALSE; matchCase := FALSE; matchWord := FALSE;
		obj := Gadgets.FindObj(Gadgets.context, "MinSize");
		Attributes.GetString(obj, "Value", path);
		IF path # "" THEN
			Strings.StrToInt(path, minSize)
		ELSE
			minSize := 0
		END;
		obj := Gadgets.FindObj(Gadgets.context, "MaxSize");
		Attributes.GetString(obj, "Value", path);
		IF path # "" THEN
			Strings.StrToInt(path, maxSize)
		ELSE
			maxSize := MAX(LONGINT)
		END;
		obj := Gadgets.FindObj(Gadgets.context, "BegDate");
		Attributes.GetString(obj, "Value", path);
		IF path # "" THEN
			Strings.StrToDate(path, begDate)
		ELSE
			begDate := MIN(LONGINT)
		END;
		obj := Gadgets.FindObj(Gadgets.context, "EndDate");
		Attributes.GetString(obj, "Value", path);
		IF path # "" THEN
			Strings.StrToDate(path, endDate)
		ELSE
			endDate := MAX(LONGINT)
		END;
		obj := Gadgets.FindObj(Gadgets.context, "FileName");
		Attributes.GetString(obj, "Value", path);
		i := 0; j := 0;
		WHILE path[i] # 0X DO
			IF path[i] = FileDir.PathChar THEN
				j := 0;
			ELSE
				filePat[j] := path[i]; INC(j)
			END;
			INC(i)
		END;
		filePat[j] := 0X; path[i-j] := 0X;
		obj := Gadgets.FindObj(Gadgets.context, "PathMode");
		Attributes.GetInt(obj, "Value", i);
		IF i = 2 THEN (* recursive *)
			IF path = "" THEN path := "./" END;
			recursive := TRUE
		ELSIF i = 1 THEN (* seach path *)
			path := ""
		ELSE (* this *)
			IF path = "" THEN path := "./" END
		END;
		obj := Gadgets.FindObj(Gadgets.context, "FileMode");
		Attributes.GetInt(obj, "Value", fileMode);
		obj := Gadgets.FindObj(Gadgets.context, "MatchCase");
		Attributes.GetBool(obj, "Value", matchCase);
		obj := Gadgets.FindObj(Gadgets.context, "MatchWord");
		Attributes.GetBool(obj, "Value", matchWord);
		obj := Gadgets.FindObj(Gadgets.context, "SearchPat");
		Links.GetLink(obj, "Model", obj);
		Attributes.TxtToStr(obj(Texts.Text), sPat);
		CalcDispVec();
		(*FileDir.EnumerateFiles(path, filePat, TRUE, EnumFiles);*)
		FileDir.Enumerate(filePat, TRUE, EnumFiles);
		NEW(T); Texts.Open(T, "");
		Texts.Append(T, W.buf);
		Oberon.OpenText(filePat, T, 512, 512)
	END Search;

BEGIN
	Texts.OpenWriter(W)
END FindFile.

FindFile.Mod  FindFile.Panel
