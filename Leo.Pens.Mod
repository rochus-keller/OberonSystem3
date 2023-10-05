MODULE Pens;	(** eos   **)

	(**
		Compatibility module for users using older version of Leonardo
	**)
	
	IMPORT
		Files, Objects, Gfx, GfxPens;
		
	
	PROCEDURE NewEmptyStrokePen*;
	BEGIN
		Objects.NewObj := GfxPens.Dummy
	END NewEmptyStrokePen;
	
	PROCEDURE NewEmptyFillPen*;
	BEGIN
		Objects.NewObj := GfxPens.Dummy
	END NewEmptyFillPen;
	
	PROCEDURE HandleColorFillPen (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen: GfxPens.Filler; ch: CHAR; dummy: INTEGER;
	BEGIN
		WITH msg: Objects.FileMsg DO
			ASSERT(msg.id = Objects.load);
			pen := obj(GfxPens.Filler);
			Files.Read(msg.R, ch); pen.col.r := ORD(ch);
			Files.Read(msg.R, ch); pen.col.g := ORD(ch);
			Files.Read(msg.R, ch); pen.col.b := ORD(ch);
			Files.ReadInt(msg.R, dummy);
			pen.handle := GfxPens.HandleFiller
		END
	END HandleColorFillPen;
	
	PROCEDURE NewColorFillPen*;
		VAR pen: GfxPens.Filler;
	BEGIN
		NEW(pen); GfxPens.InitFiller(pen, Gfx.White);
		pen.handle := HandleColorFillPen;
		Objects.NewObj := pen
	END NewColorFillPen;
	
	PROCEDURE HandleColorStrokePen (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen: GfxPens.Stroker; ch: CHAR; dummy: INTEGER;
	BEGIN
		WITH msg: Objects.FileMsg DO
			ASSERT(msg.id = Objects.load);
			pen := obj(GfxPens.Stroker);
			Files.Read(msg.R, ch); pen.col.r := ORD(ch);
			Files.Read(msg.R, ch); pen.col.g := ORD(ch);
			Files.Read(msg.R, ch); pen.col.b := ORD(ch);
			Files.ReadInt(msg.R, dummy);
			pen.handle := GfxPens.HandleStroker
		END
	END HandleColorStrokePen;
	
	PROCEDURE NewColorStrokePen*;
		VAR pen: GfxPens.Stroker;
	BEGIN
		NEW(pen); GfxPens.InitStroker(pen, Gfx.Black, 0);
		pen.handle := HandleColorStrokePen;
		Objects.NewObj := pen
	END NewColorStrokePen;
	

END Pens.
