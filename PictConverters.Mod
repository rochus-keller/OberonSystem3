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

MODULE PictConverters;	(** portable *) (* rm 1.9.1996, ejz 8.12.96, afi 11.02.1997 *)
	IMPORT Files, Texts, Oberon, Pictures, Documents, GIF, JPEG, XBM, BMP;

	CONST
		dummy = -1;

	TYPE
		CodePages = RECORD
			code, ref: INTEGER
		END;
		CodeBook = ARRAY 4096 OF CodePages;

	VAR
		W: Texts.Writer;
		CB: CodeBook;
		LastBlock: ARRAY 4096 OF INTEGER;

	PROCEDURE WriteScrDesc(VAR R: Files.Rider; P: Pictures.Picture);
		VAR i: LONGINT;
	BEGIN
		Files.WriteInt(R, P.width); Files.WriteInt(R, P.height);
		i := ASH(7+P.depth, 4); i := i+P.depth-1;
		Files.Write(R, CHR(i));
		Files.Write(R, CHR(0));
		Files.Write(R, 0X)
	END WriteScrDesc;

	PROCEDURE WriteColMap(VAR R: Files.Rider; P: Pictures.Picture);
		VAR i, cols, red, green, blue: INTEGER;
	BEGIN
		cols := SHORT(ASH(1, P.depth)); i := 0;
		WHILE i < cols DO
			Pictures.GetColor(P, i, red, green, blue);
			Files.Write(R, CHR(red)); Files.Write(R, CHR(green)); Files.Write(R, CHR(blue));
			INC(i)
		END
	END WriteColMap;

	PROCEDURE WriteGlobal(VAR R: Files.Rider; P: Pictures.Picture);
	BEGIN
		Files.WriteString(R, "GIF89a"); Files.Set(R, Files.Base(R), Files.Pos(R)-1);
		WriteScrDesc(R, P); WriteColMap(R, P)
	END WriteGlobal;

	PROCEDURE WriteImageDesc(VAR R: Files.Rider; P: Pictures.Picture);
	BEGIN
		Files.Write(R, 2CX);
		Files.WriteInt(R, 0); Files.WriteInt(R, 0);
		Files.WriteInt(R, P.width); Files.WriteInt(R, P.height);
		Files.Write(R, CHR(P.depth-1))
	END WriteImageDesc;

	PROCEDURE InitCodeBook(codeLen: INTEGER);
		VAR i, to: INTEGER;
	BEGIN
		i:=0; to:=SHORT(ASH(1, codeLen));
		WHILE i<to DO
			CB[i].code:=i; CB[i].ref:=dummy; LastBlock[i]:=dummy; INC(i)
		END;
		CB[i].code:=dummy; CB[i].ref:=dummy; INC(i);
		CB[i].code:=dummy; CB[i].ref:=dummy
	END InitCodeBook;

	PROCEDURE WriteData(VAR r: Files.Rider; pict: Pictures.Picture);
		CONST byteLen=8;
		VAR 
			last, in, clearCode, endCode, codept, startSize, prefix, bufpos, bitsfree, codelen: INTEGER;
			buffer: ARRAY 256 OF CHAR;
			i2, len: INTEGER;
			page: CodePages;
			dots: POINTER TO ARRAY OF INTEGER;
			x, y, w: INTEGER;
			
		PROCEDURE WriteCode(code: INTEGER);
			VAR temp, bitsleft: INTEGER;
		BEGIN
			bitsleft:=codelen;
			WHILE bitsleft>0 DO
				IF bitsleft<=bitsfree THEN
					temp:=SHORT(ASH(code, byteLen-bitsfree));
					buffer[bufpos]:=CHR(ORD(buffer[bufpos])+temp);
					bitsfree:=bitsfree-bitsleft; bitsleft:=0;
					IF bitsfree=0 THEN INC(bufpos); buffer[bufpos]:=0X; bitsfree:=byteLen END
				ELSE
					temp:=SHORT(ASH(code, byteLen-bitsfree)) MOD 256;
					buffer[bufpos]:=CHR(ORD(buffer[bufpos]) + temp);
					INC(bufpos); buffer[bufpos]:=0X;
					code:=SHORT(ASH(code, -bitsfree));
					bitsleft:=bitsleft-bitsfree; bitsfree:=byteLen
				END;
				IF bufpos=255 THEN
					Files.Write(r, 0FFX); Files.WriteBytes(r, buffer, 255); bufpos:=0;
					buffer[bufpos]:=0X
				END
			END	
		END WriteCode;
	
	BEGIN
		codelen:=pict.depth; IF codelen<2 THEN codelen:=2 END;
		Files.Write(r, CHR(codelen));
		clearCode:=SHORT(ASH(1, codelen)); endCode:=clearCode+1;
		codept:=endCode+1; LastBlock[codept]:=dummy;
		
		startSize:=codelen;
		InitCodeBook(codelen); INC(codelen);
		x:=0; y:=pict.height-1; w:=pict.width; NEW(dots, w);
		Pictures.GetLine(pict, dots^, x, y, w);
		prefix:=dots[0]; INC(x); bufpos:=0; buffer[0]:=0X; bitsfree:=8;
		len:=SHORT(ASH(1, codelen));
		
		WriteCode(clearCode);
		LOOP
				in:=dots[x]; i2:=LastBlock[prefix];
				IF i2#dummy THEN
					page:=CB[i2];
					WHILE (page.ref#dummy)&(page.code#in) DO
						i2:=page.ref; page:=CB[page.ref]
					END
				END;
				IF (i2=dummy) OR ((page.ref=dummy)&(page.code#in)) THEN
					WriteCode(prefix);				
					IF codept=len THEN
						INC(codelen); len:=SHORT(ASH(1, codelen))
					END;
					IF codept>=4095 THEN
							WriteCode(clearCode);
							codelen:=startSize; InitCodeBook(codelen); INC(codelen); len:=SHORT(ASH(1, codelen));
							codept:=endCode+1
					ELSE
						CB[codept].ref:=LastBlock[prefix]; CB[codept].code:=in; LastBlock[prefix]:=codept;
						LastBlock[codept]:=dummy;
						INC(codept)
					END;
					last:=prefix; prefix:=in	
				ELSE last:=prefix; prefix:=i2 
				END;
				INC(x);
				IF x=w THEN
					IF y=0 THEN EXIT END;
					x:=0; DEC(y); Pictures.GetLine(pict, dots^, x, y, w)
				END
		END;
		WriteCode(last); 
		WriteCode(clearCode); codelen:=startSize+1;
		WriteCode(CB[prefix].code); WriteCode(endCode);

		IF bufpos>0 THEN
			IF bitsfree=8 THEN
				Files.Write(r, CHR(bufpos)); Files.WriteBytes(r, buffer, bufpos)
			ELSE
				Files.Write(r, CHR(bufpos+1)); Files.WriteBytes(r, buffer, bufpos+1)
			END
		END;
		Files.Write(r, 0X)
	END WriteData;

(** Store P in gif format in to R. *)
	PROCEDURE Pict2GIF*(P: Pictures.Picture; VAR R: Files.Rider);
	BEGIN
		WriteGlobal(R, P);
		WriteImageDesc(R, P);
		WriteData(R, P);
		Files.Write(R, 3BX)
	END Pict2GIF;

(** PictConverters.PictToGIF { pict => gif }
	Converts oberon picture files into gif pictures. *)
	PROCEDURE PictToGIF*;
		VAR
			S: Texts.Scanner;
			T: Texts.Text;
			beg, end, time: LONGINT;
			Fi, Fo: Files.File;
			R: Files.Rider;
			name: ARRAY 64 OF CHAR;
			P: Pictures.Picture;
			tag: INTEGER;
	BEGIN
		Texts.WriteString(W, "PictConverters.PictToGif"); Texts.WriteLn(W);
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			T := NIL; time := -1;
			Oberon.GetSelection(T, beg, end, time);
			IF (T # NIL) & (time > 0) THEN
				Texts.OpenScanner(S, T, beg); Texts.Scan(S)
			ELSE
				RETURN
			END
		END;
		WHILE ~S.eot & (S.class IN {Texts.Name, Texts.String}) DO
			Texts.WriteString(W, S.s);
			Fi := Files.Old(S.s); Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "=") THEN
				Texts.Scan(S);
				IF (S.class = Texts.Char) & (S.c = ">") THEN
					Texts.Scan(S);
					IF S.class IN {Texts.Name, Texts.String} THEN
						IF Fi # NIL THEN
							Files.Set(R, Fi, 0); Files.ReadInt(R, tag);
							IF tag = Documents.Id THEN
								Files.ReadString(R, name);
								Files.ReadInt(R, tag); Files.ReadInt(R, tag);
								Files.ReadInt(R, tag); Files.ReadInt(R, tag);
								Files.ReadInt(R, tag)
							END;
							IF tag = Pictures.PictFileId THEN
								Texts.WriteString(W, " => "); Texts.WriteString(W, S.s);
								Fo := Files.New(S.s);
								NEW(P); Pictures.Create(P, 0, 0, 8);
								Pictures.Load(P, Fi, Files.Pos(R), time);
								Files.Set(R, Fo, 0); Pict2GIF(P, R);
								Files.Register(Fo)
							ELSE
								Texts.WriteString(W, " not a picture")
							END
						ELSE
							Texts.WriteString(W, " not found")
						END;
						Texts.Scan(S); Texts.WriteLn(W)
					END
				END
			END
		END;
		Texts.Append(Oberon.Log, W.buf)
	END PictToGIF;

(** PictConverters.GIFToPict { gif => pict }
	Converts gif pictures into oberon pictures. *)
	PROCEDURE GIFToPict*;
		VAR
			S: Texts.Scanner;
			T: Texts.Text;
			beg, end, time: LONGINT;
			Fi, Fo: Files.File;
			R: Files.Rider;
			P: Pictures.Picture;
	BEGIN
		Texts.WriteString(W, "PictConverters.GIFToPict"); Texts.WriteLn(W);
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			T := NIL; time := -1;
			Oberon.GetSelection(T, beg, end, time);
			IF (T # NIL) & (time > 0) THEN
				Texts.OpenScanner(S, T, beg); Texts.Scan(S)
			ELSE
				RETURN
			END
		END;
		WHILE ~S.eot & (S.class IN {Texts.Name, Texts.String}) DO
			Texts.WriteString(W, S.s);
			Fi := Files.Old(S.s); Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "=") THEN
				Texts.Scan(S);
				IF (S.class = Texts.Char) & (S.c = ">") THEN
					Texts.Scan(S);
					IF S.class IN {Texts.Name, Texts.String} THEN
						IF Fi # NIL THEN
							IF GIF.CheckFile(Fi) THEN
								Texts.WriteString(W, " => "); Texts.WriteString(W, S.s);
								Files.Set(R, Fi, 0);
								NEW(P); Pictures.Create(P, 0, 0, 8);
								GIF.Load(R, 14, FALSE, P);
								Fo := Files.New(S.s);
								Pictures.Store(P, Fo, 0, time);
								Files.Register(Fo)
							ELSE
								Texts.WriteString(W, " not a gif-file")
							END
						ELSE
							Texts.WriteString(W, " not found")
						END;
						Texts.Scan(S); Texts.WriteLn(W)
					END
				END
			END
		END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END GIFToPict;

(** PictConverters.JPEGToPict { jpeg => pict }
	Converts jpeg pictures into oberon pictures. *)
	PROCEDURE JPEGToPict*;
		VAR
			S: Texts.Scanner;
			T: Texts.Text;
			beg, end, time: LONGINT;
			Fi, Fo: Files.File;
			R: Files.Rider;
			P: Pictures.Picture;
	BEGIN
		Texts.WriteString(W, "PictConverters.JPEGToPict"); Texts.WriteLn(W);
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			T := NIL; time := -1;
			Oberon.GetSelection(T, beg, end, time);
			IF (T # NIL) & (time > 0) THEN
				Texts.OpenScanner(S, T, beg); Texts.Scan(S)
			ELSE
				RETURN
			END
		END;
		WHILE ~S.eot & (S.class IN {Texts.Name, Texts.String}) DO
			Texts.WriteString(W, S.s);
			Fi := Files.Old(S.s); Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "=") THEN
				Texts.Scan(S);
				IF (S.class = Texts.Char) & (S.c = ">") THEN
					Texts.Scan(S);
					IF S.class IN {Texts.Name, Texts.String} THEN
						IF Fi # NIL THEN
							Texts.WriteString(W, " => "); Texts.WriteString(W, S.s);
							Files.Set(R, Fi, 0);
							NEW(P); Pictures.Create(P, 0, 0, 8);
							JPEG.Decode(Fi, P, JPEG.Integer, 1, JPEG.DitherFS, JPEG.ColorsNew);
							Fo := Files.New(S.s);
							Pictures.Store(P, Fo, 0, time);
							Files.Register(Fo)
						ELSE
							Texts.WriteString(W, " not found")
						END;
						Texts.Scan(S); Texts.WriteLn(W)
					END
				END
			END
		END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END JPEGToPict;

(** PictConverters.XBMToPict { xbm => pict }
	Converts xbm pictures into oberon pictures. *)
	PROCEDURE XBMToPict*;
		VAR
			S: Texts.Scanner;
			T: Texts.Text;
			beg, end, time: LONGINT;
			Fi, Fo: Files.File;
			R: Files.Rider;
			P: Pictures.Picture;
	BEGIN
		Texts.WriteString(W, "PictConverters.XBMToPict"); Texts.WriteLn(W);
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			T := NIL; time := -1;
			Oberon.GetSelection(T, beg, end, time);
			IF (T # NIL) & (time > 0) THEN
				Texts.OpenScanner(S, T, beg); Texts.Scan(S)
			ELSE
				RETURN
			END
		END;
		WHILE ~S.eot & (S.class IN {Texts.Name, Texts.String}) DO
			Texts.WriteString(W, S.s);
			Fi := Files.Old(S.s); Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "=") THEN
				Texts.Scan(S);
				IF (S.class = Texts.Char) & (S.c = ">") THEN
					Texts.Scan(S);
					IF S.class IN {Texts.Name, Texts.String} THEN
						IF Fi # NIL THEN
							Texts.WriteString(W, " => "); Texts.WriteString(W, S.s);
							Files.Set(R, Fi, 0);
							NEW(P); Pictures.Create(P, 0, 0, 8);
							XBM.Load(R, P);
							Fo := Files.New(S.s);
							Pictures.Store(P, Fo, 0, time);
							Files.Register(Fo)
						ELSE
							Texts.WriteString(W, " not found")
						END;
						Texts.Scan(S); Texts.WriteLn(W)
					END
				END
			END
		END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END XBMToPict;

(** PictConverters.BMPToPict { bmp => pict }
	Converts bmp pictures into oberon pictures. *)
	PROCEDURE BMPToPict*;
		VAR
			S: Texts.Scanner;
			T: Texts.Text;
			beg, end, time: LONGINT;
			Fi, Fo: Files.File;
			R: Files.Rider;
			P: Pictures.Picture;
	BEGIN
		Texts.WriteString(W, "PictConverters.BMPToPict"); Texts.WriteLn(W);
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			T := NIL; time := -1;
			Oberon.GetSelection(T, beg, end, time);
			IF (T # NIL) & (time > 0) THEN
				Texts.OpenScanner(S, T, beg); Texts.Scan(S)
			ELSE
				RETURN
			END
		END;
		WHILE ~S.eot & (S.class IN {Texts.Name, Texts.String}) DO
			Texts.WriteString(W, S.s);
			Fi := Files.Old(S.s); Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "=") THEN
				Texts.Scan(S);
				IF (S.class = Texts.Char) & (S.c = ">") THEN
					Texts.Scan(S);
					IF S.class IN {Texts.Name, Texts.String} THEN
						IF Fi # NIL THEN
							Files.Set(R, Fi, 0);
							IF BMP.CheckFile(R) THEN
								Texts.WriteString(W, " => "); Texts.WriteString(W, S.s);
								Files.Set(R, Fi, 0);
								NEW(P); Pictures.Create(P, 0, 0, 8);
								BMP.LoadBmp(R, FALSE, P);
								Fo := Files.New(S.s);
								Pictures.Store(P, Fo, 0, time);
								Files.Register(Fo)
							ELSE
								Texts.WriteString(W, " not a gif-file")
							END
						ELSE
							Texts.WriteString(W, " not found")
						END;
						Texts.Scan(S); Texts.WriteLn(W)
					END
				END
			END
		END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END BMPToPict;

(** PictConverters.AnyToPict { any => pict }
	Converts any registered picture format into oberon pictures.
	(See System.Get PictureConverters) *)
	PROCEDURE AnyToPict*;
		VAR
			S: Texts.Scanner;
			T: Texts.Text;
			beg, end, time: LONGINT;
			Fi, Fo: Files.File;
			R: Files.Rider;
			P: Pictures.Picture;
			any: ARRAY 64 OF CHAR;
	BEGIN
		Texts.WriteString(W, "PictConverters.AnyToPict"); Texts.WriteLn(W);
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			T := NIL; time := -1;
			Oberon.GetSelection(T, beg, end, time);
			IF (T # NIL) & (time > 0) THEN
				Texts.OpenScanner(S, T, beg); Texts.Scan(S)
			ELSE
				RETURN
			END
		END;
		WHILE ~S.eot & (S.class IN {Texts.Name, Texts.String}) DO
			Texts.WriteString(W, S.s); COPY(S.s, any);
			Fi := Files.Old(any); Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "=") THEN
				Texts.Scan(S);
				IF (S.class = Texts.Char) & (S.c = ">") THEN
					Texts.Scan(S);
					IF S.class IN {Texts.Name, Texts.String} THEN
						IF Fi # NIL THEN
							Texts.WriteString(W, " => "); Texts.WriteString(W, S.s);
							Files.Set(R, Fi, 0);
							NEW(P); Pictures.Create(P, 0, 0, 8);
							Pictures.Open(P, any, FALSE);
							Fo := Files.New(S.s);
							Pictures.Store(P, Fo, 0, time);
							Files.Register(Fo)
						ELSE
							Texts.WriteString(W, " not found")
						END;
						Texts.Scan(S); Texts.WriteLn(W)
					END
				END
			END
		END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END AnyToPict;

BEGIN
	Texts.OpenWriter(W)
END PictConverters.

PictConverters.PictToGIF Clown.Pict => Clown.gif ~
PictConverters.GIFToPict Clown.gif => ClownG.Pict ~
PictConverters.JPEGToPict Clown.jpg => ClownJ.Pict ~
PictConverters.XBMToPict Clown.xbm => ClownX.Pict ~
PictConverters.BMPToPict Clown.bmp => ClownB.Pict ~
PictConverters.AnyToPict Clown.any => ClownA.Pict ~
