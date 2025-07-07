(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

MODULE Compiler;	(** portable, except where noted *)
	IMPORT
		OPP, OPB, OPV, OPT, OPS, OPC, OPL, OPO, OPM, Modules, Display, Oberon, Texts;
	
	CONST
		NoBreakPC = -1;
		
		module = OPS.module; ident = OPS.ident; period = OPS.period;	(* symbols *)
		
	VAR
		W: Texts.Writer;
	
	PROCEDURE SignOn;
	BEGIN
		Texts.WriteString(W, "Oberon Portable Compiler / nw, rc, nm, tk, prk"); Texts.WriteLn(W);
		Texts.WriteString(W, OPP.SignOnMessage); Texts.WriteLn(W); 
		Texts.Append(Oberon.Log, W.buf)
	END SignOn;
	
	PROCEDURE GetOptions(VAR S: Texts.Scanner; VAR opts: ARRAY OF CHAR);
		VAR i: LONGINT; ch: CHAR;
	BEGIN	
		WHILE (S.class = Texts.Char) & (S.c = Oberon.OptionChar) DO
			i := 0;
			WHILE opts[i] # 0X DO  INC(i)  END;
			ch := S.nextCh;
			WHILE ch > " " DO
				opts[i] := ch;  INC(i);  Texts.Read(S, ch)
			END;
			opts[i] := " "; INC(i);
			opts[i] := 0X;  S.nextCh := ch; Texts.Scan(S)
		END;
	END GetOptions;
	
	PROCEDURE InOptions(VAR opt: ARRAY OF CHAR; ch: CHAR): BOOLEAN;
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE (opt[i] # 0X) & (opt[i] # ch) DO  
			IF (opt[i] = ".") OR (opt[i] = "P") THEN
				REPEAT  INC(i)   UNTIL (opt[i] = 0X) OR (opt[i] = " ")
			ELSE INC(i) END
		END;
		RETURN opt[i] = ch
	END InOptions;
	
	PROCEDURE Locate(F: Display.Frame;  T: Texts.Text;  pos: LONGINT);
	VAR M: Oberon.CaretMsg;  N: Oberon.ControlMsg;
	BEGIN
		IF pos < 0 THEN pos := 0
		ELSIF pos > T.len THEN pos := T.len
		END;
		N.F := NIL; N.id := Oberon.neutralize; Display.Broadcast(N);
		Oberon.FadeCursor(Oberon.Pointer);
		M.id := Oberon.set; M.F := F; M.car := F; M.text := T; M.pos := pos; Display.Broadcast(M)
	END Locate;

	PROCEDURE GetBreakPC(): LONGINT;
		VAR S: Texts.Scanner; t: Texts.Text;  beg, end, time: LONGINT;
	BEGIN
		Oberon.GetSelection(t, beg, end, time);
		IF time >= 0 THEN
			Texts.OpenScanner(S, t, beg); Texts.Scan(S);
			end := S.line;
			WHILE (S.class # Texts.Int) & (S.line = end) DO  Texts.Scan(S)  END;
		END;
		IF (time < 0) OR (S.class # Texts.Int) THEN
			Texts.WriteString(W, "  pc not selected"); Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf);
			RETURN NoBreakPC
		ELSE
			RETURN S.i
		END
	END GetBreakPC;
	
	PROCEDURE ParseOptions(VAR name, options, path, pref, extension: ARRAY OF CHAR;  VAR opt: SET);
	VAR i, j, k: LONGINT;  ch: CHAR;
	BEGIN
		opt := OPM.DefOpt; i := 0; path[0] := 0X; pref[0] := 0X;
(*
		IF Modules.extension = ".Obx" THEN INCL(opt, OPM.aos) END;
*)
		COPY(Modules.extension, extension);
		LOOP
			ch := options[i]; INC(i);
			IF ch = 0X THEN EXIT
			ELSIF ch = "x" THEN opt := opt / {OPM.inxchk}
			ELSIF ch = "v" THEN opt := opt / {OPM.ovflchk}
			ELSIF ch = "t" THEN opt := opt / {OPM.typchk}
			ELSIF ch = "s" THEN opt := opt / {OPM.newsf}
			ELSIF ch = "p" THEN opt := opt / {OPM.ptrinit}
			ELSIF ch = "a" THEN opt := opt / {OPM.assert}
			ELSIF ch = "S" THEN opt := opt / {OPM.systemchk}
			ELSIF ch = "n" THEN opt := opt / {OPM.nofiles}
			ELSIF ch = "e" THEN opt := opt / {OPM.extsf}
			ELSIF ch = "f" THEN opt := opt / {OPM.findpc}
			ELSIF ch = "w" THEN opt := opt / {OPM.warning}
			ELSIF ch = "X" THEN opt := opt + {OPM.prefix}
			ELSIF ch = "2" THEN opt := opt / {OPM.oberon2}
			ELSIF ch = "z" THEN opt := opt / {OPM.fullstackinit}
			ELSIF ch = "1" THEN opt := opt / {OPM.oberon1}
			ELSIF ch = "q" THEN opt := opt / {OPM.trace}
			ELSIF ch = "A" THEN opt := opt + {OPM.aos}
			ELSIF ch = "E" THEN opt := opt - {OPM.aos}
			ELSIF ch = "T" THEN opt := opt / {OPM.traceprocs}	(* temp *)
			ELSIF ch = "." THEN
				j := 0;
				WHILE (ch # 0X) & (ch # " ") DO
					extension[j] := ch; ch := options[i];
					INC(j); INC(i)
				END;
				extension[j] := 0X
			ELSIF ch = "P" THEN
				ch := options[i];  INC(i);
				k := 0;
				WHILE (ch # 0X) & (ch # " ") DO
					path[k] := ch;  INC(k);
					ch := options[i];  INC(i)
				END;
				path[k] := 0X
			ELSIF ch = "O" THEN	(* mutually exclusive with "X" *)
				ch := options[i];  INC(i);
				k := 0;
				WHILE (ch # 0X) & (ch # " ") DO
					pref[k] := ch;  INC(k);
					ch := options[i];  INC(i)
				END;
				pref[k] := 0X
			END
		END;
		IF OPM.prefix IN opt THEN
			i := -1; REPEAT INC(i); pref[i] := name[i] UNTIL (name[i] = 0X) OR (name[i] = ".");
			IF name[i] # "." THEN i := 0 ELSE INC(i) END;
			pref[i] := 0X
		END
	END ParseOptions;
	
	PROCEDURE WriteMsg(source: Texts.Reader;  log: Texts.Text);
	VAR sym: SHORTINT;
	BEGIN
		Texts.WriteString(W, " compiling ");
		OPM.Init({}, source, log); OPS.Get(sym);
		IF sym = module THEN
			OPS.Get(sym);
			IF sym = ident THEN
				Texts.WriteString(W, OPM.outputPath);
				Texts.WriteString(W, OPM.outputPrefix);
				OPS.Get(sym); Texts.WriteString(W, OPS.name);
				WHILE sym = period DO
					Texts.Write(W, ".");
					OPS.Get(sym);
					IF sym = ident THEN Texts.WriteString(W, OPS.name); OPS.Get(sym) END;
				END;
				IF OPM.extension # Modules.extension THEN
					Texts.WriteString(W, OPM.extension)
				ELSIF (OPM.outputPath = "") & (OPM.outputPrefix = "") THEN	(* not cross-compiling *)
					IF Modules.FindMod(OPS.name) # NIL THEN
						Texts.WriteString(W, " (in use) ")
					END
				ELSE
					(* skip *)
				END
			END
		END;
		Texts.Append(log, W.buf)
	END WriteMsg;
	
	PROCEDURE Module*(source: Texts.Reader; name, options: ARRAY OF CHAR; breakpc: LONGINT;
			log: Texts.Text; VAR error: BOOLEAN);
		VAR opt: SET; extSF, newSF: BOOLEAN; p: OPT.Node; modName: OPS.Name;
	BEGIN
		ParseOptions(name, options, OPM.outputPath, OPM.outputPrefix, OPM.extension, opt);
		WriteMsg(source, log);
		OPM.Init(opt, source, log); OPS.ch := " ";
		OPB.typSize := OPV.TypSize; OPV.Init(opt, breakpc);
		newSF := OPM.newsf IN opt; extSF := OPM.extsf IN opt;
		OPP.Module(p, modName);
		IF OPM.noerr THEN
			OPL.Init;
			OPM.errpos := 0;
			OPM.Begin(modName);
			IF OPM.noerr THEN
				OPT.Export(modName, newSF, extSF);
				OPV.AdrAndSize(OPT.topScope);
				IF newSF THEN OPM.LogWStr(" new symbol file")
				ELSIF extSF THEN OPM.LogWStr(" extended symbol file")
				END;
				IF OPM.noerr THEN
					OPM.errpos := 0;
					OPC.Init;
					OPV.Module(p);
					IF OPM.noerr THEN
						OPL.OutCode(modName);
						IF OPM.noerr THEN
							OPM.LogWStr ("   "); OPM.LogWNum(OPO.pc, 1)
						END
					END
				END;
				OPL.Close
			END
		END;
		OPT.CloseScope; OPT.Close;
		OPM.LogWLn; error := ~OPM.noerr;
		OPM.outputPath := "!"; OPM.outputPrefix := "!"	(* invalid filename *)
	END Module;

	PROCEDURE CompileText(t: Texts.Text; pos: LONGINT; frame: Display.Frame; opt: ARRAY OF CHAR; VAR error: BOOLEAN);
		VAR f: BOOLEAN; pc: LONGINT; r: Texts.Reader;
	BEGIN
		IF t # NIL THEN
			Texts.OpenReader(r, t, pos);
			f := InOptions(opt, "f");
			IF f THEN
				pc := GetBreakPC();
				IF pc = NoBreakPC THEN RETURN END
			END;
			OPS.Init;
			Module(r, "", opt, pc, Oberon.Log, error);
			IF f & (frame # NIL) THEN
				Locate(frame, t, OPM.breakpos)
			END
		ELSE
			Texts.WriteString(W, "No text marked"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
			error := TRUE
		END
	END CompileText;

	PROCEDURE CompileFile*(name, opt: ARRAY OF CHAR; VAR error: BOOLEAN);
		VAR t: Texts.Text; r: Texts.Reader; pc: LONGINT;
	BEGIN
		NEW(t); Texts.Open(t, name);
		IF t.len # 0 THEN
			Texts.OpenReader(r, t, 0);
			IF InOptions(opt, "f") THEN
				pc := GetBreakPC();
				IF pc = NoBreakPC THEN RETURN END
			END;
			Texts.WriteString(W, name);
			OPS.Init;
			Module(r, name, opt, pc, Oberon.Log, error)
		ELSE
			Texts.WriteString(W, name); Texts.WriteString(W, " not found");
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
			error := TRUE
		END
	END CompileFile;
	
	PROCEDURE Compile*;
		VAR S: Texts.Scanner;  globalOpt, localOpt: ARRAY 32 OF CHAR;
			t: Texts.Text; pos, end, time: LONGINT;  frame: Display.Frame;
			name: ARRAY 64 OF CHAR; error: BOOLEAN;
	BEGIN
		error := FALSE;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(S);
		globalOpt := "";  GetOptions(S, globalOpt);
		IF (S.class = Texts.Char) & ((S.c = "*") OR (S.c = "@")) THEN
			IF S.c = "*" THEN
				t := Oberon.MarkedText();  pos := 0;  frame := Oberon.MarkedFrame();
			ELSE (* S.c = "@" *)
				Oberon.GetSelection(t, pos, end, time);  frame := NIL;
				IF time < 0 THEN RETURN END
			END;
			Texts.Scan(S);
			GetOptions(S, globalOpt);
			CompileText(t, pos, frame, globalOpt, error);
		ELSIF ((S.class = Texts.Char) & (S.c = "^")) OR (S.class = Texts.Name) THEN
			IF (S.c = "^") THEN
				Oberon.GetSelection(t, pos, end, time);
				Texts.OpenScanner(S, t, pos); Texts.Scan(S)
			ELSE
				end := MAX(LONGINT)
			END;
			WHILE (S.class = Texts.Name) & (Texts.Pos(S) - S.len <= end) & ~error DO
				COPY(S.s, name);  COPY(globalOpt, localOpt);
				Texts.Scan(S);  GetOptions(S, localOpt);
				CompileFile(name, localOpt, error)
			END
		END
	END Compile;
	
BEGIN
	Texts.OpenWriter(W); SignOn
END Compiler.

Compiler.Compile Test.Mod ~
Compiler.Compile Test.Mod\s ~
Compiler.Compile Test.Mod\sX.Obx ~
Compiler.Compile *
Compiler.Compile *\s
Compiler.Compile \.Obx Test.Mod Test.Mod\.Obf Test.Mod ~
Compiler.Compile @
