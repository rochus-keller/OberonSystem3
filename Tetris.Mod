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

MODULE Tetris;	(** portable *)	(* by W. Ibl *)
(*
	Feb '95	V 1.0	first release
	Mar'95	V 1.1	removed bugs with copy message
	Apr '95	V 1.2	improved coordinate calculation
	May '95	V 1.3	added pause button
	July '95	V 2.0	updated to Oberon System3 2.0
	Aug '95	V 2.1	corrected keyboard focus handling
	Aug '95	V 2.2	simplified storing & version check
	Dec '95	V 2.3	speed and score error removed
	Jan '96	V 2.4	FileMsg warnings removed
	Mar '96	V 2.5	ported to Native Oberon
	July '96	V 2.6	improved Display Method
	Aug '96	V 2.7	Task removel revisited
	Feb '97	V 2.8	Paused when New corrected, TermHandler is now used
	Feb '97	V 3.0	updated to Oberon Rel. 2.2
*)
IMPORT Attributes,BasicGadgets,Desktops,Display,Display3,Documents, Effects,Files,Gadgets,In,Modules,Oberon,Objects,Out,
	Panels, RandomNumbers,TextFields;

CONST
	(* Program version *)
	Version = "V 3.0";
	Date = "February '96";

	(* last compatible Program version *)
	CompVers = "V 2.4";

	(* Standard Document strings *)
	DefName = "Tetris.Doc";
	DocMenu = "Desktops.StoreDoc[Store] Tetris.NewGame[New]";
	DocIcon = "Icons3.Tetris";

	(* Task Feedback *)
	LogRemoval = FALSE;

	(* Drawing: backgroundcolor and drawing mode *)
	replace = Display3.replace;
	paint = Display3.paint;

	Left = 2;
	Fudge = 3;

	(* Text: estimated size in pixels *)
	TextW = 6;
	TextH = 17;

	(* Button Width in Pixels *)
	ButtonW = 60;

	(* Game constants: amount figures, levels and ranking, delay, scores *)
	Figures = 7;
	Levels = 10;
	Ranks = 5;
	LapTime = 60000;
	LineBonus = 2;
	DropBonus = 5;
	FullBonus = 10;

	(* Textfield sizes *)
	NameW = 10;
	PointsW = 6;
	LevelW = 4;
	RowsW = 4;

	(* Animation constants and model dimensions *)
	PreviewScale = 10;
	FigLines = 4;
	FigRows = 4;
	ScrnLines = 20;
	ScrnRows = 10;
	PotLines = ScrnLines + FigLines;
	PotRows = ScrnRows + (2 * FigRows);

	(* Control: Turn, Drop, Left and Right *)
	UpArrow = 0C1X;
	DownArrow = 0C2X;
	RightArrow = 0C3X;
	LeftArrow = 0C4X;
	KeyPrev = "V";
	Keyprev = "v";
	KeyPause = "P";
	Keypause = "p";
TYPE
	Object = Objects.Object;
	Document = Documents.Document;

	(* Message Shortcuts *)
	AttrMsg = Objects.AttrMsg;
	BindMsg = Objects.BindMsg;
	ConsumeMsg = Display.ConsumeMsg;
	ControlMsg = Oberon.ControlMsg;
	CopyMsg = Objects.CopyMsg;
	DisplayMsg = Display.DisplayMsg;
	FileMsg = Objects.FileMsg;
	InputMsg = Oberon.InputMsg;
	LinkMsg = Objects.LinkMsg;
	ModifyMsg = Display.ModifyMsg;
	UpdateMsg = Gadgets.UpdateMsg;

	(* Character representation of shapes and field *)
	Figure = ARRAY FigLines, FigRows+1 OF CHAR;
	Pot = ARRAY PotLines, PotRows+1 OF CHAR;

	(* Forward declaration of the game model *)
	Field = POINTER TO FieldDesc;

	(* Drop Impulse Generator *)
	Timer = POINTER TO TimerDesc;
	TimerDesc = RECORD(Oberon.TaskDesc)
		model: Field;
		trigger: LONGINT;
		nxt: Timer
	END;

	(* High Score Identifier *)
	Score = RECORD
		name: Objects.Name;
		points: LONGINT;
		level,rows: INTEGER;
	END;

	(* The game model *)
	FieldDesc = RECORD(Gadgets.ObjDesc)
		score: ARRAY Ranks OF Score;
		curr,next,angle,line,row,rank,mult: SHORTINT;
		delay,figures: INTEGER;
		focus,match,preview,paused: BOOLEAN;
		lap1,lap2: LONGINT;
		timer: Timer;
		pot: Pot;
	END;
	
	(* Score displaying (name, score, level, rows) *)
	ScoreField = POINTER TO ScoreFieldDesc;
	ScoreFieldDesc = RECORD(TextFields.TextFieldDesc)
		ndx,xofs: INTEGER;		(* needed for aligning *)
	END;

	(* Resizeable drawing area *)
	Frame = POINTER TO FrameDesc;
	FrameDesc = RECORD(Panels.PanelDesc)
		scale: INTEGER;
		blank: BOOLEAN;
	END;

	(* Message extension for Gadgets alignment *)
	AlignMsg = RECORD(Objects.ObjMsg)
		X,Y,W,H: INTEGER;
	END;

	(* Change Backdrop Message (if level increases) *)
	BackdropMsg = RECORD(Display.FrameMsg)
		model: Object;
		ndx: INTEGER;
	END;

	(* Figure Draw Message *)
	FigureMsg = RECORD(Display.FrameMsg)
		model: Object;
		id: INTEGER;	(* 0 create, 1 move, 2 drop, 3 whole pot *)
		ndx,angle0,line0,row0,angle1,line1,row1: SHORTINT;
	END;
VAR
	figure: ARRAY Figures, 4 OF Figure;
	color,xofs,yofs: ARRAY Figures OF SHORTINT;
	clrpot: Pot;
	timers: Timer;
	delay: ARRAY Levels OF INTEGER;
	backdrop: ARRAY Levels OF Objects.Name;
	fudge: LONGINT;

PROCEDURE OtherFrame(me: Object; VAR M: Objects.ObjMsg): BOOLEAN;
(* Determine, if an object is affected by a message *)
VAR
	b: BOOLEAN;
BEGIN
	b:= M IS Display.FrameMsg;
	IF b THEN
		WITH M: Display.FrameMsg DO b:= (M.F # NIL) & (M.F # me); END;
	END;
	RETURN(b);
END OtherFrame;

PROCEDURE RemoveTimer(T: Timer; verbose: BOOLEAN);
VAR
	t: Timer;
BEGIN
	IF (timers = T) THEN
		timers.nxt:= T.nxt
	ELSE
		t:= timers;
		WHILE (t.nxt # T) DO t:= t.nxt END;
		t.nxt:= T.nxt;
	END;
	Oberon.Remove(T);
	IF verbose & LogRemoval THEN
		Out.String("Tetris Task removed"); Out.Ln();
	END;
END RemoveTimer;

PROCEDURE NextFigure(F: Field);
(* calculate next figure, previewed figure becomes current *)
BEGIN
	IF (F.figures = 0) THEN
		RandomNumbers.InitSeed(Oberon.Time());
		F.curr:= SHORT(SHORT(ENTIER(RandomNumbers.Uniform()*Figures)));
	ELSE
		F.curr:= F.next;
	END;
	F.next:= SHORT(SHORT(ENTIER(RandomNumbers.Uniform()*Figures)));
	F.angle:= 0; F.line:= PotLines - 1; F.row:= (PotRows DIV 2) - 2;
	INC(F.figures);
END NextFigure;

PROCEDURE IncScore(F: Field; score,bonus: INTEGER);
(* Increment the score and resort the highscore list if neccessary *)
VAR
	sum: LONGINT;
	level,rows: INTEGER;
	rank: SHORTINT;
BEGIN
	rank:= F.rank;
	level:= F.score[rank].level; rows:= F.score[rank].rows;
	sum:= F.score[rank].points + (score*bonus*F.mult*(F.score[rank].level+1));
	WHILE (rank > 0) & (F.score[rank-1].points <= sum) DO
		F.score[rank]:= F.score[rank-1]; DEC(rank); DEC(F.rank);
	END;
	F.score[rank].name:= ""; F.score[rank].points:= sum;
	F.score[rank].level:= level; F.score[rank].rows:= rows;
	IF ~F.preview THEN F.mult:= 2; END;
END IncScore;

PROCEDURE IncRows(F: Field; rows: INTEGER);
(* Increment the amount of filled rows *)
BEGIN
	INC(F.score[F.rank].rows,rows);
	IncScore(F,rows,FullBonus);
END IncRows;

PROCEDURE IncLevel(F: Field);
(* Increment the current game level *)
VAR
	M: BackdropMsg;
BEGIN
	INC(F.score[F.rank].level);
	M.F:= NIL; M.model:= F; M.ndx:= F.score[F.rank].level;
	Display.Broadcast(M);
END IncLevel;

PROCEDURE ResetScore(VAR score: Score);
(* reset score record contents to initial values *)
BEGIN
	score.name:= ""; score.points:= 0; score.level:= 0; score.rows:= 0;
END ResetScore;

PROCEDURE UpdSelection(M: Display3.Mask; state: SET; x,y,w,h: INTEGER);
BEGIN
	IF (Gadgets.selected IN state) THEN
		Display3.FillPattern(M,Display3.white,Display3.selectpat,x,y,x,y,w,h,paint);
	END;
END UpdSelection;

PROCEDURE Model(D: Object): Field;
VAR
	obj,model: Object;
BEGIN
	obj:= Gadgets.FindObj(D,"Pot");			(* get the model-view object *)
	WITH obj: Frame DO model:= obj.obj; END;
	WITH model: Field DO RETURN(model); END;
END Model;

PROCEDURE PX(R: Frame; dX,row,offs: INTEGER): INTEGER;
(* Calculate the X-Position for figure drawing *)
BEGIN
	RETURN(R.X + dX + ((row+offs-FigRows) * R.scale));
END PX;

PROCEDURE PY(R: Frame; dY,line,offs: INTEGER): INTEGER;
(* Calculate the Y-Position for figure drawing *)
BEGIN
	RETURN(R.Y + dY + ((line-offs-FigLines) * R.scale));
END PY;

PROCEDURE DrawBlock(R: Frame; c,x,y: INTEGER);
(* Draw or remove one block *)
BEGIN
	IF (c = R.col) THEN
		Display3.ReplConst(R.mask,c,x,y,R.scale,R.scale,replace);
	ELSE
		Display3.FilledRect3D(R.mask,c,15,c,x,y,R.scale,R.scale,R.scale DIV 4,replace);
	END;
END DrawBlock;

PROCEDURE DrawLine(R: Frame; line: ARRAY OF CHAR; dX,dY,l: INTEGER);
(* Draw line l of the pot *)
VAR
	c,j: INTEGER;
BEGIN
	j:= 0;
	WHILE (j < ScrnRows) DO
		IF (line[j+FigRows] = "-") THEN
			c:= R.col;
		ELSE
			c:= color[ORD(line[j+FigRows])-1];
		END;
		DrawBlock(R,c,PX(R,dX,j,FigRows),PY(R,dY,l,0));
		INC(j);
	END;
END DrawLine;

PROCEDURE DrawFigure(R: Frame; fig: Figure; dX,dY,c,r,l: INTEGER);
(* Draw or remove figure fig. c is color, r row and l line *)
VAR
	i,j: SHORTINT;
BEGIN
	j:= 0;
	Oberon.RemoveMarks(R.mask.X,R.mask.Y,R.mask.W,R.mask.H);
	WHILE (j < FigRows) DO
		i:= 0;
		WHILE (i < FigLines) DO
			IF (fig[i,j] = "$") THEN DrawBlock(R,c,PX(R,dX,r,j),PY(R,dY,l,i)); END;
			INC(i);
		END;
		INC(j);
	END;
END DrawFigure;

PROCEDURE DrawDrop(R: Frame; fig: Figure; dX,dY,c,r,l: INTEGER);
(* Do not remove and redraw to avoid flickering at fast droppping *)
VAR
	i,j,k: SHORTINT;
BEGIN
	j:= 0; k:= FigLines - 1;
	Oberon.RemoveMarks(R.mask.X,R.mask.Y,R.mask.W,R.mask.H);
	WHILE (j < FigRows) DO
		i:= 0;
		WHILE (i < FigLines) DO
			IF (i-1 >= 0) THEN
				IF (fig[i,j] = "$") & (fig[i-1,j] # "$") THEN
					DrawBlock(R,R.col,PX(R,dX,r,j),PY(R,dY,l,i));
				ELSIF (fig[i,j] # "$") & (fig[i-1,j] = "$") THEN
					DrawBlock(R,c,PX(R,dX,r,j),PY(R,dY,l,i));
				END;
			ELSIF (fig[i,j] = "$") THEN
				DrawBlock(R,R.col,PX(R,dX,r,j),PY(R,dY,l,i));
			END;
			INC(i);
		END;
		IF (fig[k,j] = "$") THEN DrawBlock(R,c,PX(R,dX,r,j),PY(R,dY,l-1,k)); END;
		INC(j);
	END;
END DrawDrop;

PROCEDURE DrawPot(R: Frame; dX,dY: INTEGER; pot: Pot);
(* Draw the whole pot *)
VAR
	i: SHORTINT;
BEGIN
	i:= FigLines;
	Oberon.RemoveMarks(R.mask.X,R.mask.Y,R.mask.W,R.mask.H);
	WHILE (i < PotLines) DO DrawLine(R,pot[i],dX,dY,i); INC(i); END;
END DrawPot;

PROCEDURE DrawPreview(R: Frame; fig: Figure; xofs,yofs,c: INTEGER);
(* Draw or remove the figure in the preview panel *)
VAR
	i,j: SHORTINT;
	ox,oy: INTEGER;
BEGIN
	ox:= R.mask.X + 5;
	oy:= R.mask.Y + R.H - R.scale - 5;
	IF (xofs # 0) THEN ox:= ox + ((xofs * R.scale) DIV 2); END;
	IF (yofs # 0) THEN oy:= oy - ((yofs * R.scale) DIV 2); END;
	j:= 0;
	Oberon.RemoveMarks(R.mask.X,R.mask.Y,R.mask.W,R.mask.H);
	WHILE (j < FigRows) DO
		i:= 0;
		WHILE (i < FigLines) DO
			IF (fig[i,j] = "$") THEN
				DrawBlock(R,c,ox+(j*R.scale),oy-(i*R.scale));
			END;
			INC(i);
		END;
		INC(j);
	END;
END DrawPreview;

PROCEDURE MatchFigure(F: Field; fig: Figure; r,l: SHORTINT): BOOLEAN;
(* Check, if there is space in the pot to put figure fig at position r,l *)
VAR
	i,j: INTEGER;
	b: BOOLEAN;
BEGIN
	b:= FALSE; j:= 0;
	WHILE ~b & (j < FigRows) DO
		i:= 0;
		WHILE ~b & (i < FigLines) DO
			b:= (fig[i,j] = "$") & (F.pot[l-i,r+j] # "-");
			INC(i);
		END;
		INC(j);
	END;
	RETURN(~b);
END MatchFigure;

PROCEDURE SetFigure(F: Field; fig: Figure; r,l: SHORTINT; c: CHAR);
(* Place Figure fig into the pot at position r,l - color c *)
VAR
	i,j: INTEGER;
BEGIN
	i:= 0;
	WHILE (i < FigLines) DO
		j:= 0;
		WHILE (j < FigRows) DO
			IF (fig[i,j] = "$") THEN F.pot[l-i,r+j]:= c; END;
			INC(j);
		END;
		INC(i);
	END;
END SetFigure;

PROCEDURE FieldFigure(F: Field; set: BOOLEAN);
(* Set Model's current Figure *)
VAR
	c: CHAR;
BEGIN
	IF set THEN c:= CHR(F.curr+1); ELSE c:= "-"; END;
	SetFigure(F,figure[F.curr,F.angle],F.row,F.line,c);
END FieldFigure;

PROCEDURE InitPot(VAR pot: Pot);
(* Initialize a pot including frames (avoid overflows when checking) *)
VAR
	i,j: SHORTINT;
BEGIN
	i:= 0;
	WHILE (i < FigLines) DO
		j:= 0; WHILE (j < PotRows) DO pot[i,j]:= "$"; INC(j); END;
		pot[i,j]:= 0X;
		INC(i);
	END;
	WHILE (i < PotLines) DO
		j:= 0;
		WHILE (j < FigRows) DO
			pot[i,j]:= "$"; pot[i,j+ScrnRows+FigRows]:= "$";
			INC(j);
		END;
		pot[i,j+ScrnRows+FigRows]:= 0X;
		j:= 0; WHILE (j < ScrnRows) DO pot[i,j+FigRows]:= "-"; INC(j); END;
		INC(i);
	END;
END InitPot;

PROCEDURE CheckPot(VAR pot: Pot): INTEGER;
(* Search for filled lines in the pot, drop upper part if found *)
VAR
	i,j,k: SHORTINT;
	full: INTEGER;
	b: BOOLEAN;
BEGIN
	i:= FigLines; k:= PotLines; full:= 0;
	WHILE (i < k) DO
		b:= TRUE; j:= 0;
		WHILE b & (j < ScrnRows) DO b:= (pot[i,j+FigRows] # "-"); INC(j); END;
		IF b THEN
			j:= i + 1;
			WHILE (j < k) DO COPY(pot[j],pot[j-1]); INC(j); END;
			DEC(k); INC(full);
		ELSE
			INC(i);
		END;
	END;
	RETURN(full);
END CheckPot;
(*
PROCEDURE LogPot(pot: ARRAY OF ARRAY OF CHAR);
(* Print the pot content (for debugging purpose) *)
VAR
	i,j: INTEGER;
BEGIN
	i:= PotLines-1;
	WHILE (i >= 0) DO
		j:= 0;
		WHILE (j < PotRows) DO
			IF (pot[i,j] = "-") THEN
				Out.Char("-");
			ELSIF (pot[i,j] = "$") THEN
				Out.Char("$");
			ELSE
				Out.Char(CHR(ORD(pot[i,j])+ORD("0")-1));
			END;
			INC(j);
		END;
		Out.Ln();
		DEC(i);
	END;
END LogPot;
*)
PROCEDURE Move(F: Field; c: CHAR): BOOLEAN;
(* Handle figure reposition of figure when falling *)
VAR
	M: FigureMsg;
BEGIN
	M.row1:= MIN(SHORTINT); M.line1:= F.line;
	IF ~F.paused THEN
		CASE c OF
		| LeftArrow:     M.row1:= F.row - 1; M.angle1:= F.angle;
		| RightArrow:  M.row1:= F.row + 1; M.angle1:= F.angle;
		| DownArrow: M.row1:= F.row; M.angle1:= (F.angle+1) MOD 4;
		| UpArrow: 	 M.row1:= F.row; M.angle1:= (F.angle-1) MOD 4;
		| " ":				M.row1:= MAX(SHORTINT);
		ELSE END;
	END;
	IF (M.row1 = MAX(SHORTINT)) THEN
		IF (F.delay # -1) THEN IncScore(F,F.line,DropBonus); F.delay:= -1; END;
	ELSIF (M.row1 > MIN(SHORTINT)) THEN
		FieldFigure(F,FALSE);
		IF MatchFigure(F,figure[F.curr,M.angle1],M.row1,F.line) THEN
			M.F:= NIL; M.model:= F; M.id:= 1; M.ndx:= F.curr;
			M.angle0:= F.angle; M.row0:= F.row; M.line0:= F.line;
			Display.Broadcast(M);
			F.row:= M.row1; F.angle:= M.angle1;
		END;
		FieldFigure(F,TRUE);
	END;
	RETURN(M.row1 # MIN(SHORTINT));
END Move;

PROCEDURE Drop(F: Field);
(* Drop Figure by incrementing the line index *)
VAR
	full: INTEGER;
	lap: LONGINT;
	M: FigureMsg;
BEGIN
	M.F:= NIL; M.model:= F; M.id:= -1;
	FieldFigure(F,FALSE);
	F.match:= MatchFigure(F,figure[F.curr,F.angle],F.row,F.line-1);
	IF F.match THEN
		M.id:= 2; M.ndx:= F.curr;
		M.angle0:= F.angle; M.line0:= F.line; M.row0:= F.row;
		M.angle1:= F.angle; M.line1:= F.line-1; M.row1:= F.row;	
		DEC(F.line);
		FieldFigure(F,TRUE);
	ELSE									(* no space in pot, show next figure *)
		IncScore(F,1,LineBonus);
		FieldFigure(F,TRUE);
		full:= CheckPot(F.pot);
		IF (full > 0) THEN IncRows(F,full); M.id:= 3; END;
		NextFigure(F);
		F.match:= MatchFigure(F,figure[F.curr,F.angle],F.row,F.line);
		IF F.match THEN				(* game continues *)
			lap:= Oberon.Time(); F.delay:= 0;
			IF (F.score[F.rank].level < (Levels-1)) & (F.lap1+LapTime < lap) THEN
				IncLevel(F); F.lap1:= lap;
			END;
			INC(M.id); M.ndx:= F.curr;
			M.angle0:= F.angle; M.line0:= F.line; M.row0:= F.row;
			FieldFigure(F,TRUE);
		ELSE
			F.next:= F.curr;	(* support Preview Handler *)
		END;
		Gadgets.Update(F);
	END;
	IF (M.id # -1) THEN Display.Broadcast(M); END;
	IF (F.delay = 0) THEN F.delay:= delay[F.score[F.rank].level]; END;
END Drop;

(* ** Timer Handler ***)

PROCEDURE TimerHandler(me: Oberon.Task);
(* send the drop messages to target frame, delayed per level *)
VAR
	time: LONGINT;
BEGIN
	WITH me: Timer DO
		IF ~me.model.paused THEN
			time:= Oberon.Time();
			IF (me.model.delay < 0) OR (me.trigger <= time) THEN
				Drop(me.model);
				IF ~me.model.match THEN
					RemoveTimer(me,TRUE);
				ELSE
					me.trigger:= time + me.model.delay;
				END;
			END;
		END;
	END;
END TimerHandler;

(*** Field Handler ***)

PROCEDURE ResetField(F: Field);
(* Set field's parameters to initial values *)
BEGIN
	F.figures:= 0; F.focus:= TRUE; F.match:= TRUE;
	F.rank:= Ranks-1; F.lap1:= Oberon.Time(); F.lap2:= -1;
	F.delay:= delay[F.score[F.rank].level];
	InitPot(F.pot); NextFigure(F);
END ResetField;

PROCEDURE FieldAttr(F: Field; VAR M: AttrMsg);
BEGIN
	M.res:= -1;
	IF (M.id = Objects.get) THEN
		IF (M.name = "Gen") THEN
			M.class:= Objects.String; M.res:= 0; M.s:= "Tetris.NewField";
		ELSIF (M.name = "Preview") THEN
			M.class:= Objects.Bool; M.res:= 0; M.b:= F.preview;
		ELSIF (M.name = "Pause") THEN
			M.class:= Objects.Bool; M.res:= 0; M.b:= F.paused;
		ELSIF (M.name[1] = "[") & (M.name[3] = "]") THEN	(* indexed attr. *)
			IF (M.name[0] = "N") THEN									 (* Name *)
				M.class:= Objects.String; M.res:= 0;
				COPY(F.score[ORD(M.name[2])-1].name,M.s);
			ELSIF (M.name[0] = "P") THEN								(* Points *)
				M.class:= Objects.Int; M.res:= 0;
				M.i:= F.score[ORD(M.name[2])-1].points;
			ELSIF (M.name[0] = "L") THEN								(* Level *)
				M.class:= Objects.Int; M.res:= 0;
				M.i:= F.score[ORD(M.name[2])-1].level+1;
			ELSIF (M.name[0] = "R") THEN								(* Rows *)
				M.class:= Objects.Int; M.res:= 0;
				M.i:= F.score[ORD(M.name[2])-1].rows;
			END;
		END;
	ELSIF (M.id = Objects.set) THEN
		IF (M.name = "Preview") THEN
			M.res:= 0; F.preview:= M.b;
			IF F.preview THEN F.mult:= 1; END;
		ELSIF (M.name = "Pause") THEN
			M.res:= 0; F.paused:= M.b;
			IF F.paused THEN
				F.lap2:= Oberon.Time();
			ELSE
				F.lap1:= Oberon.Time() - (F.lap2 - F.lap1);
			END;
		ELSIF (M.name[1] = "[") & (M.name[3] = "]") THEN
			IF (M.name[0] = "N") THEN
				M.res:= 0; COPY(M.s,F.score[ORD(M.name[2])-1].name);
			END;
		END;
	ELSIF (M.id = Objects.enum) THEN
	END;
	IF (M.res = -1) THEN Gadgets.objecthandle(F,M); END;
END FieldAttr;

PROCEDURE FieldFile(F: Field; VAR M: FileMsg);
VAR
	i: SHORTINT;
BEGIN
	IF (M.id = Objects.store) THEN
		i:= 0;
		WHILE (i < Ranks) DO
			Files.WriteString(M.R,F.score[i].name);
			Files.WriteLInt(M.R,F.score[i].points);
			Files.WriteInt(M.R,F.score[i].level);
			Files.WriteInt(M.R,F.score[i].rows);
			INC(i);
		END;
		Files.Write(M.R,F.curr); Files.Write(M.R,F.next);
		Files.Write(M.R,F.angle); Files.Write(M.R,F.line);
		Files.Write(M.R,F.row); Files.Write(M.R,F.rank);
		Files.Write(M.R,F.mult); Files.WriteInt(M.R,F.delay);
		Files.WriteInt(M.R,F.figures); Files.WriteBool(M.R,F.match);
		Files.WriteBool(M.R,F.preview); Files.WriteBool(M.R,F.paused);
		Files.WriteLInt(M.R,F.lap1); Files.WriteLInt(M.R,F.lap2);
		i:= 0;
		WHILE (i < PotLines) DO Files.WriteString(M.R,F.pot[i]); INC(i); END;
	ELSIF (M.id = Objects.load) THEN
		i:= 0;
		WHILE (i < Ranks) DO
			Files.ReadString(M.R,F.score[i].name);
			Files.ReadLInt(M.R,F.score[i].points);
			Files.ReadInt(M.R,F.score[i].level);
			Files.ReadInt(M.R,F.score[i].rows);
			INC(i);
		END;
		Files.Read(M.R,F.curr); Files.Read(M.R,F.next);
		Files.Read(M.R,F.angle); Files.Read(M.R,F.line);
		Files.Read(M.R,F.row); Files.Read(M.R,F.rank);
		Files.Read(M.R,F.mult); Files.ReadInt(M.R,F.delay);
		Files.ReadInt(M.R,F.figures); Files.ReadBool(M.R,F.match);
		Files.ReadBool(M.R,F.preview); Files.ReadBool(M.R,F.paused);
		Files.ReadLInt(M.R,F.lap1); Files.ReadLInt(M.R,F.lap2);
		i:= 0;
		WHILE (i < PotLines) DO Files.ReadString(M.R,F.pot[i]); INC(i); END;
	END;
	Gadgets.objecthandle(F,M);
END FieldFile;

PROCEDURE FieldHandler*(F: Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH F: Field DO
		IF M IS AttrMsg THEN
			WITH M: AttrMsg DO FieldAttr(F,M); END;
		ELSIF M IS CopyMsg THEN
			WITH M: CopyMsg DO M.obj:= F; F.focus:= TRUE; END;
		ELSIF M IS FileMsg THEN
			WITH M: FileMsg DO FieldFile(F,M); END;
		ELSE
			Gadgets.objecthandle(F,M);
		END;
	END;
END FieldHandler;

(*** Pot Handler ***)

PROCEDURE PotAlign(R: Frame; VAR M: AlignMsg);
(* Alignment and resizing according to changed dimensions of main Panel *)
BEGIN
	R.scale:= (M.H - 26) DIV ScrnLines;		(* calculate new blocksize *)
	R.W:= R.scale * ScrnRows + 1; R.H:= R.scale * ScrnLines + 1;
	R.X:= 10; R.Y:= -(R.H + 15);
END PotAlign;

PROCEDURE PotAttr(R: Frame; VAR M: AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class:= Objects.String; M.res:= 0; M.s:= "Tetris.NewView";
	ELSE
		Panels.PanelHandler(R,M);	(* no attributes to retrieve *)
	END;
END PotAttr;

PROCEDURE PotCopy(R: Frame; VAR M: CopyMsg);
VAR
	obj: Object;
BEGIN
	IF (M.stamp = R.stamp) THEN
		M.obj:= R.dlink;
	ELSE
		obj:= Gadgets.CreateObject("Tetris.NewView");
		R.stamp:= M.stamp; R.dlink:= obj; M.obj:= obj;
		WITH obj: Frame DO
			Panels.CopyPanel(M,R,obj); obj.blank:= R.blank;
		END;
	END;
END PotCopy;

PROCEDURE PotDisplay(R: Frame; VAR M: DisplayMsg);
VAR
	obj: Object;
	mx,my: INTEGER;
	mask: Display3.Mask;	(* needed for MakeMask *)
BEGIN
	Panels.PanelHandler(R,M);
	IF ~R.blank THEN
		obj:= R.obj; mx:= M.x + R.X; my:= M.y + R.Y;
		Gadgets.MakeMask(R,mx,my,M.dlink,mask);
		IF (M.id = Display.area) THEN
			Display3.AdjustMask(R.mask,mx+M.u,my+R.H-1+M.v,M.w,M.h);
		END;
		WITH obj: Field DO DrawPot(R,M.x,M.y,obj.pot); END;
		UpdSelection(R.mask,R.state,mx,my,R.W,R.H);
	END;
END PotDisplay;

PROCEDURE PotFigure(R: Frame; VAR M: FigureMsg);
(* Redraw current figure in pot *)
VAR
	obj: Object;
	mask: Display3.Mask;	(* needed for MakeMask *)
BEGIN
	IF (M.model = R.obj) & (M.stamp # R.stamp) THEN
		Gadgets.MakeMask(R,M.x+R.X,M.y+R.Y,M.dlink,mask);
		IF (M.id = 0) THEN		(* new figure, no removal necessary *)
			DrawFigure(R,figure[M.ndx,M.angle0],
								M.x,M.y,color[M.ndx],M.row0,M.line0);
		ELSIF (M.id = 1) THEN	(* figure movement, remove and redraw *)
			DrawFigure(R,figure[M.ndx,M.angle0],
								M.x,M.y,R.col,M.row0,M.line0);
			DrawFigure(R,figure[M.ndx,M.angle1],
								M.x,M.y,color[M.ndx],M.row1,M.line1);
		ELSIF (M.id = 2) THEN	(* figure drop, use special function *)
			DrawDrop(R,figure[M.ndx,M.angle0],
								M.x,M.y,color[M.ndx],M.row0,M.line0);
		ELSE							   (* redraw the whole pot content *)
			obj:= R.obj;
			WITH obj: Field DO DrawPot(R,M.x,M.y,obj.pot); END;
			DrawFigure(R,figure[M.ndx,M.angle0],
								M.x,M.y,color[M.ndx],M.row0,M.line0);
		END;
		R.stamp:= M.stamp;
	END;
END PotFigure;

PROCEDURE PotFile(R: Frame; VAR M: FileMsg);
BEGIN
	IF (M.id = Objects.store) THEN
		Files.WriteInt(M.R,R.scale);
		Files.WriteBool(M.R,R.blank);
	ELSIF (M.id = Objects.load) THEN
		Files.ReadInt(M.R,R.scale);
		Files.ReadBool(M.R,R.blank);
	END;
	Panels.PanelHandler(R,M);
END PotFile;

PROCEDURE PotUpdate(R: Frame; VAR M: UpdateMsg);
VAR
	obj: Object;
	mask: Display3.Mask;	(* needed for MakeMask *)
BEGIN
	Panels.PanelHandler(R,M);
	IF (R.obj # NIL) & (M.obj = R.obj) THEN
		obj:= M.obj;
		WITH obj: Field DO
			IF (obj.paused # R.blank) THEN
				Gadgets.MakeMask(R,M.x+R.X,M.y+R.Y,M.dlink,mask);
				IF R.blank THEN
					DrawPot(R,M.x,M.y,obj.pot);
				ELSE
					DrawPot(R,M.x,M.y,clrpot);
				END;
				R.blank:= obj.paused;
			END;
		END;
	END;
END PotUpdate;

PROCEDURE PotHandler*(R: Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH R: Frame DO
		IF OtherFrame(R,M) THEN
			Panels.PanelHandler(R,M);
		ELSIF M IS AlignMsg THEN
			WITH M: AlignMsg DO PotAlign(R,M); END;
		ELSIF M IS AttrMsg THEN
			WITH M: AttrMsg DO PotAttr(R,M); END;
		ELSIF M IS CopyMsg THEN
			WITH M: CopyMsg DO PotCopy(R,M); END;
		ELSIF M IS DisplayMsg THEN
			WITH M: DisplayMsg DO PotDisplay(R,M); END;
		ELSIF M IS FigureMsg THEN
			WITH M: FigureMsg DO PotFigure(R,M); END;
		ELSIF M IS FileMsg THEN
			WITH M: FileMsg DO PotFile(R,M); END;
		ELSIF M IS UpdateMsg THEN
			WITH M: UpdateMsg DO PotUpdate(R,M); END;
		ELSE
			Panels.PanelHandler(R,M);
		END;
	END;
END PotHandler;

(*** Preview Handler ***)

PROCEDURE PreviewAlign(P: Frame; VAR M: AlignMsg);
(* Alignment and resizing according to changed dimensions of main Panel *)
BEGIN
	P.X:= ((M.H - 26) DIV ScrnLines) * ScrnRows + 31;
	P.Y:= -(P.H + 15);
END PreviewAlign;

PROCEDURE PreviewAttr(P: Frame; VAR M: AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class:= Objects.String; M.res:= 0; M.s:= "Tetris.NewPreview";
	ELSE
		Panels.PanelHandler(P,M);	(* no attributes to retrieve *)
	END;
END PreviewAttr;

PROCEDURE PreviewCopy(P: Frame; VAR M: CopyMsg);
VAR
	obj: Object;
BEGIN
	IF (M.stamp = P.stamp) THEN
		M.obj:= P.dlink;
	ELSE
		obj:= Gadgets.CreateObject("Tetris.NewPreview");
		P.stamp:= M.stamp; P.dlink:= obj; M.obj:= obj;
		WITH obj: Frame DO Panels.CopyPanel(M,P,obj); END;
	END;
END PreviewCopy;

PROCEDURE PreviewDisplay(P: Frame; VAR M: DisplayMsg);
VAR
	F: Object;
	mx,my: INTEGER;
	show: BOOLEAN;
	next: SHORTINT;
	mask: Display3.Mask;	(* needed for MakeMask *)
BEGIN
	Panels.PanelHandler(P,M);
	F:= P.obj;
	WITH F: Field DO show:= F.preview & ~F.paused; next:= F.next; END;
	IF show THEN
		mx:= M.x + P.X; my:= M.y + P.Y;
		Gadgets.MakeMask(P,mx,my,M.dlink,mask);
		IF (M.id = Display.area) THEN
			Display3.AdjustMask(P.mask,mx+M.u,my+P.H-1+M.v,M.w,M.h);
		END;
		DrawPreview(P,figure[next,0],xofs[next],yofs[next],color[next]);
		UpdSelection(mask,P.state,mx,my,P.W,P.H);
	END;
END PreviewDisplay;

PROCEDURE PreviewUpdate(P: Frame; VAR M: UpdateMsg);
VAR
	F: Object;
	show: BOOLEAN;
	curr,next: SHORTINT;
	mask: Display3.Mask;	(* needed for MakeMask *)
BEGIN
	Panels.PanelHandler(P,M);
	IF (P.obj # NIL) & (M.obj = P.obj) THEN
		F:= P.obj;
		WITH F: Field DO
			show:= F.preview & ~F.paused; curr:= F.curr; next:= F.next;
		END;
		IF ~show THEN	(* remove *)
			Gadgets.MakeMask(P,M.x+P.X,M.y+P.Y,M.dlink,mask);
			DrawPreview(P,figure[next,0],xofs[next],yofs[next],P.col);
		ELSE					(* remove & redraw *)
			Gadgets.MakeMask(P,M.x+P.X,M.y+P.Y,M.dlink,mask);
			DrawPreview(P,figure[curr,0],xofs[curr],yofs[curr],P.col);
			DrawPreview(P,figure[next,0],xofs[next],yofs[next],color[next]);
		END;
	END;
END PreviewUpdate;

PROCEDURE PreviewHandler*(P: Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH P: Frame DO
		IF OtherFrame(P,M) THEN
			Panels.PanelHandler(P,M);
		ELSIF M IS AlignMsg THEN
			WITH M: AlignMsg DO PreviewAlign(P,M); END;
		ELSIF M IS AttrMsg THEN
			WITH M: AttrMsg DO PreviewAttr(P,M); END;
		ELSIF M IS CopyMsg THEN
			WITH M: CopyMsg DO PreviewCopy(P,M); END;
		ELSIF M IS DisplayMsg THEN
			WITH M: DisplayMsg DO PreviewDisplay(P,M); END;
		ELSIF M IS UpdateMsg THEN
			WITH M: UpdateMsg DO PreviewUpdate(P,M); END;
		ELSE
			Panels.PanelHandler(P,M);
		END;
	END;
END PreviewHandler;

(*** Scorefield Handler ***)

PROCEDURE ScoreAlign(S: ScoreField; VAR M: AlignMsg);
(* Alignment - mention the relative position in the score array *)
BEGIN
	S.X:= ((M.H - 26) DIV ScrnLines) * ScrnRows + 31 + S.xofs;
	S.Y:= -(PreviewScale*FigLines+25)-(15+TextH)-((S.ndx+1)*TextH);
END ScoreAlign;

PROCEDURE ScoreAttr(S: ScoreField; VAR M: AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class:= Objects.String; M.res:= 0; M.s:= "Tetris.NewScoreField";
	ELSE
		TextFields.TextFieldHandler(S,M);	(* no attributes to retrieve *)
	END;
END ScoreAttr;

PROCEDURE ScoreCopy(S: ScoreField; VAR M: CopyMsg);
VAR
	obj: Object;
BEGIN
	IF (M.stamp = S.stamp) THEN
		M.obj:= S.dlink;
	ELSE
		obj:= Gadgets.CreateObject("Tetris.NewScoreField");
		S.stamp:= M.stamp; S.dlink:= obj; M.obj:= obj;
		WITH obj: ScoreField DO
			TextFields.CopyTextField(M,S,obj);
			obj.ndx:= S.ndx; obj.xofs:= S.xofs;
		END;
	END;
END ScoreCopy;

PROCEDURE ScoreFile(S: ScoreField; VAR M: FileMsg);
BEGIN
	IF (M.id = Objects.store) THEN
		Files.WriteInt(M.R,S.ndx); Files.WriteInt(M.R,S.xofs);
	ELSIF (M.id = Objects.load) THEN
		Files.ReadInt(M.R,S.ndx); Files.ReadInt(M.R,S.xofs);
	END;
	TextFields.TextFieldHandler(S,M);
END ScoreFile;

PROCEDURE ScoreInput(S: ScoreField; VAR M: InputMsg);
VAR
	F: Object;
BEGIN
	IF (S.obj = NIL) THEN
		TextFields.TextFieldHandler(S,M);
	ELSE	(* Only Highscorers are allowed to insert names *)
		F:= S.obj;
		WITH F: Field DO
			IF (S.xofs = 0) & (S.ndx < Ranks-1) & (S.ndx = F.rank) THEN
				TextFields.TextFieldHandler(S,M);
			END;
		END;
	END;
END ScoreInput;

PROCEDURE ScoreHandler*(S: Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH S: ScoreField DO
		IF M IS AlignMsg THEN
			WITH M: AlignMsg DO ScoreAlign(S,M); END;
		ELSIF M IS AttrMsg THEN
			WITH M: AttrMsg DO ScoreAttr(S,M); END;
		ELSIF M IS FileMsg THEN
			WITH M: FileMsg DO ScoreFile(S,M); END;
		ELSIF M IS CopyMsg THEN
			WITH M: CopyMsg DO ScoreCopy(S,M); END;
		ELSIF M IS InputMsg THEN
			WITH M: InputMsg DO ScoreInput(S,M); END;
		ELSE
			TextFields.TextFieldHandler(S,M);
		END;
	END;
END ScoreHandler;

(*** Preview Button Handler ***)

PROCEDURE PreviewButtonAlign(B: BasicGadgets.Button; VAR M: AlignMsg);
(* Alignment and resizing according to changed dimensions of Panel *)
BEGIN
	B.X:= ((M.H-26) DIV ScrnLines)*ScrnRows+PreviewScale*FigRows+48;
	B.Y:= -(B.H + PreviewScale*FigLines - 2);
END PreviewButtonAlign;

PROCEDURE PreviewButtonAttr(B: BasicGadgets.Button; VAR M: AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class:= Objects.String; M.res:= 0; M.s:= "Tetris.NewPreviewButton";
	ELSE
		BasicGadgets.ButtonHandler(B,M);	(* no attributes to retrieve *)
	END;
END PreviewButtonAttr;

PROCEDURE PreviewButtonHandler*(B: Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH B: BasicGadgets.Button DO
		IF M IS AlignMsg THEN
			WITH M: AlignMsg DO PreviewButtonAlign(B,M); END;
		ELSIF M IS AttrMsg THEN
			WITH M: AttrMsg DO PreviewButtonAttr(B,M); END;
		ELSE
			BasicGadgets.ButtonHandler(B,M);
		END;
	END;
END PreviewButtonHandler;

(*** Pause Button Handler ***)

PROCEDURE PauseButtonAlign(B: BasicGadgets.Button; VAR M: AlignMsg);
(* Alignment and resizing according to changed dimensions of Panel *)
BEGIN
	B.X:= ((M.H-26) DIV ScrnLines)*ScrnRows+PreviewScale*FigRows+116;
	B.Y:= -(B.H + PreviewScale*FigLines - 2);
END PauseButtonAlign;

PROCEDURE PauseButtonAttr(B: BasicGadgets.Button; VAR M: AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		M.class:= Objects.String; M.res:= 0; M.s:= "Tetris.NewPauseButton";
	ELSE
		BasicGadgets.ButtonHandler(B,M);	(* no attributes to retrieve *)
	END;
END PauseButtonAttr;

PROCEDURE PauseButtonHandler*(B: Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH B: BasicGadgets.Button DO
		IF M IS AlignMsg THEN
			WITH M: AlignMsg DO PauseButtonAlign(B,M); END;
		ELSIF M IS AttrMsg THEN
			WITH M: AttrMsg DO PauseButtonAttr(B,M); END;
		ELSE
			BasicGadgets.ButtonHandler(B,M);
		END;
	END;
END PauseButtonHandler;

(*** Main Handler ***)

PROCEDURE MainBackdrop(D: Object; VAR M: BackdropMsg);
(* force picture panel to change it's backdrop picture - next level *)
BEGIN
	IF (M.model = Model(D)) THEN
		Attributes.SetString(D,"Picture",backdrop[M.ndx]);
		Gadgets.Update(D);
	END;
END MainBackdrop;

PROCEDURE MainControl(D: Panels.Panel; VAR M: ControlMsg);
VAR
	model: Field;
BEGIN
	model:= Model(D);
	IF (M.id = Oberon.defocus) OR (M.id = Oberon.neutralize) THEN
		model:= Model(D);
		IF model.match THEN
			IF model.focus THEN
				Attributes.SetBool(model,"Pause",TRUE); Gadgets.Update(model);
			END;
			model.focus:= FALSE;
		END;
	END;
	Panels.PanelHandler(D,M);
END MainControl;

PROCEDURE MainDisplay(D: Panels.Panel; VAR M: DisplayMsg);
BEGIN
	(* send an initial update message *)
	IF (M.id = Display.extend) THEN Gadgets.Update(Model(D)); END;
	Panels.PanelHandler(D,M);
END MainDisplay;

PROCEDURE MainInput(D: Panels.Panel; VAR M: InputMsg);
VAR
	model: Field;
BEGIN
	model:= Model(D);
	IF (M.id = Oberon.track) THEN
		IF model.match & Gadgets.InActiveArea(D,M) THEN
			IF M.keys = {Left} THEN
				REPEAT
					Effects.TrackMouse(M.keys,M.X,M.Y,Effects.Arrow);
				UNTIL M.keys = {};
				IF ~model.focus THEN Oberon.Defocus(); END;
				model.focus:= TRUE; M.res:= 0;
			END;
		END;
	ELSIF (M.id = Oberon.consume) THEN	           (* discard all other events *)
		IF model.match & (model.stamp # M.stamp) THEN (* game in progress *)
			model.stamp:= M.stamp;					   (* one input for all instances  *)
			IF model.focus & ~Move(model,M.ch) THEN
				IF ((M.ch = KeyPrev) OR (M.ch = Keyprev)) THEN
					Attributes.SetBool(model,"Preview",~model.preview);
					Gadgets.Update(model);
				ELSIF ((M.ch = KeyPause) OR (M.ch = Keypause)) THEN
					Attributes.SetBool(model,"Pause",~model.paused);
					Gadgets.Update(model);
				END;
			END;
		END;
	END;
	IF (M.res # 0) THEN Panels.PanelHandler(D,M); END;
END MainInput;

PROCEDURE MainModify(D: Panels.Panel; VAR M: ModifyMsg);
VAR
	A: AlignMsg;
	model: Field;
BEGIN
	IF (M.F = D) THEN
		model:= Model(D);
		IF (D.H + M.dH # 0) THEN		(* make sure frame is not closed *)
			A.X:= M.X; A.Y:= M.Y; A.W:= M.W; A.H:= M.H;
			Objects.Stamp(A);
			Panels.ToChildren(D,A);
		END;
	END;
	Panels.PanelHandler(D,M);
END MainModify;

PROCEDURE MainHandler*(D: Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH D: Panels.Panel DO
		IF OtherFrame(D,M) THEN
			Panels.PanelHandler(D,M);
		ELSIF M IS BackdropMsg THEN
			WITH M: BackdropMsg DO MainBackdrop(D,M); END;
		ELSIF M IS ControlMsg THEN
			WITH M: ControlMsg DO MainControl(D,M); END;
		ELSIF M IS DisplayMsg THEN
			WITH M: DisplayMsg DO MainDisplay(D,M); END;
		ELSIF M IS InputMsg THEN
			WITH M: InputMsg DO MainInput(D,M); END;
		ELSIF M IS ModifyMsg THEN
			WITH M: ModifyMsg DO MainModify(D,M); END;
		ELSE
			Panels.PanelHandler(D,M);
		END;
	END;
END MainHandler;

(*** Document Handler ***)

PROCEDURE DocAttr(D: Document; VAR M: AttrMsg);
BEGIN
	M.res:= -1;
	IF (M.id = Objects.get) THEN
		IF (M.name = "Gen") THEN
			M.class:= Objects.String; M.res:= 0; M.s:= "Tetris.NewDoc";
		ELSIF (M.name = "Adaptive") THEN
			M.class:= Objects.Bool; M.res:= 0; M.b:= TRUE;
		ELSIF (M.name = "Icon") THEN
			M.class:= Objects.String; M.res:= 0; M.s:= DocIcon;
		END;
	END;
	IF (M.res = -1) THEN Documents.Handler(D,M); END;
END DocAttr;

PROCEDURE DocLink(D: Document; VAR M: LinkMsg);
BEGIN
	IF (M.id = Objects.get) & ((M.name = "DeskMenu") OR (M.name = "SystemMenu") OR (M.name = "UserMenu")) THEN
		M.obj:= Desktops.NewMenu(DocMenu); M.res := 0;
	ELSE
		Documents.Handler(D,M);
	END;
END DocLink;

PROCEDURE DocHandler*(D: Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH D: Document DO
		IF M IS AttrMsg THEN
			WITH M: AttrMsg DO DocAttr(D,M); END;
		ELSIF M IS LinkMsg THEN
			WITH M: LinkMsg DO DocLink(D,M); END;
		ELSE
			Documents.Handler(D,M);
		END;
	END;
END DocHandler;

(*** Document Creation ***)

PROCEDURE NewTop(txt: ARRAY OF CHAR; len,ofs: INTEGER): Object;
(* Creates a topline for the score array - should be editable *)
VAR
	obj: Object;
BEGIN
	obj:= Gadgets.CreateObject("Tetris.NewScoreField");
	WITH obj: ScoreField DO
		obj.ndx:= -1; obj.xofs:= ofs;
		obj.slink:= NIL; INC(obj.W,TextW*len); COPY(txt,obj.val);
	END;
	RETURN(obj);
END NewTop;

PROCEDURE NewScore(c: CHAR; num,len,ofs: INTEGER; model: Object): Object;
(* Creates one score field (c holds the attribute, indexed by num) *)
VAR
	obj: Object;
	str: ARRAY 5 OF CHAR;
BEGIN
	obj:= Gadgets.CreateObject("Tetris.NewScoreField");
	WITH obj: ScoreField DO
		obj.slink:= NIL; obj.ndx:= num; obj.xofs:= ofs;
		INC(obj.W,TextW*len); obj.obj:= model;
	END;
	str[0]:= c; str[1]:= "["; str[2]:= CHR(num+1); str[3]:= "]"; str[4]:= 0X;
	Attributes.SetString(obj,"Field",str);
	RETURN(obj);
END NewScore;

PROCEDURE ScoreArray(model: Object): Object;
(* Creates the score array visible by the user, Objects are linked by slink *)
VAR
	first,this,obj: Object;
	ofs: INTEGER;
	i: SHORTINT;
BEGIN
	i:= 0;
	first:= NewTop("Name",NameW,0);
	WITH first: Gadgets.Frame DO ofs:= first.W; END;
	obj:= first;
	this:= NewTop("Score",PointsW,ofs);
	WITH this: Gadgets.Frame DO INC(ofs,this.W); END;
	obj.slink:= this; obj:= this;
	this:= NewTop("Level",LevelW,ofs);
	WITH this: Gadgets.Frame DO INC(ofs,this.W); END;
	obj.slink:= this; obj:= this;
	this:= NewTop("Rows",RowsW,ofs);
	obj.slink:= this; obj:= this;
	WHILE (i < Ranks) DO
		this:= NewScore("N",i,NameW,0,model);
		WITH this: Gadgets.Frame DO ofs:= this.W; END;
		obj.slink:= this; obj:= this;
		this:= NewScore("P",i,PointsW,ofs,model);
		WITH this: Gadgets.Frame DO INC(ofs,this.W); END;
		obj.slink:= this; obj:= this;
		this:= NewScore("L",i,LevelW,ofs,model);
		WITH this: Gadgets.Frame DO INC(ofs,this.W); END;
		obj.slink:= this; obj:= this;
		this:= NewScore("R",i,RowsW,ofs,model);
		obj.slink:= this; obj:= this;
		INC(i);
	END;
	RETURN(first);
END ScoreArray;

PROCEDURE NewButton(gen,capt: ARRAY OF CHAR; model: Object): Object;
VAR
	obj: Objects.Object;
BEGIN
	obj:= Gadgets.CreateObject(gen);
	WITH obj: BasicGadgets.Button DO
		obj.W:= ButtonW; obj.obj:= model;
	END;
	Attributes.SetString(obj,"Field",capt);
	Attributes.SetString(obj,"Caption",capt);
	RETURN(obj);
END NewButton;

PROCEDURE OldDocument(F: Files.File; D: Document; VAR f: Gadgets.Frame);
(* Restore an old Tetris document from file *)
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
						obj.handle:= MainHandler; f:= obj;
					END;
				END;
			END;
		END;
	END;
END OldDocument;

PROCEDURE NewDocument(D: Document; VAR f: Gadgets.Frame);
(* Create a new Tetris Document *)
VAR
	C: ConsumeMsg;
	M: BackdropMsg;
	A: AlignMsg;
	obj,view,model: Object;
	panel: Panels.Panel;
BEGIN
	NEW(panel); Panels.InitPanel(panel); f:= panel;
	view:= Gadgets.CreateViewModel("Tetris.NewView","Tetris.NewField");
	WITH view: Frame DO model:= view.obj; END;
	C.id:= Display.drop; C.x:= 0; C.y:= 0; C.u:= 0; C.v:= 0;
	panel.W:= D.W-1; panel.H:= D.H-1;
	INCL(panel.state0,Panels.texture); panel.handle:= MainHandler;
	C.F:= panel; C.obj:= view; C.res:= -1; panel.handle(panel,C);
	obj:= Gadgets.CreateObject("Tetris.NewPreview");
	WITH obj: Gadgets.Frame DO obj.obj:= model; END;
	C.obj:= obj; C.res:= -1; panel.handle(panel,C);
	C.obj:= ScoreArray(model);
	C.res:= -1; panel.handle(panel,C);
	C.obj:= NewButton("Tetris.NewPreviewButton","Preview",model);
	C.res:= -1; panel.handle(panel,C);
	C.obj:= NewButton("Tetris.NewPauseButton","Pause",model);
	C.res:= -1; panel.handle(panel,C);
	M.F:= NIL; M.model:= model; M.ndx:= 0;
	M.res:= -1; MainBackdrop(panel,M);
	A.X:= panel.X; A.Y:= panel.Y; A.W:= panel.W; A.H:= panel.H;
	Panels.ToChildren(panel,A);
	Gadgets.Update(model);
END NewDocument;

PROCEDURE LoadDocument(D: Document);
(* Loading Method for Tetris Documents *)
VAR
	F: Files.File;
	frame: Gadgets.Frame;
	model: Field;
BEGIN
	F:= NIL; frame:= NIL;
	IF (D.name = "") THEN D.name:= DefName; ELSE F:= Files.Old(D.name); END;
	IF (F # NIL) THEN
		OldDocument(F,D,frame);
		IF (frame # NIL) THEN
			model:= Model(frame);
			IF model.match THEN
				Oberon.Install(model.timer); Oberon.Defocus();
			ELSE
				model.rank:= Ranks-1;
			END;
		END;
		Files.Close(F);
	ELSE
		NewDocument(D,frame);
		model:= Model(frame);
		FieldFigure(model,TRUE);
		Oberon.Install(model.timer); Oberon.Defocus();
	END;
	Documents.Init(D,frame);
END LoadDocument;

PROCEDURE StoreDocument(D: Document);
(* Storing Method for Tetris Documents *)
VAR
	F: Files.File;
	R: Files.Rider;
	B: BindMsg;
	A: AttrMsg;
	len: LONGINT;
BEGIN
	IF (D.name # "") & (D.dsc # NIL) THEN
		Out.String("Store ");
		NEW(B.lib); Objects.OpenLibrary(B.lib); D.dsc.handle(D.dsc,B);
		Objects.Stamp(A); A.id:= Objects.get; A.name:= "Gen"; D.handle(D,A);
		F:= Files.New(D.name); Files.Set(R,F,0);
		Files.WriteInt(R,Documents.Id);
		Files.WriteString(R,A.s); Files.WriteString(R,Version);
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
	i: INTEGER;
BEGIN
	NEW(F); NEW(F.timer); ResetField(F);
	FOR i:= 1 TO Ranks DO ResetScore(F.score[i-1]); END;
	F.handle:= FieldHandler;
	F.preview:= TRUE; F.paused:= FALSE; F.mult:= 1;
	F.timer.model:= F; F.timer.trigger:= Oberon.Time() + F.delay;
	F.timer.safe:= TRUE; F.timer.handle:= TimerHandler;
	F.timer.nxt:= timers; timers:= F.timer;
	Objects.NewObj:= F;
END NewField;

PROCEDURE NewView*;
VAR
	R: Frame;
BEGIN
	NEW(R); Panels.InitPanel(R);
	R.W:= 0; R.H:= 0; R.X:= 0; R.Y:= 0; R.scale:= 0; R.blank:= FALSE;
	R.col:= Display3.BG; R.handle:= PotHandler;
	Gadgets.NameObj(R,"Pot");
	Objects.NewObj:= R;
END NewView;

PROCEDURE NewScoreField*;
VAR
	S: ScoreField;
BEGIN
	NEW(S); TextFields.InitTextField(S);
	S.X:= 0; S.Y:= 0; S.W:= 10; S.H:= TextH; S.handle:= ScoreHandler;
	Objects.NewObj:= S;
END NewScoreField;

PROCEDURE NewPreviewButton*;
VAR
	B: BasicGadgets.Button;
BEGIN
	NEW(B); BasicGadgets.InitButton(B);
	B.X:= 0; B.Y:= 0; B.H:= TextH + 10; B.handle:= PreviewButtonHandler;
	Attributes.SetBool(B,"Popout",FALSE);
	Objects.NewObj:= B;
END NewPreviewButton;

PROCEDURE NewPauseButton*;
VAR
	B: BasicGadgets.Button;
BEGIN
	NEW(B); BasicGadgets.InitButton(B);
	B.X:= 0; B.Y:= 0; B.H:= TextH + 10; B.handle:= PauseButtonHandler;
	Attributes.SetBool(B,"Popout",FALSE);
	Objects.NewObj:= B;
END NewPauseButton;

PROCEDURE NewPreview*;
VAR
	R: Frame;
BEGIN
	NEW(R); Panels.InitPanel(R);
	R.scale:= PreviewScale;
	R.W:= R.scale*FigRows+10; R.H:= R.scale*FigLines+10; R.X:= 0; R.Y:= 0;
	R.col:= Display3.BG; R.handle:= PreviewHandler;
	Objects.NewObj:= R;
END NewPreview;

PROCEDURE NewDoc*;
VAR
	D: Document;
BEGIN
	NEW(D);
	D.Load:= LoadDocument; D.Store:= StoreDocument;
	D.W:= 385(*315*); D.H:= 215; D.handle:= DocHandler;
	Objects.NewObj:= D;
END NewDoc;

(*** Commands ***)

PROCEDURE NewGame*;
(* Start a new game *)
VAR
	D: Document;
	M: BackdropMsg;
	model: Object;
BEGIN
	D:= Desktops.CurDoc(Gadgets.context);
	IF (D # NIL) & (D.dsc IS Panels.Panel) THEN
		model:= Model(D.dsc);
		IF (model # NIL) THEN
			WITH model: Field DO
				Oberon.Remove(model.timer);
				model.focus:= FALSE; Oberon.Defocus();
				ResetScore(model.score[Ranks-1]);
				ResetField(model); FieldFigure(model,TRUE);
				Gadgets.Update(model);
				M.F:= NIL; M.model:= model; M.ndx:= 0; Display.Broadcast(M);
				Oberon.Install(model.timer);
			END;
		END;
	END;
END NewGame;

PROCEDURE Backdrop*;
(* Change an entry in the array of backdrop picture names *)
VAR
	level: INTEGER;
	file: Objects.Name;
BEGIN
	In.Open();
	REPEAT
		In.Int(level);
		IF In.Done THEN In.Name(file); END;
		IF In.Done & (level > 0) & (level <= Levels) THEN
			COPY(file,backdrop[level-1]);
		END;
	UNTIL ~In.Done;
END Backdrop;

PROCEDURE Delay*;
(* Change the drop impulse delay time *)
VAR
	level,value: INTEGER;
BEGIN
	In.Open();
	REPEAT
		In.Int(level);
		IF In.Done THEN In.Int(value); END;
		IF In.Done & (level > 0) & (level <= Levels) THEN
			delay[level-1]:= value;
		END;
	UNTIL ~In.Done;
END Delay;

PROCEDURE StopTimers;
BEGIN
	WHILE (timers # NIL) DO
		Oberon.Remove(timers); timers:= timers.nxt;
	END;
END StopTimers;

BEGIN
	(* What I wanted to say... *)
	Out.String("Tetris "); Out.String(Version);
	Out.String(" by W. Ibl, "); Out.String(Date); Out.Ln();
	Out.String("Original concept by Alexy Pajitnov"); Out.Ln();
	Out.String("Original design by Vadim Gerasimov"); Out.Ln();

	(* Initialize pot to be displayed when paused *)
	InitPot(clrpot);

	(* Timer Task management *)
	timers:= NIL;
	Modules.InstallTermHandler(StopTimers);

	(* those are the classic figures *)
	figure[0,0,0]:= "----";	figure[0,1,0]:= "--$-";	figure[0,2,0]:= "----";	figure[0,3,0]:= "--$-";
	figure[0,0,1]:= "$$--";	figure[0,1,1]:= "-$$-";	figure[0,2,1]:= "$$--";	figure[0,3,1]:= "-$$-";
	figure[0,0,2]:= "-$$-";	figure[0,1,2]:= "-$--";	figure[0,2,2]:= "-$$-";	figure[0,3,2]:= "-$--";
	figure[0,0,3]:= "----";	figure[0,1,3]:= "----";	figure[0,2,3]:= "----";	figure[0,3,3]:= "----";

	figure[1,0,0]:= "----";	figure[1,1,0]:= "-$--";	figure[1,2,0]:= "----";	figure[1,3,0]:= "-$--";
	figure[1,0,1]:= "-$--";	figure[1,1,1]:= "-$$-";	figure[1,2,1]:= "$$$-";	figure[1,3,1]:= "$$--";
	figure[1,0,2]:= "$$$-";	figure[1,1,2]:= "-$--";	figure[1,2,2]:= "-$--";	figure[1,3,2]:= "-$--";
	figure[1,0,3]:= "----";	figure[1,1,3]:= "----";	figure[1,2,3]:= "----";	figure[1,3,3]:= "----";

	figure[2,0,0]:= "-$--";	figure[2,1,0]:= "----";	figure[2,2,0]:= "-$--";	figure[2,3,0]:= "----";
	figure[2,0,1]:= "-$--";	figure[2,1,1]:= "$$$$";	figure[2,2,1]:= "-$--";	figure[2,3,1]:= "$$$$";
	figure[2,0,2]:= "-$--";	figure[2,1,2]:= "----";	figure[2,2,2]:= "-$--";	figure[2,3,2]:= "----";
	figure[2,0,3]:= "-$--";	figure[2,1,3]:= "----";	figure[2,2,3]:= "-$--";	figure[2,3,3]:= "----";

	figure[3,0,0]:= "----";	figure[3,1,0]:= "----";	figure[3,2,0]:= "----";	figure[3,3,0]:= "----";
	figure[3,0,1]:= "-$$-";	figure[3,1,1]:= "-$$-";	figure[3,2,1]:= "-$$-";	figure[3,3,1]:= "-$$-";
	figure[3,0,2]:= "-$$-";	figure[3,1,2]:= "-$$-";	figure[3,2,2]:= "-$$-";	figure[3,3,2]:= "-$$-";
	figure[3,0,3]:= "----";	figure[3,1,3]:= "----";	figure[3,2,3]:= "----";	figure[3,3,3]:= "----";

	figure[4,0,0]:= "----";	figure[4,1,0]:= "-$--";	figure[4,2,0]:= "----";	figure[4,3,0]:= "-$--";
	figure[4,0,1]:= "-$$-";	figure[4,1,1]:= "-$$-";	figure[4,2,1]:= "-$$-";	figure[4,3,1]:= "-$$-";
	figure[4,0,2]:= "$$--";	figure[4,1,2]:= "--$-";	figure[4,2,2]:= "$$--";	figure[4,3,2]:= "--$-";
	figure[4,0,3]:= "----";	figure[4,1,3]:= "----";	figure[4,2,3]:= "----";	figure[4,3,3]:= "----";

	figure[5,0,0]:= "-$$-";	figure[5,1,0]:= "-$$$";	figure[5,2,0]:= "--$-";	figure[5,3,0]:= "-$--";
	figure[5,0,1]:= "-$--";	figure[5,1,1]:= "---$";	figure[5,2,1]:= "--$-";	figure[5,3,1]:= "-$$$";
	figure[5,0,2]:= "-$--";	figure[5,1,2]:= "----";	figure[5,2,2]:= "-$$-";	figure[5,3,2]:= "----";
	figure[5,0,3]:= "----";	figure[5,1,3]:= "----";	figure[5,2,3]:= "----";	figure[5,3,3]:= "----";

	figure[6,0,0]:= "-$$-";	figure[6,1,0]:= "--$-";	figure[6,2,0]:= "-$--";	figure[6,3,0]:= "----";
	figure[6,0,1]:= "--$-";	figure[6,1,1]:= "$$$-";	figure[6,2,1]:= "-$--";	figure[6,3,1]:= "$$$-";
	figure[6,0,2]:= "--$-";	figure[6,1,2]:= "----";	figure[6,2,2]:= "-$$-";	figure[6,3,2]:= "$---";
	figure[6,0,3]:= "----";	figure[6,1,3]:= "----";	figure[6,2,3]:= "----";	figure[6,3,3]:= "----";

	(* Default colors of figures (non classic) *)
	color[0]:= 1; color[1]:= 9; color[2]:= 3; color[3]:= 4; color[4]:= 11; color[5]:= 7; color[6]:= 8;
	xofs[0]:= 1; xofs[1]:= 1; xofs[2]:= 1; xofs[3]:= 0; xofs[4]:= 1; xofs[5]:= 0; xofs[6]:= 0;
	yofs[0]:= 0; yofs[1]:= 0; yofs[2]:= 0; yofs[3]:= 0; yofs[4]:= 0; yofs[5]:= 1; yofs[6]:= 1;

	(* Increasing speed for falling figures *)
	delay[0]:= 250; delay[1]:= 230; delay[2]:= 200; delay[3]:= 160; delay[4]:= 100;
	delay[5]:= 70; delay[6]:= 30; delay[7]:= 20; delay[8]:= 8; delay[9]:= 1;
	FOR fudge := 0 TO 9 DO delay[fudge] := delay[fudge] * Fudge END;
	
	(* Default backdrops changing per level *)
	backdrop[0]:= "Bows.Pict";		   backdrop[1]:= "Bricks.Pict";
	backdrop[2]:= "Cells.Pict";			backdrop[3]:= "Clouds.Pict";
	backdrop[4]:= "Coins.Pict";		   backdrop[5]:= "Textils.Pict";
	backdrop[6]:= "Fractal.Pict";		 backdrop[7]:= "Surface.Pict";
	backdrop[8]:= "Molecules.Pict";	backdrop[9]:= "Spirals.Pict";
END Tetris.

Desktops.OpenDoc Tetris.Doc (Tetris.NewDoc)~
System.Free Tetris~
System.DeleteFiles Tetris.Doc~