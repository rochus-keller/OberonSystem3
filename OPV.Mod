(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

(* OPV - parse tree traverser (back end) *)
(* NM, MH, rml, prk  *)


MODULE OPV;	(** non-portable *)
	IMPORT OPS, OPT, OPL, OPO, OPC, OPM, Oberon, SYSTEM;


	CONST
		(* intermediate code output *)
		InitOPI = "OPI.Init";
		DumpCode = "OPI.DumpCode";

		(* object modes *)
		Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7;
		SProc = 8; CProc = 9; IProc = 10; Mod = 11; Head = 12; TProc = 13;
		
		(* item mode *)
		Abs = OPO.Abs;

		(* symbol values and ops *)
		times = 1; slash = 2; div = 3; mod = 4;
		and = 5; plus = 6; minus = 7; or = 8; eql = 9;
		neq = 10; lss = 11; leq = 12; gtr = 13; geq = 14;
		in = 15; is = 16; ash = 17; msk = 18; len = 19;
		conv = 20; abs = 21; cap = 22; odd = 23; not = 33;

		(*SYSTEM*)
		adr = 24; cc = 25; bit = 26; lsh = 27; rot = 28; val = 29;
		get8 = 30; get16 = 31; get32 = 32; type = 34;

		(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
		
		(* composite structure forms *)
		Basic = 1; StaticArr = 2; SDynArr = 3; DynArr = 4; OpenArr = 5; Record = 6;
		ArraySet = {StaticArr, SDynArr, DynArr, OpenArr};
		
		(* Arrays extlev *)
		static = 0; dynamic = 1; sdynamic = 2;

		(* nodes classes *)
		Nvar = 0; Nvarpar = 1; Nfield = 2; Nderef = 3; Nindex = 4; Nguard = 5; Neguard = 6;
		Nconst = 7; Ntype = 8; Nproc = 9; Nupto = 10; Nmop = 11; Ndop = 12; Ncall = 13;
		Ninittd = 14; Nif = 15; Ncaselse = 16; Ncasedo = 17; Nenter = 18; Nassign = 19;
		Nifelse =20; Ncase = 21; Nwhile = 22; Nrepeat = 23; Nloop = 24; Nexit = 25;
		Nreturn = 26; Nwith = 27; Ntrap = 28; Nassembler = 29;
		Nret = 32;

(*
   Syntax Tree  (in construction)
   
   class     left      right     link       typ        obj
   -------------------------------------------------------------
Designators
   Nproc     -         -         -          ret_type   proc
   Nfield    design    -         -          fld type   field(/meth)
Expressions
   Nmop
      val    expr      -         -          cast_type  -
Statements
   Ncall     procedure a_pars    next       ret_type   f_pars  1)


   a_pars = actual parameters
   f_pars = formal parameters
   
   1) if TProc, the first par is self
*)

		(*function number*)
		assign = 0; newfn = 1; incfn = 13; decfn = 14;
		inclfn = 15; exclfn = 16; copyfn = 18; assertfn = 32;
		awaitfn = 64; lockfn = 66;

		(*SYSTEM function number*)
		getfn = 24; putfn = 25; getrfn = 26; putrfn = 27; sysnewfn = 30; movefn = 31;
		stifn = 33; clifn = 34; poutfn = 35; pinfn = 36;						(* New Functions *)

		(* module visibility of objects *)
		internal = 0; external = 1; externalR = 2;

		(* procedure flags (conval^.setval) *)
		hasBody = 1; isRedef = 2; slNeeded = 3; asmProc = 7;


		(* sysflag *) (* ejz *)
		notag = 1; winapi = 2; cdecl = 3; delegate = 5;
		systemtype = 6;	(*implicitly generated type for arr of ptrs, allocate only when used*)


		MaxAdr 	= OPM.MaxLInt;
		MinAdr 	= OPM.MinLInt;
		VarParSize 	= OPM.PointerSize;
		RecVarParSize 	= 8; 	(* push ADR (rec); push TAG (reg) *)
		LProcOffSL 	= 12; 	(* parameter offset with static link *)
		LProcOff 	= 8; 	(* parameter offset without static link *)
		ExtProcOff 	= 8; 	(* parameter offset of external procedures *)

	TYPE
		ParamAdrProc = PROCEDURE (VAR firstPar: OPT.Object; VAR psize, dsize: LONGINT; TProc, Inline, allocDesc: BOOLEAN);
		
	VAR
		dumpCode*: BOOLEAN; (* set by OP2 *)
		ProcName*: OPS.Name; (* accessed by OPI (read only) *)
		EntryNr*: INTEGER; (* accessed by OPI (read only) *)
		ExitChain: OPC.Label;
		allocTd, assert, findpc: BOOLEAN; 	(* allocTd used only by OM *)
		dummy: OPC.Item;
		ParamAdr: ARRAY 6 OF  ParamAdrProc;
	
	PROCEDURE Init* (opt: SET; bpc: LONGINT);
		CONST ass = 6; fpc = 7;
		VAR res: INTEGER;
	BEGIN
		assert := ass IN opt; findpc := fpc IN opt;
		allocTd := TRUE;			(* allocTd used only by OM *)
		IF findpc THEN OPM.breakpc := bpc ELSE OPM.breakpc := MAX(LONGINT) END;
		IF dumpCode THEN Oberon.Call (InitOPI, Oberon.Par, FALSE, res) END
	END Init;

	PROCEDURE IncAdr(VAR adr: LONGINT; s: LONGINT);
	BEGIN
		IF (s >= 0) & (adr <= MaxAdr - s) OR (s < 0) & (adr >= MinAdr - s) THEN INC(adr, s)
		ELSE OPM.err(242)
		END
	END IncAdr;
	
	PROCEDURE AlignFld(VAR offset: LONGINT; elemsize: LONGINT);
	(* offset is initialized to base type size, 0 if none *)
	BEGIN
		IF elemsize >= 4 THEN IncAdr(offset, (-offset) MOD 4)
		ELSIF elemsize = 2 THEN IncAdr(offset, offset MOD 2)
		END
	END AlignFld;
	
	PROCEDURE AllocFld(VAR offset, this: LONGINT; elemsize: LONGINT);
	BEGIN
		this := offset; IncAdr(offset, elemsize)
	END AllocFld;
	
	PROCEDURE AlignRec(VAR size: LONGINT);
	BEGIN 
		IncAdr(size, (-size) MOD 4)
	END AlignRec;
	
	PROCEDURE AlignPar(VAR elemsize: LONGINT);
	BEGIN 
		IncAdr(elemsize, (-elemsize) MOD 4)
	END AlignPar;
	
	PROCEDURE AllocPar (VAR adr, this: LONGINT; elemsize: LONGINT);
	BEGIN
		IncAdr(adr, elemsize); this := adr
	END AllocPar;

	PROCEDURE AlignVar(VAR adr: LONGINT; elemsize: LONGINT);
	BEGIN
		IF elemsize >= 4 THEN IncAdr(adr, - (adr MOD 4))
		ELSIF elemsize = 2 THEN IncAdr(adr, - (adr MOD 2))
		END
	END AlignVar;
	
	PROCEDURE AllocVar(VAR adr, this: LONGINT; elemsize: LONGINT);
	BEGIN
		IncAdr(adr, -elemsize); this := adr
	END AllocVar;
	
	PROCEDURE AlignBlock(adr: LONGINT; VAR dsize: LONGINT);
	BEGIN 
		IncAdr(adr, - (adr MOD 4)); dsize := -adr
	END AlignBlock;

	PROCEDURE RecursionTest (typ: OPT.Struct; mode: LONGINT): BOOLEAN;
		VAR p: OPT.Object;
	BEGIN
		IF typ # NIL THEN
			IF typ.rectest < 0 THEN RETURN FALSE
			ELSIF (typ.rectest < mode) OR (typ.rectest > 5) THEN
				(* traverse btyp *)
				IF (typ.form = Comp) THEN
					typ.rectest := -typ.rectest;
					IF ~RecursionTest (typ.BaseTyp, mode) THEN RETURN FALSE END;
					IF typ.comp = Record THEN
						p := typ.link;
						WHILE (p # NIL) & (p.mode = Fld) DO 
							IF ~RecursionTest (p.typ, 2) THEN OPM.errpos := p.conval.intval; OPM.err(58); p.typ := OPT.undftyp END;
							p := p.link
						END
					END
				END
			END;
			typ.rectest := mode
		END; 
		RETURN TRUE
	END RecursionTest;

	PROCEDURE TypSize* (typ: OPT.Struct; allocDesc: BOOLEAN);
		VAR f, c: INTEGER; offset, size, dummy: LONGINT;
			fld: OPT.Object; btyp, ftyp: OPT.Struct; sizeUndef, doAlloc: BOOLEAN;		(* ftyp, OM only *)
			BEGIN
		IF typ = OPT.undftyp THEN OPM.err(58)		(* MH 26.1.94; bug fix RC 17.6.93 *)
		ELSE
			sizeUndef := typ^.size = -1;
			IF ~RecursionTest (typ, 1) THEN OPM.errpos := typ.txtpos; OPM.err(58); typ.BaseTyp := OPT.undftyp END;
			doAlloc := allocDesc & (typ^.tdadr = OPM.TDAdrUndef) & (typ^.offset = OPM.TDAdrUndef) & (typ.sysflag # systemtype);
			IF sizeUndef OR doAlloc THEN
				IF doAlloc THEN typ^.tdadr := -2 (* avoid cycles *) END ;
				f := typ^.form; c := typ^.comp; btyp := typ^.BaseTyp;
				IF c = Record THEN
					IF btyp = NIL THEN offset := 0;
					ELSE TypSize(btyp, allocDesc); offset := btyp^.size;
					END ;
					fld := typ^.link;
					WHILE (fld # NIL) DO
						IF fld^.mode = Fld THEN
							ftyp := fld^.typ; TypSize(ftyp, allocDesc);
							IF sizeUndef THEN size := ftyp^.size;
								WHILE (ftyp^.comp = StaticArr) DO ftyp := ftyp^.BaseTyp END ;
								AlignFld(offset, ftyp^.size);
								AllocFld(offset, fld^.adr, size)
							END
						END;
						fld := fld^.link
					END ;
					IF sizeUndef THEN AlignRec(offset); typ^.size := offset END ;
					IF (doAlloc) & (typ.mno <= 0) THEN
						IF allocTd THEN OPL.AllocTypDesc (typ) END; (* typ.tdadr = Entry number *)
						Traverse(typ^.link, TRUE);
						Traverse(typ^.link, FALSE)	(* !!! *)
					END;
					IF btyp = NIL THEN typ^.n := 0 ELSE typ^.n := btyp^.n END ;
					IF (typ^.strobj # NIL) & (hasBody IN typ^.strobj^.conval^.setval) THEN VisitTProcs(typ^.strobj) END;
					VisitTProcs(typ^.link);
				ELSIF c IN ArraySet THEN
					TypSize(btyp, allocDesc);
					IF sizeUndef THEN
						CASE c OF
						|  StaticArr:	typ.size := typ.n * btyp.size
						|  SDynArr:	typ.size := OPM.PointerSize
						|  OpenArr:	typ.size := (typ.n+1)*OPM.LIntSize+OPM.PointerSize	(*dims + pointer to data (descriptor) *)
						|  DynArr:	typ.size := OPM.PointerSize
						END
					END;
					IF btyp.comp IN ArraySet THEN  typ.offset := btyp.offset+OPM.LIntSize  ELSE  typ.offset := OPM.LIntSize  END
				ELSIF f = Pointer THEN
					typ^.size := OPM.PointerSize;
					IF doAlloc THEN  TypSize(btyp, allocDesc)  END
				ELSIF f = ProcTyp THEN
					IF typ.sysflag = delegate THEN
						typ^.size := OPM.ProcSize + OPM.PointerSize
					ELSE
						typ^.size := OPM.ProcSize
					END;
					IF doAlloc THEN TypSize(btyp, TRUE); size := ExtProcOff;
					END;
					ParamAdr[typ.sysflag](typ^.link, size, dummy, FALSE, FALSE, allocDesc)
				ELSE HALT(99)
				END
			END
		END
	END TypSize;

	PROCEDURE ParamAdrLR(VAR firstPar: OPT.Object; VAR psize, dsize: LONGINT; TProc, Inline, allocDesc: BOOLEAN);
		VAR par: OPT.Object; typ: OPT.Struct; adr, s: LONGINT;
	BEGIN 
		adr := 0;
		IF TProc THEN par := firstPar.link ELSE par := firstPar END;		(* guarantee that self is always the last parameter *)
		(*par := firstPar;*)
		WHILE par # NIL DO
			typ := par^.typ; TypSize(typ, allocDesc);
			IF (par.mode = VarPar) THEN
				IF (typ.comp = Record) THEN s:= RecVarParSize;
					IF typ.sysflag = notag THEN DEC(s, 4) END
				ELSIF (typ.comp = OpenArr) THEN s:= typ.size
				ELSE s:= VarParSize
				END
			ELSE s:= typ.size
			END;
			AlignPar(s);
			AllocPar(adr, par^.adr, s); 
			par := par.link
		END;
		IF TProc THEN
			TypSize(firstPar.typ, TRUE);
			IF firstPar.mode = VarPar THEN s:= RecVarParSize ELSE s := firstPar.typ.size END;
			AlignPar(s); AllocPar(adr, firstPar^.adr, s)
		END;
		psize := psize + adr;
		par := firstPar;
		IF ~Inline THEN
			WHILE par # NIL DO
				par^.adr := psize - par^.adr;
				par^.linkadr:= par.adr;
				par := par.link;
			END
		END
	END ParamAdrLR;

	PROCEDURE ParamAdrRL(VAR firstPar: OPT.Object; VAR psize, dsize: LONGINT; TProc, Inline, allocDesc: BOOLEAN);
		VAR par, parOld: OPT.Object; typ: OPT.Struct; adr, s: LONGINT; stop: BOOLEAN;
	BEGIN
		ASSERT(~Inline);
		adr := 0; 
		par := firstPar;
		IF par # NIL THEN
			stop := FALSE;
			WHILE par.link # NIL DO par := par.link END;
			WHILE ~stop DO
				stop := par = firstPar;
				typ := par^.typ; TypSize(typ, allocDesc (* TRUE *));
				IF typ.comp = OpenArr THEN s:= typ.size;
					IF typ.sysflag = notag THEN s := 4 (*DEC(s, 4)*) END;
				ELSIF (par.mode = VarPar) OR ((typ.size > 4) & (typ.form # LReal)) THEN 
						(* ValPar (RECORD), size > 4 are equal to VarPar *)
					IF (typ.comp = Record) & (par.mode = VarPar) THEN s:= RecVarParSize;
					IF typ.sysflag = notag THEN DEC(s, 4) END;
					ELSE s:= VarParSize
					END
				ELSE s:= typ.size
				END;
				AlignPar(s);
				AllocPar(adr, par^.adr, s); 
				parOld := par;
				par := firstPar;
				WHILE ~stop & (par.link # parOld) DO par := par.link END
			END
		END ;
		psize := psize + adr;
		par := firstPar;
		IF par # NIL THEN
			stop := FALSE;
			WHILE par.link # NIL DO par := par.link END;
			WHILE ~stop DO
				stop := par = firstPar;
				par^.adr := psize - par^.adr;
				IF (par^.mode = Var) & (par^.typ.comp IN {StaticArr, Record}) THEN
					(* Value parameter of type ARRAY or RECORD will be copied by the callee *)
					dsize:= dsize + par^.typ^.size;
					par^.linkadr:= -dsize
				ELSE par^.linkadr:= par.adr
				END;
				parOld := par;
				par := firstPar;
				WHILE ~stop & (par.link # parOld) DO par := par.link END
			END
		END
	END ParamAdrRL;
	
	PROCEDURE VarAdr(var: OPT.Object; VAR dsize: LONGINT);
		VAR adr, s: LONGINT; list: OPT.Object;	(* used by the inline feature *)
	BEGIN 
		adr := -dsize; list := var;
		WHILE var # NIL DO
			IF (var.link2 = NIL) & (var.vis = internal) THEN
				TypSize(var^.typ, TRUE); s := var^.typ^.size;
				AlignVar(adr, s);
				AllocVar(adr, var^.linkadr, s);
				var.adr := 0
			END;
			var := var^.link
		END ;
		AlignBlock(adr, dsize);
		WHILE list # NIL DO			(* process inline parameters *)
			IF list^.link2 # NIL THEN
				list^.linkadr := list^.link2^.adr + dsize
			END;
			list := list^.link
		END
	END VarAdr;

	PROCEDURE ArgSize (par: OPT.Object): LONGINT;
		VAR
			size: LONGINT; comp: SHORTINT; typ: OPT.Struct;
	BEGIN
		size:= 0;
		WHILE par # NIL DO
			typ:= par.typ; comp:= typ.comp;
			IF (comp=OpenArr) THEN INC (size, typ.size)
			ELSIF par.mode = VarPar THEN
				IF comp = Record THEN INC (size, 8)
				ELSE INC (size, 4)
				END
			ELSIF par.typ.form = LReal THEN INC (size, 8)
			ELSIF comp IN {StaticArr, DynArr, Record} THEN INC(size, typ.size); AlignPar(size)
			ELSE INC (size, 4)
			END;
			par:= par.link
		END;
		AlignPar (size);
		RETURN size
	END ArgSize;
	
	PROCEDURE ProcSize0(obj: OPT.Object; firstpass: BOOLEAN);
		VAR psize, oldPos, entryNr: LONGINT;
	BEGIN
		ASSERT (obj.prio # 127);
		oldPos := OPM.errpos;
		IF obj.scope # NIL THEN  OPM.errpos := obj^.scope^.adr;
		ELSE OPM.errpos := 0
		END;
		TypSize(obj.typ, TRUE);
		IF ((obj^.vis # internal) = firstpass) OR (obj^.mode IN {TProc, Typ}) THEN
			IF (obj^.mode = LProc) OR ((obj^.mode = XProc) & (obj^.mnolev >= 0) & (slNeeded IN obj^.conval^.setval)) THEN
				IF slNeeded IN obj^.conval^.setval THEN psize := LProcOffSL ELSE psize := LProcOff END ;
				obj^.adr := 0
			ELSE psize := ExtProcOff
			END ;
			IF ~(obj^.mode IN {LProc, CProc, TProc}) THEN 
				OPL.NewEntry (entryNr); INC (obj.adr, entryNr)
			END;
			TypSize(obj^.typ, TRUE);
			ParamAdr[obj.sysflag](obj^.link, psize, obj^.conval^.intval2, obj^.mode IN {TProc}, obj^.mode = CProc, TRUE);
			obj^.conval^.intval := psize;
			obj^.linkadr := OPM.LANotAlloc;
		END ;
		IF ~firstpass & (obj^.mode # TProc) THEN	(* mfix *)
			IF ~(hasBody IN obj^.conval^.setval) THEN OPM.err(129) END ;
			VarAdr(obj^.scope^.scope, obj^.conval^.intval2);	(* local variables *)
			Traverse(obj^.scope^.right, FALSE)
		END;
		OPM.errpos := oldPos
	END ProcSize0;

	PROCEDURE ProcSize(obj: OPT.Object; firstpass: BOOLEAN);
	BEGIN
		IF obj.prio = 127 THEN
			obj := obj.link2;
			WHILE obj # NIL DO ProcSize0 (obj, firstpass); obj := obj.left END
		ELSE ProcSize0 (obj, firstpass)
		END
	END ProcSize;
	
	PROCEDURE FindMth(curmod: SHORTINT; VAR name: OPS.Name; typ: OPT.Struct; VAR res: OPT.Object);	(*has a semantic different from OPT.FindField: the viewpoint is not (always) the current module*)
		VAR obj: OPT.Object;
	BEGIN res:=NIL;
		WHILE ((typ # NIL) & (typ # OPT.ToBeFixed) & (typ # OPT.undftyp)) & (res=NIL) DO obj := typ^.link;
			WHILE obj # NIL DO
				IF name < obj^.name THEN obj := obj^.left
				ELSIF name > obj^.name THEN obj := obj^.right
				ELSE INCL(obj.flag, OPT.used); res := obj; obj:=NIL
				END
			END ;
			IF (res # NIL) & (res.mode = TProc) & (res.mnolev # curmod) & (res.vis = 0(*internal*)) THEN  res := NIL END;
			IF res=NIL THEN typ := typ^.BaseTyp END
		END
	END FindMth;

PROCEDURE TypeName(t: OPT.Struct);
BEGIN
	IF t.strobj.name # "" THEN
		OPM.LogWStr(t.strobj.name)
	ELSIF t.ptr # NIL THEN
		OPM.LogWStr(t.ptr.strobj.name)
	ELSE
		OPM.LogWStr("<!!!>")
	END
END TypeName;

	PROCEDURE VisitTProcs(obj: OPT.Object);	(* TProcs of base type already visited *)
		VAR typ, t: OPT.Struct; redef: OPT.Object;
	BEGIN
		IF obj # NIL THEN
			IF obj^.mode # Typ THEN VisitTProcs(obj^.left) END;
			IF obj^.mode IN {TProc, Typ} THEN
				typ := obj^.link^.typ;	(* <- type of self *)
				IF typ^.form = Pointer THEN typ := typ^.BaseTyp END ;
				redef := NIL;
				IF obj^.mode = Typ THEN	(* Body Method *)
					t := typ.BaseTyp;
					WHILE (t # NIL) & ~(hasBody IN t.strobj.conval.setval) DO t := t.BaseTyp END;
					IF t # NIL THEN redef := t.strobj END
				ELSIF typ^.BaseTyp # NIL THEN	(* Normal Method *)
					FindMth(-typ.mno, obj.name, typ.BaseTyp, redef);
					IF (redef # NIL) & (redef.mode # TProc) THEN redef := NIL END
				END;
				IF redef # NIL THEN
					obj^.adr := 10000H*(redef^.adr DIV 10000H) (*mthno*) + (obj^.adr MOD 10000H) (*entno*);
				ELSE 
					obj.adr := (obj.adr MOD 10000H) + 10000H*typ.n; INC(typ^.n);
				END;
			END;
			IF obj^.mode # Typ THEN VisitTProcs(obj^.right) END;
		END
	END VisitTProcs;

	PROCEDURE Traverse(obj: OPT.Object; exported: BOOLEAN);
	BEGIN
		IF obj # NIL THEN
			Traverse(obj^.left, exported);
			IF (obj^.mode = Typ) & ((obj^.vis # internal) = exported) THEN TypSize(obj^.typ, TRUE);
				IF (obj.typ.comp = Record) & (obj.typ.tdadr <= -1) & (obj.typ.sysflag # systemtype) THEN OPL.AllocTypDesc(obj.typ) END;	(* mfix *)
			ELSIF obj^.mode IN {LProc, XProc, TProc, CProc, IProc} THEN ProcSize(obj, exported)
			END ;
			Traverse(obj^.right, exported);
		END
	END Traverse;

	PROCEDURE AssignTent (obj: OPT.Object);	(* mfix *)
		VAR typ: OPT.Struct;
		
		PROCEDURE AssignBody(body: OPT.Object);
			VAR entryNr: LONGINT;
		BEGIN
			IF (body # NIL) & (body.conval # NIL) & (hasBody IN body^.conval^.setval) & (body.adr MOD 10000H = 0) THEN
				body^.conval^.intval2 := 0; body^.conval^.intval := LProcOff;
				ParamAdr[body.sysflag](body^.link, body^.conval^.intval, body^.conval^.intval2, TRUE, FALSE, FALSE);
				OPL.NewEntry(entryNr); INC(body.adr, entryNr)
			END
		END AssignBody;

		PROCEDURE EnumTprocs(fld: OPT.Object);
			VAR entryNr: LONGINT;
		BEGIN
			IF fld # NIL THEN
				EnumTprocs(fld.left);
				IF (fld.mode = TProc) THEN
					IF fld.adr MOD 10000H = 0 THEN 
						IF ~(hasBody IN fld^.conval^.setval) THEN OPM.err(129) END;
						VarAdr(fld^.scope^.scope, fld^.conval^.intval2);	(* local variables *)
						Traverse(fld^.scope^.right, FALSE);
						OPL.NewEntry(entryNr); INC(fld.adr, entryNr)
					END;
				END;
				EnumTprocs(fld.right);
			END
		END EnumTprocs;

	BEGIN
		IF obj # NIL THEN
			AssignTent (obj.left);
			IF obj.history = 3 THEN
				obj.mode := 0
			END;
			typ:=obj.typ;
			IF (obj.mode = Var) THEN 	(*anonymous type*)
				IF (typ.form=Pointer)&(typ.strobj=NIL)&(typ.BaseTyp.comp=Record)&(typ.BaseTyp.ptr=typ) THEN
					typ:=typ.BaseTyp;
					AssignBody(typ.strobj); EnumTprocs(typ.link)
				ELSIF (typ.comp=Record)&(typ.strobj.name="") THEN
					AssignBody(typ.strobj); EnumTprocs(typ.link)
				END
			ELSIF (obj.mode = Typ) & (typ.mno = 0) & (typ.strobj=obj) THEN
				IF (typ.form=Pointer)&(typ.BaseTyp.comp=Record)&(typ.BaseTyp.ptr=typ) THEN
					typ:=typ.BaseTyp;
					AssignBody(typ.strobj); EnumTprocs(typ.link)
				ELSIF (typ.comp=Record) THEN
					AssignBody(typ.strobj); EnumTprocs(typ.link)
				END
			ELSIF (obj.mode IN {XProc, LProc}) THEN
				AssignTent(obj.scope.right)
			END;
			AssignTent (obj.right);
		END
	END AssignTent;

	PROCEDURE AssignEntries*(obj: OPT.Object; browse: BOOLEAN);	(*assign entry numbers of imported objects*)
		VAR adr, nofEntries, nofRecs: LONGINT; typ: OPT.Struct; 
	BEGIN
		allocTd := FALSE;
		adr := 0; nofEntries := 1;  nofRecs := -4;
		WHILE obj # NIL DO
			IF obj.mode = Var THEN
				typ := obj.typ;
				TypSize(typ, TRUE);
				IF browse THEN AlignVar(adr, typ.size); AllocVar(adr, obj.linkadr, typ.size); obj.adr := adr END;
			ELSIF obj.mode=XProc THEN
				obj.adr:=nofEntries; INC(nofEntries);
				IF obj.conval = NIL THEN obj.conval := OPT.NewConst() END;
				obj.linkadr:=OPM.LANotAlloc;
				obj.conval.intval:=-1;
				ParamAdr[obj.sysflag](obj^.link, obj.conval.intval, obj.conval.intval2, FALSE, FALSE, TRUE);
			ELSIF obj.mode = Typ THEN
				typ := obj.typ;
				obj.linkadr:=OPM.LANotAlloc;
				TypSize(typ, TRUE);
				IF typ.comp=Record THEN typ.tdadr:=OPM.TDAdrUndef;
					IF browse THEN typ.tdadr:=nofRecs; DEC(nofRecs, 4) END 
				END
			END;
			obj:=obj.nxtobj;
		END;
		allocTd := TRUE
	END AssignEntries;
	
	PROCEDURE AssignOwnEntries(obj: OPT.Object);
	VAR size: LONGINT;
	BEGIN
		allocTd := FALSE;
		WHILE obj # NIL DO
			IF (obj.mode = Var) THEN
				TypSize(obj.typ, TRUE); size := obj.typ.size;
				AlignVar(OPO.dsize, size);
				AllocVar(OPO.dsize, obj.linkadr, size);
				obj.adr := 0
			ELSIF obj.mode = XProc THEN ProcSize(obj, TRUE)
			ELSIF (obj.mode = Typ) & (obj.typ.comp = Record) THEN
				IF (obj.typ.tdadr <= 0) THEN
					TypSize(obj.typ, TRUE);
					IF (obj.typ.sysflag # systemtype) THEN OPL.AllocTypDesc(obj.typ) END
				END;
			END;
			obj:=obj.nxtobj
		END;
		allocTd := TRUE
	END AssignOwnEntries;
	
	PROCEDURE AllocAddEntries(obj: OPT.Object);
	VAR typ: OPT.Struct; 
	BEGIN
		WHILE obj # NIL DO
			typ := obj.typ;
			IF (obj.mode = Typ) & obj.used THEN
				IF (typ.comp = Record) & (typ.tdadr <= 0) THEN
					OPL.AllocTypDesc(obj.typ)
				ELSIF (obj.typ.form = Pointer) & (typ.BaseTyp.tdadr <= 0) & (typ.sysflag # systemtype) THEN
					OPL.AllocTypDesc(obj.typ.BaseTyp)
				END
			END;
			obj := obj.nxtobj
		END
	END AllocAddEntries;

	PROCEDURE AdrAndSize* (topScope: OPT.Object);
	VAR i: INTEGER; dsize: LONGINT;
	BEGIN
		OPM.errpos := topScope^.adr;	(* text position of scope used if error *)
		OPO.dsize := 0;
		i := 1;
		WHILE i < OPT.nofmod DO
			AssignEntries(OPT.modules[i].publics, FALSE);
			INC(i)
		END;
		AssignOwnEntries(OPT.objects);
		Traverse(topScope^.right, FALSE);	(* second pass *)
		AssignTent(topScope^.right);	(* mfix *)

		dsize := -OPO.dsize;
		VarAdr(topScope^.scope, dsize);	(* global variables *)
		OPO.dsize := dsize;
		i := 1; WHILE i < OPT.nofmod DO AllocAddEntries(OPT.modules[i].publics); INC(i) END
	END AdrAndSize;


	PROCEDURE Designator (n: OPT.Node; VAR x: OPC.Item);
		VAR
			obj: OPT.Object; 
			y: OPC.Item;
			index: LONGINT;
			varRec: BOOLEAN;
	BEGIN
		CASE n.class OF
			Nvar, Nvarpar:
				obj := n.obj; 
				WHILE obj.scope # NIL DO obj := obj.scope; n.obj := obj END;	(* WITH-bug fix *)
				x.node := n; x.mnolev := obj.mnolev; x.scale := OPO.noScale; x.inx := OPL.none;
				IF obj.mnolev <= 0 THEN (* global or imported variable *)
					x.mode := Abs;
					IF obj.mnolev < 0 THEN (* imported variable *)
						IF obj.adr DIV 10000H = 0 THEN (* no VarConsLink index yet *)
							OPL.NewVarCons (-obj.mnolev, SHORT (obj.adr), index);
							obj.adr := index * 10000H + obj.adr;	(* index entry *)
						END;
						x.adr := 0
					ELSE x.adr := obj.linkadr
					END
				ELSE (* Var, VarPar *)
					x.mode := obj.mode; x.adr := obj.linkadr
				END;
				x.offs := 0; x.descReg := OPL.none
		  | Nfield:
				Designator (n.left, x);
				IF (n.obj.mode = TProc) THEN
					OPC.Method(x, n.obj); RETURN	(*skip x.typ reassignment*)
				ELSE
					OPC.Field (x, n.obj.adr)
				END
		  | Nderef:
				Designator (n.left, x); 
				OPC.DeRef (x);
		  | Nindex:
				Expression (n.right, y, NIL); Designator (n.left, x); OPC.Index (x, y)
		  | Nguard:
				varRec := (n.left.class = Nvarpar) & (n.left.typ.comp = Record);
				Designator (n.left, x);
				OPC.TypeTest (x, n.typ, TRUE, FALSE, varRec)
		  | Neguard:
				varRec := (n.left.class = Nvarpar) & (n.left.typ.comp = Record);
				Designator (n.left, x);
				OPC.TypeTest (x, n.typ, TRUE, TRUE, varRec)
		  | Nproc:
				IF (n.obj.mode IN {XProc, TProc}) & (n.obj.conval.intval = -1) THEN
					n.obj.conval.intval := ArgSize (n.obj.link) + (* 4 *) 8
				END;
				IF OPM.traceprocs IN OPM.options THEN
					obj := n.obj;
					OPM.LogWLn;
					CASE obj.mode OF
						XProc:
							OPM.LogWStr("CX ");
							IF obj.mnolev < 0 THEN
								OPM.LogWStr(OPT.modules[-obj.mnolev].name); OPM.LogW("/")
							END;
						|SProc:
							OPM.LogWStr("CS "); OPM.LogWNum(obj.adr, 1)
						ELSE
							OPM.LogWStr("C? ");
							IF obj.scope # NIL THEN
								ASSERT(obj.scope.mode = Head);
								IF obj.scope.left # NIL THEN
									ASSERT(obj.scope.left.mode = Head);
									IF obj.scope.left.link # NIL THEN
										OPM.LogWStr(obj.scope.left.link.name);
										OPM.LogW("/")
									END
								END
							END
					END;
					OPM.LogWStr(obj.name)
				END;
				OPC.Procedure (x, n)
		END;
		x.typ := n.typ
	END Designator;

	PROCEDURE CallLR(proc: OPT.Node; VAR res: OPC.Item; assignment: BOOLEAN);
	VAR	 firstap, ap: OPT.Node; firstfp, fp: OPT.Object; x, dynptr, tos: OPC.Item; s, dynblocks, staticsize: LONGINT; tproc: BOOLEAN;
	
		PROCEDURE AllocTempSpace(VAR dynblocks, staticsize: LONGINT; ap: OPT.Node; fp: OPT.Object);	(*traverse in reverse order!*)
		VAR tos: OPC.Item;
		BEGIN
			IF ap # NIL THEN
				AllocTempSpace(dynblocks, staticsize, ap.link, fp.link);
				IF (ap.class = Ncall) & (ap.typ.form=Comp) THEN
					IF ap.typ.comp IN {OpenArr, SDynArr} THEN	(*dynamic*)
						OPC.AllocateStatic(tos, ap.typ.n*4+8);	(*get tos, allocate space for the len and adrptr*)
						INC(tos.offs, ap.typ.n*4+8); tos.typ := OPT.linttyp (*ap.typ*);
						Call(ap, tos, FALSE);	(*the procedure allocates the space when the array is copied back!*)
						INC(dynblocks)
					ELSIF (*(ap.typ.comp=StaticArr)&*)(fp.typ.comp=OpenArr) OR (fp.mode = VarPar) THEN	(*static, indirect*)
						INC(staticsize, ap.typ.size + (-ap.typ.size) MOD 4);	(*keep stack aligned*)
					END
				END
			END
		END AllocTempSpace;
		
	BEGIN
		IF ~assignment THEN  OPC.PushRegs  END;	(*be sure nothing is pushed in that case!*)
		firstap := proc.right; firstfp := proc.obj;
		tproc := (proc.left.obj#NIL)&(proc.left.obj.mode = TProc);
		IF tproc THEN  firstap := firstap.link; firstfp := firstfp.link  END;	(*skip self*)
		
			(*temporary values*)
		staticsize := 0; dynblocks := 0;
		AllocTempSpace(dynblocks, staticsize, firstap, firstfp);  OPC.AllocateStatic(tos, staticsize);
		
			(*return descriptor*)
		IF proc.typ.form=Comp THEN
			OPC.CorrectStackAdr(res, staticsize, dynblocks);	(*correction for static allocated ret areas*)
			OPC.PushRetDesc(res, tos);
		END;
		dynptr := tos; OPC.CorrectStackAdr(dynptr, staticsize, 0);
		
			(*parameters*)
		ap := firstap; fp := firstfp;
		WHILE ap # NIL DO
			IF (ap.class = Ncall) & (ap.typ.form = Comp) THEN
				IF ap.typ.comp IN {OpenArr, SDynArr} THEN	(*dynamic, indirect*)
					x := dynptr;
					OPC.DeRef(dynptr);
					x.typ := ap.typ; INC(x.offs, 4);
					x.descReg:=dynptr.adr; x.descOffs := dynptr.offs - 4;
					OPC.Parameter(x, fp, FALSE, FALSE);
				ELSIF (*(ap.typ.comp=StaticArr)&*)(fp.typ.comp=OpenArr) OR (fp.mode = VarPar) THEN	(*static, indirect*)
					x := tos; x.typ := ap.typ; Call(ap, x, FALSE);
					x := tos; x.typ := ap.typ; OPC.Parameter(x, fp, FALSE, FALSE);
					OPC.CorrectStackAdr(tos, ap.typ.size+(-ap.typ.size) MOD 4, 0);	(*prepare for next static*)
				ELSE	(*static, direct*)
					OPC.AllocateStatic(x, fp.typ.size); x.typ:=fp.typ; Call(ap, x, FALSE)
				END
			ELSE
				Expression(ap, x, NIL);  OPC.Parameter(x, fp, ap.class=Nderef, FALSE);
			END;
				(*correct tos*)
			IF (fp.mode = VarPar) THEN
				IF (fp.typ.comp = Record) THEN s:= RecVarParSize
				ELSIF (fp.typ.comp = OpenArr) THEN s:= fp.typ.size
				ELSE s:= VarParSize
				END
			ELSE s:= fp.typ.size
			END; AlignPar(s);
			OPC.CorrectStackAdr(tos, s, 0);
			OPC.CorrectStackAdr(dynptr, s, 0);
			ap := ap.link; fp := fp.link
		END;
		IF tproc THEN
			Expression(proc.right, x, NIL);  OPC.Parameter(x, proc.obj, proc.right.class=Nderef, FALSE)
		END;
		
			(*activation*)
		IF proc.subcl = 2 THEN	(*inlined*)
			Statement(proc.left, NIL)
		ELSE
			Designator(proc.left, x);
			IF proc.left.class = Nproc THEN OPC.Call(x, proc.left.obj, proc)
			ELSE  OPC.Call(x, NIL, proc)
			END
		END;
			(*cleanup*)
		IF ~(proc.typ.comp IN {OpenArr, SDynArr}) THEN
			OPC.RemoveStatic(staticsize);
			OPC.ResetStack(dynblocks)
		END;
		IF (proc.typ=OPT.notyp)OR(proc.typ.form=Comp) THEN  (* pop register and put result into z, also restore regs *)
			OPC.PopResult(NIL, res)
		ELSE
			OPC.PopResult(proc, res)
		END;
	END CallLR;
	
	PROCEDURE CallRL(proc: OPT.Node; VAR res: OPC.Item; assignment: BOOLEAN);
		VAR ap: OPC.Item; n, p, q: OPT.Node; fp, formPar: OPT.Object;
	BEGIN
		n := proc.right; fp := proc.obj; 
		IF ~assignment THEN OPC.PushRegs END;
		IF n # NIL THEN
			p := n; formPar := fp;
			WHILE p.link # NIL DO 
				p := p.link; formPar := formPar.link
			END;
			WHILE p # n DO
				Expression (p, ap, NIL);
				OPC.Parameter (ap, formPar, p^.class = Nderef, TRUE); (* mh 16.2.94 *)
				q := n; formPar := fp;
				WHILE q.link # p DO 
					q := q.link; formPar := formPar.link
				END;
				p := q
			END;
			Expression (n, ap, NIL);
			OPC.Parameter (ap, fp, n^.class = Nderef, TRUE); (* mh 16.2.94 *)
		END;
		IF proc.subcl = 2 THEN	(*inlined*)
			Statement(proc.left, NIL)
		ELSE
			Designator(proc.left, res);
			IF proc.left.class = Nproc THEN OPC.Call(res, proc.left.obj, proc)
			ELSE  OPC.Call(res, NIL, proc)
			END
		END;
		IF (proc.typ=OPT.notyp) THEN
			OPC.PopResult(NIL, res)
		ELSE
			OPC.PopResult(proc, res); (* pop register and put result into z *)
		END
	END CallRL;
	
	PROCEDURE Call(proc: OPT.Node; VAR res: OPC.Item; assignment: BOOLEAN);
	VAR  obj: OPT.Object; n: OPT.Node; i: LONGINT;
	BEGIN
		n := proc.left;
		IF (n.class = Nproc) OR (n.class = Nassembler) THEN	(*procedure*)
			obj := n.obj;
			IF (obj.sysflag IN {winapi, cdecl}) THEN
				CallRL(proc, res, assignment)
			ELSE
				CallLR(proc, res, assignment)
			END
		ELSE	(*procedure variable*)
			i := n.class;
			ASSERT(n.typ.form = ProcTyp);
			IF (n.typ.sysflag IN {winapi, cdecl}) THEN
				CallRL(proc, res, assignment)
			ELSE
				CallLR(proc, res, assignment)
			END
		END
	END Call;
	
	PROCEDURE Expression (n: OPT.Node; VAR z: OPC.Item; selfForUnlock: OPT.Node);
		VAR x, y: OPC.Item; f: INTEGER; real: REAL; con: OPT.Const; typ: OPT.Struct; tmp: ARRAY 8 OF BYTE;
		
		PROCEDURE AllocConst (VAR bytes: ARRAY OF SYSTEM.BYTE; len, align: LONGINT);
			VAR con1, con2: OPT.Const;
		BEGIN
			con1 := con;
			IF n.obj = NIL THEN OPL.AllocConst (bytes, len, align, con1.intval)
			ELSE
				con2 := n.obj.conval;
				IF con2.intval = OPM.ConstNotAlloc THEN OPL.AllocConst (bytes, len, align, con2.intval) END;
				con1.intval := con2.intval
			END
		END AllocConst;
		
	BEGIN
		z.node := NIL;
		CASE n.class OF
			Nconst:
				z.typ := n.typ; z.mnolev := 0; z.node := NIL; (* constants have no node *)
				con := n.conval;
				CASE z.typ.form OF
					Byte..LInt, NilTyp, Pointer:
						z.mode := Con; z.adr := con.intval
				  | Set:
						z.mode := Con; z.adr := ORD(con.setval)
				  | String:
  				  tmp[0] := ORD(con.ext[0]); tmp[1] := ORD(con.ext[1]);
  				  tmp[2] := ORD(con.ext[2]); tmp[3] := ORD(con.ext[3]);
						AllocConst (tmp, con.intval2, 4); 
						z.mode := Abs; z.adr := con.intval; z.offs := con.intval2 (* length *); z.inx := OPL.none
				  | Real:
						real := SHORT (con.realval);
						BYTES(tmp, real);
						AllocConst (tmp, 4, 4); 
						z.mode := Abs; z.adr := con.intval; z.inx := OPL.none
				  | LReal:
  				  BYTES(tmp, con.realval);
						AllocConst (tmp, 8, 4);
						z.mode := Abs; z.adr := con.intval; z.inx := OPL.none
				END
		  | Nupto:
				Expression (n.left, x, selfForUnlock); Expression (n.right, y, selfForUnlock); OPC.SetRange (z, x, y)
		  | Nmop:
				IF (n.subcl # is) & (n.subcl # type) THEN Expression (n.left, x, selfForUnlock) END;
				z := x;
				CASE n.subcl OF
					not:
						OPC.Not (z, x)
				  | minus:
						OPC.Neg (z, x)
				  | is:
						Designator (n.left, z);
						IF n.obj.typ.form = Pointer THEN OPC.TypeTest (z, n.obj.typ, FALSE, FALSE, FALSE)
						ELSE OPC.TypeTest (z, n.obj.typ, FALSE, FALSE, TRUE)
						END
				  | conv:
						IF n.typ.form = Set THEN OPC.SetElem (z, x)
						ELSE
							z := x; OPC.Convert (z, n.typ.form)
						END
				  | abs:
						OPC.AbsVal (z, x)
				  | cap:
						OPC.Cap (z, x)
				  | odd:
						OPC.Odd (z, x)
				  | adr, cc, val, get8, get16, get32: (* Module SYSTEM *)
						OPC.SYSmop (z, x, n.subcl, n.typ)
				  | type:
						typ := n.left.typ;
						IF typ.form = Pointer THEN
							typ := typ.BaseTyp
						END;
						ASSERT(typ.comp = Record);
						OPC.GetTdAdr(typ, z);
						z.typ := OPT.linttyp
				END;
		  | Ndop:
				Expression (n.left, x, selfForUnlock); f := x.typ.form; 
				IF n.subcl = and THEN OPC.CondAnd (x)
				ELSIF n.subcl = or THEN OPC.CondOr (x)
				ELSIF (n.subcl >= eql) & (n.subcl <= geq) THEN OPC.Relation (x)
				END;
				Expression (n.right, y, selfForUnlock);
				CASE n.subcl OF
					times:
						OPC.Mul (z, x, y, f)
				  | slash, div:
						OPC.Div (z, x, y, f)
				  | mod:
						OPC.Mod (z, x, y)
				  | and:
						OPC.And (z, x, y)
 				 | plus:
						OPC.Add (z, x, y, f)
				  | minus:
						OPC.Sub (z, x, y, f)
				  | or:
						OPC.Or (z, x, y)
				  | eql..geq:
						OPC.Cmp (z, x, y, n.subcl)
				  | in:
						OPC.In (z, x, y)
				  | ash:
						OPC.Ash (z, x, y)
				  | msk:
						OPC.Msk (z,  x, y)
				  | len:
						OPC.Len (z, x, y)
				  | (* SYSTEM *) bit, lsh, rot:
						OPC.SYSdop (z, x, y, n.subcl)
				END
		  | Ncall:
		  	  Call(n, z, FALSE);
		ELSE
			Designator (n, z);
			RETURN
		END;
		z.typ := n.typ;
	END Expression;
	
	PROCEDURE IfStat (n, selfForUnlock: OPT.Node; VAR Lfix, Lcfix: OPC.Label; else: BOOLEAN);
		VAR x: OPC.Item;
	BEGIN
		LOOP
			OPM.errpos := n.conval.intval;
			Expression (n.left, x, selfForUnlock);  OPC.Jncc (x, Lcfix, n); Statement (n.right, selfForUnlock);
			IF n.link = NIL THEN EXIT END;
			OPC.Jmp (Lfix, n); OPC.FixLink (Lcfix);
			n := n.link
		END;
		IF else THEN OPC.Jmp (Lfix, n) END
	END IfStat;
	
	PROCEDURE CaseStat (n, selfForUnlock: OPT.Node);
		VAR 
			case, interval: OPT.Node;
			x: OPC.Item;
			L, elseLabel, dummy: OPC.Label;
			low, high, tab: LONGINT;
	BEGIN
		Expression (n.left, x, selfForUnlock); low := n.right.conval.intval; high := n.right.conval.intval2;
		L := OPC.Nil;
		OPC.Case (x, low, high, tab, elseLabel, n);
		case := n.right.left;
		WHILE case # NIL DO
			OPC.DefLabel (dummy); (* label entry: used for common subexpression elimination *)
			interval := case.left;
			WHILE interval # NIL DO
				OPL.CaseJump (OPC.pc, tab, interval.conval.intval - low, interval.conval.intval2 - low);
				interval := interval.link
			END;
			Statement (case.right, selfForUnlock); OPC.Jmp (L, n);
			case := case.link;
		END;
		OPC.FixLink (elseLabel); elseLabel := OPC.pc;
		IF n.right.conval.setval # {} THEN Statement (n.right.right, selfForUnlock) (* ELSE part *)
		ELSE OPC.Trap (OPL.CaseTrap, n)
		END;
		OPC.CaseFixup (tab, elseLabel, high - low + 1);
		OPC.FixLink (L) 
	END CaseStat;

	PROCEDURE Dim (VAR z, nofelem: OPC.Item; n: OPT.Node; typ: OPT.Struct; nofdim: LONGINT);
		VAR
			len: OPC.Item;
	BEGIN
		ASSERT(typ.comp IN {StaticArr, DynArr, OpenArr});
		Expression(n, len, NIL);
		IF len.mode # Con THEN OPC.PushLen(len); OPC.GenDimTrap(len) END;
		
		IF nofdim = 1 THEN  nofelem:=len; nofelem.typ:=OPT.linttyp
		ELSE  OPC.MulDim(nofelem, len)  END;
		
		IF n.link # NIL THEN
			Dim(z, nofelem, n.link, typ.BaseTyp, nofdim+1)
		ELSE
			OPC.NewArray(z, nofelem, nofdim, typ.BaseTyp, TRUE);
			INC(z.offs, 4)
		END;
		IF len.mode # Con THEN  OPC.PopLen(z)  ELSE  z.typ:=OPT.linttyp; OPC.Assign(z, len)  END;
		INC(z.offs, 4)
	END Dim;

	PROCEDURE Statement (n, selfForUnlock: OPT.Node);
		VAR 
			x, y, z, times: OPC.Item; t: OPT.Struct; p: OPT.Node;
			L, Lc, prevExitChain: OPC.Label;
			proc, par: OPT.Object;
			name: ARRAY 64 OF CHAR;
			i, j: LONGINT;
			res: INTEGER;
	BEGIN 
		WHILE ~OPO.CodeErr & (n # NIL) DO 
			OPC.NewStat (n.conval.intval); 
			CASE n.class OF
				Nenter:
					IF n.obj = NIL THEN (* enter module *)
						IF OPM.traceprocs IN OPM.options THEN
							OPM.LogWLn; OPM.LogWStr("B")
						END;
						OPC.pc := 0;
						OPC.Enter (NIL, 0, NIL);
						Statement (n.right, NIL);
						OPC.Exit (NIL);
						IF dumpCode THEN
							ProcName := "Body"; EntryNr := -1;
							Oberon.Call (DumpCode, Oberon.Par, FALSE, res)
						END;
						OPL.GenCode (OPC.pc);
						OPL.OutRefPoint (NIL); OPL.OutRefName ("$$"); OPL.OutRefs (OPT.topScope);
						INC (OPC.level); Statement (n.left, NIL); DEC (OPC.level)
					ELSE (* procedure *)
						IF OPM.traceprocs IN OPM.options THEN
							OPM.LogWLn; OPM.LogWStr("P ");
							OPM.LogWStr(n.obj.name);
						END;
						proc := n.obj; par := proc.link;
						INC (OPC.level); Statement (n.left, NIL); DEC (OPC.level);
						OPC.pc := 0;
						IF hasBody IN proc.conval.setval THEN
							OPC.Enter (proc, proc.conval.intval2, n);
							IF proc.code#NIL THEN
								Statement(proc.code, NIL);	(*glue code and initialisations*)
								OPC.AllocSDynArr(proc);		(*and alloc the SDynArrs*)
							END;
							Statement (n.right, NIL);
							IF (proc.typ # OPT.notyp) & ~(asmProc IN proc.conval.setval) & (proc.mode # Typ) THEN OPC.Trap (OPL.FuncTrap, n)
							ELSE OPC.Exit (proc)
							END;
							OPL.OutRefPoint (proc);
							IF proc.mode IN {TProc, Typ} THEN
								t := proc.link.typ;
								IF (t.comp = Record) & (t.ptr # NIL) & (t.ptr.strobj # NIL) THEN par := t.ptr.strobj
								ELSIF (t.comp = Record) OR (t.BaseTyp.strobj.name = "") THEN par := t.strobj
								ELSE par := t.BaseTyp.strobj END;
								i := 0;
								IF par # NIL THEN
									WHILE par.name[i] # 0X DO name[i] := par.name[i]; INC(i) END;
									name[i] := "."; INC(i)
								ELSE
									name := "??."; i := 3;
								END;
								IF proc.mode = TProc THEN
									j := 0;
									WHILE proc.name[j] # 0X DO name[i] := proc.name[j]; INC(i); INC(j) END;
									name[i] := 0X
								ELSIF proc.mode = Typ THEN			(* Type body *)
									name[i] := "$"; name[i+1] := "$"; name[i+2] := 0X
								END
							ELSE name:=proc.name
							END;
							OPL.OutRefName (name); OPL.OutRefs (proc.scope.right);
							IF dumpCode THEN
								ProcName := proc.name; 
								IF proc.vis = external THEN EntryNr := SHORT (proc.adr MOD 10000H)
								ELSE EntryNr := -1
								END;
								Oberon.Call (DumpCode, Oberon.Par, FALSE, res)
							END;
							OPL.GenCode (OPC.pc)
						END
					END
			  | Ninittd: (* done by the loader *)
			  | Nassign:
			  	  IF n.subcl = assign THEN
			  	  	IF (n.right.class = Ncall) & (n.right.typ.form = Comp) THEN
			  	  		OPC.PushRegs;
			  	  		Expression(n.left, z, selfForUnlock);	(*dest*)
			  	  		Call(n.right, z, TRUE)
			  	  	ELSE
					  	  Expression(n.right, x, selfForUnlock);  OPC.Relation(x);		(*load the Condition Code, if generated by expression*)
					  	  Expression(n.left, z, selfForUnlock);
				  	  	OPC.Assign (z, x)
				  	  END
			  	  ELSIF (n.subcl = stifn) OR (n.subcl = clifn) THEN					(* New Functions *)
			  	  	OPC.SYSinterrupt(n.subcl=clifn)
			  	  ELSE
						IF (n.subcl # lockfn) THEN
							Expression (n.left, z, selfForUnlock)
						END;
						IF (n.subcl # newfn) THEN
							Expression (n.right, x, selfForUnlock)
						END; 
						IF n.subcl = movefn (* SYSTEM.Move *) THEN
							Expression (n.right.link, times, selfForUnlock); OPC.SYSmove (z, x, times)
						ELSE
							CASE n.subcl OF
							  | incfn, decfn: OPC.IncDec (z, x, n.subcl = incfn)
							  | inclfn, exclfn: OPC.Include (z, x, n.subcl = inclfn)
						 	 | getfn, putfn: OPC.SYSgetput (z, x, n.subcl = getfn)
						  	| getrfn, putrfn: OPC.SYSgetputReg (z, x, n.subcl = getrfn)
							  | pinfn, poutfn: OPC.SYSportio (z, x, n.subcl = pinfn)					(* New Functions *)
							  | awaitfn: Expression(n.right.link, y, selfForUnlock); OPC.Await(z, x, y)
							  | lockfn: Expression (n.right.link, z, NIL); OPC.Lock(x, z); Statement(n.left, n.right);
							  				Expression (n.right, x, NIL); Expression (n.right.link, z, NIL); OPC.Unlock(x, z);
						  	| copyfn: OPC.Copy (z, x)
						  	| sysnewfn: OPC.NewSys (z, x)
						  	| newfn:
									t := n.left.typ;
						  		IF (n.right#NIL) & ((t.comp IN ArraySet)OR (t.BaseTyp.comp IN ArraySet)) THEN
						  			IF t.form = Pointer THEN
						  				t := t.BaseTyp;
						  				IF t.comp=DynArr THEN  x := z; OPC.NewRec (x, t); OPC.DeRef(z) END	(*allocate the descriptor*)
										END;
						  			Dim(z, x, n.right, t, 1)
						  		ELSE
										ASSERT(t.form = Pointer);
										t := t.BaseTyp;
										OPC.NewRec (z, z.typ.BaseTyp);
										IF (t.comp#StaticArr) & (t.strobj # NIL) & (t.strobj.conval # NIL) THEN
											IF n.left.link # NIL THEN	(* object parametrisation *)
												n.left.link.conval := n.conval;
												Statement(n.left.link, selfForUnlock)
											END;
											p := n.right;
											WHILE p # NIL DO
												Expression(n.left, z, selfForUnlock); Expression(p, x, selfForUnlock);
												OPC.CallRecBody(z, x, p.obj.typ(*z.typ.BaseTyp*));
												p := p.link
											END
										END
									END
							END (* CASE *)
						END
					END
			  | Ncall:
					Call(n, x, FALSE)
			  | Nifelse:
					IF (n.subcl # assertfn) OR assert THEN
						L := OPC.Nil; Lc := OPC.Nil;
						IfStat (n.left, selfForUnlock, L, Lc, n.right # NIL); (* L label for jump to END of if statment, Lc for the ELSE statement *)
						OPC.FixLink (Lc);
						IF n.right # NIL THEN Statement (n.right, selfForUnlock) END;
						OPC.FixLink (L)
					END
			  | Ncase:
					CaseStat (n, selfForUnlock)
			  | Nwhile:
					L := OPC.Nil; OPC.Jmp (L, n);
					OPC.DefLabel (Lc); Statement (n.right, selfForUnlock);
					OPC.FixLink (L); Expression (n.left, x, selfForUnlock);
					OPC.Jcc (x, Lc, n)
			  | Nrepeat:
					OPC.DefLabel (L); Statement (n.left, selfForUnlock);
					Expression (n.right, x, selfForUnlock);
					OPC.Jncc (x, L, n)
			  | Nloop:
					prevExitChain := ExitChain; ExitChain := OPC.Nil;
					OPC.DefLabel (L); Statement (n.left, selfForUnlock); OPC.Jmp (L, n);
					OPC.FixLink (ExitChain); ExitChain := prevExitChain
			  | Nexit:
					OPC.Jmp (ExitChain, n)
			  | Nreturn:
					IF n.left # NIL THEN (* function *)
						IF (n.left.class = Ncall) & (n.left.typ.form = Comp) THEN (*optimization*)
							OPC.PushRegs;
							dummy.mode := VarPar; dummy.mnolev := OPC.level;	(*fake mnolev: this is a temporary address on the stack, no allocated variable*)
							dummy.adr:=n.obj.conval.intval;		(*param size, needed to find the ret adr*)
							dummy.typ:=n.left.typ;
							Call(n.left, dummy, TRUE);
							dummy.mode:=0
						ELSE
							Expression (n.left, x, NIL);
							OPC.Return (x, n.obj)
						END
					END;
					IF selfForUnlock # NIL THEN
						OPC.PushRegs;
						Expression(selfForUnlock, x, NIL);
						Expression (selfForUnlock.link, z, NIL);
						OPC.Unlock(x, z);
						OPC.PopResult(NIL, x);
					END;
					OPC.Exit (n.obj)
			  | Nwith:
					L := OPC.Nil; Lc := OPC.Nil;
					IfStat (n.left, selfForUnlock, L, Lc, TRUE); (* L label for jump to END of if statement, Lc for the ELSE statement *)
					OPC.FixLink (Lc);
					IF n.subcl = 1 (*  # NIL *) THEN Statement (n.right, selfForUnlock)
					ELSE OPC.Trap (OPL.WithTrap, n)
					END;
					OPC.FixLink (L)
			  | Ntrap:
					OPC.Trap (n.right.conval.intval, n)
			  | Nassembler:
			  	 OPC.GenAsm(n)
			END;
			n := n.link
		END; 
	END Statement;
	
	
	
	PROCEDURE Module* (prog: OPT.Node);
	BEGIN
		Statement (prog, NIL);
		IF findpc & OPM.noerr THEN OPM.err (254) END
	END Module;

BEGIN
	dummy.mode:=0;
	OPT.typSize := TypSize;
	ParamAdr[0] := ParamAdrLR;
	ParamAdr[delegate] := ParamAdrLR;
	ParamAdr[winapi] := ParamAdrRL;
	ParamAdr[cdecl] := ParamAdrRL;
END OPV.
