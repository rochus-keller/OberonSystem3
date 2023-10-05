MODULE FancyPens;	(** eos   **)

	(**
		Compatibility module for users using older version of Leonardo
	**)
	
	IMPORT
		Files, Objects, GfxPens, LeoPens;
		
	
	(*
		Dasher Pens: only problem is converting the pattern from the old set based representation to an array of reals
		when loading
	*)
	
	PROCEDURE HandleDashPen (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen: GfxPens.Dasher; ver, i: LONGINT; set: SET; len: INTEGER; period, beg, end: REAL;
	BEGIN
		WITH msg: Objects.FileMsg DO
			ASSERT(msg.id = Objects.load);
			pen := obj(GfxPens.Dasher);
			LeoPens.ReadRef(msg.R, pen.lib, pen.base);
			Files.ReadNum(msg.R, ver);
			ASSERT(ver = 1);
			Files.ReadSet(msg.R, set);
			Files.ReadInt(msg.R, len);
			Files.ReadReal(msg.R, period);
			Files.ReadBool(msg.R, pen.continuous);
			pen.continuous := ~pen.continuous;
			IF (set = {}) OR (len = 0) OR (set = {0..len-1}) THEN	(* use solid pattern *)
				pen.phase := 0; pen.len := 0
			ELSE
				i := 0; WHILE ~(i IN set) DO INC(i) END;	(* find first element in set *)
				beg := i * period/len; pen.len := 0; pen.phase := beg;
				WHILE i < len DO
					WHILE (i < len) & (i IN set) DO INC(i) END;
					end := i * period/len; pen.on[pen.len] := end - beg;
					WHILE (i < len) & ~(i IN set) DO INC(i) END;
					beg := i * period/len; pen.off[pen.len] := beg - end;
					INC(pen.len)
				END;
				pen.off[pen.len-1] := pen.off[pen.len-1] + pen.phase
			END;
			pen.handle := GfxPens.HandleDasher
		END
	END HandleDashPen;
	
	PROCEDURE NewDashPen*;
		VAR pen: GfxPens.Dasher; pat: ARRAY 2 OF REAL;
	BEGIN
		NEW(pen); GfxPens.InitDasher(pen, GfxPens.Dummy, pat, pat, 0);
		pen.handle := HandleDashPen;
		Objects.NewObj := pen
	END NewDashPen;
	
	
	(*
		Bevel Pens: currently the information about the bevel join is lost, but this doesn't really matter since no
		other join styles were implemented in previous Leonardo versions. The tricky bit is that the old pen
		implementation supports two slaves: one for filling and one for stroking the outline, basically requiring
		a forker pen. However, if one of the forker's slaves is not a real pen, the forker forwards all messages
		to its second slave. The next time it is stored, any trace of the forker is therefore lost.
	*)
	
	PROCEDURE HandleBevelPen (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen: GfxPens.Forker; width: REAL; stroke, fill: GfxPens.Pen; ol: GfxPens.Outliner; ss: GfxPens.Stroker;
	BEGIN
		pen := obj(GfxPens.Forker);
		IF (msg IS Objects.FileMsg) & (msg(Objects.FileMsg).id = Objects.load) THEN
			WITH msg: Objects.FileMsg DO
				Files.ReadReal(msg.R, width);
				LeoPens.ReadRef(msg.R, pen.lib, stroke);
				LeoPens.ReadRef(msg.R, pen.lib, fill);
				IF (stroke # NIL) & (stroke # GfxPens.Dummy) THEN
					NEW(ol); GfxPens.InitOutliner(ol, stroke, width);
					pen.upper := ol
				ELSE
					pen.upper := GfxPens.Dummy
				END;
				IF (fill # NIL) & (fill # GfxPens.Dummy) THEN
					IF fill IS GfxPens.Filler THEN
						NEW(ss); GfxPens.InitStroker(ss, fill(GfxPens.Filler).col, width);
						pen.lower := ss
					ELSE	(* will probably never happen *)
						NEW(ol); GfxPens.InitOutliner(ol, stroke, width);
						pen.lower := ol
					END
				ELSE
					pen.lower := GfxPens.Dummy
				END
			END
		ELSIF pen.upper = GfxPens.Dummy THEN
			pen.lower.handle(pen.lower, msg)
		ELSIF pen.lower = GfxPens.Dummy THEN
			pen.upper.handle(pen.upper, msg)
		ELSE
			GfxPens.HandleForker(obj, msg)
		END
	END HandleBevelPen;
	
	PROCEDURE NewBevelPen*;
		VAR pen: GfxPens.Forker;
	BEGIN
		NEW(pen); GfxPens.InitForker(pen, GfxPens.Dummy, GfxPens.Dummy);
		pen.handle := HandleBevelPen;
		Objects.NewObj := pen
	END NewBevelPen;
	
	
	(*
		Style Pens: are represented through one or two splitters, depending on whether they have one or
		two begin/end styles.
	*)
	
	PROCEDURE HandleStylePen* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR
			pen, sp: GfxPens.Splitter;
			slave, stroke, fill, liner, beg, end: GfxPens.Pen;
			width: REAL;
			fp: GfxPens.Forker;
			rp: GfxPens.Reverser;
	BEGIN
		WITH msg: Objects.FileMsg DO
			ASSERT(msg.id = Objects.load);
			pen := obj(GfxPens.Splitter);
			LeoPens.ReadRef(msg.R, pen.lib, slave);
			Files.ReadReal(msg.R, width);
			LeoPens.ReadRef(msg.R, pen.lib, stroke);
			LeoPens.ReadRef(msg.R, pen.lib, fill);
			IF (stroke = NIL) OR (stroke = GfxPens.Dummy) THEN
				liner := fill
			ELSIF (fill = NIL) OR (fill = GfxPens.Dummy) THEN
				liner := stroke
			ELSE
				NEW(fp); GfxPens.InitForker(fp, fill, stroke);
				liner := fp
			END;
			LeoPens.ReadRef(msg.R, pen.lib, beg);
			LeoPens.ReadRef(msg.R, pen.lib, end);
			IF (beg # NIL) & (beg IS GfxPens.Arrow) THEN
				beg(GfxPens.Arrow).base := liner; beg(GfxPens.Arrow).stem := width;
				NEW(rp); GfxPens.InitReverser(rp, beg);
				IF (end # NIL) & (end IS GfxPens.Arrow) THEN
					NEW(sp); GfxPens.InitSplitter(sp, rp, slave, beg(GfxPens.Arrow).len, FALSE);
					slave := sp
				ELSE
					pen.head := rp; pen.tail := slave; pen.offset := beg(GfxPens.Arrow).len; pen.relative := FALSE
				END
			END;
			IF (end # NIL) & (end IS GfxPens.Arrow) THEN
				end(GfxPens.Arrow).base := liner; end(GfxPens.Arrow).stem := width;
				pen.head := slave; pen.tail := end; pen.offset := -end(GfxPens.Arrow).len; pen.relative := FALSE
			END;
			pen.handle := GfxPens.HandleSplitter
		END
	END HandleStylePen;
	
	PROCEDURE NewStylePen*;
		VAR pen: GfxPens.Splitter;
	BEGIN
		NEW(pen); GfxPens.InitSplitter(pen, GfxPens.Dummy, GfxPens.Dummy, 0.5, TRUE);
		pen.handle := HandleStylePen;
		Objects.NewObj := pen
	END NewStylePen;
	
	
	(*
		Arrows: used to be separate type, not a pen. Read dimensions from file and trust corresponding style pen to
		set the arrow's slave pen and stem width
	*)
	
	PROCEDURE HandleArrowStyle (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen: GfxPens.Arrow; width: REAL;
	BEGIN
		WITH msg: Objects.FileMsg DO
			ASSERT(msg.id = Objects.load);
			pen := obj(GfxPens.Arrow);
			Files.ReadReal(msg.R, pen.len);
			Files.ReadReal(msg.R, width);
			pen.tan := width/pen.len;
			pen.handle := GfxPens.HandleArrow
		END
	END HandleArrowStyle;
	
	PROCEDURE NewArrowStyle*;
		VAR pen: GfxPens.Arrow;
	BEGIN
		NEW(pen); GfxPens.InitArrow(pen, GfxPens.Dummy, 10, 1, 1);
		pen.handle := HandleArrowStyle;
		Objects.NewObj := pen
	END NewArrowStyle;
	

END FancyPens.
