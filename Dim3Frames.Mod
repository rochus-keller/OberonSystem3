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

MODULE Dim3Frames;	(** portable *)	(* David Ulrich Nov 95 - März 96 *)
(** This module implements a 3D Engine frame and gadget **)

IMPORT
	Attributes, Display, Display3, Effects, Files, Input, Gadgets, Math, Oberon, Objects, Pictures, Strings,
	Dim3Read, Dim3Engine, Texts;

CONST
	MR = 0; MM = 1; ML = 2;


TYPE
	Frame* = POINTER TO FrameDesc;
	Navigator* = PROCEDURE (F: Frame; R: Display3.Mask; VAR M: Oberon.InputMsg);
	
	FrameDesc* = RECORD (Gadgets.FrameDesc)
		P* : Pictures.Picture;	(** bitmap for double buffer rendering **)
		camera*: Dim3Engine.Camera;	(** viewing parameters **)
		navigate*: Navigator;	(** maps mouse movements to camera movements **)
		absX*, absY*: INTEGER;	(** cached screen coordinates **)
	END;


VAR
	frameRate: REAL;	(* current number of frames per second *)
	W: Texts.Writer;
	drawF: Frame;	(* temporary globals when rendering picture to display *)
	drawM: Display3.Mask;
	px, py: INTEGER;


(*--- Display ---*)

PROCEDURE* DrawRect (x, y, w, h: INTEGER);
VAR r, r1, t, t1: INTEGER;
BEGIN
	r := x + w - 1; r1 := drawM.X + drawM.W - 1; t := y + h - 1; t1 := drawM.Y + drawM.H - 1;
	IF x < drawM.X THEN x := drawM.X END;
	IF y < drawM.Y THEN y := drawM.Y END;
	IF r > r1 THEN r := r1 END;
	IF t > t1 THEN t := t1 END;
	w := r - x + 1; h := t - y + 1;
	Pictures.DisplayBlock(drawF.P, x-px, y-py, w, h, x, y, Display.replace);
	IF Gadgets.selected IN drawF.state THEN
		Display3.FillPattern(drawM, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END DrawRect;

PROCEDURE RestoreFrame (F: Frame; R: Display3.Mask; x, y: INTEGER);
VAR start: LONGINT;
BEGIN
	start := Oberon.Time();
	Dim3Engine.DrawDirect(F.obj(Dim3Engine.World), F.camera, F.P);
	Pictures.ReplConst(F.P, Display.BG, 0, 0, F.P.width, 1, Display.replace);
	Pictures.ReplConst(F.P, Display.BG, F.P.width - 1, 0, 1, F.P.height, Display.replace);
	Pictures.ReplConst(F.P, Display.FG, 0, F.P.height - 1, F.P.width - 1, 1, Display.replace);
	Pictures.ReplConst(F.P, Display.FG, 0, 0, 1, F.P.height, Display.replace);
	
	drawF := F; drawM := R; px := x; py := y;
	Display3.Enum(R, DrawRect);
	frameRate := Input.TimeUnit / (2 + Oberon.Time() - start)
END RestoreFrame;


(**--- Flight Model Navigation ---**)

(* run flight model on current camera view *)
PROCEDURE RunFlightModel (F: Frame; X, Y: INTEGER; speed: REAL);
CONST
	minMove = 5; maxMove = 55; minAngle = 0.01;
VAR
	azi, pitch, roll, maxAngle, sinPitch, cosPitch, sinRoll, cosRoll, xAngle, yAngle: REAL;
	
	PROCEDURE MapToAngle (x: INTEGER): REAL;
	VAR dx: REAL;
	BEGIN
		IF ABS(x) < minMove THEN
			RETURN 0.0
		ELSIF x > 0 THEN
			IF x > maxMove THEN x := maxMove END;
			dx := (x - minMove) / (maxMove - minMove)
		ELSE
			IF x < -maxMove THEN x := -maxMove END;
			dx := (x + minMove) / (maxMove - minMove)
		END;
		RETURN maxAngle * dx*dx*dx
	END MapToAngle;

BEGIN
	(* constrain upper bound for rotations between 30 and 45 degree/sec, depending on speed ratio *)
	maxAngle := Math.pi/12.0 * (2.0 + speed) / frameRate;
	
	(* get current angles *)
	Dim3Engine.GetCameraAngles(F.camera, azi, pitch, roll);
	xAngle := MapToAngle(-X); yAngle := MapToAngle(Y);
	sinPitch := Math.sin(pitch); cosPitch := Math.cos(pitch);
	sinRoll := Math.sin(roll); cosRoll := Math.cos(roll);
	
	(*
	 * Update azimute: Turn the airplane when its wings are not parallel to the horizon (=> bank turns).
	 * The speed of the rotation depends on current airplane velocity, roll angle and on how much the pilot supports
	 * or inhibits the rotation with vertical mouse movements.
	 *)
	azi := azi + (maxAngle/2.0 - yAngle) * sinRoll * ABS(sinRoll);
	
	(*
	 * Map horizontal mouse movements into direction changes when approaching flight directions
	 * perpendicular to the ground plane.
	 *)
	azi := azi - xAngle * sinPitch;
	
	(*
	 * Update pitch: The pilot changes the plane's pitch angle using vertical mouse movements. As roll gets larger,
	 * vertical mouse movements will have an increasing effect on the direction of flight, but less on pitch.
	 * pitch will always be constrained to the interval [-pi/2..pi/2], turning the airplane upside down when necessary.
	 *)
	pitch := pitch - yAngle * cosRoll;
	IF ABS(pitch) > Math.pi/2.0 THEN	(* turn "airplane" upside down *)
		azi := azi + Math.pi;
		roll := roll + Math.pi;
		IF pitch > 0.0 THEN pitch := Math.pi - pitch
		ELSE pitch := -Math.pi - pitch
		END
	ELSIF ABS(pitch) < 0.01 THEN
		pitch := 0.0
	END;
	
	(*
	 * Update roll: when flying parallel to the ground, horizontal mouse movements will directly affect roll. When flying more
	 * and more perpendicular to the ground, however, these mouse movements will affect mainly the current azimute.
	 * (In that case, GetCameraAngles will return smaller amounts of roll, anyway)
	 *)
	roll := roll + xAngle * cosPitch;
	IF ABS(roll) < minAngle THEN
		roll := 0.0
	END;
	Dim3Engine.SetCameraAngles(F.camera, azi, pitch, roll)
END RunFlightModel;


PROCEDURE FlightNavigator* (F: Frame; R: Display3.Mask; VAR M: Oberon.InputMsg);
CONST
	minSpeed = 0.0; maxSpeed = 50.0;
VAR keys: SET; X, Y: INTEGER; ch: CHAR; speed: REAL;
BEGIN
	speed := minSpeed;
	Input.Mouse(keys, X, Y);
	Display.Dot(Display.FG, X, Y, Display.invert);
	REPEAT
		IF Input.Available() > 0 THEN	(* "a" and "z" keys control speed *)
			REPEAT 
				Input.Read(ch)
			UNTIL Input.Available() = 0;
			IF ch = "a" THEN
				speed := speed + 10/frameRate;
				IF speed > maxSpeed THEN speed := maxSpeed END
			ELSIF ch = "z" THEN
				speed := speed - 10/frameRate;
				IF speed < minSpeed THEN speed := minSpeed END
			END
		END;
		
		Dim3Engine.MoveCamera(F.camera, 0, 0, 0.1*speed/frameRate);
		RunFlightModel(F, X - M.X, Y - M.Y, (speed - minSpeed)/(maxSpeed - minSpeed));
		IF F.camera.pos[1] < 0 THEN	(* stay above "ground" *)
			F.camera.pos[1] := 0
		END;
		RestoreFrame(F, R, F.absX, F.absY);
		IF (X < F.absX) OR (X >= F.absX + F.W) OR (Y < F.absY) OR (Y >= F.absY + F.H) THEN
			Display.Dot(Display.FG, X, Y, Display.invert)
		END;
		Input.Mouse(keys, X, Y);
		Display.Dot(Display.FG, X, Y, Display.invert)
	UNTIL ~(ML IN keys);
	Display.Dot(Display.FG, X, Y, Display.invert)
END FlightNavigator;


(**--- Simple Navigation ---**)

PROCEDURE SimpleNavigator* (F: Frame; R: Display3.Mask; VAR M: Oberon.InputMsg);
CONST minSpeed = 5;
VAR keys: SET; X, Y, oldX, oldY: INTEGER; ch: CHAR;
BEGIN
	oldX := M.X;
	Input.Mouse(keys, X, Y);
	Display.Dot(Display.FG, X, Y, Display.invert);
	REPEAT
		IF Input.Available() > 0 THEN	(* "a" and "z" keys move up and down *)
			REPEAT 
				Input.Read(ch)
			UNTIL Input.Available() = 0;
			IF ch = "a" THEN
				Dim3Engine.MoveCamera(F.camera, 0, 1.0/frameRate, 0)
			ELSIF ch = "z" THEN
				Dim3Engine.MoveCamera(F.camera, 0, -1.0/frameRate, 0)
			END
		END;
		
		Dim3Engine.RotateCamera(F.camera, Math.pi * (oldX - X)/F.W, 0, 1, 0);
		oldX := X; oldY := Y;
		Y := Y - M.Y;
		IF ABS(Y) > minSpeed THEN
			IF Y > 0 THEN Y := Y - minSpeed
			ELSE Y := Y + minSpeed
			END
		ELSE
			Y := 0
		END;
		Dim3Engine.MoveCamera(F.camera, 0, 0, 5*Y/(F.H*frameRate));
		RestoreFrame(F, R, F.absX, F.absY);
		IF (X < F.absX) OR (X >= F.absX + F.W) OR (oldY < F.absY) OR (oldY >= F.absY + F.H) THEN
			Display.Dot(Display.FG, X, oldY, Display.invert)
		END;
		Input.Mouse(keys, X, Y);
		Display.Dot(Display.FG, X, Y, Display.invert)
	UNTIL ~(ML IN keys);
	Display.Dot(Display.FG, X, Y, Display.invert)
END SimpleNavigator;


(*--- Mouse Handler ---*)

PROCEDURE TrackMouse (F: Frame; VAR M: Oberon.InputMsg);
VAR
	keys, keySum: SET; X, Y, oldX, oldY: INTEGER; R: Display3.Mask; poly: Dim3Engine.Polygon;
	shape, parent: Dim3Engine.Shape; x, y: REAL; w: Dim3Engine.World; sel: BOOLEAN; ch: CHAR;
BEGIN
	Gadgets.MakeMask(F, F.absX, F.absY, M.dlink, R);

	IF ML IN M.keys THEN	(* move viewer *)
		Oberon.FadeCursor(Oberon.Mouse);
		F.navigate(F, R, M);
		Input.Mouse(keys, X, Y);
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y);
		WHILE Input.Available() > 0 DO
			Input.Read(ch)
		END;
	
	ELSIF MM IN M.keys THEN	(* execute command *)
		(* get command string *)
		x := 2*(M.X - F.absX - F.W/2) / F.W;
		y := 2*(M.Y - F.absY - F.H/2) / F.H;
		w := F.obj(Dim3Engine.World);
		poly := Dim3Engine.FrontPolygon(w, F.camera, x, y);
		IF poly # NIL THEN shape := poly.shape ELSE shape := NIL END;
		WHILE (shape # NIL) & (shape.cmd = NIL) DO
			shape := shape.parent
		END;
		IF shape # NIL THEN	(* found a shape with a command *)
			Oberon.FadeCursor(Oberon.Mouse);
			Dim3Engine.HighlightShape(w, shape);
			RestoreFrame(F, R, F.absX, F.absY);
			Input.Mouse(keys, X, Y);
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y)
		END;
		oldX := M.X; oldY := M.Y;
		keySum := M.keys;
		REPEAT
			Input.Mouse(keys, X, Y);
			keySum := keySum + keys;
			IF (X # oldX) OR (Y # oldY) THEN
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y);
				oldX := X; oldY := Y
			END
		UNTIL ~(MM IN keys);
		IF shape # NIL THEN
			Oberon.FadeCursor(Oberon.Mouse);
			Dim3Engine.HighlightShape(w, shape);	(* flip back to old color *)
			RestoreFrame(F, R, F.absX, F.absY);
			Input.Mouse(keys, X, Y);
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y);
			IF keySum # {ML, MM, MR} THEN
				Dim3Engine.executor := shape;
				Gadgets.Execute(shape.cmd^, F.obj, F, NIL, NIL)
			END
		END
	
	ELSIF MR IN M.keys THEN	(* select shape *)
		x := 2*(M.X - F.absX - F.W/2) / F.W;
		y := 2*(M.Y - F.absY - F.H/2) / F.H;
		w := F.obj(Dim3Engine.World);
		poly := Dim3Engine.FrontPolygon(w, F.camera, x, y);
		IF poly # NIL THEN shape := poly.shape ELSE shape := NIL END;
		Oberon.FadeCursor(Oberon.Mouse);
		IF shape # NIL THEN
			sel := Dim3Engine.selected IN shape.state;
			Dim3Engine.SelectShape(w, shape, ~sel);
			parent := shape.parent;
			Input.Mouse(keys, X, Y);
			WHILE MR IN keys DO
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y);
				IF (MM IN keys) & (parent # NIL) & (sel = (Dim3Engine.selected IN parent.state)) THEN
					Oberon.FadeCursor(Oberon.Mouse);
					Dim3Engine.SelectShape(w, parent, ~sel);
					parent := parent.parent;
					WHILE MM IN keys DO
						Input.Mouse(keys, X, Y);
						Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y)
					END
				END;
				Input.Mouse(keys, X, Y);
			END
			
		ELSE	(* clear selection *)
			Dim3Engine.SelectShape(w, w.shape, FALSE);
			Input.Mouse(keys, X, Y);
			WHILE MR IN keys DO
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y);
				Input.Mouse(keys, X, Y)
			END
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y)
	
	ELSE
		Gadgets.framehandle(F, M)
	END
END TrackMouse;


(**--- Message Handling ---**)

(* handle frame attributes *)
PROCEDURE FrameAttr (F: Frame; VAR M: Objects.AttrMsg);
VAR w: Dim3Engine.World;
BEGIN
	(* let frame handle message *)
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class := Objects.String; COPY("Dim3Frames.NewFrame", M.s); M.res := 0
	
	(* pass message on to selected object if still unhandled*)
	ELSIF (F.obj # NIL) & ~(Gadgets.selected IN F.state) THEN
		w := F.obj(Dim3Engine.World);
		IF w.selShape # NIL THEN
			Dim3Engine.HandleShapeAttr(w.selShape, M);
			IF M.res = 1 THEN
				Dim3Engine.ShadeShape(w, w.selShape)
			END
		ELSE
			Gadgets.framehandle(F, M)
		END
	ELSE
		Gadgets.framehandle(F, M)
	END;
	
	IF M.res < 0 THEN
		Gadgets.framehandle(F, M)
	END
END FrameAttr;

(* update checkbox which shows if the horizon is drawn *)
PROCEDURE UpdateHorizonBox* (F: Frame);
VAR obj: Objects.Object; M: Objects.AttrMsg;
BEGIN
	obj := Gadgets.FindObj(Gadgets.context, "horizonBox");
	IF obj # NIL THEN
		M.id := Objects.set; M.name := "Value"; M.res := -1; M.class := Objects.Bool;
		M.b := F.obj(Dim3Engine.World).horizon;
		obj.handle(obj, M);
		Gadgets.Update(obj)
	END;
END UpdateHorizonBox;

(** default frame handler **)
PROCEDURE FrameHandler* (F: Objects.Object; VAR M: Objects.ObjMsg);
VAR w, h, depth: INTEGER; f: Frame; R: Display3.Mask; world: Dim3Engine.World;
BEGIN
	WITH F: Frame DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN
					F.absX := M.x + F.X; F.absY := M.y+ F.Y; w := F.W; h := F.H;
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, F.absX, F.absY, M.dlink, R);
									RestoreFrame(F, R, F.absX, F.absY)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, F.absX, F.absY, M.dlink, R);
									Display3.AdjustMask(R, F.absX + M.u, F.absY + h - 1 + M.v, M.w, M.h);
									RestoreFrame(F, R, F.absX, F.absY)
								END
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & (M.keys # {}) & Gadgets.InActiveArea(F, M) THEN
								TrackMouse(F, M); M.res := 0
							ELSE
								Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Display.ModifyMsg THEN
						WITH M: Display.ModifyMsg DO
							Pictures.Create(F.P, M.W, M.H, Pictures.colorD);
							Gadgets.framehandle(F, M);
							IF M.mode = Display.display THEN
								Gadgets.Update(F)
							END
						END
					ELSIF M IS Display.SelectMsg THEN
						WITH M: Display.SelectMsg DO
							Gadgets.framehandle(F, M);
							IF (M.id = Display.get) & ~(Gadgets.selected IN F.state) THEN
								world := F.obj(Dim3Engine.World);
								IF (world.time > M.time) & (world.selCount > 0) THEN
									M.obj := F; M.time := world.time;
								END
							END
						END
					ELSIF M IS Gadgets.UpdateMsg THEN
						WITH M: Gadgets.UpdateMsg DO
							IF M.obj = F.obj THEN
								Gadgets.MakeMask(F, F.absX, F.absY, M.dlink, R);
								RestoreFrame(F, R, F.absX, F.absY);
								UpdateHorizonBox(F)
							ELSE
								Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Oberon.ControlMsg THEN
						WITH M: Oberon.ControlMsg DO
							IF M.id = Oberon.neutralize THEN
								Dim3Engine.Neutralize(F.obj(Dim3Engine.World))
							END;
							Gadgets.framehandle(F, M)
						END
					ELSE
						Gadgets.framehandle(F, M)
					END
				END
			END
		
		ELSIF M IS Objects.AttrMsg THEN
			FrameAttr(F, M(Objects.AttrMsg))
		
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				Gadgets.framehandle(F, M);
				IF M.id = Objects.store THEN
					Files.WriteInt(M.R, F.P.depth);
					Dim3Engine.WriteCamera(M.R, F.camera)
				ELSIF M.id = Objects.load THEN
					Files.ReadInt(M.R, depth);
					Pictures.Create(F.P, F.W, F.H, depth);
					Dim3Engine.ReadCamera(M.R, F.camera)
				END
			END
		
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN
					M.obj := F.dlink
				ELSE
					NEW(f); F.stamp := M.stamp; F.dlink := f;
					Gadgets.CopyFrame(M, F, f);	(* handles deep copies as well *)
					IF M.id = Objects.shallow THEN
						f.P := F.P
					ELSIF M.id = Objects.deep THEN
						NEW(f.P); Pictures.Create(f.P, f.W, f.H, F.P.depth)
					END;
					f.camera := F.camera; f.navigate := F.navigate;
					M.obj := f
				END
			END
		
		ELSE
			Gadgets.framehandle(F, M)
		END
	END
END FrameHandler;


(**--- Frame Commands ---**)

(* find frame in current context *)
PROCEDURE GetFrame* (VAR F: Frame);
VAR obj: Objects.Object;
BEGIN
	F := NIL;
	obj := Gadgets.FindObj(Gadgets.context, "camera");
	IF (obj # NIL) & (obj IS Frame) THEN
		F := obj(Frame)
	ELSE
		Texts.WriteString(W, "Dim3Frames.GetFrame: cannot find frame"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END
END GetFrame;

(** generator procedure **)
PROCEDURE NewFrame*;
VAR F: Frame;
BEGIN
	NEW(F);
	F.W := 250; F.H := 250; F.handle := FrameHandler; F.navigate := SimpleNavigator;
	NEW(F.P); Pictures.Create(F.P, F.W, F.H, Display.Depth(Display.ColLeft));
	Dim3Engine.InitCamera(F.camera);
	Gadgets.NameObj(F, "camera");
	Dim3Engine.NewWorld;
	F.obj := Objects.NewObj;
	Objects.NewObj := F;
END NewFrame;

(** clear and free actual world **)
PROCEDURE ClearWorld*;
VAR F: Frame;
BEGIN
	Texts.WriteString(W, "Dim3Frames.ClearWorld"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	GetFrame(F);
	IF F # NIL THEN
		Dim3Engine.FreeWorld(F.obj(Dim3Engine.World))	(* generates update *)
	END
END ClearWorld;

(** set horizon (yes/no) by check box **)
PROCEDURE SetHorizon*;
VAR F: Frame; S: Attributes.Scanner;
BEGIN
	Texts.WriteString(W, "Dim3Frames.SetHorizon"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	GetFrame(F);
	IF F # NIL THEN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
		IF S.class = Attributes.Name THEN
			Strings.StrToBool(S.s, F.obj(Dim3Engine.World).horizon);
			Gadgets.Update(F.obj)
		END
	END
END SetHorizon;

(** set flight model by button **)
PROCEDURE SetFlightModel*;
VAR F: Frame;
BEGIN
	Texts.WriteString(W, "Dim3Frames.SetFlightModel"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	GetFrame(F);
	IF F # NIL THEN
		F.navigate := FlightNavigator
	END
END SetFlightModel;

(** set simple model by button **)
PROCEDURE SetSimpleModel*;
VAR F: Frame;
BEGIN
	Texts.WriteString(W, "Dim3Frames.SetSimpleModel"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	GetFrame(F);
	IF F # NIL THEN
		F.navigate := SimpleNavigator
	END
END SetSimpleModel;


PROCEDURE UpdateFOV (F: Frame);
VAR obj: Objects.Object; M: Objects.AttrMsg;
BEGIN
	obj := Gadgets.FindObj(Gadgets.context, "FOV");
	IF obj # NIL THEN
		M.id := Objects.set; M.name := "Value"; M.res := -1; M.class := Objects.Real;
		M.x := 0.01 * ENTIER(100.0*2.0*180.0/Math.pi * F.camera.fov + 0.5);
		obj.handle(obj, M);
		Gadgets.Update(obj)
	END
END UpdateFOV;

(** reset view of actual frame **)
PROCEDURE ResetView*;
VAR F: Frame;
BEGIN
	Texts.WriteString(W, "Dim3Frames.ResetView"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	GetFrame(F);
	IF F # NIL THEN
		Dim3Engine.InitCamera(F.camera);
		UpdateFOV(F);
		Gadgets.Update(F)
	END
END ResetView;

(** set view angle by slider **)
PROCEDURE SetViewAngle*;
VAR F: Frame; S: Texts.Scanner;
BEGIN
	Texts.WriteString(W, "Dim3Frames.SetViewAngle"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	GetFrame(F);
	IF F # NIL THEN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Int THEN
			F.camera.fov := 0.5*Math.pi/180.0 * S.i;
			Gadgets.Update(F)
		ELSIF S.class = Texts.Real THEN
			F.camera.fov := 0.5*Math.pi/180.0 * S.x;
			Gadgets.Update(F)
		END
	END
END SetViewAngle;

PROCEDURE AlignSelection*;
VAR
	F: Frame; s: Dim3Engine.Shape; R: Display3.Mask; N, M: Dim3Engine.Matrix; angle: REAL;
	axis, scale, trans: Dim3Engine.Vector; steps: LONGINT;
BEGIN
	Texts.WriteString(W, "Dim3Frames.AlignSelection"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	GetFrame(F);
	IF F # NIL THEN
		s := F.obj(Dim3Engine.World).selShape;
		IF s # NIL THEN
			Gadgets.MakeMask(F, F.absX, F.absY, Gadgets.context, R);
			
			(* bring shape into focus *)
			Dim3Engine.GetCameraTrafo(F.camera, N);
			Dim3Engine.ConcatMatrix(N, s.T, M);
			Dim3Engine.Decompose(M, angle, axis, scale, trans);
			Dim3Engine.Normalize(trans);
			angle := Dim3Engine.Atan2(Math.sqrt(ABS(1.0 - trans[2]*trans[2])), -trans[2]);	(* angle between trans and [0 0 -1] *)
			IF ABS(angle) > 1.0E-5 THEN
				steps := ENTIER(1 + 10/Math.pi * ABS(angle) * frameRate);
				angle := -angle / steps;
				WHILE steps > 0 DO
					Dim3Engine.RotateCamera(F.camera, angle, -trans[1], trans[0], 0);
					RestoreFrame(F, R, F.absX, F.absY);
					DEC(steps)
				END
			END;
			
			(* rotate in front of shape *)
			Dim3Engine.GetCameraTrafo(F.camera, N);
			Dim3Engine.ConcatMatrix(N, s.T, M);
			Dim3Engine.Decompose(M, angle, axis, scale, trans);
			Dim3Engine.Normalize(axis);
			IF ABS(Dim3Engine.DotProd(axis, axis)) > 0 THEN
				steps := ENTIER(1 + 10/Math.pi * ABS(angle) * frameRate);
				angle := -angle / steps;
				WHILE steps > 0 DO
					Dim3Engine.MoveCamera(F.camera, 0, 0, -trans[2]);
					Dim3Engine.RotateCamera(F.camera, angle, axis[0], axis[1], axis[2]);
					Dim3Engine.MoveCamera(F.camera, 0, 0, trans[2]);
					RestoreFrame(F, R, F.absX, F.absY);
					DEC(steps)
				END
			END
		ELSE
			Texts.WriteString(W, "[More than one or no selected shapes]"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END
END AlignSelection;

PROCEDURE Poll;	(* for LNO *)
BEGIN
	IF Input.Available() = 0 THEN END
END Poll;

(** make benchmark test **)
PROCEDURE Benchmark*;
CONST nFrames = 160;
VAR F: Frame; X, Y, i: INTEGER; start, time: LONGINT; R: Display3.Mask;
BEGIN
	Texts.WriteString(W, "Dim3Frames.Benchmark: ");
	GetFrame(F);
	IF F = NIL THEN RETURN END;
	
	X := Oberon.Mouse.X; Y := Oberon.Mouse.Y;
	Oberon.FadeCursor(Oberon.Mouse);
	Gadgets.MakeMask(F, F.absX, F.absY, Gadgets.context, R);
	Dim3Engine.InitCamera(F.camera);
	UpdateFOV(F);
	start := Oberon.Time();
	
	FOR i := 1 TO nFrames DIV 8 DO
		RestoreFrame(F, R, F.absX, F.absY);
		Dim3Engine.MoveCamera(F.camera, 0, 0, -80/nFrames);
		Dim3Engine.RotateCamera(F.camera, 8*Math.pi/(6*nFrames), 0, 0, 1);
		Poll
	END;
	Dim3Engine.InitCamera(F.camera);
	Dim3Engine.MoveCamera(F.camera, 0, 0, -10);
	Dim3Engine.RotateCamera(F.camera, Math.pi/6, 0, 0, 1);
	
	FOR i := 1 TO nFrames DIV 4 DO
		RestoreFrame(F, R, F.absX, F.absY);
		Dim3Engine.MoveCamera(F.camera, 0, 0, 10);
		Dim3Engine.RotateCamera(F.camera, 4*Math.pi/nFrames, 0, 1, 0);
		Dim3Engine.MoveCamera(F.camera, 0, 0, -10);
		Poll
	END;
	Dim3Engine.InitCamera(F.camera);
	Dim3Engine.RotateCamera(F.camera, Math.pi, 0, 1, 0);
	Dim3Engine.MoveCamera(F.camera, 0, 0, -10);
	Dim3Engine.RotateCamera(F.camera, -Math.pi/6, 0, 0, 1);
	
	FOR i := 1 TO nFrames DIV 4 DO
		RestoreFrame(F, R, F.absX, F.absY);
		Dim3Engine.RotateCamera(F.camera, 8*Math.pi/(6*nFrames), 0, 0, 1);
		Poll
	END;
	Dim3Engine.InitCamera(F.camera);
	Dim3Engine.RotateCamera(F.camera, Math.pi, 0, 1, 0);
	Dim3Engine.MoveCamera(F.camera, 0, 0, -10);
	Dim3Engine.RotateCamera(F.camera, Math.pi/6, 0, 0, 1);
	
	FOR i := 1 TO nFrames DIV 4 DO
		RestoreFrame(F, R, F.absX, F.absY);
		Dim3Engine.MoveCamera(F.camera, 0, 0, 10);
		Dim3Engine.RotateCamera(F.camera, 4*Math.pi/nFrames, 0, 1, 0);
		Dim3Engine.MoveCamera(F.camera, 0, 0, -10);
		Poll
	END;
	Dim3Engine.InitCamera(F.camera);
	Dim3Engine.MoveCamera(F.camera, 0, 0, -10);
	Dim3Engine.RotateCamera(F.camera, -Math.pi/6, 0, 0, 1);
	
	FOR i := 1 TO nFrames DIV 8 DO
		RestoreFrame(F, R, F.absX, F.absY);
		Dim3Engine.MoveCamera(F.camera, 0, 0, 80/nFrames);
		Dim3Engine.RotateCamera(F.camera, 8*Math.pi/(6*nFrames), 0, 0, 1);
		Poll
	END;
	Dim3Engine.InitCamera(F.camera);
	RestoreFrame(F, R, F.absX, F.absY);
	
	time := Oberon.Time() - start;
	Texts.WriteInt(W, time, 0); Texts.WriteString(W, " ticks (");
	Texts.WriteRealFix(W, time/Input.TimeUnit, 3, 2, 0); Texts.WriteString(W, " sec)"); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf);
	Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y)
END Benchmark;

(** show actual statistics about world in log **)
PROCEDURE ShowStatistics*;
VAR F: Frame;
BEGIN
	Texts.WriteString(W, "Dim3Frames.ShowStatistics: "); Texts.Append(Oberon.Log, W.buf);
	GetFrame(F);
	IF F # NIL THEN
		Dim3Engine.Statistics(F.obj(Dim3Engine.World))
	END
END ShowStatistics;

(** read new world **)
PROCEDURE Read*;
VAR F: Frame; S: Texts.Scanner; T: Texts.Text;
BEGIN
	Texts.WriteString(W, "Dim3Frames.Read"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	GetFrame(F);
	IF F # NIL THEN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN
			Texts.WriteString(W, "  "); Texts.WriteString(W, S.s); Texts.WriteString(W, ": "); Texts.Append(Oberon.Log, W.buf);
			NEW(T); Texts.Open(T, S.s);
			Dim3Read.Read(F.obj(Dim3Engine.World), T); 
			UpdateHorizonBox(F);
			Gadgets.Update(F)
		END
	END
END Read;

(** print actual frame rate in log **)
PROCEDURE Performance*;
BEGIN
	Texts.WriteString(W, "Dim3Frames.Performance: current frame rate is "); Texts.WriteRealFix(W, frameRate, 2, 3, 0);
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
END Performance;


BEGIN
	frameRate := 10;
	Texts.OpenWriter(W)
END Dim3Frames.
