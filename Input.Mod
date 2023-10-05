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

MODULE Input;	(** portable, except where noted *)	(* pjm *)

(*
	Native Oberon Input, pjm 09.06.95
	Mouse protocol information from XFree in X11R6 distribution (Thomas Roell & David Dawes)
	PS/2 Aux port information from Linux (Johan Myreen et al.)
*)

(**
Module Input is responsible for event timing, mouse and keyboard input.
*)

IMPORT
	Files, Display, Kernel, V24, SYSTEM;

CONST
	TimeUnit* = 1000;	(** portable, but VAR on other ports *)	(** timer ticks per second (platform dependent). *)

	SHIFT* = 0;  CTRL* = 1;  ALT* = 2;	(** for GetShiftState *)
	
	BufSize = 32;	(* keyboard buffer size *)
	AuxSize = 301;	(* PS/2 aux port buffer size (multiple of 3 + 1)*)

	ScrollLock = 0;  NumLock = 1;  CapsLock = 2;  LAlt = 3;  RAlt = 4;
	LCtrl = 5;  RCtrl = 6;  LShift = 7;  RShift = 8;  GreyEsc = 9;
	Resetting = 10;  SetTypematic = 11;  SendingLEDs = 12;
	DeadKey = 0;
	
	AUX = -1;  NONE = -2;
	
	Trace = FALSE;

		(* mouse types *)
	MinType = 0;  MaxType = 9;
	MS = 0;  MSC1 = 1;  MM = 2;  Logi = 3;  MSC2 = 4;  LogiMan = 5;  PS2 = 6;  MSI = 7;  MSC3 = 8;  MSC4 = 9;
(* Native.Install.Text & build tool
	0  Microsoft serial (2-button)
	1  Mouse Systems Corp serial type a (dtr on, rts on)
	2  Logitech serial Type a (old models)
	3  Logitech serial Type b (old models)
	4  Mouse Systems Corp serial type b (dtr off, rts off)
	5  Logitech serial Type c (new models)
	6  PS/2 mouse (default)
	7  Microsoft serial IntelliMouse
	8  Mouse Systems Corp serial type c (dtr off, rts on)
	9  Mouse Systems Corp serial type d (dtr on, rts off)
	
	MT=PS2  PS/2 or built-in
	MT=LM1  Logitech 1
	MT=LM2  Logitech 2
	MT=LM3  Logitech 3
	MT=MS1  Mouse Systems 1
	MT=MS2  Mouse Systems 2
	MT=MS3  Mouse Systems 3
	MT=MS4  Mouse Systems 4
	MT=MSM  Microsoft (2-button)
	MT=MSI  Microsoft IntelliMouse
	MP=1
	MP=2
*)

VAR
	mouseErrors, auxoverflows: LONGINT;
	
		(* mouse state *)
	minX, minY, maxX, maxY, mouseX, mouseY: LONGINT;
	port, oldport, newport, rate: INTEGER;	(* Serial mouse port, bps and report rate (if supported) *)
	bps: LONGINT;
	type: SHORTINT;	(* mouse type *)
	buttons: SHORTINT;	(* -2, -3, 2, 3 *)
	mapkeys: ARRAY 8 OF SET;
	mbufp, numb: SHORTINT;	(* buffer pointer & protocol bytes *)
	mbuf: ARRAY 5 OF SET;	(* protocol buffer *)
	mask0, val0, mask1, val1, lastkeys: SET;	(* protocol parameters *)
	auxbuf: ARRAY AuxSize OF CHAR;	(* aux port buffer *)
	auxhd, auxtl: INTEGER;	(* aux buffer pointers *)
	threshold: INTEGER;	(* speedup threshold *)
	speedup: LONGINT;
	auxinit: BOOLEAN;

		(* keyboard state *)
	buffer: ARRAY 1+BufSize OF CHAR;	(* first byte not used (security) *)
	head, tail, dkey: SHORTINT;
	escNeutralise: BOOLEAN;
	lastport: LONGINT;
	lastvalue: SYSTEM.BYTE;
	keyval: INTEGER;
	table: LONGINT;
	flags: SET;
	breakproc: PROCEDURE;
	keytable: POINTER TO ARRAY OF CHAR;
	kpmap: SET;
	timerproc: Kernel.Proc;
	kdx, kdy, counter0, counter1: INTEGER;

(* ---- Keyboard Driver ---- *)

(* Translation table format:  

	table = { scancode unshifted-code shifted-code flags }  0FFX .
	scancode = <scancode byte from keyboard, bit 7 set for "grey" extended keys>
	unshifted-code = <CHAR produced by this scancode, without shift>
	shifted-code = <CHAR produced by this scancode, with shift>
	flags = <bit-mapped flag byte indicating special behaviour>
	
	flag bit	function
		0	01	DeadKey: Set dead key flag according to translated key code (1-7)
		1	02	NumLock: if set, the state of NumLock will reverse the action of shift (for num keypad)
		2	04	CapsLock: if set, the state of CapsLock will reverse the action of shift (for alpha keys)
		3	08	LAlt:  \ the state of these two flags in the table and the current state of the two...
		4	10	RAlt: / ...Alt keys must match exactly, otherwise the search is continued.
		5	20	\
		6	40	 >  dead key number (0-7), must match current dead key flag
		7	80	/
	
	The table is scanned sequentially (speed not critical).  Ctrl-Break, Ctrl-F10 and Ctrl-Alt-Del
	are always defined and are not in the table.   The control keys are also always defined. *)

(* TableUS - US keyboard translation table (dead keys: ^=1, '=2, `=3, ~=4, "=5) *)

PROCEDURE TableUS(): LONGINT;
CODE {SYSTEM.i386}
	CALL L1
L1:
	POP EAX
	ADD EAX,8
	POP EBP
	RET
		(* alphabet *)
	DB 1EX, "a", "A", 4X,	30X, "b", "B", 4X,	2EX, "c", "C", 4X,	20X, "d", "D", 4X
	DB 12X, "e", "E", 4X,	21X, "f", "F", 4X,	22X, "g", "G", 4X,	23X, "h", "H", 4X
	DB 17X, "i", "I", 4X,	24X, "j", "J", 4X,	25X, "k", "K", 4X,	26X, "l", "L", 4X
	DB 32X, "m", "M", 4X,	31X, "n", "N", 4X,	18X, "o", "O", 4X,	19X, "p", "P", 4X
	DB 10X, "q", "Q", 4X,	13X, "r", "R", 4X,	1FX, "s", "S", 4X,	14X, "t", "T", 4X
	DB 16X, "u", "U", 4X,	2FX, "v", "V", 4X,	11X, "w", "W", 4X,	2DX, "x", "X", 4X
	DB 15X, "y", "Y", 4X,	2CX, "z", "Z", 4X
		(* Oberon accents (LAlt & RAlt) *)
	DB 1EX, "ä", "Ä", 0CX,	12X, "ë", 0FFX, 0CX,	18X, "ö", "Ö", 0CX,	16X, "ü", "Ü", 0CX
	DB 17X, "ï", 0FFX, 0CX,	1FX, "ß", 0FFX, 0CX,	2EX, "ç", 0FFX, 0CX,	31X, "ñ", 0FFX, 0CX
	DB 1EX, "ä", "Ä", 14X,	12X, "ë", 0FFX, 14X,	18X, "ö", "Ö", 14X,	16X, "ü", "Ü", 14X
	DB 17X, "ï", 0FFX, 14X,	1FX, "ß", 0FFX, 14X,	2EX, "ç", 0FFX, 14X,	31X, "ñ", 0FFX, 14X
		(* dead keys (LAlt & RAlt) *)
	DB 07X, 0FFX, 1X, 9X,	28X, 2X, 5X, 9X,	29X, 3X, 4X, 9X,
	DB 07X, 0FFX, 1X, 11X,	28X, 2X, 5X, 11X,	29X, 3X, 4X, 11X,
		(* following keys *)
	DB 1EX, "â", 0FFX, 20X,	12X, "ê", 0FFX, 20X,	17X, "î", 0FFX, 20X,	18X, "ô", 0FFX, 20X
	DB 16X, "û", 0FFX, 20X,	1EX, "à", 0FFX, 60X,	12X, "è", 0FFX, 60X,	17X, "ì", 0FFX, 60X
	DB 18X, "ò", 0FFX, 60X,	16X, "ù", 0FFX, 60X,	1EX, "á", 0FFX, 40X,	12X, "é", 0FFX, 40X
	DB 1EX, "ä", "Ä", 0A4X,	12X, "ë", 0FFX, 0A0X,	17X, "ï", 0FFX, 0A0X,	18X, "ö", "Ö", 0A4X
	DB 16X, "ü", "Ü", 0A4X,	31X, "ñ", 0FFX, 80X
		(* numbers at top *)
	DB 0BX, "0", ")", 0X,	02X, "1", "!", 0X,	03X, "2", "@", 0X,	04X, "3", "#", 0X
	DB 05X, "4", "$", 0X,	06X, "5", "%", 0X,	07X, "6", "^", 0X,	08X, "7", "&", 0X
	DB 09X, "8", "*", 0X,	0AX, "9", "(", 0X
		(* symbol keys *)
	DB 28X, "'", 22X, 0X,	33X, ",", "<", 0X,	0CX, "-", "_", 0X,	34X, ".", ">", 0X
	DB 35X, "/", "?", 0X,	27X, ";", ":", 0X,	0DX, "=", "+", 0X,	1AX, "[", "{", 0X
	DB 2BX, "\", "|", 0X,	1BX, "]", "}", 0X,	29X, "`", "~", 0X
		(* control keys *)
	DB 0EX, 7FX, 7FX, 0X	(* backspace *)
	DB 0FX, 09X, 09X, 0X	(* tab *)
	DB 1CX, 0DX, 0DX, 0X	(* enter *)
	DB 39X, 20X, 20X, 0X	(* space *)
	DB 01X, 0FEX, 1BX, 0X	(* esc *)
	 	(* keypad *)
	DB 4FX, 0A9X, "1", 2X	(* end/1 *)
	DB 50X, 0C2X, "2", 2X	(* down/2 *)
	DB 51X, 0A3X, "3", 2X	(* pgdn/3 *)
	DB 4BX, 0C4X, "4", 2X	(* left/4 *)
	DB 4CX, 0FFX, "5", 2X	(* center/5 *)
	DB 4DX, 0C3X, "6", 2X	(* right/6 *)
	DB 47X, 0A8X, "7", 2X	(* home/7 *)
	DB 48X, 0C1X, "8", 2X	(* up/8 *)
	DB 49X, 0A2X, "9", 2X	(* pgup/9 *)
	DB 52X, 0A0X, "0", 2X	(* insert/0 *)
	DB 53X, 0A1X, 2EX, 2X	(* del/. *)
		(* gray keys *)
	DB 4AX, "-", "-", 0X	(* gray - *)
	DB 4EX, "+", "+", 0X	(* gray + *)
	DB 0B5X, "/", "/", 0X	(* gray / *)
	DB 37X, "*", "*", 0X	(* gray * *)
	DB 0D0X, 0C2X, 0C2X, 0X	(* gray down *)
	DB 0CBX, 0C4X, 0C4X, 0X	(* gray left *)
	DB 0CDX, 0C3X, 0C3X, 0X	(* gray right *)
	DB 0C8X, 0C1X, 0C1X, 0X	(* gray up *)
	DB 09CX, 0DX, 0DX, 0X	(* gray enter *)
	DB 0D2X, 0A0X, 0A0X, 0X	(* gray ins *)
	DB 0D3X, 0A1X, 0A1X, 0X	(* gray del *)
	DB 0C9X, 0A2X, 0A2X, 0X	(* gray pgup *)
	DB 0D1X, 0A3X, 0A3X, 0X	(* gray pgdn *)
	DB 0C7X, 0A8X, 0A8X, 0X	(* gray home *)
	DB 0CFX, 0A9X, 0A9X, 0X	(* gray end *)
		(* function keys *)
	DB 3BX, 0A4X, 0FFX, 0X	(* F1 *)
	DB 3CX, 0A5X, 0FFX, 0X	(* F2 *)
	DB 3DX, 1BX, 0FFX, 0X	(* F3 *)
	DB 3EX, 0A7X, 0FFX, 0X	(* F4 *)
	DB 3FX, 0F5X, 0FFX, 0X	(* F5 *)
	DB 40X, 0F6X, 0FFX, 0X	(* F6 *)
	DB 41X, 0F7X, 0FFX, 0X	(* F7 *)
	DB 42X, 0F8X, 0FFX, 0X	(* F8 *)
	DB 43X, 0F9X, 0FFX, 0X	(* F9 *)
	DB 44X, 0FAX, 0FFX, 0X	(* F10 *)
	DB 57X, 0FBX, 0FFX, 0X	(* F11 *)
	DB 58X, 0FCX, 0FFX, 0X	(* F12 *)
	DB 0FFX
END TableUS;

PROCEDURE TableFromFile(name: ARRAY OF CHAR): LONGINT;
VAR f: Files.File;  r: Files.Rider;  len: LONGINT;
BEGIN
	Kernel.WriteString("Keyboard: ");  Kernel.WriteString(name);
	f := Files.Old(name);
	IF f # NIL THEN
		len := Files.Length(f);
		IF len MOD 4 = 0 THEN
			NEW(keytable, len+1);
			Files.Set(r, f, 0);  Files.ReadBytes(r, keytable^, len);
			IF r.res = 0 THEN
				Kernel.WriteLn;
				keytable[len] := 0FFX;
				RETURN SYSTEM.ADR(keytable[0])
			END
		END
	END;
	Kernel.WriteString(" not used");  Kernel.WriteLn;
	RETURN TableUS()
END TableFromFile;

PROCEDURE -CoreHalt(n: LONGINT);
CODE {SYSTEM.i386}
	INT 3
END CoreHalt;

(* Translate - Translate scan code "c" to key. *)

PROCEDURE Translate(flags: SET;  c: CHAR): INTEGER;
CONST
	Alt = {LAlt, RAlt};  Ctrl = {LCtrl, RCtrl};  Shift = {LShift, RShift};
	AltShift = {LAlt, RAlt, LShift, RShift};
	All = {LAlt, RAlt, LCtrl, RCtrl, LShift, RShift};
VAR a: LONGINT;  s1: CHAR;  s: SET;  k: INTEGER;  dkn: SHORTINT;
BEGIN
	IF (c = 46X) & (flags * Ctrl # {}) THEN RETURN -2 END;	(* Ctrl-Break - break *)
	IF (c = 44X) & (flags * Ctrl # {}) THEN RETURN 0FFH END;	(* Ctrl-F10 - exit *)
	IF (c = 53X) & (flags * Ctrl # {}) & (flags * Alt # {}) THEN RETURN 0FFH END;	(* Ctrl-Alt-Del - exit *)
	IF GreyEsc IN flags THEN c := CHR(ORD(c)+80H) END;
	a := table;
	LOOP
		SYSTEM.GET(a, s1);
		IF s1 = 0FFX THEN	(* end of table, unmapped key *)
			k := -1;  dkey := 0;  EXIT
		ELSIF s1 = c THEN	(* found scan code in table *)
			SYSTEM.GET(a+3, SYSTEM.VAL(CHAR, s));	(* flags from table *)
			dkn := SHORT(SHORT(SYSTEM.VAL(LONGINT, SYSTEM.LSH(s * {5..7}, -5))));
			s := s * {DeadKey, NumLock, CapsLock, LAlt, RAlt, LCtrl, RCtrl};  k := 0;
			IF ((s * Alt = flags * Alt) OR (NumLock IN s)) & (dkn = dkey) THEN	(* Alt & dead keys match exactly *)
				IF flags * Shift # {} THEN INCL(s, LShift) END;	(* check if shift pressed *)
					(* handle CapsLock *)
				IF (CapsLock IN s) & (CapsLock IN flags) THEN s := s / {LShift} END;
					(* handle NumLock *)
				IF NumLock IN s THEN
					IF flags * Alt # {} THEN INCL(s, LShift)
					ELSIF NumLock IN flags THEN s := s / {LShift}
					END
				END;
					(* get key code *)
				IF LShift IN s THEN SYSTEM.GET(a+2, SYSTEM.VAL(CHAR, k))	(* shifted value *)
				ELSE SYSTEM.GET(a+1, SYSTEM.VAL(CHAR, k))	(* unshifted value *)
				END;
				IF (DeadKey IN s) & (k <= 7) THEN	(* dead key *)
					dkey := SHORT(k);  k := -1	(* set new dead key state *)
				ELSIF k = 0FFH THEN	(* unmapped key *)
					k := -1;  dkey := 0	(* reset dead key state *)
				ELSE	(* mapped key *)
					IF flags * Ctrl # {} THEN
						IF ((k >= 64) & (k <= 95)) OR ((k >= 97) & (k <= 122)) THEN
							k := SHORT(SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, k) * {0..4}))	(* control *)
						ELSIF k = 13 THEN	(* Ctrl-Enter *)
							k := 10
						END
					END;
					IF flags * Alt # {} THEN	(* Alt-keypad *)
						IF (k >= ORD("0")) & (k <= ORD("9")) & (NumLock IN s) THEN	(* keypad num *)
							IF keyval = -1 THEN keyval := k-ORD("0")
							ELSE keyval := (10*keyval + (k-ORD("0"))) MOD 1000
							END;
							k := -1
						END
					END;
					dkey := 0	(* reset dead key state *)
				END;
				EXIT
			END
		END;
		INC(a, 4)
	END; (* LOOP *)
	RETURN k
END Translate;

(* Wait - Wait for keyboard serial port to acknowledge byte. *)

PROCEDURE Wait;
VAR t: Kernel.MilliTimer; s: SET;
BEGIN
	Kernel.SetTimer(t, Kernel.TimeUnit DIV 50);	(* wait up to 17 ms *)
	REPEAT
		SYSTEM.PORTIN(64H, SYSTEM.VAL(CHAR, s))
	UNTIL ~(1 IN s) OR Kernel.Expired(t)
END Wait;

(* SendByte - Send a byte to the keyboard. *)

PROCEDURE SendByte(port: LONGINT;  value: SYSTEM.BYTE);
BEGIN
	Wait;  SYSTEM.PORTOUT(port, SYSTEM.VAL(CHAR, value));
	lastport := port;  lastvalue := value
END SendByte;

(* ShiftKey - Handle shift keys. *)

PROCEDURE ShiftKey(left, right: SHORTINT;  in: BOOLEAN);
BEGIN
	IF in THEN
		IF GreyEsc IN flags THEN INCL(flags, right)
		ELSE INCL(flags, left)
		END
	ELSE
		IF GreyEsc IN flags THEN EXCL(flags, right)
		ELSE EXCL(flags, left)
		END
	END
END ShiftKey;

(* LedKey - Handle "lock" keys. *)

PROCEDURE LedKey(VAR flags: SET;  lock: SHORTINT;  c: CHAR;
		VAR k: INTEGER);
BEGIN
	IF flags * {LAlt, RAlt, LCtrl, RCtrl, LShift, RShift} = {} THEN
		flags := flags / {lock}
	ELSE
		k := Translate(flags, c)
	END
END LedKey;

(* DisableInterrupts - Disable interrupts and return original flags state *)

PROCEDURE -DisableInterrupts(): SET;
CODE {SYSTEM.i386}
	PUSHFD
	POP EAX
	CLI
END DisableInterrupts;

(* RestoreInterrupts - Set flags state to restore interrupts to previous state *)

PROCEDURE -RestoreInterrupts(state: SET);
CODE {SYSTEM.i386}
	POPFD
END RestoreInterrupts;

(* MapScanCode - Map a scan code "c" to a key code. *)

PROCEDURE MapScanCode(c: CHAR): INTEGER;
VAR k: INTEGER;  oldleds, state: SET;
BEGIN
	SendByte(64H, 0ADX);  Wait;	(* disable keyboard *)
	k := -1;  oldleds := flags * {ScrollLock, NumLock, CapsLock};
	IF c = 0X THEN	(* overrun, ignore *)
	ELSIF c = 0FAX THEN	(* keyboard ack *)
		IF Resetting IN flags THEN
			EXCL(flags, Resetting);  INCL(flags, SendingLEDs);
			SendByte(60H, 0EDX)	(* set keyboard LEDs *)
		ELSIF SendingLEDs IN flags THEN
			SendByte(60H, SYSTEM.VAL(CHAR, oldleds));
			EXCL(flags, SendingLEDs)
		ELSIF SetTypematic IN flags THEN
			EXCL(flags, SetTypematic);  INCL(flags, Resetting);
			SendByte(60H, 020X)	(* 30Hz, 500 ms *)
		ELSE (* assume ack was for something else *)
		END
	ELSIF c = 0FEX THEN	(* keyboard resend *)
		SendByte(lastport, lastvalue)
	ELSIF c = 038X THEN	(* Alt make *)
		ShiftKey(LAlt, RAlt, TRUE)
	ELSIF c = 01DX THEN	(* Ctrl make *)
		ShiftKey(LCtrl, RCtrl, TRUE)
	ELSIF c = 02AX THEN	(* LShift make *)
		INCL(flags, LShift)
	ELSIF c = 036X THEN	(* RShift make *)
		INCL(flags, RShift)
	ELSIF c = 03AX THEN	(* Caps make *)
		LedKey(flags, CapsLock, c, k)
	ELSIF c = 046X THEN	(* Scroll make *)
		LedKey(flags, ScrollLock, c, k);
		state := DisableInterrupts();
		IF ScrollLock IN flags THEN
			IF Kernel.timer = NIL THEN Kernel.timer := timerproc END
		ELSE
			IF Kernel.timer = timerproc THEN Kernel.timer := NIL END
		END;
		RestoreInterrupts(state)
	ELSIF c = 045X THEN	(* Num make *)
		LedKey(flags, NumLock, c, k)
	ELSIF c = 0B8X THEN	(* Alt break *)
		ShiftKey(LAlt, RAlt, FALSE);
		IF (keyval >= 0) & (keyval < 255) THEN k := keyval END;	(* exclude 255 - reboot *)
		keyval := -1
	ELSIF c = 09DX THEN	(* Ctrl break *)
		ShiftKey(LCtrl, RCtrl, FALSE)
	ELSIF c = 0AAX THEN	(* LShift break *)
		EXCL(flags, LShift)
	ELSIF c = 0B6X THEN	(* RShift break *)
		EXCL(flags, RShift)
	ELSIF (flags * {ScrollLock, GreyEsc} = {ScrollLock}) & (c >= 47X) & (c <= 53X) & (c # 4AX) & (c # 4EX) THEN	(* key mouse *)
		INCL(kpmap, ORD(c)-47H)
	ELSIF c < 080X THEN	(* Other make *)
		k := Translate(flags, c)
	ELSIF (flags * {ScrollLock, GreyEsc} = {ScrollLock}) & (c >= 0C7X) & (c <= 0D3X) THEN	(* key mouse *)
		EXCL(kpmap, ORD(c)-0C7H)
	ELSE	(* ignore *)
	END;
	IF c = 0E0X THEN INCL(flags, GreyEsc) ELSE EXCL(flags, GreyEsc) END;
	IF flags * {ScrollLock, NumLock, CapsLock} # oldleds THEN
		INCL(flags, SendingLEDs);
		SendByte(60H, 0EDX)	(* set keyboard LEDs *)
	END;
	SendByte(64H, 0AEX);	(* enable keyboard *)
		(* now do additional mappings *)
	IF k = 0FEH THEN	(* map Esc to Neutralise or Esc *)
		IF escNeutralise THEN k := 0A5H ELSE k := 1BH END
	END;
	RETURN k
END MapScanCode;

(*
PROCEDURE -CS(): LONGINT
	033H, 0C0H,	(* XOR EAX,EAX *)
	066H, 08CH, 0C8H;	(* MOV AX,CS *)
*)

PROCEDURE -CS(): LONGINT;
CODE {SYSTEM.i386}
	XOR EAX, EAX
	MOV AX, CS
END CS;

(* KeyboardInterrupt - Handle interrupts from keyboard *)

PROCEDURE KeyboardInterrupt;
VAR
	m: SET;  c: CHAR;  k: INTEGER;  fp, esp, tmp, cs: LONGINT;  i: SHORTINT;
BEGIN
	SYSTEM.PORTIN(060H, c);	(* get scan code *)
	SYSTEM.PORTIN(061H, SYSTEM.VAL(CHAR, m));
	INCL(m, 7);  SYSTEM.PORTOUT(061H, SYSTEM.VAL(CHAR, m));
	EXCL(m, 7);  SYSTEM.PORTOUT(061H, SYSTEM.VAL(CHAR, m));	(* ack *)
	SYSTEM.STI();
	k := MapScanCode(c);
	IF k = -2 THEN	(* break *)
		head := 0;  tail := 0;	(* clear buffer *)
		IF ~Kernel.break THEN	(* first try: soft break *)
			Kernel.break := TRUE
		ELSIF ~Kernel.inGC THEN	(* second try: do hard break *)
			Kernel.break := FALSE;	(* cancel other break *)
			SYSTEM.GETREG(5, fp);	(* EBP *)
			SYSTEM.GET(fp+52, tmp);	(* get CS'' *)
			cs := CS();
			IF tmp MOD 4 # cs MOD 4 THEN	(* we interrupted at different level *)
					(* assume we are currently on system stack *)
					(* simulate a CALL to breakproc *)
				SYSTEM.GET(fp+48, tmp);	(* save old EIP *)
				SYSTEM.PUT(fp+48, breakproc);
				SYSTEM.GET(fp+60, esp);	(* get outer ESP *)
				DEC(esp, 4);
				SYSTEM.PUT(fp+60, esp);
				SYSTEM.PUT(esp, tmp)	(* PUSH old EIP *)
			ELSE	(* we interrupted at same level *)
					(* simulate a JMP to breakproc *)
				SYSTEM.PUT(fp+48, breakproc)
			END
		END
	ELSIF k >= 0 THEN
		i := (tail+1) MOD BufSize;
		IF i # head THEN
			buffer[1+tail] := CHR(k);  tail := i
		END
	END
END KeyboardInterrupt;

(* InitKeyboard - Initialise the keyboard. *)

PROCEDURE InitKeyboard;
VAR s: SET;  c: CHAR;  i: SHORTINT;  k: ARRAY 32 OF CHAR;
BEGIN
	head := 0;  tail := 0;  keyval := -1;  buffer[0] := 0X;  dkey := 0;
		(* Get table *)
	Kernel.GetConfig("Keyboard", k);
	i := 0;  WHILE (k[i] # 0X) & (k[i] # ".") DO INC(i) END;
	IF k[i] = "." THEN table := TableFromFile(k)
	ELSE table := TableUS()
	END;
		(* Get compatibility option *)
	Kernel.GetConfig("EscCompat", k);
	escNeutralise := (k # "0");
		(* install interrupt *)
	flags := {};
	Kernel.InstallIP(KeyboardInterrupt, Kernel.IRQ+1);
		(* clear the keyboard's internal buffer *)
	i := 8;
	LOOP
		SYSTEM.PORTIN(64H, SYSTEM.VAL(CHAR, s));
		IF ~(0 IN s) OR (i = 0) THEN EXIT END;
		SYSTEM.PORTIN(60H, c);	(* read byte *)
		SYSTEM.PORTIN(61H, SYSTEM.VAL(CHAR, s));
		INCL(s, 7);  SYSTEM.PORTOUT(61H, SYSTEM.VAL(CHAR, s));
		EXCL(s, 7);  SYSTEM.PORTOUT(61H, SYSTEM.VAL(CHAR, s));	(* ack *)
		DEC(i)
	END;
	flags := {SetTypematic};
	Kernel.GetConfig("NumLock", k);
	IF k[0] = "1" THEN INCL(flags, NumLock) END;
	SendByte(60H, 0F3X)	(* settypedel, will cause Ack from keyboard *)
END InitKeyboard;

(* ---- PS/2 aux port driver ---- *)

PROCEDURE PollAux;
VAR s: SET;  t: Kernel.MilliTimer;  i: SHORTINT;
BEGIN
	i := 10;	(* up to 0.2s! *)
	LOOP
		SYSTEM.PORTIN(64H, SYSTEM.VAL(CHAR, s));
		IF (s * {0,1} = {}) OR (i = 0) THEN EXIT END;
		SYSTEM.PORTIN(64H, SYSTEM.VAL(CHAR, s));
		IF s * {0,5} = {0,5} THEN SYSTEM.PORTIN(60H, SYSTEM.VAL(CHAR, s)) END;	(* byte avail *)
		Kernel.SetTimer(t, TimeUnit DIV 50);	(* 20ms *)
		REPEAT UNTIL Kernel.Expired(t);
		DEC(i)
	END
END PollAux;

PROCEDURE WriteDev(b: CHAR);
BEGIN
	PollAux;  SYSTEM.PORTOUT(64H, 0D4X);	(* aux data coming *)
	PollAux;  SYSTEM.PORTOUT(60H, b)
END WriteDev;

PROCEDURE WriteAck(b: CHAR);
VAR s: SET;  t: Kernel.MilliTimer;  i: SHORTINT;
BEGIN
	WriteDev(b);  i := 10;	(* up to 0.2s! *)
	LOOP
		SYSTEM.PORTIN(64H, SYSTEM.VAL(CHAR, s));
		IF (s * {0,5} = {0,5}) OR (i = 0) THEN EXIT END;
		Kernel.SetTimer(t, TimeUnit DIV 50);	(* 20ms *)
		REPEAT UNTIL Kernel.Expired(t);
		DEC(i)
	END;
	IF i # 0 THEN SYSTEM.PORTIN(60H, SYSTEM.VAL(CHAR, s)) END	(* byte avail *)
END WriteAck;

PROCEDURE WriteCmd(b: CHAR);
BEGIN
	PollAux;  SYSTEM.PORTOUT(64H, 60X);
	PollAux;  SYSTEM.PORTOUT(60H, b)
END WriteCmd;

PROCEDURE AuxInterrupt;
VAR c: CHAR;  t: INTEGER;
BEGIN
	SYSTEM.PORTIN(60H, c);	(* read byte *)
	t := (auxtl+1) MOD AuxSize;
	IF t # auxhd THEN auxbuf[auxtl] := c;  auxtl := t
	ELSE INC(auxoverflows)
	END
END AuxInterrupt;

PROCEDURE SerialRead(port: LONGINT;  VAR c: SYSTEM.BYTE);
VAR state: SET;  res: LONGINT;
BEGIN
	IF port = AUX THEN
		REPEAT UNTIL auxhd # auxtl;
		state := DisableInterrupts();
		c := auxbuf[auxhd];  auxhd := (auxhd+1) MOD AuxSize;
		RestoreInterrupts(state);
		res := 0
	ELSE
		V24.Receive(port, c, res)
	END
END SerialRead;

PROCEDURE SerialWrite(port: LONGINT;  c: SYSTEM.BYTE);
VAR res: LONGINT;
BEGIN
	IF port # AUX THEN
		V24.Send(port, c, res)
	END
END SerialWrite;

PROCEDURE SerialAvailable(port: LONGINT): LONGINT;
VAR n: LONGINT;  state: SET;
BEGIN
	IF port = AUX THEN
		state := DisableInterrupts();
		n := auxtl-auxhd;
		RestoreInterrupts(state);
		IF n < 0 THEN INC(n, AuxSize) END
	ELSIF port # NONE THEN
		n := V24.Available(port)
	END;
	RETURN n
END SerialAvailable;

PROCEDURE StartAux;
VAR state: SET;
BEGIN
	state := DisableInterrupts();
	auxhd := 0;  auxtl := 0;  
	RestoreInterrupts(state);
	IF ~auxinit THEN
		auxinit := TRUE;
		PollAux;
		SYSTEM.PORTOUT(64H, 0A8X);	(* enable aux *)
		WriteAck(0F3X);  WriteAck(CHR(rate));	(* set sample rate (was 100) *)
		WriteAck(0E8X);  WriteAck(3X);	(* 8 counts/mm *)
		WriteAck(0E7X);	(* 2:1 scale *)
		PollAux;
		Kernel.InstallIP(AuxInterrupt, Kernel.IRQ+12);
		WriteDev(0F4X);	(* enable aux device *)
		WriteCmd(47X);	(* controller interrupts on *)
		PollAux
	END
END StartAux;

(* ---- Mouse driver ---- *)

(* SetSpeed - Set mouse speed *)

PROCEDURE SetSpeed(old, new: LONGINT);
VAR word, stop, par: INTEGER;  c: CHAR;  res: LONGINT;  timer: Kernel.MilliTimer;
BEGIN
	IF port # AUX THEN
		IF (oldport # NONE) & (oldport # AUX) THEN V24.Stop(oldport) END;
		oldport := port;
		CASE type OF
			MS:  word := 7;  stop := V24.Stop1;  par := V24.ParNo |
			MSC1, MSC2, MSC3, MSC4:  word := 8;  stop := V24.Stop2;  par := V24.ParNo |
			MM:  word := 8;  stop := V24.Stop1;  par := V24.ParOdd |
			Logi:  word := 8;  stop := V24.Stop2;  par := V24.ParNo |
			LogiMan:  word := 7;  stop := V24.Stop1;  par := V24.ParNo |
			MSI:  word := 7;  stop := V24.Stop1;  par := V24.ParNo
		END;
		IF (type = Logi) OR (type = LogiMan) THEN
			V24.Start(port, old, word, par, stop, res);
			IF res = V24.Ok THEN
				IF new = 9600 THEN c := "q"
				ELSIF new = 4800 THEN c := "p"
				ELSIF new = 2400 THEN c := "o"
				ELSE c := "n"
				END;
				SerialWrite(port, "*");  SerialWrite(port, c);
				Kernel.SetTimer(timer, TimeUnit DIV 10);
				REPEAT UNTIL Kernel.Expired(timer);
				V24.Stop(port)
			END
		END;
		V24.Start(port, new, word, par, stop, res);
		IF res = V24.Ok THEN
			V24.SetMC(port, {V24.DTR, V24.RTS})
		END
	END
END SetSpeed;

(* InitMouse - Initialise mouse.
	"type" - mouse type from list
	"port" - V24.COM[12], AUX
	"bps" - V24.BPS*
	"rate" - sample rate (not all mice support this) *)

PROCEDURE InitMouse;
VAR c: CHAR;  t, res: LONGINT;  timer: Kernel.MilliTimer;
BEGIN
	port := newport;
	mouseX := Display.Width DIV 2;  mouseY := Display.Height DIV 2;
	mouseErrors := 0;  auxoverflows := 0;
	IF (oldport # NONE) & (oldport # AUX) THEN V24.Stop(oldport) END;
	oldport := NONE;
	IF port = AUX THEN
		StartAux;  oldport := port
	ELSE
		IF type = LogiMan THEN
			SetSpeed(1200, 1200);
			SerialWrite(port, "*");  SerialWrite(port, "X");
			SetSpeed(1200, bps)
		ELSE
			SetSpeed(9600, bps);
			SetSpeed(4800, bps);
			SetSpeed(2400, bps);
			SetSpeed(1200, bps);
			IF type = Logi THEN
				SerialWrite(port, "S");  type := MM;  SetSpeed(bps, bps);  type := Logi
			END;
				(* set sample rate *)
			IF rate <= 0 THEN c := "O"	(* continuous - don't use *)
			ELSIF rate <= 15 THEN c := "J"	(* 10 Hz *)
			ELSIF rate <= 27 THEN c := "K"	(* 20 *)
			ELSIF rate <= 42 THEN c := "L"	(* 35 *)
			ELSIF rate <= 60 THEN c := "R"	(* 50 *)
			ELSIF rate <= 85 THEN c := "M"	(* 70 *)
			ELSIF rate <= 125 THEN c := "Q"	(* 100 *)
			ELSE c := "N"	(* 150 *)
			END;
			SerialWrite(port, c);
			IF type = MSC2 THEN V24.ClearMC(port, {V24.DTR, V24.RTS})
			ELSIF type = MSC3 THEN V24.ClearMC(port, {V24.DTR})
			ELSIF type = MSC4 THEN V24.ClearMC(port, {V24.RTS})
			END
		END
	END;
	mbufp := 0;  lastkeys := {};
		(* protocol parameters *)
	CASE type OF
		MS:  numb := 3;  mask0 := {6};  val0 := {6};  mask1 := {6};  val1 := {} |
		MSC1, MSC2, MSC3, MSC4:  numb := 5;  mask0 := {3..7};  val0 := {7};  mask1 := {};  val1 := {} |
		MM:  numb := 3;  mask0 := {5..7};  val0 := {7};  mask1 := {7};  val1 := {} |
		Logi:  numb := 3;  mask0 := {5..7};  val0 := {7};  mask1 := {7};  val1 := {} |
		LogiMan:  numb := 3;  mask0 := {6};  val0 := {6};  mask1 := {6};  val1 := {} |
		PS2:  numb := 3;  mask0 := {6,7};  val0 := {};  mask1 := {};  val1 := {} |
		MSI: numb := 4;  mask0 := {6};  val0 := {6};  mask1 := {6};  val1 := {}
	END;
		(* ignore the first few bytes from the mouse (e.g. Logitech MouseMan Sensa) *)
	Kernel.SetTimer(timer, TimeUnit DIV 4);	(* wait 1/4s *)
	REPEAT
		IF SerialAvailable(port) > 0 THEN SerialRead(port, c) END
	UNTIL Kernel.Expired(timer)
END InitMouse;

(* GetMouseEvent - Read a mouse event *)

PROCEDURE GetMouseEvent(VAR keys: SET;  VAR dx, dy: INTEGER): BOOLEAN;
VAR b: SET;  res: LONGINT;
BEGIN
	WHILE SerialAvailable(port) > 0 DO
		b := {};  SerialRead(port, SYSTEM.VAL(CHAR, b));
			(* check for resync *)
		IF (mbufp # 0) & (type # PS2) & ((b * mask1 # val1) OR (b = {7})) THEN mbufp := 0 END;
		IF (mbufp = 0) & (b * mask0 # val0) THEN
				(* skip package, unless it is a LogiMan middle button... *)
			IF ((type = MS) OR (type = LogiMan)) & (b * {0,2..4,6,7} = {}) THEN
				keys := lastkeys * {0,2};
				IF 5 IN b THEN INCL(keys, 1) END;
				dx := 0;  dy := 0;
				RETURN TRUE
			ELSE
				INC(mouseErrors)
			END
		ELSE
			mbuf[mbufp] := b;  INC(mbufp);
			IF mbufp = numb THEN
				CASE type OF
					MS, LogiMan:
						keys := lastkeys * {1};
						IF 5 IN mbuf[0] THEN INCL(keys, 2) END;
						IF 4 IN mbuf[0] THEN INCL(keys, 0) END;
						dx := LONG(SYSTEM.VAL(SHORTINT, SYSTEM.LSH(mbuf[0] * {0,1}, 6) + mbuf[1] * {0..5}));
						dy := LONG(SYSTEM.VAL(SHORTINT, SYSTEM.LSH(mbuf[0] * {2,3}, 4) + mbuf[2] * {0..5})) |
					MSC1, MSC2, MSC3, MSC4:
						keys := {0..2} - (mbuf[0] * {0..2});
						dx := LONG(SYSTEM.VAL(SHORTINT, mbuf[1])) + LONG(SYSTEM.VAL(SHORTINT, mbuf[3]));
						dy := -(LONG(SYSTEM.VAL(SHORTINT, mbuf[2])) + LONG(SYSTEM.VAL(SHORTINT, mbuf[4]))) |
					MM, Logi:
						keys := mbuf[0] * {0..2};
						dx := SYSTEM.VAL(INTEGER, mbuf[1]);
						IF ~(4 IN mbuf[0]) THEN dx := -dx END;
						dy := SYSTEM.VAL(INTEGER, mbuf[2]);
						IF 3 IN mbuf[0] THEN dy := -dy END |
					PS2:
						keys := {};
						IF 2 IN mbuf[0] THEN INCL(keys, 1) END;
						IF 1 IN mbuf[0] THEN INCL(keys, 0) END;
						IF 0 IN mbuf[0] THEN INCL(keys, 2) END;
						dx := SYSTEM.VAL(INTEGER, mbuf[1]);
						IF 4 IN mbuf[0] THEN DEC(dx, 256) END;
						dy := -SYSTEM.VAL(INTEGER, mbuf[2]);
						IF 5 IN mbuf[0] THEN INC(dy, 256) END |
					MSI:
						keys := {};
						IF 4 IN mbuf[0] THEN INCL(keys, 0) END;
						IF 5 IN mbuf[0] THEN INCL(keys, 2) END;
						IF 3 IN mbuf[3] THEN INCL(keys, 3) END;
						IF 4 IN mbuf[3] THEN INCL(keys, 1) END;
						IF ~(3 IN mbuf[3]) & (mbuf[3] * {0..2} # {}) THEN INCL(keys, 4) END;
						dx := LONG(SYSTEM.VAL(SHORTINT, SYSTEM.LSH(mbuf[0] * {0,1}, 6) + mbuf[1] * {0..7}));
						dy := LONG(SYSTEM.VAL(SHORTINT, SYSTEM.LSH(mbuf[0] * {2,3}, 4) + mbuf[2] * {0..7}))
				END; (* CASE *)
				mbufp := 0;
				RETURN TRUE
			END
		END
	END;
	keys := lastkeys;  dx := 0;  dy := 0;
	RETURN FALSE
END GetMouseEvent;

(* ---- Interface ---- *)

(** Returns the number of keystrokes in the keyboard input buffer. *)
PROCEDURE Available*() : INTEGER;
VAR x: INTEGER;  state: SET;
BEGIN
	state := DisableInterrupts();
	x := tail-head;
	RestoreInterrupts(state);
	IF x < 0 THEN INC(x, BufSize) END;
	RETURN x
END Available;

(** Reads the current mouse position x, y and the key state of the mouse buttons 
(also called keys). The mouse buttons are numbered from the right to the left as 
0, 1, 2 (i.e. 1 is the middle mouse button). For example, when the left and middle 
buttons are pressed, keys will be set to {1, 2}. *)
PROCEDURE Mouse*(VAR keys: SET; VAR x, y: INTEGER);
VAR dx, dy: INTEGER;  ok: BOOLEAN;  rawkeys, state: SET;
BEGIN
	IF Kernel.break THEN Kernel.break := FALSE; CoreHalt(13) END;
	IF ScrollLock IN flags THEN
		keys := {};
		IF 11 IN kpmap THEN INCL(keys, 2) END;
		IF 5 IN kpmap THEN INCL(keys, 1) END;
		IF 12 IN kpmap THEN INCL(keys, 0) END;
		state := DisableInterrupts();
		INC(mouseX, LONG(kdx));
		INC(mouseY, LONG(kdy));
		kdx := 0;  kdy := 0;
		RestoreInterrupts(state)
	ELSE
		REPEAT	(* get all available mouse events, or until keys change *)
			ok := GetMouseEvent(rawkeys, dx, dy);
			IF (ABS(dx) > threshold) OR (ABS(dy) > threshold) THEN
				dx := SHORT(dx*speedup DIV 10); dy := SHORT(dy*speedup DIV 10)
			END;
			INC(mouseX, LONG(dx));  INC(mouseY, LONG(dy))
		UNTIL ~ok OR (rawkeys # lastkeys);
		IF ~(1 IN lastkeys) & (1 IN rawkeys) THEN	(* mouse generated middle button *)
			IF buttons = -3 THEN buttons := 3 END	(* switch off emulation in this case *)
		END;
		lastkeys := rawkeys;	(* save last known mouse key state *)
			(* middle button emulation *)
		IF buttons # 3 THEN	(* -2, 2, -3 *)
			IF buttons = 2 THEN	(* Ctrl is middle button *)
				IF flags * {LCtrl, RCtrl} # {} THEN INCL(rawkeys, 1)
				ELSE EXCL(rawkeys, 1)
				END
			ELSE	(* MM OR Ctrl is middle button *)
				IF flags * {LCtrl, RCtrl} # {} THEN INCL(rawkeys, 1) END
			END
		END;
			(* key mapping *)
		keys := mapkeys[SYSTEM.VAL(LONGINT, rawkeys * {0,1,2})]
	END;
	IF mouseX < minX THEN mouseX := minX
	ELSIF mouseX > maxX THEN mouseX := maxX
	END;
	IF mouseY < minY THEN mouseY := minY
	ELSIF mouseY > maxY THEN mouseY := maxY
	END;
	x := SHORT(mouseX);
	y := SHORT(mouseY);
	y := (Display.Height - 1) - y;
	IF x >= Display.Width THEN x := Display.Width - 1 END
END Mouse;

(** Read a character from the keyboard buffer. Blocks if no character is available. *)
PROCEDURE Read*(VAR ch: CHAR);
VAR state: SET;
BEGIN
	REPEAT (* skip *) UNTIL (head # tail) OR Kernel.break;
	IF Kernel.break THEN Kernel.break := FALSE; CoreHalt(13) END;
	state := DisableInterrupts();
	ch := buffer[1+head];  head := (head+1) MOD BufSize;
	RestoreInterrupts(state)
END Read;

(** Returns the elapsed number of timer ticks from Oberon startup. *)
PROCEDURE Time*(): LONGINT;
BEGIN
	IF Kernel.break THEN Kernel.break := FALSE; CoreHalt(13) END;
	RETURN Kernel.GetTimer()
END  Time;

(** Return the state of the shift keys. *)
PROCEDURE KeyState*(VAR keys: SET);
BEGIN
	keys := {};
	IF flags * {LAlt, RAlt} # {} THEN INCL(keys, ALT) END;
	IF flags * {LCtrl, RCtrl} # {} THEN INCL(keys, CTRL) END;
	IF flags * {LShift, RShift} # {} THEN INCL(keys, SHIFT) END
END KeyState;

(** Restricts the extent of the mouse coordinates returned by Mouse. *)
PROCEDURE SetMouseLimits*(x, y, w, h: INTEGER);	(** non-portable *)
BEGIN
	y := Display.Height-1 - y;
	minX := x;  maxY := y;  maxX := x + w-1;  minY := y - (h-1)
END SetMouseLimits;

PROCEDURE SetMouseType(s: ARRAY OF CHAR);
BEGIN
	type := MinType-1;
	IF (s[0] >= "0") & (s[0] <= "9") THEN	(* old style config *)
		type := SHORT(ORD(s[0])-ORD("0"))
	ELSE	(* new style config *)
		IF s = "" THEN
			(* default if none specified *)
		ELSIF (CAP(s[0]) = "L") & (CAP(s[1]) = "M") THEN	(* Logitech *)
			CASE s[2] OF
				"1": type := LogiMan
				|"2": type := MM
				|"3": type := Logi
			END
		ELSIF (CAP(s[0]) = "M") & (CAP(s[1]) = "S") THEN	(* Mouse Systems or Microsoft *)
			IF CAP(s[2]) = "M" THEN type := MS
			ELSIF CAP(s[2]) = "I" THEN type := MSI
			ELSE
				CASE s[2] OF
					"1": type := MSC1
					|"2": type := MSC2
					|"3": type := MSC3
					|"4": type := MSC4
				END
			END
		ELSIF CAP(s[0]) = "P" THEN	(* PS/2 *)
			type := PS2
		END
	END;
	IF (type < MinType) OR (type > MaxType) THEN type := PS2 END;	(* unknown mouse type *)
	IF type = PS2 THEN newport := AUX END;
	IF Trace THEN
		Kernel.WriteString("MouseType=");  Kernel.WriteInt(type, 1);
		Kernel.WriteChar(" ");  Kernel.WriteInt(newport, 1);
		Kernel.WriteLn
	END;
	InitMouse
END SetMouseType;

(** Configure input device parameters.  Normally only used by installation program. *)
PROCEDURE Configure*(config, value: ARRAY OF CHAR);	(** non-portable *)
VAR i: SHORTINT;  mk: ARRAY 3 OF LONGINT;
BEGIN
	IF Trace THEN
		Kernel.WriteString("Input: ");  Kernel.WriteString(config);  Kernel.WriteChar("=");
		Kernel.WriteString(value);  Kernel.WriteLn
	END;
	IF config = "MT" THEN	(* mouse type *)
		SetMouseType(value)
	ELSIF config = "MP" THEN	(* mouse port *)
		IF (value[0] >= "1") & (value[0] <= "4") THEN
			newport := V24.COM1 + (ORD(value[0])-ORD("1"))
		ELSE
			newport := V24.COM1
		END
	ELSIF config = "MB" THEN	(* mouse buttons *)
		IF value = "2" THEN buttons := 2
		ELSIF value = "3" THEN buttons := 3
		ELSIF value = "-2" THEN buttons := -2
		ELSE buttons := -3	(* default MM and Ctrl *)
		END
	ELSIF config = "MM" THEN	(* mouse key remapping *)
		mk[0] := 0;  mk[1] := 1;  mk[2] := 2;
		IF value[0] # 0X THEN
			mk[0] := ORD(value[0])-48;
			IF value[1] # 0X THEN
				mk[1] := ORD(value[1])-48;
				IF value[2] # 0X THEN
					mk[2] := ORD(value[2])-48
				END
			END
		END;
		FOR i := 0 TO 7 DO
			mapkeys[i] := {};
			IF 0 IN SYSTEM.VAL(SET, i) THEN INCL(mapkeys[i], mk[0]) END;
			IF 1 IN SYSTEM.VAL(SET, i) THEN INCL(mapkeys[i], mk[1]) END;
			IF 2 IN SYSTEM.VAL(SET, i) THEN INCL(mapkeys[i], mk[2]) END
		END
	ELSE
		IF Trace THEN Kernel.WriteString("Unknown setting");  Kernel.WriteLn END
	END
END Configure;

PROCEDURE Setting(name: ARRAY OF CHAR);
VAR s: ARRAY 16 OF CHAR;
BEGIN
	Kernel.GetConfig(name, s);  Configure(name, s)
END Setting;

PROCEDURE ConfigMouse;
VAR s: ARRAY 16 OF CHAR;  i: SHORTINT;
BEGIN
		(* boot-time settings *)
	Kernel.GetConfig("MouseBPS", s);
	IF s = "9600" THEN bps := 9600 ELSE bps := 1200 END;
		(* rate *)
	Kernel.GetConfig("MouseRate", s);
	rate := 0;  i := 0;
	WHILE s[i] # 0X DO rate := rate*10+ORD(s[i])-48; INC(i) END;
	IF (rate <= 0) OR (rate > 150) THEN rate := 100 END;
		(* threshold *)
	Kernel.GetConfig("Threshold", s);
	threshold := 0;  i := 0;
	WHILE s[i] # 0X DO threshold := threshold*10+ORD(s[i])-48; INC(i) END;
	IF threshold <= 0 THEN threshold := 5 END;
		(* speedup *)
	Kernel.GetConfig("Speedup", s);
	speedup := 0;  i := 0;
	WHILE s[i] # 0X DO speedup := speedup*10+ORD(s[i])-48; INC(i) END;
	IF speedup <= 0 THEN speedup := 15 END;
	Setting("MP");  Setting("MB");  Setting("MM");
	Setting("MT")	(* also calls InitMouse *)
END ConfigMouse;

PROCEDURE *UnsafeBreak;
VAR note1, note2, note3: ARRAY 32 OF CHAR;
BEGIN
	note1 := "Warning: Interrupting a module";
	note2 := "may invalidate its invariants";
	note3 := "and make it unstable.";
	CoreHalt(13)
END UnsafeBreak;

PROCEDURE *Timer;
VAR i: INTEGER;
BEGIN
	IF counter1 = TimeUnit DIV 100 THEN
		counter1 := 0;
		IF kpmap * {0..2, 4, 6, 8..10} = {} THEN counter0 := 0
		ELSIF counter0 < 100 THEN INC(counter0)
		END;
		i := counter0 DIV (100 DIV 12)+1;
		IF kpmap * {0,4,8} # {} THEN DEC(kdx, i) END;
		IF kpmap * {0,1,2} # {} THEN DEC(kdy, i) END;
		IF kpmap * {2,6,10} # {} THEN INC(kdx, i) END;
		IF kpmap * {8,9,10} # {} THEN INC(kdy, i) END
	ELSE
		INC(counter1)
	END
END Timer;

BEGIN
	timerproc := Timer;  kpmap := {};  kdx := 0;  kdy := 0;  counter0 := 0;
	breakproc := UnsafeBreak;
	InitKeyboard;
		(* initialise mouse state *)
	SetMouseLimits(0, 0, Display.Width, Display.Height);
	oldport := NONE;  auxinit := FALSE;
	ConfigMouse
END Input.

(** Remarks:

1. Keyboard character codes correspond to the ASCII character set. 
Some other important codes are:

	F1, SETUP	0A4X
	F2, NEUTRALISE	0A5X
	F3, SCRL	0A6X	(used in Draw)
	F4, NOSCRL	0A7X	(used in Draw)
	UP ARROW	0C1X
	RIGHT ARROW	0C3X
	DOWN ARROW	0C2X
	LEFT ARROW	0C4X
	INSERT	0A0X
	DELETE	0A1X
	PAGE-UP	0A2X
	PAGE-DOWN	0A3X
	ä, Ä	131, 128
	ö, Ö	132, 129
	ü, Ü	133, 130
	ß	150

The module EditKeys allows you to determine the keyboard code of any key pressed. 
For cross-platform portability, Oberon does not normally support all keys available 
on your keyboard.
*)
