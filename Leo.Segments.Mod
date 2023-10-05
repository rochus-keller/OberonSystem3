MODULE Segments;	(** eos   **)

	(**
		Compatibility module for users using older version of Leonardo
	**)
	
	IMPORT
		Files, Objects, GfxPens, Figures, LeoPaths, LeoPens;
		
	
	PROCEDURE HandleCurve (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR path: LeoPaths.Path; ref: Figures.Reference; prev, next: LeoPaths.Curve;
	BEGIN
		WITH msg: Objects.FileMsg DO
			path := obj(LeoPaths.Path);
			path.handle := LeoPaths.HandlePath;
			ASSERT(msg.id = Objects.load);
			Figures.HandleContainer(path, msg);
			IF path.first # NIL THEN
				ref := path.first; prev := ref.shape(LeoPaths.Curve);
				ref := ref.next;
				WHILE ref # NIL DO
					next := ref.shape(LeoPaths.Curve);
					prev.succ := next; next.pred := prev;
					ref := ref.next; prev := next
				END;
				next := path.first.shape(LeoPaths.Curve);
				IF prev.last.shape = next.first.shape THEN	(* closed *)
					prev.succ := next; next.pred := prev
				END
			END;
			LeoPaths.ValidatePath(path)
		END
	END HandleCurve;
	
	PROCEDURE NewCurve*;
		VAR path: LeoPaths.Path;
	BEGIN
		NEW(path); path.handle := HandleCurve;
		Objects.NewObj := path
	END NewCurve;
	
	PROCEDURE HandleSegment (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR curve: LeoPaths.Curve; q, p: LeoPaths.Point; ver: LONGINT;
	BEGIN
		WITH msg: Objects.FileMsg DO
			curve := obj(LeoPaths.Curve);
			ASSERT(msg.id = Objects.load);
			Figures.HandleContainer(curve, msg);
			IF curve.first = curve.last THEN
				IF curve.first = NIL THEN NEW(q); NEW(curve.first); curve.first.shape := q END;
				q := curve.first.shape(LeoPaths.Point);
				NEW(p); LeoPaths.InitPoint(p, q.x, q.y);
				NEW(curve.last); curve.last.shape := p;
				curve.last.prev := curve.first; curve.first.next := curve.last
			END;
			Files.ReadNum(msg.R, ver);
			ASSERT(ver = 1);
			LeoPens.ReadRef(msg.R, curve.lib, curve.stroke);
			IF curve.first.shape = curve.last.shape THEN
				curve.pred := curve; curve.succ := curve
			END;
			LeoPaths.ValidateCurve(curve)
		END
	END HandleSegment;
	
	PROCEDURE HandleLine (obj: Objects.Object; VAR msg: Objects.ObjMsg);
	BEGIN
		obj.handle := LeoPaths.HandlePolygon;
		HandleSegment(obj, msg)
	END HandleLine;
	
	PROCEDURE NewLine*;
		VAR curve: LeoPaths.Curve;
	BEGIN
		NEW(curve); curve.class := LeoPaths.PolygonClass; curve.handle := HandleLine;
		Objects.NewObj := curve
	END NewLine;
	
	PROCEDURE HandleArc (obj: Objects.Object; VAR msg: Objects.ObjMsg);
	BEGIN
		obj.handle := LeoPaths.HandleArc;
		HandleSegment(obj, msg)
	END HandleArc;
	
	PROCEDURE NewArc*;
		VAR curve: LeoPaths.Curve;
	BEGIN
		NEW(curve); curve.class := LeoPaths.ArcClass; curve.handle := HandleArc;
		Objects.NewObj := curve
	END NewArc;
	
	PROCEDURE HandleBezier (obj: Objects.Object; VAR msg: Objects.ObjMsg);
	BEGIN
		obj.handle := LeoPaths.HandleBezier;
		HandleSegment(obj, msg)
	END HandleBezier;
	
	PROCEDURE NewBezier*;
		VAR curve: LeoPaths.Curve;
	BEGIN
		NEW(curve); curve.class := LeoPaths.BezierClass; curve.handle := HandleBezier;
		Objects.NewObj := curve
	END NewBezier;
	
	PROCEDURE HandleSpline (obj: Objects.Object; VAR msg: Objects.ObjMsg);
	BEGIN
		obj.handle := LeoPaths.HandleSpline;
		HandleSegment(obj, msg)
	END HandleSpline;
	
	PROCEDURE NewSpline*;
		VAR curve: LeoPaths.Curve;
	BEGIN
		NEW(curve); curve.class := LeoPaths.SplineClass; curve.handle := HandleSpline;
		Objects.NewObj := curve
	END NewSpline;
	

END Segments.
