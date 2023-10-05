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

MODULE Dim3Read;	(** portable *)	(* David Ulrich Nov 95 - März 96 *)
(** This module builds polygon worlds for the 3D Engine from a text description **)

IMPORT
	Math, Oberon, Dim3Engine, Texts;

CONST
	invalid = -1; eot = 0; string = 1; ident = 2; number = 3; lpar = 4; rpar = 5; yes = 6; no = 7;
	shape = 8; end = 9; points = 10; clear = 11; horizon = 12; ambient = 13; light = 14; font = 15; 
	smooth = 16; shading = 17; dither = 18; specular = 19; add = 20; polygon = 21; save = 22; restore = 23; 
	color = 24; specexpo = 25; speccoef = 26; diffuse = 27; translate = 28; rotate = 29; scale = 30; matrix = 31; identity = 32;
	command = 33; texture = 34; transparent = 35; direct = 36; point = 37; constant = 38; gouraud = 39; text = 40;
	
TYPE
	ShapeSym = POINTER TO ShapeSymDesc;
	ShapeSymDesc = RECORD
		name: ARRAY 32 OF CHAR;
		startpos: LONGINT;
		next: ShapeSym;
	END;
	
	Attributes = POINTER TO AttributesDesc;
	AttributesDesc = RECORD
		next: Attributes;
		T: Dim3Engine.Matrix;	(* current transformation matrix *)
		color, fontColor: Dim3Engine.Color;
		diffuse, speccoef: REAL;
		specexpo: INTEGER;
		smooth, dither, gouraud, specular: BOOLEAN;
		font: ARRAY 64 OF CHAR;
	END;


VAR
	S: Texts.Scanner;
	src: Texts.Text;
	sym: INTEGER;
	W: Texts.Writer;
	lastErrPos: LONGINT;
	shapes: ShapeSym;
	cur: Attributes;


(* print error message *)
PROCEDURE Error (msg: ARRAY OF CHAR);
VAR pos: LONGINT;
BEGIN
	pos := Texts.Pos(S);
	IF pos - lastErrPos > 6 THEN
		Texts.WriteInt(W, pos, 4); Texts.WriteString(W, ": "); Texts.WriteString(W, msg);
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END;
	lastErrPos := pos
END Error;


(*--- Push and Pop Attributes ---*)

PROCEDURE Save;
VAR attr: Attributes;
BEGIN
	NEW(attr); attr^ := cur^; attr.next := cur; cur := attr
END Save;

PROCEDURE Restore;
BEGIN
	IF cur.next # NIL THEN
		cur := cur.next 
	ELSE Error("cannot restore (no corresponding 'save')")
	END
END Restore;


(*--- Scanner ---*)

PROCEDURE Get;
VAR R: Texts.Reader; ch: CHAR;
BEGIN
	Texts.Scan(S);
	IF S.eot THEN sym := eot; RETURN END;
	WHILE (S.class = Texts.Char) & (S.c <= " ") DO	(* skip white space *)
		IF S.eot THEN sym := eot; RETURN END;
		Texts.Scan(S)
	END;
	IF (S.class = Texts.Char) & (S.c = "#") THEN	(* skip comment *)
		Texts.OpenReader(R, src, Texts.Pos(S)); Texts.Read(R, ch);
		WHILE ~R.eot & (ch # 0DX) DO Texts.Read(R, ch) END;
		Texts.OpenScanner(S, src, Texts.Pos(R));
		Get; RETURN
	END;
	
	CASE S.class OF
	| Texts.Name:
		sym := ident;
		CASE S.s[0] OF
		| "a": 
			IF S.s = "add" THEN sym := add 
			ELSIF S.s = "ambient" THEN sym := ambient 
			END
		| "c":
			IF S.s = "clear" THEN sym := clear
			ELSIF S.s = "color" THEN sym := color
			ELSIF S.s = "command" THEN sym := command
			ELSIF S.s = "constant" THEN sym := constant
			END
		| "d": IF S.s = "diffuse" THEN sym := diffuse 
			   ELSIF S.s = "direct" THEN sym := direct
			   ELSIF S.s = "dither" THEN sym := dither
			   END
		| "e": IF S.s = "end" THEN sym := end END
		| "f": IF S.s = "font" THEN sym := font END
		| "g": IF S.s = "gouraud" THEN sym := gouraud END
		| "h": IF S.s = "horizon" THEN sym := horizon END
		| "i": IF S.s = "identity" THEN sym := identity END
		| "l": IF S.s = "light" THEN sym := light END
		| "m": IF S.s = "matrix" THEN sym := matrix END
		| "n": IF S.s = "no" THEN sym := no END
		| "p": IF S.s = "points" THEN sym := points 
			ELSIF S.s = "point" THEN sym := point
			ELSIF S.s = "polygon" THEN sym := polygon 
			END
		| "r": IF S.s = "restore" THEN sym := restore ELSIF S.s = "rotate" THEN sym := rotate END
		| "s":
			IF S.s = "save" THEN sym := save
			ELSIF S.s = "scale" THEN sym := scale
			ELSIF S.s = "shading" THEN sym := shading
			ELSIF S.s = "shape" THEN sym := shape
			ELSIF S.s = "smooth" THEN sym := smooth
			ELSIF S.s = "specular" THEN sym := specular
			ELSIF S.s = "specexpo" THEN sym := specexpo
			ELSIF S.s = "speccoef" THEN sym := speccoef
			END
		| "t": 
			IF S.s = "translate" THEN sym := translate
			ELSIF S.s = "transparent" THEN sym := transparent
			ELSIF S.s = "text" THEN sym := text
			ELSIF S.s = "texture" THEN sym := texture
			END
		| "y": IF S.s = "yes" THEN sym := yes END
		ELSE
		END
	| Texts.Int: sym := number; S.x := S.i	(* propagate integers to reals *)
	| Texts.Real: sym := number
	| Texts.Char:
		CASE S.c OF
		| "(": sym := lpar
		| ")": sym := rpar
		ELSE sym := invalid
		END
	| Texts.String: sym := string
	ELSE sym := invalid
	END
END Get;

PROCEDURE Expect (s: INTEGER; msg: ARRAY OF CHAR);
BEGIN
	IF sym = s THEN Get ELSE Error(msg) END
END Expect;

PROCEDURE Number (VAR x: REAL);
BEGIN
	IF sym = number THEN
		x := S.x;
		Get
	ELSE
		x := 0;
		Error("number expected")
	END
END Number;

PROCEDURE Vector (VAR vec: ARRAY OF REAL);
BEGIN
	Expect(lpar, "'(' expected");
	Number(vec[0]);
	Number(vec[1]);
	Number(vec[2]);
	Expect(rpar, "')' expected")
END Vector;


(*--- Parser ---*)

PROCEDURE Points (shape: Dim3Engine.Shape; VAR N: INTEGER);
VAR vec: Dim3Engine.Vector; p: Dim3Engine.Point;
BEGIN
	Get;
	REPEAT
		Vector(vec);
		Dim3Engine.NewPoint(p);
		Dim3Engine.Transform(shape.T, vec, p.wc);
		Dim3Engine.AddPoint(shape, p);
		INC(N)
	UNTIL sym # lpar
END Points;

PROCEDURE Texture (shape: Dim3Engine.Shape; poly: Dim3Engine.Polygon; N: INTEGER);
VAR n, cnt: INTEGER; x, u, v: REAL; trans: BOOLEAN;
     textName: ARRAY 32 OF CHAR; p: Dim3Engine.Point;
BEGIN
	Get;
	IF sym = transparent THEN
		trans := TRUE;
		Get;
	ELSE
		trans := FALSE
	END;
	IF sym = ident THEN
		COPY(S.s, textName);
		Get;
	ELSE
		Error("ident expected");
		RETURN
	END;
	cnt := 0;
	REPEAT
		Number(x);
		IF x # ENTIER(x) THEN Error("invalid number (integer expected)")
		ELSIF (x < 0) OR (x >= N) THEN Error("point for number does not exist")
		ELSE
			(* point N-1 is the first in the list, point 0 the last *)
			n := SHORT(ENTIER(x + 1));
			p := shape.points;
			WHILE n < N DO
				p := p.next;
				INC(n)
			END;
			Number(u); Number(v);
			IF u < 0 THEN u := 0 END;
			IF v < 0 THEN v := 0 END;
			Dim3Engine.AppendTexturePoint(poly.contour, p, u, v);
			INC(cnt);
		END
	UNTIL sym # number;
	IF cnt >= 3 THEN
		Dim3Engine.AddPolygon(shape, poly)
	ELSE
		Error("not enough points given for polygon")
	END;
	Dim3Engine.InitTexture(poly, textName, trans);
END Texture;

PROCEDURE Text (shape: Dim3Engine.Shape; poly: Dim3Engine.Polygon; N: INTEGER);
VAR n, cnt: INTEGER; x, u, v: REAL; trans: BOOLEAN;
     textName: ARRAY 32 OF CHAR; p: Dim3Engine.Point;
BEGIN
	Get;
	IF sym = transparent THEN
		trans := TRUE;
		Get;
	ELSE
		trans := FALSE
	END;
	IF sym = string THEN
		COPY(S.s, textName);
		Get;
	ELSE
		Error("string expected");
		RETURN
	END;
	cnt := 0;
	REPEAT
		Number(x);
		IF x # ENTIER(x) THEN Error("invalid number (integer expected)")
		ELSIF (x < 0) OR (x >= N) THEN Error("point for number does not exist")
		ELSE
			(* point N-1 is the first in the list, point 0 the last *)
			n := SHORT(ENTIER(x + 1));
			p := shape.points;
			WHILE n < N DO
				p := p.next;
				INC(n)
			END;
			Number(u); Number(v);
			IF u < 0 THEN u := 0 END;
			IF v < 0 THEN v := 0 END;
			Dim3Engine.AppendTexturePoint(poly.contour, p, u, v);
			INC(cnt);
		END
	UNTIL sym # number;
	IF cnt >= 3 THEN
		Dim3Engine.AddPolygon(shape, poly)
	ELSE
		Error("not enough points given for polygon")
	END;
	Dim3Engine.InitStringTexture(poly, textName, cur.font, cur.fontColor, cur.color, trans);
END Text;

PROCEDURE Polygon (shape: Dim3Engine.Shape; N: INTEGER);
VAR poly: Dim3Engine.Polygon; p: Dim3Engine.Point; x: REAL; n, cnt: INTEGER;
BEGIN
	Get;
	Dim3Engine.NewPolygon(poly);
	Dim3Engine.InitPolygon(poly);
	IF sym = texture THEN
		Texture(shape, poly, N);
	ELSIF sym = text THEN
		Text(shape, poly, N);
	ELSE
		cnt := 0;
		REPEAT
			Number(x);
			IF x # ENTIER(x) THEN Error("invalid number (integer expected)")
			ELSIF (x < 0) OR (x >= N) THEN Error("point for number does not exist")
			ELSE
				(* point N-1 is the first in the list, point 0 the last *)
				n := SHORT(ENTIER(x + 1));
				p := shape.points;
				WHILE n < N DO
					p := p.next;
					INC(n)
				END;
				Dim3Engine.AppendPoint(poly.contour, p);
				INC(cnt)
			END
		UNTIL sym # number;
		IF cnt >= 3 THEN
			Dim3Engine.AddPolygon(shape, poly)
		ELSE
			Error("not enough points given for polygon")
		END;
	END;
END Polygon;

PROCEDURE Transformation;
VAR angle: REAL; v: Dim3Engine.Vector; j: INTEGER;
BEGIN
	CASE sym OF
	| translate:
		Get;
		Vector(v);
		Dim3Engine.Translate(cur.T, v[0], v[1], v[2])
	| rotate:
		Get;
		Number(angle);
		Vector(v);
		Dim3Engine.Rotate(cur.T, angle * Math.pi / 180.0, v[0], v[1], v[2])
	| scale:
		Get;
		Vector(v);
		Dim3Engine.Scale(cur.T, v[0], v[1], v[2])
	| matrix:
		Get;
		FOR j := 0 TO 3 DO
			Vector(v);
			cur.T[0, j] := v[0]; cur.T[1, j] := v[1]; cur.T[2, j] := v[2]
		END
	| identity:
		Get;
		cur.T := Dim3Engine.identity
	END
END Transformation;

PROCEDURE Attribute;
VAR r, g, b: REAL;
BEGIN
	CASE sym OF
	| color:
		Get;
		Number(r);
		Number(g);
		Number(b);
		Dim3Engine.InitColor(cur.color, r, g, b)
	| diffuse:
		Get;
		Number(cur.diffuse)
	| speccoef:
		Get;
		Number(cur.speccoef)
	| specexpo:
		Get;
		Number(b);
		cur.specexpo := SHORT(ENTIER(b))
	| save:
		Get;
		Save
	| restore:
		Get;
		Restore
	| translate..identity:
		Transformation
	END
END Attribute;

PROCEDURE Shading (s: Dim3Engine.Shape);
BEGIN
	Get;
	IF sym = constant THEN
		Get;
		cur.gouraud := FALSE;
		Dim3Engine.SetShadingShape(s, cur.gouraud)
	ELSIF sym = gouraud THEN
		Get;
		cur.gouraud := TRUE;
		Dim3Engine.SetShadingShape(s, cur.gouraud)
	ELSE
		Error("'constant' or 'gouraud' expected")
	END;
END Shading;

PROCEDURE Smooth (s: Dim3Engine.Shape);
BEGIN
	Get;
	IF sym = yes THEN
		Get;
		cur.smooth := TRUE;
		Dim3Engine.SetSmoothShape(s, cur.smooth)
	ELSIF sym = no THEN
		Get;
		cur.smooth := FALSE;
		Dim3Engine.SetSmoothShape(s, cur.smooth)
	ELSE
		Error("'yes' or 'no' expected")
	END;
END Smooth;

PROCEDURE Specular (s: Dim3Engine.Shape);
BEGIN
	Get;
	IF sym = yes THEN
		Get;
		cur.specular := TRUE;
		Dim3Engine.SetSpecularReflection(s, cur.specular)
	ELSIF sym = no THEN
		Get;
		cur.specular := FALSE;
		Dim3Engine.SetSpecularReflection(s, cur.specular)
	ELSE
		Error("'yes' or 'no' expected")
	END;
END Specular;

PROCEDURE Dither (s: Dim3Engine.Shape);
BEGIN
	Get;
	IF sym = yes THEN
		Get;
		cur.dither := TRUE;
		Dim3Engine.SetDitherShape(s, cur.dither)
	ELSIF sym = no THEN
		Get;
		cur.dither := FALSE;
		Dim3Engine.SetDitherShape(s, cur.dither)
	ELSE
		Error("'yes' or 'no' expected")
	END;
END Dither;

PROCEDURE Font (s: Dim3Engine.Shape);
BEGIN
	Get;
	IF sym =  ident THEN
		COPY(S.s, cur.font);
		Get;
	ELSE
		Error("ident expected")
	END;
	Number(cur.fontColor[0]);
	Number(cur.fontColor[1]);
	Number(cur.fontColor[2]);
END Font;

PROCEDURE Light (shape: Dim3Engine.Shape);
VAR l: Dim3Engine.Light; v, dir: Dim3Engine.Vector; inten: REAL; type: INTEGER;
BEGIN
	type := Dim3Engine.DirectLight;
	Get;
	IF sym = direct THEN Get
	ELSIF sym = point THEN type := Dim3Engine.PointLight; Get
	END;
	Vector(v);
	Number(inten);
	NEW(l);
	Dim3Engine.Transform(shape.T, v, dir);
	Dim3Engine.InitLight(l, type, dir, inten);
	Dim3Engine.AddLight(shape, l)
END Light;

PROCEDURE ^Add (shape: Dim3Engine.Shape);

PROCEDURE Shape (s: Dim3Engine.Shape);
VAR sub: Dim3Engine.Shape; N: INTEGER;
BEGIN
	Get;
	N := 0;
	WHILE sym = points DO
		Points(s, N)
	END;
	WHILE  (sym >= light) & (sym <= identity) DO
		CASE sym OF
		| light:
			Light(s)
		| font:
			Font(s)
		| shading:
			Shading(s)
		| smooth:
			Smooth(s)
		| dither:
			Dither(s)
		| specular:
			Specular(s)
		| add:
			NEW(sub);
			Add(sub);
			Dim3Engine.AddSubshape(s, sub)
		| polygon:
			Polygon(s, N)
		ELSE Attribute
		END
	END;
	Expect(end, "'end' expected")
END Shape;

PROCEDURE ShapeDef;
VAR s: ShapeSym;
BEGIN
	Get;
	IF sym = ident THEN
		NEW(s);
		COPY(S.s, s.name);
		s.startpos := Texts.Pos(S);
		s.next := shapes;
		shapes := s
	ELSE
		Error("ident expected")
	END;
	WHILE (sym # eot) & (sym # end) DO	(* skip until end of definition *)
		Get
	END;
	IF sym = end THEN
		Get
	ELSE
		Error("missing 'end'")
	END;
END ShapeDef;

PROCEDURE Add (shape: Dim3Engine.Shape);
VAR s: ShapeSym; pos: LONGINT;
BEGIN
	pos := Texts.Pos(S);	(* remember where to continue *)
	Get;
	IF sym = ident THEN
		s := shapes;
		WHILE (s # NIL) & (s.name # S.s) DO
			s := s.next
		END;
		IF s # NIL THEN	(* reopen scanner at start of shape definition *)
			Texts.OpenScanner(S, src, s.startpos);
			Dim3Engine.InitShape(shape, cur.T, cur.color, cur.diffuse, cur.speccoef, cur.specexpo, cur.gouraud, cur.smooth, cur.dither, cur.specular);
			Save;
			Shape(shape);
			shape.color := cur.color; shape.diffuse := cur.diffuse;
			shape.specexpo := cur.specexpo; shape.speccoef := cur.speccoef;
			Dim3Engine.SetShadingShape(shape, cur.gouraud);
			Dim3Engine.SetSmoothShape(shape, cur.smooth);
			Dim3Engine.SetDitherShape(shape, cur.dither);
			Dim3Engine.SetSpecularReflection(shape, cur.specular);
			Restore;
			Texts.OpenScanner(S, src, pos); Get; Get;	(* continue where analysis was interrupted *)
			IF sym = command THEN
				Get;
				IF sym = string THEN
					NEW(shape.cmd);
					COPY(S.s, shape.cmd^);
					Get
				ELSE Error("command string expected")
				END
			END
		ELSE Error("unknown shape name")
		END
	ELSE Error("ident expected")
	END
END Add;

(** start reading of polygon world description **)
PROCEDURE Read* (w: Dim3Engine.World; T: Texts.Text);
VAR s: Dim3Engine.Shape;
BEGIN
	Texts.WriteString(W, "reading polygon scene description"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	lastErrPos := -10;
	src := T;
	Texts.OpenScanner(S, src, 0);
	Get;
	(* initialize attribute state *)
	NEW(cur);
	cur.T := Dim3Engine.identity;
	cur.color := Dim3Engine.white;
	cur.diffuse := 0.5;
	cur.specexpo := 10;
	cur.speccoef := 1.0;
	cur.gouraud := FALSE;
	cur.smooth := FALSE;
	cur.dither := FALSE;
	cur.specular := FALSE;
	cur.next := NIL;
	cur.font := "Default12.Scn.Fnt";
	cur.fontColor := Dim3Engine.black;
	
	(* skip shape definitions *)
	shapes := NIL;
	WHILE sym = shape DO
		ShapeDef
	END;
	
	Dim3Engine.EnableUpdate(w, FALSE);
	WHILE sym # eot DO
		IF ~((sym IN {clear..add}) OR ((sym >= save) & (sym <= identity))) THEN
			Error("unexpected symbol (keyword expected)");
			REPEAT
				Get
			UNTIL (sym IN {clear..add, save..matrix, eot}) OR (sym = identity)
		ELSE
			CASE sym OF
			| clear:
				Get;
				Dim3Engine.FreeWorld(w)
			| horizon:
				Get;
				IF sym = yes THEN
					Get;
					w.horizon := TRUE
				ELSIF sym = no THEN
					Get;
					w.horizon := FALSE
				ELSE
					Error("'yes' or 'no' expected")
				END
			| ambient:
				Get;
				Number(w.ambient)
			| light:
				Light(w.shape)
			| font:
				Font(w.shape)
			| shading:
				Shading(w.shape)
			| smooth:
				Smooth(w.shape)
			| dither:
				Dither(w.shape)
			| specular:
				Specular(w.shape)
			| add:
				NEW(s);
				Add(s);
				Dim3Engine.AddShape(w, s)
			| save..identity:
				Attribute
			END
		END
	END;
	Dim3Engine.EnableUpdate(w, TRUE);
	Texts.WriteString(W, "  done"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Read;


BEGIN
	Texts.OpenWriter(W)
END Dim3Read.
