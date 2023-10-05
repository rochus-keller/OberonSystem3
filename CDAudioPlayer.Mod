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

MODULE CDAudioPlayer;	(** portable *) (* ejz, 28.7.95 *)
	IMPORT Sound, Input, Objects, Texts, Oberon, Gadgets, BasicGadgets;

	VAR
		T: Oberon.Task;
		track, min, sec, tracks: BasicGadgets.Integer;
		power, pause: BasicGadgets.Boolean;
		pow: BOOLEAN;

	PROCEDURE *Timer(me: Oberon.Task);
		VAR t, m, s: INTEGER;
	BEGIN
		Sound.GetCDPos(t, m, s);
		IF Sound.res # Sound.Done THEN
			t := 0;
			m := 0;
			s := 0
		END;
		IF s # sec.val THEN
			sec.val := s;
			Gadgets.Update(sec)
		END;
		IF m # min.val THEN
			min.val := m;
			Gadgets.Update(min)
		END;
		IF t # track.val THEN
			track.val := t;
			Gadgets.Update(track)
		END;
		IF (t = 0) & (tracks.val # 0) THEN
			tracks.val := 0;
			Gadgets.Update(tracks)
		ELSIF (t > 0) & (tracks.val = 0) THEN
			tracks.val := Sound.NrOfCDTracks();
			Gadgets.Update(tracks)
		END;
		me.time := Oberon.Time()+Input.TimeUnit
	END Timer;

	PROCEDURE UnPause();
	BEGIN
		IF pause.val THEN
			pause.val := FALSE;
			Gadgets.Update(pause)
		END
	END UnPause;

	PROCEDURE FlipPower*;
	BEGIN
		IF power.val OR ~pow THEN
			Sound.OpenCD();
			IF Sound.res = Sound.Done THEN
				pow := TRUE;
				power.val := TRUE;
				IF T = NIL THEN
					NEW(T);
					T.safe := FALSE;
					T.handle := Timer;
					T.time := Oberon.Time();
					Oberon.Install(T)
				END
			ELSE
				power.val := FALSE
			END
		ELSE
			Sound.CloseCD();
			IF T # NIL THEN
				Timer(T);
				Oberon.Remove(T);
				T := NIL
			END;
			power.val := FALSE
		END;
		Gadgets.Update(power);
		UnPause();
		Gadgets.Update(pause)
	END FlipPower;

	PROCEDURE Stop*;
	BEGIN
		Sound.StopCD();
		UnPause()
	END Stop;

	PROCEDURE FlipDoor*;
	BEGIN
		UnPause();
		IF Sound.mediapresent IN Sound.GetCDState() THEN
			Sound.OpenDoor()
		ELSE
			Sound.CloseDoor()
		END
	END FlipDoor;

	PROCEDURE PlayFromTrack(track: INTEGER);
		VAR last, min, sec: INTEGER;
	BEGIN
		UnPause();
		last := Sound.NrOfCDTracks();
		IF tracks.val # last THEN
			Gadgets.Update(tracks)
		END;
		Sound.CDTrackInfo(last, min, sec);
		Sound.PlayCD(track, 0, 0, last, min, sec-1)
	END PlayFromTrack;

	PROCEDURE PlayAll*;
	BEGIN
		PlayFromTrack(1)
	END PlayAll;

	PROCEDURE Play*;
		VAR S: Texts.Scanner;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF (S.class = Texts.Int) & (S.i > 0) THEN
			PlayFromTrack(SHORT(S.i))
		END
	END Play;

	PROCEDURE FlipPause*;
	BEGIN
		IF pause.val THEN
			IF Sound.playing IN Sound.GetCDState() THEN
				Sound.PauseCD();
				pause.val := Sound.res = Sound.Done
			ELSE
				pause.val := FALSE
			END
		ELSIF ~(Sound.playing IN Sound.GetCDState()) THEN
			Sound.ResumeCD();
			pause.val := FALSE
		END;
		Gadgets.Update(pause)
	END FlipPause;

	PROCEDURE Prev*;
	BEGIN
		IF track.val > 1 THEN
			UnPause();
			PlayFromTrack(SHORT(track.val)-1)
		END
	END Prev;

	PROCEDURE Next*;
		VAR nr: INTEGER;
	BEGIN
		nr := Sound.NrOfCDTracks();
		IF track.val < nr THEN
			UnPause();
			PlayFromTrack(SHORT(track.val)+1)
		END
	END Next;

	PROCEDURE InitLib();
		VAR
			lib: Objects.Library;
			obj: Objects.Object;
			B: Objects.BindMsg;
	BEGIN
		lib := Objects.ThisLibrary("Sound.Lib");
		B.lib := lib;

		BasicGadgets.NewInteger();
		obj := Objects.NewObj;
		obj(BasicGadgets.Integer).val := 0;
		obj.handle(obj, B);
		Objects.PutName(lib.dict, obj.ref, "CDTrack");

		BasicGadgets.NewInteger();
		obj := Objects.NewObj;
		obj(BasicGadgets.Integer).val := 0;
		obj.handle(obj, B);
		Objects.PutName(lib.dict, obj.ref, "CDMin");

		BasicGadgets.NewInteger();
		obj := Objects.NewObj;
		obj(BasicGadgets.Integer).val := 0;
		obj.handle(obj, B);
		Objects.PutName(lib.dict, obj.ref, "CDSec");

		BasicGadgets.NewInteger();
		obj := Objects.NewObj;
		obj(BasicGadgets.Integer).val := 0;
		obj.handle(obj, B);
		Objects.PutName(lib.dict, obj.ref, "CDTracks");

		BasicGadgets.NewBoolean();
		obj := Objects.NewObj;
		obj(BasicGadgets.Boolean).val := FALSE;
		obj.handle(obj, B);
		Objects.PutName(lib.dict, obj.ref, "CDPower");

		BasicGadgets.NewBoolean();
		obj := Objects.NewObj;
		obj(BasicGadgets.Boolean).val := FALSE;
		obj.handle(obj, B);
		Objects.PutName(lib.dict, obj.ref, "CDPause");

		lib.Store(lib)
	END InitLib;

	PROCEDURE InitObjs();
		PROCEDURE FindIntObj(name: ARRAY OF CHAR): BasicGadgets.Integer;
			VAR obj: Objects.Object;
		BEGIN
			obj := Gadgets.FindPublicObj(name);
			IF (obj = NIL) OR ~(obj IS BasicGadgets.Integer) THEN
				InitLib();
				obj := Gadgets.FindPublicObj(name)
			END;
			obj(BasicGadgets.Integer).val := 0;
			RETURN obj(BasicGadgets.Integer)
		END FindIntObj;
		PROCEDURE FindBoolObj(name: ARRAY OF CHAR): BasicGadgets.Boolean;
			VAR obj: Objects.Object;
		BEGIN
			obj := Gadgets.FindPublicObj(name);
			IF (obj = NIL) OR ~(obj IS BasicGadgets.Boolean) THEN
				InitLib();
				obj := Gadgets.FindPublicObj(name)
			END;
			obj(BasicGadgets.Boolean).val := FALSE;
			RETURN obj(BasicGadgets.Boolean)
		END FindBoolObj;
	BEGIN
		track := FindIntObj("Sound.CDTrack");
		Gadgets.Update(track);
		min := FindIntObj("Sound.CDMin");
		Gadgets.Update(min);
		sec := FindIntObj("Sound.CDSec");
		Gadgets.Update(sec);
		tracks := FindIntObj("Sound.CDTracks");
		Gadgets.Update(tracks);
		power := FindBoolObj("Sound.CDPower");
		Gadgets.Update(power);
		pause := FindBoolObj("Sound.CDPause");
		Gadgets.Update(pause)
	END InitObjs;

	PROCEDURE NewTrack*;
	BEGIN
		Objects.NewObj := track
	END NewTrack;

	PROCEDURE NewMin*;
	BEGIN
		Objects.NewObj := min
	END NewMin;

	PROCEDURE NewSec*;
	BEGIN
		Objects.NewObj := sec
	END NewSec;

	PROCEDURE NewPower*;
	BEGIN
		Objects.NewObj := power
	END NewPower;

	PROCEDURE NewPause*;
	BEGIN
		Objects.NewObj := pause
	END NewPause;

	PROCEDURE NewTracks*;
	BEGIN
		Objects.NewObj := tracks
	END NewTracks;

BEGIN
	T := NIL;
	pow := FALSE;
	InitObjs()
END CDAudioPlayer.
