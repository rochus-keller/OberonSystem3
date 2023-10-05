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

MODULE XBM;	(** portable *)
	IMPORT Files, Objects, Display, Display3, Pictures;

(** Load an xbm-image from rider R. *)
	PROCEDURE Load*(VAR R: Files.Rider; pict: Pictures.Picture);
		CONST
			eof = 0;
			equal = 1;
			number = 2;
			lbrak = 3;
			rbrak = 4;
			lbrac = 5;
			rbrac = 6;
			comma = 7;
			define = 8;
			static = 9;
			char = 10;
			id = 11;
			unsigned = 12;
		VAR
			num: LONGINT;
			ident: ARRAY 64 OF CHAR;
			x, y, bits, i, sym: INTEGER;
			error: BOOLEAN;
			ch: CHAR;
		PROCEDURE GetNumber();
			PROCEDURE HexOrd(ch: CHAR): INTEGER;
			BEGIN
				IF (ch >= "0") & (ch <= "9") THEN
					RETURN ORD(ch)-ORD("0")
				ELSIF (ch >= "a") & (ch <= "f") THEN
					RETURN ORD(ch)-ORD("a")+10
				ELSIF (ch >= "A") & (ch <= "F") THEN
					RETURN ORD(ch)-ORD("A")+10
				END
			END HexOrd;
		BEGIN
			num := 0;
			IF ch = "0" THEN
				Files.Read(R, ch)
			END;
			IF CAP(ch) = "X" THEN
				Files.Read(R, ch);
				WHILE ((ch >= "0") & (ch <= "9")) OR ((ch >= "a") & (ch <= "f")) OR ((ch >= "A") & (ch <= "F")) DO
					num := 16*num+HexOrd(ch); Files.Read(R, ch)
				END
			ELSE
				WHILE ((ch >= "0") & (ch <= "9")) DO
					num := 10*num+HexOrd(ch); Files.Read(R, ch)
				END
			END
		END GetNumber;
		PROCEDURE GetIdent();
			VAR i: INTEGER;
		BEGIN
			i := 0;
			WHILE ((ch >= "A") & (ch <= "Z")) OR ((ch >= "a") & (ch <= "z")) OR ((ch >= "0") & (ch <= "9")) OR (ch = "-") OR (ch = "_") OR (ch = ".") DO
				ident[i] := ch; INC(i);
				Files.Read(R, ch)
			END;
			ident[i] := 0X
		END GetIdent;
		PROCEDURE SkipComment();
		BEGIN
			Files.Read(R, ch);
			LOOP
				IF ch = 0X THEN
					error := FALSE;
					EXIT
				ELSIF ch = "*" THEN
					Files.Read(R, ch);
					IF ch = "/" THEN
						Files.Read(R, ch);
						EXIT
					END
				ELSE
					Files.Read(R, ch)
				END
			END
		END SkipComment;
		PROCEDURE Next();
		BEGIN
			WHILE ~R.eof & (ch <= " ") DO
				Files.Read(R, ch)
			END;
			CASE ch OF
				|"=": sym := equal; Files.Read(R, ch)
				|"0" .. "9": sym := number; GetNumber()
				|"[": sym := lbrak; Files.Read(R, ch)
				|"]": sym := rbrak; Files.Read(R, ch)
				|",": sym := comma; Files.Read(R, ch)
				|"{": sym := lbrac; Files.Read(R, ch)
				|"}": sym := rbrac; Files.Read(R, ch)
				|"#": sym := define; Files.Read(R, ch);
						GetIdent();
						IF ident # "define" THEN
							error := TRUE
						END
				|"/": SkipComment(); Next()
				|"A" .. "Z", "a" .. "z": GetIdent();
							IF ident = "static" THEN
								sym := static
							ELSIF ident = "char" THEN
								sym := char
							ELSIF ident = "unsigned" THEN
								sym := unsigned
							ELSE
								sym := id
							END
			ELSE
				sym := eof
			END
		END Next;
		PROCEDURE Check(sy: INTEGER);
		BEGIN
			IF sy = sym THEN
				Next()
			ELSE
				error := TRUE
			END
		END Check;
		PROCEDURE IntDef(VAR i: INTEGER);
		BEGIN
			Check(define); Check(id);
			i := SHORT(num); Check(number)
		END IntDef;
	BEGIN
		error := FALSE; Files.Read(R, ch); Next();
		IntDef(x); IntDef(y);
		IF sym = static THEN
			Next()
		END;
		IF sym = unsigned THEN
			Next()
		END;
		Check(char); Check(id);
		Check(lbrak); Check(rbrak);
		Check(equal); Check(lbrac);
(* "http://dinis.ethz.ch:8080/httpd-internal-icons/" *)
		IF ~error THEN
			Pictures.Create(pict, x, y, 1);
			Pictures.ReplConst(pict, Display3.textbackC, 0, 0, x, y, Display.replace);
			x := 0; y := pict.height-1;
			WHILE ~error & (sym = number) DO
				bits := SHORT(num); i := 0;
				WHILE ~error & (i < 8) & (x < pict.width) DO
					IF (bits MOD 2 ) # 0 THEN
						Pictures.Dot(pict, Display3.textC, x, y, Display.replace)
					END;
					bits := bits DIV 2; INC(x); INC(i)
				END;
				IF x >= pict.width THEN
					x := 0; DEC(y)
				END;
				Next();
				IF sym = comma THEN
					Next()
				END
			END;
			Check(rbrac)
		END;
		IF error THEN
			pict.width := 0; pict.height := 0; pict.depth := 0; pict.address := 0
		END
	END Load;

	PROCEDURE Handle*(obj: Objects.Object; VAR M: Objects.ObjMsg);
		VAR R: Files.Rider;
	BEGIN
		WITH obj: Pictures.Picture DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO 
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String; M.s := "Pictures.NewPicture"; M.res:=0 
					END;
				END;
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					IF M.id = Objects.load THEN
						obj.depth := 0;  R := M.R; Load(M.R, obj);
						IF obj.depth = 0 THEN M.len := 0 ELSE M.len := Files.Pos(M.R) - Files.Pos(R) END
					ELSE
						Pictures.Handle(obj, M)
					END
				END
			ELSE 
				Pictures.Handle(obj, M)
			END
		END
	END Handle;

	PROCEDURE InitPicture*;
	BEGIN
		Objects.NewObj.handle := Handle
	END InitPicture;

(** Called from Pictures.Open to try and load an XBMP picture. The picture descriptor is pre-allocated by Pictures in
Objects.NewObj. InitPicture overwrites the handler of the picture with a new handler that will load the XBM picture
when a FileMsg is received (variant load). *)
	PROCEDURE NewPicture*;
		VAR P: Pictures.Picture;
	BEGIN
		NEW(P);
		P.handle := Handle;
		Objects.NewObj := P
	END NewPicture;

END XBM.
