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

MODULE Clocks; (** portable *)	(* Fri, 23-Apr-1993*)

IMPORT
	Input, Dates, Strings, Display, Display3, Printer, Printer3, Texts, Objects, Gadgets, Oberon,
	Fonts, Math, Files, Modules;

CONST 
	tickId* = 0; alarmId* = 1;
	Minute = 60; Hour = 60*Minute; Day = 24*Hour;
	digital = 0; calendar = 1; new = 2;

TYPE
	Alarm* = POINTER TO AlarmDesc;
	AlarmHandler* = PROCEDURE (alarm: Alarm; VAR handled: BOOLEAN);
	AlarmDesc* = RECORD
		at : LONGINT;
		handle*: AlarmHandler;
		handled : BOOLEAN;
		next : Alarm
	END;
	EnumAlarmHandler* = PROCEDURE (alarm: Alarm; t, d: LONGINT; VAR handled: BOOLEAN);

	TickMsg* = RECORD (Display.FrameMsg)
		id* : INTEGER;
		date*, time* : LONGINT
	END;

	Clock* = POINTER TO ClockDesc;
	ClockDesc* = RECORD (Gadgets.FrameDesc)
		date, time, timeDiff: LONGINT;
		state0: SET;
		col: INTEGER
	END;
	
VAR 
	alarms : BOOLEAN;
	firstAlarm  : Alarm;
	lastTask, lastAlarm, lastTick, zeroY: LONGINT;
	task : Oberon.Task;
	W : Texts.Writer;
	font: ARRAY 3 OF Fonts.Font;

(* ------------ Oberon date convertion ------------ *)

PROCEDURE ToLinearForm (t, d: LONGINT): LONGINT;
	VAR h, m, s: INTEGER;
BEGIN
	Dates.ToHMS(t, h, m, s);
	RETURN (Dates.NumberOfDays(d) - zeroY)*Day + LONG(s) + LONG(m)*Minute + LONG(h)*Hour
END ToLinearForm;

PROCEDURE ToOberonForm (time: LONGINT; VAR t, d: LONGINT);
BEGIN
	d := Dates.NumberOfDaysToDate(time DIV Day + zeroY);
	time := time MOD Day;
	t := Dates.ToTime(SHORT(time DIV Hour), SHORT(time DIV Minute  MOD Minute), SHORT(time MOD Minute))
END ToOberonForm;

PROCEDURE GetClock (): LONGINT;
	VAR d, t: LONGINT;
BEGIN Oberon.GetClock(t, d); RETURN ToLinearForm(t, d)
END GetClock;

(* ------------ alarm ------------ *)

PROCEDURE *AlarmTask(me : Oberon.Task);
	VAR a, p : Alarm; now, t, d: LONGINT; M : TickMsg; hour,min,sec : INTEGER; handled : BOOLEAN;
BEGIN
	IF alarms & (Input.Time() - lastAlarm > Input.TimeUnit) THEN
		lastAlarm := Input.Time();
		Oberon.GetClock(M.time, M.date); M.id := alarmId; M.F := NIL; Display.Broadcast(M)
	END;
	IF Input.Time() - lastTask  >  5 * Input.TimeUnit THEN
		lastTask := Input.Time();
		Oberon.GetClock(t, d); now := ToLinearForm(t, d); Dates.ToHMS(t, hour, min, sec);
		IF (now - lastTick > 16)  & (sec  < 15) THEN
			M.date := d; M.time := t; M.id := tickId; M.F := NIL; Display.Broadcast(M); lastTick := now
		END;
		a := firstAlarm; alarms := FALSE;
		WHILE a # NIL DO 
			IF a.handled THEN IF a = firstAlarm THEN firstAlarm := firstAlarm.next ELSE p.next := a.next END END;
			handled := a.handled; a.handled := TRUE;
			IF (a.at < now) & ~handled THEN
				ToOberonForm(a.at, t, d); a.handle(a, handled);
				alarms := alarms OR ~handled
			END;
			a.handled := handled;
			p := a; a := a.next
		END
	END;
	me.time := Input.Time() + Input.TimeUnit;
END AlarmTask;

PROCEDURE InstallAlarm*(alarm: Alarm; time, date: LONGINT; handle : AlarmHandler);
	VAR pa, a: Alarm;
BEGIN
	IF alarm # NIL THEN
		alarm.at := ToLinearForm(time, date); alarm.handle := handle;
		alarm.handled := FALSE;
		pa := NIL; a := firstAlarm;
		WHILE (a # NIL) & (a # alarm) DO
			pa := a; a := a.next
		END;
		IF a = alarm THEN
			IF pa # NIL THEN
				pa.next := a.next
			ELSE
				firstAlarm := a.next
			END
		END;
		alarm.next := NIL;
		pa := NIL; a := firstAlarm;
		WHILE (a # NIL) & (a.at <= alarm.at) DO
			pa := a; a := a.next
		END;
		IF a # NIL THEN
			IF pa # NIL THEN
				pa.next := alarm
			ELSE
				firstAlarm := alarm
			END;
			alarm.next := a
		ELSIF pa # NIL THEN
			pa.next := alarm
		ELSE
			firstAlarm := alarm
		END
	END
END InstallAlarm;

PROCEDURE RemoveAlarm*(alarm: Alarm);
	VAR p,a : Alarm; T : TickMsg;
BEGIN
	a := firstAlarm;
	WHILE (a # NIL) & (a # alarm) DO p := a; a := a.next END;
	IF a # NIL THEN
		IF a = firstAlarm THEN firstAlarm := a.next ELSE p.next := a.next END;
		alarms := FALSE;
		Oberon.GetClock(T.time, T.date);
		T.time := T.time DIV 2 * 2; T.id := alarmId; T.F := NIL; Display.Broadcast(T)
	END
END RemoveAlarm;

PROCEDURE ShowAlarms*(enum: EnumAlarmHandler);
	VAR a : Alarm; t, d: LONGINT;
BEGIN
	a :=  firstAlarm;
	WHILE a # NIL DO
		IF ~a.handled THEN ToOberonForm(a.at, t, d); enum(a, t, d, a.handled) END;
		a := a.next
	END;
END ShowAlarms;

(* ------------ clock ------------ *)
PROCEDURE ClockAttr(F: Clock; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Color" THEN M.class := Objects.Int; M.i := F.col; M.res := 0 
		ELSIF M.name = "TimeDiff" THEN M.class := Objects.Int; M.i := F.timeDiff DIV Hour; M.res :=  0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.i := F.H DIV 2 - 5; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "Color" THEN
			IF M.class = Objects.Int THEN F.col := SHORT(M.i); M.res := 0 END;
		ELSIF M.name = "TimeDiff" THEN F.timeDiff := M.i * Hour; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END;
	ELSIF M.id = Objects.enum THEN
		M.Enum("Color"); M.Enum("TimeDiff"); Gadgets.framehandle(F, M)
	END;
END ClockAttr;

PROCEDURE Line2(M: Display3.Mask; ang: INTEGER; x0, y0, r1, r2, color: INTEGER);
	VAR x1, y1, x2, y2: INTEGER; s,c,a : REAL;  
BEGIN
	ang := (15-ang) MOD 60;
	a := 2 * Math.pi / 60 * ang; 
	s := Math.sin(a); c := Math.cos(a);
	x1 := SHORT(ENTIER(r1*c + 0.5));
	y1 := SHORT(ENTIER(r1*s + 0.5));
	x2 := SHORT(ENTIER(r2*c + 0.5));
	y2 := SHORT(ENTIER(r2*s + 0.5));
	Display3.Line(M,color,Display.solid,x0+x1, y0+y1, x0+x2, y0+y2,  1, Display.replace)
END Line2;
		
PROCEDURE RestoreClock(F: Clock; M: Display3.Mask; x, y, w, h: INTEGER; alarm : BOOLEAN);
	VAR
		time, date: LONGINT;
		rh, rm, i ,x0, y0, r, hour, min, sec, year, month, day, dow, col: INTEGER;
		s : ARRAY 32 OF CHAR;
BEGIN
	Oberon.RemoveMarks(x,y,w,h);
	ToOberonForm(F.time + F.timeDiff, time, date);
	col := F.col;
	IF (calendar IN F.state0)  THEN
		IF ~ alarm & (date = F.date) THEN
			dow := Dates.DayOfWeek(date);
			Dates.ToYMD(date, year, month, day);
			Strings.MonthToStr(month, s, TRUE);
			Display3.CenterString(M, col, x , y ,F.W, 10, font[0], s, Display3.textmode);
			Strings.IntToStr(day, s);
			Display3.CenterString(M, col, x, y + 7, F.W, 20, font[1], s, Display3.textmode);
			IF dow = 6 THEN col := Display3.red ELSE col := F.col END;
			Strings.DayToStr(dow, s, FALSE);
			IF dow = 6 THEN col := Display3.red END;
			Display3.CenterString(M, col, x , y + 22, F.W, 10, font[0], s, Display3.textmode)
		ELSE
			F.date := date; Gadgets.Update(F)
		END
	ELSIF digital IN F.state0 THEN
		IF alarm THEN 
			IF ODD(F.time) THEN col := Display3.red END;  
			Display3.Circle(M, col, Display.solid, x+3, y+7, 3, 1, {Display3.filled}, Display3.textmode)
		ELSE
			Dates.ToHMS(time, hour, min, sec);
			s[0] := CHR(hour DIV 10 + ORD("0")); s[1] := CHR(hour MOD 10 + ORD("0")); s[2] := ":";
			s[3] := CHR(min DIV 10 + ORD("0")); s[4] := CHR(min MOD 10 + ORD("0")); s[5] := 0X;
			Display3.ReplConst(M, Display3.downC, x, y+3, w, h, Display.replace);
			Display3.CenterString(M, col, x, y + 3, w, h-3, font[1], s, Display3.paint)
		END
	ELSE
		IF F.W < F.H THEN r := F.W DIV 2 -1 ELSE r := F.H DIV 2 -1 END;
		x0 := x + w DIV 2; y0 := y + h DIV 2;
		Dates.ToHMS(time, hour, min, sec);
		IF alarm THEN
			IF ODD(F.time) THEN col := Display3.red ELSE col := Display3.textbackC END; 
			Display3.Circle(M, col, Display.solid, x0 - r  DIV 2, y0, 3, 1, {Display3.filled}, Display.replace)
		ELSIF r >= 12 THEN
			rh := 7*r DIV 11; rm := 9*r DIV 11; i := 0;
			Display3.Circle(M, Display3.textbackC, Display.solid, x0, y0, r, 1, {Display3.filled}, Display.replace);
			WHILE i < 60 DO Line2(M, i, x0, y0, rm, r, col); INC(i, 5) END;
			Line2(M, min, x0, y0, 0, rm, col);
			Line2(M, SHORT((F.time + F.timeDiff) MOD (Day DIV 2) DIV 720) , x0, y0, 0, rh, col);
			Display3.Circle(M, col, Display.solid, x0, y0, r, 1, {}, Display.replace)
		END;
		IF (hour = 12) & (min = 0) THEN s := "hn" 
		ELSIF (hour = 0) & (min = 0) THEN s := "gh"
		ELSIF hour < 12 THEN s := "am"
		ELSE s := "pm"
		END;
		Display3.String(M, F.col, x0 -r  DIV 2-4, y0-2 , font[0], s, Display3.textmode)
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreClock;

PROCEDURE PrintClock(F: Clock; VAR M: Display.DisplayMsg);
	VAR
		time, date: LONGINT;
		r, rh, rm, x0, y0, i, hour,min,sec, year,month,day,dow,col: INTEGER;
		s : ARRAY 32 OF CHAR;
		Q: Display3.Mask;

	PROCEDURE P (X: INTEGER): INTEGER;
	BEGIN RETURN SHORT(Display.Unit*X DIV Printer.Unit)
	END P;

	PROCEDURE PLine(ang: INTEGER; x0, y0, r1, r2, color: INTEGER);
		VAR x1, y1, x2, y2: INTEGER; s,c,a : REAL;  
	BEGIN
		ang := (15-ang) MOD 60;
		a := 2 * Math.pi / 60 * ang; 
		s := Math.sin(a); c := Math.cos(a);
		x1 := SHORT(ENTIER(r1*c + 0.5));
		y1 := SHORT(ENTIER(r1*s + 0.5));
		x2 := SHORT(ENTIER(r2*c + 0.5));
		y2 := SHORT(ENTIER(r2*s + 0.5));
		Printer3.Line(Q,color,Display.solid,x0+x1, y0+y1, x0+x2, y0+y2, P(1), Display.replace)
	END PLine;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q);
	ToOberonForm(F.time + F.timeDiff, time, date);
	col := F.col;
	IF calendar IN F.state0 THEN
		dow := Dates.DayOfWeek(date);
		Dates.ToYMD(date, year, month, day);
		Strings.MonthToStr(month, s, TRUE); s[3] := 0X;
		Printer3.CenterString(Q, col, M.x , M.y , P(F.W), P(10), font[0], s, Display.paint);
		Strings.IntToStr(day, s);
		Printer3.CenterString(Q, col, M.x, M.y + P(7), P(F.W) , P(20), font[1], s, Display.paint);
		IF dow = 6 THEN col := Display3.red END;
		Strings.DayToStr(dow, s, FALSE);
		Printer3.CenterString(Q, col, M.x , M.y + P(22), P(F.W), P(10), font[0], s, Display.paint)
	ELSIF digital IN F.state0 THEN
		Strings.TimeToStr(time, s);
		i := 0; WHILE s[i] # 0X DO INC(i) END;
		s[i-3] := 0X;
		Printer3.ReplConst(Q, Display3.downC, M.x, M.y + P(3), P(F.W), P(F.H), Display.replace);
		Printer3.CenterString(Q, col, M.x, M.y + P(3), P(F.W), P(F.H - 3), font[2], s, Display.paint)
	ELSE
		IF F.W < F.H THEN r := P(F.W DIV 2 - 1) ELSE r := P(F.H DIV 2 - 1) END;
		x0 := M.x + P(F.W DIV 2); y0 := M.y + P(F.H DIV 2);
		Dates.ToHMS(time, hour, min, sec);
		IF r >= 12 THEN
			rh := 7*r DIV 11; rm := 9*r DIV 11; i := 0;
			Printer3.Circle(Q, Display3.textbackC, Display.solid, x0, y0, r, P(1), {Display3.filled}, Display.replace);
			WHILE i < 60 DO PLine(i, x0, y0, rm, r, col); INC(i, 5) END;
			PLine(min, x0, y0, 0, rm, col);
			PLine(SHORT((F.time + F.timeDiff) MOD (Dates.day DIV 2) DIV 720) , x0, y0, 0, rh, col);
			Printer3.Circle(Q, col,Display.solid,x0, y0, r, P(1), {}, Display.replace);
		END;
		IF (hour = 12) & (min = 0) THEN s := "hn" 
		ELSIF (hour = 0) & (min = 0) THEN s := "gh"
		ELSIF hour < 12 THEN s := "am"
		ELSE s := "pm"
		END;
		Printer3.String(Q, col, x0 - r  DIV 2 - P(4), y0 - P(2) , font[0], s, Display.paint)
	END
END PrintClock;

PROCEDURE CopyClock*(VAR M: Objects.CopyMsg; from, to: Clock);
BEGIN
	Gadgets.CopyFrame(M, from, to); to.time := from.time; to.state0 := from.state0; to.timeDiff := from.timeDiff;
	to.col := from.col
END CopyClock;

PROCEDURE ClockHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h, u, v: INTEGER; F0: Clock; R: Display3.Mask;
BEGIN
	WITH F: Clock DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO 
				IF (M.name = "Gen") & (M.id = Objects.get) THEN
					IF digital IN F.state0 THEN M.s := "Clocks.NewDigiClock"
					ELSIF calendar IN F.state0 THEN M.s := "Clocks.NewCalendar"
					ELSE M.s := "Clocks.NewClock"
					END;
					M.res := 0; M.class := Objects.String
				ELSE
					ClockAttr(F, M) 
				END
			END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteInt(M.R, 1);
					Files.WriteSet(M.R,F.state0);
					Files.WriteNum(M.R,F.timeDiff);
					Files.WriteInt(M.R, F.col);
					Gadgets.framehandle(F, M);
				ELSIF M.id = Objects.load THEN
					Files.ReadInt(M.R, x);
					IF x # 1 THEN
						Files.Set(M.R, Files.Base(M.R), Files.Pos(M.R) - 1);
						Files.ReadSet(M.R,F.state0);
						IF new IN F.state0 THEN Files.ReadNum(M.R,F.timeDiff) END;
						INCL(F.state0,new);
						Gadgets.framehandle(F, M)
					ELSE
						Files.ReadSet(M.R,F.state0);
						IF new IN F.state0 THEN Files.ReadNum(M.R,F.timeDiff) END;
						INCL(F.state0,new);
						Files.ReadInt(M.R, F.col);
						Gadgets.framehandle(F, M)
					END
				END
			END;
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyClock(M, F, F0); M.obj := F0
				END
			END
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates of this instance *)
				u := M.x; v := M.y; (* store volatile info *)
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg  DO
						IF M.device = Display.screen THEN
							IF (M.F  = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								RestoreClock(F, R, x, y, w, h, FALSE);
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								RestoreClock(F, R, x, y, w, h, FALSE);
							END
						ELSIF M.device = Display.printer THEN PrintClock(F, M)
						END
					END
				ELSIF M IS TickMsg THEN
					WITH M :  TickMsg DO
						Gadgets.MakeMask(F, x, y, M.dlink, R);
						F.time := ToLinearForm(M.time, M.date);
						RestoreClock(F, R, x, y, w, h, M.id = alarmId)
					END
				ELSIF M IS Display.ControlMsg THEN
					WITH M :  Display.ControlMsg DO
						IF M.id = Display.restore THEN F.time := GetClock() END
					END;
					Gadgets.framehandle(F, M)
				ELSE Gadgets.framehandle(F, M)
				END;
				M.x := u; M.y := v (* restore volatile info *)
			END
		ELSE
			Gadgets.framehandle(F, M);
		END;
	END;
END ClockHandler;

PROCEDURE InsertDate*;
	VAR date : LONGINT; s : ARRAY 32 OF CHAR; M : Oberon.ConsumeMsg;
BEGIN
	date := GetClock();
	IF (Gadgets.executorObj # NIL) & (Gadgets.executorObj IS Clock) THEN
		date := date + Gadgets.executorObj(Clock).timeDiff
	END;
	date := Dates.NumberOfDaysToDate(date DIV Day + zeroY);
	Strings.DateToStr(date, s); Texts.WriteString(W, s);
	NEW(M.text); Texts.Open(M.text, "");Texts.Append(M.text, W.buf);
	M.beg := 0; M.end := M.text.len; M.F := NIL; Display.Broadcast(M)
END InsertDate;

PROCEDURE InsertTime*;
	VAR date, time : LONGINT; s : ARRAY 32 OF CHAR; M : Oberon.ConsumeMsg;
BEGIN
	time := GetClock(); 
	IF (Gadgets.executorObj # NIL) & (Gadgets.executorObj IS Clock) THEN
		time := time + Gadgets.executorObj(Clock).timeDiff
	END;
	ToOberonForm(time, time, date);
	Strings.TimeToStr(time,s); Texts.WriteString(W,s);
	NEW(M.text); Texts.Open(M.text,"");Texts.Append(M.text,W.buf);
	M.beg := 0; M.end := M.text.len; M.F := NIL; Display.Broadcast(M)
END InsertTime;

PROCEDURE Init(F: Clock);
BEGIN
	F.W := 40; F.H := 40; F.handle := ClockHandler; 
	F.state := {Gadgets.transparent}; F.state0 := {new};
	F.col := Display3.textC; F.time := GetClock();
	F.date := 0; F.timeDiff := 0
END Init;

PROCEDURE NewClock*;
VAR F: Clock;
BEGIN NEW(F); Init(F);
	F.W := 40; F.H := 40;
	F.state0 := {new}; F.col := Display3.textC;
	Objects.NewObj := F
END NewClock;

PROCEDURE NewDigiClock*;
VAR F: Clock;
BEGIN NEW(F); Init(F);
	F.W := 40; F.H := 20; 
	F.state0 := {digital, new}; F.col := Display3.white;
	Objects.NewObj := F
END NewDigiClock;

PROCEDURE NewCalendar*;
VAR F: Clock;
BEGIN NEW(F); Init(F);
	F.W := 50; F.H := 34; 
	F.state0 := {calendar, new}; F.col := Display3.textC;
	Objects.NewObj := F
END NewCalendar;

PROCEDURE *FreeMod();
BEGIN
	IF task # NIL THEN
		Oberon.Remove(task); task := NIL
	END
END FreeMod;

BEGIN
	font[0] := Fonts.This("Default8.Scn.Fnt");
	font[1] := Fonts.This("Default12b.Scn.Fnt");
	font[2] := Fonts.This("Default10b.Scn.Fnt");
	NEW(task); task.handle := AlarmTask; lastTick := 0; task.safe := TRUE; Oberon.Install(task);
	zeroY := Dates.NumberOfDays(Dates.ToDate(1961, 1, 1));
	Texts.OpenWriter(W); Modules.InstallTermHandler(FreeMod)
END Clocks.

System.Free Clocks ~
Gadgets.Insert Clocks.NewCalendar ~ Gadgets.Insert Clocks.NewDigiClock ~  ~
Gadgets.Insert Clocks.NewClock ~
