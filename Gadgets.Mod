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

MODULE Gadgets;	(** portable *) (*  , jm 18.1.95*)

(**The Gadgets module forms the basis of the Gadgets system. It defines the most important types, provide default message handlers and often used utility procedures. In addition, a few gadget specific messages are defined.
*)

(*
	jm 9.2.93 - Attributes for abstract objects
		- object name belongs intrinsically to objects
		- support for non gadget frames removed
	jm 10.2.93 - support for empty object names
		- fixed attributes for abstract objects
	jm 11.2.93 - Display.ControlMsg
		- moved mask messages to Display3
	jm 15.3.93 - Better creation of default clip masks
	jm 16.3.93 - ReadRef bug
	jm 17.3.93 - Add context to executor dlink when executing a command
	jm 23.2.93 - Fixed semantics of Oberon.Par.obj & Oberon.Par.frame
	jm 24.2.93 - Warning thrown out
	jm 24.2.93 - Gadgets.Execute hack
	jm 2.3.93 - Notes removed
	jm 3.3.93 - ExecuteAttr corrected
	jm 10.3.93 - fix version message
	jm 11.3.93 - Call error correction
	7.4.93 - Introduced editing platform code
	8.4.93 - removed edit platform code
	23.7.93 - fixed copy object
	17.09.93 15:09:48 - Find message
	06.01.94 - improved handling of UpdateMsg slightly
	29.3.94 - Broadcast removed
		- Fixed UpArrow macro
	5.4.94 - fixed unnaming of objects in public libraries
	19.4.94 - added aliasing support to Insert, removed aliasing from Attributes.Scanner
	19.4.94 - Improved lookup macro
	20.4.94 - added visible constant
	27.5.94 - improved track highlight in track frame
	29.6.94 - Added alias support to Change*
	14.7.94 - added some more debug tests for invalid masks, most are deactivated now, search for debug
	18.7.94 - changed object naming
	3.11.94 - unchanged change of 18.7.94
	7.11.94 - unchanged change of 18.7.94
	8.11.94 - changed rules in IsLocked
	
	29.11.94
		- removed optimization flags from Gadgets
		- removed nomove, noresize, nodelete, noselect flags from Gadgets
		- renamed lockchildren to locked
	30.11.94
		- added lockedsize (same as noresize before)
		- renamed locked to lockedcontents
	6.12.94 - added GetSelection
	14.12.94 - CopyObject implemented
	15.12.94 - removed col from Gadgets.Frame
	16.12.94 - removed selection bug
	21.12.94 - When no attribute exists on Objects.AttrMsg "get", nothing is returned. Previously
		an empty string was returned.
	3.8.95 - load aliases from the Registry
	6.12.95 - added ClipMask to Gadgets.ViewDesc (thanks ps) (changes the symbol file)
	15.12.95 - CreateObject now uses Modules.resMsg
	8.5.96 - fixed bug in Recursive
	20.5.96 - CreateObject now understands aliases (ps - 20.5.96)
	6.6.96 - changed Execute (light weight)
	19.6.96 - fixed bug in new Execute
	10.7.96 - added deep parameter to GetPublicObject (* ejz - 10.7.96 *)
	4.8.96 - changed printer mask scaling to Printer.Frame
	14.08.96 pjm - fix in UpArrowMacro for selected objects
	18.2.97 - added ModifySize and Consume
*)

IMPORT
	Objects, Display, Display3, Effects, Oberon, Texts, Input, Files, Modules,
	Printer, Printer3, Attributes, Links, Viewers, Strings;
	
CONST
	(** Priority message id's. *)
	top* = 0;		(** Move gadget to the front. *)
	bottom* = 1;		(** Move gadget to the back. *)
	visible* = 2;		(** Move gadget to the front if not completely visible. *)
	
	(** Gadget Frame states. *)
	selected* = 0;		(** Selected or not. *)
	lockedsize* = 2;		(** Gadget prefers a fixed W, H. *)
	transparent* = 4;		(** Transparent or not. *)
	lockedcontents* = 10;		(** All direct descendants are locked. *)

	left = 2; middle = 1; right = 0;
	
TYPE
	(** Message broadcast in the display space to indicate that "obj" has changed. Normally used for updating model gadgets, although obj can be a list of gadget frames belonging to the same container. In this case all of the frames are to be displayed. This message is used by the Inspector to indicate that an attribute value has changed. *)
	UpdateMsg* = RECORD (Display.FrameMsg)
		obj*: Objects.Object;
	END;

	(** Message broadcast in the display space to indicate that the destination frame F wants to change its overlapping 	priority. *)
	PriorityMsg* = RECORD (Display.FrameMsg)
		id*: INTEGER;	(** Top, bottom, visible. *)
		passon*: BOOLEAN;	(** Indication if a whole tree of containers should be changed in priority. *)
	END;
	
	CmdMsg* = RECORD (Objects.ObjMsg)
		cmd*: ARRAY 128 OF CHAR; (* Information to be passed, command to be executed; result returned. *)
		res*: INTEGER; (* result code *)
	END;

	(** Base type of the Model gadgets *)
	Object* = POINTER TO ObjDesc;
	ObjDesc* = RECORD (Objects.ObjDesc)
		attr*: Attributes.Attr;	(** Attribute list. Private variable. *)
		link*: Links.Link;  (** Link list. Private variable. *)
	END;
	
	(** Base type of the visual gadgets *)
	Frame* = POINTER TO FrameDesc;
	FrameDesc* = RECORD (Display.FrameDesc)
		attr*: Attributes.Attr;	(** Attribute list. Private variable. *)
		link*: Links.Link;  (** Link list. Private variable. *)
		state*: SET;
		mask*: Display3.Mask;	(**  Cached display mask. Can be NIL to indicate no/invalid mask. *)
		obj*: Objects.Object;	(** Model object, if any. *)
	END;
	
	(** Base type of the camera-view gadgets. *)
	View* = POINTER TO ViewDesc;
	ViewDesc* = RECORD (FrameDesc)
		absX*, absY*: INTEGER;	(** Absolute screen position at last message forward to descendants. *)
		border*: INTEGER;	(** Border width for clipping. *)
		
		(** Install own clipping to display/printer mask here if view has an irregular outline. Otherwise set to NIL. *)
		ClipMask*: PROCEDURE (v: View; M: Display3.Mask; ondisplay: BOOLEAN);
	END;
	
	(** Calculate a mask for gadget G positioned at X, Y in the context dlink. *)
	MakeMaskHandler* = PROCEDURE (G: Frame; X, Y: INTEGER; dlink: Objects.Object; VAR M: Display3.Mask);
	
	RecursiveMsg = RECORD (Display.FrameMsg) END;
	
	Stack = RECORD
		Mdlink, Fdlink: Objects.Object;
		absX, absY: INTEGER;
	END;

CONST
	nameLen = 32; valueLen = 64;
	
TYPE
	Alias = POINTER TO AliasDesc;
	AliasDesc = RECORD
		name: ARRAY nameLen OF CHAR;
		value: ARRAY valueLen OF CHAR;
		next: Alias;
	END;

VAR
	framehandle*: Objects.Handler;	(** Default message handler for visual gadgets. *)
	objecthandle*: Objects.Handler;	(** Default message handler for Model gadgets. *)
	MakeMask*: MakeMaskHandler;	(** Calculates the current display mask of a visual gadget. *)
	MakePrinterMask*: MakeMaskHandler;	(** Calculates the current printer mask of a visual gadget. *)
	
	(** The following fields are used for parameter transfer during command execution. *)
	context*: Objects.Object;	(** Context/parent of a gadget executing the command *)
	executorObj*: Objects.Object;	(** Gadget executing the command. Same as Oberon.Par.obj. *)
	senderObj*: Objects.Object;	(** Initiator of a drag and drop operation i.e. the gadget being dropped. *)
	receiverObj*: Objects.Object;	(** Receiver of a dropped gadget. Often same as executorObj.  *)
	
	aliases: Alias;
	par: Oberon.ParList;
	emptyText: Texts.Text;
	W, WW, mW: Texts.Writer;	
	recurse, uparrowdone, verbose: BOOLEAN;
	pMask: Display3.Mask; tmpX, tmpY: INTEGER;
	
(* Misc *)

PROCEDURE Log;
BEGIN Texts.Append(Oberon.Log, W.buf); END Log;

PROCEDURE Push(VAR S: Stack; F: View; VAR M: Display.FrameMsg);
BEGIN
	(* save old variables *)
	S.Fdlink := F.dlink; S.Mdlink := M.dlink; S.absX := F.absX; S.absY := F.absY;
	F.dlink := M.dlink; M.dlink := F
END Push;

PROCEDURE Pop(VAR S: Stack; F: View; VAR M: Display.FrameMsg);
BEGIN
	M.dlink := S.Mdlink; F.dlink := S.Fdlink; F.absX := S.absX; F.absY := S.absY
END Pop;

(* general purpose *)

(** Is the context/parent of the frame F locked ? *)
PROCEDURE IsLocked*(F: Frame; dlink: Objects.Object): BOOLEAN;
VAR A: Objects.AttrMsg;
BEGIN
	IF dlink # NIL THEN
		IF dlink IS Frame THEN RETURN lockedcontents IN dlink(Frame).state
		ELSIF dlink.handle # NIL THEN (* not a frame *)
			A.id := Objects.get; A.name := "Locked"; A.res := -1; dlink.handle(dlink, A);
			RETURN (A.res >= 0) & (A.class = Objects.Bool) & A.b
		ELSE RETURN FALSE
		END
	ELSE RETURN FALSE
	END
END IsLocked;

(** Is the mouse located inside the work area of a gadget (i.e. excluding the control areas)? *)
PROCEDURE InActiveArea*(F: Frame; VAR M: Oberon.InputMsg): BOOLEAN;
VAR x, y, w, h: INTEGER;
BEGIN
	x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
	IF Effects.Inside(M.X, M.Y, x, y, w, h) & ~(selected IN F.state) THEN
		IF IsLocked(F, M.dlink) THEN RETURN TRUE
		ELSIF Effects.InBorder(M.X, M.Y, x, y, w, h) THEN RETURN FALSE
		ELSE RETURN TRUE
		END
	ELSE RETURN FALSE
	END
END InActiveArea;

(** Returns the name of of obj. Sends an Objects.AttrMsg behind the scenes. *)
PROCEDURE GetObjName*(obj: Objects.Object; VAR name: ARRAY OF CHAR);
VAR A: Objects.AttrMsg;
BEGIN
	name[0] := 0X;
	A.id := Objects.get; COPY("Name", A.name); A.res := -1; A.s[0] := 0X;
	obj.handle(obj, A);
	IF (A.res >= 0) & (A.class = Objects.String) THEN COPY(A.s, name) END
END GetObjName;

(** Name object obj. Sends an Objects.AttrMsg behind the scenes. *)
PROCEDURE NameObj*(obj: Objects.Object; name: ARRAY OF CHAR);
VAR A: Objects.AttrMsg;
BEGIN
	A.id := Objects.set; COPY("Name", A.name); Objects.Stamp(A); A.class := Objects.String; A.res := -1; COPY(name, A.s);
	obj.handle(obj, A);
END NameObj;

(** Search for the object "O" in the public library "L.Lib" wherename is specified as "L.O". *)
PROCEDURE FindPublicObj*(name: ARRAY OF CHAR): Objects.Object; (* Lib.obj format, assumes .Lib extension *)
VAR obj: Objects.Object; libname, objname: ARRAY 64 OF CHAR; i, j, k, ref: INTEGER; lib: Objects.Library;
BEGIN
	obj := NIL; i := 0; j := 0;
	WHILE (name[i] # ".") & (name[i] # 0X) DO libname[j] := name[i]; INC(j); INC(i); END;
	IF name[i] = 0X THEN RETURN NIL END;
	libname[j] := 0X; k := j; INC(i); j := 0;
	WHILE (name[i] # " ") & (name[i] # 0X) DO objname[j] := name[i]; INC(j); INC(i); END;
	objname[j] := 0X;
	libname[k] := "."; libname[k+1] := "L"; libname[k+2] := "i"; libname[k+3] := "b"; libname[k+4] := 0X;
	lib := Objects.ThisLibrary(libname);
	IF lib # NIL THEN
		Objects.GetRef(lib.dict, objname, ref);
		IF ref # MIN(INTEGER) THEN lib.GetObj(lib, ref, obj); END
	END;
	RETURN obj;
END FindPublicObj;

(** Search for object named name in context. *)
PROCEDURE FindObj*(context: Objects.Object; name: ARRAY OF CHAR): Objects.Object;
VAR obj: Objects.Object; M: Objects.FindMsg;
BEGIN
	obj := NIL;
	IF context # NIL THEN (* search by find message *)
		M.obj := NIL; COPY(name, M.name); context.handle(context, M);
		obj := M.obj
	END;
	RETURN obj
END FindObj;

(** Sets new W and H to (offscreen) frame F. *)
PROCEDURE ModifySize* (F: Display.Frame; W, H: INTEGER);
VAR M: Display.ModifyMsg;
BEGIN
	IF (F # NIL) & ((F.W # W) OR (F.H # H)) THEN
		M.id := Display.extend; M.mode := Display.state; M.F := F;
		M.X := F.X; M.Y := F.Y + F.H - H; M.W := W; M.H := H;
		M.dW := W - F.W; M.dH := H - F.H; M.dX := 0; M.dY := -M.dH;
		M.dlink := NIL; M.x := 0; M.y := 0; M.res := -1; Objects.Stamp(M);
		F.handle(F, M)
	END
END ModifySize;

(** Inserts the frame f into container F at (u, v). (u, v) is relative to upper left corner of F. *)
PROCEDURE Consume* (F, f: Frame; u, v: INTEGER);
VAR C: Display.ConsumeMsg;
BEGIN
	IF (F # NIL) & (f # NIL) THEN
		f.slink := NIL;
		C.id := Display.drop; C.F := F;
		C.res := -1; C.dlink := NIL; C.x := 0; C.v := 0;
		C.u := u; C.v := v; C.obj := f;
		F.handle(F, C)
	END
END Consume;

(** Returns a deep or shallow copy of object obj, depending on parameter deep *) 
PROCEDURE Clone*(obj: Objects.Object; deep: BOOLEAN): Objects.Object;
VAR C: Objects.CopyMsg;
BEGIN
	C.obj := NIL;
	IF obj # NIL THEN
		IF deep THEN C.id := Objects.deep ELSE C.id := Objects.shallow END;
		Objects.Stamp(C); C.dlink := NIL; obj.handle(obj, C)
	END;
	RETURN C.obj
END Clone;

(* --- Recursion checking --- *)

PROCEDURE *RecursiveHandler(obj: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN IF ~(M IS Display3.UpdateMaskMsg) THEN recurse := TRUE END;
END RecursiveHandler;

(** Check if a message loop would be created should newchild be inserted in the container parent. Sends a dummy message behind the scenes. *)
PROCEDURE Recursive*(parent, newchild: Objects.Object): BOOLEAN;
VAR old: Objects.Handler; M: RecursiveMsg;
BEGIN
	old := parent.handle; M.dlink := NIL; M.F := NIL; M.x := 0; M.y := 0; M.res:= -1;
	parent.handle := RecursiveHandler; recurse := FALSE;
	newchild.handle(newchild, M);
	parent.handle := old;
	RETURN recurse;
END Recursive;

(** Broadcasts an Gadgets.UpdateMsg should obj be a model gadget, or a Display.DisplayMsg if obj is a Display.Frame. *)
PROCEDURE Update*(obj: Objects.Object);
VAR M: UpdateMsg; D: Display.DisplayMsg;
BEGIN
	IF obj IS Display.Frame THEN
		D.device := Display.screen; D.id := Display.full; D.F := obj(Display.Frame); Display.Broadcast(D)
	ELSE
		M.obj := obj; M.F := NIL; Display.Broadcast(M)
	END;
END Update;

(** Make a copy of a pointer to an object. A shallow copy returns a reference to obj. A deep copy results in M being forwarded to obj. *)
PROCEDURE CopyPtr*(VAR M: Objects.CopyMsg; obj: Objects.Object): Objects.Object;
BEGIN
	IF obj = NIL THEN RETURN NIL
	ELSE
		IF M.id = Objects.deep THEN
			M.obj := NIL; obj.handle(obj, M); RETURN M.obj
		ELSE (* shallow *)
			RETURN obj
		END;
	END;
END CopyPtr;

(** Copy the record fields belonging to the base gadget type. Copies handle, X, Y, W, H, state, attr and obj.*)
PROCEDURE CopyFrame*(VAR M: Objects.CopyMsg; F, F0: Frame);
BEGIN
	(* F0.slink := NIL; F0.lib := NIL; F0.ref := -1; F0.next := NIL; F0.dsc := NIL; *)
	F0.handle := F.handle; F0.X := F.X; F0.Y := F.Y; F0.W := F.W; F0.H := F.H;
	F0.state := F.state;
	Attributes.CopyAttributes(F.attr, F0.attr);
	Links.CopyLinks(M, F.link, F0.link);
	F0.obj := CopyPtr(M, F.obj);
END CopyFrame;

(** Copy the record fields belonging to the base Model gadget type. Copies handle and attr. *)
PROCEDURE CopyObject*(VAR M: Objects.CopyMsg; obj, obj0: Object);
BEGIN
	obj0.handle := obj.handle;
	Attributes.CopyAttributes(obj.attr, obj0.attr);
	Links.CopyLinks(M, obj.link, obj0.link)
END CopyObject;

PROCEDURE *EmptyHandler(obj: Objects.Object; VAR M: Objects.ObjMsg);
END EmptyHandler;

(** Default handling of Display.ModifyMsg for visual gadgets. F.mask is invalidated when the frame changes its location or size. Sends behind the scenes to F an Display.OverlapMsg message to invalidate F.mask. Finally, a Display.DisplayMsg is broadcast to update F on the display.*)
PROCEDURE Adjust*(F: Display.Frame; VAR M: Display.ModifyMsg);
VAR D: Display.DisplayMsg; O: Display3.OverlapMsg;
BEGIN
	IF (F.X # M.X) OR (F.Y # M.Y) OR (F.W # M.W) OR (F.H # M.H) THEN (* first adjust *)
		F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H;
		
		IF F IS Frame THEN O.F := F; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O);
		END
	END;
	IF (M.mode = Display.display) & (F.H > 0) & (F.W >0) THEN
		D.x := M.x; D.y := M.y; D.F := F; D.device := Display.screen; D.id := Display.full;
		D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
		F.handle(F, D)
	END
END Adjust;

(** Returns the frame that is located at X, Y on the display. U, v return the relative coordinates of X, Y inside F. Behind the scenes a Display.LocateMsg is broadcast. *)
PROCEDURE ThisFrame*(X, Y: INTEGER; VAR F: Display.Frame; VAR u, v: INTEGER);
VAR M: Display.LocateMsg;
BEGIN M.X := X; M.Y := Y; M.F := NIL; M.loc := NIL; Display.Broadcast(M); F := M.loc; u := M.u; v := M.v;
END ThisFrame;

(** Implements standard resize handling for frames. Rubber-bands the gadget size and broadcasts a Display.ModifyMsg. *)
PROCEDURE SizeFrame*(F: Display.Frame; VAR M: Oberon.InputMsg);
VAR x, y, w, h, X, Y: INTEGER; keys: SET; A: Display.ModifyMsg;
BEGIN
	x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
	Input.Mouse(keys, X, Y);
	Effects.SizeRect(NIL, keys, X, Y, x, y, w, h, NIL); 
	IF keys # {0, 1, 2} THEN
		A.id := Display.extend; A.mode := Display.display; A.X := x - M.x; A.Y := y - M.y; A.W := w; A.H := h;
		A.F := F; A.dX := A.X - F.X; A.dY := A.Y - F.Y; A.dW := A.W - F.W; A.dH := A.H - F.H;
		Display.Broadcast(A);
		M.res := 0
	ELSE M.res := 1
	END
END SizeFrame;

(**  Implements standard move behaviour for frames. Tracks the gadget outline, broadcasts a ConsumeMsg on a copy-over or consume interclick, or broadcast a Display.ModifyMsg for a simple move operation.   *)
PROCEDURE MoveFrame*(F: Display.Frame; VAR M: Oberon.InputMsg); 
VAR x, y, w, h, X, Y, u0, v0: INTEGER; keys: SET; A: Display.ModifyMsg; f: Display.Frame;
	C: Display.ConsumeMsg; old: Objects.Handler; CM: Objects.CopyMsg;
BEGIN
	x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
	Input.Mouse(keys, X, Y);
	Effects.MoveRect(NIL, keys, X, Y, x, y, w, h);
	old := F.handle; F.handle := EmptyHandler;
	ThisFrame(X, Y, f, u0, v0);
	F.handle := old;
	IF keys = {middle, right} THEN (* copy frame *)
		IF f # NIL THEN
			CM.id := Objects.shallow; Objects.Stamp(CM); F.handle(F, CM); CM.obj.slink := NIL; (* copy the object *)
			C.id := Display.drop; C.obj := CM.obj; C.F := f; C.u := u0 + (x - X); C.v := v0 + (y - Y);
			Display.Broadcast(C);
		END;
		M.res := 2; (* copied *)
	ELSIF keys = {middle, left} THEN (* consume frame *)
		IF f # NIL THEN
			(* do a consume *)
			C.id := Display.drop; C.obj := F; F.slink := NIL; C.F := f; C.u := u0 + (x - X); C.v := v0 + (y - Y);
			Display.Broadcast(C)
		END;
		M.res := 0 (* moved *)
	ELSIF (keys = {middle}) OR (keys = {left}) THEN (* move frame, left key is a special hack, see docframes *)
		A.id := Display.move; A.mode := Display.display;
		 A.X := x - M.x; A.Y := y - M.y; 
		A.W := w; A.H := h;
		A.F := F; A.dX := A.X - F.X; A.dY := A.Y - F.Y; A.dW := A.W - F.W; A.dH := A.H - F.H;
		Display.Broadcast(A);
		M.res := 0 (* moved *)
	ELSE M.res := 1 (* cancel *)
	END;
	(* Kernel.GC *)
END MoveFrame;

(** Integrate obj at the caret position. A Display.ConsumeMsg is broadcast behind the scenes. *)
PROCEDURE Integrate*(obj: Objects.Object);
VAR C: Display.ConsumeMsg;
BEGIN
	IF obj # NIL THEN
		C.id := Display.integrate; C.obj := obj; C.F := NIL; Display.Broadcast(C);
	END;
END Integrate;

PROCEDURE Atom(lib: Objects.Library; name: ARRAY OF CHAR): INTEGER;
VAR ref: INTEGER;
BEGIN
	Objects.GetKey(lib.dict, name, ref);
	RETURN ref;
END Atom;

(** Write an object POINTER to a file. Lib is the library of the object that contains the pointer.*)
PROCEDURE WriteRef*(VAR r: Files.Rider; lib: Objects.Library; obj: Objects.Object);
BEGIN
	IF obj = NIL THEN
		Files.WriteInt(r, -1);
	ELSE
		IF obj.lib # NIL THEN
			IF obj.lib # lib THEN
				IF obj.lib.name = "" THEN (* private library *)
					Files.WriteInt(r, -1);
					Texts.WriteString(W, "Warning: Object belonging to private library referenced in ");
					IF lib.name = "" THEN Texts.WriteString(W, "(private)")
					ELSE Texts.WriteString(W, lib.name)
					END;
					Texts.WriteLn(W); Log;
				ELSE
					Files.WriteInt(r, obj.ref);
					Files.WriteInt(r, Atom(lib, obj.lib.name));
				END;
			ELSE
				Files.WriteInt(r, obj.ref);
				Files.WriteInt(r, Atom(lib, "")); (* belongs to this library *)
			END;
			IF obj.lib.name # lib.name THEN
				IF verbose THEN
					Texts.WriteString(W, "Note: "); 
					IF lib.name = "" THEN Texts.WriteString(W, "(private)")
					ELSE Texts.WriteString(W, lib.name)
					END; 
					Texts.WriteString(W, " imports ");
					Texts.WriteString(W, obj.lib.name); Texts.WriteLn(W); Log
				END
			END
		ELSE
			Files.WriteInt(r, -1);
			IF verbose THEN
				Texts.WriteString(W, "Warning: Object without library referenced in "); 
				IF lib.name = "" THEN Texts.WriteString(W, "(private)")
				ELSE Texts.WriteString(W, lib.name)
				END;
				Texts.WriteLn(W); Log
			END
		END
	END
END WriteRef;

(** Read an object POINTER from a file. Lib is the library of the object that contains the pointer. Obj might be of type Objects.Dummy if a loading failure occured. *)
PROCEDURE ReadRef*(VAR r: Files.Rider; lib: Objects.Library; VAR obj: Objects.Object);
VAR i, l: INTEGER; F: Objects.Library; name: ARRAY 32 OF CHAR;
BEGIN
	Files.ReadInt(r, i);
	IF i = -1 THEN
		obj := NIL;
	ELSE
		Files.ReadInt(r, l);
		Objects.GetName(lib.dict, l, name);
		IF name[0] = 0X THEN F := lib; COPY(lib.name, name); ELSE F := Objects.ThisLibrary(name); END;
		IF F # NIL THEN
			F.GetObj(F, i, obj);
			IF (name # lib.name) & (obj # NIL) THEN
				IF verbose THEN
					Texts.WriteString(W, "Note: "); 
					IF lib.name = "" THEN Texts.WriteString(W, "(private)")
					ELSE Texts.WriteString(W, lib.name)
					END;
					Texts.WriteString(W, " imports ");
					Texts.WriteString(W, obj.lib.name); Texts.WriteLn(W); Log
				END
			END;
			IF obj = NIL THEN
				Texts.WriteString(W, "Warning: "); Texts.WriteString(W, "Object imported from ");
				Texts.WriteString(W, name); Texts.WriteString(W, " does not exist (NIL pointer)");
				Texts.WriteLn(W); Log;
			END;
		ELSE
			Texts.WriteString(W, "Warning: "); Texts.WriteString(W, name); Texts.WriteString(W, " not found");
			Texts.WriteLn(W); Log;
			obj := NIL;
		END;
	END;
END ReadRef;

PROCEDURE MakeMaskFor(G: Frame);
VAR MM: Display3.UpdateMaskMsg; O: Display3.OverlapMsg; M: Display3.Mask;
BEGIN
	MM.F := G; Display.Broadcast(MM);
	IF G.mask = NIL THEN
		(* good debug test
		IF ~(dlink IS View) & (dlink IS Frame) THEN HALT(99) END;
		*)
		(* constructing a dummy mask *)
		NEW(M); Display3.Open(M);
		Display3.Add(M, 0, -G.H+1, G.W, G.H); M.x := 0; M.y := 0;
		O.F := G; O.M := M; O.dlink := NIL; O.res := -1; O.x := 0; O.y := 0; G.handle(G, O);
		IF G.mask = NIL THEN G.mask := M END; (* frame is still misbehaving *)
	END
END MakeMaskFor;

PROCEDURE *MakeMask0(G: Frame; X, Y: INTEGER; dlink: Objects.Object; VAR M: Display3.Mask);
VAR ox, oy, x, y, w, h, b, b2: INTEGER; R: Display3.Mask; v: Objects.Object;
BEGIN
	IF G.mask = NIL THEN (* mask has been invalidated *)
		MakeMaskFor(G)
	END;
	M := G.mask; M.x := X; M.y := Y + G.H - 1;
	(* clear the clipping port *)
	M.X := X; M.Y := Y; M.W := G.W; M.H := G.H;

	(* go through the view stack and modify the mask *)
	IF dlink # NIL THEN
		v := dlink;
		WHILE v # NIL DO
			IF v IS View THEN
				WITH v: View DO
					IF v.mask = NIL THEN (* very bad *)
						MakeMaskFor(v)
					END;
					ox := v.mask.x; oy := v.mask.y;
					v.mask.x := v.absX; v.mask.y := v.absY + v.H - 1; (* place mask at absolute position *)
					IF Display3.Rectangular(v.mask, x, y, w, h) THEN
						Display3.AdjustMask(M, x, y, w, h);
					ELSIF Display3.Visible(v.mask, X, Y, G.W, G.H) THEN (* frame completely visible *)
						Display3.AdjustMask(M, X, Y, G.W, G.H);
					ELSE (* waste memory because of overlapping *)
						Display3.IntersectMasks(M, v.mask, R);
						R.X := M.X; R.Y := M.Y; R.W := M.W; R.H := M.H; (* set new port to old port *)
						M := R;
					END;
					IF v.ClipMask # NIL THEN v.ClipMask(v, M, TRUE)
					ELSE
						b := v.border; b2 := b * 2;
						Display3.AdjustMask(M, v.absX+b, v.absY+b, v.W-b2, v.H-b2)
					END;
					v.mask.x := ox; v.mask.y := oy
				END
			(*
			ELSIF (v IS Frame) & (31 IN v(Frame).state) THEN (* from definition these should be position absolutely *)
				WITH v: Display.Frame DO
					Display3.AdjustMask(M, v.X, v.Y, v.W, v.H)
				END
			*)
			ELSIF (v IS Viewers.Viewer) THEN
			ELSIF ~(v IS Frame) & (v IS Display.Frame) THEN (* from definition these should be position absolutely *)
				WITH v: Display.Frame DO
					Display3.AdjustMask(M, v.X, v.Y, v.W, v.H)
				END
			END;
			v := v.dlink;
		END;
	END;
END MakeMask0;

PROCEDURE P(x : INTEGER) : INTEGER;
BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit) END P;

PROCEDURE *EnumMakePrinterMask(X,Y,W,H: INTEGER);
VAR R, T, L, B: INTEGER; 
BEGIN
	L := P(X-tmpX) + tmpX; B := P(Y - tmpY) + tmpY; 
	R := P(X-tmpX + W) + tmpX; T := P(Y - tmpY +H) + tmpY;
	Display3.Add(pMask, L, B, R-L, T-B);
END EnumMakePrinterMask;

PROCEDURE MakePMask0(G: Frame; X, Y: INTEGER; VAR M: Display3.Mask);
VAR MM: Display3.UpdateMaskMsg;
BEGIN
	IF G.mask = NIL THEN (* mask has been invalidated *)
		MM.F := G; Display.Broadcast(MM);
		IF G.mask = NIL THEN
			(* constructing a dummy mask *)
			NEW(M); Display3.Open(M);
			Display3.Add(M, 0, -G.H+1, G.W, G.H); M.x := X; M.y := Y + G.H - 1;
			IF verbose THEN
				Texts.WriteString(W, "Warning Gadgets.MakeMask: creating a default mask"); Texts.WriteLn(W); Log
			END
		ELSE M := G.mask; M.x := X; M.y := Y + G.H - 1
		END;
	ELSE
		M := G.mask; M.x := X; M.y := Y + G.H - 1
	END;
	(* clear the clipping port *)
	M.X := X; M.Y := Y; M.W := G.W; M.H := G.H;
END MakePMask0;

PROCEDURE ScaleMask(px, py: INTEGER; in: Display3.Mask; VAR out: Display3.Mask);
BEGIN
	NEW(pMask); Display3.Open(pMask);
	tmpX := px; tmpY := py;
	Display3.EnumRect(in, in.X, in.Y, in.W, in.H, EnumMakePrinterMask);
	pMask.X := Printer.FrameX; pMask.Y := Printer.FrameY; pMask.W := Printer.FrameW; pMask.H := Printer.FrameH;
	out := pMask;
END ScaleMask;

PROCEDURE *MakePrinterMask0(G: Frame; X, Y: INTEGER; dlink: Objects.Object; VAR M: Display3.Mask);
VAR ox, oy, x, y, w, h, b, b2: INTEGER; R, R0: Display3.Mask; v: Objects.Object;
BEGIN 
	(* make the basic mask *)
	MakePMask0(G, X, Y, M);
	
	(* scale it *)
	ScaleMask(X, Y, M, M);
	
	(* add views clipping *)
	IF dlink # NIL THEN
		v := dlink;
		WHILE v # NIL DO
			IF (v IS View) & (v(View).mask # NIL) THEN
				WITH v: View DO
					ox := v.mask.x; oy := v.mask.y;
					v.mask.x := v.absX; v.mask.y := v.absY + v.H - 1; (* place mask at absolute position *)
					ScaleMask(v.absX, v.absY, v.mask, R);
					IF Display3.Rectangular(R, x, y, w, h) THEN
						Display3.AdjustMask(M, x, y, w, h);
					ELSIF Display3.Visible(R, X, Y, P(G.W), P(G.H)) THEN (* frame completely visible *)
						Display3.AdjustMask(M, X, Y, P(G.W), P(G.H));
					ELSE (* waste memory because of overlapping *)
						Display3.IntersectMasks(M, R, R0);
						R0.X := M.X; R0.Y := M.Y; R0.W := M.W; R0.H := M.H; (* set new port to old port *)
						M := R0;
					END;
					IF v.ClipMask # NIL THEN v.ClipMask(v, M, FALSE)
					ELSE
						b := v.border; b2 := b * 2;
						Display3.AdjustMask(M, v.absX+P(b), v.absY+P(b), P(v.W-b2), P(v.H-b2))
					END;
					v.mask.x := ox; v.mask.y := oy
				END
			END;
			v := v.dlink;
		END
	END
END MakePrinterMask0;

(** Execute a string as an Oberon command. The parameters executor, dlink, sender, receiver are copied to the global variables executorObj, context, senderObj, receiverObj respectively. Dlink must be the parent of executor. If a '%' is leading the command, no Oberon.Par is set up. *)
PROCEDURE Execute*(cmd: ARRAY OF CHAR; executor, dlink, sender, receiver: Objects.Object);
VAR T: Texts.Text; S: Attributes.Scanner; ch: CHAR; res, cx, cy, cw, chl, i, j: INTEGER;
	oldcontext, obj: Objects.Object; str: BOOLEAN;
BEGIN
	IF cmd[0] = 0X THEN RETURN END;
	ch := 0X; T := NIL;
	Display.GetClip(cx, cy, cw, chl); Display.ResetClip;
	executorObj := executor; context := dlink; senderObj := sender; receiverObj := receiver;
	
	NEW(par); par.obj := executor;
	(* calculate outermost frame in the menuviewer*)
	IF context = NIL THEN context := executor END; (* may be the outside most frame *) 
	obj := context;
	LOOP
		IF (obj = NIL) OR (obj.dlink = NIL) OR (obj.dlink IS Viewers.Viewer) THEN EXIT END;
		obj := obj.dlink
	END;
	IF (obj # NIL) & (obj IS Display.Frame) THEN par.frame := obj(Display.Frame)
	ELSE par.frame := Oberon.Par.frame (* hack, otherwise Oberon.Call traps *)
	END;

	(* modified ps - 6.6.96 *)
	IF cmd[0] = "%" THEN
		par.text := emptyText; par.pos := 0;
		i := 1;
		WHILE cmd[i] >  " " DO cmd[i-1] := cmd[i]; INC(i) END;
		cmd[i-1] := 0X
	ELSIF cmd[0] = "$" THEN
		NEW(par.text); Texts.Open(par.text, "");
		i := 1;
		WHILE cmd[i] > " " DO
			Texts.Write(W, cmd[i]); cmd[i-1] := cmd[i]; INC(i)
		END;
		cmd[i-1] := 0X; par.pos := i-1;
		WHILE cmd[i] # 0X DO
			Texts.Write(W, cmd[i]); INC(i)
		END;
		Texts.Append(par.text, W.buf)
	ELSE
		IF ("A" <= CAP(cmd[0])) & (CAP(cmd[0]) <= "Z") THEN (* direct command *)
			i := 0;
			WHILE (cmd[i] # 0X) & (cmd[i] >  " ") DO INC(i) END;
			j := i;
			WHILE (cmd[j] # 0X) & (cmd[j] <=  " ") DO INC(j) END;
			IF cmd[j] # 0X THEN
				Attributes.StrToTxt(cmd, T); Attributes.OpenScanner(S, T, 0); Attributes.Scan(S);
				Attributes.Read(S.R, ch)
			END
		ELSE	(* command has to be retrieved by macro handler *)
			Attributes.StrToTxt(cmd, T);
			Attributes.OpenScanner(S, T, 0); Attributes.Scan(S);
			i := 0; j:= 0;
			WHILE S.s[i] # 0X DO cmd[i] := S.s[i]; INC(i) END;
			Attributes.Read(S.R, ch);
			WHILE ~S.R.eot & (ch <= " ") DO Attributes.Read(S.R, ch) END;
			IF S.R.eot THEN cmd[i] := 0X; j := i END
		END;

		(* set up parameter block *)
		IF cmd[j] # 0X THEN
			str := FALSE;
			WHILE ~S.R.eot & (str OR (ch # "~")) DO
				IF (ch = 22X) THEN S.R.substitute := ~S.R.substitute; str := ~str END;
				Texts.Write(W, ch); Attributes.Read(S.R, ch);
			END;
			par.pos := T.len; par.text := T;
			Texts.Append(T, W.buf)
		ELSE
			par.text := emptyText;
			par.pos := 0
		END;
		cmd[i] := 0X
	END;
	
	IF executor # NIL THEN oldcontext := executor.dlink; executor.dlink := context END;
	
	Oberon.Call(cmd, par, FALSE, res);
	IF res # 0 THEN
		Texts.WriteString(W, "Call error: "); Texts.WriteString(W, Modules.resMsg);
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END;

	IF par # NIL THEN par.obj := NIL END;
	IF executor # NIL THEN executor.dlink := oldcontext END;
	Display.SetClip(cx, cy, cw, chl);
	executorObj := NIL; context := NIL; senderObj := NIL; receiverObj := NIL; par := NIL
END Execute;

(* Macros *)

PROCEDURE ReadName(VAR T: Attributes.Reader; VAR name: ARRAY OF CHAR);
VAR ch: CHAR; i: INTEGER; old: BOOLEAN;

	PROCEDURE Ok(ch: CHAR): BOOLEAN;
	BEGIN
		RETURN (ch = ".") OR ((ch >= "0") & (ch <= "9")) OR ((CAP(ch) >= "A") & (CAP(ch) <= "Z"));
	END Ok;
	
BEGIN
	i := 0; old := T.substitute; T.substitute := FALSE;
	LOOP Attributes.Read(T, ch);
		IF T.eot THEN EXIT; END;
		IF ~Ok(ch) THEN EXIT END;
		name[i] := ch; INC(i);
	END;
	name[i] := 0X;
	T.substitute := old;
END ReadName;

(* special code for the & macro. && for next higher context etc. *)
PROCEDURE Lookup0(VAR T: Attributes.Reader; VAR name: ARRAY OF CHAR; VAR context: Objects.Object);
VAR ch: CHAR; i: INTEGER; old: BOOLEAN;

	PROCEDURE Ok(ch: CHAR): BOOLEAN;
	BEGIN
		RETURN (ch = ".") OR ((ch >= "0") & (ch <= "9")) OR ((CAP(ch) >= "A") & (CAP(ch) <= "Z"));
	END Ok;
	
BEGIN
	i := 0; old := T.substitute; T.substitute := FALSE;
	Attributes.Read(T, ch);
	WHILE ~T.eot & (ch = "&") DO
		IF (context # NIL) & (context.dlink # NIL) THEN context := context.dlink END;
		 Attributes.Read(T, ch)
	END;
	LOOP
		IF T.eot THEN EXIT; END;
		IF ~Ok(ch) THEN EXIT END;
		name[i] := ch; INC(i);
		Attributes.Read(T, ch);
	END;
	name[i] := 0X;
	T.substitute := old;
END Lookup0;

PROCEDURE ObjAttr(name: ARRAY OF CHAR; context: Objects.Object; VAR W: Texts.Writer);
VAR i, j: INTEGER; attr: ARRAY 32 OF CHAR; obj: Objects.Object;
BEGIN
	IF name # "" THEN
		i := 0; WHILE name[i] # 0X DO INC(i); END;
		WHILE (i > 0) & (name[i] # ".") DO DEC(i); END;
		IF name[i] = "." THEN
			name[i] := 0X; INC(i); j := 0;
			WHILE name[i] # 0X DO attr[j] := name[i]; INC(i); INC(j); END;
			attr[j] := 0X;
			obj := FindObj(context, name);
			IF obj # NIL THEN Attributes.WriteAttr(obj, attr, W);
			ELSE Texts.WriteLn(WW); Texts.WriteString(WW, "Object not found: "); Texts.WriteString(WW, name);
				Texts.WriteLn(WW); Texts.Append(Oberon.Log, WW.buf)
			END
		ELSE Texts.WriteLn(WW); Texts.WriteString(WW, "Syntax error: "); Texts.WriteString(WW, name);
			Texts.WriteLn(WW); Texts.Append(Oberon.Log, WW.buf)
		END
	END
END ObjAttr;

PROCEDURE *StandardMacros(ch: CHAR; VAR T: Attributes.Reader; VAR res: Texts.Text; VAR beg: LONGINT);
VAR name: ARRAY 64 OF CHAR; f, context0: Objects.Object;
BEGIN
	IF ch # 0X THEN
		NEW(res); Texts.Open(res, ""); beg := 0;
		IF ch = "&" THEN
			context0 := context;
			Lookup0(T, name, context0); ObjAttr(name, context0, mW); Texts.Append(res, mW.buf)
		ELSIF ch = "#" THEN
			ReadName(T, name);
			Attributes.WriteAttr(executorObj, name, mW);  Texts.Append(res, mW.buf);
		ELSIF ch = "!" THEN (* more than one sender *)
			IF senderObj # NIL THEN
				ReadName(T, name);
				f := senderObj;
				WHILE f # NIL DO
					Attributes.WriteAttr(f, name, mW);  Texts.Write(mW, " ");
					f := f.slink
				END;
				Texts.Write(mW, " "); Texts.Append(res, mW.buf);
			END
		ELSIF ch = "'" THEN
			Texts.Write(mW, 22X); Texts.Append(res, mW.buf);
		ELSIF ch = "?" THEN (* only one recipient *)
			ReadName(T, name);
			Attributes.WriteAttr(receiverObj, name, mW);
			Texts.Append(res, mW.buf);
		END
	END
END StandardMacros;

PROCEDURE *UpArrowMacro(ch: CHAR; VAR T: Attributes.Reader; VAR res: Texts.Text; VAR beg: LONGINT);
VAR text, text0: Texts.Text; bg, end, ttime: LONGINT; obj: Objects.Object; S: Display.SelectMsg;
	i: INTEGER; name: ARRAY 32 OF CHAR; R: Attributes.Reader; ch0: CHAR; old: Objects.Library;
	string: BOOLEAN;
BEGIN
	IF ch = 0X THEN (* Reset *)
		uparrowdone := FALSE;
	ELSIF (ch = "^") THEN (* getselection *)
		IF ~uparrowdone THEN uparrowdone := TRUE;
			Attributes.Read(T, ch);
			IF (CAP(ch) >= "A") & (CAP(ch) <= "Z") THEN (* skip word *)
				i := 0;
				LOOP name[i] := ch; INC(i);
					Attributes.Read(T, ch);
					IF T.eot THEN EXIT; END;
					IF (ch # ".") & ((ch <= " ") OR ((CAP(ch) < "A") OR (CAP(ch) > "Z"))) THEN EXIT END;
				END;
				name[i] := 0X;
			END;
			Oberon.GetSelection(text, bg, end, ttime);
			S.id := Display.get; S.F := NIL; S.sel := NIL; S.obj := NIL; S.time := 0; Display.Broadcast(S);
			IF (S.time > ttime) & (S.obj # NIL) & (name # "") THEN
				NEW(text); Texts.Open(text, ""); beg := 0;
				IF S.time > 0 THEN
					obj := S.obj;
					WHILE obj # NIL DO
						IF obj IS Frame THEN Attributes.WriteAttr(obj, name, W); Texts.Write(W, " ");
						END;
						obj := obj.slink;
					END;
					Texts.Append(text, W.buf); res := text;
				ELSE res := NIL
				END;
			ELSE
				IF ttime > 0 THEN 
					(* res := text; beg := bg; *)
					Attributes.OpenReader(R, text, bg); uparrowdone := TRUE; beg := bg;
					NEW(text0); Texts.Open(text0, ""); string := FALSE;
					Attributes.Read(R, ch0);  
					WHILE ~R.eot & (beg < end) DO
						IF ch0 = 22X THEN R.substitute := ~R.substitute; string := ~string END;
						old := W.lib; W.lib := R.lib; Texts.Write(W, ch0); W.lib := old;
						IF beg + 1 = end THEN (* reached the end, ch0 is the last character read *)
							IF (ch0 # " ") & (ch0 # 0DX) & (ch0 # 9X) THEN
								Attributes.Read(R, ch0)
							ELSE ch0 := " " (* ended on a termination char *)
							END
						ELSE 
							Attributes.Read(R, ch0)
						END;
						INC(beg);
					END;
					WHILE ~R.eot & (string OR ((ch0 # " ") & (ch0 # 0DX) & (ch0 # 9X))) DO
						IF ch0 = 22X THEN R.substitute := ~R.substitute; string := ~string END;
						old := W.lib; W.lib := R.lib; Texts.Write(W, ch0); W.lib := old;
						Attributes.Read(R, ch0); INC(beg);
					END;
					Texts.Write(W, " "); Texts.Append(text0, W.buf); beg := 0; end := text0.len; res := text0
				ELSE res := NIL;
				END;
			END;
		ELSE
			res := NIL; beg := 0;
		END;
	END;
END UpArrowMacro;

(** Forwards a message from a camera-view to its contents, inserting the camera-view in the message thread. X, Y is the absolute screen coordinates of the bottom-left corner of the camera-view. This is important for calculating the correct display mask for the contents of the view. *)
PROCEDURE Send*(from: View; X, Y: INTEGER; to: Display.Frame; VAR M: Display.FrameMsg);
VAR S: Stack;
BEGIN
	Push(S, from, M); from.absX := X; from.absY := Y; to.handle(to, M); Pop(S, from, M);
END Send;

(* ---------- leaf handler ---------- *)

PROCEDURE HandleFrameAttributes(F: Frame; VAR M: Objects.AttrMsg);
VAR b: Attributes.BoolAttr; c: Attributes.CharAttr; i: Attributes.IntAttr; r: Attributes.RealAttr; s: Attributes.StringAttr; a, f: Attributes.Attr;
BEGIN
	IF M.id = Objects.get THEN
		a := F.attr;
		WHILE (a # NIL) & (a.name # M.name) DO a := a.next END;
		IF a # NIL THEN
			IF a IS Attributes.BoolAttr THEN M.class := Objects.Bool; M.b := a(Attributes.BoolAttr).b;
			ELSIF a IS Attributes.CharAttr THEN M.class := Objects.Char; M.c := a(Attributes.CharAttr).c;
			ELSIF a IS Attributes.IntAttr THEN M.class := Objects.Int; M.i := a(Attributes.IntAttr).i;
			ELSIF a IS Attributes.RealAttr THEN M.class := Objects.LongReal; M.y := a(Attributes.RealAttr).r;
			ELSIF a IS Attributes.StringAttr THEN M.class := Objects.String; COPY(a(Attributes.StringAttr).s, M.s);
			ELSE HALT(42)
			END;
			M.res := 0;
		ELSIF M.name = "Gen" THEN HALT(99)
		ELSIF (M.name = "Name") & (F.lib # NIL) & (F.lib.name # "") THEN
			M.s[0] := 0X; 
			Objects.GetName(F.lib.dict, F.ref, M.s); M.class := Objects.String; M.res := 0
		ELSIF M.name = "Transparent" THEN (* hidden attributes: special hack/rs wish *)
			M.b := transparent IN F.state; M.class := Objects.Bool; M.res := 0
		(* should return nothing 
		ELSE M.class := Objects.String; M.s[0] := 0X; M.res := 0 (* must be. some gadgets advertize Cmd *)
		*)
		END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "Gen" THEN HALT(99)
		ELSIF (M.name = "Name") (*& (M.s # "")*) THEN
			f := Attributes.FindAttr(M.name, F.attr); (* Search attribute *)
			IF M.s[0] # 0X THEN (* Insert name *)
				IF (f = NIL) OR ~(f IS Attributes.StringAttr) THEN (* Does not exist, insert *)
					NEW(s); COPY(M.s, s.s); Attributes.InsertAttr(F.attr, M.name, s) 
				ELSE (* Does exist, overwrite *)
					COPY(M.s, f(Attributes.StringAttr).s)
				END;
			ELSE (* Delete name *)
				IF f # NIL THEN (* Name in list, has to be deleted *)
					Attributes.DeleteAttr(F.attr, "Name")
				END
			END;
			M.res := 0;
		ELSE
			a := NIL; f := Attributes.FindAttr(M.name, F.attr);
			IF M.class = Objects.Bool THEN 
				IF (f = NIL) OR ~(f IS Attributes.BoolAttr) THEN
					NEW(b); b.b := M.b; a := b ELSE f(Attributes.BoolAttr).b := M.b
				END;
			ELSIF M.class = Objects.Char THEN 
				IF (f = NIL) OR ~(f IS Attributes.CharAttr) THEN NEW(c); c.c := M.c; a := c ELSE f(Attributes.CharAttr).c := M.c END;
			ELSIF M.class = Objects.Int THEN
				IF (f = NIL) OR ~(f IS Attributes.IntAttr) THEN NEW(i); i.i := M.i; a := i ELSE f(Attributes.IntAttr).i := M.i END;
			ELSIF M.class = Objects.Real THEN
				IF (f = NIL) OR ~(f IS Attributes.RealAttr) THEN NEW(r); r.r := M.x; a := r ELSE f(Attributes.RealAttr).r := M.x END;
			ELSIF M.class = Objects.LongReal THEN
				IF (f = NIL) OR ~(f IS Attributes.RealAttr) THEN NEW(r); r.r := M.y; a := r ELSE f(Attributes.RealAttr).r := M.y END;
			ELSIF (M.class = Objects.String) THEN
				IF (f = NIL) OR ~(f IS Attributes.StringAttr) THEN
					NEW(s); COPY(M.s, s.s); a:= s ELSE COPY(M.s, f(Attributes.StringAttr).s)
				END;
			ELSE RETURN
			END;
			IF a # NIL THEN Attributes.InsertAttr(F.attr, M.name, a);
			END;
			M.res := 0;
		END;
	ELSIF M.id = Objects.enum THEN
		M.Enum("Name"); 
		a := F.attr; WHILE a # NIL DO M.Enum(a.name); a := a.next END; 
		M.res := 0;
	END
END HandleFrameAttributes;

PROCEDURE HandleObjectAttributes(obj: Object; VAR M: Objects.AttrMsg);
VAR b: Attributes.BoolAttr; c: Attributes.CharAttr; i: Attributes.IntAttr; r: Attributes.RealAttr;
	s: Attributes.StringAttr; a, f: Attributes.Attr;
BEGIN
	IF M.id = Objects.get THEN
		a := obj.attr;
		WHILE (a # NIL) & (a.name # M.name) DO a := a.next END;
		IF a # NIL THEN
			IF a IS Attributes.BoolAttr THEN M.class := Objects.Bool; M.b := a(Attributes.BoolAttr).b;
			ELSIF a IS Attributes.CharAttr THEN M.class := Objects.Char; M.c := a(Attributes.CharAttr).c;
			ELSIF a IS Attributes.IntAttr THEN M.class := Objects.Int; M.i := a(Attributes.IntAttr).i;
			ELSIF a IS Attributes.RealAttr THEN M.class := Objects.LongReal; M.y := a(Attributes.RealAttr).r;
			ELSIF a IS Attributes.StringAttr THEN M.class := Objects.String; COPY(a(Attributes.StringAttr).s, M.s);
			ELSE HALT(42)
			END;
			M.res := 0;
		ELSIF M.name = "Gen" THEN HALT(99)
		ELSIF (M.name = "Name") & (obj.lib # NIL) & (obj.lib.name # "") THEN
			M.s[0] := 0X; 
			Objects.GetName(obj.lib.dict, obj.ref, M.s);  M.class := Objects.String; M.res := 0
		ELSE M.class := Objects.String; M.s[0] := 0X; M.res := 0 END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "Gen" THEN HALT(99)
		ELSIF M.name = "Name" THEN
			(*
			IF (obj.lib # NIL) & (obj.lib.name # "") THEN (* << only insert names in public libraries *)
				Objects.GetRef(obj.lib.dict, M.s, ref);
				IF (ref # MIN(INTEGER)) & (ref # obj.ref) THEN
					Texts.WriteString(W, " overwriting name "); Texts.WriteString(W, M.s); Texts.WriteLn(W); Log
				END;
				Objects.PutName(obj.lib.dict, obj.ref, M.s)
			END;
			*)
			f := Attributes.FindAttr(M.name, obj.attr); (* Search attribute *)
			IF M.s[0] # 0X THEN (* Insert name *)
				IF (f = NIL) OR ~(f IS Attributes.StringAttr) THEN (* Does not exist, insert *)
					NEW(s); COPY(M.s, s.s); Attributes.InsertAttr(obj.attr, M.name, s) 
				ELSE (* Does exist, overwrite *)
					COPY(M.s, f(Attributes.StringAttr).s)
				END;
			ELSE (* Delete name *)
				IF f # NIL THEN (* Name in list, has to be deleted *)
					Attributes.DeleteAttr(obj.attr, "Name")
				END
			END;
			M.res := 0
		ELSE
			a := NIL; f := Attributes.FindAttr(M.name, obj.attr);
			IF M.class = Objects.Bool THEN 
				IF (f = NIL) OR ~(f IS Attributes.BoolAttr) THEN
					NEW(b); b.b := M.b; a := b ELSE f(Attributes.BoolAttr).b := M.b
				END;
			ELSIF M.class = Objects.Char THEN 
				IF (f = NIL) OR ~(f IS Attributes.CharAttr) THEN NEW(c); c.c := M.c; a := c ELSE f(Attributes.CharAttr).c := M.c END;
			ELSIF M.class = Objects.Int THEN
				IF (f = NIL) OR ~(f IS Attributes.IntAttr) THEN NEW(i); i.i := M.i; a := i ELSE f(Attributes.IntAttr).i := M.i END;
			ELSIF M.class = Objects.Real THEN
				IF (f = NIL) OR ~(f IS Attributes.RealAttr) THEN NEW(r); r.r := M.x; a := r ELSE f(Attributes.RealAttr).r := M.x END;
			ELSIF M.class = Objects.LongReal THEN
				IF (f = NIL) OR ~(f IS Attributes.RealAttr) THEN NEW(r); r.r := M.y; a := r ELSE f(Attributes.RealAttr).r := M.y END;
			ELSIF (M.class = Objects.String) THEN
				IF (f = NIL) OR ~(f IS Attributes.StringAttr) THEN
					NEW(s); COPY(M.s, s.s); a:= s ELSE COPY(M.s, f(Attributes.StringAttr).s)
				END;
			ELSE RETURN
			END;
			IF a # NIL THEN Attributes.InsertAttr(obj.attr, M.name, a);
			END;
			M.res := 0
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Name"); 
		a := obj.attr; WHILE a # NIL DO M.Enum(a.name); a := a.next END; 
		M.res := 0;
	END
END HandleObjectAttributes;

(** Bind an object to a library. Nothing happens if obj is already bound to a public library, or is already bound to lib. This is the default behavior when an object received the Objects.BindMsg. *)
PROCEDURE BindObj*(obj: Objects.Object; lib: Objects.Library);
VAR ref: INTEGER;
BEGIN
	IF lib # NIL THEN 
		IF (obj.lib = NIL) OR (obj.lib.name[0] = 0X) & (obj.lib # lib) THEN
			lib.GenRef(lib, ref);
			IF ref >= 0 THEN
				lib.PutObj(lib, ref, obj)
			END
		END
	END
END BindObj;

PROCEDURE findobj(obj: Objects.Object; link: Links.Link; VAR M: Objects.FindMsg);
	VAR name: Objects.Name;
BEGIN
	GetObjName(obj, name);
	IF name = M.name THEN M.obj := obj END;
	WHILE (link # NIL) & (M.obj = NIL) DO
		IF link.obj # NIL THEN
			GetObjName(link.obj, name);
			IF name = M.name THEN M.obj := link.obj END
		END;
		link := link.next
	END
END findobj;

PROCEDURE *ObjectHandler(obj: Objects.Object; VAR M: Objects.ObjMsg);
VAR name: ARRAY 64 OF CHAR; obj0: Object; ch: CHAR;
BEGIN
	WITH obj: Object DO
		IF M IS  Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.load THEN
					Files.Read(M.R, ch);
					IF (ch = 43X) OR (ch = 42X) THEN
						Files.Set(M.R, Files.Base(M.R), Files.Pos(M.R) - 1); (* rewind *)
						Attributes.LoadAttributes(M.R, obj.attr)
					ELSIF ch = 80X THEN
						Attributes.LoadAttributes(M.R, obj.attr);
						Links.LoadLinks(M.R, obj.lib, obj.link)
					ELSE HALT(99)
					END
				ELSIF M.id = Objects.store THEN
					IF obj.link = NIL THEN (* no links, use old format for compatibility *)
						Attributes.StoreAttributes(M.R, obj.attr)
					ELSE
						Files.Write(M.R, 80X); (* version number *)
						Attributes.StoreAttributes(M.R, obj.attr);
						Links.StoreLinks(M.R, obj.lib, obj.link);
					END
				END
			END
		ELSIF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO HandleObjectAttributes(obj, M) END
		ELSIF M IS Objects.BindMsg THEN
			WITH M: Objects.BindMsg DO BindObj(obj, M.lib); Links.BindLinks(obj.link, M) END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = obj.stamp THEN M.obj := obj.dlink
				ELSE
					NEW(obj0); obj.stamp := M.stamp; obj.dlink := obj0; CopyObject(M, obj, obj0); M.obj := obj0
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				Links.HandleLinkMsg(obj.link, M)
			END
		ELSIF M IS Objects.FindMsg THEN
			WITH M: Objects.FindMsg DO
				findobj(obj, obj.link, M)
			END
		END
	END
END ObjectHandler;

PROCEDURE HasCmdAttr(F: Frame; attr: ARRAY OF CHAR): BOOLEAN;
VAR A: Objects.AttrMsg;
BEGIN
	A.id := Objects.get; COPY(attr, A.name); A.class := Objects.Inval; A.res := -1; A.dlink := NIL; Objects.Stamp(A);
	F.handle(F, A);
	RETURN (A.res >= 0) & (A.class = Objects.String) & (A.s # "") 
END HasCmdAttr;

(** Execute the attribute with name attr of F as an Oberon command. Sends a Objects.AttrMsg to retrieve the attribute attr of F. The attributed must be of the string class. *)
PROCEDURE ExecuteAttr*(F: Frame; attr: ARRAY OF CHAR; dlink, sender, receiver: Objects.Object);
VAR A: Objects.AttrMsg;
BEGIN
	A.id := Objects.get; COPY(attr, A.name); A.class := Objects.Inval; A.res := -1; A.dlink := NIL; Objects.Stamp(A);
	F.handle(F, A);
	IF (A.res >= 0) & (A.class = Objects.String) & (A.s # "") THEN Execute(A.s, F, dlink, sender, receiver) END
END ExecuteAttr;

(** Standard mouse tracking behavior of visual gadgets. Calls ExecuteAttr for the "Cmd" attribute, calls MoveFrame and SizeFrame.*)
PROCEDURE TrackFrame*(F: Display.Frame; VAR M: Oberon.InputMsg);
VAR keys: SET; x, y, w, h: INTEGER; R: Display3.Mask;
BEGIN
	WITH F: Frame DO
		IF ~(selected IN F.state) & (middle IN M.keys) THEN (* only when not selected and middle key *)
			x := M.x + F.X; y :=  M.y + F.Y; w := F.W; h := F.H;
			IF InActiveArea(F, M) THEN (* usable areas, corner, sides may be part, TRUE if locked *)
				IF HasCmdAttr(F, "Cmd") THEN
					MakeMask(F, x, y, M.dlink, R);
					Effects.TrackHighlight(R, keys, M.X, M.Y, x, y, w, h);
					IF InActiveArea(F, M) & (keys = {1}) THEN ExecuteAttr(F(Frame), "Cmd", M.dlink, NIL, NIL) END;
					M.res := 0
				ELSIF ~IsLocked(F, M.dlink) THEN MoveFrame(F, M)
				END
			ELSIF Effects.InCorner(M.X, M.Y, x, y, w, h) & ~(lockedsize IN F.state) THEN SizeFrame(F, M)
			ELSIF (Effects.InBorder(M.X, M.Y, x, y, w, h) OR Effects.InCorner(M.X, M.Y, x, y, w, h)) THEN
				MoveFrame(F, M)
			END
		END
	END
END TrackFrame;

PROCEDURE *FrameHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR F0: Frame; x, y, w, h, u, v: INTEGER; D: Display.DisplayMsg; R: Display3.Mask; obj: Objects.Object;
	name: ARRAY 64 OF CHAR;
BEGIN
	WITH F: Frame DO 
		IF M IS  Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.load THEN
					Files.ReadInt(M.R, F.X); Files.ReadInt(M.R, F.Y);
					Files.ReadInt(M.R, F.W); Files.ReadInt(M.R, F.H);
					ReadRef(M.R, F.lib, obj); (* dummy next pointer *)
					Files.ReadSet(M.R, F.state);
					Files.ReadInt(M.R, x); (* dummy *)
					IF x # 8367 THEN (* old version *)
					ELSE  (* x = 2 version with links *)
						Links.LoadLinks(M.R, F.lib, F.link)
					END;
					ReadRef(M.R, F.lib, F.obj);
					Attributes.LoadAttributes(M.R, F.attr);
					(* hack *)
					Objects.GetName(F.lib.dict, F.ref, name);
					IF name[0] # 0X THEN NameObj(F, name) END
				ELSIF M.id = Objects.store THEN
					Files.WriteInt(M.R, F.X); Files.WriteInt(M.R, F.Y);
					Files.WriteInt(M.R, F.W); Files.WriteInt(M.R, F.H);
					WriteRef(M.R, F.lib, NIL); (* not really needed *)
					Files.WriteSet(M.R, F.state);
					IF F.link = NIL THEN Files.WriteInt(M.R, 1); (* write old version *)
					ELSE
						Files.WriteInt(M.R, 8367);
						Links.StoreLinks(M.R, F.lib, F.link)
					END;
					WriteRef(M.R, F.lib, F.obj);
					Attributes.StoreAttributes(M.R, F.attr)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyFrame(M, F, F0); M.obj := F0
				END
			END
		ELSIF M IS Objects.BindMsg THEN
			WITH M: Objects.BindMsg DO
				BindObj(F, M.lib);
				IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
				Links.BindLinks(F.link, M)
			END
		ELSIF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO HandleFrameAttributes(F, M) END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M:Objects.LinkMsg DO
				IF (M.id = Objects.get) & (M.name = "Model") THEN M.obj := F.obj; M.res := 0
				ELSIF (M.id = Objects.set) & (M.name = "Model") THEN F.obj := M.obj; M.res := 0
				ELSIF M.id = Objects.enum THEN
					M.Enum("Model");
					Links.HandleLinkMsg(F.link, M)
				ELSE Links.HandleLinkMsg(F.link, M)
				END
			END
		ELSIF M IS Objects.FindMsg THEN
			WITH M: Objects.FindMsg DO
				IF F.obj # NIL THEN
					GetObjName(F.obj, name); IF name = M.name THEN M.obj := F.obj END
				END;
				findobj(F, F.link, M)
			END
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.res >= 0) THEN
					(* another debug test
					IF M IS Display3.OverlapMsg THEN HALT(100) END;
					*)
					RETURN
				END;
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; u := M.x; v := M.y; 
				
				(* debug tests *)
				IF (M.F # NIL) & (M.F IS Frame) THEN (* check if M.F is initialized. Should trap if not *) END;
				IF (ABS(x) > 20000) OR (ABS(y) > 20000) THEN HALT(99) END;
				(* end of debug tests *)
				
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								MakeMask(F, x, y, M.dlink, R);
								Display3.ReplConst(R, 1, x, y, w, h, Display.replace);
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								MakeMask(F, x, y, M.dlink, R);
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								Display3.ReplConst(R, 1, x, y, w, h, Display.replace);
							END
						ELSIF M.device = Display.printer THEN
							MakePrinterMask(F(Frame), M.x, M.y, M.dlink, R);
							Printer3.Rect(R, 15, Display.solid, M.x, M.y, P(w), P(h), 1, Display.replace)
						END
					END
				ELSIF M IS UpdateMsg THEN
					WITH M: UpdateMsg DO
						IF ~(transparent IN F.state) & (M.obj IS Frame) THEN (* causes a trap if message not initialised correctly *)
							obj := M.obj;
							WHILE obj # NIL DO
								IF obj = F THEN
									D.device := Display.screen; D.id := Display.full; D.F := F; D.x := M.x; D.y := M.y;
									D.dlink := M.dlink; D.res := -1;
									F.handle(F, D)
								END;
								obj := obj.slink
							END
						END
					END
				ELSIF M IS Display3.OverlapMsg THEN
					WITH M: Display3.OverlapMsg DO IF (M.F = F) OR (M.F = NIL) THEN F.mask := M.M; M.res := 0 END END
				ELSIF M IS Display.ModifyMsg THEN
					WITH M: Display.ModifyMsg DO
						IF (M.F = F) THEN (*Copying*)Adjust(F, M) END
					END
				ELSIF M IS Display.LocateMsg THEN
					WITH M: Display.LocateMsg DO
						IF (M.loc = NIL) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN 
							M.loc := F; M.u := M.X - x; M.v := M.Y - (y+h-1); M.res := 0
						END
					END
				ELSIF M IS Display.SelectMsg THEN
					WITH M: Display.SelectMsg DO
						IF (M.id = Display.set) & (M.F = F) THEN INCL(F.state, selected); M.res := 0
						ELSIF (M.id = Display.reset) & (M.F = F) THEN EXCL(F.state, selected); M.res := 0
						ELSIF M.id = Display.get THEN END
					END
				ELSIF M IS Display.ConsumeMsg THEN
					WITH M: Display.ConsumeMsg DO
						IF (M.id = Display.drop) & (M.F = F) & (F IS Frame) THEN
							IF HasCmdAttr(F, "ConsumeCmd") THEN
								ExecuteAttr(F(Frame), "ConsumeCmd", M.dlink, M.obj, F);
								M.res := 0
							END
						END
					END
				ELSIF M IS Display.ControlMsg THEN
					IF F.obj # NIL THEN F.obj.handle(F.obj, M) END
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO
						IF M.id = Oberon.track THEN TrackFrame(F, M) END
					END
				END;
				M.x := u; M.y := v;
			END
		END
	END
END FrameHandler;

(* ------- Additional commands -------- *)

(** Look up value of the name alias. Empty string is returned if name is not aliased. *)
PROCEDURE GetAlias*(name: ARRAY OF CHAR; VAR value: ARRAY OF CHAR);
VAR a: Alias;
BEGIN
	a := aliases; value[0] := 0X; 
	WHILE (a # NIL) & (a.name # name) DO a := a.next END;
	IF a # NIL THEN
		COPY(a.value, value);
	END;
END GetAlias;

(** Create an object from the generator procedure or alias objname. *)
PROCEDURE CreateObject*(objname: ARRAY OF CHAR): Objects.Object;
VAR genproc: ARRAY 64 OF CHAR; res: INTEGER;
BEGIN
	Objects.NewObj := NIL;
	GetAlias(objname, genproc);	(* ps 20.5.96 *)
	IF genproc = "" THEN COPY(objname, genproc) END;
	Oberon.Call(genproc, Oberon.Par, FALSE, res);
	IF res # 0 THEN
		Texts.WriteString(W, "Call error: "); Texts.WriteString(W, Modules.resMsg);
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
		RETURN NIL
	END;
	IF Objects.NewObj = NIL THEN
		Texts.WriteString(W, objname); Texts.WriteString(W, " is not a generator procedure or alias"); Texts.WriteLn(W); Log;
	END;
	RETURN Objects.NewObj
END CreateObject;

(** Create a View/Model pair from the generator procedures viewnewproc and modelnewproc. Aliasing is supported. *)
PROCEDURE CreateViewModel*(viewnewproc, modelnewproc: ARRAY OF CHAR): Display.Frame;
VAR F: Display.Frame; obj: Objects.Object; L: Objects.LinkMsg;
BEGIN	
	obj := CreateObject(viewnewproc);	
	IF obj # NIL THEN
		IF ~(obj IS Display.Frame) THEN
			Texts.WriteString(W, viewnewproc);
			Texts.WriteString(W, " is not a Display.Frame generator procedure"); 
			Texts.WriteLn(W); Log;
			RETURN NIL;
		END;
		F := obj(Display.Frame);
		IF modelnewproc # "" THEN
			obj := CreateObject(modelnewproc);
			IF (F IS Frame) THEN
				L.id := Objects.set; L.obj := obj; L.name := "Model"; L.res := -1; F.handle(F, L);
				IF L.res < 0 THEN Texts.WriteString(W, " Model could not be set"); Texts.WriteLn(W); Log END;
				RETURN F;
			ELSE
				Texts.WriteString(W, viewnewproc);
				Texts.WriteString(W, " is not a Gadget"); 
				Texts.WriteLn(W); Log;
				RETURN F;
			END;
		ELSE
			RETURN F;
		END;
	END;
	RETURN NIL;
END CreateViewModel;

(** Adds a generator alias. *)
PROCEDURE AddAlias*(name, value: ARRAY OF CHAR);
VAR a, b: Alias;
BEGIN
	IF aliases = NIL THEN
		NEW(a); aliases := a; COPY(name, a.name);
	ELSE
		a := aliases; b := NIL;
		WHILE (a # NIL) & (a.name # name) DO b := a; a := a.next END;
		IF a = NIL THEN
			NEW(a); b.next := a; COPY(name, a.name)
		END;
	END;
	COPY(value, a.value);
END AddAlias;

(** Command to insert a newly allocated gadget at the caret. Used in the form:

	Gadgets.Insert <generatorproc> ~		for a single object
		or
	Gadgets.Insert <viewgeneratorproc> <modelgeneratorproc> ~	for a model-view pair
	
	Aliasing is supported.
*)
PROCEDURE Insert*; (* ^ is "Frame.New Thing.New" *)
VAR S: Attributes.Scanner; fname, tname: ARRAY 32 OF CHAR;  F: Display.Frame;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF S.class = Attributes.Name THEN
		COPY(S.s, fname);
		Attributes.Scan(S);
		IF S.class = Attributes.Name THEN
			COPY(S.s, tname);
			F := CreateViewModel(fname, tname);
			IF F # NIL THEN
				Integrate(F);
				IF (F IS Frame) & (F(Frame).obj # NIL) THEN Update(F(Frame).obj) END;
			END;
		ELSE
			Integrate(CreateViewModel(fname, ""));
		END
	END;
	Objects.NewObj := NIL;
END Insert;

(** Returns the latest object selection. Time < 0 indicates no selection. *)
PROCEDURE GetSelection*(VAR objs: Objects.Object; VAR time: LONGINT);
VAR SM: Display.SelectMsg;
BEGIN time := -1; objs := NIL;
	SM.id := Display.get; SM.F := NIL; SM.sel := NIL; SM.obj := NIL; SM.time := -1; Display.Broadcast(SM);
	IF (SM.time >= 0) & (SM.obj # NIL) THEN
		time := SM.time; objs := SM.obj
	END
END GetSelection;

(** Search for the object "O" in the public library "L.Lib" where the name is specified as "L.O" and return a deep copy or shallow copy. *)
PROCEDURE CopyPublicObject*(name: ARRAY OF CHAR; deep: BOOLEAN): Objects.Object;
	VAR
		C: Objects.CopyMsg;
		obj: Objects.Object;
BEGIN
	obj := FindPublicObj(name);
	IF obj # NIL THEN
		Objects.Stamp(C); C.obj := NIL;
		(* ejz 10.7.96 *)
		IF deep THEN C.id := Objects.deep
		ELSE C.id := Objects.shallow
		END;
		obj.handle(obj, C);
		RETURN C.obj
	ELSE
		RETURN NIL
	END
END CopyPublicObject;

(** Changes the selected frame into a new frame type. Used in the form

	Gadgets.Change <generatorproc>
	
	Aliasing is supported.
*)
PROCEDURE Change*; (* ^ Frame.New *)
VAR S: Attributes.Scanner; C: Display.ConsumeMsg;
	fname: ARRAY 32 OF CHAR; oF, nF: Display.Frame; CM: Display.ControlMsg;
	SM: Display.SelectMsg; obj: Objects.Object;
BEGIN
	SM.id := Display.get; SM.F := NIL; SM.sel := NIL; SM.obj := NIL; SM.time := 0;
	Display.Broadcast(SM);
	IF SM.time > 0 THEN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class = Attributes.Name THEN
			COPY(S.s, fname);
			nF := CreateViewModel(fname, "");
			IF (nF # NIL) & (SM.obj IS Display.Frame) THEN
				obj := SM.obj;
				WHILE obj # NIL DO
					oF := obj(Display.Frame);
					nF.X := oF.X; nF.Y := oF.Y;
					IF (nF IS Frame) & (oF IS Frame) THEN
						nF(Frame).obj := oF(Frame).obj;
						IF ~(lockedsize IN nF(Frame).state) THEN
						nF.W := oF.W; nF.H := oF.H;
					END;
					END;
					obj := obj.slink;
					CM.id := Display.remove; CM.F := oF; Display.Broadcast(CM); (* <<< remove *)
					C.id := Display.drop; C.F := SM.sel; C.u := nF.X; C.v := nF.Y; C.obj := nF;
					Display.Broadcast(C);
					IF (nF IS Frame) & (nF(Frame).obj # NIL) THEN Update(nF(Frame).obj) END;
					IF obj # NIL THEN nF := CreateViewModel(fname, ""); END;
				END;
			END;
		END;
	END;
END Change;

(** Make a deep copy of the object selection and insert the result at the caret. *)
PROCEDURE Copy*;
VAR M: Display.SelectMsg; p, nl: Objects.Object; C: Objects.CopyMsg; CM: Display.ConsumeMsg;
BEGIN
	M.id := Display.get; M.F := NIL; M.time := 0; M.sel := NIL; M.obj := NIL; Display.Broadcast(M);
	IF M.time > 0 THEN
		p := M.obj; nl := NIL; Objects.Stamp(C);
		WHILE p # NIL DO
			C.id := Objects.deep; p.handle(p, C);
			C.obj.slink := nl; nl := C.obj;
			p := p.slink
		END;
		CM.id := Display.integrate; CM.obj := nl; CM.F := NIL; Display.Broadcast(CM);
	END;
END Copy;

(** Change the value(s) of (an) attribute(s) in the object selection. Used in the form:

		Gadgets.ChangeAttr <AttributeName> <AttributeValue> ~
	
	AttributeValue can take several forms, depending on the type of the attribute:

	names		For string attributes
	Yes/No      For boolean attributes	 
	1234	  	For number attributes
	"strings"	For string attributes
*)
PROCEDURE ChangeAttr*;
VAR S: Attributes.Scanner; M: Display.SelectMsg; obj: Objects.Object; A: Objects.AttrMsg; U: UpdateMsg;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN
		A.id := Objects.set; COPY(S.s, A.name);
		Attributes.Scan(S); A.class := Objects.Inval; A.s := "";
		IF S.class = Attributes.Int THEN A.class := Objects.Int; A.i := S.i;
		ELSIF S.class = Attributes.Name THEN A.class := Objects.String; COPY(S.s, A.s);
		ELSIF S.class = Attributes.String THEN A.class := Objects.String; COPY(S.s, A.s);
		END;
		IF (A.s = "Yes") OR (A.s = "No") THEN Strings.StrToBool(A.s, A.b); A.class := Objects.Bool END;
		IF A.class # Objects.Inval THEN
			M.id := Display.get; M.F := NIL; M.sel := NIL; M.obj := NIL; M.time := 0; Display.Broadcast(M);
			IF M.time > 0 THEN
				obj := M.obj;
				WHILE obj # NIL DO
					A.res := -1;
					obj.handle(obj, A);
					IF A.res = -1 THEN
						Texts.WriteString(W, "Attribute not set"); Texts.WriteLn(W); Log;
					END;
					obj := obj.slink;
				END;
				U.obj := M.obj; U.F := NIL; Display.Broadcast(U);
			ELSE
				Texts.WriteString(W, "No selection"); Texts.WriteLn(W); Log;
			END;
		END;
	END;
END ChangeAttr;

(** Set an attribute value of a named object. Used in the form:

	Gadgets.Set O.A <AttributeValue> ~		for attribute A of named object O in the current context
*)	
PROCEDURE Set*; (* O.A value *)
VAR S: Attributes.Scanner; name: ARRAY 64 OF CHAR; i, j: INTEGER; attr: ARRAY 32 OF CHAR; obj: Objects.Object;
	A: Objects.AttrMsg;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	name := "";
	IF S.class = Attributes.String THEN COPY(S.s, name)
	ELSIF S.class = Attributes.Name THEN COPY(S.s, name)
	END;
	WHILE name[0] = "." DO
		i := 0;
		REPEAT
			name[i] := name[i+1]; INC(i)
		UNTIL name[i] = 0X;
		IF context # NIL THEN
			context := context.dlink
		END
	END;
	Attributes.Scan(S);
	A.class := Objects.Inval; A.s := ""; A.id := Objects.set;
	IF S.class = Attributes.Int THEN A.class := Objects.Int; A.i := S.i;
	ELSIF S.class = Attributes.Real THEN A.class := Objects.Real; A.x := S.x;
	ELSIF S.class = Attributes.LongReal THEN A.class := Objects.LongReal; A.y := S.x;
	ELSIF S.class = Attributes.Name THEN A.class := Objects.String; COPY(S.s, A.s);
	ELSIF S.class = Attributes.String THEN A.class := Objects.String; COPY(S.s, A.s);
	END;
	IF (A.s = "Yes") OR (A.s = "No") THEN Strings.StrToBool(A.s, A.b); A.class := Objects.Bool END;
	
	IF (A.class # Objects.Inval) & (name # "") THEN
		i := 0; WHILE name[i] # 0X DO INC(i); END;
		WHILE (i > 0) & (name[i] # ".") DO DEC(i); END;
		IF name[i] = "." THEN
			name[i] := 0X; INC(i); j := 0;
			WHILE name[i] # 0X DO attr[j] := name[i]; INC(i); INC(j); END;
			attr[j] := 0X; COPY(attr, A.name);
			obj := FindObj(context, name);
			IF obj # NIL THEN
				obj.handle(obj, A);
				IF A.res = -1 THEN
					Texts.WriteString(W, "Attribute not set"); Texts.WriteLn(W); Log;
				ELSE Update(obj)
				END
			END
		END
	END
END Set;

(** Create a new Model gadget and link it to all the visual objects in the current selection. Used in the form:

	Gadgets.Link <modelgenerator> 
	
	Aliasing is supported. An Objects.LinkMsg is sent behind the scenes.
*)
PROCEDURE Link*;
VAR S: Attributes.Scanner; M: Display.SelectMsg; obj, o: Objects.Object; B: Objects.BindMsg;
	L: Objects.LinkMsg; oname: ARRAY 64 OF CHAR;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN
		M.id := Display.get; M.F := NIL; M.sel := NIL; M.obj := NIL; M.time := 0; Display.Broadcast(M);
		COPY(S.s, oname);
		obj := CreateObject(oname);
		IF (obj # NIL) & (M.time > 0) THEN
			o := M.obj;
			IF o # NIL THEN
				IF o.lib # NIL THEN B.lib := o.lib; obj.handle(obj, B) END (* bind *)
			END;
			WHILE o # NIL DO
				IF o IS Frame THEN
					L.id := Objects.set; L.name := "Model"; L.obj := obj; L.res := -1; o.handle(o, L);
					IF L.res < 0 THEN Texts.WriteString(W, " Model could not be set"); Texts.WriteLn(W); Log
					END
					(* old way 
					o(Frame).obj := obj
					*)
				END;
				o := o.slink
			END;
			Update(obj)
		END
	END
END Link;

PROCEDURE Parse(VAR S:Texts.Scanner; VAR A: Attributes.Attr; VAR errpos: LONGINT);
VAR sname: ARRAY 32 OF CHAR; i: Attributes.IntAttr; r: Attributes.RealAttr; s: Attributes.StringAttr; a, a0: Attributes.Attr;
BEGIN
	A := NIL; errpos := -1;
	WHILE S.class IN {Texts.Name, Texts.String} DO
		COPY(S.s, sname);
		Texts.Scan(S);
		IF (S.class =  Texts.Char) & (S.c = "=") THEN
			Texts.Scan(S);
			IF S.class =  Texts.Name THEN
				NEW(s); COPY(sname, s.name); COPY(S.s, s.s); a := s;
			ELSIF S.class =  Texts.Int THEN
				NEW(i); COPY(sname, i.name); i.i := S.i; a := i;
			ELSIF S.class =  Texts.String THEN
				NEW(s); COPY(sname, s.name); COPY(S.s, s.s); a := s;
			ELSIF S.class =  Texts.Real THEN
				NEW(r); COPY(sname, r.name); r.r := S.x; a := r
			ELSIF S.class =  Texts.LongReal THEN
				NEW(r); COPY(sname, r.name); r.r := S.y; a := r
			ELSE errpos :=  0; RETURN
			END;
			IF A = NIL THEN A := a; a0 := A ELSE a0.next := a; a0 := a END
		ELSE errpos :=  0; RETURN END;
		Texts.Scan(S)
	END;
	IF (S.class # Texts.Char) OR (S.c # "}") THEN errpos := 0 END
END Parse;

PROCEDURE LoadAliases;
VAR A: Attributes.Attr; errpos: LONGINT;  S: Texts.Scanner;
BEGIN
	Oberon.OpenScanner(S, "Gadgets.Aliases");
	IF S.class = Texts.Inval THEN
		Texts.WriteString(W, "Oberon.Text - Gadgets.Aliases not found");
		Texts.WriteLn(W); Log
	ELSE
		Parse(S, A, errpos);
		IF errpos >= 0 THEN
			Texts.WriteString(W, "Error in Gadgets.Aliases");
			Texts.WriteLn(W); Log
		ELSE
			WHILE A # NIL DO
				IF A IS Attributes.StringAttr THEN
					WITH A: Attributes.StringAttr DO
						 AddAlias(A.name, A.s);
					END
				END;
				A := A.next;
			END;
		END
	END;
	Oberon.OpenScanner(S, "Gadgets.Verbose");
	verbose := ((S.class = Texts.Name) OR (S.class = Texts.String)) & (CAP(S.s[0]) = "Y")
END LoadAliases;

BEGIN
	Texts.OpenWriter(W); Texts.OpenWriter(WW); Texts.OpenWriter(mW);
	NEW(emptyText); Texts.Open(emptyText, "");
	LoadAliases;

	IF Display.Width < 800 THEN
		Texts.WriteString(W, "Higher resolution recommended for Gadgets");
		Texts.WriteLn(W);  Log
	END;

	Attributes.AddMacro("&", StandardMacros); (* lookup *)
	Attributes.AddMacro("#", StandardMacros); (* executor *)
	Attributes.AddMacro("!", StandardMacros); (* sender *)
	Attributes.AddMacro("'", StandardMacros); (* substitute *)
	Attributes.AddMacro("^", UpArrowMacro);
	
	framehandle := FrameHandler; objecthandle := ObjectHandler;
	MakeMask := MakeMask0; MakePrinterMask := MakePrinterMask0;
	Oberon.Collect()
END Gadgets.

(** Remarks:

1. Objects
The type Gadgets.Object forms the base class of all model gadgets. Examples of these are the Integer, Boolean, Real, String and Complex gadgets.

2. Frames
The Frame definition is the base type of all displayable gadgets (sometimes called views when discussed in relation to the MVC model). The state variable (a SET) plays an important role in controlling the gadget frame. It remembers state information and controls editing abilities by setting flags. A flag is represented by a small integer value (a flag is set if that number is a member of the state set). The selected flag indicates if the gadget is selected or not. The lockedsize flag prevents resizing of the gadget. The transparent flag indicates that a gadget is transparent. It is possible to "see through" parts of a transparent gadget to gadgets lying behind it. The lockchildren flag locks the direct children of a container gadget. A locked gadget cannot be moved or resized. The lockchildren flag is inspected by the IsLocked function and also used by the InActiveArea function to determine if a gadget can be moved or resized. This flag is normally visible to the outside world through a "Locked" attribute.
The obj field points to the model of the gadget (if it has one). The mask field contains the gadget cached mask. This mask is calculated by the parent of a gadget, and transfered from parent to child through the Display3.OverlapMsg. During editing operations in the display space, the mask might become invalid due to new gadgets overlapping the gadget. In this case, a parent will invalidate the mask by setting no (i.e. NIL) mask. This results in the cached mask to be set to NIL. However, as soon as a gadget wants to display itself, the MakeMask procedure will notice the invalidated mask and request its parent to inform it of the correct mask (using Display3.UpdateMaskMsg). The mask is located in the fourth quadrant, with the top left corner of the gadget positioned at the origin (0, 0) of the mask. Before displaying a visual gadget, the cached mask is translated to the correct position on the display. This is done by a call to Gadgets.MakeMask.

3. Views
The View type forms the base of a special class of gadgets called camera-views. A camera-view displays other displayable gadgets. Different camera views may display the same gadget, where each camera view may display a different part of it. The View base type is used to calculate the actual visible area of the object being viewed. This operation is hidden behind the secens in Gadgets.MakeMask. The absX, absY pair indicate the absolute position of the camera view on the display. This is set by the camera view itself when it forwards a message down to its model (i.e. the thing it is displaying). The border field indicates how wide the border of the camera view is (the border clips away parts of the model).
	The display mask generation of Gadgets.MakeMask is intimitely coupled with the structure of the display space. The remainder of this paragraph is for those curious about how mask calculation is done. The display space is organized in a DAG-like structure. Messages travel through the DAG, possibly passing to the same frame through different messages paths Conceptually, we take the DAG and partition it into separate display groups. This is done by removing all the edges in the DAG that connect a camera view with its model, and eliminating all the non-visual gadgets and their corresponding edges. As no multiple views of the same visual gadget through camera views are involved, the mask of each gadget in a display group only takes into account the overlapping between gadgets in the same display group. These masks remain static, and can be cached for each gadget. This is under the assumption that the root object of a display-group is completely visible. In practice, display groups corresponds to panels and their contents.
	The display groups are used to determine the visibility of a gadget when it calls Gadgets.MakeMask. Using the message thread, all camera-views from the root of the display space to the displayed frame are visited. For each of these, the camera-view can influence the visibility of its descendants. By intersecting the cached mask of a gadget with all of the masks of the camera-views located in the message path, we can determine exactly what area of a gadget is visible.

4. UpdateMsg
The Smalltalk MVC framework is supported with the UpdateMsg. This message must always be broadcast to inform everybody of a change of a model gadget. It contains a pointer to the object that has changed. All gadgets that have this object as a model, has to update themselves. The object that changes need not always be a model gadget; it can also be a frame (this indicates that the frame's parent should redraw the frame). In the latter case, a whole list of frames may be updated (the frames are linked through the slink field). By convention, all the frames updated should belong to one single parent.

5. PriorityMsg
The Priority message allows the changing of the overlapping order of gadgets. Each container gadget contains a list of children gadgets, where the position in the dsc-next list specifies the overlapping priority (from back to front). Changing the position of a child in the list has the affect of moving it to the front or the back in the container. When the PriorityMsg is broadcast the destination F indicates the child that wants to change its display priority. The top, bottom and visible flags are used to move the child to the front, to the back or to make it visible when not. The visible flag has the affect of moving the child to the front only when it is overlapped by a sibling. Otherwise, no action is undertaken. The passon flag indicates if the priority change should be recursive, meaning that the parent of F and onwards should also change priority, and thus bring a whole hierarchy to the front or back.

6. Default message handlers
To simplify programming, default handlers for model and visual gadgets are provided. These may be called to handle messages a default way. The default frame handler (framehandle) responds to the Objects.FileMsg (storing/loading X, Y, W, H, state, obj and attr), Objects.CopyMsg (calls CopyFrame), BindMsg (calls BindObj), Objects.AttrMsg, Objects.FindMsg (returning itself or the model), Display.DisplayMsg (simply draws rectangle), Display3.OverlapMsg, Display.LocateMsg, Display.ModifyMsg (calls Adjust), Display.SelectMsg (only flips the selected flag), Display.ConsumeMsg (executes the ConsumeCmd attribute if the gadget has one), Display.ControlMsg (forwards it to the gadgets model), and Oberon.InputMsg (calling TrackFrame on a mouse track event). The default model gadget handler (objecthandle) respond to the Objects.FileMsg (storing/loading attr), Objects.AttrMsg, Objects.BindMsg (calls BindObj), Objects.CopyMsg (calling CopyObject), and Objects.FindMsg (returning the model if the names match).

7. The Imaging Model
Two important relationships exist between gadgets: the view relationship and parent-child relationship. A panel may display several gadgets contained inside of it. This is the parent-child relationship, where the children are displayed and managed by the parent. The parent does not assume anything about the type of its children, and the children do not assume to be contained in an object of a specified type. This allows a gadget to be integrated in all environments, and for parents to manage children that are unknown to it. This is the principle of complete integration and plays a central role in the gadgets system.
	 The view relationship allows one gadget to display or view another gadget. The first (the viewer) may either visualize the state of the viewed gadget (for example, a slider representing an integer value), or display the viewed gadget. In the first case, a model is viewed, while in the latter, a displayable object is viewed (a camera-view). Models form the interface to the application, and displayable models allow the same gadget to be displayed many times on the display. Many different views of the same object (model or displayable) may be possible, where each view can visualize the viewed object in a different manner. Views may be nested to an arbitrary depth, as long as no recursive views are created. Messages travel through the system informing views that a model has changed. These Update messages indicate the model involved, which the views may check to find out if it needs to redisplay or recalculate itself. The model-view framework is open; it is also possible for one model gadget to be dependent on another model gadget.You may have different representations of the same data, allow objects to depend on others, and allow data or objects to be shared between different documents.
	It is this flexible model-view framework combined with the ability to have gadgets overlapping each other and edited-in-place, that complicates the imaging model. A displayable gadget may be partially visible through one camera-view, and partially visible through another. The same object, can be seen and edited two or more times on different areas of the display. Also, some of these camera-views may be partially overlapped by other displayable gadgets. The problem is compounded when camera-views are nested inside camera-views, increasing the number of display instances. Thus a gadget may potentially have to display itself in many different ways. Clearly, with a single displayable gadget having so many different display instances (one for each view, in the simplest case), the gadget cannot have one unique display coordinate. The gadgets system uses relative coordinates, where the coordinate of a gadget is always relative to its parent. All displayable frame are connected to a data structure called the display root. Broadcasting a message through the display space causes all displayable objects in the structure to be reached. If we assume that views relay the message to the objects they display, the display space forms a directed a-cyclic graph (DAG). There are certain objects where two or more message paths converges. Such a convergence point can occur when two or more camera-views display the same object. Thus during a single message broadcast, the message may arrive twice or more times at the same object. If this object is displayable, it receives the message exactly once for each of its display instances. For each of these message arrivals, the gadget should have different coordinates on the display.
	In practice, the coordinates of a gadget is determined by the path the message follows to reach that gadget. Each message relay operation may change the coordinate system. This is reflected in the origin stored in the message. The display coordinates of a display instance of a gadget is thus the combination of the current origin (in the message) and the relative coordinates of the gadget itself. A gadget can be prompted into displaying itself on many different locations on the display by varying the origin of the message. This is called the multiple view model of the gadgets system.
	The main disadvantage of the multiple view model is that potentially each display instance of a frame may have a different visible area. Theoretically, the visible area of a display instance is a function of the message path to that instance. A data structure is used to indicate what part of a gadget is visible. Such a data structure is called a display mask. The mask can be constructed as the message travels through the display space, continually being reduced and expanded as the message travels. It consists of a set of non-overlapping rectangles which indicate which areas of the gadget are visible. Drawing primitives are issued through this mask, which has the effect of clipping them only to the visible areas in the mask. Operations on masks are also provided. You can, for example, calculate the intersection or union between masks, or enumerate all the visible areas in a mask.
	Implementing the sketched procedure is inefficient. Masks may be calculated that are not used at all (not all broadcasts are display related). Also, masks should be cached for each display instance, rather being recalculated each time. In practice, a imaging model is used that is based on these observations. The following remarks give an idea of how things have actually been implemented.

8. Masks
Each gadget has a mask that shows which areas of it are visible. The mask field can be set to NIL, to indicates that no mask exists. A gadget can only be displayed once it becomes a mask. Should no mask exist, the Display3.UpdateMaskMsg is broadcast, with F set the maskless gadget. The parent of F is responsible for creating a new mask for F. The Display3.OverlapMsg is used to inform the gadget of its new mask. It is sent directly from the parent to the gadget (the above protocol is explained in the section about the Display3 module).
	The mask generation is hidden from gadget programmers. When displaying a gadget, the mask's relative coordinates have to be converted into absolute screen coordinates, or possibly even a new mask created (as described above). The whole process is hidden behind the procedures MakeMask and MakePrinterMask. G is the frame for which a mask is needed, X and Y indicate the absolute screen position of the left-bottom corner of G, and dlink is the context of G. The context of G can be found in the dlink field of the received frame message. The MakePrinterMask procedure variable functions in the same way, except that a mask for the printer is created. For the latter X, Y should be the absolute printer coordinates of the gadget. The resulting masks are return in variable parameter M, and can immediately be used for displaying or printing the gadget.
	
9. Mask Calculations
	Masks are calculated from the intersection of the cached mask of a gadget and all the camera-views through which a message travels. We need a backward traversal from the gadget through all the display groups. On receiving a frame message, the dlink field in the message points to the first frame in the message thread. The list can be traversed further backwards with the dlink field of the frame. The backward traversal can continue by following the dlink fields through all frames in the thread. Thus when masks are generated one should distinguish between normal frames and camera-views, as we are only interested in camera-views when generating masks. Broadcast messages travel from one display group to another (through views) to reach a gadget. Thus the actual visible area of a gadget is the intersection of its static/cached mask plus all the masks of views through which the message travelled. This calculation only need to be made on demand. For example, when a gadget decides to display itself, it calls MakeMask to build it's visibility mask. MakeMask has to find out the path the message traveled to reach the gadget, extract all the camera-views, and build the intersection of the static mask plus all the masks of the views. This can be done by following the message path back from the receiver gadget to the root of the display.
	Typically we don't want to modify the static mask of a gadget. However, this mask will be changed by the intersection process during mask calculation. Observations shows that the masks of views are mostly rectangular, i.e they are seldomly partially overlapped. If we assume that this is always the case, the mask calculation is nothing more than reducing the static mask by rectangular areas (clipping windows or ports). For this situation, the mask is provided with a rectangular clipping port, to which all output primitives are clipped after they have been clipped by the mask itself. The simple structure of the clipping port means that it can easily be saved, modified and restored, without affecting the static portion of the mask. Of course, the latter condition fails when the views are also partially obscured. In this case, the mask calculation has to be done in the less efficient way.

10. Command Execution
Gadgets may execute Oberon commands (procedures Execute and ExecuteAttr) specified by their command attributes. Commands can take their parameters from the user interface. For this purpose, several global variables are exported from the gadgets module. The variable context identifies the context, normally the parent, of the gadget executing the command. The context of a gadget is found in the dlink field of a Display.FrameMsg the gadget receives. The variable executorObj identifies the gadget executing the command, which is always the same as Oberon.Par.obj. The senderObj and receiverObj identifies the objects involved in consume operations, and may be NIL.

11. Aliasing
The Gadgets module implements a simple aliasing feature. This allows the user to give more meaningful abbreviations or names to the not so easy to remember object generator procedures. The principle client of aliasing are the Gadgets.Insert and Gadgets.Link commands. The aliases are found in the Oberon.Text/Registry section called Aliases. The aliases are read into an internal lookup table when the Gadgets module is loaded for the first time. The format of each line of the Aliases section is:

			Alias=GeneratorProc

*)
