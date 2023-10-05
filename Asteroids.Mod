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

MODULE Asteroids;	(** portable *)	(* by W. Ibl *)
(*
	Aug '96	V 1.0	first release
	Sep '96	V1.1	added ship placement
	Feb '97	V1.2	fixed the marker trap
	Feb '97	V1.3	ported to release 2.2
	July '97	V1.4	FileMessage Bug removed
	Aug '97	V1.4	drawing of selected panel updated
	Okt '97	V1.5	added pause button
*)
IMPORT Attributes,Desktops,Display,Display3,Documents,Effects,Files,Fonts,
			  Gadgets,Strings,Modules,Math,Oberon,Objects,Out,Panels,
			  RandomNumbers;
CONST
	(* Program version *)
	Version = "V 1.5";
	Date = "August '97";

	(* last compatible Program version *)
	CompVers = "V 1.5";

	(* Standard Document strings *)
	DefName = "Asteroids.Doc";
	DocMenu1 = "Desktops.StoreDoc[Store] Asteroids.NewGame[New] Asteroids.PauseGame[Pause]";
	DocMenu2 = "Desktops.StoreDoc[Store] Asteroids.NewGame[New] Asteroids.ResumeGame[Cont]";
	DocIcon = "Icons3.Asteroids";

	(* who wants to live forever? *)
	Indestructable = FALSE;

	(* standard timer delay *)
	BaseDelay = 16;

	(* Control: Turn Left, Turn Right, Accelerate and Brake *)
	ChThrust = 0C1X;
	ChTurnRight = 0C3X;
	ChTurnLeft = 0C4X;
	ChFire = " ";
	ChShield = "z";
	ChWarp = "x";

	(* amount of ships in credit *)
	StartShips = 3;

	(* spaceship parameters and starting values *)
	ShipRotvel = 0.05;	(* rotation velocity inc/decrement per keypress *)
	ShipThrust = 0.3;	(* thrust inc/decrement per keypress *)
	ShipShield = 100;	(* shield energy on stock *)
	ShipWarp = 10;	(* warps on stock *)

	(* ship's bullet parameters and starting values *)
	SBulletMax = 5;	(* Max. of ships' bullets in space at a time *)
	SBulletSpd = 5.0;	(* Speed of ships' bullets *)
	SBulletGrant = 100;	(* amount of ticks a bullet is active *)
	SBulletCost = 10;	(* score decrement per fired bullet *)

	(* timer rounds where shield is stable *)
	SShieldGrant = 5;

	(* factor for ufo appearance - less is more seldom *)
	EAppear = 8000;	(* RAND < (frame/EAppear) *)

	(* ufo's bullet parameters and starting values *)
	EBulletMax = 1;	(* Max. of ufos' bullets in space at a time *)
	EBulletSpd = 2.0;	(* Speed of ufos' bullets *)
	EBulletGrant = 200;	(* amount of ticks a bullet is active *)

	(* detonation parameters *)
	DetonationMax = 50;	(* Max. radius of a detonation circle *)
	DetonationStep = 1;	(* radius increment per tick *)

	(* score adds *)
	HitScoreE1 = 100;	(* hit ufo *)
	HitScoreA1 = 50;	(* hit big asteroid *)
	HitScoreA2 = 70;	(* hit medium asteroid *)
	HitScoreA3 = 80;	(* hit small asteroid *)

	StartAsts = 4;	(* amount of asteroids at first level *)
	SplitAsts = 2;	(* amount of asteroids appearing after detonation *)
TYPE
	Object = Objects.Object;
	Document = Documents.Document;

	(* Message Shortcuts *)
	AttrMsg = Objects.AttrMsg;
	CopyMsg = Objects.CopyMsg;
	DisplayMsg = Display.DisplayMsg;
	FileMsg = Objects.FileMsg;
	InputMsg = Oberon.InputMsg;
	LinkMsg = Objects.LinkMsg;
	ModifyMsg = Display.ModifyMsg;
	UpdateMsg = Gadgets.UpdateMsg;

	(* used for updating the Document's Menu Buttons *)
	MenuMsg = RECORD(Display.FrameMsg)
		frame: Display.Frame;
		paused: BOOLEAN;
	END;

	Vertices = POINTER TO ARRAY OF INTEGER;

	(* the asteroid field *)
	Starfield = POINTER TO StarfieldDesc;
	StarfieldDesc = RECORD(Panels.PanelDesc)
		scaleX,scaleY: REAL;
		fdx: INTEGER;
	END;

	(* vertices of game figures *)
	Shape = POINTER TO ShapeDesc;
	ShapeDesc = RECORD
		n: INTEGER;
		px,py: Vertices;
	END;

	(* object in the starfield space *)
	SpaceObj = POINTER TO SpaceObjDesc;
	SpaceObjDesc = RECORD
		x,y,x0,y0: REAL;
		alive: BOOLEAN;
		next: SpaceObj;
	END;

	(* Detonation - a continuous expanding circle *)
	Detonation = POINTER TO DetonationDesc;
	DetonationDesc = RECORD(SpaceObjDesc)
		r0,r: INTEGER;
	END;

	(* hitable object in the starfield space *)
	Mass = POINTER TO MassDesc;
	MassDesc = RECORD(SpaceObjDesc)
		mass: LONGREAL;
		rot,xvel,yvel,rotvel: REAL;
		shape: Shape;
		n0,u,v,w,h: INTEGER;
		px0,py0,px1,py1: Vertices;
	END;

	(* controlled moving object *)
	FlyingObj = POINTER TO FlyingObjDesc;
	FlyingObjDesc = RECORD(MassDesc)
		bullets: INTEGER;
	END;

	(* fired bullet *)
	Bullet = POINTER TO BulletDesc;
	BulletDesc = RECORD(MassDesc)
		time,rpos: INTEGER;
		ship: FlyingObj;
	END;

	(* player's ship *)
	Ship = POINTER TO ShipDesc;
	ShipDesc = RECORD(FlyingObjDesc)
		thrust0,thrust: BOOLEAN;
		shield0,shield: SHORTINT;
		shieldval,warpval: INTEGER;
		shape0: Shape;
		px2,py2: Vertices;
	END;

	(* an ufo - god knows where it comes from and why *)
	Enemy = POINTER TO EnemyDesc;
	EnemyDesc = RECORD(FlyingObjDesc)
	END;

	(* ship's bullet *)
	SBullet = POINTER TO SBulletDesc;
	SBulletDesc = RECORD(BulletDesc)
	END;

	(* ufo's bullet *)
	EBullet = POINTER TO EBulletDesc;
	EBulletDesc = RECORD(BulletDesc)
	END;

	(* the "real" enemies *)
	Asteroid = POINTER TO AsteroidDesc;
	AsteroidDesc = RECORD(MassDesc)
	END;

	(* the game's model *)
	Field = POINTER TO FieldDesc;
	FieldDesc = RECORD(Gadgets.ObjDesc)
		ship: Ship;
		started,changed,paused: BOOLEAN;
		ships,ufos,frames: INTEGER;
		score,high0,high: LONGINT;
		line0,line: ARRAY 80 OF CHAR;
		objects: SpaceObj;
	END;

	(* sometimes, we need a kick... *)
	Timer = POINTER TO TimerDesc;
	TimerDesc = RECORD(Oberon.TaskDesc)
		model: Field;
		trigger: LONGINT;
		tnext: Timer;
	END;
VAR
	shAsteroid1,shAsteroid2,shAsteroid3,	(* standard shapes *)
	shEnemy,shEBullet,
	shShip,shThrShip,shSBullet: Shape;
	hitscore: ARRAY 4 OF INTEGER;	(* score increments per figure *)
	fnt: ARRAY 7 OF Fonts.Font;	(* score line resize *)
	fw,fh: ARRAY 7 OF INTEGER;
	b,w: INTEGER;	(* drawing colors *)
	timer: Timer;	(* active kickers *)

PROCEDURE FontGeometry(dim: ARRAY OF CHAR; fdx: INTEGER);
	(* query font's parameters for zooming *)
VAR
	fn: Objects.Name;
	fd: INTEGER;
BEGIN
	COPY("Oberon",fn);
	Strings.Append(fn,dim); Strings.Append(fn,".Scn.Fnt");
	fnt[fdx]:= Fonts.This(fn); Display3.StringSize("X",fnt[fdx],fw[fdx],fh[fdx],fd);
END FontGeometry;

PROCEDURE Intersect(x11,y11,x12,y12,x21,y21,x22,y22: INTEGER; VAR x3,y3: INTEGER): BOOLEAN;
	(* calculate intersection between two lines, point is in (x3,y3) *)
VAR
	k1,k2,d1,d2: REAL;
	h1,h2: BOOLEAN;

	PROCEDURE Within(c,a,b: INTEGER): BOOLEAN;
		(* interval calculation *)
	BEGIN
		IF (a < b) THEN RETURN((c>a)&(c<b)); ELSE RETURN((c>=b)&(c<=a)); END;
	END Within;

BEGIN
	h1:= (x11 = x12); h2:= (x21 = x22);
	IF ~h1 THEN
		k1:= (y12 - y11) / (x12 - x11); d1:= y11 - (k1 * x11);
	END;
	IF ~h2 THEN
		k2:= (y22 - y21) / (x22 - x21); d2:= y21 - (k2 * x21);
	END;
	IF ~h1 & ~h2 THEN
		IF (k1 = k2) THEN x3:= -1; y3:= -1; RETURN(FALSE); END;
		x3:= SHORT(ENTIER((d2 - d1) / (k1 - k2)));
		y3:= SHORT(ENTIER((k1 * x3) + d1));
	ELSIF ~h1 & h2 THEN
		x3:= x21; y3:= SHORT(ENTIER((k1 * x3) + d1));
	ELSIF h1 & ~h2 THEN
		x3:= x11; y3:= SHORT(ENTIER((k2 * x3) + d2));
	ELSE
		x3:= x11; y3:= y11; RETURN(x11 = x21);
	END;
	RETURN(Within(x3,x11,x12) & Within(x3,x21,x22) &
				   Within(y3,y11,y12) & Within(y3,y21,y22));
END Intersect;

PROCEDURE Sign(v: REAL): INTEGER;
	(* get the sign of a real (+1|-1) *)
BEGIN
	IF (v < 0.0) THEN RETURN(-1); ELSE RETURN(1); END;
END Sign;

PROCEDURE TransX(x,y: INTEGER; p,v: REAL): REAL;
	(* Transform x-coord - shift and rotate *)
BEGIN
	RETURN((x*Math.cos(p)+y*Math.sin(p))+v);
END TransX;

PROCEDURE TransY(x,y: INTEGER; p,v: REAL): REAL;
	(* Transform y-coord - shift and rotate *)
BEGIN
	RETURN((-x*Math.sin(p)+y*Math.cos(p))+v);
END TransY;

PROCEDURE Model(D: Object): Field;
	(* return the game's model *)
VAR
	model: Object;
BEGIN
	WITH D: Starfield DO model:= D.obj; END;
	WITH model: Field DO RETURN(model); END;
END Model;

PROCEDURE Score(F: Field; score: INTEGER);
	(* calculate player's current score *)
BEGIN
	F.score:= F.score + score; F.changed:= TRUE;
	IF (F.score > F.high0) THEN F.high:= F.score; ELSE F.high:= F.high0; END;
END Score;

PROCEDURE Pair(sh: Shape; n,x,y: INTEGER);
	(* shape initialization *)
BEGIN
	sh.px[n]:= x; sh.py[n]:= y;
END Pair;

PROCEDURE Tag(obj: SpaceObj; VAR tag: Objects.Name);
	(* string tag for loading/storing *)
BEGIN
	WITH
	  	obj: Asteroid DO COPY("Asteroid",tag);
	|	obj: EBullet DO COPY("EBullet",tag);
	|	obj: SBullet DO COPY("SBullet",tag);
	|	obj: Enemy DO COPY("Enemy",tag);
	|	obj: Ship DO COPY("Ship",tag);
	|	obj: Detonation DO COPY("Detonation",tag);
	END;
END Tag;

PROCEDURE ShowStatus(obj: Field; VAR status: ARRAY OF CHAR);
	(* create a up-to-date status line *)
VAR
	nr: ARRAY 16 OF CHAR;
BEGIN
	IF obj.started THEN
		COPY("Ships: ",status);
		Strings.IntToStr(obj.ships,nr); Strings.Append(status,nr);
		Strings.Append(status,"  Warps: ");
		Strings.IntToStr(obj.ship.warpval,nr); Strings.Append(status,nr);
		Strings.Append(status,"  Shield: ");
		Strings.IntToStr(obj.ship.shieldval,nr); Strings.Append(status,nr);
		Strings.Append(status,"  Field: ");
		Strings.IntToStr(obj.frames,nr); Strings.Append(status,nr);
		Strings.Append(status,"  Score: ");
		Strings.IntToStr(obj.score,nr); Strings.Append(status,nr);
		Strings.Append(status,"  High: ");
		Strings.IntToStr(obj.high,nr); Strings.Append(status,nr);
	ELSE
		COPY("Asteroids for Oberon ",status);
		Strings.Append(status,Version);
		Strings.Append(status," by W. Ibl, ");
		Strings.Append(status,Date);
	END;
END ShowStatus;

(*** Game object shapes ***)

PROCEDURE Asteroid1Shape(VAR sh: Shape);
	(* Shape of a big asteroid *)
BEGIN
	NEW(sh); sh.n:= 11; NEW(sh.px,sh.n); NEW(sh.py,sh.n);
	Pair(sh,0,0,0); Pair(sh,1,0,-40); Pair(sh,2,20,-40); Pair(sh,3,40,-20);
	Pair(sh,4,40,20); Pair(sh,5,20,40); Pair(sh,6,-20,40); Pair(sh,7,-40,20);
	Pair(sh,8,-40,-20); Pair(sh,9,-20,-40); Pair(sh,10,0,-40);
END Asteroid1Shape;

PROCEDURE Asteroid2Shape(VAR sh: Shape);
	(* Shape of a medium asteroid *)
BEGIN
	NEW(sh); sh.n:= 11; NEW(sh.px,sh.n); NEW(sh.py,sh.n);
	Pair(sh,0,0,0); Pair(sh,1,0,-20); Pair(sh,2,10,-20); Pair(sh,3,20,-10);
	Pair(sh,4,20,10); Pair(sh,5,10,20); Pair(sh,6,-10,20); Pair(sh,7,-20,10);
	Pair(sh,8,-20,-10); Pair(sh,9,-10,-20); Pair(sh,10,0,-20);
END Asteroid2Shape;

PROCEDURE Asteroid3Shape(VAR sh: Shape);
	(* Shape of a small asteroid *)
BEGIN
	NEW(sh); sh.n:= 11; NEW(sh.px,sh.n); NEW(sh.py,sh.n);
	Pair(sh,0,0,0); Pair(sh,1,0,-10); Pair(sh,2,5,-10); Pair(sh,3,10,-5);
	Pair(sh,4,10,5); Pair(sh,5,5,10); Pair(sh,6,-5,10); Pair(sh,7,-10,5);
	Pair(sh,8,-10,-5); Pair(sh,9,-5,-10); Pair(sh,10,0,-10);
END Asteroid3Shape;

PROCEDURE EnemyShape(VAR sh: Shape);
	(* Shape of an ufo *)
BEGIN
	NEW(sh); sh.n:= 5; NEW(sh.px,sh.n); NEW(sh.py,sh.n);
	Pair(sh,0,-10,0); Pair(sh,1,0,-15); Pair(sh,2,10,0); Pair(sh,3,0,15);
	Pair(sh,4,-10,0);
END EnemyShape;

PROCEDURE EBulletShape(VAR sh: Shape);
	(* Shape of an ufo's bullet *)
BEGIN
	NEW(sh); sh.n:= 5; NEW(sh.px,sh.n); NEW(sh.py,sh.n);
	Pair(sh,0,0,0); Pair(sh,1,3,-3); Pair(sh,2,6,0); Pair(sh,3,3,3);
	Pair(sh,4,0,0);
END EBulletShape;

PROCEDURE ShipShape(VAR sh: Shape);
	(* Shape of the player's ship *)
BEGIN
	NEW(sh); sh.n:= 7; NEW(sh.px,sh.n); NEW(sh.py,sh.n);
	Pair(sh,0,0,0); Pair(sh,1,-20,-20); Pair(sh,2,0,-20); Pair(sh,3,20,0);
	Pair(sh,4,0,20); Pair(sh,5,-20,20); Pair(sh,6,0,0);
END ShipShape;

PROCEDURE ThrShipShape(VAR sh: Shape);
	(* Shape of the player's ship thrusting *)
BEGIN
	NEW(sh); sh.n:= 10; NEW(sh.px,sh.n); NEW(sh.py,sh.n);
	Pair(sh,0,0,0); Pair(sh,1,-20,-20); Pair(sh,2,0,-20); Pair(sh,3,20,0);
	Pair(sh,4,0,20); Pair(sh,5,-20,20); Pair(sh,6,0,0); Pair(sh,7,-5,5);
	Pair(sh,8,-20,0); Pair(sh,9,-7,-5);
END ThrShipShape;

PROCEDURE SBulletShape(VAR sh: Shape);
	(* Shape of the player's ship's bullet *)
BEGIN
	NEW(sh); sh.n:= 2; NEW(sh.px,sh.n); NEW(sh.py,sh.n);
	Pair(sh,0,0,0); Pair(sh,1,10,0);
END SBulletShape;

(*** Object initialization ***)

PROCEDURE InitSpaceObj(obj: SpaceObj);
BEGIN
	obj.x:= 0.0; obj.y:= 0.0; obj.alive:= TRUE; obj.next:= NIL;
END InitSpaceObj;

PROCEDURE InitMass(obj: Mass; shape: Shape);
BEGIN
	InitSpaceObj(obj);
	obj.shape:= shape; obj.n0:= shape.n;
	NEW(obj.px0,obj.n0); NEW(obj.py0,obj.n0);
	NEW(obj.px1,obj.n0); NEW(obj.py1,obj.n0);
	obj.rot:= 0.0; obj.xvel:= 0.0; obj.yvel:= 0.0; obj.rotvel:= 0.0;
END InitMass;

PROCEDURE InitFlyingObj(obj: FlyingObj; shape: Shape);
BEGIN
	InitMass(obj,shape); obj.bullets:= 0;
END InitFlyingObj;

PROCEDURE InitBullet(obj: Bullet; shape: Shape; ship: FlyingObj; grant: INTEGER);
BEGIN
	InitMass(obj,shape); obj.ship:= ship; obj.time:= grant; obj.rpos:= -1;
END InitBullet;

PROCEDURE InitShip(obj: Ship; x,y: REAL);
BEGIN
	InitFlyingObj(obj,shThrShip); obj.shape:= shShip; obj.shape0:= shThrShip;
	IF (obj.px2 = NIL) THEN NEW(obj.px2,shThrShip.n); END;
	IF (obj.py2 = NIL) THEN NEW(obj.py2,shThrShip.n); END;
	obj.thrust:= FALSE; obj.thrust0:= FALSE;
	obj.shield:= 0; obj.shield0:= 0;
	obj.shieldval:= ShipShield; obj.warpval:= ShipWarp;
	obj.x:= x; obj.y:= y;
END InitShip;

PROCEDURE InitSBullet(obj: SBullet; ship: Ship);
BEGIN
	InitBullet(obj,shSBullet,ship,SBulletGrant);
	obj.x:= ship.px1[3]; obj.y:= ship.py1[3]; obj.rot:= ship.rot;
	obj.xvel:= SBulletSpd * ((ship.px1[3] - ship.px1[0]) / 20);
	obj.yvel:= SBulletSpd * ((ship.py1[3] - ship.py1[0]) / 20);
	obj.rotvel:= 0.0;
END InitSBullet;

PROCEDURE InitEnemy(obj: Enemy);
BEGIN
	InitFlyingObj(obj,shEnemy);
	obj.x:= RandomNumbers.Uniform() * Display.Width;
	obj.y:= RandomNumbers.Uniform() * Display.Height;
	obj.xvel:= RandomNumbers.Uniform() - 0.5;
	obj.yvel:= RandomNumbers.Uniform() - 0.5;
	obj.rotvel:= 0.3;
END InitEnemy;

PROCEDURE InitEBullet(obj: EBullet; ufo: Enemy; ship: Ship);
VAR
	dw,dx,dy,dz: REAL;
BEGIN
	InitBullet(obj,shEBullet,ufo,EBulletGrant);
	obj.x:= ufo.px1[0]; obj.y:= ufo.py1[0];
	dx:= (ship.px1[0]-ufo.px1[0]); dy:= (ship.py1[0]-ufo.py1[0]); dz:= dy/dx;
	IF (ABS(dz) > 1.0) THEN dw:= ABS(dz); ELSE dw:= 1.0; END;
	obj.xvel:= Sign(dx) * (EBulletSpd / dw);
	obj.yvel:= Sign(dy) * (EBulletSpd / dw) * dz;
	obj.rotvel:= 0.0;
END InitEBullet;

PROCEDURE InitAsteroid(obj,father: Asteroid; shape: Shape; hx,hy: INTEGER);
BEGIN
	InitMass(obj,shape);
	IF (father # NIL) THEN
		obj.x:= father.px1[0]; obj.y:= father.py1[0];
		obj.xvel:= RandomNumbers.Uniform()-(-(0.5)*Sign(father.px1[0]-hx));
		obj.yvel:= RandomNumbers.Uniform()-(-(0.5)*Sign(father.py1[0]-hy));
	ELSE
		obj.x:= RandomNumbers.Uniform() * Display.Width;
		obj.y:= RandomNumbers.Uniform() * Display.Height;
		obj.xvel:= RandomNumbers.Uniform() - (0.5 * hx);
		obj.yvel:= RandomNumbers.Uniform() - (0.5 * hy);
	END;
	obj.rot:= (RandomNumbers.Uniform() - 0.5) / 10;
	obj.rotvel:= (RandomNumbers.Uniform() - 0.5) / 10;
END InitAsteroid;

PROCEDURE InitField(obj: Field);
BEGIN
	obj.ships:= StartShips; obj.ufos:= 0; obj.frames:= 0; obj.score:= 0;
	obj.high0:= obj.high; obj.objects:= NIL;
	obj.started:= FALSE; obj.changed:= FALSE; obj.paused:= FALSE;
	ShowStatus(obj,obj.line);
END InitField;

PROCEDURE StoreShapeRef(VAR R: Files.Rider; shape: Shape);
	(* store a given tag string *)
BEGIN
	IF (shape = shAsteroid1) THEN
		Files.WriteString(R,"shAsteroid1");
	ELSIF (shape = shAsteroid2) THEN
		Files.WriteString(R,"shAsteroid2");
	ELSIF (shape = shAsteroid3) THEN
		Files.WriteString(R,"shAsteroid3");
	ELSIF (shape = shEnemy) THEN
		Files.WriteString(R,"shEnemy");
	ELSIF (shape = shEBullet) THEN
		Files.WriteString(R,"shEBullet");
	ELSIF (shape = shShip) THEN
		Files.WriteString(R,"shShip");
	ELSIF (shape = shThrShip) THEN
		Files.WriteString(R,"shThrShip");
	ELSIF (shape = shSBullet) THEN
		Files.WriteString(R,"shSBullet");
	END;
END StoreShapeRef;

PROCEDURE LoadShapeRef(VAR R: Files.Rider; VAR shape: Shape);
	(* return shape depending on the tag string *)
VAR
	str: Objects.Name;
BEGIN
	Files.ReadString(R,str);
	IF (str = "shAsteroid1") THEN
		shape:= shAsteroid1;
	ELSIF (str = "shAsteroid2") THEN
		shape:= shAsteroid2;
	ELSIF (str = "shAsteroid3") THEN
		shape:= shAsteroid3;
	ELSIF (str = "shEnemy") THEN
		shape:= shEnemy;
	ELSIF (str = "shEBullet") THEN
		shape:= shEBullet;
	ELSIF (str = "shShip") THEN
		shape:= shShip;
	ELSIF (str = "shThrShip") THEN
		shape:= shThrShip;
	ELSIF (str = "shSBullet") THEN
		shape:= shSBullet;
	ELSE
		shape:= NIL;
	END;
END LoadShapeRef;

(*** Game Object loading/storing ***)

PROCEDURE FileSpaceObj(VAR R: Files.Rider; id: INTEGER; obj,root: SpaceObj);
BEGIN
	IF (id = Objects.store) THEN
		Files.WriteReal(R,obj.x); Files.WriteReal(R,obj.y);
		Files.WriteReal(R,obj.x0); Files.WriteReal(R,obj.y0);
		Files.WriteBool(R,obj.alive);
	ELSIF (id = Objects.load) THEN
		Files.ReadReal(R,obj.x); Files.ReadReal(R,obj.y);
		Files.ReadReal(R,obj.x0); Files.ReadReal(R,obj.y0);
		Files.ReadBool(R,obj.alive);
	END;
END FileSpaceObj;

PROCEDURE FileDetonation(VAR R: Files.Rider; id: INTEGER; obj: Detonation; root: SpaceObj);
BEGIN
	FileSpaceObj(R,id,obj,root);
	IF (id = Objects.store) THEN
		Files.WriteInt(R,obj.r0); Files.WriteInt(R,obj.r);
	ELSIF (id = Objects.load) THEN
		Files.ReadInt(R,obj.r0); Files.ReadInt(R,obj.r);
	END;
END FileDetonation;

PROCEDURE FileMass(VAR R: Files.Rider; id: INTEGER; obj: Mass; root: SpaceObj);
VAR
	i,j: LONGINT;
BEGIN
	FileSpaceObj(R,id,obj,root);
	IF (id = Objects.store) THEN
		Files.WriteLReal(R,obj.mass); Files.WriteReal(R,obj.rot);
		Files.WriteReal(R,obj.xvel); Files.WriteReal(R,obj.yvel);
		StoreShapeRef(R,obj.shape);
		Files.WriteReal(R,obj.rotvel); Files.WriteInt(R,obj.n0);
		Files.WriteInt(R,obj.u); Files.WriteInt(R,obj.v);
		Files.WriteInt(R,obj.w); Files.WriteInt(R,obj.h);
		j:= LEN(obj.px0^); Files.WriteLInt(R,j);
		FOR i:= 0 TO j-1 DO
			Files.WriteInt(R,obj.px0[i]); Files.WriteInt(R,obj.py0[i]);
			Files.WriteInt(R,obj.px1[i]); Files.WriteInt(R,obj.py1[i]);
		END;
	ELSIF (id = Objects.load) THEN
		Files.ReadLReal(R,obj.mass); Files.ReadReal(R,obj.rot);
		Files.ReadReal(R,obj.xvel); Files.ReadReal(R,obj.yvel);
		LoadShapeRef(R,obj.shape);
		Files.ReadReal(R,obj.rotvel); Files.ReadInt(R,obj.n0);
		Files.ReadInt(R,obj.u); Files.ReadInt(R,obj.v);
		Files.ReadInt(R,obj.w); Files.ReadInt(R,obj.h);
		Files.ReadLInt(R,j);
		NEW(obj.px0,j); NEW(obj.py0,j);
		NEW(obj.px1,j); NEW(obj.py1,j);
		FOR i:= 0 TO j-1 DO
			Files.ReadInt(R,obj.px0[i]); Files.ReadInt(R,obj.py0[i]);
			Files.ReadInt(R,obj.px1[i]); Files.ReadInt(R,obj.py1[i]);
		END;
	END;
END FileMass;

PROCEDURE FileFlyingObj(VAR R: Files.Rider; id: INTEGER; obj: FlyingObj; root: SpaceObj);
BEGIN
	FileMass(R,id,obj,root);
	IF (id = Objects.store) THEN
		Files.WriteInt(R,obj.bullets);
	ELSIF (id = Objects.load) THEN
		Files.ReadInt(R,obj.bullets);
	END;
END FileFlyingObj;

PROCEDURE FileBullet(VAR R: Files.Rider; id: INTEGER; obj: Bullet; root: SpaceObj);
VAR
	rpos: INTEGER;
BEGIN
	FileMass(R,id,obj,root);
	IF (id = Objects.store) THEN
		rpos:= 0; WHILE (root # obj.ship) DO INC(rpos); root:= root.next; END;
		Files.WriteInt(R,obj.time); Files.WriteInt(R,rpos);
	ELSIF (id = Objects.load) THEN
		Files.ReadInt(R,obj.time); Files.ReadInt(R,obj.rpos);
	END;
END FileBullet;

PROCEDURE FileShip(VAR R: Files.Rider; id: INTEGER; obj: Ship; root: SpaceObj);
VAR
	i: INTEGER;
BEGIN
	FileFlyingObj(R,id,obj,root);
	IF (id = Objects.store) THEN
		Files.WriteBool(R,obj.thrust0); Files.WriteBool(R,obj.thrust);
		Files.Write(R,obj.shield0); Files.Write(R,obj.shield);
		Files.WriteInt(R,obj.shieldval); Files.WriteInt(R,obj.warpval);
		StoreShapeRef(R,obj.shape0);
		FOR i:= 0 TO obj.shape0.n-1 DO
			Files.WriteInt(R,obj.px2[i]); Files.WriteInt(R,obj.py2[i]);
		END;
	ELSIF (id = Objects.load) THEN
		Files.ReadBool(R,obj.thrust0); Files.ReadBool(R,obj.thrust);
		Files.Read(R,obj.shield0); Files.Read(R,obj.shield);
		Files.ReadInt(R,obj.shieldval); Files.ReadInt(R,obj.warpval);
		LoadShapeRef(R,obj.shape0);
		NEW(obj.px2,shThrShip.n); NEW(obj.py2,shThrShip.n);
		FOR i:= 0 TO shThrShip.n-1 DO
			Files.ReadInt(R,obj.px2[i]); Files.ReadInt(R,obj.py2[i]);
		END;
	END;
END FileShip;

PROCEDURE FileEnemy(VAR R: Files.Rider; id: INTEGER; obj: Enemy; root: SpaceObj);
BEGIN
	FileFlyingObj(R,id,obj,root);
END FileEnemy;

PROCEDURE FileSBullet(VAR R: Files.Rider; id: INTEGER; obj: SBullet; root: SpaceObj);
BEGIN
	FileBullet(R,id,obj,root);
END FileSBullet;

PROCEDURE FileEBullet(VAR R: Files.Rider; id: INTEGER; obj: EBullet; root: SpaceObj);
BEGIN
	FileBullet(R,id,obj,root);
END FileEBullet;

PROCEDURE FileAsteroid(VAR R: Files.Rider; id: INTEGER; obj: Asteroid; root: SpaceObj);
BEGIN
	FileMass(R,id,obj,root);
END FileAsteroid;

(*** end of loading/storing ***)

PROCEDURE ModifyStatus(F: Starfield; obj: Field; mx,my: INTEGER);
	(* create a new status line and display it *)
BEGIN
	ShowStatus(obj,obj.line);
	Oberon.RemoveMarks(F.mask.X,F.mask.Y+5,F.mask.W,fh[F.fdx]);
	Display3.String(F.mask,F.col,mx+F.X+5,my+F.Y+5,fnt[F.fdx],obj.line0,Display3.paint);
	Display3.String(F.mask,w,mx+F.X+5,my+F.Y+5,fnt[F.fdx],obj.line,Display3.paint);
END ModifyStatus;

PROCEDURE RestoreStatus(F: Starfield; obj: Field; mx,my: INTEGER);
	(* display the current status line *)
BEGIN
	Oberon.RemoveMarks(F.mask.X,F.mask.Y+5,F.mask.W,fh[F.fdx]);
	IF (obj.line0 # obj.line) THEN
		Display3.String(F.mask,F.col,mx+F.X+5,my+F.Y+5,fnt[F.fdx],obj.line0,Display3.paint);
		COPY(obj.line,obj.line0);
	END;
	Display3.String(F.mask,w,mx+F.X+5,my+F.Y+5,fnt[F.fdx],obj.line,Display3.paint);
END RestoreStatus;		

(* Game Object drawing *)

PROCEDURE DrawDetonation(F: Starfield; obj: Detonation; mx,my: INTEGER): INTEGER;
VAR
	sx,sy,sr: INTEGER;
BEGIN
	sx:= SHORT(ENTIER(obj.x*F.scaleX)); sy:= SHORT(ENTIER(obj.y*F.scaleY));
	sr:= SHORT(ENTIER(obj.r0*((F.scaleX+F.scaleY)/2)));
	Oberon.RemoveMarks(F.mask.X+sx-sr,F.mask.Y+sy-sr,sr*2,sr*2);
	Display3.Circle(F.mask,F.col,Display.solid,mx+F.X+sx,my+F.Y+sy,sr,1,{},Display3.replace);
	IF obj.alive THEN
		sr:= SHORT(ENTIER(obj.r*((F.scaleX+F.scaleY)/2)));
		Oberon.RemoveMarks(F.mask.X+sx-sr,F.mask.Y+sy-sr,sr*2,sr*2);
		Display3.Circle(F.mask,w,Display.grey2,mx+F.X+sx,my+F.Y+sy,sr,1,{},Display3.replace);
	END;
	RETURN(sy-sr);
END DrawDetonation;

PROCEDURE DrawMass(F: Starfield; obj: Mass; mx,my: INTEGER): INTEGER;
VAR
	su,sv,sw,sh: INTEGER;

	PROCEDURE Poly(x,y: ARRAY OF INTEGER; n,dx,dy,c: INTEGER);
		(* add offset to every point in array and draw *)
	VAR
		i: INTEGER;
	BEGIN
		FOR i:= 0 TO n-1 DO
			x[i]:= SHORT(ENTIER(x[i]*F.scaleX))+dx;
			y[i]:= SHORT(ENTIER(y[i]*F.scaleY))+dy;
		END;
		Display3.Poly(F.mask,c,Display.solid,x,y,n,1,{},Display3.replace);
	END Poly;

BEGIN
	su:= SHORT(ENTIER(obj.u*F.scaleX)); sv:= SHORT(ENTIER(obj.v*F.scaleY));
	sw:= SHORT(ENTIER(obj.w*F.scaleX)); sh:= SHORT(ENTIER(obj.h*F.scaleY));
	Oberon.RemoveMarks(F.mask.X+su,F.mask.Y+sv,sw,sh);
	Poly(obj.px0^,obj.py0^,obj.n0,mx+F.X,my+F.Y,F.col);
	IF obj.alive THEN
		Poly(obj.px1^,obj.py1^,obj.shape.n,mx+F.X,my+F.Y,w);
	END;
	RETURN(sv);
END DrawMass;

PROCEDURE DrawShip(F: Starfield; obj: Ship; mx,my: INTEGER): INTEGER;
VAR
	sx,sy,sr,sv: INTEGER;
BEGIN
	sr:= SHORT(ENTIER(34*((F.scaleX+F.scaleY)/2)));
	IF (obj.shield0 > 0) THEN
		sx:= SHORT(ENTIER(obj.x0*F.scaleX));
		sy:= SHORT(ENTIER(obj.y0*F.scaleY));
		Oberon.RemoveMarks(F.mask.X+sx-sr,F.mask.Y+sy-sr,sr*2,sr*2);
		Display3.Circle(F.mask,F.col,Display.solid,mx+F.X+sx,my+F.Y+sy,sr,1,{},Display3.replace);
	END;
	sv:= DrawMass(F,obj,mx,my);
	IF obj.alive & (obj.shield > 0) THEN
		Oberon.RemoveMarks(F.mask.X+sx-sr,F.mask.Y+sy-sr,sr*2,sr*2);
		sx:= SHORT(ENTIER(obj.x*F.scaleX));
		sy:= SHORT(ENTIER(obj.y*F.scaleY));
		sv:= sy - sr;
		Display3.Circle(F.mask,w,Display.solid,mx+F.X+sx,my+F.Y+sy,sr,1,{},Display3.replace);
	END;
	RETURN(sv);
END DrawShip;

PROCEDURE MoveMass(obj: Mass);
	(* calculate new position of shape vertices using velocities for x, y and rot *)
VAR
	i,w1,h1,w2,h2: INTEGER;
	shp: Shape;
BEGIN
	w1:= 0; h1:= 0; w2:= 0; h2:= 0; shp:= obj.shape;
	obj.x0:= obj.x; obj.y0:= obj.y;
	obj.x:= obj.x + obj.xvel; obj.y:= obj.y + obj.yvel;
	obj.rot:= obj.rot + obj.rotvel;
	FOR i:= 0 TO shp.n-1 DO
		obj.px1[i]:= SHORT(ENTIER(TransX(shp.px[i],shp.py[i],obj.rot,obj.x)));
		obj.py1[i]:= SHORT(ENTIER(TransY(shp.px[i],shp.py[i],obj.rot,obj.y)));
		IF (obj.px1[i] > Display.Width) THEN INC(w1); END;
		IF (obj.px1[i] < 0) THEN INC(w2); END;
		IF (obj.py1[i] > Display.Height) THEN INC(h1); END;
		IF (obj.py1[i] < 0) THEN INC(h2); END;
	END;
	(* if an object disappeared completly, let it fully appear on the opposite *)
	IF (w1 = shp.n) THEN
		obj.x:= obj.x - Display.Width;
		FOR i:= 0 TO shp.n-1 DO DEC(obj.px1[i],Display.Width); END;
	ELSIF (w2 = shp.n) THEN
		obj.x:= obj.x + Display.Width;
		FOR i:= 0 TO shp.n-1 DO INC(obj.px1[i],Display.Width); END;
	END;
	IF (h1 = shp.n) THEN
		obj.y:= obj.y - Display.Height;
		FOR i:= 0 TO shp.n-1 DO DEC(obj.py1[i],Display.Height); END;
	ELSIF (h2 = shp.n) THEN
		obj.y:= obj.y + Display.Height;
		FOR i:= 0 TO obj.shape.n-1 DO DEC(obj.py1[i],Display.Height); END;
	END;
	(* calculate the objects hull (x,y,u,v) for easier intersection and redraw *)
	w1:= MAX(INTEGER); h1:= MAX(INTEGER);
	w2:= MIN(INTEGER); h2:= MIN(INTEGER);
	FOR i:= 0 TO shp.n-1 DO
		IF (obj.px1[i] < w1) THEN w1:= obj.px1[i]; END;
		IF (obj.py1[i] < h1) THEN h1:= obj.py1[i]; END;
		IF (obj.px1[i] > w2) THEN w2:= obj.px1[i]; END;
		IF (obj.py1[i] > h2) THEN h2:= obj.py1[i]; END;
	END;
	obj.u:= w1; obj.v:= h1; obj.w:= w2 - w1; obj.h:= h2 - h1;
END MoveMass;

PROCEDURE IntersectMass(obj1,obj2: Mass; VAR x,y: INTEGER): BOOLEAN;
	(* calculate intersection of two objects *)
VAR
	i,j: INTEGER;

	PROCEDURE In(v,min,max: INTEGER): BOOLEAN;
	BEGIN
		RETURN((v >= min) & (v <= max));
	END In;

	PROCEDURE InBound(i,j: Mass): BOOLEAN;
	(* intersect the hulls *)
	BEGIN
		RETURN((In(i.u,j.u,j.u+j.w) OR In(i.u+i.w,j.u,j.u+j.w)) & (In(i.v,j.v,j.v+j.h) OR In(i.v+i.h,j.v,j.v+j.h)));
	END InBound;

BEGIN
	(* if hulls don't intersect, skip line checking *)
	IF InBound(obj1,obj2) OR InBound(obj2,obj1) THEN
		(* just a speedup for small asteroids *)
			IF (obj1.shape = shAsteroid3) OR (obj2.shape = shAsteroid3) THEN
			RETURN(TRUE);
		END;
		FOR i:= 0 TO obj1.shape.n-2 DO
			FOR j:= 0 TO obj2.shape.n-2 DO
				IF Intersect(obj1.px1[i],obj1.py1[i],obj1.px1[i+1],obj1.py1[i+1],
								   obj2.px1[j],obj2.py1[j],obj2.px1[j+1],obj2.py1[j+1],x,y) THEN
					RETURN(TRUE);
				END;
			END;
		END;
	END;
	RETURN(FALSE);
END IntersectMass;

PROCEDURE SFire(F: Field; ship: Ship);
	(* fire a ship's bullet - if possible *)
VAR
	bullet: SBullet;
BEGIN
	IF (ship.bullets < SBulletMax) THEN
		NEW(bullet); InitSBullet(bullet,ship); INC(ship.bullets);
		bullet.next:= F.objects; F.objects:= bullet;
		Score(F,-SBulletCost);
	END;
END SFire;

PROCEDURE SShield(F: Field; ship: Ship);
	(* activate ship's shield - if possible *)
BEGIN
	IF (ship.shieldval > 0) THEN
		ship.shield:= SShieldGrant; DEC(ship.shieldval); F.changed:= TRUE;
	END;
END SShield;

PROCEDURE SWarp(F: Field; ship: Ship);
	(* warp to another position - if possible *)
BEGIN
	IF (ship.warpval > 0) THEN
		DEC(ship.warpval);
		ship.x:= RandomNumbers.Uniform() * Display.Width;
		ship.y:= RandomNumbers.Uniform() * Display.Height;
		ship.xvel:= 0.0; ship.yvel:= 0.0; ship.rot:= 0.0; ship.rotvel:= 0.0;
 		F.changed:= TRUE;
	END;
END SWarp;

PROCEDURE EFire(F: Field; ufo: Enemy);
	(* fire an ufo's bullet - if possible *)
VAR
	bullet: EBullet;
BEGIN
	IF (ufo.bullets < EBulletMax) THEN
		NEW(bullet); InitEBullet(bullet,ufo,F.ship); INC(ufo.bullets);
		bullet.next:= F.objects; F.objects:= bullet;
	END;
END EFire;

PROCEDURE Hit(F: Field; x,y: REAL);
	(* produce a nice detonation *)
VAR
	det: Detonation;
BEGIN
	NEW(det); InitSpaceObj(det); det.x:= x; det.y:= y; det.r0:= 0; det.r:= 0;
	det.next:= F.objects; F.objects:= det;
END Hit;

PROCEDURE HitShip(F: Field; obj: Ship);
	(* maybe, you're gone. draw detonation and update status *)
BEGIN
	IF (obj.shield = 0) & ~Indestructable THEN
		Hit(F,obj.px1[0],obj.py1[0]); obj.alive:= FALSE;
		DEC(F.ships); F.changed:= TRUE;
	END;
END HitShip;

PROCEDURE SplitAsteroid(F: Field; obj: Asteroid; x,y: INTEGER): INTEGER;
	(* split asteroid into pieces (ast1->ast2*SplitAsts->ast3*SplitAsts->none *)
VAR
	ast: Asteroid;
	shp: Shape;
	size,i: INTEGER;
BEGIN
	IF (obj.shape = shAsteroid1) THEN	(* Big Asteroid *)
		size:= 1; shp:= shAsteroid2;
	ELSIF (obj.shape = shAsteroid2) THEN	(* Medium Asteroid *)
		size:= 2; shp:= shAsteroid3;
	ELSE													(* Small Asteroid *)
		size:= 3; obj.alive:= FALSE;
	END;
	IF obj.alive THEN
		FOR i:= 1 TO SplitAsts DO
			NEW(ast); InitAsteroid(ast,obj,shp,x,y);
			ast.next:= F.objects; F.objects:= ast;
		END;
	END;
	RETURN(size);
END SplitAsteroid;

PROCEDURE NewShip(F: Field; x,y: REAL);
	(* initialize a new ship and place it somewhere into the field *)
BEGIN
	IF (F.ships > 0) THEN
		IF (F.ships = StartShips) THEN
			NEW(F.ship); F.ship.px2:= NIL; F.ship.py2:= NIL;
		END;
		InitShip(F.ship,x,y);	(* new ships are always static *)
		F.ship.next:= F.objects; F.objects:= F.ship; F.changed:= TRUE;
	END;
END NewShip;

PROCEDURE NewEnemy(F: Field);
	(* initialize a new ufo and place it somewhere into the field *)
VAR
	obj: Enemy;
BEGIN
	NEW(obj); InitEnemy(obj); INC(F.ufos);	(* ufo's are moving *)
	obj.next:= F.objects; F.objects:= obj;
END NewEnemy;

PROCEDURE NewRound(F: Field; amt: INTEGER);
	(* produce new, big asteroids and place them, amount depends on level *)
VAR
	ast: Asteroid;
	i: INTEGER;
BEGIN
	FOR i:= 1 TO amt DO
		NEW(ast); InitAsteroid(ast,NIL,shAsteroid1,1,1);
		ast.next:= F.objects; F.objects:= ast;
	END;
END NewRound;

PROCEDURE MoveShip(F: Field; obj: Ship);
	(* calculate new position of ships' vertices using velocities and thrust *)
VAR
	tgt: SpaceObj;
	hit: BOOLEAN;
	x,y: INTEGER;
	swpV: Vertices;
	swpS: Shape;
BEGIN
	IF (obj.thrust0 # obj.thrust) THEN	(* change shapes if or not thrusting *)
		swpV:= obj.px1; obj.px1:= obj.px2; obj.px2:= swpV;
		swpV:= obj.py1; obj.py1:= obj.py2; obj.py2:= swpV;
		swpS:= obj.shape; obj.shape:= obj.shape0; obj.shape0:= swpS;
	END;
	IF obj.thrust THEN
		obj.xvel:= obj.xvel + ShipThrust * ((obj.px1[3] - obj.px1[0]) / 20);
		obj.yvel:= obj.yvel + ShipThrust * ((obj.py1[3] - obj.py1[0]) / 20);
	END;
	MoveMass(obj); obj.rotvel:= 0.0;
	tgt:= F.objects; hit:= FALSE;
	WHILE ~hit & (tgt # NIL) DO	(* check, if ship is hitten *)
		IF (tgt IS Asteroid) OR (tgt IS Enemy) THEN
			WITH tgt: Mass DO hit:= IntersectMass(obj,tgt,x,y); END;
		END;
		IF ~hit THEN tgt:= tgt.next; END;
	END;
	IF hit THEN
		HitShip(F,obj);
		WITH	(* produce a post mortal animation *)
		  	tgt: Asteroid DO
					Hit(F,tgt.px1[0],tgt.py1[0]); x:= SplitAsteroid(F,tgt,x,y);
		|	tgt: Enemy DO
					Hit(F,tgt.px1[0],tgt.py1[0]); x:= 0;
		END;
		Score(F,hitscore[x]); tgt.alive:= FALSE;	(* kamikaze salairy *)
	END;
END MoveShip;

PROCEDURE MoveEnemy(F: Field; obj: Enemy);
	(* calculate new position of ships' vertices using velocities *)
VAR
	tgt: SpaceObj;
	hit: BOOLEAN;
	x,y: INTEGER;
BEGIN
	MoveMass(obj);
	tgt:= F.objects; hit:= FALSE;
	WHILE ~hit & (tgt # NIL) DO	(* check, if ufo is hitten *)
		IF (tgt IS Asteroid) OR (tgt IS Ship) THEN
			WITH tgt: Mass DO hit:= IntersectMass(obj,tgt,x,y); END;
		END;
		IF ~hit THEN tgt:= tgt.next; END;
	END;
	IF hit THEN
		IF (tgt IS Asteroid) THEN
			WITH tgt: Asteroid DO
				Hit(F,tgt.px1[0],tgt.py1[0]); x:= SplitAsteroid(F,tgt,x,y);
				tgt.alive:= FALSE;
			END;
		ELSE
			WITH tgt: Ship DO HitShip(F,tgt); END;
		END;
		Hit(F,obj.px1[0],obj.py1[0]); obj.alive:= FALSE;
	END;
END MoveEnemy;

PROCEDURE MoveSBullet(F: Field; obj: SBullet);
	(* calculate new position of ships' bullet using velocities *)
VAR
	tgt: SpaceObj;
	hit: BOOLEAN;
	x,y: INTEGER;
BEGIN
	MoveMass(obj);
	tgt:= F.objects; hit:= FALSE;
	WHILE ~hit & (tgt # NIL) DO	(* check, if shot wasn't in vain *)
		IF ~(tgt IS SBullet) & (tgt IS Mass) THEN
			WITH tgt: Mass DO hit:= IntersectMass(obj,tgt,x,y); END;
		END;
		IF ~hit THEN tgt:= tgt.next; END;
	END;
	IF hit THEN
		obj.time:= 0;
		IF (tgt IS Ship) THEN	(* self destruction is not fair! *)
		ELSIF (tgt IS Enemy) THEN
			Hit(F,x,y); tgt.alive:= FALSE; DEC(F.ufos); Score(F,hitscore[0]);
		ELSIF (tgt IS Asteroid) THEN
			WITH tgt: Asteroid DO
				Hit(F,tgt.px1[0],tgt.py1[0]); x:= SplitAsteroid(F,tgt,x,y);
				Score(F,hitscore[x]);
			END;
			tgt.alive:= FALSE;
		END;
	END;
	DEC(obj.time);
	IF (obj.time < 0) THEN DEC(obj.ship.bullets); obj.alive:= FALSE; END;
END MoveSBullet;

PROCEDURE MoveEBullet(F: Field; obj: EBullet);
	(* calculate new position of ufos' bullet using velocities *)
VAR
	tgt: SpaceObj;
	hit: BOOLEAN;
	x,y: INTEGER;
BEGIN
	MoveMass(obj);
	tgt:= F.objects; hit:= FALSE;
	WHILE ~hit & (tgt # NIL) DO	(* check ufo's shot *)
		IF ~(tgt IS EBullet) & (tgt IS Mass) THEN
			WITH tgt: Mass DO hit:= IntersectMass(obj,tgt,x,y); END;
		END;
		IF ~hit THEN tgt:= tgt.next; END;
	END;
	IF hit & ~(tgt IS Enemy) THEN
		obj.time:= 0;
		IF (tgt IS Ship) THEN	(* gotcha! *)
			WITH tgt: Ship DO HitShip(F,tgt); END;
		ELSIF (tgt IS Asteroid) THEN
			WITH tgt: Asteroid DO
				Hit(F,tgt.px1[0],tgt.py1[0]); x:= SplitAsteroid(F,tgt,x,y);
			END;
			tgt.alive:= FALSE;
		END;
	END;
	DEC(obj.time);
	IF (obj.time < 0) THEN DEC(obj.ship.bullets); obj.alive:= FALSE; END;
END MoveEBullet;

PROCEDURE UpdateShip(obj: Ship);
	(* update ship values after redraw *)
BEGIN
	obj.shield0:= obj.shield; IF (obj.shield > 0) THEN DEC(obj.shield); END;
	obj.thrust0:= obj.thrust; obj.thrust:= FALSE;
END UpdateShip;

PROCEDURE UpdateStatus(obj: Field);
	(* update score line values after redraw *)
BEGIN
	IF obj.changed THEN COPY(obj.line,obj.line0); END;
	obj.changed:= FALSE;
END UpdateStatus;

PROCEDURE Step1(F: Field; obj: SpaceObj);
	(* first step of animation - keep old vertices and calculate new ones *)
VAR
	swp: Vertices;
BEGIN
	IF (obj IS Detonation) THEN	(* special behavior of detonations *)
		WITH obj: Detonation DO
			obj.r0:= obj.r;
			IF obj.alive THEN
				INC(obj.r,DetonationStep); obj.alive:= (obj.r <= DetonationMax);
			END;
		END;
	ELSIF (obj IS Mass) THEN	(* keep old shape for object removal *)
		WITH obj: Mass DO
			swp:= obj.px0; obj.px0:= obj.px1; obj.px1:= swp;
			swp:= obj.py0; obj.py0:= obj.py1; obj.py1:= swp;
			obj.n0:= obj.shape.n;
			IF obj.alive THEN
				WITH	(* various move algorithms *)
				  	obj: Ship DO MoveShip(F,obj);
				|	obj: SBullet DO MoveSBullet(F,obj);
				|	obj: Enemy DO MoveEnemy(F,obj);
				|	obj: EBullet DO MoveEBullet(F,obj);
				|	obj: Mass DO MoveMass(obj);
				END;
			END;
		END;
	END;
END Step1;

PROCEDURE Step2(F: Field; obj: SpaceObj; VAR obj0: SpaceObj): BOOLEAN;
	(* second step of animation *)
VAR
	b: BOOLEAN;
BEGIN
	b:= FALSE;
	IF ~obj.alive THEN	(* remove "dead" objects *)
		IF (obj0 = NIL) THEN F.objects:= obj.next; ELSE obj0.next:= obj.next; END;
	ELSE
		IF (obj IS Ship) THEN	(* update ship's values after draw *)
			WITH obj: Ship DO UpdateShip(obj); END;
		ELSE
			b:= TRUE;
		END;
		obj0:= obj;
	END;
	RETURN(b);
END Step2;

PROCEDURE TimerHandler(me: Oberon.Task);
	(* tick task handler *)
VAR
	time: LONGINT;
	model: Field;
	amt: INTEGER;
	r1: REAL;
	obj0,obj: SpaceObj;
BEGIN
	WITH me: Timer DO
		model:= me.model;
		IF ~model.paused THEN
			time:= Oberon.Time();	(* slow down animation *)
			IF (me.trigger <= time) THEN
				obj:= model.objects;
				WHILE (obj # NIL) DO Step1(model,obj); obj:= obj.next; END;
				Gadgets.Update(model);
				obj0:= NIL; obj:= model.objects;
				WHILE (obj # NIL) DO
					IF Step2(model,obj,obj0) THEN INC(amt); END;
					obj:= obj.next;
				END;
				IF (amt = 0) THEN
					INC(model.frames);
					NewRound(model,model.frames+StartAsts);
				ELSIF (model.ship # NIL) & model.ship.alive & (model.ufos <= model.frames) THEN
					r1:= RandomNumbers.Uniform();	(* create a new ufo *)
					IF (r1 < (model.frames+1)/EAppear) THEN NewEnemy(model); END;
				END;
				UpdateStatus(model);
				amt:= BaseDelay - amt; IF (amt < 0) THEN amt:= 0; END;
				me.trigger:= Oberon.Time() + amt;
			END;
		END;
	END;
END TimerHandler;

PROCEDURE StopTimers();
	(* remove all tick tasks - a term handler *)
BEGIN
	WHILE (timer # NIL) DO Oberon.Remove(timer); timer:= timer.tnext; END;
END StopTimers;

(*** Field Handler ***)

PROCEDURE FieldAttr(F: Field; VAR M: AttrMsg);
BEGIN
	M.res:= -1;
	IF (M.id = Objects.get) THEN
		IF (M.name = "Gen") THEN
			M.class:= Objects.String; M.res:= 0; M.s:= "Asteroids.NewField";
		END;
	ELSIF (M.id = Objects.enum) THEN
	END;
	IF (M.res = -1) THEN Gadgets.objecthandle(F,M); END;
END FieldAttr;

PROCEDURE FieldFile(F: Field; VAR M: FileMsg);
VAR
	obj0,obj: SpaceObj;
	rpos: INTEGER;
	id: Objects.Name;
	as: Asteroid;
	eb: EBullet;
	sb: SBullet;
	sh: Ship;
	en: Enemy;
	de: Detonation;

	PROCEDURE Connect(VAR root,obj: SpaceObj; new: SpaceObj);
		(* get the pointer by stepping thru' *)
	BEGIN
		IF (obj = NIL) THEN root:= new; ELSE obj.next:= new; END;
		new.next:= NIL; obj:= new;
	END Connect;

BEGIN
	IF (M.id = Objects.store) THEN
		obj:= F.objects; rpos:= 0;
		WHILE (obj # NIL) & (obj # F.ship) DO INC(rpos); obj:= obj.next; END;
		Files.WriteInt(M.R,rpos);
		Files.WriteBool(M.R,F.started); Files.WriteBool(M.R,F.paused);
		Files.WriteInt(M.R,F.ships); Files.WriteInt(M.R,F.ufos);
		Files.WriteInt(M.R,F.frames); Files.WriteLInt(M.R,F.score);
		Files.WriteLInt(M.R,F.high0); Files.WriteLInt(M.R,F.high);
		Files.WriteString(M.R,F.line0); Files.WriteString(M.R,F.line);
		obj:= F.objects;
		WHILE (obj # NIL) DO
			Tag(obj,id); Files.WriteString(M.R,id);
			IF (id = "Asteroid") THEN
				WITH obj: Asteroid DO FileAsteroid(M.R,M.id,obj,F.objects); END;
			ELSIF (id = "EBullet") THEN
				WITH obj: EBullet DO FileEBullet(M.R,M.id,obj,F.objects); END;
			ELSIF (id = "SBullet") THEN
				WITH obj: SBullet DO FileSBullet(M.R,M.id,obj,F.objects); END;
			ELSIF (id = "Enemy") THEN
				WITH obj: Enemy DO FileEnemy(M.R,M.id,obj,F.objects); END;
			ELSIF (id = "Ship") THEN
				WITH obj: Ship DO FileShip(M.R,M.id,obj,F.objects); END;
			ELSIF (id = "Detonation") THEN
				WITH obj: Detonation DO FileDetonation(M.R,M.id,obj,F.objects); END;
			END;
			obj:= obj.next;
		END;
		Files.WriteString(M.R,"$");
	ELSIF (M.id = Objects.load) THEN
		Files.ReadInt(M.R,rpos);
		Files.ReadBool(M.R,F.started); Files.ReadBool(M.R,F.paused);
		Files.ReadInt(M.R,F.ships); Files.ReadInt(M.R,F.ufos);
		Files.ReadInt(M.R,F.frames); Files.ReadLInt(M.R,F.score);
		Files.ReadLInt(M.R,F.high0); Files.ReadLInt(M.R,F.high);
		Files.ReadString(M.R,F.line0); Files.ReadString(M.R,F.line);
		F.objects:= NIL; obj:= NIL;
		REPEAT
			Files.ReadString(M.R,id);
			IF (id = "Asteroid") THEN
				NEW(as); FileAsteroid(M.R,M.id,as,NIL); Connect(F.objects,obj,as);
			ELSIF (id = "EBullet") THEN
				NEW(eb); FileEBullet(M.R,M.id,eb,NIL); Connect(F.objects,obj,eb);
			ELSIF (id = "SBullet") THEN
				NEW(sb); FileSBullet(M.R,M.id,sb,NIL); Connect(F.objects,obj,sb);
			ELSIF (id = "Enemy") THEN
				NEW(en); FileEnemy(M.R,M.id,en,NIL); Connect(F.objects,obj,en);
			ELSIF (id = "Ship") THEN
				NEW(sh); FileShip(M.R,M.id,sh,NIL); Connect(F.objects,obj,sh);
			ELSIF (id = "Detonation") THEN
				NEW(de); FileDetonation(M.R,M.id,de,NIL); Connect(F.objects,obj,de);
			END;
		UNTIL (id = "$");
		obj:= F.objects;
		WHILE (obj # NIL) DO
			IF (obj IS Bullet) THEN
				WITH obj: Bullet DO
					obj0:= F.objects;
					WHILE (obj.rpos > 0) DO obj0:= obj0.next; DEC(obj.rpos); END;
					WITH obj0: FlyingObj DO obj.ship:= obj0; END;
				END;
			ELSIF (obj IS Ship) & (rpos = 0) THEN
				WITH obj: Ship DO F.ship:= obj; END;
			END;
			obj:= obj.next; DEC(rpos);
		END;
	END;
	Gadgets.objecthandle(F,M);
END FieldFile;

PROCEDURE FieldHandler*(F: Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH F: Field DO
		WITH
		  	M: AttrMsg DO FieldAttr(F,M);
		|	M: CopyMsg DO M.obj:= F;
		|	M: FileMsg DO FieldFile(F,M); 
		ELSE
			Gadgets.objecthandle(F,M);
		END;
	END;
END FieldHandler;

(*** Starfield Handler ***)

PROCEDURE StarfieldAttr(F: Starfield; VAR M: AttrMsg);
BEGIN
	M.res:= -1;
	IF (M.id = Objects.get) THEN
		IF (M.name = "Gen") THEN
			M.class:= Objects.String; M.res:= 0; M.s:= "Asteroids.NewStarfield";
		END;
	END;
	IF (M.res = -1) THEN Panels.PanelHandler(F,M); END;
END StarfieldAttr;

PROCEDURE StarfieldCopy(F: Starfield; VAR M: CopyMsg);
VAR
	obj: Object;
BEGIN
	IF (M.stamp = F.stamp) THEN
		M.obj:= F.dlink;
	ELSE
		obj:= Gadgets.CreateObject("Asteroids.NewStarfield");
		F.stamp:= M.stamp; F.dlink:= obj; M.obj:= obj;
		WITH obj: Starfield DO Panels.CopyPanel(M,F,obj); END;
	END;
END StarfieldCopy;

PROCEDURE StarfieldDisplay(F: Starfield; VAR M: DisplayMsg);
VAR
	model: Field;
	obj: SpaceObj;
	mx,my,v: INTEGER;
	mask: Display3.Mask;	(* needed for MakeMask *)
BEGIN
	Panels.PanelHandler(F,M);
	mx:= M.x + F.X; my:= M.y + F.Y;
	Gadgets.MakeMask(F,mx,my,M.dlink,mask);
	IF (M.id = Display.area) THEN
		Display3.AdjustMask(F.mask,mx+M.u,my+F.H-1+M.v,M.w,M.h);
	END;
	model:= Model(F);
	obj:= model.objects;
	WHILE (obj # NIL) DO
		IF (obj IS Detonation) THEN
			WITH obj: Detonation DO v:= DrawDetonation(F,obj,M.x,M.y); END;
		ELSIF (obj IS Ship) THEN
			WITH obj: Ship DO v:= DrawShip(F,obj,M.x,M.y); END;
		ELSIF (obj IS Mass) THEN
			WITH obj: Mass DO v:= DrawMass(F,obj,M.x,M.y); END;
		END;
		obj:= obj.next;
	END;
	RestoreStatus(F,model,M.x,M.y);
END StarfieldDisplay;

PROCEDURE StarfieldFile(F: Starfield; VAR M: FileMsg);
BEGIN
	IF (M.id = Objects.store) THEN
		Files.WriteReal(M.R,F.scaleX); Files.WriteReal(M.R,F.scaleY);
	ELSIF (M.id = Objects.load) THEN
		Files.ReadReal(M.R,F.scaleX); Files.ReadReal(M.R,F.scaleY);
	END;
	Panels.PanelHandler(F,M);
END StarfieldFile;

PROCEDURE StarfieldInput(F: Starfield; VAR M: InputMsg);
VAR
	model: Field;
	keysum: SET;
BEGIN
	model:= Model(F); M.res:= -1;
	IF (M.id = Oberon.consume) & (model.ship # NIL) & model.ship.alive THEN
		CASE M.ch OF
		| ChTurnLeft: model.ship.rotvel:= -ShipRotvel; M.res:= 0;
		| ChTurnRight: model.ship.rotvel:= ShipRotvel; M.res:= 0;
		| ChThrust: model.ship.thrust:= TRUE; M.res:= 0;
		| ChFire: SFire(model,model.ship); M.res:= 0;
		| ChShield: SShield(model,model.ship); M.res:= 0;
		| ChWarp: SWarp(model,model.ship); M.res:= 0;
		ELSE
			Panels.PanelHandler(F,M);
		END;
	ELSIF ~model.paused & ((model.ship = NIL) OR ~model.ship.alive & (model.ships > 0)) THEN
		IF (M.id = Oberon.track) & Gadgets.InActiveArea(F,M) & (M.keys = {2}) THEN
			REPEAT
				Effects.TrackMouse(M.keys,M.X,M.Y,Oberon.Star);
				keysum:= keysum + M.keys;
			UNTIL M.keys = {};
			NewShip(model,(M.X-M.x-F.X) / F.scaleX,(M.Y-M.y-F.Y) / F.scaleY);
			model.started:= TRUE;
			M.res:= 0;
		ELSE
			Oberon.DrawCursor(Oberon.Mouse,Oberon.Star,M.X,M.Y); M.res:= 0;
		END;
	ELSE
		Panels.PanelHandler(F,M);
	END;
END StarfieldInput;

PROCEDURE StarfieldModify(F: Starfield; VAR M: ModifyMsg);
VAR
	model: Field;
	len: LONGINT;
BEGIN
	IF (M.F = F) THEN
		F.scaleX:= M.W / Display.Width; F.scaleY:= M.H / Display.Height;
		model:= Model(F); len:= Strings.Length(model.line) + 4; F.fdx:= 6;
		WHILE (F.fdx > 0) & (M.W < (len * fw[F.fdx])) DO DEC(F.fdx); END;
	END;
	Panels.PanelHandler(F,M);
END StarfieldModify;

PROCEDURE StarfieldUpdate(F: Starfield; VAR M: UpdateMsg);
VAR
	model: Field;
	obj: SpaceObj;
	sv: INTEGER;
	ovlap: BOOLEAN;
	mask: Display3.Mask;	(* needed for MakeMask *)
BEGIN
	Panels.PanelHandler(F,M);
	IF (F.obj # NIL) & (M.obj = F.obj) THEN
		Gadgets.MakeMask(F,F.X+M.x,F.Y+M.y,M.dlink,mask);
		model:= Model(F);
		ovlap:= FALSE; obj:= model.objects;
		WHILE (obj # NIL) DO
			IF (obj IS Detonation) THEN
				WITH obj: Detonation DO sv:= DrawDetonation(F,obj,M.x,M.y); END;
			ELSIF (obj IS Ship) THEN
				WITH obj: Ship DO sv:= DrawShip(F,obj,M.x,M.y); END;
			ELSIF (obj IS Mass) THEN
				WITH obj: Mass DO sv:= DrawMass(F,obj,M.x,M.y); END;
			END;
			IF obj IS Enemy THEN WITH obj: Enemy DO EFire(model,obj); END; END;
			ovlap:= ovlap OR (sv <= 5+fh[F.fdx]);
			obj:= obj.next;
		END;
		IF (Gadgets.selected IN F.state) THEN
			Display3.FillPattern(F.mask,Display3.white,Display3.selectpat,M.x+F.X,M.y+F.Y,M.x+F.X,M.y+F.Y,F.W,F.H,Display3.paint);
		END;
		IF model.changed THEN
			ModifyStatus(F,model,M.x,M.y);
		ELSIF ovlap THEN
			RestoreStatus(F,model,M.x,M.y);
		END;
	END;
END StarfieldUpdate;

PROCEDURE StarfieldHandler*(F: Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH F: Starfield DO
		WITH
		  	M: CopyMsg DO StarfieldCopy(F,M);
		|	M: AttrMsg DO StarfieldAttr(F,M);
		|	M: DisplayMsg DO StarfieldDisplay(F,M);
		|	M: FileMsg DO StarfieldFile(F,M);
		|	M: InputMsg DO StarfieldInput(F,M);
		|	M: ModifyMsg DO StarfieldModify(F,M);
		|	M: UpdateMsg DO StarfieldUpdate(F,M);
		ELSE
			Panels.PanelHandler(F,M);
		END;
	END;
END StarfieldHandler;

(*** Document Handler ***)

PROCEDURE DocAttr(D: Document; VAR M: AttrMsg);
BEGIN
	M.res:= -1;
	IF (M.id = Objects.get) THEN
		IF (M.name = "Gen") THEN
			M.class:= Objects.String; M.res:= 0; M.s:= "Asteroids.NewDoc";
		ELSIF (M.name = "Adaptive") THEN
			M.class:= Objects.Bool; M.res:= 0; M.b:= TRUE;
		ELSIF (M.name = "Icon") THEN
			M.class:= Objects.String; M.res:= 0; M.s:= DocIcon;
		END;
	END;
	IF (M.res = -1) THEN Documents.Handler(D,M); END;
END DocAttr;

PROCEDURE DocLink(D: Document; VAR M: LinkMsg);
VAR
	model: Field;
BEGIN
	IF (M.id = Objects.get) & ((M.name = "DeskMenu") OR (M.name = "SystemMenu") OR (M.name = "UserMenu")) THEN
		model:= Model(D.dsc);
		IF ~model.paused THEN M.obj:= Desktops.NewMenu(DocMenu1); ELSE M.obj:= Desktops.NewMenu(DocMenu2); END;
		M.res:= 0;
	ELSE
		Documents.Handler(D,M);
	END;
END DocLink;

PROCEDURE DocMenu(D: Document; VAR M: MenuMsg);
VAR
	f,menu: Display.Frame;
	capt: ARRAY 64 OF CHAR;
BEGIN
	IF (M.frame = D.dsc) THEN
		menu := Desktops.CurMenu(M.dlink);
		IF (menu # NIL) THEN
			f:= menu.dsc;
			WHILE (f # NIL) DO
				Attributes.GetString(f,"Caption",capt);
				IF (capt = "Pause") OR (capt = "Cont") THEN
					IF M.paused THEN
						Attributes.SetString(f,"Caption","Cont");
						Attributes.SetString(f,"Cmd","Asteroids.ResumeGame");
						Gadgets.Update(f);
					ELSE
						Attributes.SetString(f,"Caption","Pause");
						Attributes.SetString(f,"Cmd","Asteroids.PauseGame");
						Gadgets.Update(f);
					END;
				END;
				f:= f.next
			END;
		END;
	END;
END DocMenu;

PROCEDURE DocHandler*(D: Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH D: Document DO
		IF M IS AttrMsg THEN
			WITH M: AttrMsg DO DocAttr(D,M); END;
		ELSIF M IS LinkMsg THEN
			WITH M: LinkMsg DO DocLink(D,M); END;
		ELSIF M IS MenuMsg THEN
			WITH M: MenuMsg DO DocMenu(D,M); END;
		ELSE
			Documents.Handler(D,M);
		END;
	END;
END DocHandler;

(*** Document Creation ***)

PROCEDURE OldDocument(F: Files.File; D: Document; VAR f: Gadgets.Frame);
	(* Restore an old Asteroids document from file *)
VAR
	obj: Objects.Object;
	tag: INTEGER;
	len: LONGINT;
	id: CHAR;
	str: Objects.Name;
	lib: Objects.Library;
	R: Files.Rider;
BEGIN
	Files.Set(R,F,0); Files.ReadInt(R,tag);
	IF (tag = Documents.Id) THEN
		Files.ReadString(R,str);								(* Skip over Generator *)
		Files.ReadString(R,str);								(* Document Version *)
		Files.ReadInt(R,D.X); Files.ReadInt(R,D.Y);
		Files.ReadInt(R,D.W); Files.ReadInt(R,D.H);
		Files.Read(R,id);
		IF (str # Version) & (str # CompVers) THEN   (* Check Program Version *)
			Out.String("Unmatching "); Out.String(str); Out.Ln();
		ELSIF (id = Objects.LibBlockId) THEN		  (* Check for correct id *)
			NEW(lib); Objects.OpenLibrary(lib);
			Objects.LoadLibrary(lib,F,Files.Pos(R),len);
			lib.GetObj(lib,0,obj);
			IF (obj # NIL) THEN
				IF obj IS Objects.Dummy THEN
					WITH obj: Objects.Dummy DO
						Out.String("Discarding "); Out.String(obj.GName); Out.Ln();
					END;
				ELSIF obj IS Panels.Panel THEN
					WITH obj: Gadgets.Frame DO
						obj.handle:= StarfieldHandler; f:= obj;
					END;
				END;
			END;
		END;
	END;
END OldDocument;

PROCEDURE NewDocument(D: Document; VAR f: Gadgets.Frame);
	(* Create a new Asteroids Document *)
VAR
	frame: Display.Frame;
BEGIN
	frame:= Gadgets.CreateViewModel("Asteroids.NewStarfield","Asteroids.NewField");
	WITH frame: Gadgets.Frame DO f:= frame; END;
END NewDocument;

PROCEDURE LoadDocument(D: Document);
	(* Loading Method for Asteroids Documents *)
VAR
	F: Files.File;
	T: Timer;
	frame: Gadgets.Frame;
	model: Field;
BEGIN
	F:= NIL; frame:= NIL;
	IF (D.name = "") THEN D.name:= DefName; ELSE F:= Files.Old(D.name); END;
	IF (F # NIL) THEN
		OldDocument(F,D,frame); Files.Close(F);
	ELSE
		NewDocument(D,frame);
		model:= Model(frame);
		Oberon.Defocus();
	END;
	NEW(T); T.model:= Model(frame); T.trigger:= 0; T.tnext:= timer;
	T.handle:= TimerHandler; timer:= T; Oberon.Install(T);
	Documents.Init(D,frame);
END LoadDocument;

PROCEDURE StoreDocument(D: Document);
	(* Storing Method for Asteroids Documents *)
VAR
	F: Files.File;
	R: Files.Rider;
	B: Objects.BindMsg;
	str: Objects.Name;
	len: LONGINT;
BEGIN
	IF (D.name # "") & (D.dsc # NIL) THEN
		Out.String("Store ");
		NEW(B.lib); Objects.OpenLibrary(B.lib); D.dsc.handle(D.dsc,B);
		Attributes.GetString(D,"Gen",str);
		F:= Files.New(D.name); Files.Set(R,F,0);
		Files.WriteInt(R,Documents.Id);
		Files.WriteString(R,str); Files.WriteString(R,Version);
		Files.WriteInt(R,D.X); Files.WriteInt(R,D.Y);
		Files.WriteInt(R,D.W); Files.WriteInt(R,D.H);
		Objects.StoreLibrary(B.lib,F,Files.Pos(R),len);
		Files.Register(F); Files.Close(F);
		Out.Char(22X); Out.String(D.name); Out.Char(22X); Out.Ln();
	END;
END StoreDocument;

(*** Generators ***)

PROCEDURE NewField*;
VAR
	F: Field;
BEGIN
	NEW(F); InitField(F); COPY(F.line,F.line0); F.handle:= FieldHandler;
	Objects.NewObj:= F;
END NewField;

PROCEDURE NewStarfield*;
VAR
	F: Starfield;
BEGIN
	NEW(F); Panels.InitPanel(F); F.handle:= StarfieldHandler;
	F.col:= b; INCL(F.state0,Panels.flatlook);
	F.fdx:= 0; F.scaleX:= 1.0; F.scaleY:= 1.0; Objects.NewObj:= F;
END NewStarfield;

PROCEDURE NewDoc*;
VAR
	D: Document;
BEGIN
	NEW(D);
	D.Load:= LoadDocument; D.Store:= StoreDocument;
	D.W:= 292; D.H:= 292; D.handle:= DocHandler;
	Objects.NewObj:= D;
END NewDoc;

(*** Commands ***)

PROCEDURE NewGame*;
VAR
	D: Document;
	model: Field;
	obj: SpaceObj;
BEGIN
	D:= Desktops.CurDoc(Gadgets.context);
	IF (D # NIL) & (D.dsc IS Panels.Panel) THEN
		model:= Model(D.dsc);
		IF (model # NIL) THEN
			obj:= model.objects;
			WHILE (obj # NIL) DO
				obj.alive:= FALSE; Step1(model,obj); obj:= obj.next;
			END;
			Gadgets.Update(model);
			InitField(model); INC(model.frames); NewRound(model,StartAsts);
			Gadgets.Update(model);
		END;
	END;
END NewGame;

PROCEDURE PauseGame*;
VAR
	D: Document;
	M: MenuMsg;
	model: Field;
	i,j: LONGINT;
BEGIN
	D:= Desktops.CurDoc(Gadgets.context);
	IF (D # NIL) & (D.dsc IS Panels.Panel) THEN
		model:= Model(D.dsc);
		IF (model # NIL) THEN
			i:= Strings.Length(model.line); model.line:= "Game paused . . .";
			FOR j:= Strings.Length(model.line) TO i DO model.line[j]:= " "; END;
			model.line[j]:= 0X;
			model.paused:= TRUE; Gadgets.Update(model);
			M.frame:= D.dsc; M.paused:= TRUE; Display.Broadcast(M);
		END;
	END;
END PauseGame;

PROCEDURE ResumeGame*;
VAR
	D: Document;
	M: MenuMsg;
	model: Field;
BEGIN
	D:= Desktops.CurDoc(Gadgets.context);
	IF (D # NIL) & (D.dsc IS Panels.Panel) THEN
		model:= Model(D.dsc);
		IF (model # NIL) THEN
			ShowStatus(model,model.line);
			model.paused:= FALSE; Gadgets.Update(model);
			M.frame:= D.dsc; M.paused:= FALSE; Display.Broadcast(M);
		END;
	END;
END ResumeGame;

BEGIN
	(* What I wanted to say... *)
	Out.String("Asteroids "); Out.String(Version);
	Out.String(" by W. Ibl, "); Out.String(Date); Out.Ln();

	(* create object shapes *)
	Asteroid1Shape(shAsteroid1); Asteroid2Shape(shAsteroid2);
	Asteroid3Shape(shAsteroid3); EnemyShape(shEnemy);
	EBulletShape(shEBullet); ShipShape(shShip);
	ThrShipShape(shThrShip); SBulletShape(shSBullet);

	(* query font information *)
	FontGeometry("8",0); FontGeometry("10",1); FontGeometry("12",2);
	FontGeometry("14",3); FontGeometry("16",4); FontGeometry("20",5);
	FontGeometry("24",6);

	(* initialize score increments *)
	hitscore[0]:= HitScoreE1; hitscore[1]:= HitScoreA1; 
	hitscore[2]:= HitScoreA2; hitscore[3]:= HitScoreA3;

	b:= Display3.black; w:= Display3.white; timer:= NIL;

	Modules.InstallTermHandler(StopTimers);

END Asteroids.

Desktops.OpenDoc Asteroids.Doc (Asteroids.NewDoc)~
System.Free Asteroids~
System.DeleteFiles Asteroids.Doc~

Compiler.Compile *\2s
