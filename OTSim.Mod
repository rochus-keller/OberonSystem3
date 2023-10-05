MODULE OTSim;	(** eos   **)

	(**
		TrueType instruction simulator
	**)
	
	IMPORT
		Kernel, Files, Display, Input, Objects, Fonts, Texts, Pictures, Oberon, Display3, Attributes, Gadgets,
		Coroutines, OType, OTInt, OTScan;
		
	
	CONST
		ModelName = "Model";
		
		Loading = 1; Loaded = 2; Instantiating = 3; Instantiated = 4; Hinting = 5; Hinted = 6;	(* model states *)
		ExecStates = {Loading, Instantiating, Hinting};	(* states during which instructions are executed *)
		
		LogText = 0; Code = 1; Stack = 2; CVT = 3; Store = 4; Points = 5;	(* multiview modes *)
		MVLineH = 14; MVLineY = 4; MVScrollW = 20; MVScrollH = 10;
		
		X = OTInt.X; Y = OTInt.Y;
		
		DebugStackSize = 10000H;
		
	
	TYPE
		Model = POINTER TO ModelDesc;
		Procedure = PROCEDURE (model: Model);
		
		Coroutine = POINTER TO CorDesc;
		CorDesc = RECORD (Coroutines.CorDesc)
			model: Model;
			proc: Procedure;	(* current procedure *)
		END;
		
		NotifierData = POINTER TO NotifierDesc;
		NotifierDesc = RECORD (OTInt.NotifierDesc)
			model: Model;
		END;
		
		ModelDesc = RECORD (Gadgets.ObjDesc)
			state: INTEGER;
			cor: Coroutine;
			data: NotifierData;
			fileName: ARRAY 64 OF CHAR;
			font: OType.Font;
			xMin, yMin, xMax, yMax: INTEGER;
			numGlyphs: Objects.Object;
			upm: INTEGER;
			ptsize: LONGINT;
			xdpi, ydpi: INTEGER;
			inst: OType.Instance;
			glyphNo: INTEGER;
			glyph: OType.Glyph;
			log: Texts.Text;
			debugFontProg, debugCVTProg, debugGlyphProg: BOOLEAN;
			hinted: BOOLEAN;
			fixDropouts: BOOLEAN;
			scanType: INTEGER;
			context: OTInt.Context;
			breakCode: OTInt.Code;
			breakPC: LONGINT;
			breakInstr: CHAR;
		END;
		
		PosArray = POINTER TO ARRAY OF LONGINT;
		
		Multiview = POINTER TO MultiviewDesc;
		MultiviewDesc = RECORD (Gadgets.FrameDesc)
			mode: INTEGER;
			start, end, lines, len: LONGINT;
			pos: PosArray;
			model: Model;
			code: OTInt.Code;
			clen: LONGINT;
		END;
		
		GlyphView = POINTER TO GlyphViewDesc;
		GlyphViewDesc = RECORD (Gadgets.FrameDesc)
			pixW, pixH: INTEGER;	(* number of display pixels per font pixel *)
			minX, minY: LONGINT;	(* offset in font pixels *)
			left, right, bot, top: INTEGER;	(* border widths *)
			showGrid, showPattern, showOutline, showTwilight, showPoints: BOOLEAN;
		END;
		
		ScanData = RECORD (OTScan.EnumData)
			x, y: OTInt.F26D6;
			w, h: INTEGER;
		END;
		
		Char = POINTER TO CharDesc;
		CharDesc = RECORD (Gadgets.ObjDesc)
			val: CHAR;
		END;
		
	
	VAR
		W: Texts.Writer;
		DummyModel: Model;
		Buffer: Pictures.Picture;
		MVFont, GVFont: Fonts.Font;
		GVPict: Pictures.Picture;
		EvenRowPat, OddRowPat, EvenColPat, OddColPat: Display.Pattern;
		InstrStr: ARRAY 2048 OF CHAR;	(* instruction mnemonics *)
		InstrIdx: ARRAY 100H OF INTEGER;	(* index into InstrStr *)
		Arg: ARRAY 100H OF SHORTINT;	(* number of arguments per instruction *)
		
	
	(*--- Conversions ---*)
	
	PROCEDURE HexToStr (x, n: LONGINT; VAR s: ARRAY OF CHAR; pos: LONGINT);
		VAR i, d: LONGINT;
	BEGIN
		i := 28; n := 4*n;
		WHILE (i > 0) & (i >= n) & (ASH(x, -i) MOD 10H = 0) DO DEC(i, 4) END;
		WHILE (i >= 0) & (pos < LEN(s)-1) DO
			d := ASH(x, -i) MOD 10H;
			IF d < 10 THEN s[pos] := CHR(ORD("0") + d)
			ELSE s[pos] := CHR(ORD("A") - 10 + d)
			END;
			DEC(i, 4); INC(pos)
		END;
		s[pos] := 0X
	END HexToStr;
	
	PROCEDURE F26D6ToStr (x, n: LONGINT; VAR s: ARRAY OF CHAR; pos: LONGINT);
		VAR y, i, j: LONGINT; d: ARRAY 6 OF INTEGER;
	BEGIN
		IF x < 0 THEN x := -x; s[pos] := "-" ELSE s[pos] := " " END; INC(pos);
		y := x DIV 40H;
		i := 7; j := 10000000;
		WHILE (i > 0) & (i >= n) & (y DIV j = 0) DO DEC(i); j := j DIV 10 END;
		WHILE (i >= 0) & (pos < LEN(s)-1) DO
			s[pos] := CHR(ORD("0") + (y DIV j) MOD 10);
			DEC(i); j := j DIV 10; INC(pos)
		END;
		x := x MOD 40H;
		IF x # 0 THEN
			FOR i := 0 TO 5 DO d[i] := 0 END;
			IF x > 20H THEN d[0] := 5; DEC(x, 20H) END;
			IF x > 10H THEN INC(d[0], 2); d[1] := 5; DEC(x, 10H) END;
			IF x > 8 THEN INC(d[0], 1); INC(d[1], 2); d[2] := 5; DEC(x, 8) END;
			IF x > 4 THEN INC(d[1], 6); INC(d[2], 2); d[3] := 5; DEC(x, 4) END;
			IF x > 2 THEN INC(d[1], 3); INC(d[2], 1); INC(d[3], 2); d[4] := 5; DEC(x, 2) END;
			IF x > 1 THEN INC(d[1], 1); INC(d[2], 5); INC(d[3], 6); INC(d[4], 2); d[5] := 5 END;
			IF pos < LEN(s)-1 THEN s[pos] := "."; INC(pos) END;
			i := 5; WHILE (i >= 0) & (d[i] = 0) DO DEC(i) END;
			IF pos + i >= LEN(s)-1 THEN i := LEN(s) - pos - 1 END;
			WHILE i >= 0 DO
				IF d[i] >= 10 THEN INC(d[i-1]); DEC(d[i], 10) END;
				s[pos] := CHR(ORD("0") + d[i]);
				INC(pos); DEC(i)
			END
		END;
		s[pos] := 0X
	END F26D6ToStr;
	
	
	(*--- Logging ---*)
	
	PROCEDURE Str (s: ARRAY OF CHAR);
	BEGIN
		Texts.WriteString(W, s)
	END Str;
	
	PROCEDURE Int (i: LONGINT);
	BEGIN
		Texts.WriteInt(W, i, 0)
	END Int;
	
	PROCEDURE Hex (x, n: LONGINT);
		VAR s: ARRAY 9 OF CHAR;
	BEGIN
		HexToStr(x, n, s, 0);
		Texts.WriteString(W, s)
	END Hex;
	
	PROCEDURE Log (model: Model);
	BEGIN
		Texts.WriteLn(W); Texts.Append(model.log, W.buf)
	END Log;
	
	
	(*--- Execution within Coroutine ---*)
	
	PROCEDURE DebugLoop (me: Coroutines.Coroutine);
		VAR cor: Coroutine;
	BEGIN
		cor := me(Coroutine);
		Coroutines.Transfer(Coroutines.main);	(* return immediately when first activated by Start *)
		LOOP
			cor.proc(cor.model);
			Coroutines.Transfer(Coroutines.main)
		END
	END DebugLoop;
	
	PROCEDURE InitCoroutine (cor: Coroutine);
	BEGIN
		Coroutines.Init(cor, DebugLoop, DebugStackSize);
		Kernel.DisableGC;
		Coroutines.Start(cor);
		Kernel.EnableGC
	END InitCoroutine;
	
	PROCEDURE Notify (VAR c: OTInt.Context; data: OTInt.NotifierData);
		VAR model: Model; op, i, j, beg, end, inc: LONGINT; ch: CHAR; str: ARRAY 11 OF CHAR;
	BEGIN
		model := data(NotifierData).model;
		IF (c.code = model.breakCode) & (c.pc = model.breakPC+1) THEN	(* result of single stepping *)
			DEC(c.pc); c.code[c.pc] := model.breakInstr;	(* re-execute instruction *)
			INC(c.tos)	(* because DEBUG was artificially inserted and its execution messed up the stack *)
		END;
		model.context := c; model.fixDropouts := c.fixDropouts; model.scanType := c.scanType;
		Hex(c.pc, 4); Str(": ");
		IF c.pc >= c.codeLen THEN
			Str("[END]")
		ELSE
			op := ORD(c.code[c.pc]);
			i := InstrIdx[op]; j := 0;
			REPEAT
				ch := InstrStr[i]; str[j] := ch; INC(i); INC(j)
			UNTIL ch = 0X;
			Str(str);
			IF op = 40H THEN	(* NPUSHB *)
				beg := c.pc+2; end := beg + ORD(c.code[c.pc+1]); inc := 1
			ELSIF op = 41H THEN	(* NPUSHW *)
				beg := c.pc+2; end := beg + 2*ORD(c.code[c.pc+1]); inc := 2
			ELSIF (0B0H <= op) & (op <= 0B7H) THEN	(* PUSHBx *)
				beg := c.pc+1; end := beg + op MOD 8 + 1; inc := 1
			ELSIF (0B8H <= op) & (op <= 0BFH) THEN	(* PUSHWx *)
				beg := c.pc+1; end := beg + 2*(op MOD 8) + 2; inc := 2
			ELSE
				beg := c.pc; end := beg
			END;
			IF beg < end THEN
				Str(" ");
				WHILE beg < end DO
					IF inc = 1 THEN Hex(ORD(c.code[beg]), 0)
					ELSE Hex(100H*ORD(c.code[beg]) + ORD(c.code[beg+1]), 0)
					END;
					INC(beg, inc);
					IF beg < end THEN Str(", ") END
				END
			END;
			IF (op = 32H) OR (op = 33H) OR (op = 39H) OR (op = 3CH) OR (op = 80H) THEN	(* arguments depend on loop variable *)
				beg := c.tos; end := beg - c.loop
			ELSIF op = 38H THEN	(* SHPIX behaviour *)
				beg := c.tos; end := beg - 1 - c.loop
			ELSIF (op = 5DH) OR (71H <= op) & (op <= 75H) THEN	(* delta instruction *)
				beg := c.tos-1; end := beg - 2*c.stack[c.tos]
			ELSE
				beg := c.tos; end := beg - Arg[op]
			END;
			IF beg > end THEN
				Str(" ");
				WHILE beg > end DO
					Hex(c.stack[beg], 0); DEC(beg);
					IF beg > end THEN Str(", ") END
				END
			END
		END;
		Log(data(NotifierData).model);
		Coroutines.Transfer(Coroutines.main)
	END Notify;
	
	PROCEDURE Execute (model: Model; proc: Procedure; debug: BOOLEAN);
	BEGIN
		model.cor.proc := proc;
		IF debug THEN
			OTInt.InstallNotifier(Notify, model.data)
		END;
		Kernel.DisableGC;
		Coroutines.Transfer(model.cor);
		Kernel.EnableGC;
		OTInt.InstallNotifier(NIL, NIL);
		Gadgets.Update(model)
	END Execute;
	
	PROCEDURE Resume (model: Model);
	BEGIN
		IF model.state IN ExecStates THEN
			OTInt.InstallNotifier(Notify, model.data);
			Kernel.DisableGC;
			Coroutines.Transfer(model.cor);
			Kernel.EnableGC;
			OTInt.InstallNotifier(NIL, NIL);
			Gadgets.Update(model)
		END
	END Resume;
	
	PROCEDURE BreakFinish (model: Model);
	BEGIN
		IF model.context.ctos >= 0 THEN
			model.breakCode := model.context.callStack[model.context.ctos].ret.code;
			model.breakPC := model.context.callStack[model.context.ctos].ret.pc + 1;
			IF (model.breakCode # NIL) & (model.breakPC < LEN(model.breakCode^)) THEN
				model.breakInstr := model.breakCode[model.breakPC];
				model.breakCode[model.breakPC] := 4FX
			END
		END
	END BreakFinish;
	
	PROCEDURE BreakNext (model: Model);
		VAR code: OTInt.Code; pc, level: LONGINT;
	BEGIN
		code := model.context.code; pc := model.context.pc;
		IF (code # NIL) & (pc < model.context.codeLen) THEN
			IF code[pc] = 2DX THEN	(* ENDF *)
				BreakFinish(model)
			ELSE
				IF (code[pc] = 58X) & (model.context.stack[model.context.tos] = 0) THEN	(* if clause will be skipped *)
					level := 0;
					LOOP
						IF code[pc] = 58X THEN	(* initial or nested IF *)
							INC(level)
						ELSIF (code[pc] = 1BX) & (level = 0) THEN	(* ELSE terminates if on level 0 *)
							EXIT
						ELSIF code[pc] = 59X THEN	(* EIF lowers nest level and may terminate *)
							DEC(level);
							IF level = 0 THEN EXIT END
						END;
						INC(pc)
					END
				ELSIF code[pc] = 1BX THEN	(* if ELSE is encountered, the previous IF test was successful *)
					INC(pc); level := 1;
					LOOP
						IF code[pc] = 58X THEN	(* nested IF *)
							INC(level)
						ELSIF code[pc] = 59X THEN	(* EIF *)
							DEC(level);
							IF level = 0 THEN EXIT END
						END;
						INC(pc)
					END
				ELSIF (code[pc] = 2CX) OR (code[pc] = 89X) THEN	(* FDEF or IDEF *)
					REPEAT INC(pc) UNTIL code[pc] = 2DX	(* skip until ENDF *)
				ELSIF code[pc] = 40X THEN	(* NPUSHB *)
					INC(pc, LONG(1 + ORD(code[pc+1])))
				ELSIF code[pc] = 41X THEN	(* NPUSHW *)
					INC(pc, LONG(1 + 2*ORD(code[pc+1])))
				ELSIF (0B0X <= code[pc]) & (code[pc] <= 0B7X) THEN	(* PUSHBx *)
					INC(pc, LONG(1 + ORD(code[pc]) MOD 8))
				ELSIF (0B8X <= code[pc]) & (code[pc] <= 0BFX) THEN	(* PUSHWx *)
					INC(pc, LONG(2 + 2*(ORD(code[pc]) MOD 8)))
				END;
				INC(pc);
				model.breakCode := code; model.breakPC := pc;
				IF pc < model.context.codeLen THEN
					model.breakInstr := code[pc];
					code[pc] := 4FX	(* DEBUG instruction *)
				END
			END
		END
	END BreakNext;
	
	PROCEDURE BreakStep (model: Model);
		VAR code: OTInt.Code; n, pc: LONGINT;
	BEGIN
		code := model.context.code; pc := model.context.pc;
		IF (code # NIL) & (pc < model.context.codeLen) THEN
			IF (code[pc] = 2AX) OR (code[pc] = 2BX) THEN	(* (LOOP)CALL *)
				n := model.context.stack[model.context.tos];
				code := model.context.func[n].code;
				pc := model.context.func[n].pc+1;
				model.breakCode := code; model.breakPC := pc;
				IF pc < LEN(code^) THEN
					model.breakInstr := code[pc];
					code[pc] := 4FX
				END
			ELSE
				BreakNext(model)
			END
		END
	END BreakStep;
	
	PROCEDURE Reset (model: Model);
	BEGIN
		IF model.state IN ExecStates THEN
			OTInt.InstallNotifier(NIL, NIL);
			Kernel.DisableGC;
			Coroutines.Transfer(model.cor);
			Kernel.EnableGC
		END
	END Reset;
	
	PROCEDURE InvalidateContext (model: Model);
	BEGIN
		OTInt.SetStacks(model.context, NIL, NIL);
		OTInt.SetStructures(model.context, NIL, NIL, NIL, NIL);
		OTInt.InitState(model.context);
		OTInt.InstallNotifier(NIL, NIL);
		OTInt.Execute(model.context, NIL, 0, OTInt.EmptyZone, model.context.zone[1])
	END InvalidateContext;
	
	
	(**--- Models ---**)
	
	PROCEDURE InitModel (model: Model; handle: Objects.Handler);
	BEGIN
		model.handle := handle;
		NEW(model.cor); InitCoroutine(model.cor); model.cor.model := model;
		NEW(model.data); model.data.model := model;
		NEW(model.log); Texts.Open(model.log, "");
		model.hinted := TRUE
	END InitModel;
	
	PROCEDURE HandleModel (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR model, copy: Model;
	BEGIN
		model := obj(Model);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.enum THEN
					Gadgets.objecthandle(model, msg)
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "OTSim.NewModel"; msg.res := 0
					ELSIF msg.name = "DebugFontProg" THEN msg.class := Objects.Bool; msg.b := model.debugFontProg; msg.res := 0
					ELSIF msg.name = "DebugCVTProg" THEN msg.class := Objects.Bool; msg.b := model.debugCVTProg; msg.res := 0
					ELSIF msg.name = "DebugGlyphProg" THEN msg.class := Objects.Bool; msg.b := model.debugGlyphProg; msg.res := 0
					ELSIF msg.name = "Hinted" THEN msg.class := Objects.Bool; msg.b := model.hinted; msg.res := 0
					ELSIF msg.name = "MinDist" THEN
						msg.class := Objects.String; HexToStr(model.context.minDist, 0, msg.s, 0); msg.res := 0
					ELSIF msg.name = "CVTCutIn" THEN
						msg.class := Objects.String; HexToStr(model.context.cvtCutIn, 0, msg.s, 0); msg.res := 0
					ELSIF msg.name = "SingleWidthCutIn" THEN
						msg.class := Objects.String; HexToStr(model.context.swCutIn, 0, msg.s, 0); msg.res := 0
					ELSIF msg.name = "SingleWidth" THEN
						msg.class := Objects.String; HexToStr(model.context.swVal, 0, msg.s, 0); msg.res := 0
					ELSIF msg.name = "DeltaBase" THEN msg.class := Objects.Int; msg.i := model.context.deltaBase; msg.res := 0
					ELSIF msg.name = "DeltaShift" THEN msg.class := Objects.Int; msg.i := model.context.deltaShift; msg.res := 0
					ELSIF msg.name = "AutoFlip" THEN msg.class := Objects.Bool; msg.b := model.context.autoFlip; msg.res := 0
					ELSE Gadgets.objecthandle(model, msg)
					END
				ELSIF msg.id = Objects.set THEN
					IF (msg.name = "DebugFontProg") & (msg.class = Objects.Bool) THEN model.debugFontProg := msg.b; msg.res := 0
					ELSIF (msg.name = "DebugCVTProg") & (msg.class = Objects.Bool) THEN model.debugCVTProg := msg.b; msg.res := 0
					ELSIF (msg.name = "DebugGlyphProg") & (msg.class = Objects.Bool) THEN model.debugGlyphProg := msg.b; msg.res := 0
					ELSIF (msg.name = "Hinted") & (msg.class = Objects.Bool) THEN model.hinted := msg.b; msg.res := 0
					ELSE Gadgets.objecthandle(model, msg)
					END
				ELSE
					Gadgets.objecthandle(model, msg)
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			IF msg.stamp # model.stamp THEN
				NEW(copy); model.dlink := copy; model.stamp := msg.stamp;
				InitModel(copy, HandleModel)
			END;
			msg(Objects.CopyMsg).obj := model.dlink
		ELSE
			Gadgets.objecthandle(model, msg)
		END
	END HandleModel;
	
	PROCEDURE NewModel*;
		VAR model: Model;
	BEGIN
		NEW(model); InitModel(model, HandleModel);
		Objects.NewObj := model
	END NewModel;
	
	
	(**--- Multiviews ---**)
	
	PROCEDURE SetPosLength (mv: Multiview; len: LONGINT);
		VAR pos: PosArray; i: LONGINT;
	BEGIN
		IF mv.pos = NIL THEN
			NEW(mv.pos, -((-len) DIV 100H) * 100H)
		ELSIF LEN(mv.pos^) < len THEN
			NEW(pos, -((-len) DIV 100H) * 100H);
			FOR i := 0 TO LEN(mv.pos^)-1 DO
				pos[i] := mv.pos[i]
			END;
			mv.pos := pos
		END
	END SetPosLength;
	
	PROCEDURE GetScrollParts (mv: Multiview; h: INTEGER; VAR ys, ye: INTEGER);
		VAR min: INTEGER;
	BEGIN
		IF h < MVScrollH THEN min := h ELSE min := MVScrollH END;
		IF mv.start = 0 THEN
			ys := h; ye := SHORT((mv.len - mv.end) * h DIV mv.len);
			IF h - ye < min THEN ye := h - min END
		ELSIF mv.end = mv.len THEN
			ys := h - SHORT(mv.start * h DIV mv.len); ye := 0;
			IF ys < min THEN ys := min END
		ELSE
			ys := h - SHORT(mv.start * h DIV mv.len);
			ye := SHORT((mv.len - mv.end) * h DIV mv.len);
			IF ys - ye < min THEN
				INC(ys, (min - (ys - ye)) DIV 2);
				IF ys < min THEN
					ys := min; ye := 0
				ELSIF ys > h THEN
					ys := h; ye := h - min
				ELSE
					ye := ys - min
				END
			END
		END
	END GetScrollParts;
	
	PROCEDURE TrackMV (mv: Multiview; VAR msg: Oberon.InputMsg);
		VAR x, y, h, ys, ye, mx, my, dy: INTEGER; keysum, keys: SET; lines, start: LONGINT;
	BEGIN
		IF mv.len > mv.lines THEN
			x := msg.X - (msg.x + mv.X); y := msg.Y - (msg.y + mv.Y + 1);
			h := mv.H-2;
			keysum := msg.keys;
			IF (0 <= x) & (x < MVScrollW) & (0 <= y) & (y < h) THEN
				GetScrollParts(mv, h, ys, ye);
				IF y > ys THEN	(* scroll one page up *)
					REPEAT
						Input.Mouse(keys, mx, my); keysum := keysum + keys
					UNTIL keys = {};
					IF keysum # {0..2} THEN
						lines := mv.lines-1;
						IF mv.start < lines THEN lines := mv.start END;
						DEC(mv.start, lines); mv.end := mv.start + mv.lines;
						Gadgets.Update(mv)
					END;
					msg.res := 0
				ELSIF y < ye THEN	(* scroll one page down *)
					REPEAT
						Input.Mouse(keys, mx, my); keysum := keysum + keys
					UNTIL keys = {};
					IF keysum # {0..2} THEN
						lines := mv.lines-1;
						IF mv.end + lines > mv.len THEN lines := mv.len - mv.end END;
						INC(mv.end, lines); mv.start := mv.end - mv.lines;
						Gadgets.Update(mv)
					END;
					msg.res := 0
				ELSE	(* drag knob *)
					my := msg.Y; dy := ys - y;
					REPEAT
						Input.Mouse(keys, x, y);
						IF (1 IN keys) & (y # my) THEN
							ys := y - (msg.y + mv.Y + 1) + dy;
							start := ((h - ys) * mv.len) DIV h;
							IF start < 0 THEN start := 0
							ELSIF start + mv.lines > mv.len THEN start := mv.len - mv.lines
							END;
							IF start # mv.start THEN
								mv.start := start; mv.end := start + mv.lines;
								Gadgets.Update(mv)
							END;
							my := y
						END
					UNTIL keys = {}
				END
			END
		END
	END TrackMV;
	
	PROCEDURE RestoreMV (mv: Multiview; mask: Display3.Mask; fx, fy, x, y, w, h: INTEGER);
		VAR
			i, last, ratio, xratio, yratio, j, k: LONGINT; lft, rgt, bot, top, ly, backCol, textCol, lx, dx, xc, yc, wc, hc, ys, ye: INTEGER;
			r: Texts.Reader; ch: CHAR; str: ARRAY 128 OF CHAR; pat: Display.Pattern;
	BEGIN
		Oberon.RemoveMarks(x, y, w, h);
		
		IF x + w > fx + MVScrollW THEN	(* restore lines *)
			lft := fx + MVScrollW; rgt := fx + mv.W; bot := fy; top := fy + mv.H;
			Display3.Rect3D(mask, Display3.bottomC, Display3.topC, lft, bot, rgt - lft, top - bot, 1, Display.replace);
			INC(lft); INC(bot); DEC(rgt); DEC(top);
			i := mv.start + (top - (y + h)) DIV MVLineH;
			IF i < mv.start THEN i := mv.start END;	(* happens when displaying full frame *)
			last := mv.start + (top - y) DIV MVLineH;
			IF last >= mv.end THEN last := mv.end-1 END;
			ly := top - SHORT(i - mv.start) * MVLineH;
			
			IF (mv.mode = CVT) & (mv.model.state >= Instantiating) THEN
				ratio := mv.model.context.ratio;
				IF ratio = 0 THEN
					IF mv.model.inst.xppm >= mv.model.inst.yppm THEN
						xratio := 10000H; yratio := OTInt.ShiftDiv(mv.model.inst.yppm, 10H, mv.model.inst.xppm)
					ELSE
						xratio := OTInt.ShiftDiv(mv.model.inst.xppm, 10H, mv.model.inst.yppm); yratio := 10000H
					END;
					xratio := ASH(mv.model.context.proj.x * xratio, -14);
					yratio := ASH(mv.model.context.proj.y * yratio, -14);
					ratio := OTInt.Norm(xratio, yratio)
				END
			END;
			
			WHILE i <= last DO
				DEC(ly, MVLineH);
				backCol := Display3.textbackC; textCol := Display3.textC;
				CASE mv.mode OF
				| LogText:
					Texts.OpenReader(r, mv.model.log, mv.pos[i]);
					Texts.Read(r, str[0]); j := 0;
					WHILE ~r.eot & (j < LEN(str)-1) & (str[j] # 0DX) DO
						INC(j); Texts.Read(r, str[j])
					END;
					str[j] := 0X
				
				| Code:
					IF mv.pos[i] = mv.model.context.pc THEN
						backCol := Display3.textC; textCol := Display3.textbackC
					END;
					HexToStr(mv.pos[i], 4, str, 0); str[4] := ":"; str[5] := " ";
					IF mv.pos[i] < mv.model.context.codeLen THEN
						j := InstrIdx[ORD(mv.model.context.code[mv.pos[i]])]; k := 6;
						REPEAT
							ch := InstrStr[j]; str[k] := ch; INC(j); INC(k)
						UNTIL ch = 0X
					ELSE
						str[6] := "["; str[7] := "E"; str[8] := "N"; str[9] := "D"; str[10] := "]"; str[11]  := 0X
					END
				
				| Stack:
					HexToStr(i, 4, str, 0); str[4] := ":"; str[5] := " ";
					HexToStr(mv.model.context.stack[mv.model.context.tos - i], 0, str, 6)
				
				| CVT:
					HexToStr(i, 3, str, 0); str[3] := ":"; str[4] := " ";
					IF mv.model.state >= Instantiating THEN
						HexToStr(OTInt.MulShift(mv.model.context.cvt[i], ratio, -16), 0, str, 5)
					ELSE
						HexToStr(mv.model.context.cvt[i], 0, str, 5)
					END
				
				| Store:
					HexToStr(i, 3, str, 0); str[3] := ":"; str[4] := " ";
					HexToStr(mv.model.context.store[i], 0, str, 5)
				
				| Points:
					HexToStr(i, 3, str, 0); str[3] := ":"; str[4] := " ";
					HexToStr(mv.model.context.zone[1].pt[i].cur[X], 8, str, 5); str[13] := " ";
					HexToStr(mv.model.context.zone[1].pt[i].cur[Y], 8, str, 14)
				ELSE
				END;
				
				Pictures.ReplConst(Buffer, backCol, 0, 0, Buffer.width, Buffer.height, Display.replace);
				j := 0; lx := 2;
				WHILE (str[j] # 0X) & (lx < mv.W) DO
					Fonts.GetChar(MVFont, str[j], dx, xc, yc, wc, hc, pat);
					IF pat # 0 THEN
						Pictures.CopyPattern(Buffer, textCol, pat, lx + xc, MVLineY + yc, Display.paint)
					END;
					INC(lx, dx); INC(j)
				END;
				Display3.Pict(mask, Buffer, 0, 0, rgt - lft, MVLineH, lft, ly, Display.replace);
				INC(i)
			END;
			Display3.ReplConst(mask, Display3.textbackC, lft, bot, rgt - lft, ly - bot, Display.replace)
		END;
		
		IF x < fx + MVScrollW THEN	(* restore scroll area *)
			lft := fx; rgt := fx + MVScrollW; bot := fy; top := fy + mv.H;
			Display3.Rect3D(mask, Display3.bottomC, Display3.topC, lft, bot, rgt - lft, top - bot, 1, Display.replace);
			INC(lft); INC(bot); DEC(rgt); DEC(top);
			wc := rgt - lft; hc := top - bot;
			IF mv.len > mv.lines THEN
				GetScrollParts(mv, hc, ys, ye);
				IF mv.start > 0 THEN
					top := bot + ys;
					Display3.ReplConst(mask, Display3.textbackC, lft, top, wc, hc - ys, Display.replace)
				END;
				IF mv.end < mv.len THEN
					Display3.ReplConst(mask, Display3.textbackC, lft, bot, wc, ye, Display.replace);
					INC(bot, ye)
				END;
				hc := top - bot
			END;
			Display3.FilledRect3D(mask, Display3.topC, Display3.bottomC, Display3.groupC, lft, bot, wc, hc, 1, Display.replace);
		END;
		
		IF Gadgets.selected IN mv.state THEN
			Display3.FillPattern(mask, Display3.white, Display3.selectpat, fx, fy, x, y, w, h, Display.paint)
		END
	END RestoreMV;
	
	PROCEDURE SetMVMode (mv: Multiview; mode: INTEGER);
		VAR r: Texts.Reader; ch: CHAR; code: OTInt.Code; pc, m: LONGINT;
	BEGIN
		IF (mode # mv.mode) OR (mode = Code) & (mv.code # mv.model.context.code) THEN
			mv.mode := mode;
			CASE mode OF
			| LogText:
				mv.len := 0;
				SetPosLength(mv, 1);
				mv.pos[0] := 0;
				Texts.OpenReader(r, mv.model.log, 0); Texts.Read(r, ch);
				WHILE ~r.eot DO
					WHILE ~r.eot & (ch # 0DX) DO
						Texts.Read(r, ch)
					END;
					INC(mv.len);
					SetPosLength(mv, mv.len+1);
					mv.pos[mv.len] := Texts.Pos(r);
					Texts.Read(r, ch)
				END;
				mv.end := mv.len; mv.start := mv.end - mv.lines;
				IF mv.start < 0 THEN mv.start := 0 END
			
			| Code:
				code := mv.model.context.code; mv.code := code; mv.clen := mv.model.context.codeLen;
				IF code = NIL THEN
					mv.len := 0; mv.start := 0; mv.end := 0
				ELSE
					mv.len := 0; pc := 0;
					WHILE pc < mv.clen DO
						SetPosLength(mv, mv.len+1);
						mv.pos[mv.len] := pc;
						INC(mv.len);
						CASE code[pc] OF
						| 40X: INC(pc, LONG(2 + ORD(code[pc+1])))	(* NPUSHB *)
						| 41X: INC(pc, LONG(2 + 2*ORD(code[pc+1])))	(* NPUSHW *)
						| 0B0X..0B7X: INC(pc, LONG(2 + ORD(code[pc]) MOD 8))	(* PUSHBx *)
						| 0B8X..0BFX: INC(pc, LONG(3 + 2*(ORD(code[pc]) MOD 8)))	(* PUSHWx *)
						ELSE INC(pc)
						END
					END;
					SetPosLength(mv, mv.len+1);
					mv.pos[mv.len] := pc;
					INC(mv.len);
					IF mv.len <= mv.lines THEN
						mv.start := 0; mv.end := mv.len
					ELSE
						mv.start := 0;
						WHILE (mv.start + mv.lines < mv.len) & (mv.pos[mv.start + mv.lines DIV 2] < mv.model.context.pc) DO
							INC(mv.start)
						END;
						mv.end := mv.start + mv.lines;
						IF mv.end > mv.len THEN mv.end := mv.len END
					END
				END
			
			| Stack:
				IF mv.model.context.stack = NIL THEN
					mv.len := 0; mv.start := 0; mv.end := 0
				ELSE
					mv.len := mv.model.context.tos + 1; mv.start := 0; mv.end := mv.start + mv.lines;
					IF mv.end > mv.len THEN mv.end := mv.len END
				END
			
			| CVT:
				IF mv.model.context.cvt = NIL THEN
					mv.len := 0; mv.start := 0; mv.end := 0
				ELSE
					mv.len := LEN(mv.model.context.cvt^); mv.start := 0; mv.end := mv.start + mv.lines;
					IF mv.end > mv.len THEN mv.end := mv.len END
				END
			
			| Store:
				IF mv.model.context.store = NIL THEN
					mv.len := 0; mv.start := 0; mv.end := 0
				ELSE
					mv.len := LEN(mv.model.context.store^); mv.start := 0; mv.end := mv.start + mv.lines;
					IF mv.end > mv.len THEN mv.end := mv.len END
				END
			
			| Points:
				mv.len := mv.model.context.zone[1].first[mv.model.context.zone[1].contours] + 2;
				mv.start := 0; mv.end := mv.start + mv.lines;
				IF mv.end > mv.len THEN mv.end := mv.len END
			ELSE
			END;
			Gadgets.Update(mv);
			IF mv.obj # NIL THEN
				Attributes.GetInt(mv.obj, "Value", m);
				IF m # mv.mode THEN
					Attributes.SetInt(mv.obj, "Value", mv.mode);
					Gadgets.Update(mv.obj)
				END
			END
		END
	END SetMVMode;
	
	PROCEDURE HandleMVAttr (mv: Multiview; VAR msg: Objects.AttrMsg);
	BEGIN
		IF msg.id = Objects.enum THEN
			msg.Enum("Mode");
			Gadgets.framehandle(mv, msg)
		ELSIF msg.id = Objects.get THEN
			IF msg.name = "Gen" THEN
				msg.class := Objects.String; msg.s := "OTSim.NewMultiview"; msg.res := 0
			ELSIF msg.name = "Mode" THEN
				msg.class := Objects.Int; msg.i := mv.mode; msg.res := 0
			ELSE
				Gadgets.framehandle(mv, msg)
			END
		ELSIF msg.id = Objects.set THEN
			IF (msg.name = "Mode") & (msg.class = Objects.Int) THEN
				SetMVMode(mv, SHORT(msg.i));
				msg.res := 0
			END
		ELSE
			Gadgets.framehandle(mv, msg)
		END
	END HandleMVAttr;
	
	PROCEDURE HandleMVLink (mv: Multiview; VAR msg: Objects.LinkMsg);
		VAR mode: LONGINT;
	BEGIN
		IF msg.id = Objects.enum THEN
			msg.Enum("Model"); msg.Enum("ModeObj")
		ELSIF msg.id = Objects.get THEN
			IF msg.name = "Model" THEN msg.obj := mv.model; msg.res := 0
			ELSIF msg.name = "ModeObj" THEN msg.obj := mv.obj; msg.res := 0
			ELSE Gadgets.framehandle(mv, msg)
			END
		ELSIF msg.id = Objects.set THEN
			IF (msg.name = "Model") & (msg.obj # NIL) & (msg.obj IS Model) THEN mv.model := msg.obj(Model); msg.res := 0
			ELSIF msg.name = "ModeObj" THEN
				mv.obj := msg.obj;
				Attributes.GetInt(mv.obj, "Value", mode);
				SetMVMode(mv, SHORT(mode));
				msg.res := 0
			ELSE Gadgets.framehandle(mv, msg)
			END
		ELSE
			Gadgets.framehandle(mv, msg)
		END
	END HandleMVLink;
	
	PROCEDURE HandleMultiview (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR
			mv, copy: Multiview; fx, fy, x, y: INTEGER; mask: Display3.Mask; r: Texts.Reader; ch: CHAR;
			dm: Display.DisplayMsg; mode, len, ver: LONGINT;
	BEGIN
		mv := obj(Multiview);
		IF msg IS Display.FrameMsg THEN
			WITH msg: Display.FrameMsg DO
				IF (msg.F = NIL) OR (msg.F = mv) THEN
					fx := msg.x + mv.X; fy := msg.y + mv.Y;
					IF msg IS Oberon.InputMsg THEN
						WITH msg: Oberon.InputMsg DO
							IF (msg.id = Oberon.track) & (msg.keys # {}) & Gadgets.InActiveArea(mv, msg) THEN
								TrackMV(mv, msg)
							ELSE
								Gadgets.framehandle(mv, msg)
							END
						END
					ELSIF msg IS Display.DisplayMsg THEN
						WITH msg: Display.DisplayMsg DO
							IF msg.device = Display.screen THEN
								IF (msg.id = Display.full) OR (msg.F = NIL) THEN
									Gadgets.MakeMask(mv, fx, fy, msg.dlink, mask);
									RestoreMV(mv, mask, fx, fy, fx, fy, mv.W, mv.H)
								ELSIF msg.id = Display.area THEN
									Gadgets.MakeMask(mv, fx, fy, msg.dlink, mask);
									x := fx + msg.u; y := fy + mv.H - 1 + msg.v;
									Display3.AdjustMask(mask, x, y, msg.w, msg.h);
									RestoreMV(mv, mask, fx, fy, x, y, msg.w, msg.h)
								END
							ELSIF msg.device = Display.printer THEN
								(* do this when someone really needs it *) 
							END
						END
					ELSIF msg IS Display.ModifyMsg THEN
						WITH msg: Display.ModifyMsg DO
							mv.lines := (mv.H + msg.dH - 2) DIV MVLineH;
							mv.end := mv.start + mv.lines;
							IF mv.end > mv.len THEN
								mv.end := mv.len; mv.start := mv.end - mv.lines;
								IF mv.start < 0 THEN mv.start := 0 END
							END;
							Gadgets.Adjust(mv, msg)
						END
					ELSIF msg IS Gadgets.UpdateMsg THEN
						WITH msg: Gadgets.UpdateMsg DO
							IF msg.obj = mv.obj THEN
								Attributes.GetInt(mv.obj, "Value", mode);
								SetMVMode(mv, SHORT(mode))
							ELSIF msg.obj = mv.model THEN
								IF mv.mode = Code THEN
									IF (mv.model.context.code # mv.code) OR (mv.model.context.codeLen # mv.clen) THEN
										SetMVMode(mv, Code)
									ELSIF (mv.end < mv.len) & (mv.model.context.pc >= mv.pos[mv.end]) THEN
										REPEAT INC(mv.end) UNTIL (mv.end = mv.len) OR (mv.model.context.pc < mv.pos[mv.end]);
										mv.start := mv.end - mv.lines;
										IF mv.start < 0 THEN mv.start := 0 END
									END
								ELSIF mv.mode = Stack THEN
									IF mv.model.context.stack = NIL THEN
										mv.len := 0; mv.start := 0; mv.end := 0
									ELSE
										len := mv.model.context.tos + 1;
										IF mv.end > len THEN
											mv.end := len; mv.start := mv.end - mv.lines;
											IF mv.start < 0 THEN mv.start := 0 END
										ELSIF (len > mv.len) & (mv.len < mv.lines) THEN
											mv.end := mv.start + mv.lines;
											IF mv.end > len THEN mv.end := len END
										END;
										mv.len := len
									END
								ELSIF mv.mode = Points THEN
									len := mv.model.context.zone[1].first[mv.model.context.zone[1].contours] + 2;
									IF len # mv.len THEN
										IF mv.end > len THEN
											mv.end := len; mv.start := mv.end - mv.lines;
											IF mv.start < 0 THEN mv.start := 0 END
										ELSIF (len > mv.len) & (mv.len < mv.lines) THEN
											mv.end := mv.start + mv.lines;
											IF mv.end > len THEN mv.end := len END
										END;
										mv.len := len
									END
								END;
								Gadgets.Update(mv)
							END
						END
					ELSIF msg IS Texts.UpdateMsg THEN
						WITH msg: Texts.UpdateMsg DO
							IF (mv.mode = LogText) & (msg.text = mv.model.log) THEN	(* a line has been append to the log text *)
								Texts.OpenReader(r, msg.text, mv.pos[mv.len]); Texts.Read(r, ch);
								WHILE ~r.eot DO
									WHILE ~r.eot & (ch # 0DX) DO
										Texts.Read(r, ch)
									END;
									INC(mv.len);
									SetPosLength(mv, mv.len+1);
									mv.pos[mv.len] := Texts.Pos(r);
									Texts.Read(r, ch)
								END;
								IF mv.len <= mv.lines THEN	(* update line area *)
									INC(mv.end);
									dm.F := mv; dm.device := Display.screen; dm.id := Display.area;
									dm.u := MVScrollW; dm.v := -SHORT(mv.end * MVLineH); dm.w := mv.W - MVScrollW; dm.h := MVLineH;
									Display.Broadcast(dm)
								ELSIF mv.end+1 = mv.len THEN	(* scroll window *)
									INC(mv.start); INC(mv.end);
									Gadgets.Update(mv)
								ELSE	(* update scroll area *)
									dm.F := mv; dm.device := Display.screen; dm.id := Display.area;
									dm.u := 0; dm.v := 1-mv.H; dm.w := MVScrollW; dm.h := mv.H;
									Display.Broadcast(dm)
								END
							END
						END
					ELSE
						Gadgets.framehandle(mv, msg)
					END
				END
			END
		ELSIF msg IS Objects.AttrMsg THEN
			HandleMVAttr(mv, msg(Objects.AttrMsg))
		ELSIF msg IS Objects.LinkMsg THEN
			HandleMVLink(mv, msg(Objects.LinkMsg))
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # mv.stamp THEN
					NEW(copy); mv.dlink := copy; mv.stamp := msg.stamp;
					Gadgets.CopyFrame(msg, mv, copy);
					copy.mode := mv.mode; copy.model := mv.model;
					copy.start := mv.start; copy.end := mv.end; copy.pos := mv.pos
				END;
				msg.obj := mv.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			mv.model.handle(mv.model, msg);
			Gadgets.framehandle(mv, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Gadgets.framehandle(mv, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Files.WriteInt(msg.R, mv.mode);
					Gadgets.WriteRef(msg.R, mv.lib, mv.model)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 1 THEN
						Files.ReadInt(msg.R, mv.mode);
						Gadgets.ReadRef(msg.R, mv.lib, obj);
						IF (obj # NIL) & (obj IS Model) THEN mv.model := obj(Model)
						ELSE NEW(mv.model); InitModel(mv.model, HandleModel)
						END;
						mv.lines := (mv.H-2) DIV MVLineH
					END
				END
			END
		ELSIF msg IS Objects.FindMsg THEN
			mv.model.handle(mv.model, msg);
			IF msg(Objects.FindMsg).obj # mv.model THEN
				Gadgets.framehandle(mv, msg)
			END
		ELSE
			Gadgets.framehandle(mv, msg)
		END
	END HandleMultiview;
	
	PROCEDURE NewMultiview*;
		VAR mv: Multiview;
	BEGIN
		NEW(mv); mv.handle := HandleMultiview;
		mv.W := 160; mv.H := 142; mv.lines := (mv.H-2) DIV MVLineH;
		mv.model := DummyModel;
		mv.mode := -1; SetMVMode(mv, LogText);
		Objects.NewObj := mv
	END NewMultiview;
	
	
	(**--- Glyph Views ---**)
	
	PROCEDURE InitPatterns;
		VAR p: ARRAY 2 OF SET;
	BEGIN
		p[0] := {0..7}; p[1] := {};
		EvenRowPat := Display.NewPattern(8, 2, p);
		p[0] := {}; p[1] := {0..7};
		OddRowPat := Display.NewPattern(8, 2, p);
		p[0] := {0, 2, 4, 6}; p[1] := {0, 2, 4, 6};
		EvenColPat := Display.NewPattern(8, 2, p);
		p[0] := {1, 3, 5, 7}; p[1] := {1, 3, 5, 7};
		OddColPat := Display.NewPattern(8, 2, p)
	END InitPatterns;
	
	PROCEDURE FillRow (row: INTEGER; beg, end: OTInt.F26D6; VAR d: OTScan.EnumData);
		VAR y: INTEGER; pat: Display.Pattern;
	BEGIN
		WITH d: ScanData DO
			y := SHORT((d.y DIV 40H + row) * d.h);
			IF ODD(y) THEN pat := OddRowPat ELSE pat := EvenRowPat END;
			Pictures.ReplPattern(
				GVPict, 12, pat,
				SHORT((d.x + beg) DIV 40H * d.w), y,
				SHORT((end - beg) DIV 40H * d.w), d.h, Display.paint
			)
		END
	END FillRow;
	
	PROCEDURE FillCol (col: INTEGER; beg, end: OTInt.F26D6; VAR d: OTScan.EnumData);
		VAR x: INTEGER; pat: Display.Pattern;
	BEGIN
		WITH d: ScanData DO
			x:= SHORT((d.x DIV 40H + col) * d.w);
			IF ODD(x) THEN pat := OddColPat ELSE pat := EvenColPat END;
			Pictures.ReplPattern(
				GVPict, 12, pat,
				x, SHORT((d.y + beg) DIV 40H * d.w),
				d.w, SHORT((end - beg) DIV 40H * d.w), Display.paint
			)
		END
	END FillCol;
	
	PROCEDURE DrawLine (col: INTEGER; x0, y0, x1, y1: LONGINT);
		VAR x, y, dx, dy, incx, incy, dx2, dy2, d: INTEGER;
	BEGIN
		x := SHORT(x0); y := SHORT(y0);
		dx := SHORT(x1) - x; dy := SHORT(y1) - y;
		IF dx >= 0 THEN incx := 1 ELSE incx := -1; dx := -dx END;
		IF dy >= 0 THEN incy := 1 ELSE incy := -1; dy := -dy END;
		dx2 := 2*dx; dy2 := 2*dy;
		Pictures.Dot(GVPict, col, x, y, Display.replace);
		IF dx >= dy THEN
			d := 2*dy - dx;
			WHILE x # x1 DO
				INC(x, incx); INC(d, dy2);
				IF d > 0 THEN
					INC(y, incy); DEC(d, dx2)
				END;
				Pictures.Dot(GVPict, col, x, y, Display.replace)
			END
		ELSE
			d := 2*dx - dy;
			WHILE y # y1 DO
				INC(y, incy); INC(d, dx2);
				IF d > 0 THEN
					INC(x, incx); DEC(d, dy2)
				END;
				Pictures.Dot(GVPict, col, x, y, Display.replace)
			END
		END
	END DrawLine;
	
	PROCEDURE DrawBezier (col: INTEGER; x0, y0, x1, y1, x2, y2: LONGINT);
		VAR dx01, dy01, dx12, dy12, x01, y01, x12, y12, xm, ym: LONGINT;
	BEGIN
		dx01 := x1 - x0; dy01 := y1 - y0;
		dx12 := x2 - x1; dy12 := y2 - y1;
		IF dx01*dx01 + dy01*dy01 + dx12*dx12 + dy12*dy12 <= 4 THEN
			DrawLine(col, x0, y0, x2, y2)
		ELSE
			x01 := (x0 + x1 + 1) DIV 2; y01 := (y0 + y1 + 1) DIV 2;
			x12 := (x1 + x2 + 1) DIV 2; y12 := (y1 + y2 + 1) DIV 2;
			xm := (x01 + x12 + 1) DIV 2; ym := (y01 + y12 + 1) DIV 2;
			DrawBezier(col, x0, y0, x01, y01, xm, ym);
			DrawBezier(col, xm, ym, x12, y12, x2, y2)
		END
	END DrawBezier;
	
	PROCEDURE DrawPoint (col: INTEGER; x, y: INTEGER; touchedX, touchedY: BOOLEAN);
	BEGIN
		Pictures.Dot(GVPict, col, x, y, Display.replace);
		IF touchedX THEN
			Pictures.ReplConst(GVPict, col, x-2, y, 5, 1, Display.replace)
		END;
		IF touchedY THEN
			Pictures.ReplConst(GVPict, col, x, y-2, 1, 5, Display.replace)
		END
	END DrawPoint;
	
	PROCEDURE DrawString (col: INTEGER; x, y: INTEGER; s: ARRAY OF CHAR);
		VAR i, dx, cx, cy, cw, ch: INTEGER; pat: Display.Pattern;
	BEGIN
		i := 0;
		WHILE s[i] # 0X DO
			Fonts.GetChar(GVFont, s[i], dx, cx, cy, cw, ch, pat);
			IF pat # 0 THEN
				Pictures.CopyPattern(GVPict, col, pat, x + cx, y + cy, Display.paint)
			END;
			INC(x, dx); INC(i)
		END
	END DrawString;
	
	PROCEDURE RestoreGVPict (gv: GlyphView; w, h: INTEGER);
		VAR
			model: Model; zone, z: OTInt.Zone; x, y, cont, beg, n, i, j, k, l: INTEGER; ras: OTScan.Rasterizer; rules: SET;
			data: ScanData; x0, y0, x2, y2, x1, y1: OTInt.F26D6; s: ARRAY 7 OF CHAR;
	BEGIN
		Pictures.ReplConst(GVPict, Display3.textbackC, 0, 0, w, h, Display.replace);
		model := gv.obj(Model); zone := model.context.zone[1];
		IF (zone # NIL) & (gv.pixW > 0) & (gv.pixH > 0) THEN
			IF (model.state >= Instantiating) & gv.showGrid THEN
				x := 0;
				WHILE x < w DO
					Pictures.ReplConst(GVPict, Display3.groupC, x, 0, 1, h, Display.replace);
					INC(x, gv.pixW)
				END;
				y := 0;
				WHILE y < h DO
					Pictures.ReplConst(GVPict, Display3.groupC, 0, y, w, 1, Display.replace);
					INC(y, gv.pixH)
				END
			END;
			
			IF model.state >= Hinting THEN
				IF gv.showPattern & (zone.contours > 0) THEN
					rules := {OTScan.Round};
					IF model.fixDropouts THEN
						IF model.scanType IN {0, 1, 4, 5} THEN INCL(rules, OTScan.Dropouts) END;
						IF model.scanType IN {1, 5} THEN INCL(rules, OTScan.Stubs) END;
						IF model.scanType IN {4, 5} THEN INCL(rules, OTScan.Smart) END
					END;
					OTScan.Convert(zone, rules, ras);
					data.w := gv.pixW; data.h := gv.pixH; data.x := ras.xmin - gv.minX; data.y := ras.ymin - gv.minY;
					OTScan.EnumerateRows(ras, FillRow, data);
					OTScan.EnumerateColumns(ras, FillCol, data)
				END;
				
				IF gv.showOutline THEN
					cont := 0;
					WHILE cont < zone.contours DO
						beg := zone.first[cont]; n := zone.first[cont+1] - beg; i := 0;
						WHILE (i < n) & ~zone.pt[beg + i].onCurve DO INC(i) END;
						IF i < n THEN
							j := i; k := beg + j;
							x0 := ((zone.pt[k].cur[X] - gv.minX) * gv.pixW + 20H) DIV 40H;
							y0 := ((zone.pt[k].cur[Y] - gv.minY) * gv.pixH + 20H) DIV 40H;
							REPEAT
								j := (j+1) MOD n; k := beg + j;
								IF zone.pt[k].onCurve THEN
									x2 := ((zone.pt[k].cur[X] - gv.minX) * gv.pixW + 20H) DIV 40H;
									y2 := ((zone.pt[k].cur[Y] - gv.minY) * gv.pixH + 20H) DIV 40H;
									DrawLine(Display3.black, x0, y0, x2, y2)
								ELSE
									x1 := ((zone.pt[k].cur[X] - gv.minX) * gv.pixW + 20H) DIV 40H;
									y1 := ((zone.pt[k].cur[Y] - gv.minY) * gv.pixH + 20H) DIV 40H;
									l := beg + (j+1) MOD n;
									IF zone.pt[l].onCurve THEN
										k := l; j := k - beg;
										x2 := ((zone.pt[k].cur[X] - gv.minX) * gv.pixW + 20H) DIV 40H;
										y2 := ((zone.pt[k].cur[Y] - gv.minY) * gv.pixH + 20H) DIV 40H;
									ELSE
										x2 := (((zone.pt[k].cur[X] + zone.pt[l].cur[X]) DIV 2 - gv.minX) * gv.pixW + 20H) DIV 40H;
										y2 := (((zone.pt[k].cur[Y] + zone.pt[l].cur[Y]) DIV 2 - gv.minY) * gv.pixH + 20H) DIV 40H
									END;
									DrawBezier(Display3.black, x0, y0, x1, y1, x2, y2)
								END;
								x0 := x2; y0 := y2
							UNTIL j = i
						END;
						INC(cont)
					END
				END;
				
				IF gv.showTwilight THEN
					z := model.context.zone[0];
					FOR i := 0 TO z.first[z.contours]-1 DO
						x := SHORT(((z.pt[i].cur[X] - gv.minX) * gv.pixW + 20H) DIV 40H);
						y := SHORT(((z.pt[i].cur[Y] - gv.minY) * gv.pixH + 20H) DIV 40H);
						DrawPoint(5, x, y, z.pt[i].touched[X], z.pt[i].touched[Y]);
						HexToStr(i, 0, s, 0);
						DrawString(Display3.black, x+4, y, s)
					END
				END;
				
				IF gv.showPoints THEN
					FOR i := 0 TO zone.first[zone.contours]+1 DO
						x := SHORT(((zone.pt[i].cur[X] - gv.minX) * gv.pixW + 20H) DIV 40H);
						y := SHORT(((zone.pt[i].cur[Y] - gv.minY) * gv.pixH + 20H) DIV 40H);
						DrawPoint(Display3.white, x, y, zone.pt[i].touched[X], zone.pt[i].touched[Y]);
						HexToStr(i, 0, s, 0);
						DrawString(Display3.black, x+4, y, s)
					END;
					x0 := (-gv.minX * gv.pixW + 20H) DIV 40H;
					y0 := (-gv.minY * gv.pixH + 20H) DIV 40H;
					DrawLine(Display3.blue, x0, y0, x0 + model.context.proj2.x DIV 200H, y0 + model.context.proj2.y DIV 200H);
					DrawLine(Display3.green, x0, y0, x0 + model.context.proj.x DIV 200H, y0 + model.context.proj.y DIV 200H);
					DrawLine(Display3.red, x0, y0, x0 + model.context.free.x DIV 200H, y0 + model.context.free.y DIV 200H)
				END
			END
		END
	END RestoreGVPict;
	
	PROCEDURE RestoreGV (gv: GlyphView; mask: Display3.Mask; fx, fy, x, y, w, h: INTEGER);
		VAR fw, fh: INTEGER;
	BEGIN
		Oberon.RemoveMarks(x, y, w, h);
		Display3.Rect3D(mask, Display3.bottomC, Display3.topC, fx, fy, gv.W, gv.H, 1, Display.replace);
		fx := fx+1; fy := fy+1; fw := gv.W-2; fh := gv.H-2;
		IF gv.left # 0 THEN
			Display3.ReplConst(mask, Display3.textbackC, fx, fy, gv.left, fh, Display.replace);
			INC(fx, gv.left); DEC(fw, gv.left)
		END;
		IF gv.right # 0 THEN
			DEC(fw, gv.right);
			Display3.ReplConst(mask, Display3.textbackC, fx + fw, fy, gv.right, fh, Display.replace)
		END;
		IF gv.bot # 0 THEN
			Display3.ReplConst(mask, Display3.textbackC, fx, fy, fw, gv.bot, Display.replace);
			INC(fy, gv.bot); DEC(fh, gv.bot)
		END;
		IF gv.top # 0 THEN
			DEC(fh, gv.top);
			Display3.ReplConst(mask, Display3.textbackC, fx, fy + fh, fw, gv.top, Display.replace)
		END;
		RestoreGVPict(gv, fw, fh);
		Display3.Pict(mask, GVPict, 0, 0, fw, fh, fx, fy, Display.replace);
		IF Gadgets.selected IN gv.state THEN
			Display3.FillPattern(mask, Display3.white, Display3.selectpat, fx, fy, x, y, w, h, Display.paint)
		END
	END RestoreGV;
	
	PROCEDURE UpdateGV (gv: GlyphView; w, h: INTEGER);
		VAR model: Model; upm, maxX, maxY, dx, dy: LONGINT; t: INTEGER;
	BEGIN
		DEC(w, 3); DEC(h, 3);
		model := gv.obj(Model);
		IF model.state >= Instantiating THEN
			upm := 40H*LONG(model.upm);
			gv.minX := (model.xMin * model.inst.xppm) DIV upm * 40H - 80H;
			gv.minY := (model.yMin * model.inst.yppm) DIV upm * 40H - 80H;
			maxX := -((-model.xMax * model.inst.xppm) DIV upm) * 40H + 80H;
			maxY := -((-model.yMax * model.inst.yppm) DIV upm) * 40H + 80H;
			dx := maxX - gv.minX; dy := maxY - gv.minY;
			IF (dx > 0) & (dy > 0) THEN
				IF w * dy < h * dx THEN
					gv.pixW := SHORT(40H*LONG(w) DIV dx);
					gv.pixH := SHORT(gv.pixW * model.inst.xppm DIV model.inst.yppm)
				ELSE
					gv.pixH := SHORT(40H*LONG(h) DIV dy);
					gv.pixW := SHORT(gv.pixH * model.inst.yppm DIV model.inst.xppm)
				END;
				t := SHORT(w - gv.pixW * dx DIV 40H);
				gv.left := t DIV 2; gv.right := t - gv.left;
				t := SHORT(h - gv.pixH * dy DIV 40H);
				gv.bot := t DIV 2; gv.top := t - gv.bot
			END;
			IF (w > GVPict.width) OR (h > GVPict.height) THEN
				Pictures.Create(GVPict, -((-w) DIV 32) * 32, -((-h) DIV 32) * 32, GVPict.depth)
			END
		END
	END UpdateGV;
	
	PROCEDURE HandleGVAttr (gv: GlyphView; VAR msg: Objects.AttrMsg);
	BEGIN
		IF msg.id = Objects.enum THEN
		ELSIF msg.id = Objects.get THEN
			IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "OTSim.NewGlyphView"; msg.res := 0
			ELSIF msg.name = "ShowGrid" THEN msg.class := Objects.Bool; msg.b := gv.showGrid; msg.res := 0
			ELSIF msg.name = "ShowPattern" THEN msg.class := Objects.Bool; msg.b := gv.showPattern; msg.res := 0
			ELSIF msg.name = "ShowOutline" THEN msg.class := Objects.Bool; msg.b := gv.showOutline; msg.res := 0
			ELSIF msg.name = "ShowTwilight" THEN msg.class := Objects.Bool; msg.b := gv.showTwilight; msg.res := 0
			ELSIF msg.name = "ShowPoints" THEN msg.class := Objects.Bool; msg.b := gv.showPoints; msg.res := 0
			ELSE Gadgets.framehandle(gv, msg)
			END
		ELSIF msg.id = Objects.set THEN
			IF (msg.name = "ShowGrid") & (msg.class = Objects.Bool) THEN gv.showGrid := msg.b; msg.res := 0
			ELSIF (msg.name = "ShowPattern") & (msg.class = Objects.Bool) THEN gv.showPattern := msg.b; msg.res := 0
			ELSIF (msg.name = "ShowOutline") & (msg.class = Objects.Bool) THEN gv.showOutline := msg.b; msg.res := 0
			ELSIF (msg.name = "ShowTwilight") & (msg.class = Objects.Bool) THEN gv.showTwilight := msg.b; msg.res := 0
			ELSIF (msg.name = "ShowPoints") & (msg.class = Objects.Bool) THEN gv.showPoints := msg.b; msg.res := 0
			ELSE Gadgets.framehandle(gv, msg)
			END
		END
	END HandleGVAttr;
	
	PROCEDURE HandleGlyphView (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR gv, copy: GlyphView; fx, fy, x, y: INTEGER; mask: Display3.Mask; ver: LONGINT;
	BEGIN
		gv := obj(GlyphView);
		IF msg IS Display.FrameMsg THEN
			WITH msg: Display.FrameMsg DO
				IF (msg.F = NIL) OR (msg.F = gv) THEN
					fx := msg.x + gv.X; fy := msg.y + gv.Y;
					IF msg IS Display.DisplayMsg THEN
						WITH msg: Display.DisplayMsg DO
							IF msg.device = Display.screen THEN
								IF (msg.id = Display.full) OR (msg.F = NIL) THEN
									Gadgets.MakeMask(gv, fx, fy, msg.dlink, mask);
									RestoreGV(gv, mask, fx, fy, fx, fy, gv.W, gv.H)
								ELSIF msg.id = Display.area THEN
									Gadgets.MakeMask(gv, fx, fy, msg.dlink, mask);
									x := fx + msg.u; y := fy + gv.H - 1 + msg.v;
									Display3.AdjustMask(mask, x, y, msg.w, msg.h);
									RestoreGV(gv, mask, fx, fy, x, y, msg.w, msg.h)
								END
							ELSIF msg.device = Display.printer THEN
								(* too lazy for the moment *)
							END
						END
					ELSIF msg IS Display.ModifyMsg THEN
						WITH msg: Display.ModifyMsg DO
							UpdateGV(gv, msg.W, msg.H);
							Gadgets.Adjust(gv, msg)
						END
					ELSIF msg IS Gadgets.UpdateMsg THEN
						WITH msg: Gadgets.UpdateMsg DO
							IF msg.obj = gv.obj THEN
								UpdateGV(gv, gv.W, gv.H);
								Gadgets.Update(gv)
							END
						END
					ELSE
						Gadgets.framehandle(gv, msg)
					END
				END
			END
		ELSIF msg IS Objects.AttrMsg THEN
			HandleGVAttr(gv, msg(Objects.AttrMsg))
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # gv.stamp THEN
					NEW(copy); gv.dlink := copy; gv.stamp := msg.stamp;
					Gadgets.CopyFrame(msg, gv, copy);
					UpdateGV(copy, copy.W, copy.H)
				END;
				msg.obj := gv.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Gadgets.framehandle(gv, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 2);
					Files.WriteBool(msg.R, gv.showGrid); Files.WriteBool(msg.R, gv.showPattern);
					Files.WriteBool(msg.R, gv.showOutline); Files.WriteBool(msg.R, gv.showTwilight);
					Files.WriteBool(msg.R, gv.showPoints)
				ELSIF msg.id = Objects.store THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 2 THEN
						Files.ReadBool(msg.R, gv.showGrid); Files.ReadBool(msg.R, gv.showPattern);
						Files.ReadBool(msg.R, gv.showOutline); Files.ReadBool(msg.R, gv.showTwilight);
						Files.ReadBool(msg.R, gv.showPoints)
					END;
					UpdateGV(gv, gv.W, gv.H)
				END
			END
		ELSE
			Gadgets.framehandle(gv, msg)
		END
	END HandleGlyphView;
	
	PROCEDURE NewGlyphView*;
		VAR gv: GlyphView;
	BEGIN
		NEW(gv); gv.handle := HandleGlyphView;
		gv.W := 320; gv.H := 320; gv.obj := DummyModel;
		gv.showGrid := TRUE; gv.showPattern := TRUE; gv.showOutline := TRUE; gv.showPoints := TRUE;
		Objects.NewObj := gv
	END NewGlyphView;
	
	
	(**--- Commands ---**)
	
	PROCEDURE FindModel (VAR model: Model): BOOLEAN;
		VAR context, obj: Objects.Object;
	BEGIN
		context := Gadgets.context;
		REPEAT
			obj := Gadgets.FindObj(context, ModelName);
			IF (obj # NIL) & (obj IS Model) THEN
				model := obj(Model);
				RETURN TRUE
			END;
			context := context.dlink
		UNTIL context = NIL;
		Str("no OTSim.Model found");
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
		RETURN FALSE
	END FindModel;
	
	PROCEDURE open (model: Model);
		VAR pos, len: LONGINT; r: Files.Rider; numGlyphs: INTEGER;
	BEGIN
		model.font := OType.Open(model.fileName);
		IF model.font = NIL THEN Str("couldn't open '") ELSE Str("loaded '") END;
		Str(model.fileName); Str("'"); Log(model);
		InvalidateContext(model);
		model.state := Loaded;
		ASSERT(OType.FindTable(model.font, "head", pos, len));
		Files.Set(r, model.font.file, pos+18); OType.ReadInt(r, model.upm);
		Files.Set(r, model.font.file, pos+36);
		OType.ReadInt(r, model.xMin); OType.ReadInt(r, model.yMin);
		OType.ReadInt(r, model.xMax); OType.ReadInt(r, model.yMax);
		IF model.numGlyphs # NIL THEN
			IF model.font # NIL THEN
				ASSERT(OType.FindTable(model.font, "maxp", pos, len));
				Files.Set(r, model.font.file, pos + 4);
				OType.ReadInt(r, numGlyphs);
				Attributes.SetInt(model.numGlyphs, "Max", numGlyphs-1)
			ELSE
				Attributes.SetInt(model.numGlyphs, "Max", 0)
			END;
			Gadgets.Update(model.numGlyphs)
		ELSE Str("no numGlyphs object found"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END open;
	
	(** open filename designated by Oberon.Par **)
	PROCEDURE Open*;
		VAR model: Model; s: Attributes.Scanner; context: Objects.Object;
	BEGIN
		IF FindModel(model) THEN
			Attributes.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
			Attributes.Scan(s);
			IF s.class IN {Attributes.Name, Attributes.String} THEN
				Reset(model);
				Str("loading '"); Str(s.s); Str("'"); Log(model);
				model.state := Loading;
				COPY(s.s, model.fileName);
				model.xMin := 0; model.yMin := 0; model.xMax := 0; model.yMax := 0;
				context := Gadgets.context;
				REPEAT
					model.numGlyphs := Gadgets.FindObj(context, "NumGlyphs");
					context := context.dlink
				UNTIL (context = NIL) OR (model.numGlyphs # NIL);
				Execute(model, open, model.debugFontProg);
				Gadgets.Update(model)
			ELSE
				Str("file name expected"); Log(model)
			END
		END
	END Open;
	
	PROCEDURE instantiate (model: Model);
	BEGIN
		OType.GetInstance(model.font, model.ptsize, model.xdpi, model.ydpi, OType.Identity, model.inst);
		Str("instance ready"); Log(model);
		InvalidateContext(model);
		model.state := Instantiated
	END instantiate;
	
	(** instantiate font; Instantiate pointsize xdpi [ydpi] **)
	PROCEDURE Instantiate*;
		VAR model: Model; s: Attributes.Scanner; name: ARRAY 64 OF CHAR;
	BEGIN
		IF FindModel(model) THEN
			Attributes.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
			Attributes.Scan(s);
			IF s.class IN {Attributes.Int, Attributes.Real, Attributes.LongReal} THEN
				IF s.class = Attributes.Int THEN model.ptsize := 40H*s.i
				ELSIF s.class = Attributes.Real THEN model.ptsize := ENTIER(40H*s.x + 0.5)
				ELSE model.ptsize := ENTIER(40H*s.y + 0.5)
				END;
				Attributes.Scan(s);
				IF s.class = Attributes.Int THEN
					model.xdpi := SHORT(s.i);
					Attributes.Scan(s);
					IF s.class = Attributes.Int THEN model.ydpi := SHORT(s.i)
					ELSE model.ydpi := model.xdpi
					END;
					IF model.state >= Loading THEN
						Reset(model);
						OType.GetName(model.font, OType.FullName, name);
						Str("instance '"); Str(name);
						F26D6ToStr(model.ptsize, 0, name, 0);
						Str("' size="); Str(name);
						IF model.xdpi = model.ydpi THEN Str(" dpi="); Int(model.xdpi); Log(model)
						ELSE Str(" xdpi="); Int(model.xdpi); Str(" ydpi="); Int(model.ydpi); Log(model)
						END;
						model.state := Instantiating;
						Execute(model, instantiate, model.debugCVTProg);
						Gadgets.Update(model)
					ELSE Str("no font has been opened"); Log(model)
					END
				ELSE Str("integer dpi value expected"); Log(model)
				END
			ELSE Str("numeric point size value expected"); Log(model)
			END
		END
	END Instantiate;
	
	PROCEDURE load (model: Model);
		VAR mode: SET;
	BEGIN
		mode := {OType.Width, OType.Outline};
		IF model.hinted THEN INCL(mode, OType.Hinted) END;
		IF model.glyph = NIL THEN NEW(model.glyph) END;
		IF model.glyph.font # model.font THEN OType.InitGlyph(model.glyph, model.font) END;
		OType.LoadGlyph(model.inst, model.glyph, model.glyphNo, mode);
		Str("glyph loaded"); Log(model);
		InvalidateContext(model);
		model.state := Hinted
	END load;
	
	(** load glyph n or character ch **)
	PROCEDURE Load*;
		VAR model: Model; s: Attributes.Scanner;
	BEGIN
		IF FindModel(model) THEN
			Attributes.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
			Attributes.Scan(s);
			IF s.class IN {Attributes.Int, Attributes.Char, Attributes.Name, Attributes.String} THEN
				IF s.class = Attributes.Int THEN
					model.glyphNo := SHORT(s.i)
				ELSIF s.class = Attributes.Char THEN
					model.glyphNo := OType.UnicodeToGlyph(model.font, OType.CharToUnicode[ORD(s.c)])
				ELSE
					model.glyphNo := OType.UnicodeToGlyph(model.font, OType.CharToUnicode[ORD(s.s[0])])
				END;
				IF model.state >= Instantiating THEN
					Reset(model);
					Str("load glyph "); Int(model.glyphNo); Log(model);
					model.state := Hinting;
					Execute(model, load, TRUE);	(* always break to copy outline *)
					IF ~model.debugGlyphProg THEN Resume(model) END;	(* break point at start of code *)
					IF ~model.debugGlyphProg THEN Resume(model) END;	(* break point at end of code *)
					Gadgets.Update(model)
				ELSE Str("no font instance created"); Log(model)
				END
			ELSE Str("glyph number or character expected"); Log(model)
			END
		END
	END Load;
	
	(** resume execution if previously interrupted **)
	PROCEDURE Continue*;
		VAR model: Model;
	BEGIN
		IF FindModel(model) THEN
			Resume(model);
			Gadgets.Update(model)
		END
	END Continue;
	
	(** execute next instruction, stepping into function calls **)
	PROCEDURE Step*;
		VAR model: Model;
	BEGIN
		IF FindModel(model) & (model.state IN ExecStates) THEN
			BreakStep(model);
			Resume(model);
			Gadgets.Update(model)
		END
	END Step;
	
	(** execute next instruction, executing whole functions **)
	PROCEDURE Next*;
		VAR model: Model;
	BEGIN
		IF FindModel(model) & (model.state IN ExecStates) THEN
			BreakNext(model);
			Resume(model);
			Gadgets.Update(model)
		END
	END Next;
	
	(** finish current function call **)
	PROCEDURE Finish*;
		VAR model: Model;
	BEGIN
		IF FindModel(model) & (model.state IN ExecStates) THEN
			BreakFinish(model);
			Resume(model);
			Gadgets.Update(model)
		END
	END Finish;
	
	
	(**--- Character Object ---**)
	
	PROCEDURE HandleChar (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR char, copy: Char; ver: LONGINT;
	BEGIN
		char := obj(Char);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Value"); msg.Enum("String");
					Gadgets.objecthandle(char, msg)
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "OTSim.NewChar"; msg.res := 0
					ELSIF msg.name = "Value" THEN msg.class := Objects.Int; msg.i := ORD(char.val); msg.res := 0
					ELSIF msg.name = "String" THEN msg.class := Objects.String; msg.s[0] := char.val; msg.s[1] := 0X; msg.res := 0
					ELSE Gadgets.objecthandle(char, msg)
					END
				ELSIF msg.id = Objects.set THEN
					IF (msg.name = "Value") & (msg.class = Objects.Int) THEN char.val := CHR(msg.i); msg.res := 0
					ELSIF (msg.name = "String") & (msg.class = Objects.String) THEN char.val := msg.s[0]; msg.res := 0
					ELSE Gadgets.objecthandle(char, msg)
					END
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # char.stamp THEN
					NEW(copy); char.dlink := copy; char.stamp := msg.stamp;
					Gadgets.CopyObject(msg, char, copy);
					copy.val := char.val
				END;
				msg.obj := char.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Gadgets.objecthandle(char, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Files.Write(msg.R, char.val)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 1 THEN Files.Read(msg.R, char.val) END
				END
			END
		ELSE
			Gadgets.objecthandle(char, msg)
		END
	END HandleChar;
	
	PROCEDURE NewChar*;
		VAR char: Char;
	BEGIN
		NEW(char); char.handle := HandleChar; char.val := 0X;
		Objects.NewObj := char
	END NewChar;
	
	
	(*--- Initialization ---*)
	
	PROCEDURE InitInstr;
		VAR i, j, n: LONGINT; s: ARRAY 11 OF CHAR;
		
		PROCEDURE hex (n: LONGINT): CHAR;
		BEGIN
			IF n < 10 THEN RETURN CHR(ORD("0") + n)
			ELSE RETURN CHR(ORD("A") - 10 + n)
			END
		END hex;
		
		PROCEDURE add (s: ARRAY OF CHAR);
			VAR k: LONGINT; ch: CHAR;
		BEGIN
			InstrIdx[j] := SHORT(i); INC(j);
			k := 0;
			REPEAT
				ch := s[k];
				IF ch = "." THEN
					InstrStr[i] := 0X; INC(i);
					InstrIdx[j] := SHORT(i); INC(j);
					INC(k); ch := s[k]
				END;
				InstrStr[i] := ch;
				INC(i); INC(k)
			UNTIL ch = 0X
		END add;
		
	BEGIN
		i := 0; j := 0;
		add("SVTCA[0].SVTCA[1].SPVTCA[0].SPVTCA[1].SFVTCA[0].SFVTCA[1].SPVTL[0].SPVTL[1].SFVTL[0].SFVTL[1]");
		add("SPVFS.SFVFS.GPV.GFV.SFVTPV.ISECT.SRP0.SRP1.SRP2.SZP0.SZP1.SZP2.SZPS.SLOOP.RTG.RTHG.SMD");
		add("ELSE.JMPR.SCVTCI.SSWCI.SSW.DUP.POP.CLEAR.SWAP.DEPTH.CINDEX.MINDEX.ALIGNPTS.-28-");
		add("UTP.LOOPCALL.CALL.FDEF.ENDF.MDAP[0].MDAP[1].IUP[0].IUP[1].SHP[0].SHP[1].SHC[0].SHC[1]");
		add("SHZ[0].SHZ[1].SHPIX.IP.MSIRP[0].MSIRP[1].ALIGNRP.RTDG.MIAP[0].MIAP[1].NPUSHB.NPUSHW");
		add("WS.RS.WCVTP.RCVT.GC[0].GC[1].SCFS.MD[1].MD[0].MPPEM.MPS.FLIPON.FLIPOFF.DEBUG");
		add("LT.LTEQ.GT.GTEQ.EQ.NEQ.ODD.EVEN.IF.EIF.AND.OR.NOT.DELTAP1.SDB.SDS.ADD.SUB.DIV.MUL");
		add("ABS.NEG.FLOOR.CEILING.ROUND[0].ROUND[1].ROUND[2].ROUND[3].NROUND[0].NROUND[1]");
		add("NROUND[2].NROUND[3].WCVTF.DELTAP2.DELTAP3.DELTAC1.DELTAC2.DELTAC3.SROUND.S45ROUND");
		add("JROT.JROF.ROFF.-7B-.RUTG.RDTG.SANGW.AA.FLIPPT.FLIPRGON.FLIPRGOFF.-83-.-84-");
		add("SCANCTRL.SDPVTL[0].SDPVTL[1].GETINFO.IDEF.ROLL.MAX.MIN.SCANTYPE.INSTCTRL");
		s := "-00-";
		FOR n := 8FH TO 0AFH DO
			s[1] := hex(n DIV 10H); s[2] := hex(n MOD 10H); add(s)
		END;
		s := "PUSHB[0]";
		FOR n := ORD("0") TO ORD("7") DO
			s[6] := CHR(n); add(s)
		END;
		s := "PUSHW[0]";
		FOR n := ORD("0") TO ORD("7") DO
			s[6] := CHR(n); add(s)
		END;
		s := "MDRP[0000]";
		FOR n := 0 TO 1FH DO
			s[5] := hex(n DIV 10H); s[6] := hex(n DIV 8 MOD 2); s[7] := hex(n DIV 4 MOD 2); s[8] := hex(n MOD 4); add(s)
		END;
		s := "MIRP[0000]";
		FOR n := 0 TO 1FH DO
			s[5] := hex(n DIV 10H); s[6] := hex(n DIV 8 MOD 2); s[7] := hex(n DIV 4 MOD 2); s[8] := hex(n MOD 4); add(s)
		END;
		
		Arg[00H] := 0; Arg[01H] := 0; Arg[02H] := 0; Arg[03H] := 0; Arg[04H] := 0; Arg[05H] := 0; Arg[06H] := 2; Arg[07H] := 2;
		Arg[08H] := 2; Arg[09H] := 2; Arg[0AH] := 2; Arg[0BH] := 2; Arg[0CH] := 0; Arg[0DH] := 0; Arg[0EH] := 0; Arg[0FH] := 5;
		Arg[10H] := 1; Arg[11H] := 1; Arg[12H] := 1; Arg[13H] := 1; Arg[14H] := 1; Arg[15H] := 1; Arg[16H] := 1; Arg[17H] := 1;
		Arg[18H] := 0; Arg[19H] := 0; Arg[1AH] := 1; Arg[1BH] := 0; Arg[1CH] := 1; Arg[1DH] := 1; Arg[1EH] := 1; Arg[1FH] := 1;
		Arg[20H] := 1; Arg[21H] := 1; Arg[22H] := 0; Arg[23H] := 2; Arg[24H] := 0; Arg[25H] := 1; Arg[26H] := 1; Arg[27H] := 2;
		Arg[28H] := 0; Arg[29H] := 1; Arg[2AH] := 2; Arg[2BH] := 1; Arg[2CH] := 1; Arg[2DH] := 0; Arg[2EH] := 1; Arg[2FH] := 1;
		Arg[30H] := 0; Arg[31H] := 0; Arg[32H] := 0; Arg[33H] := 0; Arg[34H] := 1; Arg[35H] := 1; Arg[36H] := 1; Arg[37H] := 1;
		Arg[38H] := 0; Arg[39H] := 0; Arg[3AH] := 2; Arg[3BH] := 2; Arg[3CH] := 0; Arg[3DH] := 0; Arg[3EH] := 2; Arg[3FH] := 2;
		Arg[40H] := 0; Arg[41H] := 0; Arg[42H] := 2; Arg[43H] := 1; Arg[44H] := 2; Arg[45H] := 1; Arg[46H] := 1; Arg[47H] := 1;
		Arg[48H] := 2; Arg[49H] := 2; Arg[4AH] := 2; Arg[4BH] := 0; Arg[4CH] := 0; Arg[4DH] := 0; Arg[4EH] := 0; Arg[4FH] := 0;
		Arg[50H] := 2; Arg[51H] := 2; Arg[52H] := 2; Arg[53H] := 2; Arg[54H] := 2; Arg[55H] := 2; Arg[56H] := 1; Arg[57H] := 1;
		Arg[58H] := 1; Arg[59H] := 0; Arg[5AH] := 2; Arg[5BH] := 2; Arg[5CH] := 1; Arg[5DH] := 0; Arg[5EH] := 1; Arg[5FH] := 1;
		Arg[60H] := 2; Arg[61H] := 2; Arg[62H] := 2; Arg[63H] := 2; Arg[64H] := 1; Arg[65H] := 1; Arg[66H] := 1; Arg[67H] := 1;
		Arg[68H] := 1; Arg[69H] := 1; Arg[6AH] := 1; Arg[6BH] := 1; Arg[6CH] := 1; Arg[6DH] := 1; Arg[6EH] := 1; Arg[6FH] := 1;
		Arg[70H] := 2; Arg[71H] := 0; Arg[72H] := 0; Arg[73H] := 0; Arg[74H] := 0; Arg[75H] := 0; Arg[76H] := 1; Arg[77H] := 1;
		Arg[78H] := 2; Arg[79H] := 2; Arg[7AH] := 0; Arg[7BH] := 0; Arg[7CH] := 0; Arg[7DH] := 0; Arg[7EH] := 1; Arg[7FH] := 1;
		Arg[80H] := 0; Arg[81H] := 2; Arg[82H] := 2; Arg[83H] := 0; Arg[84H] := 0; Arg[85H] := 1; Arg[86H] := 2; Arg[87H] := 2;
		Arg[88H] := 1; Arg[89H] := 1; Arg[8AH] := 0; Arg[8BH] := 2; Arg[8CH] := 2; Arg[8DH] := 1; Arg[8EH] := 1;
		FOR n := 8FH TO 0BFH DO Arg[n] := 0 END;
		FOR n := 0C0H TO 0DFH DO Arg[n] := 1 END;
		FOR n := 0E0H TO 0FFH DO Arg[n] := 2 END
	END InitInstr;
	

BEGIN
	Texts.OpenWriter(W);
	NEW(DummyModel); InitModel(DummyModel, HandleModel);
	NEW(Buffer); Pictures.Create(Buffer, 1280, MVLineH, Display.Depth(Display.ColLeft));
	MVFont := Fonts.This("Courier10.Scn.Fnt");
	GVFont := Fonts.This("Oberon10b.Scn.Fnt");
	NEW(GVPict); Pictures.Create(GVPict, 320, 320, Display.Depth(Display.ColLeft));
	InitPatterns;
	InitInstr
END OTSim.
