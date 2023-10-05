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


(* ---- Interface ---- *)

(** Returns the number of keystrokes in the keyboard input buffer. *)
PROCEDURE Available*() : INTEGER;
END Available;

(** Reads the current mouse position x, y and the key state of the mouse buttons 
(also called keys). The mouse buttons are numbered from the right to the left as 
0, 1, 2 (i.e. 1 is the middle mouse button). For example, when the left and middle 
buttons are pressed, keys will be set to {1, 2}. *)
PROCEDURE Mouse*(VAR keys: SET; VAR x, y: INTEGER);
END Mouse;

(** Read a character from the keyboard buffer. Blocks if no character is available. *)
PROCEDURE Read*(VAR ch: CHAR);
END Read;

(** Returns the elapsed number of timer ticks from Oberon startup. *)
PROCEDURE Time*(): LONGINT;
END  Time;

(** Return the state of the shift keys. *)
PROCEDURE KeyState*(VAR keys: SET);
END KeyState;

(** Restricts the extent of the mouse coordinates returned by Mouse. *)
PROCEDURE SetMouseLimits*(x, y, w, h: INTEGER);	(** non-portable *)
END SetMouseLimits;



BEGIN
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
