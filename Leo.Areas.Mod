MODULE Areas;	(** eos   **)

	(**
		Compatibility module for users using older version of Leonardo
	**)
	
	IMPORT
		Files, Objects, GfxPens, Figures, LeoBasic, LeoPaths, LeoPens;
		
	
	PROCEDURE RemoveArrows (stroke: GfxPens.Pen): GfxPens.Pen;
		VAR split: GfxPens.Splitter; rev: GfxPens.Reverser;
	BEGIN
		IF (stroke # NIL) & (stroke IS GfxPens.Splitter) THEN
			split := stroke(GfxPens.Splitter);
			IF (split.head # NIL) & (split.head IS GfxPens.Arrow) THEN
				stroke := RemoveArrows(split.tail)
			ELSIF (split.head # NIL) & (split.head IS GfxPens.Reverser) THEN
				rev := split.head(GfxPens.Reverser);
				IF (rev.base # NIL) & (rev.base IS GfxPens.Arrow) THEN
					stroke := RemoveArrows(split.tail)
				END
			ELSIF (split.tail # NIL) & (split.tail IS GfxPens.Arrow) THEN
				stroke := RemoveArrows(split.head)
			END
		END;
		RETURN stroke
	END RemoveArrows;
	
	PROCEDURE HandleRect (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR rect: LeoBasic.Shape; ver: LONGINT; first, last: Figures.Reference; p0, p1, p2: LeoPaths.Point;
			dummy: BOOLEAN; fill, stroke: GfxPens.Pen;
	BEGIN
		WITH msg: Objects.FileMsg DO
			rect := obj(LeoBasic.Shape);
			rect.handle := LeoBasic.HandleRect;
			ASSERT(msg.id = Objects.load, 90);
			Figures.HandleShape(rect, msg);
			Files.ReadNum(msg.R, ver);
			ASSERT(ver = 1, 91);
			Figures.ReadRefs(msg.R, rect.lib, first, last);
			ASSERT(first.shape IS LeoPaths.Point, 92);
			p0 := first.shape(LeoPaths.Point);
			ASSERT(first.next.shape IS LeoPaths.Point, 93);
			p1 := first.next.shape(LeoPaths.Point);
			ASSERT(last.shape IS LeoPaths.Point, 94);
			p2 := last.shape(LeoPaths.Point);
			rect.ax := 0.5*(p1.x - p0.x); rect.ay := 0.5*(p1.y - p0.y);
			rect.bx := 0.5*(p2.x - p0.x); rect.by := 0.5*(p2.y - p0.y);
			rect.mx := p0.x + rect.ax + rect.bx; rect.my := p0.y + rect.ay + rect.by;
			Files.ReadBool(msg.R, dummy);
			Files.ReadNum(msg.R, ver);
			ASSERT(ver = 1, 95);
			LeoPens.ReadRef(msg.R, rect.lib, fill);
			LeoPens.ReadRef(msg.R, rect.lib, stroke);
			IF fill = GfxPens.Dummy THEN fill := NIL END;
			IF stroke = GfxPens.Dummy THEN stroke := NIL END;
			rect.fill := fill; rect.stroke := RemoveArrows(stroke);
			Figures.ReadRefs(msg.R, rect.lib, first, last);	(* ignore constraints *)
			Figures.ReadRefs(msg.R, rect.lib, first, last);
			LeoBasic.ValidateShape(rect)
		END
	END HandleRect;
	
	PROCEDURE NewRectangle*;
		VAR rect: LeoBasic.Shape;
	BEGIN
		NEW(rect); rect.handle := HandleRect;
		Objects.NewObj := rect
	END NewRectangle;
	
	
	PROCEDURE HandleEllipse (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR ell: LeoBasic.Shape; ver: LONGINT; first, last: Figures.Reference; p0, p1, p2: LeoPaths.Point;
			dummy: BOOLEAN; fill, stroke: GfxPens.Pen; forker: GfxPens.Forker;
	BEGIN
		WITH msg: Objects.FileMsg DO
			ell := obj(LeoBasic.Shape);
			ell.handle := LeoBasic.HandleEllipse;
			ASSERT(msg.id = Objects.load);
			Figures.HandleShape(ell, msg);
			Files.ReadNum(msg.R, ver);
			ASSERT(ver = 1);
			Figures.ReadRefs(msg.R, ell.lib, first, last);
			p0 := first.shape(LeoPaths.Point);
			p1 := first.next.shape(LeoPaths.Point);
			p2 := last.shape(LeoPaths.Point);
			ell.mx := p0.x; ell.my := p0.y;
			ell.ax := p1.x - p0.x; ell.ay := p1.y - p0.y;
			ell.bx := p2.x - p0.x; ell.by := p2.y - p0.y;
			Files.ReadBool(msg.R, dummy);
			Files.ReadNum(msg.R, ver);
			ASSERT(ver = 1);
			LeoPens.ReadRef(msg.R, ell.lib, fill);
			LeoPens.ReadRef(msg.R, ell.lib, stroke);
			IF fill = GfxPens.Dummy THEN fill := NIL END;
			IF stroke = GfxPens.Dummy THEN stroke := NIL END;
			ell.fill := fill; ell.stroke := RemoveArrows(stroke);
			Figures.ReadRefs(msg.R, ell.lib, first, last);	(* ignore constraints *)
			Figures.ReadRefs(msg.R, ell.lib, first, last);
			LeoBasic.ValidateShape(ell)
		END
	END HandleEllipse;
	
	PROCEDURE NewEllipse*;
		VAR ell: LeoBasic.Shape;
	BEGIN
		NEW(ell); ell.handle := HandleEllipse;
		Objects.NewObj := ell
	END NewEllipse;
	
	
	PROCEDURE HandleArea (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR path, p: LeoPaths.Path; ref, prev, next: Figures.Reference; ver: LONGINT;
	BEGIN
		WITH msg: Objects.FileMsg DO
			path := obj(LeoPaths.Path);
			path.handle := LeoPaths.HandlePath;
			ASSERT(msg.id = Objects.load);
			Figures.HandleContainer(path, msg);	(* reads several subpaths (curves) => join to single path *)
			ref := path.first; prev := NIL;
			WHILE ref # NIL DO
				next := ref.next;
				IF ref.shape IS LeoPaths.Path THEN
					p := ref.shape(LeoPaths.Path);
					IF prev # NIL THEN prev.next := p.first ELSE path.first := p.first END;
					IF next # NIL THEN next.prev := p.last ELSE path.last := p.last END;
					p.first.prev := prev; p.last.next := next;
					prev := p.last
				ELSE
					prev := ref
				END;
				ref := next
			END;
			Files.ReadNum(msg.R, ver);
			ASSERT(ver = 1);
			LeoPens.ReadRef(msg.R, path.lib, path.fill)
		END
	END HandleArea;
	
	PROCEDURE NewArea*;
		VAR path: LeoPaths.Path;
	BEGIN
		NEW(path); path.handle := HandleArea;
		Objects.NewObj := path
	END NewArea;
	

END Areas.
