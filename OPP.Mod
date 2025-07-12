(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

(* OPP - Oberon Portable Parser (front end) *)
(* NW, RC, JM, rml, pjm, prk *)


MODULE OPP;	(** non-portable *)
	IMPORT OPT, OPS, OPM, OPB, OPA;
		
	CONST
		(* numtyp values *)
		char = 1; integer = 2; real = 3; longreal = 4;

		(* symbol values *)
		null = OPS.null; times = OPS.times; slash = OPS.slash; div = OPS.div; 
		mod = OPS.mod; and = OPS.and; plus = OPS.plus; minus = OPS.minus; 
		or = OPS.or; eql = OPS.eql; neq = OPS.neq; lss = OPS.lss; leq = OPS.leq; 
		gtr = OPS.gtr; geq = OPS.geq; in = OPS.in; is = OPS.is; arrow = OPS.arrow; 
		period = OPS.period; comma = OPS.comma; colon = OPS.colon; upto = OPS.upto; 
		rparen = OPS.rparen; rbrak = OPS.rbrak; rbrace = OPS.rbrace; of = OPS.of; 
		then = OPS.then; do = OPS.do; to = OPS.to; by = OPS.by; lparen = OPS.lparen; 
		lbrak = OPS.lbrak; lbrace = OPS.lbrace; not = OPS.not; becomes = OPS.becomes; 
		number = OPS.number; nil = OPS.nil; true = OPS.true; false = OPS.false; 
		string = OPS.string; ident = OPS.ident; semicolon = OPS.semicolon; 
		bar = OPS.bar; end = OPS.end; else = OPS.else; elsif = OPS.elsif; 
		until = OPS.until; if = OPS.if; case = OPS.case; while = OPS.while; 
		repeat = OPS.repeat; for = OPS.for; loop = OPS.loop; with = OPS.with; 
		exit = OPS.exit; return = OPS.return; array = OPS.array; object = OPS.object; 
		record = OPS.record; pointer = OPS.pointer; begin = OPS.begin; code = OPS.code; 
		const = OPS.const; type = OPS.type; var = OPS.var; procedure = OPS.procedure; 
		import = OPS.import; module = OPS.module; eof = OPS.eof; 

		(* object modes *)
		Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7;
		SProc = 8; CProc = 9; IProc = 10; Mod = 11; Head = 12; TProc = 13;

		(* Structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
		intSet = {SInt..LInt};
		
		(* composite structure forms *)
		Basic = 1; StaticArr = 2; SDynArr = 3; DynArr = 4; OpenArr = 5; Record = 6;
		ArraySet = {StaticArr, SDynArr, DynArr, OpenArr};
		
		(*function number*)
		haltfn = 0; newfn = 1; sizefn = 12; incfn = 13; lenfn = 17; sysnewfn = 30;
		awaitfn = 64;

		(* nodes classes *)
		Nvar = 0; Nvarpar = 1; Nfield = 2; Nderef = 3; Nindex = 4; Nguard = 5; Neguard = 6;
		Nconst = 7; Ntype = 8; Nproc = 9; Nupto = 10; Nmop = 11; Ndop = 12; Ncall = 13;
		Ninittd = 14; Nif = 15; Ncaselse = 16; Ncasedo = 17; Nenter = 18; Nassign = 19;
		Nifelse = 20; Ncase = 21; Nwhile = 22; Nrepeat = 23; Nloop = 24; Nexit = 25;
		Nreturn = 26; Nwith = 27; Ntrap = 28;
		Nassembler = 29; Ncode = 30; (* Ncode isn't a duplicate of Nret, it's used only with Nassembler *)

		(* node subclasses *)
		super = 1;
		
		(* module visibility of objects *)
		internal = 0; external = 1; externalR = 2;

		(* procedure flags (conval^.setval) *)
		hasBody = 1; isRedef = 2; slNeeded = 3; locked =6; asmProc = 7; operatorFlag = 8;
		checkOverwriting = 31;	(*set in record.strobj when field/mth overwriting check is delayed because base is undef*)
		
		(* record flags (flags) *)
		protectedObj = 4; activeObj = 5; safe = 8;
		
		(* sysflag *) (* ejz *)
		notag = 1; stdcall = 2; cdecl = 3; untraced = 4; delegate = 5;
		systemtype = 6;	(*implicitly generated type for arr of ptrs, allocate only when used*)

		(* the hidden parameter for methods *)
		HiddenSelf = "@SELF";
	
	TYPE
		CaseTable = ARRAY OPM.MaxCases OF
			RECORD
				low, high: LONGINT
			END ;

	CONST
		FTarget = 1; FExpr = 2; FAssign = 3; FCall = 4; FCond = 5; 
		FParam = 6; FPassExpr = 7; FReturn = 9;
		
	TYPE
		FixPtr = POINTER TO FixDesc;		(* late parsing *)
		FixDesc = RECORD
			mode: LONGINT; scope: OPT.Object; level: SHORTINT; node: OPT.Node; stream: OPS.TokenStream; next: FixPtr
		END;
		TypeFix = RECORD
			pos: LONGINT; name: OPS.Name; scope: OPT.Object; level: SHORTINT;
		END;
		ObjFixDesc = RECORD (TypeFix)  obj: OPT.Object  END;
		StructFixDesc = RECORD (TypeFix)  typ: OPT.Struct  END;

		
	VAR
		SignOnMessage*: ARRAY 80 OF CHAR;
		sym, level: SHORTINT;
		LoopLevel: INTEGER;
		TDinit, lastTDinit: OPT.Node;	(*global list of TDInit nodes*)
		RecInit, lastRecInit: OPT.Node;	(*global list of Record Nodes (method code)*)
		CondNodes: OPT.Node;
		CondCount: SHORTINT;
		UndefFlag, FixPhase: BOOLEAN;
		UndefObj: OPT.Object;
		scopeLock: BOOLEAN;	(*current or any parent statement block locked *)
		
		FixList, FixLast: FixPtr;
		ExtObj: OPT.Object;		(*for searching in the module scope*)
		inc: OPT.Object;	(* the INC sproc, used by trace *)
		ptrToRec: OPT.Struct;
		
		ObjFix:  ARRAY 128 OF ObjFixDesc;
		ObjCheck:  ARRAY 256 OF RECORD  obj: OPT.Object;  level: SHORTINT  END;
		TypFix:  ARRAY 128 OF StructFixDesc;
		nofCheck, nofObjFix, nofTypFix: LONGINT;


	PROCEDURE err(n: INTEGER);
	BEGIN OPM.err(n)
	END err;

	PROCEDURE CheckSym(s: INTEGER);
	BEGIN
		IF sym = s THEN OPS.Get(sym) ELSE OPM.err(s) END
	END CheckSym;

	PROCEDURE IsModuleScope ():BOOLEAN;
	BEGIN
		RETURN OPT.topScope^.link^.mode = Mod
	END IsModuleScope;
	
	PROCEDURE IsObjectScope ():BOOLEAN;
	BEGIN
		RETURN OPT.topScope^.link^.mode = Typ
	END IsObjectScope;

	PROCEDURE IsRecordScope(): BOOLEAN;
		VAR owner: OPT.Object;
	BEGIN	owner:=OPT.topScope.link;
		RETURN (owner.mode=Typ) & (owner.typ#NIL) & (owner.typ.comp=Record)
	END IsRecordScope;

	PROCEDURE SetFlags (obj: OPT.Object; flag: SET);
	BEGIN
		obj^.conval^.setval := obj^.conval^.setval + flag
	END SetFlags;
	
	PROCEDURE GetFlags (obj: OPT.Object):SET;
	BEGIN
		RETURN obj^.conval^.setval
	END GetFlags;
	
	PROCEDURE DumpScope(o: OPT.Object);
	BEGIN
		IF o # NIL THEN
			DumpScope(o.left);
			OPM.LogWLn; OPM.LogWStr(o.name); OPM.LogWNum (o.mode, 4);
			DumpScope(o.right);
		END
	END DumpScope;
	
	PROCEDURE GetSelf():OPT.Object;
		VAR self: OPT.Object;
	BEGIN
		OPT.FindInScope(HiddenSelf, OPT.topScope, self);
		RETURN self
	END GetSelf;

	PROCEDURE InsertFix (mode: LONGINT; stream: OPS.TokenStream; node: OPT.Node);
		VAR fix: FixPtr;
	BEGIN
		NEW (fix);
		fix.mode := mode; fix.stream := stream; fix.scope := OPT.topScope;
		fix.level := level; fix.node := node;
		fix.next := NIL;
		IF FixLast = NIL THEN FixList := fix	ELSE FixLast.next := fix	END;
		FixLast := fix;
		node.link := NIL
	END InsertFix;
	
	PROCEDURE NewFix(VAR f: TypeFix; name: OPS.Name);
	BEGIN  f.pos := OPM.errpos; f.scope := OPT.topScope; f.name := name; f.level := level
	END NewFix;
	
	PROCEDURE NewCheck(obj: OPT.Object);
	BEGIN  ObjCheck[nofCheck].obj := obj;  ObjCheck[nofCheck].level := level;  INC(nofCheck)
	END NewCheck;
	
	PROCEDURE NewType(obj: OPT.Object);	(*a new type is declared, do an early fix*)
	VAR  i: LONGINT; old: SHORTINT;
	BEGIN
		i := 0;
		WHILE i < nofTypFix DO
			IF (OPT.topScope = TypFix[i].scope) & (obj.name = TypFix[i].name) THEN
				TypFix[i].typ.BaseTyp := obj.typ;  CheckStruct(TypFix[i].typ);
				INCL(obj.flag, OPT.used);
				IF ~TypFix[i].typ.incomplete & (TypFix[i].typ.strobj # NIL) THEN
					CheckObj(TypFix[i].typ.strobj);  TypFix[i].typ.strobj.mode := ABS(TypFix[i].typ.strobj.mode)
				END;
				TypFix[i].scope := NIL;  TypFix[i].typ := NIL
			END;
			INC(i)
		END;
		WHILE i < nofObjFix DO
			IF (OPT.topScope = ObjFix[i].scope) & (obj.name = ObjFix[i].name) THEN
				ObjFix[i].obj.typ := obj.typ;  CheckObj(ObjFix[i].obj);
				INCL(obj.flag, OPT.used);
				IF ~obj.typ.incomplete THEN  ObjFix[i].obj.mode := ABS(ObjFix[i].obj.mode)  END;
				ObjFix[i].scope := NIL;  ObjFix[i].obj := NIL
			END;
			INC(i)
		END;
		i := 0;
		WHILE i < nofCheck DO
			IF (ObjCheck[i].obj # NIL) & (ObjCheck[i].obj.typ # NIL) THEN
				CheckStruct(ObjCheck[i].obj.typ);
				IF ~ObjCheck[i].obj.typ.incomplete THEN
					old := level; level := ObjCheck[i].level;
					ObjCheck[i].obj.mode := ABS(ObjCheck[i].obj.mode);
					CheckObj(ObjCheck[i].obj); ObjCheck[i].obj := NIL;
					level := old
				END
			END;
			INC(i)
		END;
	END NewType;
	
	PROCEDURE CheckRecord(typ: OPT.Struct);
	CONST stamp = 1234H;
	VAR t, base: OPT.Struct;
		PROCEDURE Traverse(p: OPT.Object);
		VAR fwd: OPT.Object;
		BEGIN
			IF p # NIL THEN
				Traverse(p.left);
				IF p.mode = TProc THEN
					OPT.FindField(p.name, typ.BaseTyp, fwd, TRUE);
					IF (fwd # NIL) & (fwd.mode = TProc) THEN
						OPM.errpos := p.conval.intval;
						OPB.CheckParameters (p.link.link, fwd.link.link, FALSE);
					END;
					p.conval.intval := 0
				ELSIF p.mode = Fld THEN
					OPT.FindField(p.name, typ.BaseTyp, fwd, TRUE);
					IF (fwd # NIL) THEN OPM.Mark(1, p.conval.intval) END;
				END;
				Traverse(p.right)
			END
		END Traverse;
	BEGIN
		ASSERT(typ.comp = Record);
		IF typ.rectest = stamp THEN
			err(58); typ.BaseTyp := NIL; RETURN
		END;
		base := typ.BaseTyp;
		IF base # NIL THEN
			typ.rectest := stamp;
			CheckStruct(base);
			typ.rectest := 0;
			IF  base.incomplete  THEN  RETURN  END;
		END;
		IF base = NIL THEN
			(*ok*)
		ELSIF base = OPT.undftyp THEN	
			typ.BaseTyp := NIL; err(999)	(* wrong base type *)
		ELSE
			IF base.form = Pointer THEN
				base := base.BaseTyp;
				typ.BaseTyp := base;
				IF typ.ptr = NIL THEN OPM.Mark(249, typ.txtpos) END;	(*this record must also be a pointer to record*)
			END;
			OPT.MarkType(base);
			IF base.comp # Record THEN  OPM.Mark(52, typ.txtpos2);  RETURN  END;
			IF (base.sysflag = notag) OR (typ.sysflag = notag) THEN  OPM.Mark(200, typ.txtpos2)  END;
			typ.extlev := base.extlev+1;
			SetFlags(typ.strobj, GetFlags(base.strobj) * {protectedObj});
			IF typ^.strobj^.link2 = NIL THEN
				typ^.strobj^.link2 := base^.strobj.link2;	(* inherit initialiser *)
			END;
			t := base;
			WHILE (t # NIL) & ~(hasBody IN GetFlags(t.strobj)) DO  t := t.BaseTyp  END;
			IF t # NIL THEN  SetFlags(typ.strobj, {isRedef})  END;
			IF checkOverwriting IN typ.strobj.conval.setval THEN
				Traverse(typ.strobj.scope.right);
			END
		END;
		typ.incomplete := FALSE
	END CheckRecord;
	
	PROCEDURE CheckArray(typ: OPT.Struct);
	VAR base: OPT.Struct;
	BEGIN
		ASSERT(typ.comp IN ArraySet);
		CheckStruct(typ.BaseTyp);
		base := typ.BaseTyp;
		IF base.incomplete THEN  RETURN  END;
		CASE typ.comp OF
		|  StaticArr:
				IF base.comp IN {OpenArr, DynArr, SDynArr}  THEN  OPM.Mark(89, typ.txtpos2)  END;
		|  OpenArr, DynArr:
				IF base.comp IN ({SDynArr, DynArr, OpenArr}-{typ.comp})  THEN  OPM.Mark(89, typ.txtpos2)
				ELSIF base.comp = typ.comp THEN
					typ.n := base.n +1
				ELSE
					typ.n := 0
				END
		|  SDynArr:
				IF base.comp IN {OpenArr, DynArr}  THEN  OPM.Mark(89, typ.txtpos2)  END;
				typ.offset := 0
		END;
		typ.incomplete := FALSE
	END CheckArray;
	
	PROCEDURE CheckPointer(typ: OPT.Struct);
	VAR base: OPT.Struct;
	BEGIN
		ASSERT(typ.form = Pointer);
		CheckStruct(typ.BaseTyp);
		base := typ.BaseTyp;
		IF base.incomplete THEN  RETURN  END;
		IF ~(base.comp IN {Record, StaticArr, DynArr, OpenArr}) THEN
			typ.BaseTyp := OPT.undftyp; OPM.Mark(57, typ.txtpos2)
		END;
		typ.incomplete := FALSE
	END CheckPointer;
	
	PROCEDURE CheckProcedure(typ: OPT.Struct);
	VAR par: OPT.Object; quit: BOOLEAN;
	BEGIN
		IF typ.BaseTyp = NIL THEN RETURN END;
		par := typ.link; quit := FALSE;
		WHILE (par#NIL) & ~quit DO
			IF par.typ.incomplete THEN CheckObj(par); quit := par.typ.incomplete END;
			par := par.link
		END;
		CheckStruct(typ.BaseTyp);
		typ.incomplete := quit OR typ.BaseTyp.incomplete;
	END CheckProcedure;
	
	PROCEDURE CheckStruct(str: OPT.Struct);
	BEGIN
		IF ~str.incomplete OR (str = OPT.ToBeFixed) THEN  RETURN  END;
		IF str.comp = Record THEN CheckRecord(str)
		ELSIF str.comp IN ArraySet THEN CheckArray(str)
		ELSIF str.form = Pointer THEN CheckPointer(str)
		ELSIF str.form = ProcTyp THEN CheckProcedure(str)
		ELSE  OPM.err(200)
		END
	END CheckStruct;
	
	PROCEDURE CheckObj(obj: OPT.Object);
	BEGIN
		IF (obj.mode IN {XProc, LProc}) & (obj.typ = NIL) & FixPhase THEN	(*avoid NIL trap when no return type is defined*)
			obj.typ := OPT.undftyp; RETURN
		END;
		CheckStruct(obj.typ);
		IF obj.typ.incomplete THEN  RETURN  END;
		IF (obj.typ.comp = SDynArr) & (level = 0) THEN OPM.Mark(90, obj.txtpos)
		ELSE
			CASE obj.mode OF
			| Var, VarPar:	
						IF OPT.param IN obj.flag THEN
							IF obj.typ.comp = DynArr THEN OPM.Mark(91, obj.txtpos)  END;
						ELSE
							IF obj.typ.comp = OpenArr THEN OPM.Mark(88, obj.txtpos)  END;
						END;
			| Fld:	IF obj.typ.comp IN {OpenArr, DynArr(*, DynArr2*), SDynArr} THEN  OPM.Mark(88, obj.txtpos)  END;
			| XProc, LProc:
						IF (obj.typ = NIL) & FixPhase THEN	obj.typ := OPT.notyp	END;	(*avoid NIL trap when no return type is defined*)
			ELSE
			END;
		END;
	END CheckObj;
	
	PROCEDURE qualident(VAR id: OPT.Object);
		VAR obj, self: OPT.Object; lev: SHORTINT; m: BOOLEAN;
	BEGIN (*sym = ident*)
		OPT.Find(obj);  OPS.Get(sym);
		IF (sym = period) & (obj # NIL) & (obj^.mode = Mod) THEN
			m := TRUE;
			OPS.Get(sym);
			IF sym = ident THEN
				OPT.FindImport(obj, obj); OPS.Get(sym)
			ELSE err(ident); obj := NIL
			END
		ELSE m := FALSE
		END ;
		IF obj = NIL THEN
			IF FixPhase OR m THEN
				err(0);
				obj := OPT.NewObj(); obj^.mode := Var; obj^.typ := OPT.undftyp; obj^.adr := 0
			ELSE UndefFlag := TRUE; obj := UndefObj
			END
		ELSE 
			IF (obj.mode IN {Fld, TProc}) THEN
				self := GetSelf(); lev := self.mnolev;
			ELSE
				lev := obj^.mnolev
			END;
			IF (obj^.mode IN {Var, VarPar, Fld, TProc}) & (lev # level) THEN
				obj^.leaf := FALSE;
				IF lev > 0 THEN OPB.StaticLink(level-lev) END
			END
		END ;
		id := obj;
		IF (id = UndefObj) & (OPM.oberon1 IN OPM.options) THEN err(260) END
	END qualident;
	
	PROCEDURE ConstExpression(VAR x: OPT.Node);
	VAR tmp: BOOLEAN;
	BEGIN
		tmp := FixPhase;  FixPhase := TRUE;	(*no forward references to constants allowed*)
		Expression(x);
		IF x^.class # Nconst THEN
			err(50); x := OPB.NewIntConst(1) 
		END;
		FixPhase := tmp
	END ConstExpression;

	PROCEDURE CheckMark(VAR vis: SHORTINT; rdonlyAllowed: BOOLEAN);
	BEGIN OPS.Get(sym);
		IF (sym = times) OR (sym = minus) THEN
			IF level > 0 THEN err(47) END ;
			IF sym = times THEN vis := external
				ELSIF rdonlyAllowed  THEN vis := externalR 
				ELSE err(47) 
				END ;
			OPS.Get(sym)
		ELSE vis := internal
		END
	END CheckMark;
	
	PROCEDURE CheckSysFlag(VAR sysflag: SHORTINT; default: SHORTINT; allowed: SET);	(* ejz *)
		VAR x: OPT.Node; sf: LONGINT;
	BEGIN
		sf := default;
		IF sym = lbrak THEN
			IF ~OPT.SYSimported THEN err(135) END;
			OPS.Get(sym);
			IF sym = ident THEN
				IF OPM.WarnUnsafe THEN err(-666) END;
				IF OPS.name = "C" THEN
					sf := cdecl
				ELSIF OPS.name = "WINAPI" THEN
					sf := stdcall
				ELSIF OPS.name = "NOTAG" THEN
					sf := notag
				ELSIF OPS.name = "UNTRACED" THEN
					sf := untraced
				ELSE
					err(115)
				END;
				OPS.Get(sym)
			ELSE
				err(ident)
			END;
			CheckSym(rbrak)
		ELSIF sym = lbrace THEN
			OPS.Get(sym);
			IF sym = ident THEN
				IF OPS.name = "DELEGATE" THEN
					sf := delegate
				ELSE
					err(115)
				END;
				OPS.Get(sym)
			ELSE
				err(ident)
			END;
			CheckSym(rbrace)
		END;
		IF (sf # default) & ~(sf IN allowed) THEN  sf := default; err(200)  END;
		sysflag := SHORT(SHORT(sf))
	END CheckSysFlag;

	PROCEDURE BlockMode (VAR flag: SET;  local: BOOLEAN;  VAR lock: BOOLEAN);
		VAR x: OPT.Node; objscope: BOOLEAN;
	
		PROCEDURE ProtectScope();
			VAR p: OPT.Object;
		BEGIN
			p := OPT.topScope;
			IF (p#NIL)&(p.link.mode IN {XProc, LProc})&(p.link.typ.comp IN {OpenArr, SDynArr}) THEN err(200) END;
			WHILE (p # NIL) & ~(p.link.mode IN {Typ, Mod}) DO p := p.left END;
			IF p = NIL THEN err(1000)
			ELSIF (p.link.mode = Typ) & (p.link.typ.ptr = NIL) THEN err(252)
			END;
			INCL(p.link.conval.setval, protectedObj)
		END ProtectScope;
	
	BEGIN
		lock := FALSE;
		objscope := IsObjectScope();
		IF sym = lbrace THEN
			OPS.Get(sym);
			LOOP
				IF sym = ident THEN
					IF OPS.name = "EXCLUSIVE" THEN
						OPS.Get (sym);
						ProtectScope();
						INCL(flag, locked);
						lock := TRUE
					ELSIF ~local THEN
						IF OPS.name = "ACTIVE" THEN
							IF ~objscope THEN err(200) END;
							INCL(flag, activeObj); OPS.Get(sym)
						ELSIF OPS.name = "PRIORITY" THEN
							IF ~objscope  THEN err(200) END;
							IF ~(activeObj IN flag) THEN err(272) END;
							OPS.Get(sym);
							IF sym = lparen THEN
								ConstExpression(x);
								IF x.class # Nconst THEN err(50)
								ELSIF x^.typ^.form # SInt THEN err(220)
								ELSE OPT.topScope^.link^.prio := SHORT(SHORT(x^.conval^.intval))
								END
							ELSE
								x := OPB.NewIntConst(0)
							END
						ELSIF OPS.name = "SAFE" THEN
							IF ~(activeObj IN flag) THEN err(272) END;
							INCL (flag, safe); OPS.Get(sym)
						ELSE err(0); OPS.Get(sym)
						END
					ELSE err(0); OPS.Get(sym)
					END
				ELSIF sym # rbrace THEN err(0); OPS.Get(sym)
				END;
				IF sym = rbrace THEN EXIT END;
				CheckSym(comma);
			END;
			CheckSym(rbrace)
		END;
		IF ~local & objscope & ~(activeObj IN flag) THEN err(999) END;
	END BlockMode;

	PROCEDURE RecordType(VAR typ, banned: OPT.Struct; owner: OPT.Object);
		VAR base: OPT.Object;
			sysflag: SHORTINT;
			c: LONGINT;
			procdec, statseq, p: OPT.Node; lev: SHORTINT;
	BEGIN
		typ := OPT.NewStr(Comp, Record); typ^.BaseTyp := NIL;
		IF ptrToRec # NIL THEN	(*POINTER TO RECORD, ptr already declared*)
			typ.ptr := ptrToRec; ptrToRec := NIL;
		END;
		IF owner = NIL THEN	(*create anonymous owner to store flags*)
			owner := OPT.NewObj(); owner.mode := Typ; owner.name := "";
			owner.vis := internal; owner.typ := typ
		END;
		owner^.conval := OPT.NewConst(); typ.strobj := owner;
		CheckSysFlag(sysflag, 0, {0, notag});
		typ.incomplete := TRUE;
		IF sym = lparen THEN	(*record extension*)
			OPS.Get(sym);
			IF sym = ident THEN
				typ.txtpos2 := OPM.errpos;
				qualident(base);
				IF (base # UndefObj) & (base.mode = Typ) THEN
					IF base^.typ = banned THEN err(58)
					ELSE
						typ.BaseTyp := base.typ
					END
				ELSIF base = UndefObj THEN	(*base type not declared yet*)
					UndefFlag := FALSE;
					IF sym = period THEN
						OPT.FindInScope (OPS.name, ExtObj, base);
						OPS.Get (sym);
						IF (base # NIL) & (base.mode = Mod) THEN
							OPT.FindImport (base, base)
						END;
						CheckSym (ident);
						IF base = NIL THEN err (0)
						ELSIF base.mode # Typ THEN  err(52)
						ELSIF base.typ = banned THEN  err(58)
						ELSE  typ.BaseTyp := base^.typ
						END
					ELSE
						typ.BaseTyp := OPT.ToBeFixed;
						NewFix(TypFix[nofTypFix], OPS.name);  TypFix[nofTypFix].typ := typ;  INC(nofTypFix);
					END
				ELSE err(52)
				END
			ELSE err(ident)
			END ;
			CheckSym(rparen)
		END;
		typ^.sysflag := sysflag;
		CheckRecord(typ);
		OPT.OpenScope(0, owner);
		lev := level; level := 0; c := OPM.errpos;
		IF sym = semicolon THEN OPS.Get(sym) END;
		Block(procdec, statseq);
		IF typ^.link = NIL THEN typ^.link := OPT.topScope^.right END;
		ASSERT((statseq = NIL) OR (hasBody IN owner.conval.setval));		(*stat#NIL  ==> hasBody*)
		IF (procdec # NIL) OR (hasBody IN owner.conval.setval) OR (statseq # NIL) THEN
			p := CondNodes;
			WHILE p # NIL DO p.obj.mnolev := 1; p := p.link END;	(*patch condition proc level*)
			OPB.Enter(CondNodes, statseq, owner); CondNodes^.link := procdec; procdec := CondNodes;
			procdec^.conval := OPT.NewConst(); procdec^.conval^.intval := c;
			OPB.Link(RecInit, lastRecInit, procdec)
		END;
		level := lev; OPT.CloseScope;
	END RecordType;
	
	PROCEDURE OwnScope(VAR obj: OPT.Object);
	BEGIN
		IF ~(obj.mode IN {Con, Typ, SProc}) THEN
			IF IsRecordScope()
			OR ((obj.mnolev=OPT.topScope.mnolev)&(obj.link2=NIL)&(obj.myscope=OPT.topScope))  THEN err(90) END;
		END
	END OwnScope;

	PROCEDURE ArrayType(VAR typ, banned: OPT.Struct);
	VAR	x: OPT.Node; n: LONGINT;  sysflag: SHORTINT;
	
		PROCEDURE HiddenVar (IN name: ARRAY OF CHAR; exp: OPT.Node): OPT.Object;
			VAR dim, owner: OPT.Object; y: OPT.Node;
		BEGIN
			owner:=OPT.topScope;  (* insert var at first place in the variables of the actual scope *)
			WHILE (OPT.topScope.left#NIL) & (OPT.topScope.link=OPT.topScope.left.link) DO
				OPT.topScope:=OPT.topScope.left
			END;
			OPT.Insert("@@", dim); dim^.name := name;
			dim^.link:=NIL; dim^.mode:=Var; dim^.typ:=OPT.linttyp;
			dim.flag := {OPT.used};
			IF OPT.topScope^.scope=NIL THEN OPT.topScope^.scope:=dim
			ELSE
				dim^.link:=OPT.topScope^.scope; OPT.topScope^.scope:=dim
			END;
			OPT.topScope:=owner;
			y:=OPB.NewLeaf(dim); OPB.Assign(y, exp); (* generate assignment instructions *)
			y^.conval := OPT.NewConst(); y^.conval^.intval := OPM.errpos;
			OPB.CodeInsert(y);
			RETURN dim;
		END HiddenVar;

	BEGIN
		CheckSysFlag(sysflag, 0, {0, notag});
		IF sym = times THEN
			typ := OPT.NewStr(Comp, DynArr); typ^.sysflag := sysflag; OPS.Get(sym);
			IF (OPM.oberon1 IN OPM.options) THEN err(271) END
		ELSIF sym # of THEN
			Expression(x);
			IF x.class = Nconst THEN
				typ := OPT.NewStr(Comp, StaticArr); typ^.sysflag := sysflag;
				IF x^.typ^.form IN intSet THEN n := x^.conval^.intval;
					IF (n <= 0) OR (n > OPM.MaxIndex) THEN err(63); n := 1 END
				ELSE err(51); n := 1
				END;
				typ^.n := n; typ^.link:=NIL
			ELSE
				typ := OPT.NewStr(Comp, SDynArr); typ^.sysflag := sysflag; typ.n:=0;
				IF (x.typ = NIL) OR ~(x^.typ^.form IN intSet) THEN typ.comp := StaticArr; err(68)
				ELSE  typ^.link:=HiddenVar ("@dim", x)  END;
				IF (OPM.oberon1 IN OPM.options) THEN err(271) END
			END
		ELSE
			typ := OPT.NewStr(Comp, OpenArr); typ^.sysflag := sysflag;
		END;
		typ.incomplete := TRUE;
		IF sym = comma THEN
			OPS.Get(sym); typ.txtpos2 := OPM.errpos; ArrayType(typ.BaseTyp, banned)
		ELSIF sym = of THEN
			OPS.Get(sym); typ.txtpos2 := OPM.errpos; TypeDecl(typ.BaseTyp, banned, NIL);
			IF typ.BaseTyp = OPT.ToBeFixed THEN
				NewFix(TypFix[nofTypFix], OPS.name);  TypFix[nofTypFix].typ := typ;  INC(nofTypFix)
			END
		END;
		CheckArray(typ);
	END ArrayType;

	PROCEDURE ObjectType(VAR typ, banned: OPT.Struct);
	BEGIN
		typ := OPT.NewStr(Pointer, Basic);
		typ.incomplete := TRUE; ptrToRec := typ; typ.txtpos2 := OPM.curpos;
		RecordType(typ^.BaseTyp, banned, NIL);
		IF typ.BaseTyp = OPT.ToBeFixed THEN
			NewFix(TypFix[nofTypFix], OPS.name);  TypFix[nofTypFix].typ := typ;  INC(nofTypFix)
		END;
		CheckPointer(typ);
	END ObjectType;

	PROCEDURE PointerType(VAR typ, banned: OPT.Struct);
		VAR id: OPT.Object;
	BEGIN typ := OPT.NewStr(Pointer, Basic); CheckSysFlag(typ^.sysflag, 0, {0});
		typ.incomplete := TRUE;
		CheckSym(to);
		IF sym = ident THEN OPT.Find(id); typ.txtpos2 := OPM.errpos;
			IF id = NIL THEN
				NewFix(TypFix[nofTypFix], OPS.name);  TypFix[nofTypFix].typ := typ;  INC(nofTypFix);
				typ.BaseTyp := OPT.ToBeFixed;
				OPS.Get(sym)
			ELSE qualident(id);
				IF id^.mode = Typ THEN  typ.BaseTyp := id.typ
				ELSE typ^.BaseTyp := OPT.undftyp; err(52)
				END
			END
		ELSE 
			IF sym= record THEN ptrToRec := typ END;	(*special case POINTER TO RECORD, all together*)
			typ.txtpos2 := OPM.curpos;
			TypeDecl(typ^.BaseTyp, banned, NIL);
			IF typ.BaseTyp = OPT.ToBeFixed THEN
				NewFix(TypFix[nofTypFix], OPS.name);  TypFix[nofTypFix].typ := typ;  INC(nofTypFix)
			END;
			CheckPointer(typ);
		END;
	END PointerType;
	
	PROCEDURE FormalParameters(VAR firstPar: OPT.Object; VAR resTyp: OPT.Struct;  sysflag: SHORTINT);
		VAR mode: SHORTINT;
				par, first, last, res: OPT.Object; typ, btyp: OPT.Struct;
	BEGIN first := NIL; last := firstPar;
		IF (sym = ident) OR (sym = var) THEN
			LOOP
				IF sym = var THEN OPS.Get(sym); mode := VarPar ELSE mode := Var END ;
				LOOP
					IF sym = ident THEN
						OPT.Insert(OPS.name, par); OPS.Get(sym);
						par.flag := {OPT.param};
						par^.mode := mode; par^.link := NIL;
						IF first = NIL THEN first := par END ;
						IF firstPar = NIL THEN firstPar := par ELSE last^.link := par END ;
						last := par
					ELSE err(ident)
					END ;
					IF sym = comma THEN OPS.Get(sym)
					ELSIF sym = ident THEN err(comma)
					ELSIF sym = var THEN err(comma); OPS.Get(sym)
					ELSE EXIT
					END
				END ;
				CheckSym(colon); TypeDecl(typ, OPT.notyp, NIL);
				IF ~typ.incomplete & (typ.strobj = NIL) & (typ.comp # OpenArr) THEN err(-305) END;
				IF sysflag IN {stdcall, cdecl} THEN
					IF (typ.comp IN {OpenArr, Record}) & (typ.sysflag # notag) THEN err(200) END;
					IF typ.comp IN {DynArr, SDynArr} THEN err(200) END
				END;
				IF mode = Var THEN OPT.MarkType(typ) END;
				WHILE first # NIL DO
					IF typ = OPT.ToBeFixed THEN		(*incomplete structure, add fixup*)
						NewFix(ObjFix[nofObjFix], OPS.name);  ObjFix[nofObjFix].obj := first;  INC(nofObjFix);
					END;
					IF typ.incomplete THEN		(*incomplete structure, check (to repair the mode)*)
						NewCheck(first);
						first.mode := -first.mode	(* mark variable *)
					END;
					first^.typ := typ; first := first^.link
				END ;
				IF sym = semicolon THEN OPS.Get(sym)
				ELSIF sym = ident THEN err(semicolon)
				ELSE EXIT
				END
			END
		END ;
		CheckSym(rparen);
		IF sym = colon THEN
			OPS.Get(sym); resTyp := OPT.undftyp;
			typ := NIL;
			WHILE sym = array DO
				OPS.Get(sym); CheckSym(of);
				btyp := typ;
				typ := OPT.NewStr(Comp, OpenArr); typ.incomplete := TRUE; typ.BaseTyp := btyp;
				IF btyp = NIL THEN resTyp := typ END;
			END;
			IF sym = ident THEN qualident(res);
				IF res = UndefObj THEN
					IF typ # NIL THEN
						NewFix(TypFix[nofTypFix], OPS.name); TypFix[nofTypFix].typ := resTyp; INC(nofTypFix);
						resTyp := typ
					ELSE
						resTyp := NIL;		(* special handling -> new fix in GetParams *)
					END;
					IF (sysflag # 0) THEN err(200) END
				ELSIF res^.mode = Typ THEN
					IF typ#NIL THEN  resTyp.BaseTyp := res^.typ; resTyp := typ; CheckStruct(typ)
					ELSE resTyp := res^.typ
					END;
					IF (sysflag # 0) & (resTyp.form = Comp) THEN err(200) END
				ELSE err(52)
				END
			ELSE err(ident)
			END
		ELSE resTyp := OPT.notyp
		END;
	END FormalParameters;

	PROCEDURE CheckAndFix(typ: OPT.Struct);
		VAR lev: SHORTINT;
	BEGIN
		WHILE typ.comp = SDynArr DO
			lev := typ.link.mnolev;
			IF lev#level THEN typ.link.leaf:=FALSE; IF lev>0 THEN OPB.StaticLink(level-lev) END END;
			typ:=typ.BaseTyp
		END;
	END CheckAndFix;

	PROCEDURE TypeDecl(VAR typ, banned: OPT.Struct; owner: OPT.Object);
		VAR id: OPT.Object; name: OPS.Name;
	BEGIN typ := OPT.undftyp;
		IF sym < lparen THEN err(12);
			REPEAT OPS.Get(sym) UNTIL sym >= lparen
		END ;
		name := OPS.name;
		IF sym = ident THEN qualident(id);
			OPS.name := name;
			IF id = UndefObj THEN typ := OPT.undftyp; UndefFlag := FALSE;
				IF (sym = period) THEN
					OPT.FindInScope (name, ExtObj, id);
					IF (id # NIL) & (id.mode = Mod) THEN
						OPS.Get (sym); OPT.FindImport (id, id); OPS.Get(sym);
					END;
					IF id = NIL THEN err (0); typ := OPT.undftyp
					ELSIF id.mode = Typ THEN
						IF id^.typ # banned THEN typ := id^.typ ELSE err(58) END
					ELSE err (52); typ := OPT.undftyp
					END
				ELSE
					typ := OPT.ToBeFixed;	(*will be fixed by the caller!!! Name is in OPS.name stored*)
				END
			ELSIF id^.mode = Typ THEN
				IF id^.typ # banned THEN typ := id^.typ ELSE err(58) END
			ELSE err(52)
			END;
			IF id#NIL THEN CheckAndFix(id.typ) END
		ELSIF sym = array THEN
			OPS.Get(sym); ArrayType(typ, banned);
		ELSIF sym = record THEN
			OPS.Get(sym); RecordType(typ, banned, owner);
			OPB.Inittd(TDinit, lastTDinit, typ); (*CheckSym(end)*)	(* --> done in RecordType *)
		ELSIF sym = pointer THEN
			OPS.Get(sym); PointerType(typ, banned);
		ELSIF sym = object THEN
			OPS.Get(sym); ObjectType(typ, banned);
			OPB.Inittd(TDinit, lastTDinit, typ.BaseTyp);
		ELSIF sym = procedure THEN
			IF OPM.WarnUnsafe THEN OPM.err(-1112) END;
			OPS.Get(sym); typ := OPT.NewStr(ProcTyp, Basic);
			IF OPM.OptimizeSelf THEN
				CheckSysFlag(typ^.sysflag, 0, {0, stdcall, cdecl, delegate})
			ELSE
				CheckSysFlag(typ^.sysflag, 0, {0, stdcall, cdecl})
			END;
			IF sym = lparen THEN
				OPS.Get(sym); OPT.OpenScope(level, NIL);
				FormalParameters(typ^.link, typ^.BaseTyp, typ^.sysflag); OPT.CloseScope;
				id := typ.link;
				WHILE (id#NIL)& ~id.typ.incomplete DO  id := id.link  END;
				typ.incomplete := (id#NIL)&id.typ.incomplete;
				IF typ.BaseTyp = NIL THEN
					NewFix(TypFix[nofTypFix], OPS.name);  TypFix[nofTypFix].typ := typ;  INC(nofTypFix);  typ.incomplete := TRUE;
				END;
				UndefFlag := FALSE
			ELSE typ^.BaseTyp := OPT.notyp; typ^.link := NIL
			END
		ELSE err(12)
		END ;
		LOOP
			IF (sym >= semicolon) & (sym <= else) OR (sym = rparen) OR (sym = eof) OR (sym = ident) THEN EXIT END;
			err(15); IF sym = ident THEN EXIT END;
			OPS.Get(sym)
		END
	END TypeDecl;
	
	PROCEDURE selector(VAR x: OPT.Node);
		VAR obj, proc: OPT.Object; y: OPT.Node; typ: OPT.Struct; name: OPS.Name;
	BEGIN
		IF x.obj.name = "SELF" THEN
			(* object self or module self ? *)
			OPT.FindInScope ("@SELF", OPT.topScope, obj);
			IF obj.typ.comp = Record THEN	(* <- local self *)
				(* x <= S.VAL (PTR, S.ADR (x)) *)
				x := OPB.NewLeaf (obj);
				IF (obj.typ.ptr # NIL)&(sym # period) THEN
					OPB.StPar0 (x, 20); OPB.StFct (x, 20, 1);	(* S.ADR *)
					x.typ := obj.typ.ptr
				END
			ELSIF obj.typ # OPT.ptrtyp THEN	(* local, but already pointer (i.e. in the body) *)
				x := OPB.NewLeaf (obj)
			END
		END;
		LOOP
			IF sym = lbrak THEN OPS.Get(sym);
				LOOP
					IF (x^.typ # NIL) & (x^.typ^.form = Pointer) THEN OPB.DeRef(x) END ;
					Expression(y); IF ~UndefFlag THEN OPB.Index(x, y) END;
					IF sym = comma THEN OPS.Get(sym) ELSE EXIT END
				END ;
				CheckSym(rbrak)
			ELSIF (sym = period) THEN 
				OPS.Get(sym);
				IF sym = ident THEN name := OPS.name; OPS.Get(sym);
					IF UndefFlag & ~FixPhase THEN	(*delayed*)
					ELSIF x^.typ # NIL THEN
						IF x^.typ^.form = Pointer THEN 
							OPT.MarkObj(x.typ.strobj);
							OPB.DeRef(x)
						END;
						IF x^.typ^.comp = Record THEN
							OPT.FindField(name, x^.typ, obj, TRUE); 
							IF ((obj = NIL) OR (obj.mode < 0)) & ~FixPhase THEN UndefFlag := TRUE ELSE OPB.Field(x, obj) END;
						ELSIF (x.typ = OPT.undftyp) & ~FixPhase THEN UndefFlag := TRUE		(*can happen when the btyp is not known(?)*)
						ELSE err(53)
						END (* x^.typ^.comp = Record *)
					ELSE err(52)
					END (*x^.typ # NIL*)
				ELSE err(ident)
				END (*sym = ident*)
			ELSIF sym = arrow THEN OPS.Get(sym);
				IF UndefFlag & ~FixPhase THEN
				ELSIF (x.obj#NIL) & (x.obj^.mode = TProc) THEN
					y := x^.left;
					IF y^.class = Nderef THEN y := y^.left END ;	(* y = record variable *)
					IF y^.obj # NIL THEN
						proc := OPT.topScope;	(* find innermost scope which owner is a TProc *)
						WHILE (proc^.link # NIL) & (proc^.link^.mode # TProc) DO proc := proc^.left END ;
						IF (proc^.link = NIL) OR (proc^.link^.link # y^.obj) THEN err(75) END ;
						typ := y^.obj^.typ;
						IF typ^.form = Pointer THEN typ := typ^.BaseTyp END ;
						OPT.FindField (x.obj.name, typ^.BaseTyp, proc, TRUE);
						IF proc # NIL THEN
							x^.subcl := super;
						ELSE err(74) END
					ELSE err(75)
					END	(* y^.obj # NIL *)
				ELSIF x.typ.form # Pointer THEN err(84)
				ELSE OPB.DeRef(x)
				END
			ELSIF (sym = lparen) & UndefFlag & ~FixPhase THEN	(*type cast or proc call, here is Oberon ambigous*)
				OPS.Get(sym);  UndefFlag := FALSE; 
				IF sym # rparen THEN
					Expression(x);
					WHILE sym = comma DO
						OPS.Get(sym);  UndefFlag := FALSE;  Expression(x)
					END
				END;
				CheckSym(rparen); UndefFlag := TRUE
			ELSIF (sym = lparen) & (x^.class < Nconst) & (x^.typ #NIL) & (x^.typ^.form # ProcTyp) &
					((x^.obj = NIL) OR (x^.obj^.mode # TProc)) THEN
				OPS.Get(sym);
				IF sym = ident THEN
					qualident(obj);
					IF obj^.mode = Typ THEN OPB.TypTest(x, obj, TRUE)
					ELSIF ~UndefFlag THEN err(52)
					ELSIF sym = period THEN	(* M.T -> Module not defined *)
						err (0); OPS.Get (sym); CheckSym (ident)
					END
				ELSE err(ident)
				END ;
				CheckSym(rparen)
			ELSE EXIT
			END
		END
	END selector;

	PROCEDURE ActualParameters(VAR aparlist: OPT.Node; fpar: OPT.Object);
		VAR apar, last, aparret, lastret: OPT.Node;
			b: BOOLEAN;
	BEGIN aparlist := NIL; last := NIL; b := UndefFlag; lastret:=NIL; aparret:=NIL;
		IF sym # rparen THEN
			LOOP 
				Expression(apar);
				IF fpar # NIL THEN
					UndefFlag := UndefFlag OR (fpar.mode<0);
					IF ~UndefFlag & ~ b THEN
						OPB.Param(apar, fpar); OPB.Link(aparlist, last, apar)
					END;
					fpar := fpar^.link;
				ELSIF ~UndefFlag & ~ b THEN err(64)
				END;
				IF sym = comma THEN OPS.Get(sym)
				ELSIF (lparen <= sym) & (sym <= ident) THEN err(comma)
				ELSE EXIT
				END
			END;
			IF aparret#NIL THEN lastret.link:=aparlist; aparlist:=aparret END
		END ;
		IF (fpar # NIL) & ~UndefFlag & ~ b THEN err(65) END;
		UndefFlag := UndefFlag OR b
	END ActualParameters;


	PROCEDURE Await(VAR x: OPT.Node; VAR n: INTEGER);
		VAR proc, self: OPT.Object; exp, cond: OPT.Node; name: OPS.Name; i: LONGINT; ts: OPS.TokenStream;
	BEGIN
		self := GetSelf();
		IF sym = lparen THEN
			n := 1; OPS.Get(sym);
		(* Create guard evaluation function *)
			IF OPT.topScope^.link = NIL THEN name := "$$"
			ELSE name := OPT.topScope^.link^.name END;
			i := 0; WHILE name[i] # 0X DO INC(i) END;
			name[i] := ".";
			name[i+1] := "@";
			name[i+2] := CHR((CondCount DIV 100) MOD 10 + ORD("0"));
			name[i+3] := CHR((CondCount DIV 10) MOD 10 + ORD("0"));
			name[i+4] := CHR(CondCount MOD 10 + ORD("0"));
			name[i+5] := 0X;
			INC(CondCount);
			OPT.Insert(name, proc); proc.mode := XProc;		(* XProc, because this proc is passed as param, needs fixup!! *)
			proc.link := NIL; proc.vis := internal; proc.adr := 0;
			proc^.typ := OPT.booltyp; proc.conval := OPT.NewConst(); proc^.conval^.setval := {hasBody, slNeeded};
			proc.conval.intval := 12;
			INC(level); OPT.OpenScope(level, proc);
			Expression(x);
			IF UndefFlag THEN
				exp := x; proc.typ := x.typ; OPB.Return(x, proc); proc^.typ := OPT.booltyp
			ELSE
				OPB.StPar0(x, awaitfn); OPB.Return(x, proc);
			END;
			OPT.CloseScope; DEC(level);
			x.conval := OPT.NewConst(); x^.conval.intval := OPM.errpos;
			cond := NIL; OPB.Enter(cond, x, proc); cond.link := CondNodes; CondNodes := cond;
			cond.conval := OPT.NewConst(); cond^.conval.intval := OPM.errpos;
		(* Create parameters for the await call *)
			x := OPB.NewLeaf(proc); 
			x.link := OPB.NewLeaf(self);	(* Always push SELF *)
			CheckSym(rparen); 
		ELSE
			err (65)
		END;
		IF OPB.AwaitIF THEN
			x.link.link := OPB.NewIntConst(0)
		ELSE
			x.link.link := OPB.NewIntConst(2)
		END;
		IF UndefFlag THEN
			UndefFlag := FALSE; OPS.StopRecording (ts);
			InsertFix (FPassExpr, ts, exp)
		END
	END Await;

	PROCEDURE StandProcCall(VAR x: OPT.Node);
		VAR y: OPT.Node; m: SHORTINT; n: INTEGER;
			flag, flag1: BOOLEAN;
	BEGIN m := SHORT(SHORT(x^.obj^.adr)); n := 0;
		IF ((m = sizefn) OR (m = lenfn)) & (OPB.verify # NIL) THEN
			flag := TRUE; OPB.verify := NIL; flag1 := FixPhase; FixPhase := TRUE
		END;
		IF m = awaitfn THEN
			Await(x, n)
		ELSIF sym = lparen THEN OPS.Get(sym);
			IF sym # rparen THEN
				LOOP
					IF n = 0 THEN Expression(x);
						(* intercept derefencing of undefined types *)
						IF ~UndefFlag & ~FixPhase & (m = newfn) & (n = 0) & (x.typ.BaseTyp = OPT.undftyp) THEN UndefFlag := TRUE END;
						IF ~UndefFlag THEN OPB.StPar0(x, m) END; n := 1
					ELSIF n = 1 THEN Expression(y); IF ~UndefFlag THEN OPB.StPar1(x, y, m) END; n := 2
					ELSE Expression(y); IF ~UndefFlag THEN OPB.StParN(x, y, m, n) END; INC(n)
					END ;
					IF sym = comma THEN OPS.Get(sym)
					ELSIF (lparen <= sym) & (sym <= ident) THEN err(comma)
					ELSE EXIT
					END
				END ;
				CheckSym(rparen)
			ELSE OPS.Get(sym)
			END ;
		END ;
		IF ~UndefFlag THEN OPB.StFct(x, m, n) END;
		IF flag THEN OPB.verify := OwnScope; FixPhase := flag1 END;
		IF (level > 0) & ((m = newfn) OR (m = sysnewfn)) THEN OPT.topScope^.link^.leaf := FALSE END
	END StandProcCall;
	
	PROCEDURE InlineProc(VAR x: OPT.Node; VAR apar: OPT.Node; fpar: OPT.Object);			(* Inline *)
		VAR inline, par, list: OPT.Object; glueCode, src, trg: OPT.Node; assembly: BOOLEAN; c: OPT.Const;
		
			PROCEDURE CopyLocals(obj: OPT.Object);
				VAR	new: OPT.Object; name: OPS.Name; i, j: LONGINT;
			BEGIN
				IF obj # NIL THEN
					IF (obj^.mode = Var) OR (assembly & (obj^.mode = VarPar)) THEN
						i := 0; WHILE inline^.name[i] # 0X DO name[i] := inline^.name[i]; INC(i) END;
						name[i] := "."; INC(i);
						j := 0; WHILE obj^.name[j] # 0X DO name[i] := obj^.name[j]; INC(j); INC(i) END;
						name[i] := 0X;
						OPT.Insert(name, new);
						new.flag := {OPT.used};
						par.link := new; par := new;
						new^.leaf := FALSE(*obj^.leaf*); new^.mode := obj^.mode;
						new^.vis := internal; new^.typ := obj^.typ;
						obj^.link2 := new;
						IF assembly THEN new^.link2 := obj END
					END;
					CopyLocals(obj^.left);		(* pre-order traversing --> prevents a degenerated list *)
					CopyLocals(obj^.right)
				END
			END CopyLocals;
			
	BEGIN
			inline := x^.obj; assembly := asmProc IN inline^.conval^.setval;
		(* get parameters *)
			IF ~OPM.noerr THEN
				IF assembly THEN	(* get rid of annoying duplicate 126 *)
					x.class := Ncall; x.typ := x.obj.typ; x^.subcl := 2
				END;
				RETURN
			END;
			IF ~(hasBody IN inline^.conval^.setval) THEN err(129); RETURN END;
		(* insert locals *)
			IF ~assembly & (inline^.link2 # OPT.topScope) THEN	(* do it only the first time *)
				par := OPT.topScope.scope;
				IF par # NIL THEN 
					WHILE par^.link # NIL DO par := par^.link END;
					CopyLocals(inline^.scope^.right)
				ELSE
					NEW(list); par := list;
					CopyLocals(inline^.scope^.right);
					IF OPT.topScope.scope # NIL THEN OPT.topScope.scope := list^.link END
				END;
				inline^.link2 := OPT.topScope;
			END;
		(* insert glue-code *)
			IF assembly THEN
				OPB.Call(x, apar, fpar);				(* this is the glue code for the inline *)
				OPB.CopyAndSubst(x^.left, inline^.code);
				x^.subcl := 2;	(* inlined proc *)
			ELSE
				x := NIL; glueCode := NIL;
				c := OPT.NewConst(); c^.intval := OPM.errpos;
				WHILE fpar # NIL DO
					IF fpar^.mode = VarPar THEN
						fpar^.link2 := apar^.obj;
						apar := apar^.link
					ELSE
						(* move apar to fpar *)
							src := apar; apar := apar^.link; src^.link := NIL;
							trg := OPB.NewLeaf(fpar^.link2);
							OPB.Assign(trg, src); trg.conval := c;
							IF glueCode = NIL THEN x := trg ELSE glueCode^.link := trg END;
							glueCode := trg
					END;
					fpar := fpar^.link
				END;
		(* copy parse tree *)
				IF glueCode = NIL THEN
					OPB.CopyAndSubst(x, inline^.code)
				ELSE
					OPB.CopyAndSubst(glueCode^.link, inline^.code)
				END
			END
	END InlineProc;
	
	PROCEDURE Element(VAR x: OPT.Node);
		VAR y: OPT.Node;
	BEGIN Expression(x);
		IF sym = upto THEN
			OPS.Get(sym); Expression(y);
			IF ~UndefFlag THEN OPB.SetRange(x, y) END
		ELSIF ~UndefFlag THEN OPB.SetElem(x)
		END
	END Element;

	PROCEDURE Sets(VAR x: OPT.Node);
		VAR y: OPT.Node;
	BEGIN
		IF sym # rbrace THEN
			Element(x);
			LOOP
				IF sym = comma THEN OPS.Get(sym)
				ELSIF (lparen <= sym) & (sym <= ident) THEN err(comma)
				ELSE EXIT
				END ;
				Element(y);
				IF ~UndefFlag THEN OPB.Op(plus, x, y) END
			END
		ELSE x := OPB.EmptySet()
		END ;
		CheckSym(rbrace)
	END Sets;
	
	PROCEDURE Resolve(VAR obj: OPT.Object; IN name: ARRAY OF CHAR; VAR x, y: OPT.Node);
	BEGIN
		obj:=OPT.Resolve(name, x, y); OPT.MarkObj (obj)
	END Resolve;
	
	PROCEDURE OpCall(VAR op: OPT.Object; VAR x: OPT.Node; y: OPT.Node);
		VAR fpar: OPT.Object; proc, apar, last, retlist, lastret: OPT.Node;
	BEGIN apar:=NIL; last:=NIL; retlist:=NIL; lastret:=NIL;
		IF op#NIL THEN
			(*IF op.prio=125 THEN err(136) END;*)
			proc:=OPB.NewLeaf(op); OPB.PrepCall(proc, fpar);
			IF (x.typ.form=Pointer) & (op.link.typ.comp=DynArr) THEN OPB.DeRef(x) END;
			OPB.Link(apar, last, x);
			IF y#NIL THEN
				OPB.Link(apar, last, y)
			END;
			IF retlist#NIL THEN lastret.link:=apar; apar:=retlist END;
			OPB.Call(proc, apar, fpar);
			x:=proc
		ELSE err(137)
		END
	END OpCall;

	PROCEDURE Factor (VAR x: OPT.Node);
		VAR fpar, id: OPT.Object; apar, y: OPT.Node; name: OPS.Name;
	BEGIN
		IF sym < lparen THEN err(13);
			REPEAT OPS.Get(sym) UNTIL sym >= lparen
		END ;
		IF sym = ident THEN
			qualident(id);
		END;
		IF (id#NIL) & (id.prio#127) THEN	(*found object is not an operator *)
			x := OPB.NewLeaf(id); selector(x);
			IF (x^.class = Nproc) & (x^.obj^.mode = SProc) THEN 
				IF (x.obj.name = "SIZE") & ~FixPhase THEN UndefFlag := TRUE END;
				StandProcCall(x)	(* x may be NIL *)
			ELSIF sym = lparen THEN
					UndefFlag := UndefFlag OR (x.typ = NIL);
					OPS.Get(sym);
					IF UndefFlag THEN
						ActualParameters(apar, fpar)
					ELSE
						OPB.PrepCall(x, fpar); ActualParameters(apar, fpar);
						IF (x^.class = Nproc) & (x^.obj^.mode = CProc) THEN InlineProc (x, apar, fpar)
						ELSE OPB.Call(x, apar, fpar)
						END;
					END;
					CheckSym(rparen);
					IF level > 0 THEN OPT.topScope^.link^.leaf := FALSE END
			END
		ELSIF (id#NIL) & (id.prio=127) THEN (* imported operator/ *)
			 OPS.Get(sym); Factor(x); Resolve(id, name, x, y); OpCall(id, x, NIL)
		ELSIF sym = number THEN
			CASE OPS.numtyp OF
			   char: x := OPB.NewIntConst(OPS.intval); x^.typ := OPT.chartyp
			| integer: x := OPB.NewIntConst(OPS.intval)
			| real: x := OPB.NewRealConst(OPS.realval, OPT.realtyp)
			| longreal: x := OPB.NewRealConst(OPS.lrlval, OPT.lrltyp)
			END ;
			OPS.Get(sym)
		ELSIF sym = true THEN
			x := OPB.BoolConst(1); OPS.Get(sym)	(* 1 is a compiler internal representation only *)
		ELSIF sym = false THEN
			x := OPB.BoolConst(0); OPS.Get(sym)	(* 0 is a compiler internal representation only *)
		ELSIF sym = string THEN
			x := OPB.NewString(OPS.str, OPS.intval); OPS.Get(sym)
		ELSIF sym = nil THEN
			x := OPB.Nil(); OPS.Get(sym)
		ELSIF sym = lparen THEN
			OPS.Get(sym); Expression(x); CheckSym(rparen)
		ELSIF sym = lbrak THEN
			OPS.Get(sym); err(lparen); Expression(x); CheckSym(rparen)
		ELSIF sym = lbrace THEN OPS.Get(sym); Sets(x)
		ELSIF (sym = not)  THEN
			name:=OPS.name; OPS.Get(sym); y:=NIL; id:=NIL;
			Factor(x);
			IF ~UndefFlag THEN	(*test*)
				Resolve(id, name, x, y);
				IF id=NIL THEN OPB.MOp(not, x)
				ELSE OpCall(id, x, y)
				END
			END
		ELSE err(13); OPS.Get(sym); x := NIL
		END ;
		IF x = NIL THEN x := OPB.NewIntConst(1); x^.typ := OPT.undftyp END
	END Factor;

	PROCEDURE Term(VAR x: OPT.Node);
		VAR 
			y: OPT.Node; mulop: SHORTINT; name: OPS.Name; op: OPT.Object;
			b: BOOLEAN;
	BEGIN
		b := UndefFlag; UndefFlag := FALSE;
		Factor(x);
		WHILE (times <= sym) & (sym <= and) DO 
			op:=NIL; mulop := sym; name:=OPS.name;
			OPS.Get(sym); Factor(y); 
			IF ~UndefFlag THEN Resolve(op, name, x, y);
				IF op=NIL THEN OPB.Op(mulop, x, y) 
				ELSE OpCall(op, x, y)
				END
			END
		END;
		UndefFlag := UndefFlag OR b;
	END Term;
	
	PROCEDURE SimpleExpression(VAR x: OPT.Node);
		VAR 
			y: OPT.Node; addop : SHORTINT; name: OPS.Name; op: OPT.Object;
			b: BOOLEAN;
	BEGIN
		b := UndefFlag; UndefFlag := FALSE;
		IF (sym=plus) OR (sym=minus) THEN
			op:=NIL; addop := sym; name:=OPS.name; OPS.Get(sym); 
			Term(x); y:=NIL;
			IF ~UndefFlag THEN Resolve(op, name, x, y);
				IF op=NIL THEN OPB.MOp(addop, x)
				ELSE OpCall(op, x, y)
				END
			END
		ELSE Term(x)
		END ;
		WHILE (plus <= sym) & (sym <= or) DO
			op:=NIL; addop := sym; name:=OPS.name; OPS.Get(sym);
			Term(y);
			IF ~UndefFlag THEN Resolve(op, name, x, y);
				IF op=NIL THEN OPB.Op(addop, x, y)
				ELSE OpCall(op, x, y)
				END
			END
		END;
		UndefFlag := UndefFlag OR b;
	END SimpleExpression;
	
	PROCEDURE Expression(VAR x: OPT.Node);
		VAR y: OPT.Node; obj: OPT.Object; relation: SHORTINT; name: OPS.Name; 
	BEGIN SimpleExpression(x);
		IF (eql <= sym) & (sym <= geq) THEN
			obj:=NIL; relation := sym; name:=OPS.name;
			OPS.Get(sym); SimpleExpression(y);
			IF ~UndefFlag THEN Resolve(obj, name, x, y);
				IF obj=NIL THEN OPB.Op(relation, x, y)
				ELSE OpCall(obj, x, y)
				END
			END
		ELSIF sym = in THEN
			obj:=NIL; name:=OPS.name;
			OPS.Get(sym); SimpleExpression(y);
			IF ~UndefFlag THEN Resolve(obj, name, x, y);
				IF obj=NIL THEN OPB.In(x, y)
				ELSE OpCall(obj, x, y)
				END
			END
		ELSIF sym = is THEN
			OPS.Get(sym);
			IF sym = ident THEN
				qualident(obj);
				IF ~UndefFlag THEN
					IF obj^.mode = Typ THEN OPB.TypTest(x, obj, FALSE)
					ELSE err(52)
					END
				ELSE
					IF sym = period THEN err (0); OPS.Get (sym); CheckSym (ident) END
				END
			ELSE err(ident)
			END
		END
	END Expression;
	
	PROCEDURE ProcedureDeclaration(VAR x: OPT.Node);
		 (* operator prio =126
			 sentinel prio = 127
			 temp against recursive oper = 128 *)

		VAR proc, fwd: OPT.Object;
			name: OPS.Name;
			sysflag, mode, vis, prio: SHORTINT;
			forward, init: BOOLEAN;
			flags: SET;
			scope: OPT.Object; redef: BOOLEAN;
			selfname: OPS.Name; selftype, selfrec: OPT.Struct; selfmode: SHORTINT;

		PROCEDURE GetParam;	(* set link and typ *)
		BEGIN
			proc.typ := OPT.notyp; proc.link := NIL; proc^.sysflag := sysflag;
			IF mode = TProc THEN (* insert hidden self *)
				OPT.Insert (selfname, proc.link); 
				proc.link.mode := selfmode; proc.link.typ := selftype;
			END;
			IF sym = lparen THEN
				OPS.Get(sym); 
				IF mode # TProc THEN FormalParameters(proc^.link, proc^.typ, sysflag)
				ELSE FormalParameters(proc^.link^.link, proc^.typ, sysflag)
				END;
				IF proc.typ = NIL THEN
					NewFix(ObjFix[nofObjFix], OPS.name);  ObjFix[nofObjFix].obj := proc;  INC(nofObjFix)
				END;
				IF (proc.typ = NIL) OR (proc.typ.incomplete) THEN  NewCheck(proc)  END;
			ELSIF prio=126 THEN err(30)	(* operator should have parameters *)
			END;
			IF prio=126 THEN
				IF proc.name=":=" THEN
					IF proc^.typ#OPT.notyp THEN err(147) END;
					IF (proc.link#NIL)&(proc.link.mode#VarPar) THEN err(148) END;
				ELSIF proc^.typ=OPT.notyp THEN err(141) END;
				IF ~forward THEN OPT.Contextualize(proc);  proc.prio:=125; OPT.topScope.link:=proc
				ELSE err(145)
				END
			END;
			IF (fwd # NIL) & (prio<126) THEN
				IF (mode = TProc) & redef THEN
					INCL(proc.flag, OPT.used);
					OPB.CheckParameters (proc.link.link, fwd.link.link, FALSE);
					IF proc.link.mode # fwd.link.mode THEN err(115) END
				ELSE
					OPB.CheckParameters (proc.link, fwd.link, TRUE)
				END;
				IF proc.typ # fwd.typ THEN err(117) END;
				IF ~redef THEN proc := fwd; OPT.topScope := fwd.scope 
				ELSE INCL (proc.conval.setval, isRedef) END
			END;
			(* general checks *)
			IF init & (proc.typ # OPT.notyp) THEN err(134) END;
			IF init & (OPT.topScope.left.link.mode = Mod) & (proc.link # NIL) THEN err(133) END;
			IF (OPM.oberon1 IN OPM.options) & (proc.typ # NIL) & (proc.typ.form = Comp) THEN err(270) END
		END GetParam;

		PROCEDURE Body;
			VAR c, n: LONGINT; ext: OPT.ConstExt; procdec, statseq: OPT.Node;
		BEGIN
			c := OPM.errpos; INCL(proc.conval.setval, hasBody);
			IF (sym = number) THEN		(* old style inline *)
				IF ~OPT.SYSimported THEN err(135) END ;
				statseq := OPT.NewNode(Ncode); statseq.conval := OPT.NewConst(); procdec := NIL;
				n := 0; ext := OPT.NewExt(); statseq.conval.ext := ext;
				OPB.Construct (Nassembler, statseq, NIL); statseq.conval := OPT.NewConst(); statseq.conval.intval := c;
				statseq.obj := proc;
				INCL (proc.conval.setval, asmProc); proc.conval.ext := ext;
				LOOP
					IF sym = number THEN INC(n);
						IF (OPS.intval < 0) OR (OPS.intval > 255) OR (n = OPT.MaxConstLen) THEN
							err(63); OPS.intval := 1; n := 1
						END ;
						ext[n] := CHR(OPS.intval);
						OPS.Get(sym); 
					END ;
					IF sym = comma THEN OPS.Get(sym)
					ELSIF sym = number THEN err(comma)
					ELSE
						ext[0] := CHR(n);
						EXIT
					END
				END
			ELSE		(* oberon procedure *)
				CheckSym(semicolon);
				Block(procdec, statseq);
				IF (sym=number) OR (sym=string) THEN OPS.name := OPS.str; sym := ident; proc.prio := prio END;
				IF sym = ident THEN
					IF OPS.name # proc.name THEN err(4) END;
					OPS.Get(sym)
				ELSE err(ident)
				END
			END;
			IF mode = CProc THEN
				IF ~(asmProc IN proc.conval.setval) & ((proc.typ # OPT.notyp) OR (procdec # NIL)) THEN err(200) END;
				proc.code := statseq; procdec := NIL
			ELSE
				OPB.Enter(procdec, statseq, proc);
				procdec.conval := OPT.NewConst(); procdec.conval.intval := c;
			END;
			x := procdec;
		END Body;
		
		PROCEDURE Receiver;
			VAR obj: OPT.Object; rec: OPT.Struct;
		BEGIN
			IF IsObjectScope() THEN
				mode := TProc;
				rec := OPT.topScope.link.typ;
				ASSERT(rec.comp = Record);
				IF OPM.OptimizeSelf & (rec.ptr # NIL) THEN
					ASSERT(rec.ptr.form = Pointer);
					selfmode := Var; selfname := HiddenSelf; selftype := rec.ptr; selfrec := rec
				ELSE
					selfmode := VarPar; selfname := HiddenSelf; selftype := rec; selfrec := rec
				END;
				IF (OPM.oberon1 IN OPM.options) THEN err(261) END
			ELSIF (sym = lparen) & (OPM.oberon2 IN OPM.options) THEN
				mode := TProc; OPS.Get(sym);
				IF sym = var THEN selfmode := VarPar; OPS.Get(sym) ELSE selfmode := Var END;
				selfname := OPS.name; CheckSym(ident); CheckSym(colon);
				IF sym = ident THEN OPT.Find (obj); OPS.Get(sym);
					IF obj = NIL THEN err(0); selftype := OPT.undftyp;
					ELSIF obj^.mode # Typ THEN err(72);  selftype := OPT.undftyp;
					ELSE selftype := obj^.typ; selfrec := selftype;
						IF selftype^.form = Pointer THEN selfrec := selfrec^.BaseTyp END ;
						IF ~((selfmode = Var) & (selftype^.form = Pointer) & (selfrec^.comp = Record) OR
							(selfmode = VarPar) & (selftype^.comp = Record)) THEN err(70); (*rec := NIL*) END ;
						IF (selfrec # NIL) & (selfrec^.mno # level) THEN err(72); (*rec := NIL*) END;
						IF selfrec.comp = Record THEN OPT.topScope := selfrec.strobj.scope END;
					END
				ELSE err(ident)
				END;
				CheckSym(rparen)
			END
		END Receiver;
		
	BEGIN
		(* init vars *)
		forward := FALSE; scope := OPT.topScope;
		proc := NIL; x := NIL; mode := LProc; init := FALSE; flags := {};
		prio := 0;

		IF sym = arrow THEN forward := TRUE; OPS.Get(sym) END;
		Receiver;	(* set mode + scope + selfXYZ vars *)
		
		(* special modes *)
		IF (sym # ident) & (sym # string) & (sym # number) THEN
			IF sym = lbrak THEN
				IF mode = TProc THEN CheckSysFlag(sysflag, 0, {0})
				ELSE CheckSysFlag(sysflag, 0, {0, stdcall, cdecl})
				END
			END;
			IF sym = times THEN OPS.Get (sym)	(* mode set later in OPB.CheckAssign *)
			ELSIF sym = plus THEN
				IF mode = TProc THEN err(47) END;
				mode := IProc; 
				IF ~OPT.SYSimported THEN err(135) END ;
				OPS.Get (sym)
			ELSIF sym = and THEN init := TRUE;
				IF ~IsObjectScope() THEN err(253) END;
				IF (OPT.topScope.link.link2 # NIL) & (OPT.topScope.link.link2.link.typ.strobj.scope = OPT.topScope) THEN err(144) END;
				IF (OPT.topScope.link.typ.ptr = NIL) THEN err(249) END;
				OPS.Get (sym)
			ELSIF sym = minus THEN
				IF mode = TProc THEN err(47) END;
				mode := CProc;
				OPS.Get (sym)
			ELSIF sysflag = 0 THEN err(ident)
			END;
		END;
		IF (sym=number) OR (sym=string) THEN
			OPS.CheckOperator(prio);
			IF prio=126 THEN
				sym:=ident;
				IF IsObjectScope() THEN err(140)
				ELSIF ~forward & (operatorFlag IN OPT.topScope.conval.setval) THEN err(-212)
				END
			ELSE
				err(142)
			END
		ELSIF ~IsObjectScope() THEN INCL(OPT.topScope.conval.setval, operatorFlag)
		END;
		IF (sym = ident) OR (sym=number) OR (sym=string) THEN OPT.Find (fwd);
			name := OPS.name; CheckMark(vis, TRUE);
			IF init THEN vis := external END;
			IF (vis # internal) & (mode = LProc) THEN mode := XProc END ;
			
			(* false forwards *)
			IF (fwd # NIL) & (~(fwd.mode IN {TProc, LProc, XProc, CProc, IProc}) OR ((fwd.mnolev >= 0) & (fwd.mnolev # level)) OR ((mode=TProc) & (fwd.mode#TProc)) OR (prio=126)) THEN 
				fwd := NIL
			END;
			redef := (fwd # NIL) & (mode = TProc) & (fwd.mode = TProc) & (selfrec # fwd.link.typ) & (selfrec # fwd.link.typ.BaseTyp) ;
			IF (fwd = NIL) OR redef THEN
				IF ~(OPM.oberon2 IN OPM.options) OR (mode # TProc) OR (selftype # NIL) THEN
					OPT.Insert (name, proc)
				ELSE proc := OPT.NewObj(); proc.name := name
				END;
				(* special case for o2-methods in an empty record *)
				IF (scope # OPT.topScope) & (selfrec.link = NIL) THEN selfrec.link := OPT.topScope.right END;
				proc.prio := prio
			ELSE
				IF vis # fwd.vis THEN err(118) END;
				IF hasBody IN fwd.conval.setval THEN err(1) END;
				proc := OPT.NewObj(); proc^.leaf := TRUE;
			END;
			
			proc.mode := mode; proc.vis := vis;
			proc.conval := OPT.NewConst(); proc.conval.setval := flags;
			IF IsObjectScope() & (selfrec.BaseTyp # NIL) & selfrec.BaseTyp.incomplete THEN
				SetFlags(OPT.topScope.link, {checkOverwriting});
				proc.conval.intval := OPM.errpos
			END;
			
			(* general limitations and link setup *)
			IF (mode # LProc) & (level > 0) THEN err(73) END ;
			IF init THEN OPT.topScope.link.link2 := proc END;
			
			(* parse params+body *)
			OPT.topScope := scope;
			INC(level); OPT.OpenScope(level, proc); OPT.topScope.adr := OPM.errpos;
			OPT.topScope.conval := OPT.NewConst();
			GetParam;
			IF ~forward THEN Body END;
			DEC(level); OPT.CloseScope;
			
		ELSE err(ident)
		END;
	END ProcedureDeclaration;

	PROCEDURE CaseLabelList(VAR lab: OPT.Node; LabelForm: INTEGER; VAR n: INTEGER; VAR tab: CaseTable);
		VAR x, y, lastlab: OPT.Node; i, f: INTEGER; xval, yval: LONGINT;
	BEGIN lab := NIL; lastlab := NIL;
		LOOP ConstExpression(x); f := x^.typ^.form;
			IF f IN intSet + {Char} THEN  xval := x^.conval^.intval
			ELSE err(61); xval := 1
			END ;
			IF f IN intSet THEN
				IF LabelForm < f THEN err(60) END
			ELSIF LabelForm # f THEN err(60)
			END ;
			IF sym = upto THEN
				OPS.Get(sym); ConstExpression(y); yval := y^.conval^.intval;
				IF (y^.typ^.form # f) & ~((f IN intSet) & (y^.typ^.form IN intSet)) THEN err(60) END ;
				IF yval < xval THEN err(63); yval := xval END
			ELSE yval := xval
			END ;
			x^.conval^.intval2 := yval;
			(*enter label range into ordered table*)  i := n;
			IF i < OPM.MaxCases THEN
				LOOP
					IF i = 0 THEN EXIT END ;
					IF tab[i-1].low <= yval THEN
						IF tab[i-1].high >= xval THEN err(62) END ;
						EXIT
					END ;
					tab[i] := tab[i-1]; DEC(i)
				END ;
				tab[i].low := xval; tab[i].high := yval; INC(n)
			ELSE err(213)
			END ;
			OPB.Link(lab, lastlab, x);
			IF sym = comma THEN OPS.Get(sym)
			ELSIF (sym = number) OR (sym = ident) THEN err(comma)
			ELSE EXIT
			END
		END
	END CaseLabelList;

	PROCEDURE CheckBool(VAR x: OPT.Node);
	BEGIN
		IF (x^.class = Ntype) OR (x^.class = Nproc) OR (x.class = Nfield) & (x.obj.mode = TProc) THEN err(126); x := OPB.NewBoolConst(FALSE)
		ELSIF x.typ = NIL THEN err(120); x := OPB.NewBoolConst(FALSE)
		ELSIF x^.typ^.form # Bool THEN err(120); x := OPB.NewBoolConst(FALSE)
		END ;
	END CheckBool;

	PROCEDURE DoFixes;
		VAR id, obj, typ, fpar, topscope, (*scope, *)op: OPT.Object; x, y, z, link, apar: OPT.Node; conval: OPT.Const; i: LONGINT;
			sysflag, done: BOOLEAN;
	BEGIN
		topscope := OPT.topScope; i := 0;
		
		REPEAT
			i := 0; done := FALSE;
(*OPM.LogWLn; OPM.LogWStr("Start OBJ fix");*)
			WHILE i < nofObjFix DO
				IF  ObjFix[i].obj # NIL THEN
(*OPM.LogWLn; OPM.LogWStr("fixing..."); OPM.LogWStr(ObjFix[i].name);*)
					OPM.errpos := ObjFix[i].pos; level := ObjFix[i].level;
					OPT.FindInScope(ObjFix[i].name, ObjFix[i].scope, typ);
					IF typ # NIL THEN
(*OPM.LogWStr("  done");*)
						ObjFix[i].obj.mode := ABS(ObjFix[i].obj.mode);
						ObjFix[i].obj.typ := typ.typ;  ObjFix[i].obj := NIL;  done := TRUE
					(*ELSE
OPM.LogWStr("  failed");*)
					END
				END;
				INC(i)
			END;
		UNTIL ~done;
		FixPhase := TRUE; 
		i := 0;
		WHILE i < nofObjFix DO
			IF  ObjFix[i].obj # NIL THEN  OPM.Mark(0, ObjFix[i].pos);  ObjFix[i].obj := NIL;  ObjFix[i].scope := NIL  END;
			INC(i)
		END;
		nofObjFix := 0;

(*OPM.LogWLn; OPM.LogWStr("Start TYPE fix");*)
		WHILE 0 < nofTypFix DO
			DEC(nofTypFix);
			IF TypFix[nofTypFix].typ # NIL THEN
(*OPM.LogWLn; OPM.LogWStr("fixing..."); OPM.LogWStr(TypFix[i].name);*)
				OPM.errpos := TypFix[nofTypFix].pos; level := TypFix[nofObjFix].level;
				OPT.FindInScope(TypFix[nofTypFix].name, TypFix[nofTypFix].scope, typ);
				IF typ # NIL THEN
					TypFix[nofTypFix].typ.BaseTyp := typ.typ
				ELSIF TypFix[nofTypFix].typ.comp = Record THEN
					err(0);  TypFix[nofTypFix].typ.BaseTyp := NIL
				ELSE
					err(0);  TypFix[nofTypFix].typ.BaseTyp := OPT.undftyp
				END;
				TypFix[nofTypFix].typ := NIL; TypFix[nofTypFix].scope := NIL
			END
		END;
		i := 0;
(*OPM.LogWLn; OPM.LogWStr("Start Check");*)
		WHILE i < nofCheck DO
			IF ObjCheck[i].obj # NIL THEN
(*OPM.LogWLn; OPM.LogWStr("checking..."); OPM.LogWStr(ObjCheck[i].obj.name);*)
				level := ObjCheck[i].level;
				ObjCheck[i].obj.mode := ABS(ObjCheck[i].obj.mode);
				CheckObj(ObjCheck[i].obj); ObjCheck[i].obj := NIL;
			END;
			INC(i)
		END;
		
		WHILE FixList # NIL DO
			OPT.topScope := FixList.scope; level := FixList.level;
			OPS.StartPlaying (FixList.stream); x := FixList.node; OPS.Get (sym);
			link := x.link; x.link := NIL; conval := x.conval; x.conval := NIL;

			CASE FixList.mode OF
			| FTarget:
					NEW(y); y := x^.left;
					qualident (id); z := OPB.NewLeaf (id); selector (z);
					Resolve(op, ":=", z, y);
					IF op=NIL THEN  OPB.Assign(z, y)  ELSE  OpCall(op, z, y)  END
			| FExpr:
					NEW(z); z^ := x^;
					Expression (y); 
					Resolve(op, ":=", z, y);
					IF op=NIL THEN  OPB.Assign(z, y)  ELSE  OpCall(op, z, y)  END
			| FAssign:
					qualident(id); z := OPB.NewLeaf(id); selector(z);
					IF sym = becomes THEN
						OPS.Get(sym); Expression(y);
						Resolve(op, ":=", z, y);
						IF op=NIL THEN  OPB.Assign(z, y)  ELSE  OpCall(op, z, y)  END
					ELSE err (1002)
					END
			| FCall:
					qualident(id);
					z := OPB.NewLeaf(id); selector(z);
					IF (z^.class = Nproc) & (z^.obj^.mode = SProc) THEN
						StandProcCall(z);
						IF (z # NIL) & (z^.typ # OPT.notyp) THEN err(55) END
					ELSE OPB.PrepCall(z, fpar);
						IF sym = lparen THEN
							OPS.Get(sym); ActualParameters(apar, fpar); CheckSym(rparen)
						ELSE apar := NIL;
							IF fpar # NIL THEN err(65) END
						END ;
						IF (z.class=Nproc) OR (z.class=Nassembler) THEN
							sysflag := z.obj.sysflag # 0
						ELSE
							sysflag := z.typ.sysflag # 0
						END;
						IF (z^.class = Nproc) & (z^.obj^.mode = CProc) THEN InlineProc (z, apar, fpar)
						ELSE OPB.Call(z, apar, fpar)
						END;
						IF z^.typ # OPT.notyp THEN
							IF ~sysflag THEN err(55) ELSE z.typ := OPT.notyp END
						END;
						IF level > 0 THEN OPT.topScope^.link^.leaf := FALSE END
					END ;
			| FCond:
					Expression (z); CheckBool (z);
					conval := z.conval
			| FParam:
					obj := x.obj;
					Expression (z);  OPB.Param (z, obj);
			| FPassExpr:
					(* sym = AWAIT *)
					OPS.Get (sym); (* sym = "(" *)
					OPS.Get (sym);
					Expression (z); conval := z.conval;
					OPB.StPar0(z, awaitfn);
			| FReturn:
					Expression (z); OPB.Return(z, OPT.topScope^.link)
			END;
			IF z = NIL THEN
				(* construct a NOP node -> ninittd don't generate code !! this is not clean !! *)
				OPB.Construct (Ninittd, z, NIL)
			END;
			x^ := z^; x.link := link; x.conval := conval;
			FixList := FixList.next
		END;
		OPT.topScope := topscope
	END DoFixes;

	PROCEDURE StatSeq(VAR stat: OPT.Node);
		VAR fpar, id, t, obj, owner, op: OPT.Object; typ, idtyp: OPT.Struct; sysflag, e: BOOLEAN;
				x1, x2, s, x, y, z, apar, last, lastif: OPT.Node; pos: LONGINT;
				ts: OPS.TokenStream;

		PROCEDURE CasePart(VAR x: OPT.Node);
			VAR n: INTEGER; low, high: LONGINT; e: BOOLEAN;
					tab: CaseTable; cases, lab, y, lastcase: OPT.Node; 
		BEGIN
			FixPhase := TRUE; Expression(x); FixPhase := FALSE; pos := OPM.errpos;
			IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
			ELSIF ~(x^.typ^.form IN {Char..LInt}) THEN err(125)
			END ;
			CheckSym(of); cases := NIL; lastcase := NIL; n := 0;
			LOOP
				IF sym < bar THEN
					FixPhase := TRUE; CaseLabelList(lab, x^.typ^.form, n, tab); FixPhase := FALSE;
					CheckSym(colon); StatSeq(y);
					OPB.Construct(Ncasedo, lab, y); OPB.Link(cases, lastcase, lab)
				END ;
				IF sym = bar THEN OPS.Get(sym) ELSE EXIT END
			END ;
			IF n > 0 THEN low := tab[0].low; high := tab[n-1].high;
				IF high - low > OPM.MaxCaseRange THEN err(209) END
			ELSE low := 1; high := 0; err (213)
			END ;
			e := sym = else;
			IF e THEN OPS.Get(sym); StatSeq(y) ELSE y := NIL END ;
			OPB.Construct(Ncaselse, cases, y); OPB.Construct(Ncase, x, cases);
			cases^.conval := OPT.NewConst();
			cases^.conval^.intval := low; cases^.conval^.intval2 := high;
			IF e THEN cases^.conval^.setval := {1} ELSE cases^.conval^.setval := {} END
		END CasePart;
		
		PROCEDURE SetPos(x: OPT.Node);
		BEGIN
			x^.conval := OPT.NewConst(); x^.conval^.intval := pos
		END SetPos;

	BEGIN stat := NIL; last := NIL; UndefFlag := FALSE;
		LOOP x := NIL;
			IF sym < ident THEN err(14);
				REPEAT OPS.Get(sym) UNTIL sym >= ident
			END ;
			IF UndefFlag THEN err (1001); UndefFlag := FALSE END;
			IF sym = ident THEN
				OPS.StartRecording (sym);
				qualident(id); x := OPB.NewLeaf(id); selector(x);
				IF sym = becomes THEN
					OPS.Get(sym);
					IF UndefFlag THEN UndefFlag := FALSE; x := NIL;
						Expression (x); OPS.StopRecording (ts);
						IF UndefFlag THEN InsertFix (FAssign, ts, x); UndefFlag := FALSE
						ELSE OPB.Construct (Ntrap(*dummy*), x, NIL); InsertFix (FTarget, ts, x) END
					ELSE OPS.StartRecording (sym); Expression(y); OPS.StopRecording (ts);
						IF UndefFlag THEN InsertFix (FExpr, ts, x); UndefFlag := FALSE
						ELSE
							Resolve(op, ":=", x, y);
							IF op=NIL THEN  OPB.Assign(x, y)  ELSE  OpCall(op, x, y)  END
						END
					END
				ELSIF sym = eql THEN
					err(becomes); OPS.Get(sym); Expression(y); OPB.Assign(x, y)
				ELSIF (x^.class = Nproc) & (x^.obj^.mode = SProc) THEN
					StandProcCall(x);
					OPS.StopRecording (ts);
					IF UndefFlag THEN UndefFlag := FALSE; InsertFix (FCall, ts, x)
					ELSIF (x # NIL) & (x^.typ # OPT.notyp) THEN err(55)
					END;
				ELSE 
					IF ~UndefFlag THEN OPB.PrepCall(x, fpar) END;
					IF sym = lparen THEN
						OPS.Get(sym); ActualParameters(apar, fpar); CheckSym(rparen)
					ELSE apar := NIL;
						IF (fpar # NIL) & ~UndefFlag THEN err(65) END
					END ;
					IF ~UndefFlag THEN 
						IF (x.class=Nproc) OR (x.class=Nassembler) THEN
							sysflag := x.obj.sysflag # 0
						ELSE
							sysflag := x.typ.sysflag # 0
						END;
						IF (x^.class = Nproc) & (x^.obj^.mode = CProc) THEN InlineProc (x, apar, fpar)
						ELSE OPB.Call(x, apar, fpar)
						END;
						IF (x # NIL) & (x^.typ # OPT.notyp) THEN
							IF ~sysflag THEN err(55) ELSE x.typ := OPT.notyp END
						END
					END;
					OPS.StopRecording(ts);
					IF UndefFlag THEN UndefFlag := FALSE; InsertFix (FCall, ts, x) END;
					IF level > 0 THEN OPT.topScope^.link^.leaf := FALSE END
				END ;
				pos := OPM.errpos
			ELSIF sym = if THEN
				OPS.Get(sym);
				OPS.StartRecording (sym); Expression(x); OPS.StopRecording (ts);
				IF UndefFlag THEN InsertFix (FCond, ts, x); s := x; x.class := 0; UndefFlag := FALSE
				ELSE CheckBool(x); s := NIL
				END;
				CheckSym(then); StatSeq(y);
				OPB.Construct(Nif, x, y); SetPos(x); lastif := x;
				WHILE sym = elsif DO
					OPS.Get(sym);
					OPS.StartRecording (sym); Expression(y); OPS.StopRecording (ts);
					IF UndefFlag THEN InsertFix (FCond, ts, y); s := x; x.class := 0; UndefFlag := FALSE
					ELSE CheckBool(y)
					END;
					CheckSym(then); StatSeq(z);
					OPB.Construct(Nif, y, z); SetPos(y); OPB.Link(x, lastif, y);
				END ;
				IF sym = else THEN OPS.Get(sym); StatSeq(y)
				ELSE y := NIL
				END ;
				OPB.Construct(Nifelse, x, y); CheckSym(end);
				IF s = NIL THEN  OPB.OptIf(x)  (*ELSE  s.link := x*)  END; 
				pos := OPM.errpos
			ELSIF sym = case THEN
				OPS.Get(sym); CasePart(x); CheckSym(end)
			ELSIF sym = while THEN
				OPS.Get(sym);
				OPS.StartRecording (sym); Expression(x); OPS.StopRecording (ts);
				IF UndefFlag THEN InsertFix (FCond, ts, x); UndefFlag := FALSE
				ELSE CheckBool(x)
				END;
				CheckSym(do); StatSeq(y); CheckSym(end);
				IF (x.class = Nconst) & (x.conval.intval = 0) THEN
					x := NIL		(* WHILE FALSE -> dead code removal *)
				ELSE
					OPB.Construct(Nwhile, x, y)
				END
			ELSIF sym = repeat THEN
				OPS.Get(sym); StatSeq(x);
				IF sym = until THEN OPS.Get(sym);
					pos := OPM.errpos;
					OPS.StartRecording (sym); Expression(y); OPS.StopRecording (ts);
					IF UndefFlag THEN InsertFix (FCond, ts, y); UndefFlag := FALSE
					ELSE CheckBool(y)
					END
				ELSE err(until)
				END ;
				OPB.Construct(Nrepeat, x, y)
			ELSIF sym = for THEN
				OPS.Get(sym);
				IF sym = ident THEN
					FixPhase := TRUE;
					qualident(id); x := OPB.NewLeaf(id); selector (x);
					OPB.CopyAndSubst (x1, x); OPB.CopyAndSubst (x2, x);
					IF ~(x^.typ^.form IN intSet) THEN err(68) END;
					CheckSym(becomes);
					FixPhase := FALSE; typ := x.typ;
					OPS.StartRecording(sym); Expression(y); OPS.StopRecording (ts);
					pos := OPM.errpos;
					IF UndefFlag THEN
						InsertFix (FExpr, ts, x); UndefFlag := FALSE
					ELSE
						OPB.Assign(x, y)
					END;
					SetPos(x); CheckSym(to); 
					
					OPS.StartRecording(sym); Expression(y); OPS.StopRecording (ts);
					pos := OPM.errpos;
					IF (y^.class # Nconst) OR UndefFlag THEN
						owner := OPT.topScope;
						WHILE (OPT.topScope.left # NIL) & (OPT.topScope.link = OPT.topScope.left.link) DO
							OPT.topScope := OPT.topScope.left
						END;
						OPT.Insert("@@", t); t^.name := "@for"; t^.mode := Var; t^.typ := typ;
						t.flag := {OPT.used};
						obj := OPT.topScope^.scope;
						IF obj = NIL THEN OPT.topScope^.scope := t
						ELSE
							WHILE obj^.link # NIL DO obj := obj^.link END ;
							obj^.link := t
						END ;
						OPT.topScope := owner;
						z := OPB.NewLeaf(t);
						IF UndefFlag THEN
							InsertFix (FExpr, ts, z); UndefFlag := FALSE
						ELSE
							OPB.Assign(z, y);
						END;
						SetPos(z); OPB.Link(stat, last, z);
						y := OPB.NewLeaf(t)
					ELSIF (y^.typ^.form < SInt) OR (y^.typ^.form > typ.form) THEN err(113)
					END ;
					OPB.Link(stat, last, x);
					IF sym = by THEN OPS.Get(sym); ConstExpression(z) ELSE z := OPB.NewIntConst(1) END ;
					pos := OPM.errpos;
					x := x1;				(* use the copy of x *)
					IF z^.conval^.intval > 0 THEN OPB.Op(leq, x, y)
					ELSIF z^.conval^.intval < 0 THEN OPB.Op(geq, x, y)
					ELSE err(63); OPB.Op(geq, x, y)
					END ;
					CheckSym(do); StatSeq(s);
					y := x2;				(* use the copy of x *)
					OPB.StPar1(y, z, incfn); SetPos(y);
					IF s = NIL THEN s := y
					ELSE z := s;
						WHILE z^.link # NIL DO z := z^.link END ;
						z^.link := y
					END ;
					CheckSym(end); OPB.Construct(Nwhile, x, s)
				ELSE err(ident)
				END
			ELSIF sym = loop THEN
				OPS.Get(sym); INC(LoopLevel); StatSeq(x); DEC(LoopLevel);
				OPB.Construct(Nloop, x, NIL); CheckSym(end); pos := OPM.errpos
			ELSIF sym = with THEN
				OPS.Get(sym); idtyp := NIL; x := NIL;
				LOOP
					IF sym = ident THEN
						qualident(id); y := OPB.NewLeaf(id);
						IF (id # NIL) & (id^.typ^.form = Pointer) & ((id^.mode = VarPar) OR ~id^.leaf) THEN
							err(-302)	(* warning 302 *)
						END ;
						CheckSym(colon);
						IF sym = ident THEN qualident(t);
							IF t^.mode = Typ THEN
								IF id # NIL THEN
									idtyp := id^.typ; OPB.TypTest(y, t, FALSE);
									IF id.mnolev < 0 THEN id^.typ := t^.typ
									ELSE
										owner := OPT.topScope^.link; OPT.OpenScope (level, owner);
										OPT.Insert (id.name, obj); obj^.mode := id^.mode; obj^.scope := id;
										obj^.typ := t^.typ
									END
								ELSE err(130)
								END
							ELSE err(52)
							END
						ELSE err(ident)
						END
					ELSE err(ident)
					END ;
					pos := OPM.errpos; CheckSym(do); StatSeq(s); OPB.Construct(Nif, y, s); SetPos(y);
					IF id.mnolev < 0 THEN
						id^.typ := idtyp
					ELSE
						IF idtyp # NIL THEN OPT.CloseScope; owner^.scope := OPT.topScope; idtyp := NIL END ;
					END;
					IF x = NIL THEN x := y; lastif := x ELSE OPB.Link(x, lastif, y) END ;
					IF (sym = bar) & (OPM.oberon2 IN OPM.options) THEN OPS.Get(sym) ELSE EXIT END
				END;
				e := sym = else;
				IF e & (OPM.oberon2 IN OPM.options) THEN OPS.Get(sym); StatSeq(s) ELSE s := NIL END ;
				OPB.Construct(Nwith, x, s); CheckSym(end); 
				IF e THEN x^.subcl := 1 END
			ELSIF sym = exit THEN
				OPS.Get(sym);
				IF LoopLevel = 0 THEN err(38) END ;
				OPB.Construct(Nexit, x, NIL);
				pos := OPM.errpos
			ELSIF sym = return THEN OPS.Get(sym);
				IF sym < semicolon THEN OPS.StartRecording (sym); Expression(x); OPS.StopRecording (ts) END ;
				IF UndefFlag OR (OPT.topScope.link.typ = NIL) THEN InsertFix (FReturn, ts, x); UndefFlag := FALSE
				ELSE
					IF level > 0 THEN OPB.Return(x, OPT.topScope^.link)
					ELSE (* not standard Oberon *) OPB.Return(x, NIL)
					END
				END;
				pos := OPM.errpos
			ELSIF sym = begin THEN OPS.Get(sym);
				StatBlock(x, TRUE)
			END ;
			IF UndefFlag THEN	err (1000); UndefFlag := FALSE	END;
			IF x # NIL THEN SetPos(x); OPB.Link(stat, last, x) END ;
			IF sym = semicolon THEN OPS.Get(sym)
			ELSIF (sym <= ident) OR (if <= sym) & (sym <= return) THEN err(semicolon)
			ELSE EXIT
			END
		END
	END StatSeq;
	
	PROCEDURE StatBlock(VAR statseq: OPT.Node;  local: BOOLEAN);	(* BEGIN [BlockMode] StatSeq END *)
	VAR  lock, oldScopeLock: BOOLEAN; pos: LONGINT; owner: OPT.Object;
	BEGIN
		(* BEGIN already parsed *)
		owner := OPT.topScope.link; pos := OPM.errpos;
		BlockMode(owner.conval.setval, local, lock);
		IF scopeLock & lock THEN  err(246)  END;
		oldScopeLock := scopeLock; scopeLock := scopeLock OR lock;
		StatSeq(statseq); CheckSym(end);
		scopeLock := oldScopeLock;
		IF lock THEN
			OPB.Lock(statseq, GetSelf(), TRUE);
			statseq.conval := OPT.NewConst();
			statseq.conval.intval := pos
		END
	END StatBlock;
	
	PROCEDURE AddTraceCode(owner: OPT.Object;  VAR statseq: OPT.Node);
	VAR  curScope, obj, last: OPT.Object;  x: OPT.Node;  name: OPS.Name;  i, m: SHORTINT;
	BEGIN
		curScope := OPT.topScope;  OPT.topScope := OPT.modules[0];	(*switch to module scope*)
		name := "trace";  i := 0;
		WHILE (i < LEN(name)-6) & (owner.name[i] # 0X) DO
			name[5+i] := owner.name[i]; INC(i)
		END;
		name[5+i] := 0X;
		OPT.Insert(name, obj);  obj.mode := Var;  obj.typ := OPT.linttyp;
		last := OPT.topScope.scope;
		IF last # NIL THEN
			WHILE last.link # NIL DO  last := last.link  END;
			last.link := obj
		ELSE
			OPT.topScope.scope := obj
		END;
		OPT.topScope := curScope;
		m := SHORT(SHORT(inc.adr));
		x := OPB.NewLeaf(obj);
		OPB.StPar0(x, m);
		OPB.StFct(x, m, 1);
		x^.conval := OPT.NewConst(); x^.conval^.intval := OPM.errpos;
		x.link := statseq;  statseq := x
	END AddTraceCode;

	PROCEDURE Block(VAR procdec, statseq: OPT.Node);
		VAR typ: OPT.Struct;
			owner, obj, first, last, dmy: OPT.Object;
			x, lastdec: OPT.Node;
			pos: LONGINT; vars, proc: BOOLEAN;

	BEGIN first := NIL; last := NIL; 
		procdec := NIL; lastdec := NIL; proc := FALSE; vars := FALSE;
		LOOP
			IF (sym = const) THEN
				IF (OPM.oberon1 IN OPM.options) & proc THEN err(262) END;
				OPS.Get(sym);
				WHILE sym = ident DO
					OPT.Insert(OPS.name, obj); CheckMark(obj^.vis, FALSE);
					IF IsObjectScope() & (obj.vis = external) THEN err (47) END;		(* <- prevent export, implementation restriction *)
					obj^.typ := OPT.sinttyp; obj^.mode := Var;	(* Var to avoid recursive definition *)
					IF sym = eql THEN
						OPS.Get(sym); ConstExpression(x)
					ELSIF sym = becomes THEN
						err(eql); OPS.Get(sym); ConstExpression(x)
					ELSE err(eql); x := OPB.NewIntConst(1)
					END ;
					obj^.mode := Con; obj^.typ := x^.typ; obj^.conval := x^.conval; (* ConstDesc ist not copied *)
					CheckSym(semicolon);
					WHILE sym=semicolon DO OPS.Get(sym) END;
				END
			END ;
			IF (sym = type) THEN
				IF (OPM.oberon1 IN OPM.options) & proc THEN err(262) END;
				OPS.Get(sym);
				WHILE sym = ident DO
					OPT.Insert(OPS.name, obj); obj^.mode := Typ; obj^.typ := OPT.undftyp;
					x := NIL;
					CheckMark(obj^.vis, FALSE);
					IF sym = eql THEN
						OPS.Get(sym); TypeDecl(obj^.typ, obj^.typ, obj)
					ELSIF (sym = becomes) OR (sym = colon) THEN
						err(eql); OPS.Get(sym); TypeDecl(obj^.typ, obj^.typ, obj)
					ELSE err(eql)
					END ;
					IF obj.typ = OPT.ToBeFixed THEN		(*incomplete structure, add fixup, hidden*)
						NewFix(ObjFix[nofObjFix], OPS.name);  ObjFix[nofObjFix].obj := obj;  INC(nofObjFix);
						obj.mode := -obj.mode
					ELSE  NewType(obj)
					END;
					IF obj.typ.incomplete THEN  NewCheck(obj)  ELSE  CheckObj(obj);  END;
					IF ((obj^.typ^.comp = Record)OR(obj^.typ^.form = Pointer)&(obj^.typ^.BaseTyp^.comp = Record)) & (sym = ident) THEN
						IF obj^.name # OPS.name THEN err(4)
						END;
						OPS.Get(sym)
					END;
					IF obj^.typ^.strobj = NIL THEN obj^.typ^.strobj := obj END ;
					IF obj^.conval = NIL THEN obj^.conval := OPT.NewConst() END;
					CheckSym(semicolon)
				END;
				IF OPT.topScope.scope#NIL THEN
					first:=OPT.topScope.scope;
					WHILE first^.link#NIL DO first:=first^.link END;
					last:=first; first:=NIL
				END
			END ;
			IF (sym = var) OR (IsObjectScope() & (sym = ident)) THEN
				vars := TRUE;
				IF (OPM.oberon1 IN OPM.options) & proc THEN err(262) END;
				IF sym = var THEN OPS.Get(sym) END;
				WHILE sym = ident DO
					LOOP
						IF sym = ident THEN
							IF ~IsObjectScope() THEN	(* If this is a record field, then check overriding *)
							ELSIF OPT.topScope.link.typ.incomplete THEN
								SetFlags(OPT.topScope.link, {checkOverwriting})
							ELSE
								OPT.FindField(OPS.name, OPT.topScope.link.typ, obj, FALSE);
								IF (obj # NIL) & (obj.mode IN {Fld, TProc}) THEN err(1) END
							END;
							OPT.Insert(OPS.name, obj); CheckMark(obj^.vis, TRUE);
							IF level = 0 THEN
								CheckSysFlag(obj.sysflag, 0, {0, untraced})
							ELSE
								CheckSysFlag(obj.sysflag, 0, {0})
							END;
							IF IsObjectScope() THEN
								obj^.mode := Fld; obj.conval := OPT.NewConst(); obj.conval.intval := OPM.errpos;
								OPT.FindField (obj.name, OPT.topScope.link.typ.BaseTyp, dmy, TRUE);
							ELSE
								obj^.mode := Var; obj^.leaf := obj^.vis = internal
							END;
							obj^.link := NIL; obj^.typ := OPT.undftyp; obj.myscope:=OPT.topScope;
							IF first = NIL THEN first := obj END ;
							IF last = NIL THEN 
								IF IsObjectScope() THEN OPT.topScope^.link^.typ^.link := obj ELSE OPT.topScope^.scope := obj  END
							ELSE last^.link := obj END ;
							last := obj
						ELSE err(ident)
						END ;
						IF sym = comma THEN OPS.Get(sym)
						ELSIF sym = ident THEN err(comma)
						ELSE EXIT
						END
					END ;
					CheckSym(colon); TypeDecl(typ, OPT.notyp, NIL);
					IF IsObjectScope() & (OPT.topScope.link.typ = typ) THEN	err (58)	END;
					OPT.MarkType(typ);
					WHILE first # NIL DO
						first^.typ := typ; 
						IF typ.incomplete THEN	(*hide*)
							IF typ = OPT.ToBeFixed THEN
								NewFix(ObjFix[nofObjFix], OPS.name);  ObjFix[nofObjFix].obj := first;  INC(nofObjFix)
							END;
							NewCheck(first);  first.mode := -first.mode;	(* mark variable *)
						ELSE
							CheckObj(first)
						END;
						first := first^.link
					END ;
					IF ~IsObjectScope() OR (sym # end) THEN CheckSym(semicolon) END;
					WHILE sym=semicolon DO OPS.Get(sym) END;
				END
			END ;
			IF sym = procedure THEN
				proc := TRUE;
				OPS.Get(sym); ProcedureDeclaration(x);
				IF x # NIL THEN
					IF lastdec = NIL THEN procdec := x ELSE lastdec^.link := x END ;
					lastdec := x;
				END ;
				CheckSym(semicolon)
			END;
			IF (sym < const) OR (sym > procedure) THEN EXIT END ;
		END ;	(* LOOP *)
		OPT.topScope^.adr := OPM.errpos;
		IF IsObjectScope() & (last = NIL) THEN
			OPT.topScope^.link^.typ^.link := OPT.topScope^.right
		END;

		CondNodes := NIL; CondCount := 0;
		owner := OPT.topScope.link;
		IF sym = begin THEN
			IF (owner.mode = CProc) & (owner.vis # internal) THEN  err(250)  END;
			IF IsObjectScope() THEN			(* object body, VAR self: TDesc *)
				typ := owner.typ;
				IF typ.ptr = NIL THEN  err(249)  END;
				ASSERT(typ # NIL);
				IF typ.ptr # NIL THEN
					OPT.Insert(HiddenSelf, obj); obj^.mode := Var; obj^.typ := typ.ptr;
				ELSE
					OPT.Insert(HiddenSelf, obj); obj^.mode := VarPar; obj^.typ := typ;
				END;
				obj^.adr := OPM.errpos; obj.mnolev := 1 (*level*);
				obj^.link := NIL;
				owner^.link := obj;	(* set parameter list *)
				IF owner^.typ^.link = NIL THEN owner^.typ^.link := obj END
			END;
			OPS.Get(sym); 
			StatBlock(statseq,  FALSE);
			SetFlags (owner, {hasBody});
			IF (OPM.trace IN OPM.options) & (level = 1) THEN  AddTraceCode(owner, statseq)  END;
			IF (CondNodes # NIL) & ~IsObjectScope() THEN
				IF lastdec = NIL THEN procdec := CondNodes ELSE lastdec^.link := CondNodes END ;
				lastdec := CondNodes
			END;
		ELSIF sym = code THEN 		(* iOPA *)
			IF (owner.mode = CProc) & vars THEN  err(247)  END;
			IF OPM.WarnUnsafe THEN err(-666) END;
			pos := OPM.errpos; SetFlags(owner, {asmProc});
			OPA.Assemble(statseq,  owner.vis # internal, owner.mode = CProc); 
			IF statseq # NIL THEN
				statseq^.conval := OPT.NewConst(); statseq^.conval^.intval := pos;
				statseq.obj := owner
			END;
			OPS.Get(sym)
		ELSE 
			statseq := NIL; CheckSym(end)
		END ;
		IF (level = 0) & (TDinit # NIL) & IsModuleScope() THEN
			lastTDinit^.link := statseq; statseq := TDinit
		END ;
		IF (level = 0) & (RecInit # NIL) & IsModuleScope() THEN
			lastRecInit.link := procdec; procdec := RecInit; RecInit := NIL;
		END ;
	END Block;

	PROCEDURE CreateHiddenStructs;
		VAR obj, fld1, fld2: OPT.Object;
		
		PROCEDURE CreateStruct(IN name: ARRAY OF CHAR; VAR obj: OPT.Object);
		VAR typ: OPT.Struct;
		BEGIN
			typ := OPT.NewStr(Comp, Record);
			typ.BaseTyp := NIL; typ.sysflag := systemtype;
			OPT.Insert(name, obj);
			obj.mode := Typ; obj.typ := typ; obj.vis := internal; typ.strobj := obj; INCL(obj.flag, OPT.used);
			obj.conval := OPT.NewConst()
		END CreateStruct;
		
	BEGIN
		CreateStruct(OPT.Delegate, obj);
		OPT.OpenScope(0, obj);
		OPT.Insert("proc", fld1); fld1.mode := Fld; fld1.typ := OPT.linttyp; obj.typ.link := fld1; INCL(fld1.flag, OPT.used);
		OPT.Insert("self", fld2); fld2.mode := Fld; fld2.typ := OPT.ptrtyp; fld2.link := fld1; INCL(fld2.flag, OPT.used);
		OPT.CloseScope;
		CheckObj(obj);

		CreateStruct(OPT.HdPtrStruct, obj);
		OPT.OpenScope(0, obj);
		OPT.Insert("ptr", fld1); fld1.mode := Fld; fld1.typ := OPT.ptrtyp; obj.typ.link := fld1; INCL(fld1.flag, OPT.used);
		OPT.CloseScope;
		CheckObj(obj);
	END CreateHiddenStructs;

	PROCEDURE FullName(VAR fullname: OPS.Name);
	VAR  i, j: LONGINT;
	BEGIN
		i := 0;
		WHILE OPS.name[i] # 0X DO  fullname[i] := OPS.name[i];  INC(i)  END;
		OPS.Get(sym);
		WHILE (sym = period) DO
			IF (i < LEN(fullname)-1) THEN fullname[i] := "."; INC(i) END;
			OPS.Get(sym);
			IF sym = ident THEN
				j := 0;
				WHILE (OPS.name[j] # 0X) & (i < LEN(fullname)-1) DO
					fullname[i] := OPS.name[j];  INC(i); INC(j)
				END;
				IF OPS.name[j] # 0X THEN err(240)  END;
				OPS.Get(sym)
			ELSE
				err(ident)
			END
		END;
		fullname[i] := 0X
	END FullName;

	PROCEDURE Module*(VAR prog: OPT.Node; VAR modName: OPS.Name);
		VAR shortName, impName, aliasName: OPS.Name;
				procdec, statseq: OPT.Node;
				c: LONGINT;
				mod: OPT.Object;
	BEGIN
		ptrToRec := NIL;
		nofObjFix := 0; nofTypFix := 0; nofCheck := 0;
		UndefObj := OPT.NewObj(); UndefObj^.mode := Var; UndefObj^.typ := OPT.undftyp; UndefObj^.adr := 0;
		FixList := NIL; FixPhase := FALSE; UndefFlag := FALSE;
		FixLast := NIL;
		LoopLevel := 0; level := 0;
		scopeLock := FALSE;
		OPS.Get(sym);
		IF sym = module THEN OPS.Get(sym) ELSE err(16) END ;
		IF sym = ident THEN
			FullName(modName);
			IF OPM.traceprocs IN OPM.options THEN
				OPM.LogWLn; OPM.LogWStr("M "); OPM.LogWStr(OPS.name)
			END;
			shortName := OPS.name;
			OPT.Init(modName);
			mod := OPT.NewObj(); mod.scope := OPT.topScope; OPT.topScope^.link := mod;
			OPT.topScope.conval:=OPT.NewConst();
			mod^.mode := Mod;
			mod^.conval := OPT.NewConst();
			mod^.typ := OPT.notyp;
			INCL(mod^.conval^.setval, protectedObj);	(* module is always protected *)

			ExtObj := OPT.topScope;
			mod^.name := modName;
			CheckSym(semicolon);
			IF sym = import THEN OPS.Get(sym);
				LOOP
					IF sym = ident THEN
						aliasName := OPS.name; impName := aliasName; OPS.Get(sym);
						IF sym = becomes THEN OPS.Get(sym);
							IF sym = ident THEN FullName(impName) ELSE err(ident) END
						ELSIF sym = period THEN  err(200)
						END ;
						IF (OPM.systemchk IN OPM.options) & (impName = "SYSTEM") THEN err(152)
						ELSE
							OPT.Import(aliasName, impName, modName)
						END
					ELSE err(ident)
					END ;
					IF sym = comma THEN OPS.Get(sym)
					ELSIF sym = ident THEN err(comma)
					ELSE EXIT
					END
				END ;
				CheckSym(semicolon)
			END ;
			IF OPM.noerr THEN TDinit := NIL; lastTDinit := NIL; c := OPM.errpos;
				RecInit := NIL; lastRecInit := NIL;
				CreateHiddenStructs;
				Block(procdec, statseq);
				OPB.Enter(procdec, statseq, NIL); prog := procdec;
				prog^.conval := OPT.NewConst(); prog^.conval^.intval := c;
				IF sym = ident THEN
					IF OPS.name # shortName THEN err(4) END ;
					OPS.Get(sym)
				ELSE err(ident)
				END ;
				IF sym # period THEN err(period) END
			END
		ELSE err(ident)
		END ;
		TDinit := NIL; lastTDinit := NIL;
		RecInit := NIL; lastRecInit := NIL;
		IF OPM.noerr THEN DoFixes 
		ELSE
			WHILE nofObjFix > 0 DO  DEC(nofObjFix);  ObjFix[nofObjFix].scope := NIL;  ObjFix[nofObjFix].obj := NIL   END;
			WHILE nofTypFix > 0 DO  DEC(nofTypFix);  TypFix[nofTypFix].scope := NIL;  TypFix[nofTypFix].typ := NIL   END;
			WHILE nofCheck > 0 DO  DEC(nofCheck);  ObjCheck[nofCheck].obj := NIL  END;
		END;
		IF OPM.noerr & (OPM.warning IN OPM.options) THEN OPT.TraverseObjects(OPT.topScope.right) END;
	END Module;

BEGIN
	SignOnMessage := "Oberon Parser (Active & X Extensions) / prk";
	OPS.name := "INC"; OPT.Find(inc)
END OPP.
