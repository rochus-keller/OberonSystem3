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

MODULE TGA;	(** portable *)
(*
	JJ 02.03.95	Original Version of Jack Johnson's Targa
	PM 25.10.95	System 3 / DOS/PC-Oberon version
	PM 12.04.96	renamed to PictureTools, added StoreTGA
	IW  22.10.96	changed Interface for PictureConverters, removed StoreTGA
*)

IMPORT Display, Files, Objects, Out, Pictures;

TYPE
	Color = ARRAY 3 OF INTEGER;
	Header = RECORD
		IDlength: CHAR;
		cmap, type: SHORTINT;
		cmaporigin, cmaplength: INTEGER;
		csize: SHORTINT;
		xorigin, yorigin, width, height: INTEGER;
		depth, descriptor: SHORTINT;
	END;			
	
PROCEDURE GetTgaHeader( VAR R: Files.Rider; VAR H: Header): BOOLEAN;
VAR string: ARRAY 256 OF CHAR;
BEGIN
	IF Files.Length(Files.Base(R)) < 18 THEN Out.String("Broken header: file less than 18 bytes long.");
	ELSE
		Files.Read(R, H.IDlength); Files.Read(R, H.cmap); Files.Read(R, H.type);
		Files.ReadInt(R, H.cmaporigin); Files.ReadInt(R, H.cmaplength);
		Files.Read(R, H.csize);
		Files.ReadInt(R, H.xorigin); Files.ReadInt(R, H.yorigin);
		Files.ReadInt(R, H.width); Files.ReadInt(R, H.height);
		Files.Read(R, H.depth); Files.Read( R, H.descriptor);

		IF H.type = 0 THEN Out.String("Type 0: No image data.");
		ELSIF (H.type = 11) OR (H.type = 32) OR (H.type = 33) THEN
			Out.String("Targa type not supported.");
		ELSIF (H.type # 1) & (H.type # 2) & (H.type # 3) & (H.type # 9) & (H.type # 10) THEN
			(*Out.String("Unknown Targa type.");*)
		ELSE
			Out.String("Targa Type "); Out.Int(H.type, 0);
			IF H.cmaplength > 256 THEN Out.String(" Palette size too large; color depth not supported.");
			ELSE
				Out.Int(H.cmaplength - H.cmaporigin, 5);
				Out.String(" colors. ");
				IF ((H.type = 1) OR (H.type = 9)) & (H.csize # 24) THEN Out.String("Bad palette color size.");
				ELSE
					Out.Int(H.width, 0); Out.String(" by "); Out.Int(H.height, 0);
					IF H.depth # 8 THEN Out.String("Unsupported color depth.");
					ELSE
						Out.Int(H.depth, 3);
						Out.String("-bit image depth.");
						Files.ReadBytes( R, string, ORD(H.IDlength));
						string[ ORD(H.IDlength)]:= 0X;
						Out.String(string);  Out.Ln;
						RETURN TRUE
					END
				END
			END
		END
	END;
	Out.Ln();
	RETURN FALSE;
END GetTgaHeader;
		
PROCEDURE DataFieldError;
BEGIN
	Out.String("Broken file in image data field."); Out.Ln();
END DataFieldError;
	
PROCEDURE GetPalette( VAR R: Files.Rider; P: Pictures.Picture; H: Header): BOOLEAN;
VAR
	color: ARRAY 3 OF CHAR;
	count: INTEGER;
BEGIN
	CASE H.type OF
	1, 9:
		count := H.cmaporigin;
		WHILE count < H.cmaplength DO
			Files.ReadBytes(R, color, 3);
			Pictures.SetColor(P, count, ORD(color[2]), ORD(color[1]), ORD(color[0]));
			INC(count)
		END;
		RETURN TRUE
	| 3:
		FOR count := 0 TO 255 DO Pictures.SetColor(P, count, count, count, count) END;
		RETURN TRUE
	ELSE
		Out.String("Really bad error in module Targa");
	END;
	RETURN FALSE;
END GetPalette;

PROCEDURE LoadTga(VAR R: Files.Rider; colorConversion: BOOLEAN; P: Pictures.Picture);
VAR
	H: Header;
	countx, county, count, count2, count3: INTEGER;
	temp, temp2: CHAR;
	error, done, good: BOOLEAN;
	color, hold: Color;
	colora: ARRAY 3 OF CHAR;
	len: LONGINT; f: Files.File;
	pos: LONGINT;
BEGIN
	pos := Files.Pos(R);
	IF GetTgaHeader( R, H) THEN
		Pictures.Create( P, H.width, H.height, H.depth);
		IF (H.type = 1) OR (H.type = 3) OR (H.type = 9) THEN
			IF GetPalette( R, P, H) THEN 
				CASE H.type OF
				1,3:
					FOR county := 0 TO P.height-1 DO
						FOR countx := 0 TO P.width -1 DO
							Files.Read(R, temp);
							Pictures.Dot(P, ORD(temp), countx, county, Display.replace);
						END;
					END;
				| 9:
					countx := 0; county := 0;
					error := FALSE; done := FALSE;
					REPEAT
						Files.Read(R, temp);
						IF R.eof THEN DataFieldError; error := TRUE
						ELSIF ORD(temp) > 127 THEN
							count := 128;
							Files.Read(R, temp2);
							IF R.eof THEN DataFieldError; error := TRUE
							ELSE
								WHILE (count <= ORD(temp) ) & ~R.eof DO
									Pictures.Dot(P, ORD(temp2), countx, county, Display.replace);
									INC(countx);
									IF countx = P.width THEN
										countx := 0;
										INC(county);
										IF county = P.height THEN done := TRUE END
									END;
									INC(count)
								END
							END
						ELSE
							count := 0;
							WHILE (count <= ORD(temp)) & ~R.eof DO
								Files.Read(R, temp2);
								IF R.eof THEN DataFieldError; error := TRUE
								ELSE
									Pictures.Dot(P, ORD(temp2), countx, county, Display.replace);
									INC(countx);
									IF countx = P.width THEN
										countx := 0;
										INC(county);
										IF county = P.height THEN done := TRUE END
									END
								END;
								INC(count)
							END
						END
					UNTIL R.eof OR done;
					IF R.eof THEN
						Out.Int(countx, 0); Out.Ln();
						Out.Int(county, 0); Out.Ln();
						f := Files.New("Error.Pict");
						Pictures.Store(P, f, 0, len);
						Files.Register(f);
					END;
					IF error THEN Out.String("OOPS"); END;
				ELSE Out.String("Really bad error in module Targa");
				END (* CASE *)
			END
		ELSE
			CASE H.type OF
			2:
				error := FALSE;
				count := 0; county := 0;
				WHILE county < P.height DO
					countx := 0;
					WHILE countx < P.width DO
						Files.ReadBytes(R, color, 3);
						color[0] := ORD(colora[0]);
						color[1] := ORD(colora[1]);
						color[2] := ORD(colora[2]);
						count2 := 0;
						good := FALSE;
						REPEAT
							Pictures.GetColor(P, count2, hold[2], hold[1], hold[0]);
							INC(count2);
							IF ((hold[0] = color[0]) & (hold[1] = color[1]) & 
								(hold[2] = color[2])) THEN good := TRUE END
						UNTIL good OR (count = count2);
						IF good THEN Pictures.Dot(P, count2, countx, county, Display.replace)
						ELSE
							INC(count);
							IF count > 256 THEN
								Out.String("Error: Inconsistency bewteen color depth and image data.");
								Out.Ln();
								error := TRUE
							ELSE
								Pictures.SetColor(P, count, color[2], color[1], color[0]);
								Pictures.Dot(P, count, countx, county, Display.replace)
							END
						END;
						INC(countx)
					END;
					INC(county)
				END;
			|10:
				error := FALSE; done := FALSE;
				count := 0; county := 0; countx := 0;
				REPEAT
					Files.Read(R, temp);
					IF R.eof THEN DataFieldError; error := TRUE
					ELSIF ORD(temp) > 127 THEN
						Files.ReadBytes(R, color, 3);
						color[0] := ORD(colora[0]);
						color[1] := ORD(colora[1]);
						color[2] := ORD(colora[2]);
						IF R.eof THEN DataFieldError; error := TRUE
						ELSE
							count2 := 0;
							good := FALSE;
							REPEAT
								Pictures.GetColor(P, count2, hold[2], hold[1], hold[0]);
								INC(count2);
								IF ((hold[0] = color[0]) & (hold[1] = color[1]) & 
									(hold[2] = color[2])) THEN good := TRUE END
							UNTIL good OR (count = count2);
							IF good THEN
								count3 := 128;
								WHILE count3 <= ORD(temp) DO
									Pictures.Dot(P, count2, countx, county, Display.replace);
									INC(count3)
								END;
								INC(countx);
								IF countx = P.width THEN
									countx := 0;
									INC(county);
									IF county = P.height THEN done := TRUE END
								END
							ELSE
								INC(count);
								IF count > 256 THEN
									Out.String("Error: Inconsistency bewteen color depth and image data.");
									error := TRUE
								ELSE
									Pictures.SetColor(P, count, color[2], color[1], color[0]);
									count3 := 128;
									WHILE count3 <= ORD(temp) DO
										Pictures.Dot(P, count, countx, county, Display.replace);
										INC(count3)
									END;
									INC(countx);
									IF countx = P.width THEN
										countx := 0;
										INC(county);
										IF county = P.height THEN done := TRUE END
									END
								END
							END
						END
						ELSE
							count3 := 0;
							WHILE count3 <= ORD(temp) DO
								Files.ReadBytes(R, color, 3);
								color[0] := ORD(colora[0]);
								color[1] := ORD(colora[1]);
								color[2] := ORD(colora[2]);
								IF R.eof THEN DataFieldError; error := TRUE
								ELSE
									count2 := 0;
									good := FALSE;
									REPEAT
										Pictures.GetColor(P, count2, hold[2], hold[1], hold[0]);
										INC(count2);
										IF ((hold[0] = color[0]) & (hold[1] = color[1]) & 
											(hold[2] = color[2])) THEN good := TRUE END
									UNTIL good OR (count = count2);
									IF good THEN
										Pictures.Dot(P, count2, countx, county, Display.replace);
										INC(countx);
										IF countx = P.width THEN
											countx := 0;
											INC(county);
											IF county = P.height THEN done := TRUE END
										END
									ELSE
										INC(count);
										IF count > 256 THEN
											Out.String("Error: Inconsistency bewteen color depth and image data.");
											error := TRUE
										ELSE
											Pictures.SetColor(P, count, color[2], color[1], color[0]);
											Pictures.Dot(P, count, countx, county, Display.replace);
											INC(countx);
											IF countx = P.width THEN
												countx := 0;
												INC(county);
												IF county = P.height THEN done := TRUE END
											END
										END
									END
								END;
							INC(count3)
						END
					END
				UNTIL R.eof OR done;
			ELSE Out.String("Really bad error in module Targa");
			END
		END
	ELSE Files.Set(R, Files.Base(R), pos)
	END;
END LoadTga;

PROCEDURE Handle*(obj: Objects.Object; VAR msg: Objects.ObjMsg);
VAR
	pos: LONGINT;
BEGIN
	WITH obj: Pictures.Picture DO
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO 
				IF (msg.id = Objects.get) & (msg.name = "Gen") THEN 
					msg.class:= Objects.String; COPY("Pictures.NewPicture",msg.s); msg.res:=0 
				END;
			END;
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF (msg.id = Objects.load) THEN
					pos:= Files.Pos(msg.R);
					LoadTga(msg.R,TRUE,obj); msg.len:= Files.Pos(msg.R) - pos;
				ELSE
					Pictures.Handle(obj,msg)
				END;
			END;
		ELSE 
			Pictures.Handle(obj, msg)
		END;
	END;
END Handle;

(** Called from Pictures.Open to try and load an PCX bitmap. The picture descriptor is pre-allocated by Pictures in
Objects.NewObj. InitPicture overwrites the handler of the picture with a new handler that will load the PCX
Picture when a FileMsg is received (variant load). *)
PROCEDURE InitPicture*;
BEGIN
	Objects.NewObj.handle:= Handle;
END InitPicture;
	
PROCEDURE NewPicture*;
VAR
	P: Pictures.Picture;
BEGIN
	NEW(P); P.handle:= Handle; Objects.NewObj:= P;
END NewPicture;
					
END TGA.

Targa file types:

       0  -  No image data included.
       1  -  Uncompressed, color-mapped images.
       2  -  Uncompressed, RGB images.
       3  -  Uncompressed, black and white images.
       9  -  Runlength encoded color-mapped images.
      10  -  Runlength encoded RGB images.
      11  -  Compressed, black and white images.
      32  -  Compressed color-mapped data, using Huffman, Delta, and
                    runlength encoding.
      33  -  Compressed color-mapped data, using Huffman, Delta, and
                    runlength encoding.  4-pass quadtree-type process.
