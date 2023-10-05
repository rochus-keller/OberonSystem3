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

MODULE Objects;	(** portable *) (* JG 21.9.93/comments jm 28.2.95 *)

(** Module Objects forms the basis of the object-oriented part of the Oberon system. 
It provides the system with the type Object and defines what messages objects understand. 
Most entities in Oberon are derived from this base type.
*)

  IMPORT SYSTEM, Kernel, Files, Modules;

  CONST
    enum* = 0; get* = 1; set* = 2; (** AttrMsg and LinkMsg id *)
    shallow* = 0; deep* = 1; (** CopyMsg id *)
    load* = 0; store* = 1; (** FileMsg id*)
    
    (** AttrMsg class *)
    Inval* = 0; String* = 2; Int* = 3; Real* = 4; LongReal* = 5; Char* = 6; Bool* = 7;

    MaxNews = 64; MaxRuns = 64;
	StepSize = 64; 	(* number of elems to grow an index block *)
	Version = 052454942H;

  TYPE 
    Name* = ARRAY 32 OF CHAR;
    Object* = POINTER TO ObjDesc;
    Dummy* = POINTER TO DummyDesc;
    Library* = POINTER TO LibDesc;

    ObjMsg* = RECORD	(** Base type of all messages sent to objects. *)
      stamp*: LONGINT;	(** Message time stamp. *)
      dlink*: Object	(** Sender of the message. *)
    END;

    Handler* = PROCEDURE (obj: Object; VAR M: ObjMsg);

    ObjDesc* = RECORD	(** Base type of all objects. *)	(* Note: SIZE used in Fonts.GetCharObj *)
      stamp*: LONGINT;	(** Time stamp of last message processed by object. *)
      dlink*,	(** Next object in the message thread. *)
      slink*: Object;	(** Next object in a list of objects. *)
      lib*: Library; ref*: INTEGER;	(** Library and reference number of object. *)
      handle*: Handler	(** Message handler. *)
    END;

    (** Set, get and enumerate the attributes of an object. *)
	AttrMsg* = RECORD (ObjMsg)
		id*: INTEGER;	(** get, set or enum. *)
		Enum*: PROCEDURE (name: ARRAY OF CHAR);	(** Called by object to enumerate attribute names. *)
		name*: Name;	(** Name of the attribute to be set or retrieved. *)
		res*: INTEGER;	(** Return result: < 0 = no response, >= 0 action completed. *)
		class*: INTEGER;	(** Attribute class (Inval, String, Int, Real, LongReal, Char or Bool). *)
		i*: LONGINT;
        x*: REAL;
        y*: LONGREAL;
		c*: CHAR;
		b*: BOOLEAN;
		s*: ARRAY 64 OF CHAR
	END;

	(** Link objects with each other or retrieve the link structure between objects *)
	LinkMsg* = RECORD (ObjMsg)
		id*: INTEGER;	(** get, set or enum. *)
		Enum*: PROCEDURE (name: ARRAY OF CHAR);	(** Called by object to enumerate link names. *)
		name*: Name;	(** Link name. *)
		res*: INTEGER;	(** Return result: < 0 = no response, >= 0 action completed. *)
        obj*: Object	(** Value of the link to be set, or link result. *)
	END;

	(** Request to an object to make a copy of itself *)
    CopyMsg* = RECORD (ObjMsg)
      id*: INTEGER;	(** Copy style: deep or shallow. *)
      obj*: Object	(** Result of the copy operation. *)
    END;

	(** Request to an object to bind itself to a library. *)
    BindMsg* = RECORD (ObjMsg)
      lib*: Library	(** Library where object should be bound. *)
    END;

	(** Request to an object to load/store itself. *)
    FileMsg* = RECORD (ObjMsg)
      id*: INTEGER;	(** load or store *)
      len*: LONGINT;	(** Length of the object data on loading. *)
      R*: Files.Rider	(** Rider with which to load or store data. *)
    END;

	(** Search request for an object with the specified name. *)
    FindMsg* = RECORD (ObjMsg)
      name*: Name;
      obj*: Object	(** Result object, if found. *)
    END;

	(** A placeholder object created for objects that cannot be loaded. *)
	DummyDesc* = RECORD (ObjDesc)
		GName*: Name;	(** Generator procedure of failed object. *)
		len: LONGINT;	(* length of data block *)
		blk: POINTER TO ARRAY OF CHAR	(* stores the data on file *)
    END;

	(** (Hidden) Data structure containing the objects of a library. *)
    Index* = POINTER TO IndexDesc;
    IndexDesc* = RECORD END;

	(** (Hidden) Map of (ref) numbers and corresponding object names. *)
	Dictionary* = POINTER TO DictionaryDesc;
	DictionaryDesc* = RECORD END;

    Block = POINTER TO ARRAY OF Object;
	ArrayIndex = POINTER TO ArrayIndexDesc;
	ArrayIndexDesc = RECORD (IndexDesc)
		index: Block;	(* index block, containing the objects *)
		org: LONGINT;	(* offset in libfile where index block starts *) 
		size: INTEGER	(* size of the actual index block *)
	END;

    Entry = POINTER TO EntryDesc;
    EntryDesc = RECORD
      next: Entry;
      key: INTEGER;
      name: Name
    END;

	ListDict = POINTER TO ListDictDesc;
	ListDictDesc = RECORD (DictionaryDesc)
		key: INTEGER;
		first: Entry
	END;
		
	GenName = ARRAY 64 OF CHAR;

    LibDesc* = RECORD	(** Container for persistent objects. *)
      next: Library; (* offset used by Fonts.GetCharObj, also next offset *)
      ind*: Index;	(** Library contents. *)
      f: Files.File;	(* file containing data *)
      R: Files.Rider;	(* a rider on the lib file *)
      name*: Name;	(** name of the library. Private library when "", else public library. *)
      dict*: Dictionary;	(** Object names. *)
      maxref*: INTEGER;	(** Highest ref number used in library. *)
      GName: POINTER TO ARRAY OF GenName;

      (** Return a free reference number. *)
      GenRef*: PROCEDURE (L: Library; VAR ref: INTEGER);
      
      (** Return the object with the indicated reference number. *)
      GetObj*: PROCEDURE (L: Library; ref: INTEGER; VAR obj: Object);
      
      (** Insert an object under the indicated reference number. *)
      PutObj*: PROCEDURE (L: Library; ref: INTEGER; obj: Object);
      
      (** Free object with indicated reference number. *)
      FreeObj*: PROCEDURE (L: Library; ref: INTEGER);
      
      (** Initialize/load library with L.name. *)
      Load*: PROCEDURE (L: Library);
      
      (** Store library under L.name. *)
      Store*: PROCEDURE (L: Library)
    END;

    NewProc* = PROCEDURE (): Library;	(** Library generator. *)
    EnumProc* = PROCEDURE (L: Library);	(** Enumerator of public libraries *)

	RunRec = RECORD beg, end: INTEGER END;
	
	Alias = POINTER TO AliasDesc;
	AliasDesc = RECORD
		next: Alias;
		name: Name;
		lib: Library
	END;
	
  VAR
    LibBlockId*: CHAR;	(** Identification character as first character of a Library file. *)
    FirstLib: Library;
	NoObj: Object;

    NewObj*: Object;	(** Newly generated objects are returned here. *)
    stamp: LONGINT;

    nofreg: INTEGER;
    LibExt: ARRAY  8, 8 OF CHAR;
    LibNew: ARRAY 8 OF NewProc;
    
    FirstAlias: Alias;

  PROCEDURE Stamp* (VAR M: ObjMsg);	(** Timestamp a message.  *)
  BEGIN M.stamp := stamp;
    IF stamp # MAX(LONGINT) THEN INC(stamp) ELSE stamp := MIN(LONGINT) END
  END Stamp;

  (*general library management*)

	(* Delete library L from the list, without changing L.next. *)
	
	PROCEDURE Cleanup(L: SYSTEM.PTR);
	VAR p0, p: Library; a0, a: Alias;
	BEGIN
		WITH L: Library DO
			p0 := FirstLib;  p := p0.next;
			WHILE (p # NIL) & (p # L) DO p0 := p;  p := p.next END;
			IF p = L THEN (* found in list *)
				p0.next := p.next
			END;
			a0 := FirstAlias; a := a0.next;
			WHILE (a # NIL) & (a.lib # L) DO a0 := a; a := a.next END;
			IF a # NIL THEN a0.next := a.next END
		END
	END Cleanup;

(* Check if end of s matches ext.  len returns length of ext. *)

	PROCEDURE Match(VAR s, ext: ARRAY OF CHAR; VAR len: INTEGER): BOOLEAN;
	VAR i, j: INTEGER;
	BEGIN
		i := 0; WHILE ext[i] # 0X DO INC(i) END; len := i;
		j := 0; WHILE s[j] # 0X DO INC(j) END;
		REPEAT DEC(i); DEC(j)
		UNTIL (i < 0) OR (j < 0) OR (ext[i] # s[j]);
		RETURN i < 0	
	END Match;

(** Search, load and cache a public library. *)
  PROCEDURE ThisLibrary* (name: ARRAY OF CHAR): Library;
    VAR L: Library; len, n, n0, t, i, j: INTEGER; proc: NewProc;  A: Alias;
  BEGIN
    A := FirstAlias.next;
    WHILE (A # NIL) & (name # A.name) DO A := A.next END;
    IF A # NIL THEN
      L := A.lib
    ELSE
      L := FirstLib.next;
      WHILE (L # NIL) & (name # L.name) DO L := L.next END;
      IF L = NIL THEN
        n := nofreg; n0 := 0; len := -1;
        WHILE n0 # nofreg DO	(* find longest matching extension *)
          IF Match(name, LibExt[n0], t) & (t >= len) THEN
            n := n0; len := t
          END;
          INC(n0)
        END;
        IF n # nofreg THEN
          proc := LibNew[n];
          L := proc();
          COPY(name, L.name);
          L.Load(L);  Kernel.RegisterObject(L, Cleanup, FALSE);
          IF name = L.name THEN
            L.next := FirstLib.next; FirstLib.next := L
          ELSE
            NEW(A); COPY(name, A.name); A.lib := L; A.next := FirstAlias.next; FirstAlias.next := A;
            Kernel.WriteString("Alias: ");
            Kernel.WriteString(name);  Kernel.WriteString(" -> ");  Kernel.WriteString(L.name);
            Kernel.WriteLn
          END
        END
      END
    END;
    RETURN L
  END ThisLibrary;

(** Free library from public library cache *)
  PROCEDURE FreeLibrary* (name: ARRAY OF CHAR);
    VAR L: Library;
  BEGIN
    L := FirstLib.next;
    WHILE L # NIL DO
      IF name = L.name THEN Cleanup(L) END;
      L := L.next
    END
  END FreeLibrary;

(** Enumerate public libraries. Don't free libraries during enumeration! *)
  PROCEDURE Enumerate* (P: EnumProc);
    VAR L: Library;
  BEGIN
    L := FirstLib.next;
    WHILE L # NIL DO P(L); L := L.next END
  END Enumerate;

(** Register a new library file extension and its associated generator procedure. *)
  PROCEDURE Register* (ext: ARRAY OF CHAR; new: NewProc);
    VAR n, len: INTEGER; L: Library;
  BEGIN n := 0;
    WHILE (n # nofreg) & (ext # LibExt[n]) DO INC(n) END;
    IF n # nofreg THEN LibNew[n] := new
      ELSE COPY(ext, LibExt[nofreg]); LibNew[nofreg] := new; INC(nofreg)
    END;
    (* free library entries that match *)
    L := FirstLib.next;
    WHILE L # NIL DO
    	IF Match(L.name, ext, len) THEN Cleanup(L) END;
    	L := L.next
    END
  END Register;

  (*standard libraries*)

  PROCEDURE ReadName (VAR R: Files.Rider; VAR name: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN i := 0; Files.Read(R, ch);
    WHILE (ch # ".") & (ch # 0X) DO name[i] := ch; INC(i); Files.Read(R, ch) END;
    name[i] := "."; INC(i); Files.Read(R, ch);
    WHILE ch # 0X DO name[i] := ch; INC(i); Files.Read(R, ch) END;
    name[i] := 0X
  END ReadName;

  PROCEDURE SplitName (VAR name, MName, PName: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN i := 0;
    WHILE name[i] # "." DO MName[i] := name[i]; INC(i) END;
    MName[i] := 0X; INC(i); j := 0;
    WHILE name[i] # 0X DO PName[j] := name[i]; INC(i); INC(j) END;
    PName[j] := 0X
  END SplitName;

	PROCEDURE HandleDummy (obj: Object; VAR M: ObjMsg);
		VAR dum: Dummy;
	BEGIN
		WITH obj: Dummy DO
			IF M IS AttrMsg THEN
				WITH M: AttrMsg DO 
					IF (M.id = get) & (M.name = "Gen") THEN COPY(obj.GName, M.s) END
				END
			ELSIF M IS CopyMsg THEN
				WITH M: CopyMsg DO
					IF M.stamp = obj.stamp THEN M.obj := obj.dlink
					ELSE
						NEW(dum); obj.stamp := M.stamp; obj.dlink := dum;
						dum.handle := obj.handle;
						COPY(obj.GName, dum.GName); dum.len := obj.len; dum.blk := obj.blk;
						M.obj := dum
					END
				END
			ELSIF M IS FileMsg THEN
				WITH M: FileMsg DO
					IF M.id = load THEN
						obj.len := M.len; NEW(obj.blk, obj.len);
						Files.ReadBytes(M.R, obj.blk^, obj.len)
					ELSIF M.id = store THEN
						Files.WriteBytes(M.R, obj.blk^, obj.len)
					END
				END
			END
		END
	END HandleDummy;

	PROCEDURE NewDummy (VAR GName: ARRAY OF CHAR);
		VAR dum: Dummy;
	BEGIN
		NEW(dum); dum.handle := HandleDummy;
		COPY(GName, dum.GName);
		NewObj := dum
	END NewDummy;

	PROCEDURE GetObj (L: Library; ref: INTEGER; VAR obj: Object);
		VAR objOrg: LONGINT; ind: ArrayIndex; MName, PName: ARRAY 32 OF CHAR; n: INTEGER;
				Mod: Modules.Module; Cmd: Modules.Command; M: FileMsg;
	BEGIN
		ind := L.ind(ArrayIndex);
		IF (ref < 0) OR (ref >= ind.size) THEN obj := NIL; RETURN END;
		obj := ind.index[ref];
		IF obj = NIL THEN
			IF L.f # NIL THEN
				Files.Set(L.R, L.f, ind.org + ref*4);
				Files.ReadLInt(L.R, objOrg);
				IF objOrg > ind.org THEN
					NewObj := NIL;
					Files.Set(L.R, L.f, objOrg);
					Files.ReadInt(L.R, n);
					SplitName(L.GName[n], MName, PName);
					Mod := Modules.ThisMod(MName);
					IF Modules.res = 0 THEN
						Cmd := Modules.ThisCommand(Mod, PName);
						IF Modules.res = 0 THEN Cmd
						ELSE NewDummy(L.GName[n])
						END
					ELSE NewDummy(L.GName[n])
					END;
					obj := NewObj;
					IF obj # NIL THEN
						obj.lib := L; obj.ref := ref;
						ind.index[ref] := obj;
						(* read in data *)
						M.id := load; Stamp(M);
						Files.ReadLInt(L.R, M.len);
						Files.Set(M.R, L.f, Files.Pos(L.R));
						IF M.len > 0 THEN obj.handle(obj, M) END
					ELSE ind.index[ref] := NoObj
					END
				ELSE ind.index[ref] := NoObj
				END
			ELSE ind.index[ref] := NoObj
			END
		ELSIF obj = NoObj THEN obj := NIL
		END
	END GetObj;

	PROCEDURE PutObj (L: Library; ref: INTEGER; obj: Object);
		VAR index: Block; ind: ArrayIndex; i : LONGINT; size: INTEGER;
	BEGIN
		IF (ref < 0) OR (obj = NIL) THEN RETURN END;
		ind := L.ind(ArrayIndex);
		IF ref >= ind.size THEN
			size := (ref DIV StepSize + 1) * StepSize;
			NEW(index, size);
			IF ind.index # NIL THEN SYSTEM.MOVE(SYSTEM.ADR(ind.index^), SYSTEM.ADR(index^), ind.size*4) END;
			FOR i := ind.size TO size-1 DO index[i] := NoObj END;
			ind.size := size; ind.index := index
		END;
		ind.index[ref] := obj; obj.lib := L; obj.ref := ref;
		IF ref >= L.maxref THEN L.maxref := ref + 1 END
	END PutObj;

	PROCEDURE FreeObj (L: Library; ref: INTEGER);
	BEGIN
		IF (ref >= 0) & (ref < L.ind(ArrayIndex).size) THEN L.ind(ArrayIndex).index[ref] := NoObj END
	END FreeObj;

	PROCEDURE GenRef (L: Library; VAR ref: INTEGER);
	BEGIN ref := L.maxref; INC(L.maxref)
	END GenRef;

(* Load a standard object library (old format) from position pos in file f. *)
	PROCEDURE OldLoadLibrary (L: Library; f: Files.File; pos: LONGINT; VAR len: LONGINT);
		VAR R, S: Files.Rider; Mod: Modules.Module; Cmd: Modules.Command; NofRuns, key, N, i, k, m: INTEGER;
				clen, dlen: LONGINT; type, n: SHORTINT; ch: CHAR; entry: Entry;
				obj: Object; M: FileMsg; MName, PName: Name; GName: ARRAY MaxNews OF Name;
				run: ARRAY MaxRuns OF RunRec; ind: ArrayIndex; dict: ListDict;
	BEGIN
		ind := L.ind(ArrayIndex); dict:= L.dict(ListDict);
		Files.Set(R, f, pos); Files.Read(R, type);
		Files.ReadLInt(R, clen);
		Files.Set(S, f, pos + 1 + clen);
		Files.ReadLInt(S, dlen);
		Files.ReadInt(S, key);
		WHILE key # MIN(INTEGER) DO NEW(entry);
			Files.ReadString(S, entry.name);
			entry.key := key;
			entry.next := dict.first; dict.first := entry;
			IF key < dict.key THEN dict.key := key END;
			Files.ReadInt(S, key)
		END;
		IF type >= 0 THEN (*old format*)
			Files.Read(R, ch); Files.Read(R, ch);
			Files.ReadInt(R, i); Files.ReadInt(R, i); Files.ReadInt(R, i);
			Files.ReadInt(R, i); Files.ReadInt(R, i)
		END;
		Files.ReadInt(R, NofRuns);
		k := 0;
		 WHILE k # NofRuns DO
			Files.ReadInt(R, run[k].beg); Files.ReadInt(R, run[k].end);
			INC(k)
		END;
		N := 0; k := 0; m := 0;
		WHILE k < NofRuns DO m := run[k].beg;
			WHILE m < run[k].end DO Files.Read(R, n);
				IF n = N THEN ReadName(R, GName[N]); INC(N) END;
				SplitName(GName[n], MName, PName);
				Mod := Modules.ThisMod(MName);
				IF Modules.res = 0 THEN
					Cmd := Modules.ThisCommand(Mod, PName);
					IF Modules.res = 0 THEN Cmd
					ELSE NewDummy(GName[n])
					END
				ELSE NewDummy(GName[n])
				END;
				PutObj(L, m, NewObj);
				NewObj.lib := L; NewObj.ref := m;
				INC(m)
			END;
			INC(k)
		END;
		L.maxref := m;
		M.id := load; Stamp(M);
		Files.Set(M.R, f, Files.Pos(R));
		k := 0; m := 0;
		WHILE k < NofRuns DO m := run[k].beg;
			WHILE m < run[k].end DO
				Files.ReadLInt(M.R, M.len);
				pos := Files.Pos(M.R)+M.len;
				IF M.len # 0 THEN
					obj := ind.index[m];
					obj.handle(obj, M)
				END;
				IF Files.Pos(M.R) < pos THEN (*ejz skip rest of obj data *)
					Files.Set(M.R, f, pos)
				ELSIF Files.Pos(M.R) > pos THEN (*ejz object read too much *)
					HALT(99)
				END;
				INC(m)
			END;
			INC(k)
		END;
		len := 1 + clen + dlen
	END OldLoadLibrary;
	
(** Load a standard object library from position pos in file f. *)
	PROCEDURE LoadLibrary* (L: Library; f: Files.File; pos: LONGINT; VAR len: LONGINT);
		VAR ind: ArrayIndex; dict: ListDict; i, version, dorg, gorg: LONGINT; key, n, N: INTEGER; entry: Entry;
				R: Files.Rider;
	BEGIN
		ind := L.ind(ArrayIndex);
		Files.Set(R, f, pos);
		Files.ReadLInt(R, version);
		IF version = Version THEN
			Files.ReadLInt(R, gorg); Files.ReadLInt(R, dorg);
			Files.ReadInt(R, L.maxref); ind.size := L.maxref; ind.org := Files.Pos(R);
			IF L.maxref > 0 THEN NEW(ind.index, L.maxref) END;
			FOR i := 0 TO L.maxref - 1 DO ind.index[i] := NIL END;
			(* read generator table *)
			Files.Set(R, f, gorg);
			Files.ReadInt(R, N);
			IF N > 0 THEN
				NEW(L.GName, N);
				FOR n := 0 TO N - 1 DO Files.ReadString(R, L.GName[n]) END
			ELSE
				L.GName := NIL
			END;
			(* read dict *)
			dict := L.dict(ListDict);
			Files.Set(R, f, dorg);
			Files.ReadInt(R, key);
			WHILE key # MIN(INTEGER) DO
				NEW(entry);
				Files.ReadString(R, entry.name);
				entry.key := key;
				entry.next := dict.first; dict.first := entry;
				IF key < dict.key THEN dict.key := key END;
				Files.ReadInt(R, key)
			END;

			L.f := f; Files.Set(L.R, f, ind.org);
			len := Files.Pos(R) - pos
		ELSE
			ind.org := 0; ind.size := 0; ind.index := NIL;
			L.f := NIL; Files.Set(L.R, NIL, 0);
			OldLoadLibrary(L, f, pos, len)
		END
	END LoadLibrary;

(** Store a standard object library at position pos in file f. *)
	PROCEDURE StoreLibrary* (L: Library; f: Files.File; pos: LONGINT; VAR len: LONGINT);
		VAR obj: Object; ind: ArrayIndex; i, olen, org, indorg: LONGINT; m, n, N: INTEGER; entry: Entry;
				ch: CHAR; GName: ARRAY MaxNews OF GenName; R, indR: Files.Rider; M: FileMsg; A: AttrMsg;
	BEGIN
		ind := L.ind(ArrayIndex);
		Files.Set(R, f, pos);
		Files.Write(R, LibBlockId);
		Files.WriteLInt(R, Version);
		Files.WriteLInt(R, -1);	(* place holder genTable pos *)
		Files.WriteLInt(R, -1);	(* place holder dict pos *)
		Files.WriteInt(R, L.maxref);
		indorg := Files.Pos(R); Files.Set(indR, f, indorg);
		IF L.maxref > 0 THEN Files.WriteBytes(R, ind.index^, L.maxref*4) END;

		(* store obj data *)
		A.id := get; A.name := "Gen";
		N := 0;
		M.id := store; Stamp(M);
		FOR i := 0 TO L.maxref-1 DO
			obj := ind.index[i];
			IF obj = NIL THEN	(* object is not load yet *)
				Files.Set(L.R, L.f, ind.org + 4*i);
				Files.ReadLInt(L.R, org);
				IF org >= 0 THEN	(* there is an object in the file *)
					Files.Set(L.R, L.f, org);
					Files.ReadInt(L.R, m); Files.ReadLInt(L.R, olen);
					COPY(L.GName[m], GName[N]);
					n := 0;
					WHILE GName[n] # GName[N] DO INC(n) END;
					IF n = N THEN INC(N) END;
					
					Files.WriteLInt(indR, Files.Pos(R));	(* write index *)
					Files.WriteInt(R, n);
					Files.WriteLInt(R, olen);
					WHILE olen > 0 DO Files.Read(L.R, ch); Files.Write(R, ch); DEC(olen) END
				ELSE	(* there was never an object with this ref *)
					Files.WriteLInt(indR, -1)
				END
			ELSIF obj # NoObj THEN	(* there is an object to store *)
				A.res := -1; obj.handle(obj, A); COPY(A.s, GName[N]);
				n := 0;
				WHILE GName[n] # GName[N] DO INC(n) END;
				IF n = N THEN INC(N) END;

				Files.WriteLInt(indR, Files.Pos(R));	(* write index *)
				Files.WriteInt(R, n);
				Files.Set(M.R, f, Files.Pos(R));
				Files.WriteLInt(M.R, 0); obj.handle(obj, M);
				olen := Files.Pos(M.R) - Files.Pos(R) - 4;
				Files.WriteLInt(R, olen);
				Files.Set(R, f, Files.Pos(M.R))
			ELSE	(* no object *)
				Files.WriteLInt(indR, -1)
			END
		END;

		(* write generator table *)
		i := Files.Pos(R);
		Files.Set(R, f, pos + 5); Files.WriteLInt(R, i); Files.Set(R, f, i);
		Files.WriteInt(R, N);
		IF N > 0 THEN
			NEW(L.GName, N);
			FOR n := 0 TO N-1 DO
				Files.WriteString(R, GName[n]);
				COPY(GName[n], L.GName[n])
			END
		END;

		(* store dict *)
		i := Files.Pos(R);
		Files.Set(R, f, pos + 9); Files.WriteLInt(R, i); Files.Set(R, f, i);
		entry := L.dict(ListDict).first;
		WHILE entry # NIL DO
			Files.WriteInt(R, entry.key); i := 0;
			Files.WriteString(R, entry.name);
			entry := entry.next
		END;
		Files.WriteInt(R, MIN(INTEGER));
		len := Files.Pos(R) - pos;
		L.f := f; ind.org := indorg;
		Files.Set(L.R, L.f, ind.org)
	END StoreLibrary;

	PROCEDURE LoadFileLib (L: Library);
		VAR f: Files.File; R: Files.Rider; len: LONGINT; id: CHAR;
	BEGIN
		f := Files.Old(L.name);
		IF f # NIL THEN
			Files.Set(R, f, 0); Files.Read(R, id);
			IF id = LibBlockId THEN LoadLibrary(L, f, 1, len)
			ELSE L.f := NIL; L.ind(ArrayIndex).size := 0; L.ind(ArrayIndex).index := NIL
			END
		END
	END LoadFileLib;

	PROCEDURE StoreFileLib (L: Library);
		VAR f: Files.File; len: LONGINT;
	BEGIN
		f := Files.New(L.name);
		IF f # NIL THEN StoreLibrary(L, f, 0, len); Files.Register(f) END
	END StoreFileLib;

(** Initialize a standard object library. *)
	PROCEDURE OpenLibrary* (L: Library);
		VAR ind: ArrayIndex; dict: ListDict;
	BEGIN
		L.Load := LoadFileLib; L.Store := StoreFileLib;
		L.GenRef:= GenRef; L.GetObj := GetObj;
		L.PutObj := PutObj; L.FreeObj := FreeObj;
		NEW(ind); ind.org:= 0; ind.size := 0; ind.index := NIL; L.ind := ind;
		NEW(dict); dict.first := NIL; dict.key := 0; L.dict := dict;
		L.maxref := 0
	END OpenLibrary;

  PROCEDURE NewLibrary (): Library;
    VAR L: Library;
  BEGIN NEW(L); OpenLibrary(L); RETURN L
  END NewLibrary;

(** Given an object name, return the object reference number from the dictionary. *)
	PROCEDURE GetRef* (VAR D: Dictionary; name: ARRAY OF CHAR; VAR ref: INTEGER);
		VAR cur: Entry;
	BEGIN
		IF D IS ListDict THEN
			cur := D(ListDict).first;
			WHILE (cur # NIL) & ((cur.key < 0) OR (cur.name # name)) DO cur := cur.next END;
			IF cur = NIL THEN ref := MIN(INTEGER) ELSE ref := cur.key END
		ELSE ref := MIN(INTEGER)
		END
	END GetRef;

(** Allocate a key (any integer < 0) to a name. *)
  PROCEDURE GetKey* (VAR D: Dictionary; name: ARRAY OF CHAR; VAR key: INTEGER);
		VAR cur: Entry;
	BEGIN
		IF D IS ListDict THEN
			WITH D: ListDict DO
				cur := D.first;
				WHILE (cur # NIL) & ((cur.key >= 0) OR (cur.name # name)) DO cur := cur.next END;
				IF cur = NIL THEN DEC(D.key);
					NEW(cur); cur.key := D.key; COPY(name, cur.name); cur.next := D.first; D.first := cur
				END;
				key := cur.key
			END
		ELSE key := MIN(INTEGER)
		END 
  END GetKey;

(** Get name associated with a key/reference number. *)
	PROCEDURE GetName* (VAR D: Dictionary; key: INTEGER; VAR name: ARRAY OF CHAR);
		VAR cur: Entry;
	BEGIN
		IF D IS ListDict THEN
			cur := D(ListDict).first;
			WHILE (cur # NIL) & (cur.key # key) DO cur := cur.next END;
			IF cur = NIL THEN name[0] := 0X ELSE COPY(cur.name, name) END
		ELSE name[0] := 0X
		END
	END GetName;

(** Associate a name with a reference number. *)
  PROCEDURE PutName* (VAR D: Dictionary; key: INTEGER; name: ARRAY OF CHAR);
(* Note: D could be value parameter *)
		VAR cur: Entry;
	BEGIN
		IF D IS ListDict THEN
			IF key >= 0 THEN
				WITH D: ListDict DO
					cur := D.first;
					WHILE (cur # NIL) & (cur.key # key) DO cur := cur.next END;
					IF cur = NIL THEN
					NEW(cur); cur.key := key; cur.next := D.first; D.first := cur
					END;
					COPY(name, cur.name)
				END
			END
		END
  END PutName;

BEGIN LibBlockId := 0DBX;
	NEW(FirstLib);  FirstLib.next := NIL;
	Kernel.DisableTracing(SYSTEM.ADR(FirstLib^), SYSTEM.ADR(FirstLib.next));
	NEW(FirstAlias);  FirstAlias.next := NIL;
	Kernel.DisableTracing(SYSTEM.ADR(FirstAlias^), SYSTEM.ADR(FirstAlias.lib));
	stamp := MIN(LONGINT);
	NEW(NoObj);
	nofreg := 0;
	Register("Lib", NewLibrary)
END Objects.
 
(** Remarks:

1. Objects and Messages
Objects and the messages sent to them are both types in the Oberon system. Just as we can extend an object by defining an object-subtype, we can extend a message by defining a message sub-type. As root of the object and message type hierarchies we have the types Objects.Object and Object.ObjMsg respectively. We will refering to extensions of these types as Objects and Messages respectively. This way of organizing things allows us to send a message of any type to an object of any type (even when the receiving object might not make sense of the message). As an examples of an object we can mention the Frames of module Display (visual objects). Frames have a set of associated messages called frame messages (i.e. messages sent to frames). A base type called Display.FrameMsg is an extension of Object.ObjMsg and the base of the frame messages. The module Objects define the object messages, i.e. the messages that all objects understand. Objects are allocated on the heap and messages temporarily on the stack.

2. Message Handlers
Message handlers process the message sent to an object. A message handler is a procedure with the definition Objects.Handler. A message handler receives as first parameter the object the message is sent to, and as second parameter the message itself. The message handler does message type tests to discrimate between the different message types it receives, and acts accordingly to each message type (most of the actions are prescribed the messages defined in modules like Objects and Display). The message handler of a newly created object is "installed" in an object by assigning it to the field handle of the object. A typical handler might look as follows:

	PROCEDURE MyHandler(obj: Object; VAR M: ObjMsg);
	BEGIN
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				...
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				...
			END
		ELSE
			(* message not understood by handler. *)
		END
	END MyHandler;

To create a new object, we first have to introduce a new object type, allocate a new instance on the heap and attach the message handler:

	TYPE
		MyObj = POINTER TO MyObjDesc;
		MyObjDesc = RECORD (Objects.ObjDesc)	(* Extension of Objects.ObjDesc. *)
			A, B: LONGINT;	(* Object instance variables. *)
		END;
		
	PROCEDURE CreateObj;
	VAR obj: MyObj;
	BEGIN
		NEW(obj);	(* allocate a new object on the heap *)
		obj.handle := MyHandler;	(* attach the message handler. *)
	END CreateObj;
	
Here we created a new object type with two additional instance variables A and B. To open up access to the instance variables in the message handler, we will need to modify the message handler slightly:

	PROCEDURE MyHandler(obj: Object; VAR M: ObjMsg);
	BEGIN
		WITH obj: MyObj DO	(* Open up access to the instance variables of MyObj. *)
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					...
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					...
				END
			ELSE
				(* message not understood by handler. *)
			END
		END
	END MyHandler;

This change also means that MyHandler can only be safely attached to objects (or extensions) of type MyObj; attaching the handler to objects of other types will cause a runtime exception (trap) when trying to open access to the fields of MyObj. Sending a message to an object involves allocating it on the stack, filling out the message fields, and calling the object message handler. For example:

	VAR obj: MyObj;
	
	PROCEDURE GetName;
	VAR M: Objects.AttrMsg;	(* Allocate message on the stack. *)
	BEGIN
		M.id := Objects.get; M.name := "Name"; M.res := -1;	(* Fill out message fields *)
		obj.handle(obj, M);	(* Send message. *)
		Out.String(M.s); Out.Ln;	(* Process result. *)
	END GetName;
	
You are allowed to define new message types for your own objects, in a similar manner as shown in the message definitions above. Note how many of the messages have id fields; these indicate different sub-operations a message requests. The id values are declared per message as INTEGER constants at the beginning of the module.

3. Forwarding and Broadcasts
Objects may forward messages to other objects. This is typically done when an object cannot handle a message itself or does not even know the message. Sometimes messages are sent in such a way that each object does some handle of a message, and then forwards it anyway to all other objects it controls. This we call message broadcasting. Messages thus pass from one object to another in ways only known to the objects themselves. The route a message follows we call the message path.

4. Time stamps
During a message broadcast, more than one message path may lead to the same object, resulting in the object receiving a the message many times (i.e. exactly once for each message path). To allow an object to determine if it has already processed a message, each message that is broadcast is given a timestamp. The receiving object remembers the message timestamp in its field stamp, and can compare it against a later message received. Due to message broadcasts occuring during a message broadcast itself (i.e. recursive broadcasts), you should not assume that message arrive in time stamp sequence. The stamp is a LONGINT value incremented on each broadcast by the procedure Stamp.

5. The Message Thread
The message thread informs an object of the path a message followed to reach it, and can be used to implement path dependent behaviour. The dlink field in the ObjMsg points to the last forwarder of the message. The dlink field of the latter object contains the previous object in the path, and so onwards until the beginning of the path (the thread points backwards). Due to recursive message broadcasts the dlink field in the message and the objects themselves should be saved on the stack before the values are changed:

	(* Forward a message from one object to another. *)
	PROCEDURE SendMsg(from, to: Objects.Object; VAR M: Objects.ObjMsg);
	VAR p, p0; Objects.Object;
	BEGIN
		p := from.dlink; p0 := M.dlink; (* save *)
		from.dlink := M.dlink; (* hook sender in dlink chain *)
		M.dlink := from; (* set sender of the message *)
		to.handle(to, M);
		from.dlink := p; M.dlink := p0 (* restore *)
	END SendMsg;

A message sender may refuse to add itself to the message thread (for optimization purposes). This has no effect but to make it invisible to further recipients in the message path. The message thread is typically used in the display space (see module Display) to find out how a message travelled from the display root to an object located somewhere in the display space.

6. The slink field
The slink field links objects together in a list so that they can be passed around as a group. Never assume that the slink list remains the same before and after a message broadcast.

7. Libraries
Libraries are indexed collections of objects. An object belonging to a library is said to be bound to the library (otherwise it is free). When bound, an objects obtains an index or reference number (>= 0) in its library (and its lib and ref fields are set accordingly). The Objects module implements the standard object libraries. These allow you to store the library and its contents in an atomic action to disk. On disk, reference numbers instead of pointers are used to refer to objects. Thus pointers and reference numbers are swizzled (exchanged) when loading or storing libraries. The procedures Gadgets.ReadRef and Gadgets.WriteRef use the library mechanism to transparently read and write object pointers to disk. The library dictionary mechanism allows you to attach names to objects (more concretely to reference numbers). An object belonging to public library L and having the name O in the dictionary, is refered to as "L.O" (note the similarity with "M.P"). Sometimes the dictionary is also used to attach keys (< 0) to strings. Keys are used to save string space when storing libraries. Libraries are divided into public and private libraries. Public libraries are named (i.e. L.name # "") and are cached in memory on loading. The garbage collector will uncache a library automatically if it is not required any more. The Libraries.Panel allow you to manipulate the contents of public libraries. Private libraries are primarily used as a means to make objects persistent in documents and are never cached. The default public library file extension is "Lib". It is possible to add new types of libraries by registering new library extensions and the associated library generator.

8. The Object Messages
All objects should implement handlers for the so-called object messages defined in this module. The object messages are the LinkMsg (for structure building and exploration), the CopyMsg (for copying an object), the BindMsg (for binding an object to a library), the AttrMsg (for setting and getting attributes), the FileMsg (for loading and storing), and the FindMsg (for locating named objects).

9. The LinkMsg
The LinkMsg is used to link objects between each other i.e. setting a pointer in one object to point to another. The links must be identified by name. Most displayable gadgets have a "Model" link that points to a model gadget.

10. The CopyMsg
Shallow copy means copying an object but reusing its descendants, and deep copy means copying all objects reachable from a certain root object. Due to the DAG nature of the display space, the deep copy message arrives once or more times at an object, in which case it only should copy itself once to guarantee structure preserving copies. The following shows that an object should cache the first copy that it makes of itself in the dlink field, which is then returned on receiving the message a second time:

		VAR F0: Frame; (* the copy goes here *)
		
		IF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink	(* copy msg arrives again *)
				ELSE	(* first time copy message arrives *)
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyFrame(M, F, F0); M.obj := F0
				END
			END
		END
		
11. The BindMsg
The BindMsg is a request to an object to bind itself to a library. By convention, an object can migrate from library to library, except when bound to a public library. Binding allocates a reference number to an object which is conveniently used as a pointer alias between objects stored in a file.

	PROCEDURE BindObj(obj: Objects.Object; lib: Objects.Library);
	VAR ref: INTEGER; name: ARRAY 32 OF CHAR;
	BEGIN
		IF lib # NIL THEN 
			IF (obj.lib = NIL) OR (obj.lib.name[0] = 0X) & (obj.lib # lib) THEN (* free, or belongs to a private library *)
				lib.GenRef(lib, ref);	(* allocate reference number *)
				IF ref >= 0 THEN	(* successful *)
					lib.PutObj(lib, ref, obj);
				END
			END
		END
	END BindObj;

12. The AttrMsg
The attribute message is used to enumerate, set or retrieve an object attribute. The class field of the AttrMsg indicate what the type of an attribute is. Each object should have a Name attribute and a Gen attribute (both of type String). The name attribute refers to the intrinsic name of an object (it should not be confused with the name the object might have in a dictionary). Copying an object results in two objects with the same names. The FindMsg locates an object with a certain intrinsic name. The Gen attribute indicates the name of the object generator (in the form "M.P"). Calling the generator of an object results in the freshly created object attached to Objects.NewObj, from where it is picked up by commands like Gadgets.Insert.

13. The FileMsg
The FileMsg is a request to an object to write or read its state to or from a Rider. An object should always read and write the same number of bytes, otherwise traps may result. It is recommended to use version numbers to distinguish objects of different generations from each other and so allow for smooth upgrading to new file formats for older objects. The FileMsg is typically used when reading or writing a library from or to disk.

14. The FindMsg
The FindMsg is a request to an object to locate the object with the indicated intrinsic name. Should an object not know of an object with such a name, it should forward the message to all objects it controls (children). By convention, searching should be done in a bread-first manner between descendants of a container.

15. Keys
Each library has a dictionary of (key, name) pairs. The key is either positive or zero, in which case it is regarded as a reference number in the library (with associated object name), or negative, in which case it is simply a short way of refering to a string (an atom). The latter reduces the space used when the same string appears many times in a library file.

16. Dummies
Dummies are objects created in place of objects that cannot be loaded into memory (module missing). Pointers to Dummies are often set to NIL by the application itself.

17. Extended Libraries
It is possible to add new library types to the system. New types are distinguished by filename extensions that are registered by Objects.Register. The NewProc is called by Objects.ThisLibrary to create an empty instance of the new library type. The name field is filled in, after which the Load procedure of the library is called to load the library from disk. In accordance, the Store procedure stores the library under its name to disk. The LoadLibrary and StoreLibrary procedures implement the default behaviour for the standard object libraries.

*)