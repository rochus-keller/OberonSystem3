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

MODULE Directories;	(** portable *)		(* ps,   *)

IMPORT
	(*SYSTEM, Kernel32,*) FileDir, Files, (*Modules,*) Input, Strings, Display, Pictures, Display3, Printer, Printer3, Objects, Attributes, Texts, 
	Gadgets, Oberon, ListRiders, ListGadgets;

CONST
	(* drive types *)
	None = 1; Removable = 2; Fixed = 3; Remote = 4; CDROM = 5; RAMDisk = 6; Floppy = 7;
	FoldC = 8; FoldO = 9;
	Picts = 9;

	NoDataStr = "INVALID DATA";

TYPE
	Data = POINTER TO DataDesc;
	DataDesc = RECORD (ListRiders.StringDesc)
		pictNr: LONGINT
	END;

	Item = POINTER TO ItemDesc;
	ItemDesc = RECORD
		s: ARRAY 64 OF CHAR;	(* Data value *)
		key, pos, stamp, state: LONGINT;
		dsc, asc, next, prev: Item	(* asc: parent; dsc: first child (sentinel); next, prev: brothers *)
	END;
	
	Model* = POINTER TO ModelDesc;
	ModelDesc* = RECORD (Gadgets.ObjDesc)
		tail: Item;	(* top of tree (sentinel) *)
		mask: ARRAY 32 OF CHAR;	(* filename mask *)
		rootDir: FileDir.FileName;	(* root Directory *)
		key: LONGINT	(* Next unique-key *)
	END;
	
	Rider* = POINTER TO RiderDesc;
	RiderDesc* = RECORD (ListRiders.RiderDesc)
		item: Item	(* Rider's current item *)
	END;

VAR
	model: Model;	(* global used in Enum *)
	root: Item;	(* global used in Enum *)
	R: ListRiders.Rider;	(* global used in EnumForList *)
	writePath: BOOLEAN;	(* global used in EnumForList *)
	 
	mMethod: ListRiders.Method;
	vMethod: ListGadgets.Method;
	drvPicts: ARRAY Picts OF Pictures.Picture;
	maxW: INTEGER;

	drv: Objects.Object;
	StringHandler: Objects.Handler;
	(*task : Oberon.Task;*)

(*========== aux. procs ==========*)
(*
PROCEDURE IsDriveAvailable (drv: ARRAY OF CHAR): BOOLEAN;
BEGIN
	RETURN (drv[0] = "C") OR (Kernel32.GetDriveType(SYSTEM.ADR(drv)) > None)
END IsDriveAvailable;
*)

PROCEDURE IsOnlyDrive (path: ARRAY OF CHAR): BOOLEAN;
BEGIN RETURN (path[0] # 0X) & (path[1] = ":") & (path[2] = 0X)
END IsOnlyDrive;

PROCEDURE IsDirectory (path: ARRAY OF CHAR): BOOLEAN;
VAR attrs: LONGINT; res: BOOLEAN;
BEGIN
	RETURN FALSE
(*
	IF IsOnlyDrive(path) THEN res := IsDriveAvailable(path)
	ELSE
		attrs := Kernel32.GetFileAttributes(SYSTEM.ADR(path));
		IF attrs # -1 THEN res := Kernel32.Includes(attrs, Kernel32.FileAttributeDirectory);
		ELSE res := FALSE
		END
	END;
	RETURN res
*)
END IsDirectory;

PROCEDURE CheckPath (VAR path: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN
	IF (path[0] # 0X) & (path[1] = ":") THEN	(* path with dirve *)
		path[0] := CAP(path[0]);
		IF (path[2] = FileDir.PathChar) & (path[3] = 0X) THEN path[2] := 0X END
	END;
	i := 0; WHILE path[i] # 0X DO INC(i) END;
	WHILE (i > 0) & ~IsDirectory(path) DO
		REPEAT DEC(i) UNTIL (i = 0) OR (path[i] = FileDir.PathChar);
		path[i] := 0X
	END
END CheckPath;

PROCEDURE GetKey (obj: Model): LONGINT;
BEGIN INC(obj.key); RETURN obj.key - 1
END GetKey;

(*========== Item handling ==========*)
(* creates a new item *)
PROCEDURE NewItem (name: ARRAY OF CHAR; key: LONGINT): Item;
VAR n: Item;
BEGIN
	NEW(n); COPY(name, n.s); n.key := key; n.stamp := -1;
	n.next := n; n.prev := n; n.dsc := NIL; n.asc := NIL;
	RETURN n
END NewItem;

(* Insert item "n" after "item"  *)
PROCEDURE InsertItem (item, n: Item);
BEGIN
	n.next := item.next; n.prev := item; item.next.prev := n; item.next := n;
	n.pos := item.pos; n.asc := item.asc;
	WHILE n.key >= 0 DO INC(n.pos); n := n.next END
END InsertItem;

(*
(* FileDir.FileEnumerator. Global variable "model" has to be preset. *)
PROCEDURE * Enum (path, name: ARRAY OF CHAR; time, date, size: LONGINT; isDir: BOOLEAN);
VAR new, cur: Item;

	PROCEDURE CAPCompare (VAR s1, s2: ARRAY OF CHAR): INTEGER;
	VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE (s1[i] # 0X) & (s2[i] # 0X) & (CAP(s1[i]) = CAP(s2[i])) DO INC(i) END;
		RETURN ORD(CAP(s1[i])) - ORD(CAP(s2[i]))
	END CAPCompare;

BEGIN
	new := NewItem(name, GetKey(model));
	cur := root;
	IF isDir THEN
		new.dsc := NewItem("", -1); new.dsc.pos := -1; new.dsc.asc := new;
		REPEAT cur := cur.next UNTIL (cur = root) OR (cur.dsc = NIL) OR (CAPCompare(cur.s, name) > 0)
	ELSE
		REPEAT cur := cur.next UNTIL (cur = root) OR ((cur.dsc = NIL) & (CAPCompare(cur.s, name) > 0))
	END;
	InsertItem(cur.prev, new)
END Enum;
*)

PROCEDURE * Enum (name: ARRAY OF CHAR; time, date, size: LONGINT; VAR continue: BOOLEAN);
BEGIN
	InsertItem(root.prev, NewItem(name, GetKey(model)))
END Enum;

PROCEDURE BuildList (obj: Model; tail: Item; path, mask: ARRAY OF CHAR);
BEGIN
	model := obj; root := tail;
(*
	FileDir.EnumerateFiles(path, mask, FALSE, Enum);
*)
	FileDir.Enumerate(mask, FALSE, Enum);
	root := NIL; model := NIL
END BuildList;

(*========== Rider handling ==========*)
PROCEDURE SetItem (R: Rider; item: Item);
VAR d: Data; res: LONGINT;
BEGIN
	R.item := item; R.eol := item.key < 0; R.dsc := item.dsc # NIL;
	IF (R.d = NIL) OR ~(R.d IS Data) THEN NEW(d); R.d := d ELSE d := R.d(Data) END;
	COPY(item.s, d.s);
	IF IsOnlyDrive(item.s) THEN	(* item is a drive *)
		IF CAP(item.s[0]) = "C" THEN res := Fixed
		ELSIF CAP(item.s[0]) < "C" THEN res := Floppy
		ELSE
(*
			res := Kernel32.GetDriveType(SYSTEM.ADR(item.s));
			IF res > RAMDisk THEN res := Fixed ELSIF res < None THEN res := None END
*)
			res := None
		END;
		d.pictNr := res
	ELSIF R.dsc THEN d.pictNr := FoldC
	ELSE d.pictNr := -1
	END
END SetItem;

(* Get the current item's key *)
PROCEDURE * Key (R: ListRiders.Rider): LONGINT;
BEGIN RETURN R(Rider).item.key
END Key;

(* Position rider R on the item having the given key *)
PROCEDURE * Seek (R: ListRiders.Rider; key: LONGINT);

	PROCEDURE Traverse (this: Item; key: LONGINT): Item;
	VAR found: Item;
	BEGIN
		this := this.next;
		WHILE (this.key >= 0) & (this.key # key) DO
			IF this.dsc # NIL THEN
				found := Traverse(this.dsc, key);
				IF found.key = key THEN RETURN found END
			END;
			this := this.next
		END;
		RETURN this
	END Traverse;

BEGIN
	SetItem(R(Rider), Traverse(R.base(Model).tail, key))
END Seek;

(* Get current position of the rider *)
PROCEDURE * Pos (R: ListRiders.Rider): LONGINT;
BEGIN RETURN R(Rider).item.pos
END Pos;

(* Position rider R on the item having the given pos *)
PROCEDURE * Set (R: ListRiders.Rider; pos: LONGINT);
VAR n : Item;
BEGIN
	WITH R: Rider DO
		n := R.item;
		ASSERT(n # NIL);
		IF n.pos > pos THEN REPEAT n := n.prev UNTIL (n.pos = pos) OR (n.key < 0)
		ELSIF n.pos < pos THEN REPEAT n := n.next UNTIL (n.pos = pos) OR (n.key < 0)
		END;
		SetItem(R, n)
	END
END Set;

(* Insert data at the current position of R. This Method is disabled *)
PROCEDURE * Write (R: ListRiders.Rider; d: ListRiders.Data);
END Write;

(* Link the item at the position of linkR to the current position of R. This Method is disabled *)
PROCEDURE * WriteLink (R, linkR: ListRiders.Rider);
END WriteLink;

(* Delete item at the current position of R. This Method is disabled *)
PROCEDURE * DeleteLink (R, linkR: ListRiders.Rider);
END DeleteLink;

(* Get a rider working on the descendants of the item on the position of R. If old is NIL, then a new rider
	is allocated. old is recycled if not NIL *)
PROCEDURE * Desc (R, old: ListRiders.Rider): ListRiders.Rider;
VAR new: Rider; base: Model; item: Item; path: FileDir.FileName; pos: LONGINT;

	PROCEDURE MakePath (item: Item; VAR path: ARRAY OF CHAR; VAR pos: LONGINT);
	VAR i: LONGINT;
	BEGIN
		IF item.asc # NIL THEN MakePath(item.asc, path, pos) END;
		i:= 0; 
		WHILE item.s[i] # 0X DO path[pos] := item.s[i]; INC(pos); INC(i) END;
		path[pos] := "/"; INC(pos); path[pos] := 0X
	END MakePath;

BEGIN
	IF old = NIL THEN NEW(new) ELSE new := old(Rider) END;
	WITH R: Rider DO
		new.do := R.do; new.base := R.base;
		IF R.item.dsc # NIL THEN
			item := R.item.dsc;
			IF item.next = item THEN
				path := ""; pos := 0;
				(*MakePath(R.item, path, pos);*)
				base := R.base(Model);
				BuildList(base, item, path, base.mask);
			END;
			item := item.next
		ELSE item := R.item
		END;
		SetItem(new, item)
	END;
	RETURN new
END Desc;

(* Get stamp value of the item at the current position of R *)
PROCEDURE * GetStamp (R: ListRiders.Rider): LONGINT;
BEGIN RETURN R(Rider).item.stamp
END GetStamp;

(* Set stamp value of the item at the current position of R *)
PROCEDURE * SetStamp (R: ListRiders.Rider; stamp: LONGINT);
BEGIN R(Rider).item.stamp := stamp
END SetStamp;

(* Get the state of the current item *)
PROCEDURE * State (R: ListRiders.Rider): LONGINT;
BEGIN RETURN R(Rider).item.state
END State;

(* Set the state of the current item *)
PROCEDURE * SetState (R: ListRiders.Rider; s: LONGINT);
BEGIN R(Rider).item.state := SHORT(s)
END SetState;

PROCEDURE ConnectRider (R: Rider; base: Model);
BEGIN R.do := mMethod; R.base := base; SetItem(R, base.tail.next)
END ConnectRider;

(*========== Model handling ==========*)
PROCEDURE ^ InitModel* (obj: Model; rootDir, mask: ARRAY OF CHAR);

(** Update the model (not yet implemented) *)
PROCEDURE UpdateModel* (obj: Model);
BEGIN
	InitModel(obj, obj.rootDir, obj.mask);
END UpdateModel;

PROCEDURE ModelAttr (obj: Model; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN COPY("Directories.New", M.s); M.class := Objects.String; M.res := 0
		ELSIF M.name = "Mask" THEN COPY(obj.mask, M.s); M.class := Objects.String; M.res := 0
		ELSIF M.name = "RootDir" THEN COPY(obj.rootDir, M.s); M.class := Objects.String; M.res := 0
		ELSE Gadgets.objecthandle(obj, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Mask" THEN
			IF (M.class = Objects.String) THEN
				IF M.s # obj.mask THEN
					COPY(M.s, obj.mask); UpdateModel(obj)
				END;
				M.res := 0
			END
		ELSIF M.name = "RootDir" THEN
			IF M.class = Objects.String THEN
				IF ~Strings.CAPCompare(M.s, obj.rootDir) THEN
					COPY(M.s, obj.rootDir); UpdateModel(obj)
				END;
				M.res := 0
			END
		ELSE Gadgets.objecthandle(obj, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Mask"); M.Enum("RootDir"); Gadgets.objecthandle(obj, M)
	ELSE Gadgets.objecthandle(obj, M)
	END
END ModelAttr;

(** Standard handler for directory models *)
PROCEDURE ModelHandler* (obj: Objects.Object; VAR M: Objects.ObjMsg);
VAR R: Rider;
BEGIN
	WITH obj: Model DO
		IF M IS Objects.AttrMsg THEN
			ModelAttr(obj, M(Objects.AttrMsg))
		ELSIF M IS Objects.CopyMsg THEN
			M(Objects.CopyMsg).obj := obj	(* Too heavyweight to copy ==> returning myself*)
		ELSIF M IS ListRiders.ConnectMsg THEN
			NEW(R); ConnectRider(R, obj); M(ListRiders.ConnectMsg).R := R
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.load THEN
					Files.ReadString(M.R, obj.mask);
					Files.ReadString(M.R, obj.rootDir);
					UpdateModel(obj)
				ELSIF M.id = Objects.store THEN
					Files.WriteString(M.R, obj.mask);
					Files.WriteString(M.R, obj.rootDir)
				END;
				Gadgets.objecthandle(obj, M)
			END
		ELSE Gadgets.objecthandle(obj, M)
		END
	END
END ModelHandler;

(** Initialize a directory model *)
PROCEDURE InitModel* (obj: Model; rootDir, mask: ARRAY OF CHAR);
VAR tail: Item; i: LONGINT; drvName: ARRAY 4 OF CHAR;

	PROCEDURE NewDrv (name: ARRAY OF CHAR);
	VAR drv, dsc: Item;
	BEGIN
		drv := NewItem(name, GetKey(obj));
		dsc := NewItem("", -1); dsc.pos := -1; dsc.asc := drv;
		drv.dsc := dsc;
		InsertItem(tail.prev, drv)
	END NewDrv;

BEGIN
	obj.handle := ModelHandler; obj.key := 0;
	COPY(rootDir, obj.rootDir); CheckPath(obj.rootDir);
	COPY(mask, obj.mask);
	tail := NewItem("", -1); tail.pos := -1; obj.tail := tail;
	IF obj.rootDir = "" THEN
(*
		COPY("A:", drvName);
		FOR i := 0 TO 25 DO
			drvName[0] := CHR(ORD("A") + i);
			IF IsDriveAvailable(drvName) THEN NewDrv(drvName) END
		END
*)
		NewDrv("")
	ELSE NewDrv(obj.rootDir)
	END
END InitModel;

(** Generator for directory models *)
PROCEDURE New*;
VAR obj: Model;
BEGIN NEW(obj); InitModel(obj, "", "*"); Objects.NewObj := obj
END New;

(* ------------ view stuff ------------ *)

PROCEDURE * FormatLine (F: ListGadgets.Frame; R: ListRiders.Rider; L: ListGadgets.Line);
VAR d: Data; pict: Pictures.Picture;
BEGIN
	IF (R.d # NIL) & (R.d IS Data) THEN
		d := R.d(Data);
		Display3.StringSize(d.s, F.fnt, L.w, L.h, L.dsr);
		IF d.pictNr >= None THEN
			pict := drvPicts[d.pictNr-1];
			IF (pict # NIL) & (pict.height + 2 > L.h) THEN L.h := pict.height + 2 END
		END
	ELSE
		Display3.StringSize(NoDataStr, F.fnt, L.w, L.h, L.dsr)
	END;
	L.dx := maxW + 2 + L.lev*F.tab
END FormatLine;

PROCEDURE * DisplayLine (F: ListGadgets.Frame; Q: Display3.Mask; x, y, w, h: INTEGER; R: ListRiders.Rider; L: ListGadgets.Line);
VAR d: Data; pict: Pictures.Picture; str: ARRAY 64 OF CHAR;
BEGIN
	Display3.ReplConst(Q, F.backC, x, y, w, h, Display.replace);
	INC(x, L.lev*F.tab);
	IF (R.d # NIL) & (R.d IS Data) THEN
		d := R.d(Data);
		IF d.pictNr >= None THEN
			IF (d.pictNr = FoldC) & ~L.folded THEN INC(d.pictNr) END;
			pict := drvPicts[d.pictNr-1];
			Display3.Pict(Q, pict, 0, 0, pict.width, pict.height, x, y + 2, Display.replace)
		END;
		COPY(d.s, str)
	ELSE str := NoDataStr
	END;
	INC(x, maxW + 2);
	Display3.String(Q, F.textC, x, y + L.dsr, F.fnt, str, Display.paint)
END DisplayLine;

PROCEDURE P (x: LONGINT): INTEGER;
BEGIN RETURN SHORT((x * Display.Unit) DIV Printer.Unit)
END P;

PROCEDURE * PrintFormatLine (F: ListGadgets.Frame; R: ListRiders.Rider; L: ListGadgets.Line);
VAR d: Data; pict: Pictures.Picture;
BEGIN
	IF (R.d # NIL) & (R.d IS Data) THEN
		d := R.d(Data);
		Printer3.StringSize(d.s, F.fnt, L.w, L.h, L.dsr);
		IF d.pictNr >= None THEN
			pict := drvPicts[d.pictNr-1];
			IF (pict # NIL) & (P(pict.height + 2) > L.h) THEN L.h := P(pict.height + 2) END
		END
	ELSE
		Printer3.StringSize("INVALID DATA", F.fnt, L.w, L.h, L.dsr)
	END;
	L.dx := P(maxW + 2 + L.lev*F.tab)
END PrintFormatLine;

PROCEDURE * PrintLine (F: ListGadgets.Frame; Q: Display3.Mask; x, y, w, h: INTEGER; R: ListRiders.Rider; L: ListGadgets.Line);
VAR d: Data; pict: Pictures.Picture; str: ARRAY 64 OF CHAR;
BEGIN
	Printer3.ReplConst(Q, F.backC, x, y, w, h, Display.replace);
	INC(x, P(L.lev*F.tab));
	IF (R.d # NIL) & (R.d IS Data) THEN
		d := R.d(Data);
		IF d.pictNr >= None THEN
			IF (d.pictNr = FoldC) & ~L.folded THEN INC(d.pictNr) END;
			pict := drvPicts[d.pictNr-1];
			Printer3.Pict(Q, pict, x, y+2, P(pict.width), P(pict.height), Display.replace)
		END;
		COPY(d.s, str)
	ELSE str := NoDataStr
	END;
	INC(x, P(maxW + 2));
	Printer3.String(Q, F.textC, x, y + L.dsr, F.fnt, str, Display.paint)
END PrintLine;

PROCEDURE * GadgetHandler (F: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	IF M IS Objects.AttrMsg THEN
		WITH M: Objects.AttrMsg DO
			IF (M.id = Objects.get) & (M.name = "Gen") THEN
				M.class := Objects.String; M.s := "Directories.NewDirList"; M.res := 0
			ELSE ListGadgets.FrameHandler(F, M)
			END
		END
	ELSE ListGadgets.FrameHandler(F, M)
	END
END GadgetHandler;

PROCEDURE NewDirList*;
VAR F: ListGadgets.Frame;
BEGIN
	NEW(F); ListGadgets.InitFrame(F);
	F.handle := GadgetHandler; F.do := vMethod;
	F.tab := 8;
	(*INCL(F.state0, ListGadgets.inclpath);*) INCL(F.state0, ListGadgets.extendsel);
	Objects.NewObj := F
END NewDirList;

(* ------------ working dir. model ------------ *)

(*
PROCEDURE *TaskHandler (me : Oberon.Task);
VAR old, s: ARRAY 64 OF CHAR;
BEGIN
	FileDir.GetWorkingDirectory(s);
	Attributes.GetString(drv, "Value", old);
	IF old # s THEN
		Attributes.SetString(drv, "Value", s); Gadgets.Update(drv)
	END;
	me.time := Oberon.Time() + Input.TimeUnit DIV 2
END TaskHandler;
*)

PROCEDURE *HandleDrv (obj: Objects.Object; VAR M: Objects.ObjMsg);	
BEGIN
	IF M IS Objects.CopyMsg THEN 
			M(Objects.CopyMsg).obj := drv;
	ELSIF M IS Objects.AttrMsg THEN
		WITH M : Objects.AttrMsg DO
			IF (M.id = Objects.get) & (M.name = "Gen") THEN M.s := "Directories.NewDrv" 
			ELSIF (M.id = Objects.set) & (M.name = "Value") THEN (* skip *)
			ELSE StringHandler(obj, M)
			END
		END
	ELSE StringHandler(obj,M)
	END
END HandleDrv;

PROCEDURE NewDrv*;
BEGIN Objects.NewObj := drv
END NewDrv;

(* ------------ aux. Commands ------------ *)
(*
PROCEDURE * EnumForList (path, name: ARRAY OF CHAR; time, date, size: LONGINT; isDir: BOOLEAN);
VAR d: ListRiders.String; full: ARRAY 256 OF CHAR; i, j: LONGINT;
BEGIN
	IF ~isDir THEN
		NEW(d);
		IF writePath THEN
			i := 0; j := 0;
			WHILE path[j] # 0X DO full[i] := path[j]; INC(i); INC(j) END;
			full[i] := FileDir.PathChar; INC(i);
			j := 0;
			WHILE name[j] # 0X DO full[i] := name[j]; INC(i); INC(j) END;
			full[i] := 0X;
			FileDir.RelFileName(full, d.s)
		ELSE
			COPY(name, d.s)
		END;
		R.do.Write(R, d)
	END
END EnumForList;
*)

PROCEDURE * EnumForList (name: ARRAY OF CHAR; time, date, size: LONGINT; VAR continue: BOOLEAN);
VAR d: ListRiders.String;
BEGIN
	NEW(d);
	COPY(name, d.s);
	R.do.Write(R, d)
END EnumForList;

(** Finds all the filenames in the search path that match a specified pattern and inserts them
	into a list model gadget (ListModel, Tree or Dag) named <Objname> in the current context. 
	If the option p is specified, the filenames are prefixed with their relative path in the current
	working directory.
	Usage: Directories.Directory [\p] "<pattern>" <Objname> ~
*)
PROCEDURE Directory*;
VAR obj: Objects.Object; i: LONGINT; mask: ARRAY 32 OF CHAR; C: ListRiders.ConnectMsg; S: Texts.Scanner;
BEGIN
	writePath := FALSE;
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN
		S.s := ""; Texts.Scan(S);
		i := 0;
		WHILE S.s[i] # 0X DO writePath := writePath OR (S.s[i] = "p"); INC(i) END;
		Texts.Scan(S)
	END;
	IF S.class IN {Texts.Name, Texts.String}  THEN
		COPY(S.s, mask); Texts.Scan(S);
		IF S.class IN {Texts.Name, Texts.String}  THEN
			obj := Gadgets.FindObj(Gadgets.context, S.s);
			IF obj # NIL THEN
				C.R := NIL; Objects.Stamp(C); obj.handle(obj, C);
				IF C.R # NIL THEN
					R := C.R;
					WHILE ~R.eol DO R.do.DeleteLink(NIL, R) END;
					R.do.Set(R, 0);
(*
					FileDir.EnumerateFiles("", mask, FALSE, EnumForList);
*)
					FileDir.Enumerate(mask, FALSE, EnumForList);
					Gadgets.Update(obj);
					R := NIL	(* for carbage collection *)
				END
			END
		END
	END
END Directory;

(* ------------ aux. Porcs ------------ *)
PROCEDURE GetPicts;

	PROCEDURE Set (i: LONGINT; pict: Objects.Object);
	BEGIN
		DEC(i);
		IF (pict = NIL) OR ~(pict IS Pictures.Picture) THEN drvPicts[i] := NIL
		ELSE
			WITH pict: Pictures.Picture DO
				drvPicts[i] := pict;
				IF maxW < pict.width THEN maxW := pict.width END
			END
		END
	END Set;

BEGIN
	maxW := 0;
	Set(None, Gadgets.FindPublicObj("Symbols.None"));
	Set(Removable, Gadgets.FindPublicObj("Symbols.Removable"));
	Set(Fixed, Gadgets.FindPublicObj("Symbols.Fixed"));
	Set(Remote, Gadgets.FindPublicObj("Symbols.Remote"));
	Set(CDROM, Gadgets.FindPublicObj("Symbols.CDROM"));
	Set(RAMDisk, Gadgets.FindPublicObj("Symbols.RAMDisk"));
	Set(Floppy, Gadgets.FindPublicObj("Symbols.Floppy"));
	Set(FoldC, Gadgets.FindPublicObj("Symbols.FoldC"));
	Set(FoldO, Gadgets.FindPublicObj("Symbols.FoldO"))
END GetPicts;

(*
PROCEDURE Cleanup;
BEGIN
	Oberon.Remove(task)
END Cleanup;
*)

BEGIN
	NEW(mMethod);
	mMethod.Key := Key; mMethod.Seek := Seek; mMethod.Pos := Pos; mMethod.Set := Set;
	mMethod.State := State; mMethod.SetState := SetState;
	mMethod.Write := Write; mMethod.WriteLink := WriteLink; mMethod.DeleteLink := DeleteLink;
	mMethod.Desc := Desc; mMethod.GetStamp := GetStamp; mMethod.SetStamp := SetStamp;

	NEW(vMethod);
	vMethod^ := ListGadgets.methods^;
	vMethod.Format := FormatLine; vMethod.Display := DisplayLine;
	vMethod.PrintFormat := PrintFormatLine; vMethod.Print := PrintLine;

	(*NEW(task); task.handle := TaskHandler; task.time := 0; task.safe := TRUE; Oberon.Install(task);*)
	drv := Gadgets.CreateObject("String"); StringHandler := drv.handle; drv.handle := HandleDrv;
	(*Modules.InstallTermHandler(Cleanup);*)
	GetPicts
END Directories.

Gadgets.Insert TextFields.NewTextField Directories.NewDrv ~
Gadgets.Insert Directories.NewDirList Directories.New ~

System.Free Directories ~
