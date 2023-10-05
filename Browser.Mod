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


MODULE Browser;	(** portable, except where noted *)
	IMPORT
		Modules, OPM, OPS, OPT, OPV,
		Files, Texts, Display, Oberon, Fonts;

	CONST
		(*visibility*)	internal=0; external=1; externalR=2;
		(*object modes*)	Var=1; VarPar=2; Con=3; Fld=4; Typ=5; LProc=6; XProc=7; CProc=9; TProc=13;
		(*structure forms*)	Bool=2; Char=3; SInt=4; Int=5; LInt=6; Real=7; LReal=8; Set=9; String=10; NilTyp=11;
		(*structure forms*)	Pointer=13; ProcTyp=14; Comp=15; StaticArr=2; DynArr=4; OpenArr = 5; Record = 6;

	VAR
		W, W1: Texts.Writer; Null, T: Texts.Text; Source: Texts.Reader; dum: OPS.Name; show, hidden, extend, signedOn: BOOLEAN; mode: SET;
		NormalFont, TitleFont: Fonts.Font;
		theMod: OPT.Object;
		incr: BOOLEAN;

	PROCEDURE SignOn;
	BEGIN
		IF	~signedOn	THEN	signedOn:=TRUE;
			Texts.WriteString(W, "Module Interface Browser / mf/tk 5.1.96"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END SignOn;

	PROCEDURE Str(s: ARRAY OF CHAR); BEGIN Texts.WriteString(W, s) END Str;
	PROCEDURE Ch(ch: CHAR); BEGIN Texts.Write(W, ch) END Ch;
	PROCEDURE Ln; BEGIN Texts.WriteLn(W) END Ln;
	PROCEDURE Ht(i: INTEGER); BEGIN WHILE i > 0 DO Ch(9X); DEC(i) END END Ht;
	PROCEDURE Dec(i: LONGINT); BEGIN Texts.WriteInt(W, i, 0) END Dec;
	PROCEDURE Hd(i: LONGINT); BEGIN IF i > 9 THEN Ch(CHR(55+i)) ELSE Ch(CHR(48+i)) END END Hd;
	PROCEDURE Hex(i: LONGINT); BEGIN IF i > 9FH THEN Ch("0") END; Hd(i DIV 16); Hd(i MOD 16) END Hex;
	PROCEDURE Adr(i: LONGINT); BEGIN IF show THEN Ch("["); Dec(i); Str("] ") END END Adr;
	PROCEDURE Mrk(vis: INTEGER); BEGIN IF vis=external THEN Ch("*") ELSIF vis=externalR THEN Ch("-") END END Mrk;
	PROCEDURE SFlg(flg: INTEGER); BEGIN IF flg#0 THEN Ch("-") END END SFlg;
	PROCEDURE Title; BEGIN Texts.SetFont (W, TitleFont); END Title;
	PROCEDURE Normal; BEGIN Texts.SetFont (W, NormalFont); END Normal;

	PROCEDURE ^ Structure(typ: OPT.Struct);

	PROCEDURE TypName(typ: OPT.Struct);
		VAR obj: OPT.Object;
	BEGIN	obj:=typ.strobj;
		IF	(obj#NIL)	&	(obj.name#"")	THEN
			IF	typ.mno>1	THEN	Str(OPT.modules[typ.mno].name); Ch(".")
			ELSIF	(typ=OPT.bytetyp) OR (typ=OPT.ptrtyp)	THEN	Str("SYSTEM.")	END;
			Str(obj.name)
		ELSE	Structure(typ)	END
	END TypName;

	PROCEDURE Signature(result: OPT.Struct; par: OPT.Object);
		VAR paren, res, first: BOOLEAN;
	BEGIN	first:=TRUE; res:=result#OPT.notyp; paren:=res OR (par#NIL);
		IF	paren	THEN	Ch("(")	END;
		WHILE	par#NIL	DO
			IF	~first	THEN	Str("; ")	ELSE	first:=FALSE	END;
			IF	par.mode=VarPar	THEN	Str("VAR ")	END;
			Adr(par.adr); Str(par.name);
			WHILE	(par.link#NIL)&(par.link.typ=par.typ)&(par.link.mode=par.mode)	DO	Str(", "); par:=par.link; Adr(par.adr); Str(par.name)	END;
			Str(": "); TypName(par.typ);
			par:=par.link
		END;
		IF	paren	THEN	Ch(")")	END;
		IF	res	THEN	Str(": "); TypName(result)	END
	END Signature;

	PROCEDURE Tproc(obj: OPT.Object);
		VAR rcv: OPT.Object;
	BEGIN
		IF	obj#NIL	THEN	Tproc(obj.left);
			IF	(obj.mode=TProc)&(obj.name#"")&(obj.vis # internal)	THEN	rcv:=obj.link; Ht(3); Adr(obj.adr); Str("PROCEDURE ");
				IF obj.link.typ.strobj.link2 = obj THEN Str(" & ") END;
				Title; Str(obj.name); Normal; Ch("*"); Signature(obj.typ, rcv.link); Ch(";"); Ln
			END;
			Tproc(obj.right)
		END
	END Tproc;

	PROCEDURE RecType(typ: OPT.Struct);
		VAR fld: OPT.Object;
	BEGIN
		fld:=typ.link; Ln;
		WHILE	(fld#NIL) & (fld.mode=Fld)	DO
			IF	fld.name#""	THEN	Ht(3); Adr(fld.adr); Str(fld.name);
				WHILE	(fld.link#NIL)&(fld.link.typ=fld.typ)&(fld.link.name#"")	DO
					Mrk(fld.vis); Str(", "); fld:=fld.link; Str(fld.name)
				END;
				Mrk(fld.vis); Str(": "); TypName(fld.typ); Ch(";"); Ln
			ELSIF	show	THEN	Ht(3); Adr(fld.adr); Str("@: "); TypName(fld.typ); Ch(";"); Ln	END;
			fld:=fld.link
		END;
		Tproc(typ.link) 		
	END RecType;

	PROCEDURE TypHierarchy(typ: OPT.Struct);
	BEGIN
		IF typ.BaseTyp # NIL THEN TypHierarchy(typ.BaseTyp);
		END;
		Ln; Ht(3); Str("(* "); TypName(typ); Str(" *)");
		RecType(typ);
	END TypHierarchy;

	PROCEDURE Structure(typ: OPT.Struct);
	BEGIN
		CASE	typ.form	OF
		| Pointer:	Str("POINTER"); SFlg(typ.sysflag); Str(" TO "); 
							IF (typ.BaseTyp.comp # Record) OR (typ.BaseTyp.strobj.vis = external) THEN
								TypName(typ.BaseTyp)
							ELSE
								Structure(typ.BaseTyp)
							END
		| ProcTyp:	Str("PROCEDURE"); Signature(typ.BaseTyp, typ.link)
		| Comp:
				CASE	typ.comp	OF
				| StaticArr:	Str("ARRAY"); SFlg(typ.sysflag); Ch(" "); Dec(typ.n); Str(" OF "); TypName(typ.BaseTyp)
				| DynArr:	Str("ARRAY * OF "); TypName(typ.BaseTyp)
				| OpenArr:	Str("ARRAY OF "); TypName(typ.BaseTyp)
				| Record:	Str("RECORD "); Adr(typ.tdadr); 
					IF	(typ.BaseTyp#NIL) & ~extend	THEN
						Ch("(");
						IF typ.BaseTyp.ptr # NIL THEN TypName(typ.BaseTyp.ptr) ELSE TypName(typ.BaseTyp) END;
						Ch(")")
					ELSIF	typ.BaseTyp#NIL	THEN	TypHierarchy(typ.BaseTyp)
					END;
					RecType(typ); Ht(2); Adr(typ.size); Str("END")
				END
		END
	END Structure;

	PROCEDURE Objects(obj: OPT.Object);
		VAR i: LONGINT; m, vis: INTEGER; s: SET; con: OPT.Const; ext: OPT.ConstExt;
	BEGIN
		IF	obj#NIL	THEN	Objects(obj.left); vis:=obj.vis;
			IF	(obj.mode IN mode) & ((vis#internal) OR show)	THEN
				CASE obj.mode OF
				| Con:	con:=obj.conval;
						Ht(2); Str(obj.name); Str("* = ");
						CASE obj.typ.form OF
						| Bool:	IF	con.intval=1	THEN	Str("TRUE")	ELSE	Str("FALSE")	END
						| Char:
								IF	(con.intval>=32) & (con.intval<=126)	THEN	Ch(22X); Ch(CHR(con.intval)); Ch(22X)
								ELSE	Hex(con.intval); Ch("X")	END
						| SInt, Int, LInt:	Dec(con.intval)
						| Set:
								Ch("{"); i:=0; s:=con.setval;
								WHILE	i <= MAX(SET)	DO
									IF	i IN s	THEN	Dec(i); EXCL(s, i);
										IF	s#{}	THEN	Str(", ")	END
									END;
									INC(i)
								END;
								Ch("}")
						| Real:	Texts.WriteReal(W, SHORT(con.realval), 16)
						| LReal:	Texts.WriteLongReal(W, con.realval, 23)
						| String:	 Ch(22X); Str(con.ext^); Ch(22X)
						| NilTyp:	Str("NIL")
						END
				| Typ:
						Ht(2); Title; Str(obj.name); Normal;
						IF	obj.typ.strobj#obj	THEN
							Str("* = "); TypName(obj.typ); Normal
						ELSE
							Mrk(vis); Str(" = "); Structure(obj.typ)
						END
				| Var:
						Ht(2); Adr(obj.adr); Str(obj.name); Mrk(vis); Str(": "); TypName(obj.typ)
				| XProc, LProc, CProc:
						Ht(1); Adr(obj.adr); Str("PROCEDURE");
						IF	obj.mode=CProc	THEN	Ch("-")	END;
						Ch(" "); Title; Str(obj.name); Normal; 
						IF obj.mode=XProc THEN Ch("*") END;
						Signature(obj.typ, obj.link);
						IF	obj.mode=CProc	THEN	ext:=obj.conval.ext; m:=ORD(ext^[0]); i:=1; Ch(" ");
							WHILE	i <= m	DO	Hex(ORD(ext^[i])); Ch("H");
								IF	i < m	THEN	Str(", ")	END;
								INC(i)
							END
						END
				END;
				Ch(";"); Ln
			END;
			Objects(obj.right)
		END
	END Objects;


	PROCEDURE PutSection(s: ARRAY OF CHAR);
	BEGIN
		IF	W.buf.len>0	THEN	Texts.Write(W1, 9X); Texts.WriteString(W1, s); Texts.WriteLn(W1); Ln;
			Texts.Append(T, W1.buf); Texts.Append(T, W.buf)
		END
	END PutSection;

	PROCEDURE Scope;
		VAR i: INTEGER; first: BOOLEAN; scope: OPT.Object;
	BEGIN	i:=2; first:=TRUE; scope:=theMod;
		WHILE	i < OPT.nofmod	DO
			IF	first	THEN	first:=FALSE; Ht(2)	ELSE	Str(", ")	END;
			Str(OPT.modules[i].name); INC(i)
		END;
		IF	W.buf.len>0	THEN	Ch(";"); Ln; PutSection("IMPORT")	END;
		mode:={Con}; Objects(scope); PutSection("CONST");
		mode:={Typ}; Objects(scope); PutSection("TYPE");
		mode:={Var}; Objects(scope); PutSection("VAR");
		mode:={XProc, LProc, CProc}; Objects(scope)
	END Scope;

	PROCEDURE GetArgs(VAR S: Texts.Scanner);
		VAR text: Texts.Text; beg, end, time: LONGINT;
	BEGIN	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF	(S.line#0) OR (S.class#Texts.Name)	THEN	Oberon.GetSelection(text, beg, end, time);
			IF	time>=0	THEN	Texts.OpenScanner(S, text, beg); Texts.Scan(S)	END
		END
	END GetArgs;

	PROCEDURE QualIdent(VAR name, first, second: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN	i:=0; ch:=name[0];
		WHILE	(ch#".") & (ch#0X)	DO	first[i]:=ch; INC(i); ch:=name[i]	END;
		first[i]:=0X; INC(i); j:=0; ch:=name[i];
		WHILE	ch#0X	DO	second[j]:=ch; INC(i); INC(j); ch:=name[i]	END;
		second[j]:=0X
	END QualIdent;

	PROCEDURE Append(VAR d: ARRAY OF CHAR; s: ARRAY OF CHAR);
		VAR i, j: INTEGER; ch: CHAR;
	BEGIN
		i:=0; WHILE	d[i]#0X	DO	INC(i)	END;
		j:=0; REPEAT	ch:=s[j]; d[i]:=ch; INC(i); INC(j)	UNTIL	ch=0X
	END Append;
	
	PROCEDURE GetModule(name: OPS.Name): OPT.Object;
	VAR  found: BOOLEAN; i, j: LONGINT; ch0, ch1: CHAR; iname: OPS.Name; F: Files.File; R: Files.Rider;
	BEGIN
		COPY(Modules.extension, OPM.extension);
		found:=FALSE; i:=0; ch0:=name[0];
		WHILE	(ch0#0X) & (i < 32)	DO	iname[i]:=ch0; INC(i); ch0:=name[i]	END;
		j := 0;
		WHILE (OPM.extension[j] # 0X) & (i < 32) DO
			iname[i] := OPM.extension[j];  INC(i);  INC(j)
		END;
		IF OPM.extension[j] = 0X THEN
			F := Files.Old(iname); Files.Set(R, F, 0); found := F # NIL;
			IF	found	THEN	Files.Read(R, ch0); Files.Read(R, ch1);
				found := (ch0=0BBX) & (ch1=0AFX)
			END;
			Files.Close(F);
			
			IF found THEN
				IF	incr	THEN	OPT.Close; incr:=FALSE	END;
				OPM.Init({}, Source, Null); OPS.Init; OPT.Init(dum, {});
				OPT.OpenScope(0, NIL);
				OPT.Import(name, name, dum); OPT.CloseScope;
				OPV.AssignEntries(OPT.modules[1].publics, TRUE);
				RETURN OPT.modules[1].right
			END
		END;
		RETURN NIL
	END GetModule;

	PROCEDURE ShowDef*;
		VAR S: Texts.Scanner; vname, name: OPS.Name; i: INTEGER;
	BEGIN	GetArgs(S); SignOn; show := FALSE; extend := FALSE; hidden := FALSE;
		IF	S.class=Texts.Name	THEN	QualIdent(S.s, name, vname); Texts.Scan(S);
			IF (S.class=Texts.Char) & (S.c = Oberon.OptionChar) THEN
				Texts.Scan(S);
				IF (S.class IN {Texts.Name, Texts.String}) THEN 
					i := 0; WHILE S.s[i] # 0X DO 
						IF S.s[i] = "d" THEN show := TRUE END;
						IF S.s[i] = "e" THEN extend := TRUE END;
						INC(i)
					END
				END
			END;
			theMod:=GetModule(name);
			IF	theMod#NIL	THEN
				COPY(name, vname); Append(vname, ".Def"); NEW(T); Texts.Open(T, "");
				Oberon.OpenText(vname, T, Display.Width DIV 2, 200);
				Str("DEFINITION "); Title; Str(name); Normal; Ch(";"); Ln; Ln; Texts.Append(T, W.buf);
				Scope; Ln; Str("END "); Str(name); Ch("."); Texts.Append(T, W.buf)
			END;
		END
	END ShowDef;
	
	PROCEDURE ShowScope*;	(** non-portable *)
	VAR vname: ARRAY 32 OF CHAR;
	BEGIN
		show := TRUE; extend := TRUE;  hidden := TRUE; vname := "CURRENT";
		theMod := OPT.topScope.right;
		Append(vname, ".Def"); NEW(T); Texts.Open(T, "");
		Oberon.OpenText(vname, T, Display.Width DIV 2, 200);
		Scope; Texts.Append(T, W.buf)
	END ShowScope;

BEGIN
	Texts.OpenWriter(W); Texts.OpenWriter(W1); NEW(Null); Texts.Open(Null, ""); Texts.OpenReader(Source, Null, 0); dum:="$$";
	NormalFont := Fonts.This ("Oberon10.Scn.Fnt"); TitleFont := Fonts.This ("Oberon10b.Scn.Fnt");
	NEW(Null); Texts.Open(Null, ""); Texts.OpenReader(Source, Null, 0); dum:="$$"
END Browser.
