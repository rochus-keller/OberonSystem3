MODULE LeoDraw;	(** eos   **)

	(**
		Support for loading Draw files into Leonardo
	**)
	
	IMPORT
		Files, Objects, Attributes, Strings, Documents, GfxMatrix, GfxMaps, Gfx, GfxPens, Figures,
		LeoFrames, Leonardo, LeoBasic, LeoText, LeoPaths;
		
	
	CONST
		GraphFileId = 0F9X; LibFileId = 0FDX; NameLen = 16;
		
	
	TYPE
		Name = ARRAY NameLen OF CHAR;
		
		MacroHead = POINTER TO MacroHeadDesc;
		Library = POINTER TO LibraryDesc;
		
		MacroHeadDesc = RECORD
			name: Name;
			first: Figures.Shape;
			next: MacroHead;
		END;
		
		LibraryDesc = RECORD
			name: Name;
			first: MacroHead;
		END;
		
		Context = RECORD
			font: ARRAY 10, 32 OF CHAR;
			size: ARRAY 10 OF INTEGER;
			lib: ARRAY 4 OF Library;
			class: ARRAY 10, 64 OF CHAR;
			pen: ARRAY 16, 6 OF GfxPens.Pen;
		END;
		
	
	VAR
		GreyFiller: GfxPens.Filler;
		MacroFig: Figures.Figure;
		
	
	PROCEDURE InitContext (VAR ctxt: Context);
		VAR i, j: LONGINT;
	BEGIN
		ctxt.class[1] := "Graphics.NewLine";
		ctxt.class[2] := "Graphics.NewCaption";
		ctxt.class[3] := "Graphics.NewMacro";
		FOR i := 4 TO 9 DO ctxt.class[i] := "" END;
		FOR i := 0 TO 15 DO
			FOR j := 0 TO 5 DO ctxt.pen[i, j] := NIL END
		END
	END InitContext;
	
	PROCEDURE^ LoadElems (VAR r: Files.Rider; VAR ctxt: Context; VAR shapes: Figures.Shape);
	
	PROCEDURE ThisLibrary (VAR name: ARRAY OF CHAR): Library;
		VAR
			lib: Library; i, j, w, h: INTEGER; lname, fname: ARRAY 32 OF CHAR; file: Files.File; r: Files.Rider; ch: CHAR; ctxt: Context;
			shapes: Figures.Shape; mh: MacroHead;
	BEGIN
		lib := NIL;
		i := 0; WHILE name[i] >= "0" DO lname[i] := name[i]; INC(i) END;
		lname[i] := 0X;
		j := 0; WHILE name[j] > 0X DO fname[j] := name[j]; INC(j) END;
		IF i = j THEN
			fname[j] := "."; fname[j+1] := "L"; fname[j+2] := "i"; fname[j+3] := "b"; INC(j, 4)
		END;
		fname[j] := 0X;
		file := Files.Old(fname);
		IF file # NIL THEN
			Files.Set(r, file, 0); Files.Read(r, ch);
			IF ch = LibFileId THEN
				NEW(lib); COPY(lname, lib.name); lib.first := NIL;
				InitContext(ctxt);
				LoadElems(r, ctxt, shapes);
				WHILE shapes # NIL DO
					Figures.Integrate(MacroFig, MacroFig.root, shapes);
					NEW(mh); mh.first := shapes;
					Files.ReadInt(r, w); Files.ReadInt(r, h);
					Files.ReadString(r, mh.name);
					mh.next := lib.first; lib.first := mh;
					LoadElems(r, ctxt, shapes)
				END
			END
		END;
		RETURN lib
	END ThisLibrary;
	
	PROCEDURE ThisPen (VAR ctxt: Context; col, width: INTEGER): GfxPens.Pen;
		VAR pen: GfxPens.Stroker;
	BEGIN
		col := col MOD 16; width := (width - 1) MOD 6;
		IF ctxt.pen[col, width] = NIL THEN
			NEW(pen); GfxPens.InitStroker(pen, GfxMaps.DisplayPal.col[col], width+1);
			ctxt.pen[col, width] := pen
		END;
		RETURN ctxt.pen[col, width]
	END ThisPen;
	
	PROCEDURE CreateLine (VAR ctxt: Context; x0, y0, x1, y1: REAL; col, width: INTEGER; VAR shape: Figures.Shape);
		VAR p, q: LeoPaths.Point; first, last: Figures.Reference; line: LeoPaths.Curve;
	BEGIN
		NEW(p); LeoPaths.InitPoint(p, x0, y0);
		NEW(q); LeoPaths.InitPoint(q, x1, y1);
		p.slink := q;
		Figures.MakeRefs(p, first, last);
		NEW(line); LeoPaths.InitCurve(line, LeoPaths.PolygonClass, first, last, ThisPen(ctxt, col, width));
		line.handle := LeoPaths.HandlePolygon;
		shape := line
	END CreateLine;
	
	PROCEDURE CreateEllipse (VAR ctxt: Context; xc, yc, xr, yr: REAL; col, width: INTEGER; VAR shape: Figures.Shape);
		VAR ell: LeoBasic.Shape;
	BEGIN
		NEW(ell); LeoBasic.InitEllipse(ell, xc, yc, xr, yr, NIL, ThisPen(ctxt, col, width));
		shape := ell
	END CreateEllipse;
	
	PROCEDURE CreateRectangle (VAR ctxt: Context; x0, y0, x1, y1: REAL; col, width: INTEGER; fill: GfxPens.Pen; VAR shape: Figures.Shape);
		VAR rect: LeoBasic.Shape;
	BEGIN
		NEW(rect); LeoBasic.InitRect(rect, x0, y0, x1, y1, fill, ThisPen(ctxt, col, width));
		shape := rect
	END CreateRectangle;
	
	PROCEDURE CreateSpline (VAR ctxt: Context; closed: BOOLEAN; VAR u, v: ARRAY OF INTEGER; n, col, width: INTEGER;
		VAR shape: Figures.Shape
	);
		VAR p: LeoPaths.Point; first, last, ref: Figures.Reference; i: LONGINT; spline: LeoPaths.Curve;
	BEGIN
		NEW(p); LeoPaths.InitPoint(p, u[0] + 0.5, v[0] + 0.5);
		NEW(first); last := first; first.shape := p;
		i := 1;
		WHILE i < n DO
			NEW(p); LeoPaths.InitPoint(p, u[i] + 0.5, v[i] + 0.5);
			NEW(ref); ref.shape := p;
			last.next := ref; ref.prev := last;
			last := ref;
			INC(i)
		END;
		IF closed THEN
			NEW(ref); ref.shape := first.shape;
			last.next := ref; ref.prev := last;
			last := ref
		END;
		NEW(spline); LeoPaths.InitCurve(spline, LeoPaths.SplineClass, first, last, ThisPen(ctxt, col, width));
		spline.handle := LeoPaths.HandleSpline;
		shape := spline
	END CreateSpline;
	
	PROCEDURE LoadCaption (VAR ctxt: Context; VAR r: Files.Rider; x, y, col: INTEGER; VAR shape: Figures.Shape);
		VAR fno: SHORTINT; i: LONGINT; ch: CHAR; s: ARRAY 64 OF CHAR; cap: LeoText.Caption;
	BEGIN
		Files.Read(r, fno);
		Files.Read(r, ch); i := 0;
		WHILE ch > 0DX DO
			s[i] := ch; INC(i);
			Files.Read(r, ch)
		END;
		s[i] := 0X;
		NEW(cap); LeoText.InitCaption(cap, x + 0.5, y + 0.5, s);
		Attributes.SetString(cap, "Font", ctxt.font[fno]);
		Attributes.SetInt(cap, "Size", ctxt.size[fno]);
		Attributes.SetInt(cap, "Color", col);
		shape := cap
	END LoadCaption;
	
	PROCEDURE LoadMacro (VAR ctxt: Context; VAR r: Files.Rider; x, y, col: INTEGER; VAR shape: Figures.Shape);
		VAR
			lno: SHORTINT; name: Name; mh: MacroHead; group: Figures.Container; copies: Figures.Shape;
			first, last: Figures.Reference; mat: GfxMatrix.Matrix;
	BEGIN
		Files.Read(r, lno); Files.ReadString(r, name);
		IF ctxt.lib[lno] # NIL THEN
			mh := ctxt.lib[lno].first;
			WHILE (mh # NIL) & (mh.name # name) DO mh := mh.next END;
			GfxMatrix.Translate(GfxMatrix.Identity, x, y, mat);
			Figures.Transform(MacroFig, mh.first, mat);
			Figures.CopyShapes(mh.first, copies);
			Figures.Undo(MacroFig);
			Figures.MakeRefs(copies, first, last);
			NEW(group); Figures.InitGroup(group, first, last);
			shape := group
		ELSE
			NEW(shape); shape.handle := Figures.HandleShape
		END
	END LoadMacro;
	
	PROCEDURE LoadCurve (VAR ctxt: Context; VAR r: Files.Rider; x, y, w, h, col: INTEGER; VAR shape: Figures.Shape);
		VAR len, kind, lw: INTEGER;
	BEGIN
		Files.ReadInt(r, len);
		Files.ReadInt(r, kind);
		Files.ReadInt(r, lw);
		IF kind = 0 THEN	(* up_line *)
			CreateLine(ctxt, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, col, lw, shape)
		ELSIF kind = 1 THEN	(* down_line *)
			CreateLine(ctxt, x + 0.5, y + h - 0.5, x + w - 0.5, y + 0.5, col, lw, shape)
		ELSIF kind = 2 THEN	(* circle *)
			w := w DIV 2;
			CreateEllipse(ctxt, x + w + 0.5, y + w + 0.5, w, w, col, lw, shape)
		ELSIF kind = 3 THEN	(* ellipse *)
			w := w DIV 2; h := h DIV 2;
			CreateEllipse(ctxt, x + w + 0.5, y + h + 0.5, w, h, col, lw, shape)
		ELSE
			NEW(shape); shape.handle := Figures.HandleShape
		END
	END LoadCurve;
	
	PROCEDURE LoadRectangle (VAR ctxt: Context; VAR r: Files.Rider; x, y, w, h, col: INTEGER; VAR shape: Figures.Shape);
		VAR len: INTEGER; width, vers: SHORTINT; fill: GfxPens.Pen;
	BEGIN
		Files.ReadInt(r, len);
		Files.Read(r, width); Files.Read(r, vers);
		IF vers # 0 THEN fill := GreyFiller ELSE fill := NIL END;
		CreateRectangle(ctxt, x + 0.5, y + 0.5, x + w - 0.5, y + h - 0.5, col, width, fill, shape)
	END LoadRectangle;
	
	PROCEDURE LoadSpline (VAR ctxt: Context; VAR r: Files.Rider; x, y, col: INTEGER; VAR shape: Figures.Shape);
		VAR len, n, i: INTEGER; open: SHORTINT; u, v: ARRAY 21 OF INTEGER;
	BEGIN
		Files.ReadInt(r, len);
		n := (len - 1) DIV 4;
		Files.Read(r, open);
		FOR i := 0 TO n - 1 DO Files.ReadInt(r, u[i]); INC(u[i], x) END;
		FOR i := 0 TO n - 1 DO Files.ReadInt(r, v[i]); INC(v[i], y) END;
		CreateSpline(ctxt, open # 1, u, v, n, col, 1, shape)
	END LoadSpline;
	
	PROCEDURE LoadShape (VAR ctxt: Context; VAR r: Files.Rider; VAR gen: ARRAY OF CHAR; VAR shape: Figures.Shape);
		VAR x, y, w, h, col: INTEGER;
	BEGIN
		Files.ReadInt(r, x); Files.ReadInt(r, y); INC(y, SHORT(ENTIER(Figures.A4H)));
		Files.ReadInt(r, w); Files.ReadInt(r, h);
		Files.ReadInt(r, col);
		IF gen = "Graphics.NewLine" THEN
			IF w > h THEN
				CreateLine(ctxt, x + 0.5, y + 0.5*h, x + w - 0.5, y + 0.5*h, col, h, shape)
			ELSE
				CreateLine(ctxt, x + 0.5*w, y + 0.5, x + 0.5*w, y + h - 0.5, col, w, shape)
			END
		ELSIF gen = "Graphics.NewCaption" THEN
			LoadCaption(ctxt, r, x, y, col, shape)
		ELSIF gen = "Graphics.NewMacro" THEN
			LoadMacro(ctxt, r, x, y - SHORT(ENTIER(Figures.A4H)), col, shape)
		ELSIF gen = "Curves.New" THEN
			LoadCurve(ctxt, r, x, y, w, h, col, shape)
		ELSIF gen = "Rectangles.New" THEN
			LoadRectangle(ctxt, r, x, y, w, h, col, shape)
		ELSIF gen = "Splines.New" THEN
			LoadSpline(ctxt, r, x, y, col, shape)
		ELSE
			NEW(shape); shape.handle := Figures.HandleShape
		END
	END LoadShape;
	
	PROCEDURE LoadElems (VAR r: Files.Rider; VAR ctxt: Context; VAR shapes: Figures.Shape);
		VAR last, new: Figures.Shape; cno, k: SHORTINT; name, cmd: ARRAY 32 OF CHAR; i, j: LONGINT; len: INTEGER;
	BEGIN
		shapes := NIL; last := NIL;
		Files.Read(r, cno);
		WHILE ~r.eof & (cno >= 0) DO
			IF cno = 0 THEN
				Files.Read(r, cno); Files.Read(r, k); Files.ReadString(r, name);
				IF cno = 0 THEN
					i := 0;
					WHILE (name[i] # 0X) & (name[i] # ".") & ((name[i] < "0") OR ("9" < name[i])) DO
						ctxt.font[k, i] := name[i]; INC(i)
					END;
					ctxt.font[k, i] := 0X;
					IF ("0" <= name[i]) & (name[i] <= "9") THEN
						ctxt.size[k] := 0;
						REPEAT
							ctxt.size[k] := 10*ctxt.size[k] + ORD(name[i]) - ORD("0");
							INC(i)
						UNTIL (name[i] < "0") OR ("9" < name[i]);
						IF name[i] = "i" THEN
							Strings.Append(ctxt.font[k], "-Italic")
						ELSIF name[i] = "m" THEN
							Strings.Append(ctxt.font[k], "-Medium")
						ELSIF name[i] = "b" THEN
							Strings.Append(ctxt.font[k], "-Bold")
						ELSIF name[i] = "j" THEN
							Strings.Append(ctxt.font[k], "-BoldItalic")
						END
					ELSE
						ctxt.size[k] := 1
					END
				ELSIF cno = 1 THEN
					ctxt.lib[k] := ThisLibrary(name)
				ELSE
					Files.ReadString(r, cmd);
					i := 0; j := 0;
					WHILE name[i] # 0X DO
						ctxt.class[k, i] := name[i]; INC(i)
					END;
					ctxt.class[k, i] := "."; INC(i);
					WHILE cmd[j] # 0X DO
						ctxt.class[k, i] := cmd[j]; INC(i); INC(j)
					END;
					ctxt.class[k, i] := 0X
				END
			ELSIF ctxt.class[cno] # "" THEN
				LoadShape(ctxt, r, ctxt.class[cno], new);
				IF last = NIL THEN shapes := new ELSE last.slink := new END;
				last := new
			ELSE
				Files.Set(r, Files.Base(r), Files.Pos(r) + 10); Files.ReadInt(r, len);
				Files.Set(r, Files.Base(r), Files.Pos(r) + len)
			END;
			Files.Read(r, cno)
		END
	END LoadElems;
	
	PROCEDURE LoadDoc (doc: Documents.Document);
		VAR
			fig: Figures.Figure; file: Files.File; r: Files.Rider; tag: CHAR; ctxt: Context; shapes: Figures.Shape; layer: LeoFrames.Layer;
			main: LeoFrames.Frame; ruler: Leonardo.Ruler;
	BEGIN
		fig := NIL;
		file := Files.Old(doc.name);
		IF file # NIL THEN
			Files.Set(r, file, 0);
			Files.Read(r, tag);
			IF tag = GraphFileId THEN
				NEW(MacroFig); Figures.Init(MacroFig, 0, 0);
				InitContext(ctxt);
				LoadElems(r, ctxt, shapes);
				NEW(fig); Figures.Init(fig, Figures.A4W, Figures.A4H);
				Figures.Integrate(fig, fig.root, shapes);
				Figures.ClearSelection(fig);
				MacroFig := NIL
			END
		END;
		IF fig = NIL THEN
			doc.name := "No Draw file found";
			NEW(fig); Figures.Init(fig, Figures.A4W, Figures.A4H);
			NEW(layer); LeoFrames.InitLayer(layer, "Main", TRUE, TRUE, TRUE, TRUE);
			Figures.Integrate(fig, fig.root, layer)
		END;
		NEW(main); LeoFrames.InitFrame(main, fig, Figures.cm, 10);
		NEW(ruler); Leonardo.InitRuler(ruler, main);
		Documents.Init(doc, ruler)
	END LoadDoc;
	
	PROCEDURE NewDoc*;
		VAR doc: Documents.Document;
	BEGIN
		NEW(doc); Leonardo.InitDoc(doc);
		doc.Load := LoadDoc;
		Objects.NewObj := doc
	END NewDoc;
	

BEGIN
	NEW(GreyFiller); GfxPens.InitFiller(GreyFiller, Gfx.LGrey)
END LeoDraw.
