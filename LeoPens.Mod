MODULE LeoPens;	(** eos   **)

	(**
		Pen management for Leonardo
	**)
	
	IMPORT
		Files, Objects, Display, Fonts, Pictures, Printer, Strings, Oberon, Display3, Printer3, Attributes, Links, Gadgets,
		ListRiders, ListGadgets, GfxPens, Figures, Leonardo;
		
	
	CONST
		Replace* = 0;	(** change message id **)
		StrokePen* = 0; FillPen* = 1;	(** change message destination elements **)
		
		EditorName = "Editor";
		
	
	TYPE
		ChangeMsg* = RECORD (Figures.ShapeMsg)
			id*: INTEGER;	(** Replace **)
			res*: INTEGER;	(** result field **)
			dest*: SET;	(** StrokePen, FillPen **)
			pen*: ARRAY 2 OF GfxPens.Pen;	(** pens to replace old one with **)
		END;
		
		GenFrame = POINTER TO GenFrameDesc;
		GenFrameDesc = RECORD (Gadgets.FrameDesc)
			font: Fonts.Font;	(* font for displaying model generator *)
		END;
		
		Item = POINTER TO ItemDesc;
		ItemDesc = RECORD (ListRiders.DataDesc)
			pen: GfxPens.Pen;	(* underlying pen object *)
			name: ARRAY 32 OF CHAR;	(* attribute/link name *)
			obj: Objects.Object;	(* model object for attribute (if edited) *)
			prev, next, dsc: Item;	(* links for building hierarchy *)
			key, pos, stamp, state: LONGINT;	(* rider functionality *)
		END;
		
		Model = POINTER TO ModelDesc;
		ModelDesc = RECORD (Gadgets.ObjDesc)
			tail: Item;	(* list sentinel *)
			key: LONGINT;	(* next unique key *)
		END;
		
		PenAction = POINTER TO PenActionDesc;
		PenActionDesc = RECORD (Figures.ActionDesc)
			name: ARRAY 32 OF CHAR;
			shape, pen: Objects.Object;
		END;
		
	
	VAR
		Filler*: GfxPens.Pen;	(** current fill pen **)
		Stroker*: GfxPens.Pen;	(** current stroke pen **)
		
		RMethods: ListRiders.Method;
		UniqueKey: LONGINT;
		EnumTail: Item;
		
		FMethods: ListGadgets.Method;
		FoldedPict, UnfoldedPict: Pictures.Picture;
		PictWidth: INTEGER;
		
	
	(**--- Legacy from GfxPens ---**)
	
	PROCEDURE LinkRef* (VAR msg: Objects.LinkMsg; name: ARRAY OF CHAR; allowNIL: BOOLEAN; VAR pen: GfxPens.Pen);
	BEGIN
		IF msg.id = Objects.enum THEN
			msg.Enum(name)
		ELSIF (msg.id = Objects.get) & (msg.name = name) THEN
			msg.obj := pen; msg.res := 0
		ELSIF (msg.id = Objects.set) & (msg.name = name) THEN
			IF (msg.obj = NIL) & allowNIL THEN pen := NIL; msg.res := 0
			ELSIF (msg.obj # NIL) & (msg.obj IS GfxPens.Pen) THEN pen := msg.obj(GfxPens.Pen); msg.res := 0
			END
		END
	END LinkRef;
	
	PROCEDURE WriteRef* (VAR r: Files.Rider; lib: Objects.Library; pen: GfxPens.Pen);
	BEGIN
		Gadgets.WriteRef(r, lib, pen)
	END WriteRef;
	
	PROCEDURE ReadRef* (VAR r: Files.Rider; lib: Objects.Library; VAR pen: GfxPens.Pen);
		VAR obj: Objects.Object;
	BEGIN
		Gadgets.ReadRef(r, lib, obj);
		IF (obj # NIL) & (obj IS GfxPens.Pen) THEN pen := obj(GfxPens.Pen)
		ELSE pen := NIL
		END
	END ReadRef;
	
	PROCEDURE Bind* (obj: Objects.Object; lib: Objects.Library);
	BEGIN
		Gadgets.BindObj(obj, lib)
	END Bind;
	
	PROCEDURE CopyRef* (VAR msg: Objects.CopyMsg; from: GfxPens.Pen; VAR to: GfxPens.Pen);
		VAR obj: Objects.Object;
	BEGIN
		IF msg.id = Objects.shallow THEN
			to := from
		ELSIF msg.id = Objects.deep THEN
			IF from = NIL THEN to := NIL
			ELSE obj := Gadgets.CopyPtr(msg, from); to := obj(GfxPens.Pen)
			END
		END
	END CopyRef;
	
	
	(*--- Generator Frames ---*)
	
	PROCEDURE GetGenerator (obj: Objects.Object; VAR s: ARRAY OF CHAR);
		VAR i, j: LONGINT; ch: CHAR;
	BEGIN
		IF obj # NIL THEN
			Attributes.GetString(obj, "Gen", s);
			IF Strings.Prefix("GfxPens.New", s) THEN
				i := 0; j := 11;
				REPEAT
					ch := s[j]; s[i] := s[j]; INC(i); INC(j)
				UNTIL ch = 0X
			END
		ELSE
			COPY("NIL", s)
		END
	END GetGenerator;
	
	PROCEDURE RestoreGen (gen: GenFrame; x, y: INTEGER; mask: Display3.Mask);
		VAR name: ARRAY 64 OF CHAR; w, h, dsr: INTEGER;
	BEGIN
		Oberon.RemoveMarks(x, y, gen.W, gen.H);
		Display3.FilledRect3D(mask, Display3.bottomC, Display3.topC, Display3.textbackC, x, y, gen.W, gen.H, 1, Display.replace);
		GetGenerator(gen.obj, name);
		Display3.StringSize(name, gen.font, w, h, dsr);
		Display3.String(mask, Display3.textC, x + (gen.W - w) DIV 2, y + (gen.H - h) DIV 2 + dsr, gen.font, name, Display.paint);
		IF Gadgets.selected IN gen.state THEN
			Display3.FillPattern(mask, Display3.white, Display3.selectpat, 0, 0, x, y, gen.W, gen.H, Display.paint)
		END
	END RestoreGen;
	
	PROCEDURE PrintGen (gen: GenFrame; VAR msg: Display.DisplayMsg);
		VAR gw, gh, w, h, dsr: INTEGER; mask: Display3.Mask; name: ARRAY 64 OF CHAR;
	BEGIN
		gw := SHORT(LONG(gen.W) * 10000 DIV Printer.Unit);
		gh := SHORT(LONG(gen.H) * 10000 DIV Printer.Unit);
		Gadgets.MakePrinterMask(gen, msg.x, msg.y, msg.dlink, mask);
		Printer3.FilledRect3D(mask, Display3.bottomC, Display3.topC, Display3.textbackC, msg.x, msg.y, gw, gh, 1, Display.replace);
		GetGenerator(gen.obj, name);
		Printer3.StringSize(name, gen.font, w, h, dsr);
		Printer3.String(mask, Display3.textC, msg.x + (gw - w) DIV 2, msg.y + (gh - h) DIV 2 - dsr, gen.font, name, Display.paint);
		IF Gadgets.selected IN gen.state THEN
			Printer3.FillPattern(mask, Display3.white, Display3.selectpat, 0, 0, msg.x, msg.y, gw, gh, Display.paint)
		END
	END PrintGen;
	
	PROCEDURE HandleGen (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR gen, copy: GenFrame; x, y: INTEGER; mask: Display3.Mask; ver: LONGINT; fontName: ARRAY 32 OF CHAR;
	BEGIN
		gen := obj(GenFrame);
		IF msg IS Display.FrameMsg THEN
			WITH msg: Display.FrameMsg DO
				IF (msg.F = NIL) OR (msg.F = gen) THEN
					IF msg IS Display.DisplayMsg THEN
						WITH msg: Display.DisplayMsg DO
							x := msg.x + gen.X; y := msg.y + gen.Y;
							IF msg.device = Display.screen THEN
								IF (msg.id = Display.full) OR (msg.F = NIL) THEN
									Gadgets.MakeMask(gen, x, y, msg.dlink, mask);
									RestoreGen(gen, x, y, mask)
								ELSIF msg.id = Display.area THEN
									Gadgets.MakeMask(gen, x, y, msg.dlink, mask);
									Display3.AdjustMask(mask, x + msg.u, y + gen.H - 1 + msg.v, msg.w, msg.h);
									RestoreGen(gen, x, y, mask)
								END
							ELSIF msg.device = Display.printer THEN
								PrintGen(gen, msg)
							END
						END
					ELSE
						Gadgets.framehandle(gen, msg)
					END
				END
			END
		ELSIF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Font");
					Gadgets.framehandle(gen, msg)
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN
						msg.class := Objects.String; msg.s := "LeoPens.NewGen"; msg.res := 0
					ELSIF msg.name = "Font" THEN
						msg.class := Objects.String; COPY(gen.font.name, msg.s); msg.res := 0
					ELSE
						Gadgets.framehandle(gen, msg)
					END
				ELSIF (msg.id = Objects.set) & (msg.name = "Font") & (msg.class = Objects.String) THEN
					gen.font := Fonts.This(msg.s); msg.res := 0
				ELSE
					Gadgets.framehandle(gen, msg)
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # gen.stamp THEN
					NEW(copy); gen.dlink := copy; gen.stamp := msg.stamp;
					Gadgets.CopyFrame(msg, gen, copy);
					copy.font := gen.font
				END;
				msg.obj := gen.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Gadgets.framehandle(gen, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Files.WriteString(msg.R, gen.font.name)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 1 THEN
						Files.ReadString(msg.R, fontName);
						gen.font := Fonts.This(fontName)
					END
				END
			END
		ELSE
			Gadgets.framehandle(gen, msg)
		END
	END HandleGen;
	
	PROCEDURE InitGen (gen: GenFrame; obj: Objects.Object);
	BEGIN
		gen.handle := HandleGen; gen.W := 100; gen.H := 20; gen.obj := obj;
		gen.font := Fonts.Default
	END InitGen;
	
	PROCEDURE NewGen*;
		VAR gen: GenFrame;
	BEGIN
		NEW(gen); InitGen(gen, NIL);
		Objects.NewObj := gen
	END NewGen;
	
	
	(*--- Items & Riders ---*)
	
	PROCEDURE NewKey (): LONGINT;
	BEGIN
		INC(UniqueKey);
		RETURN UniqueKey
	END NewKey;
	
	PROCEDURE NewItem (name: ARRAY OF CHAR; key: LONGINT; pen: GfxPens.Pen): Item;
		VAR item: Item;
	BEGIN
		NEW(item); COPY(name, item.name); item.key := key; item.stamp := -1; item.pen := pen;
		RETURN item
	END NewItem;
	
	PROCEDURE NewTail (pen: GfxPens.Pen): Item;
		VAR item: Item;
	BEGIN
		NEW(item); item.key := -1; item.stamp := -1; item.pos := -1;
		item.next := item; item.prev := item;
		item.pen := pen;
		RETURN item
	END NewTail;
	
	PROCEDURE Append (tail, item: Item);
	BEGIN
		item.next := tail; item.prev := tail.prev;
		tail.prev := item; item.prev.next := item;
		item.pos := item.prev.pos+1
	END Append;
	
	PROCEDURE EnumAttr (name: ARRAY OF CHAR);
		VAR item: Item;
	BEGIN
		item := NewItem(name, NewKey(), EnumTail.pen); item.dsc := NIL;
		Append(EnumTail, item)
	END EnumAttr;
	
	PROCEDURE EnumLink (name: ARRAY OF CHAR);
		VAR lm: Objects.LinkMsg; item: Item;
	BEGIN
		lm.id := Objects.get; COPY(name, lm.name); lm.res := -1;
		EnumTail.pen.handle(EnumTail.pen, lm);
		IF (lm.res >= 0) & ((lm.obj = NIL) OR (lm.obj IS GfxPens.Pen)) THEN
			item := NewItem(name, NewKey(), EnumTail.pen);
			IF lm.obj = NIL THEN
				item.dsc := NewTail(NIL)
			ELSE
				item.dsc := NewTail(lm.obj(GfxPens.Pen))
			END;
			Append(EnumTail, item)
		END
	END EnumLink;
	
	PROCEDURE BuildItems (tail: Item);
		VAR lm: Objects.LinkMsg; am: Objects.AttrMsg;
	BEGIN
		ASSERT(tail.next = tail);
		IF tail.pen # NIL THEN
			EnumTail := tail;
			lm.id := Objects.enum; lm.Enum := EnumLink;
			tail.pen.handle(tail.pen, lm);
			am.id := Objects.enum; am.Enum := EnumAttr;
			tail.pen.handle(tail.pen, am)
		END
	END BuildItems;
	
	PROCEDURE SetItem (r: ListRiders.Rider; item: Item);
	BEGIN
		r.d := item; r.eol := item.key < 0; r.dsc := item.dsc # NIL
	END SetItem;
	
	PROCEDURE ConnectRider (r: ListRiders.Rider; base: Model);
	BEGIN
		r.do := RMethods; r.base := base;
		SetItem(r, base.tail.next)
	END ConnectRider;
	
	PROCEDURE Key (r: ListRiders.Rider): LONGINT;
	BEGIN
		RETURN r.d(Item).key
	END Key;
	
	PROCEDURE Seek (r: ListRiders.Rider; key: LONGINT);
		PROCEDURE findItem (tail: Item; key: LONGINT): Item;
			VAR item, found: Item;
		BEGIN
			item := tail.next;
			WHILE (item # tail) & (item.key # key) DO
				IF item.dsc = NIL THEN
					item := item.next
				ELSE
					found := findItem(item.dsc, key);
					IF found.key = key THEN
						item := found
					ELSE
						item := item.next
					END
				END
			END;
			RETURN item
		END findItem;
	BEGIN
		SetItem(r, findItem(r.base(Model).tail, key))
	END Seek;
	
	PROCEDURE Pos (r: ListRiders.Rider): LONGINT;
	BEGIN
		RETURN r.d(Item).pos
	END Pos;
	
	PROCEDURE Set (r: ListRiders.Rider; pos: LONGINT);
		VAR item: Item;
	BEGIN
		item := r.d(Item);
		IF item.pos > pos THEN
			REPEAT item := item.prev UNTIL (item.pos = pos) OR (item.key < 0)
		ELSIF item.pos < pos THEN
			REPEAT item := item.next UNTIL (item.pos = pos) OR (item.key < 0)
		END;
		SetItem(r, item)
	END Set;
	
	PROCEDURE Write (r: ListRiders.Rider; data: ListRiders.Data);
	END Write;
	
	PROCEDURE WriteLink (r, link: ListRiders.Rider);
	END WriteLink;
	
	PROCEDURE DeleteLink (r, link: ListRiders.Rider);
	END DeleteLink;
	
	PROCEDURE Desc (r, old: ListRiders.Rider): ListRiders.Rider;
		VAR new: ListRiders.Rider; item: Item;
	BEGIN
		IF (old = NIL) THEN NEW(new) ELSE new := old END;
		new.do := r.do; new.base := r.base;
		item := r.d(Item);
		IF ~r.eol & (item.dsc # NIL) THEN
			item := item.dsc;
			IF item.next = item THEN	(* empty *)
				BuildItems(item)
			END;
			item := item.next
		END;
		SetItem(new, item);
		RETURN new
	END Desc;
	
	PROCEDURE State (r: ListRiders.Rider): LONGINT;
	BEGIN
		RETURN r.d(Item).state
	END State;
	
	PROCEDURE SetState (r: ListRiders.Rider; state: LONGINT);
	BEGIN
		r.d(Item).state := state
	END SetState;
	
	PROCEDURE GetStamp (r: ListRiders.Rider): LONGINT;
	BEGIN
		RETURN r.d(Item).stamp
	END GetStamp;
	
	PROCEDURE SetStamp (r: ListRiders.Rider; stamp: LONGINT);
	BEGIN
		r.d(Item).stamp := stamp
	END SetStamp;
	
	PROCEDURE InitRiders;
	BEGIN
		NEW(RMethods);
		RMethods.Key := Key; RMethods.Seek := Seek; RMethods.Pos := Pos; RMethods.Set := Set;
		RMethods.Write := Write; RMethods.WriteLink := WriteLink; RMethods.DeleteLink := DeleteLink;
		RMethods.State := State; RMethods.SetState := SetState;
		RMethods.Desc := Desc;
		RMethods.GetStamp := GetStamp; RMethods.SetStamp := SetStamp
	END InitRiders;
	
	
	(*--- Model ---*)
	
	PROCEDURE ModelHandler (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR model, copy: Model; ver: LONGINT; r: ListRiders.Rider;
	BEGIN
		model := obj(Model);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF (msg.id = Objects.get) & (msg.name = "Gen") THEN
					msg.class := Objects.String; msg.s := "LeoPens.NewModel"; msg.res := 0
				ELSE
					Gadgets.objecthandle(model, msg)
				END
			END
		ELSIF msg IS Objects.LinkMsg THEN
			LinkRef(msg(Objects.LinkMsg), "Pen", TRUE, model.tail.pen);
			Gadgets.objecthandle(model, msg)
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # model.stamp THEN
					NEW(copy); model.dlink := copy; model.stamp := msg.stamp;
					copy.tail := NewTail(model.tail.pen);
					IF msg.id = Objects.deep THEN CopyRef(msg, model.tail.pen, copy.tail.pen) END;
					BuildItems(model.tail);
					copy.key := 0
				END;
				msg.obj := copy.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			IF model.tail.pen # NIL THEN
				Bind(model.tail.pen, msg(Objects.BindMsg).lib)
			END;
			Gadgets.objecthandle(model, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Gadgets.objecthandle(model, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					WriteRef(msg.R, model.lib, model.tail.pen)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 1 THEN
						model.tail.next := model.tail; model.tail.prev := model.tail;
						ReadRef(msg.R, model.lib, model.tail.pen);
						BuildItems(model.tail)
					END
				END
			END
		ELSIF msg IS ListRiders.ConnectMsg THEN
			NEW(r); ConnectRider(r, model);
			msg(ListRiders.ConnectMsg).R := r
		ELSE
			Gadgets.objecthandle(model, msg)
		END
	END ModelHandler;
	
	PROCEDURE InitModel (model: Model; pen: GfxPens.Pen);
	BEGIN
		model.handle := ModelHandler; model.key := 0; model.tail := NewTail(pen);
		BuildItems(model.tail)
	END InitModel;
	
	PROCEDURE NewModel*;
		VAR model: Model;
	BEGIN
		NEW(model); InitModel(model, NIL);
		Objects.NewObj := model
	END NewModel;
	
	
	(*--- List Gadget ---*)
	
	PROCEDURE FormatLine (list: ListGadgets.Frame; r: ListRiders.Rider; line: ListGadgets.Line);
		VAR item: Item; pict: Pictures.Picture;
	BEGIN
		item := r.d(Item);
		Display3.StringSize(item.name, list.fnt, line.w, line.h, line.dsr);
		IF item.dsc # NIL THEN
			IF line.folded THEN pict := FoldedPict ELSE pict := UnfoldedPict END;
			IF pict.height+2 > line.h THEN line.h := pict.height+2 END
		END;
		line.dx := PictWidth + 2 + line.lev * list.tab
	END FormatLine;
	
	PROCEDURE DisplayLine (list: ListGadgets.Frame; mask: Display3.Mask; x, y, w, h: INTEGER; r: ListRiders.Rider; line: ListGadgets.Line);
		VAR item: Item; pict: Pictures.Picture;
	BEGIN
		Display3.ReplConst(mask, list.backC, x, y, w, h, Display.replace);
		INC(x, line.lev * list.tab);
		item := r.d(Item);
		IF item.dsc # NIL THEN
			IF line.folded THEN pict := FoldedPict ELSE pict := UnfoldedPict END;
			Display3.Pict(mask, pict, 0, 0, w, h, x, y + (h - pict.height) DIV 2, Display.replace)
		END;
		INC(x, PictWidth+2);
		Display3.String(mask, list.textC, x, y + line.dsr, list.fnt, item.name, Display.paint)
	END DisplayLine;
	
	PROCEDURE P (x: LONGINT): INTEGER;
	BEGIN
		RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;
	
	PROCEDURE PrintFormatLine (list: ListGadgets.Frame; r: ListRiders.Rider; line: ListGadgets.Line);
		VAR item: Item; pict: Pictures.Picture;
	BEGIN
		item := r.d(Item);
		Printer3.StringSize(item.name, list.fnt, line.w, line.h, line.dsr);
		IF item.dsc # NIL THEN
			IF line.folded THEN pict := FoldedPict ELSE pict := UnfoldedPict END;
			IF P(pict.height+2) > line.h THEN line.h := P(pict.height+2) END
		END;
		line.dx := P(PictWidth + 2 + line.lev * list.tab)
	END PrintFormatLine;
	
	PROCEDURE PrintLine (list: ListGadgets.Frame; mask: Display3.Mask; x, y, w, h: INTEGER; r: ListRiders.Rider; line: ListGadgets.Line);
		VAR item: Item; pict: Pictures.Picture;
	BEGIN
		Printer3.ReplConst(mask, list.backC, x, y, w, h, Display.replace);
		INC(x, P(line.lev * list.tab));
		item := r.d(Item);
		IF item.dsc # NIL THEN
			IF line.folded THEN pict := FoldedPict ELSE pict := UnfoldedPict END;
			Printer3.Pict(mask, pict, x, y + (h - P(pict.height)) DIV 2, P(pict.width), P(pict.height), Display.replace)
		END;
		INC(x, P(PictWidth+2));
		Printer3.String(mask, list.textC, x, y + line.dsr, list.fnt, item.name, Display.paint)
	END PrintLine;
	
	PROCEDURE RemoveEditor (ctxt: Objects.Object);
		VAR obj: Objects.Object; ocm: Oberon.ControlMsg; dcm: Display.ControlMsg;
	BEGIN
		obj := Gadgets.FindObj(ctxt, EditorName);
		IF (obj # NIL) & (obj IS Display.Frame) THEN
			ocm.F := obj(Display.Frame); ocm.id := Oberon.defocus;
			Display.Broadcast(ocm);
			dcm.F := obj(Display.Frame); dcm.id := Display.remove;
			Display.Broadcast(dcm)
		END
	END RemoveEditor;
	
	PROCEDURE Integrate (obj, ctxt: Objects.Object);
		VAR cm: Display.ConsumeMsg;
	BEGIN
		IF obj # NIL THEN
			Attributes.SetString(obj, "Name", EditorName);
			cm.F := ctxt(Display.Frame); cm.id := Display.drop; cm.u := 0; cm.v := 0; cm.obj := obj;
			Display.Broadcast(cm)
		END
	END Integrate;
	
	PROCEDURE GetSelData (list: ListGadgets.Frame; VAR item: Item);
		VAR am: Objects.AttrMsg; model: Objects.Object; cm: ListRiders.ConnectMsg; r: ListRiders.Rider;
	BEGIN
		item := NIL;
		am.id := Objects.get; am.name := "SelKey"; am.res := -1;
		list.handle(list, am);
		IF (am.res >= 0) & (am.class = Objects.Int) & (am.i >= 0) & (list.obj # NIL) THEN
			model := list.obj;
			Objects.Stamp(cm); cm.R := NIL;
			model.handle(model, cm);
			r := cm.R;
			IF r # NIL THEN
				r.do.Seek(r, am.i);
				item := r.d(Item)
			END
		END
	END GetSelData;
	
	PROCEDURE InsertEditor (frame: ListGadgets.Frame; ctxt: Objects.Object);
		VAR
			item: Item;
			gen: GenFrame;
			lm: Objects.LinkMsg; am: Objects.AttrMsg;
			i: LONGINT; x: REAL; b: BOOLEAN; s: ARRAY 64 OF CHAR;
			obj, link: Objects.Object;
	BEGIN
		RemoveEditor(ctxt);
		GetSelData(frame, item);
		IF item = NIL THEN
			NEW(gen); InitGen(gen, frame.obj(Model).tail.pen);
			Attributes.SetString(gen, "Constraints", "0 -20 0 0");
			Integrate(gen, ctxt)
		ELSE
			IF item.dsc # NIL THEN
				IF item.obj = NIL THEN
					lm.id := Objects.get; COPY(item.name, lm.name); lm.obj := NIL; lm.res := -1;
					item.pen.handle(item.pen, lm);
					item.obj := lm.obj
				END;
				NEW(gen); InitGen(gen, item.obj);
				Attributes.SetString(gen, "Constraints", "0 -20 0 0");
				Integrate(gen, ctxt)
			ELSE
				am.id := Objects.get; COPY(item.name, am.name); am.class := Objects.Inval; am.res := -1;
				item.pen.handle(item.pen, am);
				CASE am.class OF
				| Objects.Int:
					IF item.obj = NIL THEN
						item.obj := Gadgets.CreateObject("Integer");
						Attributes.SetInt(item.obj, "Value", am.i)
					END;
					i := 0;
					Strings.CAPSearch("color", am.name, i);
					IF i >= 0 THEN	(* assume attribute to be a color index *)
						obj := Gadgets.CreateObject("ColorWells.NewColorWell");
						Attributes.SetString(obj, "Constraints", "0 -20 x 0");
					ELSE
						obj := Gadgets.CreateObject("TextField");
						Attributes.SetString(obj, "Constraints", "0 -20 0 0")
					END;
					Links.SetLink(obj, "Model", item.obj);
					Attributes.GetInt(item.obj, "Value", i);
					Attributes.SetInt(obj, "Value", i);
					Integrate(obj, ctxt)
				| Objects.Real:
					IF item.obj = NIL THEN
						item.obj := Gadgets.CreateObject("Real");
						Attributes.SetReal(item.obj, "Value", am.x)
					END;
					obj := Gadgets.CreateObject("TextField");
					Attributes.SetString(obj, "Constraints", "0 -20 0 0");
					Links.SetLink(obj, "Model", item.obj);
					Attributes.GetReal(item.obj, "Value", x);
					Attributes.SetReal(obj, "Value", x);
					Integrate(obj, ctxt)
				| Objects.Bool:
					IF item.obj = NIL THEN
						item.obj := Gadgets.CreateObject("Boolean");
						Attributes.SetBool(item.obj, "Value", am.b)
					END;
					obj := Gadgets.CreateObject("CheckBox");
					Attributes.SetString(obj, "Constraints", "0 -20 x 0");
					Links.SetLink(obj, "Model", item.obj);
					Attributes.GetBool(item.obj, "Value", b);
					Attributes.SetBool(obj, "Value", b);
					Integrate(obj, ctxt)
				| Objects.String:
					IF item.obj = NIL THEN
						item.obj := Gadgets.CreateObject("String");
						Attributes.SetString(item.obj, "Value", am.s)
					END;
					obj := Gadgets.CreateObject("TextField");
					Attributes.SetString(obj, "Constraints", "0 -20 0 0");
					Links.SetLink(obj, "Model", item.obj);
					Attributes.GetString(item.obj, "Value", s);
					Attributes.SetString(obj, "Value", s);
					Integrate(obj, ctxt)
				ELSE
				END
			END
		END
	END InsertEditor;
	
	PROCEDURE SetPen (list: ListGadgets.Frame; pen: GfxPens.Pen);
		VAR model: Model; ocm: Oberon.ControlMsg;
	BEGIN
		RemoveEditor(Gadgets.context);
		ASSERT((list.obj # NIL) & (list.obj IS Model));
		model := list.obj(Model);
		model.tail.next := model.tail; model.tail.prev := model.tail;
		model.tail.pen := pen;
		BuildItems(model.tail);
		Gadgets.Update(model);
		ocm.F := list; ocm.id := Oberon.neutralize;
		Display.Broadcast(ocm)	(* force display of pen generator *)
	END SetPen;
	
	PROCEDURE ReplacePen (list: ListGadgets.Frame; item: Item; pen: GfxPens.Pen);
		VAR line, l: ListGadgets.Line; n: INTEGER; obj: Objects.Object;
	BEGIN
		line := list.lines;
		REPEAT
			line := line.next
		UNTIL line.key = item.key;
		IF ~line.folded THEN	(* oops! fold line before exchanging pen; code taken from ListGadgets.ToggleLine *)
			l := line.next;
			WHILE l.lev > line.lev DO l := l.next END;
			line.next := l; l.prev := line;
			l := line; n := l.n;
			WHILE l # list.lines DO
				l.n := n; INC(n);
				l := l.next
			END;
			line.folded := TRUE;
			Links.GetLink(list, "VRange", obj);
			IF obj # NIL THEN
				Attributes.SetInt(obj, "Value", n-1);
				Gadgets.Update(obj)
			END
		END;
		item.dsc.next := item.dsc; item.dsc.prev := item.dsc; item.dsc.pen := pen; item.obj := pen;
		line.sel := FALSE;
		Gadgets.Update(list);
		InsertEditor(list, Gadgets.context)
	END ReplacePen;
	
	PROCEDURE HandleListGadget (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR frame: ListGadgets.Frame;
	BEGIN
		frame := obj(ListGadgets.Frame);
		IF msg IS Display.FrameMsg THEN
			WITH msg: Display.FrameMsg DO
				IF (msg.F = NIL) OR (msg.F = frame) THEN
					IF msg IS Oberon.InputMsg THEN
						WITH msg: Oberon.InputMsg DO
							IF msg.id = Oberon.track THEN
								IF msg.keys = {0} THEN
									ListGadgets.FrameHandler(frame, msg);
									InsertEditor(frame, msg.dlink)
								ELSIF msg.keys = {1} THEN
									ListGadgets.FrameHandler(frame, msg)	(* need this to expand on links *)
								ELSE
									Gadgets.framehandle(frame, msg)
								END
							END
						END
					ELSIF msg IS Oberon.ControlMsg THEN
						WITH msg: Oberon.ControlMsg DO
							ListGadgets.FrameHandler(frame, msg);
							IF msg.id = Oberon.neutralize THEN
								InsertEditor(frame, msg.dlink)
							END
						END
					ELSIF msg IS Display.ControlMsg THEN
						WITH msg: Display.ControlMsg DO
							ListGadgets.FrameHandler(frame, msg);
							IF msg.id = Display.restore THEN
								InsertEditor(frame, msg.dlink)
							END
						END
					ELSE
						ListGadgets.FrameHandler(frame, msg)
					END
				END
			END
		ELSIF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF (msg.id = Objects.get) & (msg.name = "Gen") THEN
					msg.class := Objects.String; msg.s := "LeoPens.NewListGadget"; msg.res := 0
				ELSE
					ListGadgets.FrameHandler(frame, msg)
				END
			END
		ELSE
			ListGadgets.FrameHandler(frame, msg)
		END
	END HandleListGadget;
	
	PROCEDURE NewListGadget*;
		VAR list: ListGadgets.Frame;
	BEGIN
		NEW(list); ListGadgets.InitFrame(list);
		list.handle := HandleListGadget; list.do := FMethods;
		list.tab := 8; list.state0 := list.state0 - {ListGadgets.multisel} + {ListGadgets.locked};
		Objects.NewObj := list
	END NewListGadget;
	
	PROCEDURE InitListGadgets;
		VAR lib: Objects.Library; ref: INTEGER; obj: Objects.Object;
	BEGIN
		NEW(FMethods);
		FMethods.GetRider := ListGadgets.GetStandardRider;
		FMethods.Format := FormatLine; FMethods.Display := DisplayLine;
		FMethods.PrintFormat := PrintFormatLine; FMethods.Print := PrintLine;
		
		lib := Objects.ThisLibrary("Leonardo.Lib");
		IF lib # NIL THEN
			Objects.GetRef(lib.dict, "FoldedPict", ref);
			IF ref # MIN(INTEGER) THEN
				lib.GetObj(lib, ref, obj);
				IF (obj # NIL) & (obj IS Pictures.Picture) THEN
					FoldedPict := obj(Pictures.Picture)
				END
			END;
			Objects.GetRef(lib.dict, "UnfoldedPict", ref);
			IF ref # MIN(INTEGER) THEN
				lib.GetObj(lib, ref, obj);
				IF (obj # NIL) & (obj IS Pictures.Picture) THEN
					UnfoldedPict := obj(Pictures.Picture)
				END
			END
		END;
		IF FoldedPict = NIL THEN
			NEW(FoldedPict); Pictures.Create(FoldedPict, 16, 16, Pictures.colorD)
		END;
		IF UnfoldedPict = NIL THEN
			NEW(UnfoldedPict); Pictures.Create(UnfoldedPict, 16, 16, Pictures.colorD)
		END;
		IF FoldedPict.width > UnfoldedPict.width THEN PictWidth := FoldedPict.width
		ELSE PictWidth := UnfoldedPict.width
		END
	END InitListGadgets;
	
	
	(**--- Pen List Commands ---**)
	
	PROCEDURE GetList (VAR s: Attributes.Scanner; VAR list: ListGadgets.Frame);
		VAR obj: Objects.Object;
	BEGIN
		list := NIL;
		Attributes.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(s);
		IF s.class = Attributes.Name THEN
			obj := Gadgets.FindObj(Gadgets.context, s.s);
			IF (obj # NIL) & (obj IS ListGadgets.Frame) THEN
				list := obj(ListGadgets.Frame)
			END
		END
	END GetList;
	
	PROCEDURE GetSelLink (link: ARRAY OF CHAR; VAR pen: GfxPens.Pen; VAR valid: BOOLEAN);
		VAR fig: Figures.Figure; sel: Figures.Shape; lm: Objects.LinkMsg; obj: Objects.Object;
	BEGIN
		pen := NIL; valid := FALSE;
		Leonardo.FindFigure(fig);
		IF fig # NIL THEN
			Figures.GetSelection(fig, sel);
			IF sel # NIL THEN
				lm.id := Objects.get; COPY(link, lm.name);
				obj := sel;
				WHILE obj # NIL DO
					lm.res := -1; obj.handle(obj, lm);
					IF (lm.res >= 0) & (lm.obj # NIL) & (lm.obj IS GfxPens.Pen) THEN
						IF pen = NIL THEN
							pen := lm.obj(GfxPens.Pen); valid := TRUE
						ELSIF pen # lm.obj THEN
							valid := FALSE
						END
					END;
					obj := obj.slink
				END
			END
		END
	END GetSelLink;
	
	PROCEDURE GetPen (VAR s: Attributes.Scanner; VAR pen: GfxPens.Pen; VAR valid: BOOLEAN);
	BEGIN
		valid := FALSE;
		Attributes.Scan(s);
		IF s.class IN {Attributes.Name, Attributes.String} THEN
			IF s.s = "Def Filler" THEN
				pen := Filler; valid := TRUE
			ELSIF s.s = "Def Stroker" THEN
				pen := Stroker; valid := TRUE
			ELSIF s.s = "Sel Filler" THEN
				GetSelLink("FillPen", pen, valid)
			ELSIF s.s = "Sel Stroker" THEN
				GetSelLink("StrokePen", pen, valid)
			END
		END
	END GetPen;
	
	PROCEDURE GetNewPen (VAR s: Attributes.Scanner; VAR pen: GfxPens.Pen; VAR valid: BOOLEAN);
		VAR obj: Objects.Object;
	BEGIN
		valid := FALSE;
		Attributes.Scan(s);
		IF s.class IN {Attributes.Name, Attributes.String} THEN
			IF s.s = "NIL" THEN
				pen := NIL; valid := TRUE
			ELSE
				obj := Gadgets.CreateObject(s.s);
				IF (obj # NIL) & (obj IS GfxPens.Pen) THEN
					pen := obj(GfxPens.Pen); valid := TRUE
				END
			END
		END
	END GetNewPen;
	
	PROCEDURE ApplyAttr (model: Model);
		VAR changed: BOOLEAN;
		
		PROCEDURE copy (VAR pen: GfxPens.Pen);
			VAR cm: Objects.CopyMsg;
		BEGIN
			Objects.Stamp(cm); cm.id := Objects.shallow; cm.obj := pen;
			pen.handle(pen, cm);
			IF (cm.obj # NIL) & (cm.obj IS GfxPens.Pen) THEN
				pen := cm.obj(GfxPens.Pen)
			END
		END copy;
		
		PROCEDURE traverse (tail: Item; VAR changed: BOOLEAN);
			VAR item: Item; pen: GfxPens.Pen; am: Objects.AttrMsg; c: BOOLEAN; lm: Objects.LinkMsg;
		BEGIN
			item := tail.next; changed := FALSE; pen := tail.pen;
			WHILE item # tail DO
				IF item.dsc = NIL THEN
					IF item.obj # NIL THEN
						IF ~changed THEN
							copy(pen);
							changed := TRUE
						END;
						am.id := Objects.get; am.name := "Value"; am.res := -1;
						item.obj.handle(item.obj, am);
						IF am.res >= 0 THEN
							IF am.class = Objects.LongReal THEN am.class := Objects.Real; am.x := SHORT(am.y) END;
							am.id := Objects.set; COPY(item.name, am.name); am.res := -1;
							pen.handle(pen, am)
						END
					END
				ELSE
					traverse(item.dsc, c);
					IF c OR (item.obj # NIL) THEN
						IF ~changed THEN
							copy(pen);
							changed := TRUE
						END;
						item.obj := item.dsc.pen; changed := TRUE;
						lm.id := Objects.set; COPY(item.name, lm.name); lm.obj := item.obj; lm.res := -1;
						pen.handle(pen, lm)
					END
				END;
				item := item.next
			END;
			tail.pen := pen
		END traverse;
		
	BEGIN
		traverse(model.tail, changed)
	END ApplyAttr;
	
	PROCEDURE DoSetPen (fig: Figures.Figure; act: Figures.Action; stamp: LONGINT; undo: BOOLEAN);
		VAR a: PenAction; lm: Objects.LinkMsg; old: Objects.Object;
	BEGIN
		a := act(PenAction);
		lm.id := Objects.get; COPY(a.name, lm.name); lm.res := -1; lm.obj := NIL;
		a.shape.handle(a.shape, lm);
		old := lm.obj; lm.obj := a.pen; a.pen := old;
		lm.id := Objects.set; lm.res := -1;
		a.shape.handle(a.shape, lm);
		IF lm.res >= 0 THEN
			a.shape.stamp := stamp; a.shape(Figures.Shape).sel := TRUE
		END
	END DoSetPen;
	
	PROCEDURE ApplySel (dest: LONGINT; pen: GfxPens.Pen);
		VAR fig: Figures.Figure; sel: Figures.Shape; cm: ChangeMsg; obj: Objects.Object; a: PenAction;
	BEGIN
		Leonardo.FindFigure(fig);
		IF fig # NIL THEN
			Figures.GetSelection(fig, sel);
			IF sel # NIL THEN
				Figures.DisableUpdate(fig);
				Figures.BeginCommand(fig);
				cm.fig := fig; cm.id := Replace; cm.dest := {dest}; cm.pen[dest] := pen;
				obj := sel;
				WHILE obj # NIL DO
					cm.res := -1;
					obj.handle(obj, cm);
					IF cm.res < 0 THEN
						NEW(a); a.shape := obj; a.pen := pen;
						IF dest = StrokePen THEN a.name := "StrokePen" ELSE a.name := "FillPen" END;
						Figures.AddAction(fig, a, DoSetPen)
					END;
					obj := obj.slink
				END;
				Figures.EndCommand(fig);
				Figures.EnableUpdate(fig)
			END
		END
	END ApplySel;
	
	PROCEDURE Apply (VAR s: Attributes.Scanner; pen: GfxPens.Pen);
	BEGIN
		Attributes.Scan(s);
		IF s.class IN {Attributes.Name, Attributes.String} THEN
			IF s.s = "Def Filler" THEN
				Filler := pen
			ELSIF s.s = "Def Stroker" THEN
				Stroker := pen
			ELSIF s.s = "Sel Filler" THEN
				ApplySel(FillPen, pen)
			ELSIF s.s = "Sel Stroker" THEN
				ApplySel(StrokePen, pen)
			END
		END
	END Apply;
	
	PROCEDURE EditPen*;
		VAR s: Attributes.Scanner; list: ListGadgets.Frame; pen: GfxPens.Pen; valid: BOOLEAN;
	BEGIN
		GetList(s, list);
		IF list # NIL THEN
			GetPen(s, pen, valid);
			IF valid THEN
				SetPen(list, pen)
			END
		END
	END EditPen;
	
	PROCEDURE LinkPen*;
		VAR s: Attributes.Scanner; list: ListGadgets.Frame; item: Item; pen: GfxPens.Pen; valid: BOOLEAN;
	BEGIN
		GetList(s, list);
		IF list # NIL THEN
			GetSelData(list, item);
			IF (item # NIL) & (item.dsc # NIL) THEN
				GetPen(s, pen, valid);
				IF valid THEN
					ReplacePen(list, item, pen)
				END
			END
		END
	END LinkPen;
	
	PROCEDURE ApplyPen*;
		VAR s: Attributes.Scanner; list: ListGadgets.Frame; model: Model;
	BEGIN
		GetList(s, list);
		IF list # NIL THEN
			model := list.obj(Model);
			ApplyAttr(model);
			Apply(s, model.tail.pen)
		END
	END ApplyPen;
	
	PROCEDURE NewPen*;
		VAR s: Attributes.Scanner; list: ListGadgets.Frame; pen: GfxPens.Pen; valid: BOOLEAN;
	BEGIN
		GetList(s, list);
		IF list # NIL THEN
			GetNewPen(s, pen, valid);
			IF valid THEN
				SetPen(list, pen)
			END
		END
	END NewPen;
	
	PROCEDURE LinkNewPen*;
		VAR s: Attributes.Scanner; list: ListGadgets.Frame; item: Item; pen: GfxPens.Pen; valid: BOOLEAN;
	BEGIN
		GetList(s, list);
		IF list # NIL THEN
			GetSelData(list, item);
			IF (item # NIL) & (item.dsc # NIL) THEN
				GetNewPen(s, pen, valid);
				IF valid THEN
					ReplacePen(list, item, pen)
				END
			END
		END
	END LinkNewPen;
	
	PROCEDURE EnterAliases;
		PROCEDURE enter (alias, gen: ARRAY OF CHAR);
			VAR val: ARRAY 64 OF CHAR;
		BEGIN
			Gadgets.GetAlias(alias, val);
			IF val = "" THEN
				Gadgets.AddAlias(alias, gen)
			END
		END enter;
	BEGIN
		enter("SolidStroker", "GfxPens.NewSolidStroker");
		enter("SolidFiller", "GfxPens.NewSolidFiller");
		enter("Dasher", "GfxPens.NewDasher");
		enter("Splitter", "GfxPens.NewSplitter");
		enter("Forker", "GfxPens.NewForker");
		enter("Reverser", "GfxPens.NewReverser");
		enter("Arrow", "GfxPens.NewArrow");
		enter("Outliner", "GfxPens.NewOutliner");
		enter("EasyPen", "GfxPens.NewEasyPen")
	END EnterAliases;
	

BEGIN
	GfxPens.NewSolidFiller; Filler := Objects.NewObj(GfxPens.Pen);
	GfxPens.NewSolidStroker; Stroker := Objects.NewObj(GfxPens.Pen);
	InitRiders;
	InitListGadgets;
	UniqueKey := -1;
	EnterAliases
END LeoPens.
