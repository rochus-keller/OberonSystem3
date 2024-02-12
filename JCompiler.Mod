(*
	Juice(TM), Version 1.1

	Copyright (c) 1996-1997 Regents of the University of California. 
	All rights reserved.

	This software was developed as part of the Juice project by the research 
	group of Prof. Dr. M. Franz at the University of California, Irvine.
	http://www.ics.uci.edu/~juice

	Redistribution and use in source and binary forms are permitted
	provided that:
	
	(a)	the above copyright notice and this paragraph are duplicated 
			in all such forms and provided that any documentation,
			advertising materials, and other materials related to such
			distribution and use acknowledge that the software was 
			developed by the University of California, Irvine.  
		
	(b)	all interface changes and all conversions of this software to other 
			platforms agree with style and content of Juice. In case of doubt
			juice-request@ics.uci.edu shall be asked for consent.
	
	The name of the University may not be used to endorse or promote products derived
	from this software without specific prior written permission.
	
	THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
	IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
	WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

	"Juice" is a trademark owned by the Regents of the University of California
*)

MODULE JCompiler;	(* tk 8/5/96 *)

	(* Juice Compiler *)

	IMPORT
		Texts, Oberon, Display, Objects, Files,
		OPP := JOCP, OPB := JOCB, OPT := JOCT,
		OPS := JOCS, OPM := JOCM, POPV := JOCV;
	
	CONST
		(* compiler options: *)
		newsf = 10;	(* s - generation of new symbol file allowed *)
		extsf =11;	(* e - generation of extended symbol file allowed *)
		warning = 12;	(* w - display warnings *)
		
	VAR
		signedOn: BOOLEAN;
		source: Texts.Text; sourceR: Texts.Reader;
		S: Texts.Scanner; W: Texts.Writer;
		dpath: ARRAY 512 OF CHAR; 

	PROCEDURE SignOn;
	BEGIN
		IF ~signedOn THEN signedOn := TRUE;
			Texts.WriteString(W, "Oberon Portable Compiler / nw & rc"); Texts.WriteLn(W);
			Texts.WriteString(W, "Slim Binary Code Generator  / mf & tk 9.7.96"); Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END
	END SignOn;
		
	PROCEDURE ThisFrame(X, Y: INTEGER; VAR F: Display.Frame);
		VAR M: Display.LocateMsg;
	BEGIN	M.X := X; M.Y := Y; M.F := NIL; M.loc := NIL; Display.Broadcast(M); F := M.loc
	END ThisFrame;

	PROCEDURE GetText(VAR par: Display.Frame): Texts.Text;
		VAR M: Objects.LinkMsg; t: Texts.Text;
	BEGIN
		t := NIL; ThisFrame(Oberon.Pointer.X, Oberon.Pointer.Y, par);
		IF par # NIL THEN
			M.id := Objects.get; M.name := "Model"; M.obj := NIL; M.res := -1; par.handle(par, M);
			IF (M.obj # NIL) & (M.obj IS Texts.Text) THEN t := M.obj(Texts.Text) END
		END;
		RETURN t
	END GetText;
				
	PROCEDURE Module* (source: Texts.Reader; opt: ARRAY OF CHAR; log: Texts.Text; VAR error: BOOLEAN);
		VAR newSF, extSF: BOOLEAN; options: SET; p: OPT.Node; modName: OPS.Name; i: INTEGER; ch: CHAR;
	BEGIN
		options := {}; i := 0;
		REPEAT	ch := opt[i]; INC(i);				
			IF ch = "s" THEN options := options / {newsf}
			ELSIF ch = "e" THEN options := options / {extsf}
			ELSIF ch = "w" THEN options := options / {warning}
			END
		UNTIL ch = 0X;
		OPM.Init(options, source, log); OPB.typSize := POPV.NoTypSize; OPT.typSize := POPV.NoTypSizeF;
		newSF := newsf IN options; extSF := extsf IN options;
		OPP.Module(p, modName, options);
		IF OPM.noerr THEN OPM.Begin(modName);
			OPM.errpos := 0; OPT.Export(modName, newSF, extSF);
			IF newSF THEN OPM.LogWStr(" new symbol file")
			ELSIF extSF THEN OPM.LogWStr(" extended symbol file")
			END;
			OPM.errpos := 0;
			IF OPM.noerr THEN POPV.Module(p) END
		END;
		OPT.CloseScope; OPT.Close;
		OPM.LogWLn; error := ~OPM.noerr
	END Module;
	
	PROCEDURE Compile*;
		VAR beg, end, time: LONGINT; error: BOOLEAN; ch: CHAR; F: Display.Frame; 
				defopt: ARRAY 32 OF CHAR; f: Files.File;  
				
		PROCEDURE GetOptions(VAR options: ARRAY OF CHAR);
			VAR i: SHORTINT;
		BEGIN	i := 0; 
			ch := S.nextCh; i := 0;
			WHILE ((ch >= "0") & (ch <= "9") OR (ch >= "a") & (ch <= "z") OR (ch >= "A") & (ch <= "Z")) DO	
				i := 0; WHILE (options[i] # ch) & (options[i] # 0X) DO INC(i) END;
				IF options[i] = 0X THEN options[i] := ch; options[i+1] := 0X END;
				Texts.Read(S, ch)	
			END;
			S.nextCh := ch; Texts.Scan(S)
		END GetOptions;
		
		PROCEDURE Do(filename: ARRAY OF CHAR; beg: LONGINT; options: ARRAY OF CHAR);
			VAR S1: Texts.Scanner; line: INTEGER; name: ARRAY 32 OF CHAR;
		BEGIN
			Texts.WriteString(W, filename); Texts.WriteString(W, "  compiling  ");
			Texts.OpenScanner(S1, source, beg); Texts.Scan(S1);
			WHILE ~S1.eot & ((S1.class # Texts.Name) OR (S1.s # "MODULE")) DO Texts.Scan(S1) END;
			IF (S1.class = Texts.Name) & (S1.s = "MODULE") THEN Texts.Scan(S1); 
				IF S1.class = Texts.Name THEN COPY(S1.s, name); Texts.WriteString(W, S1.s) END
			END;
			Texts.Append(Oberon.Log, W.buf);
			line := S.line; 
			Texts.Scan(S);
			IF (S.line = line) & (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN GetOptions(options) END;
			Texts.OpenReader(sourceR, source, beg);
			Module(sourceR, options, Oberon.Log, error) 
		END Do;

	BEGIN
		error := FALSE; defopt[0] := 0X; COPY(dpath, OPM.outputPath); OPS.Get := NIL; 
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S); SignOn;
		IF (S.class = Texts.Char) & (S.c # Oberon.OptionChar) THEN
			IF S.c = "*" THEN	source := GetText(F);
				IF	source#NIL	THEN	Do("", 0, defopt)	END
			ELSIF S.c = "^" THEN
				Oberon.GetSelection(source, beg, end, time);
				IF time >= 0 THEN
					Texts.OpenScanner(S, source, beg); Texts.Scan(S); NEW(source);
					IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) & (Texts.Pos(S) - S.len <= end) THEN 
						defopt[0] := 0X; GetOptions(defopt)
					END; 
					WHILE (S.class IN {Texts.Name, Texts.String}) & (Texts.Pos(S) - S.len <= end) & ~error DO
						Texts.Open(source, S.s);
						IF source.len # 0 THEN Do(S.s, 0, defopt)
						ELSE
							Texts.WriteString(W, S.s); Texts.WriteString(W, " not found");
							Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf); error := TRUE
						END
					END
				END
			ELSIF S.c = "@" THEN
				Oberon.GetSelection(source, beg, end, time);
				IF time >= 0 THEN Do("", beg, defopt) END
			END
		ELSE NEW(source);
			IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN
				defopt[0] := 0X; GetOptions(defopt)
			END;
			WHILE (S.class IN {Texts.Name, Texts.String}) & ~error DO
				OPS.Get := NIL; 
				f := Files.Old(S.s);
				IF f # NIL THEN
					Texts.Open(source, S.s); Do(S.s, 0, defopt)
				ELSE
					Texts.WriteString(W, S.s); Texts.WriteString(W, " not found");
					Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf); error := TRUE
				END
			END
		END;
		Oberon.Collect; COPY(dpath, OPM.outputPath)
	END Compile;

	PROCEDURE SetDestPath*;
		VAR beg, end, time: LONGINT; T: Texts.Text; S: Texts.Scanner;
	BEGIN	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF	(S.class=Texts.Char)&(S.c="^")	THEN	Oberon.GetSelection(T, beg, end, time);
			IF	time >= 0	THEN	Texts.OpenScanner(S, T, beg); Texts.Scan(S)	END
		END;
		IF	(S.class IN {Texts.Name, Texts.String})	THEN	Texts.WriteString(W, "Compiler.SetDestPath "); Texts.WriteString(W, S.s);
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf); COPY(S.s, dpath); COPY(dpath, OPM.outputPath)
		END
	END SetDestPath;

BEGIN	Texts.OpenWriter(W)
END JCompiler.
