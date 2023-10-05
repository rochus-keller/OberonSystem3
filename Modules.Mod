(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE Modules;	(** portable, except where noted *)	(* rc/mh/jm/tk/ard/rml/prk/pjm *)

(**
 The Modules module implements the dynamic module loader of the Oberon system. 
 It is responsible for loading and freeing modules.
*)

IMPORT Kernel;

CONST
	done = 0;
	fileNotFound = 1;
	invalidObjFile = 2;
	corruptedObjFile = 4;
	cmdNotFound = 5;
	moduleNotFound = 6;
	notEnoughSpace = 7;
	refCntNotZero = 8;
	cyclicImport = 9;
	incompImport = 16;

TYPE
	Command* = Kernel.Proc;
	Module* = Kernel.Module;
	ModuleName* = Kernel.Name;

VAR
	res*: INTEGER;	(** Error code for ThisMod and ThisCommand. res = 0 indicates success. *)
	resMsg*: ARRAY 256 OF CHAR;	(** Explanation of res, if res # 0 *)
	extension*: ARRAY 8 OF CHAR;	(** Extension of object files (non-portable) *)
	resMsgLen: LONGINT;
	
	imported, importing: ModuleName;	(* Specifies the modules involved in a key mismatch. *)
	
	
(* Error Messages *)

PROCEDURE Ch(ch: CHAR);
BEGIN
	IF resMsgLen # LEN(resMsg)-1 THEN
		resMsg[resMsgLen] := ch; INC(resMsgLen); resMsg[resMsgLen] := 0X
	END
END Ch;

PROCEDURE Str(IN s: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN
	i := 0; WHILE s[i] # 0X DO Ch(s[i]); INC(i) END
END Str;

PROCEDURE Clear;
BEGIN
	resMsg[0] := 0X; resMsgLen := 0
END Clear;

PROCEDURE ErrMsg(res: INTEGER);
BEGIN
	IF res # 0 THEN
		Clear;  Str(importing);
		IF (res = fileNotFound) OR (res = moduleNotFound) THEN Str(" not found")
		ELSIF res = invalidObjFile THEN Str(" not an obj-file")
		ELSIF res = corruptedObjFile THEN Str(" corrupted obj file")
		ELSIF res = notEnoughSpace THEN Str(" not enough space")
		ELSIF res = refCntNotZero THEN Str(" reference count not zero")
		ELSIF res = cyclicImport THEN Str(" cyclic import")
		ELSIF res = incompImport THEN
			Str(" imports incompatible version of ");  Str(imported);
		ELSIF res = cmdNotFound THEN
			Clear;  Str(imported);  Ch(".");  Str(importing);
			Str(" command not found");  (* assumes importing = procedure name and imported = module name *)
		ELSE Str(" unknown error code")
		END;
		Kernel.WriteString("Modules: ");  Kernel.WriteString(resMsg);  Kernel.WriteLn
	END
END ErrMsg;

(** Returns a handle to an already loaded module. *)

PROCEDURE FindMod*(IN name: ARRAY OF CHAR): Module;
VAR m: Module;
BEGIN
	m := Kernel.modules;
	WHILE (m # NIL) & (m.name # name) DO m := m.next END;
	RETURN m
END FindMod;


(*---- module loading ---- *)

PROCEDURE Load (IN name: ARRAY OF CHAR; VAR m: Module);
	VAR i, j: INTEGER; fname: ARRAY 64 OF CHAR; tag: CHAR;
BEGIN
	m := FindMod(name); res := done; Clear;
	IF m = NIL THEN
    IF ~LDMOD(name) THEN 
      res := invalidObjFile; 
  		Str("Error loading module "); Str(name); 
  		Kernel.WriteString(resMsg);  Kernel.WriteLn
    ELSE imported := name;
      NEW(m);
      m.name := name;
      m.next := Kernel.modules;
      Kernel.modules := m
    END
	END
END Load;

(** Returns a handle to an already loaded module, or if not loaded, loads the module and all its imported modules. *)

PROCEDURE ThisMod* (IN name: ARRAY OF CHAR): Module;
	VAR mod: Module;
BEGIN
	Load(name, mod);
	RETURN mod
END ThisMod;

(** Returns a procedure variable representing an exported command in a module. 
Calling this procedure executes the command. *)

PROCEDURE ThisCommand* (mod: Module; IN name: ARRAY OF CHAR): Command;
	VAR i: LONGINT; cmd: Command;
BEGIN
	IF mod # NIL THEN
		cmd := LDCMD(mod.name,name);
		IF cmd = NIL THEN 
  		res := cmdNotFound;
  		Str("Error loading command "); Str(mod.name); Str("."); Str(name); 
  		Kernel.WriteString(resMsg);  Kernel.WriteLn
  	ELSE res := done END;
		RETURN cmd
	END;
	RETURN NIL
END ThisCommand;

PROCEDURE Delete (m: Module);
	VAR m1: Module;
BEGIN
	m1 := Kernel.modules;
	IF m = m1 THEN
		Kernel.modules := m.next
	ELSE
		WHILE m1.next # m DO m1 := m1.next END;
		m1.next := m.next
	END
END Delete;

(** Free a module from memory. Only modules with no clients can be freed. The all flag requests that 
all imported modules should be freed too (i.e. a recursive call to Free). *)
PROCEDURE Free* (IN name: ARRAY OF CHAR; all: BOOLEAN);
	VAR m, m1: Module; i, j: LONGINT;
BEGIN
	res := done;  Clear;
	m := FindMod(name);
	IF m = NIL THEN importing := name; res := moduleNotFound; ErrMsg(res)
	ELSIF m.refcnt # 0 THEN importing := m.name; res := refCntNotZero; ErrMsg(res)
	ELSE
		// TODO Kernel.FinalizeModule(m);
		i := LEN(m.imports);
		WHILE i > 0 DO DEC(i); m1 := m.imports[i]; DEC(m1.refcnt) END;
		IF all THEN i := LEN(m.imports);
			WHILE i > 0  DO DEC(i); m1 := m.imports[i]; Free(m1.name, TRUE) END;
			res := done;  Clear
		END;
		Delete(m);
			(* now clear the module block *)
	END
END Free;

(** InstallTermHandler - Install a procedure to execute when a module is freed. 
Never perform upcalls in the installed procedure! *)

PROCEDURE InstallTermHandler*(h: Kernel.Proc);
BEGIN
	Kernel.InstallTermHandler(h)
END InstallTermHandler;

BEGIN
(*
	Kernel.GetConfig("ModExt", extension);
	IF extension = "" THEN extension := ".Obj" END;
	Kernel.GetConfig("TraceModules", disp);  trace := (disp[0] = "1");
	Kernel.GetConfig("Init", disp);
	IF disp = "9090" THEN
		disp := "Empty."	(* tracing *)
	ELSE
		Kernel.GetConfig("Display", disp)
	END
	*)
END Modules.

(** Remarks:

1. Oberon uses reference counting to determine how many clients of a module are loaded.
A module can only be freed when the reference count is 0.

2. The res codes are not the same numerically on all Oberon platforms. It is advisable to use
the resMsg as a correct indication of the error condition.

3. Module and command names are single words consisting of A to Z, a to z, and 0 to 9.
Names must not start with a digit.

4. Care should be taken freeing modules. Oberon cannot detect if a client has a procedure
variable still "pointing" at code in a freed module. Calling such a procedure can be
unpredictable at times, although the system generates a trap most of the time.
*)

