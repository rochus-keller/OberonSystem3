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

MODULE Dim3Engine;	(** portable *)	(* David Ulrich Nov  95 - März 96 *)
(** This module contains a 3D Engine to draw 3D worlds consisting of polygons **)

IMPORT
	Attributes, Display, Files, Gadgets, Math, Oberon, Objects, Pictures, Texts, Dim3Paint, Fonts, Dim3Base;


CONST
	invisible* = 0; mustClip* = 1; selected* = 2; smooth* = 3; dither* = 4; gouraud* = 5; specular* = 6; (** shape state flags **)
	locked* = 0; needUpdate* = 1;	(** world state flags **)
	maxVertices = 20;	(* maximum number of vertices for clipped polygons *)
	nPlanes = 5;	(* number of clipping planes *)
	hither = -0.01;	(* z-position of front clipping plane *)
	numDynScreen = 500; 	(* max number of rows in world *)
	SKY = 83; GND = 8; 	(* sky and ground colors based on rembrandt color map *)
	DirectLight* = 0; PointLight* = 1;	(** types of light sources **)
	Dist = 0.2;	(* Correction for distance calculation used by point lights for diffuse reflection*)
	DistSpec = 0.5; 	(* Correction for distance calculation used by point lights for specular reflection*)
	EOS = 0X; (* end of string *)
	MaxString* = 64; (** maximal number of characters in StringTextures **)


TYPE
	Vector* = ARRAY 3 OF REAL;	(** 4th homogenous coordinate (W) is always assumed to be 1 **)
	Matrix* = ARRAY 3, 4 OF REAL;	(** bottom row is always assumed to be [0, 0, 0, 1] **)
	Color* = ARRAY 3 OF REAL;	(** red, green and blue value **)
	
	(** directional  or point light sources **)
	Light* = POINTER TO LightDesc;
	LightDesc* = RECORD
		next*: Light;
		type*: INTEGER;	(** direct light source -> type = DirectLight; point light source -> type = PointLight **)
		inten*: REAL;	(** light intensity, 0 < inten <= 1 **)
		dir*: Vector;	(** light direction or position of point light source in world space **)
	END;
	
	LightRef = POINTER TO LightRefDesc;
	LightRefDesc = RECORD
		next: LightRef;
		light: Light;
		factor: REAL;
		R: Vector;
	END;
	
	(** geometric structures **)
	Point* = POINTER TO PointDesc;
	PointRef* = POINTER TO PointRefDesc;
	Polygon* = POINTER TO PolygonDesc;
	Shape* = POINTER TO ShapeDesc;
	Texture = POINTER TO TextureDesc;
	
	TextureDesc = RECORD
		stringTexture: BOOLEAN; (* TRUE -> string texture, FALSE -> normal texture *)
		name, font: ARRAY MaxString OF CHAR;
		fontCol, backCol: Color;	(* used for string textures *)
		basePict: Pictures.Picture;	(* original texture *)
		shadedPict: ARRAY 6 OF Dim3Paint.TextureMap; (* shaded textures, maximal 6 mipmaps *)
		numPict: INTEGER;	(* number of mipmaps used *)
		transparent: BOOLEAN;	(* use perspective correction *)
	END;
	
	PointDesc* = RECORD
		next*: Point;
		wc*: Vector;	(** 3D world coordinates (WC) *)
		vrc*: Vector;	(** 3D view reference coordinates (VRC) *)
		normal: Vector;	(* normal vector of point *)
	END;
	
	PointRefDesc* = RECORD
		next*, prev*: PointRef;	(** successor and predecessor in doubly linked polygon list **)
		p*: Point;	(** referenced point **)
		u, v: REAL;  (** texture coordinates **)
		inten*: REAL; (** light intensity in point, 0 < inten <= 1 **)
		specular: REAL; (* specular light intensity, only used during drawing *)
		light: LightRef; (* list of lights for specular reflexion *)
	END;
	
	PolygonDesc* = RECORD
		next*: Polygon;
		contour*: PointRef;	(** list of contour point references **)
		normal*: Vector;	(** vector pointing away from polygon (in WC) **)
		dist*: REAL;	(** distance of polygon to origin => poly.normal * X + poly.dist = (signed) distance of vector X to plane **)
		col*: INTEGER;	(** color number of shaded polygon **)
		shape*: Shape;	(** shape that contains polygon **)
		texture*: Texture; 	(** texture, the plane has to be filled with, NIL if no texture **)
	END;
	
	ShapeDesc* = RECORD
		next*: Shape;	(** successor in parent's subshape list **)
		parent*: Shape;	(** the shape this shape is a part of **)
		subshapes*: Shape;
		points*, realPoints: Point;
		polygons*, realPolygons: Polygon;
		lights*: Light;	(** local light sources **)
		T*: Matrix;	(** local transformation matrix (to be set by application) **)
		state*: SET;
		color*: Color;	(** shape surface color **)
		grayscale*: BOOLEAN;	(** use grayscale colors **)
		diffuse*: REAL;	(** coefficient for diffuse reflection **)
		speccoef*: REAL;	(** coefficien for specular reflection **)
		specexpo*: INTEGER;	(** exponent for specular reflection **)
		center: Vector;	(* center of bounding sphere in WC *)
		radius: REAL;	(* radius of bounding sphere *)
		cmd*: POINTER TO ARRAY 64 OF CHAR;	(** associated command string **)
	END;
	
	(* binary space partitioning tree nodes *)
	BSPNode = POINTER TO BSPNodeDesc;
	BSPNodeDesc = RECORD
		front, back: BSPNode;	(* subtrees on both sides *)
		poly: Polygon;	(* polygon which serves as splitting plane *)
	END;
	
	(** polygon world **)
	World* = POINTER TO WorldDesc;
	WorldDesc* = RECORD (Gadgets.ObjDesc)
		state*: SET;
		shape*: Shape;	(** the "world shape" **)
		bspTree: BSPNode;
		ambient*: REAL;	(** intensity of ambient light **)
		skyCol*, gndCol*: INTEGER;	(** color numbers for sky and ground **)
		horizon*: BOOLEAN;	(** flag whether to draw horizon or not **)
		time*: LONGINT;	(** time of selection **)
		selCount*: INTEGER;	(** number of selected shapes **)
		selShape*: Shape;	(** selected shape (if only one selected) **)
	END;
	
	(** view specification **)
	Camera* = RECORD
		fov*: REAL;	(** field of view angle **)
		pos*, u*, v*, w*: Vector;	(** camera position and coordinate axes **)
		zx, zy: REAL;	(* zoom factor in u and v direction *)
	END;


VAR
	identity*: Matrix;	(** transformation matrix containing identity transformation **)
	white*, black*: Color;	(** default color vectors **)
	executor*: Shape;	(** shape that issued a command **)
	pointPool: Point;	(* memory pools for frequently allocated structures *)
	refPool: PointRef;
	polyPool: Polygon;
	bspPool: BSPNode;
	W: Texts.Writer;
	NullVector: Vector;
	
	(* clipping planes *)
	clip: ARRAY nPlanes OF RECORD
		normal: Vector;	(* points away from view volume *)
		dist: REAL;	(* distance to origin *)
	END;
	
	(* dyn. Screen *)
	dynScreen: ARRAY numDynScreen OF Dim3Paint.DSEntry;
	tsList: Dim3Paint.TSEntry;


(*--- Errors ---*)

PROCEDURE Halt (cmd, msg: ARRAY OF CHAR);
BEGIN
	Texts.WriteString(W, "Dim3Engine."); Texts.WriteString(W, cmd); Texts.WriteString(W, ": ");
	Texts.WriteString(W, msg); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	HALT(127)
END Halt;


(**--- Memory Management of Frequently Used Structures ---**)
(** allocate new point **)
PROCEDURE NewPoint* (VAR p: Point);
BEGIN
	IF pointPool = NIL THEN
		NEW(p)
	ELSE
		p := pointPool;
		pointPool := pointPool.next;
		p.next := NIL
	END
END NewPoint;

(** allocate new point ref structure**)
PROCEDURE NewRef* (VAR ref: PointRef);
BEGIN
	IF refPool = NIL THEN
		NEW(ref)
	ELSE
		ref := refPool;
		refPool := refPool.next;
		ref.next := NIL;
		ref.light := NIL;
	END
END NewRef;

(** allocate new polygon structure**)
PROCEDURE NewPolygon* (VAR poly: Polygon);
BEGIN
	IF polyPool = NIL THEN
		NEW(poly)
	ELSE
		poly := polyPool;
		polyPool := polyPool.next;
		poly.next := NIL;
		poly.texture := NIL;
		poly.contour := NIL;
		poly.shape := NIL;
	END
END NewPolygon;

(** free point list to pool **)
PROCEDURE FreePointList* (p: Point);
VAR last: Point;
BEGIN
	IF p # NIL THEN
		last := p;
		WHILE last.next # NIL DO last := last.next END;
		last.next := pointPool; pointPool := p
	END
END FreePointList;

(** free point ref list to pool **)
PROCEDURE FreeRefList* (ref: PointRef);
BEGIN
	IF ref # NIL THEN
		ref.prev.next := refPool; refPool := ref
	END
END FreeRefList;

(** free polygon list to pool **)
PROCEDURE FreePolyList* (poly: Polygon);
VAR last: Polygon;
BEGIN
	IF poly # NIL THEN
		last := poly;
		WHILE last.next # NIL DO last := last.next END;
		last.next := polyPool; polyPool := poly
	END
END FreePolyList;

(** free structure pools **)
PROCEDURE ReleaseMem*;
BEGIN
	(* make structure pools empty => used memory can be collected by GC *)
	pointPool := NIL;
	refPool := NIL;
	polyPool := NIL
END ReleaseMem;


(** --- Arc tangent of y/x ---**)

PROCEDURE Atan2* (y, x: REAL): REAL;
BEGIN
	IF (ABS(x) < 1.0) & (ABS(y) >= ABS(x * MAX(REAL))) THEN	(* y / x would result in overflow/divide by zero trap *)
		IF y >= 0 THEN RETURN Math.pi/2
		ELSE RETURN -Math.pi/2
		END
	ELSIF x > 0 THEN	(* 1st or 4th quadrant *)
		RETURN Math.arctan(y / x)
	ELSIF x < 0 THEN	(* 2nd or 3rd quadrant *)
		RETURN Math.arctan(y / x) + Math.pi
	END
END Atan2;


(**--- Vector Operations ---**)

(* All routines use VAR parameters for efficiency, so beware of alias problems *)

PROCEDURE InitVector* (VAR v: Vector; x, y, z: REAL);
BEGIN
	v[0] := x; v[1] := y; v[2] := z
END InitVector;

PROCEDURE MakeVector* (VAR from, to, v: Vector);
BEGIN
	InitVector(v, to[0] - from[0], to[1] - from[1], to[2] - from[2])
END MakeVector;

(** cross product of two vectors **)
PROCEDURE CrossProd* (VAR u, v, w: Vector);
BEGIN
	w[0] := u[1] * v[2] - u[2] * v[1];
	w[1] := u[2] * v[0] - u[0] * v[2];
	w[2] := u[0] * v[1] - u[1] * v[0];
END CrossProd;

(**  dot product of two vectors **)
PROCEDURE DotProd* (VAR u, v: Vector): REAL;
BEGIN
	RETURN u[0]*v[0] + u[1]*v[1] + u[2]*v[2]
END DotProd;

(** scale vector to unit length **)
PROCEDURE Normalize* (VAR x: Vector);
CONST eps = 1.E-7;
VAR f: REAL;
BEGIN
	f := Math.sqrt(x[0]*x[0] + x[1]*x[1] + x[2]*x[2]);
	IF f >= eps THEN
		x[0] := x[0]/f; x[1] := x[1]/f; x[2] := x[2]/f
	END
END Normalize;

(* add vector y to vector x *)
PROCEDURE VectorSum (VAR x: Vector; y: Vector);
BEGIN
	x[0] := x[0] + y[0];
	x[1] := x[1] + y[1];
	x[2] := x[2] + y[2];
END VectorSum;

(* calculate distance between two points *)
PROCEDURE Distance (x, y: Vector):REAL;
VAR t1, t2, t0: REAL;
BEGIN
	t0 := x[0] - y[0]; t1 := x[1] - y[1]; t2 := x[2] - y[2];
	RETURN Math.sqrt(t0*t0 + t1*t1 + t2*t2);
END Distance;

PROCEDURE WriteVector (VAR R: Files.Rider; VAR v: Vector);
BEGIN
	Files.WriteReal(R, v[0]); Files.WriteReal(R, v[1]); Files.WriteReal(R, v[2])
END WriteVector;

PROCEDURE ReadVector (VAR R: Files.Rider; VAR v: Vector);
BEGIN
	Files.ReadReal(R, v[0]); Files.ReadReal(R, v[1]); Files.ReadReal(R, v[2])
END ReadVector;


(**--- Matrix Operations ---**)

(* All routines use VAR parameters for efficiency, so beware of alias problems *)

(** concat matrices A and B and store result in C **)
PROCEDURE ConcatMatrix* (VAR A, B, C: Matrix);
VAR i: INTEGER; a0, a1, a2: REAL;
BEGIN
	FOR i := 0 TO 2 DO
		a0 := A[i, 0]; a1 := A[i, 1]; a2 := A[i, 2];
		C[i, 0] := a0*B[0, 0] + a1*B[1, 0] + a2*B[2, 0];	(* + A[i, 3]*B[3, 0] = 0 *)
		C[i, 1] := a0*B[0, 1] + a1*B[1, 1] + a2*B[2, 1];	(* + A[i, 3]*B[3, 1] = 0 *)
		C[i, 2] := a0*B[0, 2] + a1*B[1, 2] + a2*B[2, 2];	(* + A[i, 3]*B[3, 2] = 0 *)
		C[i, 3] := a0*B[0, 3] + a1*B[1, 3] + a2*B[2, 3] + A[i, 3]
	END
END ConcatMatrix;

(** apply transformation matrix to vector **)
PROCEDURE Transform* (VAR M: Matrix; VAR x, y: Vector);
BEGIN
	y[0] := M[0, 0]*x[0] + M[0, 1]*x[1] + M[0, 2]*x[2] + M[0, 3];
	y[1] := M[1, 0]*x[0] + M[1, 1]*x[1] + M[1, 2]*x[2] + M[1, 3];
	y[2] := M[2, 0]*x[0] + M[2, 1]*x[1] + M[2, 2]*x[2] + M[2, 3]
END Transform;

(** compute rotation matrix **)
PROCEDURE GetRotation* (VAR M: Matrix; angle, x, y, z: REAL);
CONST eps = 1.E-10;
VAR s, c, t: REAL;
BEGIN
	t := Math.sqrt(x*x + y*y + z*z);
	IF t > eps THEN
		(* the following formula comes from: A. S. Glassner,  Graphic Gems, Addison-Wesley 1990, p. 466 (Rotation Tools) *)
		x := x/t; y := y/t; z := z/t;	(* normalize axis *)
		s := Math.sin(angle); c := Math.cos(angle); t := 1 - c;
		M[0, 0] := t*x*x + c; M[0, 1] := t*x*y - s*z; M[0, 2] := t*x*z + s*y; M[0, 3] := 0;
		M[1, 0] := t*y*x + s*z; M[1, 1] := t*y*y + c; M[1, 2] := t*y*z - s*x; M[1, 3] := 0;
		M[2, 0] := t*z*x - s*y; M[2, 1] := t*z*y + s*x; M[2, 2] := t*z*z + c; M[2, 3] := 0
	ELSE Halt("GetRotation", "axis is too short to be normalized")
	END
END GetRotation;

(* Translation and scaling matrices are much easier to create, so no GetTranslation/GetScale is provided *)

(*
 * The following three procedures append a transformation matrix to a given matrix. Because of the right to left evaluation
 * order of transformation matrices, the effect is that the new transformation becomes the first transformation applied
 * to a point. This is more convenient for maintaining a current transformation matrix (CTM) during the creation of sceneries
 * since it allows local transformations to be applied to subsequent point definitions independent of any inherited CTM.
 *)

(** prepend translation to transformation **)
PROCEDURE Translate* (VAR M: Matrix; dx, dy, dz: REAL);
VAR i: INTEGER; m0, m1, m2: REAL;
BEGIN
	FOR i := 0 TO 2 DO
		m0 := M[i, 0]; m1 := M[i, 1]; m2 := M[i, 2];
		M[i, 3] := M[i, 3] + m0*dx + m1*dy + m2*dz
	END
END Translate;

(** prepend rotation to transformation **)
PROCEDURE Rotate* (VAR M: Matrix; angle, x, y, z: REAL);
VAR R, Q: Matrix;
BEGIN
	GetRotation(R, angle, x, y, z);
	Q := M;
	ConcatMatrix(Q, R, M)
END Rotate;

(** prepend scale to transformation **)
PROCEDURE Scale* (VAR M: Matrix; sx, sy, sz: REAL);
VAR i: INTEGER;
BEGIN
	FOR i:= 0 TO 2 DO
		M[i, 0] := sx*M[i, 0];
		M[i, 1] := sy*M[i, 1];
		M[i, 2] := sz*M[i, 2]
	END
END Scale;

(**
 * Decompose matrix into rotation angle and axis, scale and translation vectors. In order to achieve the given transformation,
 * you first have to scale, then rotate and finally translate any given point. It is assumed that the matrix consists only of
 * concatenated rotations, translations and scaling transformations.
 **)
PROCEDURE Decompose* (VAR M: Matrix; VAR angle: REAL; VAR axis, scale, trans: Vector);
VAR i: INTEGER; sin, cos, m0, m1, m2: REAL;
BEGIN
	(* translation is easy: just copy the last column of M *)
	FOR i := 0 TO 2 DO
		trans[i] := M[i, 3]
	END;
	
	(*
	 * Consider applying M (without translation) to the unit vectors (1 0 0), (0 1 0) and (0 0 1)
	 * => the resulting vectors are the columns of M. We can find the scaling factors along each axis by calculating the
	 * length of the transformed unit vectors.
	 *)
	FOR i := 0 TO 2 DO
		m0 := M[0, i]; m1 := M[1, i]; m2 := M[2, i];
		scale[i] := Math.sqrt(m0*m0 + m1*m1 + m2*m2)
	END;
	
	(* calculate angle (see A. S. Glassner,  Graphic Gems, Addison-Wesley 1990, pp. 466 (Rotation Tools)) *)
	cos := 0.5 * (M[0, 0]/scale[0] + M[1, 1]/scale[1] + M[2, 2]/scale[2] - 1.0);
	sin := Math.sqrt(ABS(1.0 - cos*cos));
	angle := Atan2(sin, cos);
	
	(* get axis *)
	IF sin > 1.0E-6 THEN
		axis[0] := 0.5 * (M[1, 2]/scale[2] - M[2, 1]/scale[1]) / sin;
		axis[1] := 0.5 * (M[2, 0]/scale[0] - M[0, 2]/scale[2]) / sin;
		axis[2] := 0.5 * (M[0, 1]/scale[1] - M[1, 0]/scale[0]) / sin
	ELSE
		InitVector(axis, 0, 0, 0)
	END
END Decompose;

PROCEDURE WriteMatrix (VAR R: Files.Rider; VAR M: Matrix);
VAR i, j: INTEGER;
BEGIN
	FOR i := 0 TO 2 DO
		FOR j := 0 TO 3 DO
			Files.WriteReal(R, M[i, j])
		END
	END
END WriteMatrix;

PROCEDURE ReadMatrix (VAR R: Files.Rider; VAR M: Matrix);
VAR i, j: INTEGER;
BEGIN
	FOR i := 0 TO 2 DO
		FOR j := 0 TO 3 DO
			Files.ReadReal(R, M[i, j])
		END
	END
END ReadMatrix;


(**--- Colors ---**)

PROCEDURE InitColor* (VAR col: Color; r, g, b: REAL);
BEGIN
	col[0] := r; col[1] := g; col[2] := b
END InitColor;


(**--- Points ---**)

PROCEDURE InitPoint* (p: Point; x, y, z: REAL);
BEGIN
	InitVector(p.wc, x, y, z);
	p.next := NIL
END InitPoint;

PROCEDURE WritePoint (VAR R: Files.Rider; p: Point);
BEGIN
	WriteVector(R, p.wc);	(* it's sufficient to store world coordinates, since the rest will be recalculated anyway *)
END WritePoint;

PROCEDURE ReadPoint (VAR R: Files.Rider; p: Point);
BEGIN
	ReadVector(R, p.wc)
END ReadPoint;


(**--- Contours ---**)

(** append point reference to contour, inten = light intensity in point (if known) **)
PROCEDURE AppendPoint* (VAR contour: PointRef; p: Point);
VAR ref: PointRef;
BEGIN
	NewRef(ref); ref.p := p; ref.inten := 0; ref.light := NIL;
	IF contour = NIL THEN	(* first point *)
		contour := ref;
		ref.next := ref;
		ref.prev := ref
	ELSE
		ref.next := contour;
		ref.prev := contour.prev;
		ref.prev.next := ref;
		ref.next.prev := ref
	END
END AppendPoint;

(** append point reference to contour and texture coordinates **)
PROCEDURE AppendTexturePoint* (VAR contour: PointRef; p: Point; u, v: REAL);
VAR ref: PointRef;
BEGIN
	NewRef(ref); ref.p := p; ref.u := u; ref.v := v; ref.inten := 0; ref.light := NIL;
	IF contour = NIL THEN	(* first point *)
		contour := ref;
		ref.next := ref;
		ref.prev := ref
	ELSE
		ref.next := contour;
		ref.prev := contour.prev;
		ref.prev.next := ref;
		ref.next.prev := ref
	END
END AppendTexturePoint;

(* append point reference to contour, inten = light intensity in point (if known) *)
PROCEDURE AppTextPointSpecial (VAR contour: PointRef; p: Point; inten, u, v: REAL);
VAR ref: PointRef;
BEGIN
	NewRef(ref); ref.p := p; ref.u := u; ref.v := v; ref.inten := inten; ref.light := NIL;
	IF contour = NIL THEN	(* first point *)
		contour := ref;
		ref.next := ref;
		ref.prev := ref
	ELSE
		ref.next := contour;
		ref.prev := contour.prev;
		ref.prev.next := ref;
		ref.next.prev := ref
	END
END AppTextPointSpecial;

(* append point reference to contour, inten = light intensity in point (if known) *)
PROCEDURE AppPointSpecial (poly: Polygon; VAR contour: PointRef; p: Point; inten: REAL; lightRef: LightRef);
VAR ref: PointRef; newLight: LightRef; k: REAL; normal, dir: Vector; l: Light;
BEGIN
	NewRef(ref); ref.p := p; ref.inten := inten; ref.light := NIL;
	
	WHILE lightRef # NIL DO	(* recalculate data for specular reflection *)
		NEW(newLight);
		newLight.light := lightRef.light; l := lightRef.light;
		IF smooth IN poly.shape.state THEN normal := ref.p.normal ELSE normal := poly.normal END;
		Normalize(normal);
		IF l.type = PointLight THEN
			MakeVector(p.wc, l.dir, dir); Normalize(dir);
			k := DotProd(normal, dir) * 2;
			IF k > 0.0 THEN
				newLight.R[0] := normal[0] * k - dir[0]; newLight.R[1] := normal[1] * k - dir[1]; 
				newLight.R[2] := normal[2] * k - dir[2];
				newLight.factor := poly.shape.speccoef / (Distance(l.dir, p.wc) * DistSpec);
				Normalize(newLight.R);
			ELSE
				newLight.factor := 0
			END;
		ELSE
			k :=  DotProd(normal, l.dir) * 2;
			newLight.R[0] := normal[0] * k - l.dir[0]; newLight.R[1] := normal[1] * k - l.dir[1]; 
			newLight.R[2] := normal[2] * k - l.dir[2];
			IF k > 0.0 THEN
				newLight.R[0] := normal[0] * k - l.dir[0]; newLight.R[1] := normal[1] * k - l.dir[1]; 
				newLight.R[2] := normal[2] * k - l.dir[2];
				newLight.factor := poly.shape.speccoef;
				Normalize(newLight.R);
			ELSE
				newLight.factor := 0
			END;
		END;
		newLight.next := ref.light; ref.light := newLight;
		lightRef := lightRef.next;
	END;
	
	IF contour = NIL THEN	(* first point *)
		contour := ref;
		ref.next := ref;
		ref.prev := ref
	ELSE
		ref.next := contour;
		ref.prev := contour.prev;
		ref.prev.next := ref;
		ref.next.prev := ref
	END
END AppPointSpecial;

(* clip a list of point references to the field of view of a camera *)
PROCEDURE ClipPoly (contour: PointRef; VAR x, y, w, i, spec, u, v: ARRAY OF REAL; VAR n: INTEGER; shade, texture: BOOLEAN);
VAR
	s, f: ARRAY nPlanes OF PointRef; first, inside: ARRAY nPlanes OF BOOLEAN; dist, fdist: ARRAY nPlanes OF REAL;
	isList, ref: PointRef; 
	
	PROCEDURE Intersection (pRef, qRef: PointRef; dp, dq: REAL): PointRef;
	CONST eps = 1.E-7;
	VAR s, t, x, y, z: REAL; r, p, q: Point; rRef: PointRef;
	BEGIN
		p := pRef.p; q := qRef.p;
		(* the intersection is a linear combination of p and q, whose distances to p and q are dp and dq *)
		IF ABS(dp) < eps THEN
			RETURN pRef
		ELSIF ABS(dq) < eps THEN
			RETURN qRef
		ELSE	(* true intersection *)
			t := dp / (dp - dq); s := 1 - t;
			x := s*p.vrc[0] + t*q.vrc[0];
			y := s*p.vrc[1] + t*q.vrc[1];
			z := s*p.vrc[2] + t*q.vrc[2];
			NewPoint(r); InitVector(r.vrc, x, y, z);
			NEW(rRef); rRef.p := r;
			rRef.inten := s*pRef.inten + t*qRef.inten;
			rRef.specular := s*pRef.specular + t*qRef.specular;
			IF texture THEN rRef.u := s * pRef.u + t * qRef.u; rRef.v := s * pRef.v + t * qRef.v END;
			rRef.next := isList; isList := rRef;
			RETURN rRef
		END
	END Intersection;
		
	PROCEDURE Clip (plane: INTEGER; ref: PointRef);
	VAR p: Point; d: REAL; in: BOOLEAN; isRef: PointRef;
	BEGIN
		p := ref.p;
		IF plane = nPlanes THEN	(* p is inside all clipping planes => append to clipped polygon *)
			(* apply perspective transformation *)
			x[n] := -p.vrc[0]/p.vrc[2];
			y[n] := -p.vrc[1]/p.vrc[2];
			i[n] := ref.inten; spec[n] := ref.specular;
			IF texture THEN u[n] := ref.u; v[n] := ref.v; w[n] := -p.vrc[2] END;
			INC(n);
			RETURN
		END;
		
		IF first[plane] THEN	(* p is the first point that reaches the current clipping plane *)
			first[plane] := FALSE; s[plane] := ref; f[plane] := ref;
			dist[plane] := DotProd(p.vrc, clip[plane].normal) + clip[plane].dist;
			fdist[plane] := dist[plane];
			in := dist[plane] <= 0; inside[plane] := in;	(* used to be compiler bug in DOS-Oberon, simplify when fixed *)
		
		ELSE
			d := DotProd(p.vrc, clip[plane].normal) + clip[plane].dist;
			in := d <= 0;
			IF in # inside[plane] THEN	(* p and previous point are on different sides of the clipping plane *)
				isRef := Intersection(s[plane], ref, dist[plane], d);
				inside[plane] := in;
				Clip(plane+1, isRef)
			END;
			s[plane] := ref; dist[plane] := d;
		END;
		
		(* propagate visible points to next clipping plane *)
		IF inside[plane] THEN Clip(plane+1, s[plane]) END
	END Clip;
	
	PROCEDURE Close (plane: INTEGER);
	VAR isRef: PointRef;
	BEGIN
		IF plane < nPlanes THEN
			IF ~first[plane] & (inside[plane] # (fdist[plane] <= 0)) THEN	(* create intersection between last and first point *)
				isRef := Intersection(s[plane], f[plane], dist[plane], fdist[plane]);
				Clip(plane+1, isRef)
			END;
			Close(plane+1)
		END
	END Close;

BEGIN
	(* The procedure uses the well known Sutherland-Hodgman polygon clipping algorithm (CACM 17(1), 1974) *)
	n := 0;
	WHILE n < nPlanes DO
		first[n] := TRUE;
		INC(n)
	END;
	
	isList := NIL;
	n := 0;
	ref := contour;
	REPEAT
		Clip(0, ref);
		ref := ref.next
	UNTIL (ref = contour) OR (n = LEN(x));
	Close(0);
END ClipPoly;

(**--- Textures ---**)

(** build the texture for a string **)
PROCEDURE InitStringTexture* (poly: Polygon; string, font: ARRAY OF CHAR; col, backCol: Color; transparent: BOOLEAN);
VAR P: Pictures.Picture; width, height, i, dx, x, y, w, h, fontCol, bgCol, X: INTEGER; F: Fonts.Font; pat: LONGINT;
BEGIN
	(* calculate size of picture for the string *)
	F := Fonts.This(font);
	IF F = NIL THEN F := Fonts.Default END;
	height := F.height + 6; width := 6;
	i := 0;
	WHILE (i < MaxString) & (string[i] # EOS) DO
		Fonts.GetChar(F, string[i], dx, x, y, w, h, pat);
		INC(width, dx);
		INC(i);
	END;

	(* generate texture for the string *)
	fontCol := 240; bgCol := 16;
	NEW(P);
	Pictures.Create(P,width, height, 8);
	Pictures.SetColor(P, fontCol, SHORT(ENTIER(col[0] * 255.99)), SHORT(ENTIER(col[1] * 255.99)), SHORT(ENTIER(col[2] * 255.99)));
	Pictures.SetColor(P, bgCol, SHORT(ENTIER(backCol[0] * 255.99)), SHORT(ENTIER(backCol[1] * 255.99)), SHORT(ENTIER(backCol[2] * 255.99)));
	
	Pictures.ReplConst(P, bgCol, 0, 0, width, height, Display.replace);
	i := 0; X := 3; 
	WHILE (i < MaxString) & (string[i] # EOS) DO
		Fonts.GetChar(F, string[i], dx, x, y, w, h, pat);
		Pictures.CopyPattern(P, fontCol, pat, X+x, y-F.minY +3, Display.paint);
		INC(X, dx); INC(i);
	END;
	
	NEW(poly.texture);
	poly.texture.basePict := P;
	poly.texture.transparent := transparent;
	poly.texture.stringTexture := TRUE;
	COPY(string, poly.texture.name);
	COPY(font, poly.texture.font);
	poly.texture.fontCol := col; poly.texture.backCol := backCol;
	Texts.Append(Oberon.Log, W.buf);
END InitStringTexture;

(** calculate and init the texture of the polygon **)
PROCEDURE InitTexture* (poly: Polygon; name: ARRAY OF CHAR; transparent: BOOLEAN);
VAR P: Pictures.Picture;
BEGIN
	NEW(P);
	Pictures.Open(P,name, TRUE);
	IF P # NIL THEN
		NEW(poly.texture);
		poly.texture.basePict := P;
		poly.texture.transparent := transparent;
		poly.texture.stringTexture := FALSE;
		COPY(name, poly.texture.name)
	ELSE
		poly.texture := NIL
	END;
END InitTexture;

PROCEDURE WriteTexture (VAR R: Files.Rider; poly: Polygon);
VAR texture: Texture;
BEGIN
	texture := poly.texture;
	Files.WriteBool(R, texture.stringTexture);
	Files.WriteBool(R, texture.transparent);
	IF texture.stringTexture THEN
		Files.WriteReal(R, texture.fontCol[0]); Files.WriteReal(R, texture.fontCol[1]); Files.WriteReal(R, texture.fontCol[2]);
		Files.WriteReal(R, texture.backCol[0]); Files.WriteReal(R, texture.backCol[1]); Files.WriteReal(R, texture.backCol[2]);
		Files.WriteString(R, texture.name); Files.WriteString(R, texture.font);
	ELSE
		Files.WriteString(R, texture.name);
	END
END WriteTexture;

PROCEDURE ReadTexture (VAR R: Files.Rider; poly: Polygon);
VAR stringTexture, transp: BOOLEAN; fontCol, backCol: Color; name, font: ARRAY MaxString OF CHAR;
BEGIN
	Files.ReadBool(R, stringTexture);
	Files.ReadBool(R, transp);
	IF stringTexture THEN
		Files.ReadReal(R, fontCol[0]); Files.ReadReal(R, fontCol[1]); Files.ReadReal(R, fontCol[2]);
		Files.ReadReal(R, backCol[0]); Files.ReadReal(R, backCol[1]); Files.ReadReal(R, backCol[2]);
		Files.ReadString(R, name); Files.ReadString(R, font);
		InitStringTexture(poly, name, font, fontCol, backCol, transp);
	ELSE
		Files.ReadString(R, name);
		InitTexture(poly, name, transp);
	END;
END ReadTexture;


(**--- Polygons ---**)

PROCEDURE InitPolygon* (poly: Polygon);
BEGIN
	poly.contour := NIL;
	poly.shape := NIL;
	poly.texture := NIL;
END InitPolygon;

(* compute iteratively the normals of the shape points *)
PROCEDURE CalcPointNormals(normal: Vector; contour: PointRef);
VAR ref: PointRef;
BEGIN
	ref := contour;
	IF contour = NIL THEN RETURN END;
	REPEAT
		VectorSum(ref.p.normal,normal);
		ref := ref.next;
	UNTIL (ref = contour) OR (ref = NIL);
END CalcPointNormals;

(* compute plane equation of a polygon *)
PROCEDURE CalcPlane (poly: Polygon);
VAR p, q, r: Point; ref: PointRef; u, v: Vector;
BEGIN
	(* Take the cross product of the first two edge vectors. They are assumed to form a left turn, seen from above *)
	ref := poly.contour; p := ref.p;
	ref := ref.next; q := ref.p;
	ref := ref.next; r := ref.p;
	MakeVector(p.wc, q.wc, u); MakeVector(p.wc, r.wc, v);
	CrossProd(u, v, poly.normal);
	Normalize(poly.normal);
	poly.dist := -DotProd(poly.normal, p.wc);
	CalcPointNormals(poly.normal,poly.contour)
END CalcPlane;

PROCEDURE WritePoly (VAR R: Files.Rider; poly: Polygon);
VAR ref: PointRef; p: Point; n: INTEGER; texture: BOOLEAN;
BEGIN
	texture := poly.texture # NIL;
	Files.WriteBool(R, texture);
	IF texture THEN WriteTexture(R, poly) END;
	(* the contour of the polygon is saved a sequence of point numbers *)
	ref := poly.contour;
	REPEAT
		(* compute point number *)
		p := poly.shape.realPoints;
		n := 0;
		WHILE p # ref.p DO
			INC(n);
			p := p.next
		END;
		Files.WriteInt(R, n);
		IF texture THEN	(* write texture coordinates *)
			Files.WriteReal(R, ref.u); Files.WriteReal(R, ref.v);
		END;
		ref := ref.next
	UNTIL ref = poly.contour;
	Files.WriteInt(R, -1)
END WritePoly;

PROCEDURE ReadPoly (VAR R: Files.Rider; poly: Polygon);
VAR n: INTEGER; p: Point; texture: BOOLEAN; u, v:REAL;
BEGIN
	Files.ReadBool(R, texture);
	IF texture THEN ReadTexture(R, poly) END;
	Files.ReadInt(R, n);
	WHILE n >= 0 DO
		p := poly.shape.points;
		WHILE n > 0 DO
			p := p.next;
			DEC(n)
		END;
		IF texture THEN
			Files.ReadReal(R, u); Files.ReadReal(R, v);
			AppendTexturePoint(poly.contour, p, u, v)
		ELSE 
			AppendPoint(poly.contour, p);
		END;
		Files.ReadInt(R, n)
	END
END ReadPoly;


(**--- Binary Space Partitioning Trees ---**)

(* split polygon along plane into front and back part *)
PROCEDURE BSPSplit (bsp: BSPNode; poly: Polygon; VAR front, back: Polygon);
CONST eps = 1.0E-5;
VAR
	dcur, dpred, dmin, dmax, s, t, u, v, inten: REAL; cur, pred, frontList, backList: PointRef; curP, predP, is, isList: Point;
	plane: Polygon; shape: Shape;
BEGIN
	plane := bsp.poly;
	pred := poly.contour.prev;
	dpred := DotProd(plane.normal, pred.p.wc) + plane.dist;
	
	(* check for parallel planes *)
	IF ABS(ABS(DotProd(plane.normal, poly.normal)) - 1) < 1.0E-7 THEN	(* normals are colinear *)
		IF dpred >= 0 THEN
			front := poly; back := NIL
		ELSE
			back := poly; front := NIL
		END;
		RETURN
	END;
	
	frontList := NIL; backList := NIL; isList := NIL;
	dmin := MAX(REAL); dmax := MIN(REAL);	(* largest distances of points from plane *)
	cur := poly.contour;
	REPEAT
		dcur := DotProd(plane.normal, cur.p.wc) + plane.dist;
		IF dcur < dmin THEN
			dmin := dcur
		END;
		IF dcur > dmax THEN
			dmax := dcur
		END;
		IF dcur * dpred < 0 THEN	(* add intersection to both lists *)
			t := dcur / (dcur - dpred); s := 1 - t;
			curP := cur.p; predP := pred.p;
			NewPoint(is);
			is.wc[0] := s * curP.wc[0] + t * predP.wc[0];
			is.wc[1] := s * curP.wc[1] + t * predP.wc[1];
			is.wc[2] := s * curP.wc[2] + t * predP.wc[2];
			is.normal[0] := s * curP.normal[0] + t * predP.normal[0];
			is.normal[1] := s * curP.normal[1] + t * predP.normal[1];
			is.normal[2] := s * curP.normal[2] + t * predP.normal[2];
			inten := s * cur.inten + t * pred.inten;
			is.next := isList; isList := is;
			IF poly.texture = NIL THEN
				AppPointSpecial(poly, frontList, is, inten, cur.light);
				AppPointSpecial(poly, backList, is, inten, cur.light)
			ELSE
				u := s * cur.u + t * pred.u;
				v := s * cur.v + t * pred.v;
				AppTextPointSpecial(frontList, is, inten, u, v);
				AppTextPointSpecial(backList, is, inten, u, v)
			END;
		END;
		IF dcur >= 0 THEN	(* add cur to front list *)
			IF poly.texture = NIL THEN
				AppPointSpecial(poly, frontList, cur.p, cur.inten, cur.light)
			ELSE
				AppTextPointSpecial(frontList, cur.p, cur.inten, cur.u, cur.v)
			END;
		END;
		IF dcur <= 0 THEN	(* add cur to back list *)
			IF poly.texture = NIL THEN
				AppPointSpecial(poly, backList, cur.p, cur.inten, cur.light)
			ELSE
				AppTextPointSpecial(backList, cur.p, cur.inten, cur.u, cur.v)
			END;
		END;
		dpred := dcur; pred := cur; cur := cur.next
	UNTIL cur = poly.contour;

	IF dmax < eps THEN	(* poly is on negative side of plane *)
		back := poly; front := NIL;
		FreeRefList(frontList); FreeRefList(backList); FreePointList(isList)
	ELSIF -dmin < eps THEN	(* poly is on positive side of plane *)
		front := poly; back := NIL;
		FreeRefList(frontList); FreeRefList(backList); FreePointList(isList)
	ELSE	(* plane splits poly in two => create two new polygons *)
		shape := poly.shape;
		WHILE isList # NIL DO	(* append intersection points to shape points *)
			is := isList.next; isList.next := shape.points; shape.points := isList; isList := is
		END;
		NewPolygon(front); front^ := poly^; front.contour := frontList; front.next := shape.polygons; shape.polygons := front;
		NewPolygon(back); back^ := poly^; back.contour := backList; back.next := shape.polygons; shape.polygons := back
	END;
END BSPSplit;

(* insert polygon into BSP tree *)
PROCEDURE BSPInsert (VAR bsp: BSPNode; poly: Polygon);
VAR front, back: Polygon;
BEGIN
	IF bsp = NIL THEN	(* add new leaf node *)
		IF bspPool = NIL THEN NEW(bsp) ELSE bsp := bspPool; bspPool := bspPool.front END;
		bsp.front := NIL; bsp.back := NIL; bsp.poly := poly
	
	ELSE	(* split poly and insert parts *)
		BSPSplit(bsp, poly, front, back);
		IF front # NIL THEN BSPInsert(bsp.front, front) END;
		IF back # NIL THEN BSPInsert(bsp.back, back) END
	END
END BSPInsert;

(* return BSP nodes to memory pool *)
PROCEDURE BSPFree (bsp: BSPNode);
BEGIN
	IF bsp # NIL THEN
		BSPFree(bsp.front);
		BSPFree(bsp.back);
		bsp.front := bspPool; bspPool := bsp
	END
END BSPFree;


(** return frontmost polygon that intersects given ray; x, y are taken as normalized picture coordinates (-1..1) **)
PROCEDURE FrontPolygon* (w: World; VAR C: Camera; x, y: REAL): Polygon;
VAR dir: Vector; i: INTEGER;

	PROCEDURE Frontmost (bsp: BSPNode): Polygon;
	CONST eps = 1.0E-4;
	VAR
		front, back: BSPNode; visible: BOOLEAN; nom, denom, t, cphi, sum: REAL; poly: Polygon;
		v, p, q: Vector; ref: PointRef;
	BEGIN
		IF bsp # NIL THEN
			IF DotProd(C.pos, bsp.poly.normal) + bsp.poly.dist <= 0 THEN	(* polygon faces away from viewer *)
				front := bsp.back; back := bsp.front;
				visible := FALSE
			ELSE	(* polygon faces viewer *)
				front := bsp.front; back := bsp.back;
				visible := TRUE
			END;
			
			poly := Frontmost(front);	(* try to find shape nearer to the viewer *)
			IF poly = NIL THEN
				IF visible THEN	(* intersect ray with bsp.poly *)
					denom := DotProd(bsp.poly.normal, dir);
					IF ABS(denom) > eps THEN	(* polygon is not seen edge-on *)
						nom := DotProd(bsp.poly.normal, C.pos) + bsp.poly.dist;
						t := -nom / denom;
						IF t > 0 THEN	(* intersection is in front of viewer *)
							InitVector(v, C.pos[0] + t*dir[0], C.pos[1] + t*dir[1], C.pos[2] + t*dir[2]);
							ref := bsp.poly.contour;
							MakeVector(v, ref.prev.p.wc, q); Normalize(q);
							sum := 0.0;
							REPEAT
								MakeVector(v, ref.p.wc, p); Normalize(p);
								cphi := DotProd(p, q);
								sum := sum + Atan2(Math.sqrt(ABS(1.0 - cphi*cphi)), cphi);
								q := p; ref := ref.next
							UNTIL ref = bsp.poly.contour;
							IF ABS(ABS(sum) - 2.0*Math.pi) < eps THEN	(* intersection is inside polygon *)
								poly := bsp.poly
							END
						END
					END
				END;
				
				IF poly = NIL THEN	(* poly is backface (invisible) or intersection is not within poly.contour *)
					poly := Frontmost(back)
				END
			END;
			RETURN poly
			
		ELSE
			RETURN NIL
		END
	END Frontmost;

BEGIN
	(* compute ray from camera position to point (x, y) in view plane *)
	x := x/C.zx; y := y/C.zy;	(* account for zoomed pictures *)
	FOR i := 0 TO 2 DO
		dir[i] := -C.w[i] + x*C.u[i] + y*C.v[i]
	END;
	RETURN Frontmost(w.bspTree)
END FrontPolygon;

(* calculate specular reflection for a polygon*)
PROCEDURE CalcSpecularReflection (poly: Polygon; N: Matrix);
VAR ref: PointRef; lightRef: LightRef; V, R: Vector; t:REAL;
BEGIN
	(* initialize point intensities *)
	ref := poly.contour;
	IF ref # NIL THEN
		REPEAT
			MakeVector(ref.p.vrc, NullVector, V);
			Normalize(V);
			ref.specular := 0; 
			lightRef := ref.light;
			WHILE lightRef # NIL DO
				Transform(N, lightRef.R, R);
				Normalize(R);
				t := DotProd(R, V);
				IF t < 0.05 THEN t := 0 ELSE t :=  Math.exp(poly.shape.specexpo * Math.ln(t)) * lightRef.factor END;
				ref.specular := ref.specular + t;
				lightRef := lightRef.next
			END;
			ref := ref.next;
		UNTIL (ref = poly.contour) OR (ref = NIL)
	END;
END CalcSpecularReflection;

(* render polygons in back to front order in picture*)
PROCEDURE DrawBSPDirect (bsp: BSPNode; VAR C: Camera; P: Pictures.Picture; N: Matrix);
VAR
	poly: Polygon; drawFront, drawBack: BOOLEAN;
	n: INTEGER; x, y, w, i,s, u, v: ARRAY maxVertices OF REAL; ref: PointRef; p: Point;
	cos, t, D: REAL;  col: ARRAY 3 OF REAL;
BEGIN
	IF bsp # NIL THEN
		(*
		 * If a BSPT node's plane does not intersect the view volume at all, one of the node's subtrees is completely
		 * invisible. There is no intersection if the polygon crosses the view plane normal w behind the camera and
		 * the angle between w and the plane normal is small enough so that the plane can't intersect the view volume.
		 *)
		drawFront := TRUE; drawBack := TRUE;
		poly := bsp.poly;
		D := DotProd(poly.normal, C.pos) + poly.dist;
		cos := DotProd(C.w, poly.normal);	(* cosine of angle between (normalized!) vectors C.w and poly.normal *)
		t := C.zx*C.zx + C.zy*C.zy;	(* largest distance from midpoint of view plane to its boundary *)
		t := Math.sqrt(t / (1.0 + t));	(* sine of largest angle between w-axis and a vertex on the view plane boundary *)
		IF ABS(cos) > t THEN	(* if this is true, poly's plane cannot intersect the view volume *)
			t := -D/cos;
			IF t >= 0 THEN	(* poly crosses w-axis behind viewer => can prune one subtree *)
				IF cos > 0 THEN
					drawFront := FALSE
				ELSE
					drawBack := FALSE
				END
			END
		END;
		
		IF (D > 0)  THEN	(* polygon faces camera *)
			IF drawFront THEN
				DrawBSPDirect(bsp.front, C, P, N)
			END;
			IF ~(invisible IN poly.shape.state) THEN
				IF (poly.texture = NIL) & (gouraud IN poly.shape.state) & (specular IN poly.shape.state) THEN CalcSpecularReflection(poly, N) END;
				IF mustClip IN poly.shape.state THEN
					ClipPoly(poly.contour, x, y, w, i, s, u, v, n, TRUE, poly.texture # NIL)
				ELSE
					n := 0; ref := poly.contour;
					REPEAT
						p := ref.p;
						(* apply perspective transformation *)
						x[n] := -p.vrc[0]/p.vrc[2];
						y[n] := -p.vrc[1]/p.vrc[2];
						i[n] := ref.inten; s[n] := ref.specular; 
						u[n] := ref.u; v[n] := ref.v; w[n] := -p.vrc[2];
						ref := ref.next;
						INC(n)
					UNTIL (ref = poly.contour) OR (n = LEN(x))
				END;
				IF n > 1 THEN
					IF poly.texture = NIL THEN
						IF gouraud IN poly.shape.state THEN
							col[0] := poly.shape.color[0];
							col[1] := poly.shape.color[1];
							col[2] := poly.shape.color[2];
							Dim3Paint.DrawShadePoly(P, dynScreen, col, poly.col, poly.shape.grayscale, FALSE, selected IN poly.shape.state, 
															dither IN poly.shape.state, specular IN poly.shape.state, x, y, i, s, n)
						ELSE
							Dim3Paint.DrawShadePoly(P, dynScreen, col, poly.col, poly.shape.grayscale, TRUE, selected IN poly.shape.state, 
															FALSE, FALSE, x, y, i, s, n)
						END;
					ELSE
						Dim3Paint.DrawPersTexture(P, dynScreen, poly.texture.shadedPict, poly.texture.numPict,
															selected IN poly.shape.state, poly.texture.transparent , tsList, x, y, w, u, v, poly.col, n)
					END;
				END;	
			END;
			IF drawBack THEN
				DrawBSPDirect(bsp.back, C, P, N)
			END;
		
		ELSE	(* polygon faces away from camera => don't draw it *)
			IF drawBack THEN
				DrawBSPDirect(bsp.back, C, P, N)
			END;
			(* draw transparent texture polygon also on the back side *)
			IF (~(invisible IN poly.shape.state))  & (poly.texture # NIL) & poly.texture.transparent THEN
				IF mustClip IN poly.shape.state THEN
					ClipPoly(poly.contour, x, y, w, i, s, u, v, n, TRUE, poly.texture # NIL)
				ELSE
					n := 0; ref := poly.contour;
					REPEAT
						p := ref.p;
						(* apply perspective transformation *)
						x[n] := -p.vrc[0]/p.vrc[2];
						y[n] := -p.vrc[1]/p.vrc[2];
						u[n] := ref.u; v[n] := ref.v; w[n] := -p.vrc[2];
						ref := ref.next;
						INC(n)
					UNTIL (ref = poly.contour) OR (n = LEN(x))
				END;
				IF n > 1 THEN
					Dim3Paint.DrawPersTexture(P, dynScreen, poly.texture.shadedPict, poly.texture.numPict,
															selected IN poly.shape.state, poly.texture.transparent , tsList, x, y, w, u, v, poly.col, n)
				END;	
			END;
			IF drawFront THEN
				DrawBSPDirect(bsp.front, C, P, N)
			END;
		END
	END
END DrawBSPDirect;

(**--- Lights ---**)
(** Initialisation of light sources; point light -> type = PointLight; direct light -> type = DirectLight **)
PROCEDURE InitLight* (l: Light; type: INTEGER; VAR dir: Vector; inten: REAL);
BEGIN
	l.dir := dir; l.next := NIL;
	IF inten > 1.0 THEN l.inten := 1.0 ELSIF inten < 0.0 THEN l.inten := 0.0 ELSE l.inten := inten END;
	IF type= PointLight THEN 
		l.type := PointLight;
	ELSE 
		l.type := DirectLight;
		l.dir[0] := -l.dir[0]; l.dir[1] := -l.dir[1]; l.dir[2] := -l.dir[2];	(* change direction of light, from point to light source *)
		Normalize(l.dir);
	END;
END InitLight;

PROCEDURE WriteLight (VAR R: Files.Rider; l: Light);
BEGIN
	Files.WriteInt(R, l.type);  
	WriteVector(R, l.dir); 
	Files.WriteReal(R, l.inten);
END WriteLight;

PROCEDURE ReadLight (VAR R: Files.Rider; l: Light);
BEGIN
	Files.ReadInt(R, l.type);  
	ReadVector(R, l.dir);
	Files.ReadReal(R, l.inten);
END ReadLight;


(**--- Shapes ---**)

(** Shapes are not real objects (this would probably be overkill), nevertheless, they can handle Attribute messages **)
PROCEDURE HandleShapeAttr* (s: Shape; VAR M: Objects.AttrMsg);
VAR n, r, g, b: INTEGER; sub: Shape;
	  col: ARRAY 3 OF REAL;
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Cmd" THEN
			M.class := Objects.String; M.res := 0;
			IF s.cmd # NIL THEN
				COPY(s.cmd^, M.s)
			ELSE
				M.s := ""
			END
		ELSIF M.name = "Color" THEN
			M.class := Objects.Int;
			col[0] := s.color[0]; col[1] := s.color[1]; col[2] := s.color[2];
			n := Dim3Paint.GetColor(col,1, FALSE);
			M.i := n; M.res := 0
		ELSIF M.name = "Diffuse" THEN
			M.class := Objects.Real; M.x := ENTIER(1024*s.diffuse + 0.5)/1024.0; M.res := 0
		ELSIF M.name = "Speccoef" THEN
			M.class := Objects.Real; M.x := ENTIER(1024*s.speccoef + 0.5)/1024.0; M.res := 0
		ELSIF M.name = "Specexpo" THEN
			M.class := Objects.Int; M.i := s.specexpo; M.res := 0
		END
	ELSIF M.id = Objects.set THEN
		IF (M.name = "Cmd") & (M.class = Objects.String) THEN
			IF s.cmd = NIL THEN NEW(s.cmd) END;
			COPY(M.s, s.cmd^);
			M.res := 0
		ELSIF (M.name = "Color") & (M.class = Objects.Int) THEN
			Display.GetColor(SHORT(M.i), r, g, b);
			InitColor(s.color, r/255, g/255, b/255);
			sub := s.subshapes;
			WHILE sub # NIL DO
				IF selected IN sub.state THEN HandleShapeAttr(sub, M) END;
				sub := sub.next
			END;
			M.res := 1
		ELSIF M.name = "Diffuse" THEN
			IF M.class = Objects.Real THEN
				s.diffuse := M.x; M.res := 1
			ELSIF M.class = Objects.LongReal THEN
				s.diffuse := SHORT(M.y); M.res := 1
			END
		ELSIF M.name = "Speccoef" THEN
			IF M.class = Objects.Real THEN
				s.speccoef := M.x; M.res := 1
			ELSIF M.class = Objects.LongReal THEN
				s.speccoef := SHORT(M.y); M.res := 1
			END
		ELSIF M.name = "Specexpo" THEN
			IF M.class = Objects.Int THEN
				s.specexpo := SHORT(M.i); M.res := 1
			ELSIF M.class = Objects.Real THEN
				s.specexpo := SHORT(ENTIER(M.x)); M.res := 1
			END;
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Cmd"); M.Enum("Color"); M.Enum("Diffuse"); M.Enum("Speccoef"); M.Enum("Specexpo"); M.res := 0
	END
END HandleShapeAttr;

(** set shading method **)
PROCEDURE SetShadingShape* (s: Shape; doGouraud: BOOLEAN);
BEGIN
	IF doGouraud THEN
		s.state := s.state + {gouraud}
	ELSE
		s.state := s.state - {gouraud, smooth, dither}
	END;
END SetShadingShape;

(** set specular reflection of shape **)
PROCEDURE SetSpecularReflection* (s: Shape; doSpecular: BOOLEAN);
BEGIN
	IF doSpecular & (gouraud IN s.state) THEN
		s.state := s.state + {specular}
	ELSE
		s.state := s.state - {specular}
	END;
END SetSpecularReflection;

(** set smoothing of shape **)
PROCEDURE SetSmoothShape* (s: Shape; doSmooth: BOOLEAN);
BEGIN
	IF doSmooth & (gouraud IN s.state) THEN
		s.state := s.state + {smooth}
	ELSE
		s.state := s.state - {smooth}
	END;
END SetSmoothShape;

(** set dithering of shape **)
PROCEDURE SetDitherShape* (s: Shape; doDither: BOOLEAN);
BEGIN
	IF doDither  & (gouraud IN s.state) THEN
		s.state := s.state + {dither}
	ELSE
		s.state := s.state - {dither}
	END;
END SetDitherShape;

PROCEDURE InitShape* (s: Shape; VAR T: Matrix; VAR color: Color; diffuse, coef: REAL; expo: INTEGER;
								doGouraud, doSmooth, doDither, doSpecular: BOOLEAN);
BEGIN
	s.next := NIL; s.parent := NIL; s.subshapes := NIL;
	s.points := NIL; s.realPoints := NIL; s.polygons := NIL; s.realPolygons := NIL; s.lights := NIL;
	InitVector(s.center, 0, 0, 0); s.radius := 0;
	s.cmd := NIL;
	s.T := T;
	s.color := color; s.diffuse := diffuse;s.speccoef := coef; s.specexpo := expo;
	s.state := {};
	IF doGouraud THEN 
		s.state := s.state + {gouraud};	(* smooth, dithering only with gouraud shading *)
		IF doSmooth THEN s.state := s.state + {smooth} END;
		IF doDither THEN s.state := s.state + {dither} END;
		IF doSpecular THEN s.state := s.state + {specular} END
	END;
END InitShape;

PROCEDURE FreeShape* (s: Shape);
VAR sub, next: Shape; poly: Polygon;
BEGIN
	sub := s.subshapes;
	WHILE sub # NIL DO
		next := sub.next;
		FreeShape(sub);
		sub := next
	END;
	FreePointList(s.points);
	poly := s.polygons;
	WHILE poly # NIL DO
		FreeRefList(poly.contour);
		poly := poly.next
	END;
	FreePolyList(s.polygons)
END FreeShape;

(** add point to shape **)
PROCEDURE AddPoint* (s: Shape; p: Point);
BEGIN
	p.next := s.points;
	s.points := p
END AddPoint;

(** add polygon to shape **)
PROCEDURE AddPolygon* (s: Shape; poly: Polygon);
CONST eps = 1.0E-14;
VAR pRef, qRef, rRef, pCopy, qCopy: PointRef; x, y, z, v, n: Vector; new: Polygon;
BEGIN
	poly.shape := s;
	
	(* eliminate duplicate points and unnecessary edges *)
	pRef := poly.contour.prev;
	qRef := poly.contour;
	MakeVector(pRef.p.wc, qRef.p.wc, y);
	REPEAT
		x := y;
		pRef := qRef; qRef := qRef.next;
		MakeVector(pRef.p.wc, qRef.p.wc, y);
		CrossProd(x, y, v);
		IF DotProd(v, v) < eps THEN	(* kill point p *)
			pRef.prev.next := qRef;
			qRef.prev := pRef.prev;
			pRef.next := refPool; refPool := pRef;
			IF poly.contour = pRef THEN
				poly.contour := qRef.prev
			END
		END
	UNTIL qRef = poly.contour;
	
	(*
	 * Subdivide poly into convex polygons
	 * The procedure goes as follows: trace the contour of the polygon, until either all vertices have been visited or a
	 * concave turn is found at a vertex. In the second case, find the first possible starting point and cut off a new polygon;
	 * the new polygon is recursively added to the shape and will have at least one concave turn less than the original polygon.
	 * In both cases, continue with the rest of the contour.
	 * The algorithm only works correctly if the first 3 points on the contour form a convex turn.
	 *)
	(* get polygon normal *)
	pRef := poly.contour.next; qRef := pRef.next; rRef := qRef.next;
	MakeVector(pRef.p.wc, qRef.p.wc, x);
	MakeVector(poly.contour.p.wc, pRef.p.wc, y);
	CrossProd(y, x, n);
	
	MakeVector(qRef.p.wc, rRef.p.wc, y);
	CrossProd(x, y, v);
	WHILE pRef # poly.contour DO
		WHILE DotProd(v, n) < 0 DO	(* concave turn in q *)
			(* find first possible starting point *)
			REPEAT
				pRef := pRef.prev;
				MakeVector(qRef.p.wc, pRef.p.wc, z);
				CrossProd(x, z, v);
			UNTIL DotProd(v, n) <= 0;
			pRef := pRef.next;
			
			(* cut contour apart between pRef and qRef *)
			NewRef(pCopy); pCopy.p := pRef.p;	(* duplicate references to shared points *)
			NewRef(qCopy); qCopy.p := qRef.p;
			pCopy.prev := qCopy;
			pCopy.next := pRef.next;
			pCopy.next.prev := pCopy;
			pRef.next := qRef;
			qCopy.next := pCopy;
			qCopy.prev := qRef.prev;
			qCopy.prev.next := qCopy;
			qRef.prev := pRef;
			
			NewPolygon(new);
			new.contour := qCopy.prev;	(* so we can be sure the first three points form a convex turn *)
			AddPolygon(s, new);
			
			MakeVector(pRef.p.wc, qRef.p.wc, x);
			CrossProd(x, y, v);
			poly.contour := pRef
		END;
		
		(* move to next turn *)
		pRef := qRef; qRef := rRef; rRef := rRef.next;
		x := y;
		MakeVector(qRef.p.wc, rRef.p.wc, y);
		CrossProd(x, y, v)
	END;
	
	poly.next := s.polygons; s.polygons := poly
END AddPolygon;

(** add local light source to shape **)
PROCEDURE AddLight* (s: Shape; l: Light);
BEGIN
	l.next := s.lights;
	s.lights := l
END AddLight;

(** add subshape to shape **)
PROCEDURE AddSubshape* (s, sub: Shape);
BEGIN
	sub.next := s.subshapes; s.subshapes := sub;
	sub.parent := s
END AddSubshape;


PROCEDURE WriteShape (VAR R: Files.Rider; shape: Shape);
VAR n: INTEGER; p: Point; poly: Polygon; l: Light; sub: Shape;
BEGIN
	Files.WriteBool(R, gouraud IN shape.state);
	Files.WriteBool(R, smooth IN shape.state);
	Files.WriteBool(R, dither IN shape.state);
	Files.WriteBool(R, specular IN shape.state);
	WriteMatrix(R, shape.T);
	Files.WriteReal(R, shape.color[0]); Files.WriteReal(R, shape.color[1]); Files.WriteReal(R, shape.color[2]);
	Files.WriteReal(R, shape.diffuse);
	Files.WriteReal(R, shape.speccoef); Files.WriteInt(R, shape.specexpo);
	IF shape.cmd # NIL THEN
		Files.Write(R, 1X);
		Files.WriteString(R, shape.cmd^)
	ELSE
		Files.Write(R, 0X)
	END;
	
	p := shape.realPoints; n := 0;
	WHILE p # NIL DO INC(n); p := p.next END;
	Files.WriteInt(R, n);
	p := shape.realPoints;
	WHILE p # NIL DO WritePoint(R, p); p := p.next END;
	
	poly := shape.realPolygons; n := 0;
	WHILE poly # NIL DO INC(n); poly := poly.next END;
	Files.WriteInt(R, n);
	poly := shape.realPolygons;
	WHILE poly # NIL DO WritePoly(R, poly); poly := poly.next END;
	
	l := shape.lights; n := 0;
	WHILE l # NIL DO INC(n); l := l.next END;
	Files.WriteInt(R, n);
	l := shape.lights;
	WHILE l # NIL DO WriteLight(R, l); l := l.next END;
	
	sub := shape.subshapes; n := 0;
	WHILE sub # NIL DO INC(n); sub := sub.next END;
	Files.WriteInt(R, n);
	sub := shape.subshapes;
	WHILE sub # NIL DO WriteShape(R, sub); sub := sub.next END
END WriteShape;

PROCEDURE ReadShape (VAR R: Files.Rider; shape: Shape);
VAR ch: CHAR; n: INTEGER; p: Point; poly: Polygon; l: Light; sub: Shape; bool: BOOLEAN;
BEGIN
	shape.state := {};
	Files.ReadBool(R, bool); IF bool THEN shape.state := shape.state + {gouraud} END;
	Files.ReadBool(R, bool); IF bool THEN shape.state := shape.state + {smooth} END;
	Files.ReadBool(R, bool); IF bool THEN shape.state := shape.state + {dither} END;
	Files.ReadBool(R, bool); IF bool THEN shape.state := shape.state + {specular} END; 
	ReadMatrix(R, shape.T);
	Files.ReadReal(R, shape.color[0]); Files.ReadReal(R, shape.color[1]); Files.ReadReal(R, shape.color[2]);
	Files.ReadReal(R, shape.diffuse);
	Files.ReadReal(R, shape.speccoef); Files.ReadInt(R, shape.specexpo); 
	Files.Read(R, ch);
	IF ch # 0X THEN
		NEW(shape.cmd);
		Files.ReadString(R, shape.cmd^)
	END;
	
	Files.ReadInt(R, n);
	IF n > 0 THEN
		NewPoint(p); ReadPoint(R, p); DEC(n);
		shape.points := p;
		WHILE n > 0 DO
			NewPoint(p.next); p := p.next; ReadPoint(R, p); DEC(n)
		END
	END;
	
	Files.ReadInt(R, n);
	IF n > 0 THEN
		NewPolygon(poly); poly.shape := shape; ReadPoly(R, poly); DEC(n);
		shape.polygons := poly;
		WHILE n > 0 DO
			NewPolygon(poly.next); poly := poly.next; poly.shape := shape; ReadPoly(R, poly); DEC(n)
		END
	END;
	
	Files.ReadInt(R, n);
	IF n > 0 THEN
		NEW(l); ReadLight(R, l); DEC(n);
		shape.lights := l;
		WHILE n > 0 DO
			NEW(l.next); l := l.next; ReadLight(R, l); DEC(n)
		END
	END;
	
	Files.ReadInt(R, n);
	IF n > 0 THEN
		NEW(sub); sub.parent := shape; ReadShape(R, sub); DEC(n);
		shape.subshapes := sub;
		WHILE n > 0 DO
			NEW(sub.next); sub := sub.next; sub.parent := shape; ReadShape(R, sub); DEC(n)
		END
	END
END ReadShape;


(*
 * The next few procedures compute parameters not directly related to the building of worlds but important for drawing,
 * i.e., bounding spheres, polygon colors and creation of the scene BSP tree. They process a shape and all its subshapes.
 *)

(* calculate bounding sphere for shape (including subshapes) *)
PROCEDURE CalcBound (s: Shape);
CONST eps = 1.E-5;
VAR p: Point; i: INTEGER; sub: Shape; d, r, t: REAL; v: Vector;
BEGIN
	IF s.subshapes # NIL THEN	(* get bounding sphere encompassing all subshape bounds *)
		sub := s.subshapes;
		CalcBound(sub);
		s.center := sub.center; s.radius := sub.radius;
		sub := sub.next;
		WHILE sub # NIL DO
			CalcBound(sub);
			MakeVector(s.center, sub.center, v);
			d := Math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
			IF d + sub.radius > s.radius THEN	(* s must have bigger radius *)
				IF d < eps THEN
					s.radius := sub.radius + eps
				ELSE
					r := (s.radius + d + sub.radius) / 2.0;
					t := (r - s.radius) / d;
					FOR i := 0 TO 2 DO
						s.center[i] := s.center[i] + t*v[i]
					END;
					s.radius := r
				END
			END;
			sub := sub.next
		END
	ELSIF s.points # NIL THEN	(* initialize with first point *)
		s.center := s.points.wc;
		s.radius := eps
	END;
	
	(* extend sphere until all points are inside *)
	p := s.points;
	WHILE p # NIL DO
		MakeVector(s.center, p.wc, v);
		d := Math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
		IF d > s.radius THEN	(* point is outside current sphere *)
			r := (s.radius + d + eps) / 2.0;
			t := (r - s.radius) / d;
			FOR i := 0 TO 2 DO
				s.center[i] := s.center[i] + t*v[i]
			END;
			s.radius := r
		END;
		p := p.next
	END
END CalcBound;

(* update bounding spheres of parent shapes *)
PROCEDURE UpdateBound (s: Shape);
CONST eps = 1.E-7;
VAR i: INTEGER; parent: Shape; d, r, t: REAL; v: Vector;
BEGIN
	(* update parent shapes *)
	parent := s.parent;
	WHILE parent # NIL DO
		MakeVector(parent.center, s.center, v);
		d := Math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
		IF d + s.radius > parent.radius THEN
			IF d < eps THEN
				parent.radius := s.radius + eps
			ELSE
				r := (parent.radius + d + s.radius) / 2.0;
				t := (r - parent.radius) / d;
				FOR i := 0 TO 2 DO
					parent.center[i] := parent.center[i] + t*v[i]
				END;
				parent.radius := r
			END
		ELSE
			RETURN
		END;
		parent := parent.parent
	END
END UpdateBound;

PROCEDURE InitShapePoints (s: Shape);
VAR p: Point;
BEGIN
	p := s.points;
	WHILE p #  NIL DO
		InitVector(p.normal,0,0,0);
		p := p.next;
	END;
END InitShapePoints;

(* (re)calculate normals for shape polygons (including subshapes) *)
PROCEDURE CalcShapePlanes (s: Shape);
VAR poly: Polygon; sub: Shape;
BEGIN
	(* calculate polygon plane equations *)
	InitShapePoints(s);
	poly := s.polygons;
	WHILE poly # NIL DO
		CalcPlane(poly);
		poly := poly.next
	END;
	
	sub := s.subshapes;
	WHILE sub # NIL DO
		CalcShapePlanes(sub);
		sub := sub.next
	END
END CalcShapePlanes;


(*
 * The following procedure reorders the polygons of the shape to create an "optimal" sequence for insertion into a BSP tree.
 * Polygons that split few others are moved to the beginning of the list, whereupon the remaining polygons are divided into
 * three sets: polygons lying in front of, behind or on both sides of the moved polygon. The process continues with each of
 * those sets separately. A second selection criterion is the balance of a BSP tree that would result if the polygons were
 * inserted in that order.
 * This approach is based on local criteria only. There is no guarantee that splits are minimized when inserting the polygons
 * into an already existing, non-empty BSP tree.
 *)
PROCEDURE ReorderPolygons (s: Shape);
CONST inFront = 1; behind = -1; splitting = 0;
VAR pset: Polygon; sub: Shape;

	(* find out if q is in front of, behind or splitting p *)
	PROCEDURE WhichSide (p, q: Polygon): INTEGER;
	VAR d: REAL; ref: PointRef;
	BEGIN
		ref := q.contour;
		REPEAT
			d := DotProd(p.normal, ref.p.wc) + p.dist;
			ref := ref.next
		UNTIL (ref = q.contour) OR (d # 0.0);
		WHILE ref # q.contour DO
			IF d * (DotProd(p.normal, ref.p.wc) + p.dist) < 0 THEN
				RETURN splitting
			END;
			ref := ref.next
		END;
		IF d >= 0 THEN RETURN
			inFront
		ELSE
			RETURN behind
		END
	END WhichSide;
	
	(* choose "best" polygon and append it to s.polygons *)
	PROCEDURE AppendBest (set: Polygon);
	CONST maxTries = 10;
	VAR tries, splits, balance, value, bestValue: INTEGER; poly, cand, best, frontSet, backSet, splitSet: Polygon;
	BEGIN
		IF set # NIL THEN
			(* select polygon which splits as few others as possible *)
			tries := 0; bestValue := MAX(INTEGER); cand := set; best := cand;
			WHILE (bestValue > 0) & (cand # NIL) & (tries < maxTries) DO
				poly := set; splits := 0; balance := 0;
				WHILE poly # NIL DO
					IF poly # cand THEN
						CASE WhichSide(cand, poly) OF
						| inFront: INC(balance)
						| behind: DEC(balance)
						| splitting: INC(splits)
						END
					END;
					poly := poly.next
				END;
				value := 4 * splits + ABS(balance);	(* minimization of splits is more important than balance *)
				IF value < bestValue THEN
					bestValue := value; best := cand
				END;
				cand := cand.next;
				INC(tries)
			END;
			
			(* partition set *)
			frontSet := NIL; backSet := NIL; splitSet := NIL;
			WHILE set # NIL DO
				poly := set; set := set.next;
				IF poly = best THEN
					poly.next := s.polygons; s.polygons := poly;	(* best polygon goes back to s.polygons *)
				ELSE
					CASE WhichSide(best, poly) OF
					| behind: poly.next := backSet; backSet := poly
					| inFront: poly.next := frontSet; frontSet := poly
					| splitting: poly.next := splitSet; splitSet := poly
					END
				END
			END;
			
			(* insert non-splitting polygons first *)
			AppendBest(frontSet); AppendBest(backSet); AppendBest(splitSet)
		END
	END AppendBest;
	
BEGIN
	pset := s.polygons; s.polygons := NIL;
	AppendBest(pset);
	
	sub := s.subshapes;
	WHILE sub # NIL DO
		ReorderPolygons(sub);
		sub := sub.next
	END
END ReorderPolygons;

(* insert shape polygons into the BSPT *)
PROCEDURE InsertShape (s: Shape; VAR bsp: BSPNode);
VAR poly: Polygon; sub: Shape;
BEGIN
	s.realPoints := s.points;
	s.realPolygons := s.polygons;
	poly := s.polygons;
	WHILE poly # NIL DO
		BSPInsert(bsp, poly);
		poly := poly.next
	END;
	
	sub := s.subshapes;
	WHILE sub # NIL DO
		InsertShape(sub, bsp);
		sub := sub.next
	END
END InsertShape;

(* determine a priori visibility of shape *)
PROCEDURE CullShape (s: Shape; VAR C: Camera; VAR N: Matrix; zoom: REAL; pstate: SET);
VAR v: Vector; r, d: REAL; plane: INTEGER; p: Point; sub: Shape;
BEGIN
	IF mustClip IN pstate THEN
		(* transform bounding sphere to camera coordinates *)
		Transform(N, s.center, v); r := zoom * s.radius;
		
		(* intersect bounding sphere with clipping planes *)
		plane := 0; s.state := s.state - {invisible, mustClip};
		LOOP
			d := DotProd(v, clip[plane].normal) + clip[plane].dist;
			IF d > r THEN
				INCL(s.state, invisible); EXIT
			ELSIF d >= -r THEN
				INCL(s.state, mustClip); EXIT
			END;
			INC(plane);
			IF plane = nPlanes THEN EXIT END
		END
	ELSE
		s.state := s.state - {invisible, mustClip} + pstate	(* either invisible or fully visible *)
	END;
	
	(* cull subshapes *)
	sub := s.subshapes;
	WHILE sub # NIL DO
		CullShape(sub, C, N, zoom, s.state);
		sub := sub.next
	END;
	
	IF ~(invisible IN s.state) THEN	(* transform points *)
		p := s.points;
		WHILE p # NIL DO
			Transform(N, p.wc, p.vrc);	(* normalizing transformation *)
			p := p.next
		END
	END
END CullShape;


(**--- Cameras ---**)

(** initialize camera **)
PROCEDURE InitCamera* (VAR C: Camera);
BEGIN
	(* move camera to origin, looking along negative z-axis, y-axis pointing upwards *)
	InitVector(C.pos, 0, 0, 0);
	InitVector(C.u, 1, 0, 0);
	InitVector(C.v, 0, 1, 0);
	InitVector(C.w, 0, 0, 1);
	C.fov := Math.pi/6;
END InitCamera;

(** move camera position in its own coordinate system **)
PROCEDURE MoveCamera* (VAR C: Camera; right, up, forward: REAL);
BEGIN
	C.pos[0] := C.pos[0] + right*C.u[0] + up*C.v[0] - forward*C.w[0];
	C.pos[1] := C.pos[1] + right*C.u[1] + up*C.v[1] - forward*C.w[1];
	C.pos[2] := C.pos[2] + right*C.u[2] + up*C.v[2] - forward*C.w[2];
END MoveCamera;

(** rotate camera in its local coordinate system **)
PROCEDURE RotateCamera* (VAR C: Camera; angle, x, y, z: REAL);
VAR R: Matrix; sx, sy, sz: REAL; v: Vector;
BEGIN
	(* transform rotation axis from camera to world coordinates *)
	sx := x*C.u[0] + y*C.v[0] + z*C.w[0];
	sy := x*C.u[1] + y*C.v[1] + z*C.w[1];
	sz := x*C.u[2] + y*C.v[2] + z*C.w[2];
	
	(* apply rotation to camera axes *)
	GetRotation(R, angle, sx, sy, sz);
	Transform(R, C.v, v); C.v := v;
	Transform(R, C.w, v); C.w := v;
	CrossProd(C.v, C.w, C.u)
END RotateCamera;


(** get azimute, pitch and roll angle **)
PROCEDURE GetCameraAngles* (VAR C: Camera; VAR azi, pitch, roll: REAL);
CONST eps = 1.0E-7;
VAR sin, cos: REAL; u: Vector;
BEGIN
	(*
	 * The camera angles are defined as follows: rotating the camera by -azi around y, then rotating by -pitch around x
	 * and finally rotating by -roll around z brings the camera into its default coordinate system.
	 *)
	IF C.w[0]*C.w[0] + C.w[2]*C.w[2] < eps THEN	(* view plane is perpendicular to y-axis *)
		pitch := Atan2(C.w[1], 0); roll := 0;
		azi := Atan2(-C.u[2], C.u[0])	(* what usually is considered roll is now azimute *)
	ELSE
		(* rotate projection of w on xz-plane into z-axis *)
		azi := Atan2(C.w[0], C.w[2]);
		sin := -Math.sin(azi); cos := Math.cos(azi);
		InitVector(u, cos*C.u[0] + sin*C.u[2], C.u[1], -sin*C.u[0] + cos*C.u[2]);
		
		(* rotate w into z-axis *)
		pitch := -Atan2(C.w[1], -sin*C.w[0] + cos*C.w[2]);
		sin := Math.sin(pitch); cos := Math.cos(pitch);
		
		(* calculate roll angle *)
		roll := Atan2(cos*u[1] + sin*u[2], u[0])
	END
END GetCameraAngles;

(** set camera orientation by azimute, pitch and roll angles **)
PROCEDURE SetCameraAngles* (VAR C: Camera; azi, pitch, roll: REAL);
VAR sa, ca, sp, cp, sr, cr, t: REAL;
BEGIN
	(*
	 * This code calculates a rotation by 'roll' around z, followed by a rotation by 'pitch' around x and a
	 * rotation by 'azi' around y. This rotation is applied to the default coordinate axes which have azi, pitch and
	 * roll set to zero. (u = [1 0 0], v = [0 1 0], w = [0 0 1])
	 *)
	 sa := Math.sin(azi); ca := Math.cos(azi);
	 sp := -Math.sin(pitch); cp := Math.cos(pitch);
	 sr := Math.sin(roll); cr := Math.cos(roll);
	 t := sp*sr;
	 InitVector(C.u, ca*cr - sa*t, cp*sr, -sa*cr - ca*t);
	 t := sp*cr;
	 InitVector(C.v, -ca*sr - sa*t, cp*cr, sa*sr - ca*t);
	 InitVector(C.w, sa*cp, sp, ca*cp)
END SetCameraAngles;


(** get transformation that translates and rotates from WC into camera space **)
PROCEDURE GetCameraTrafo* (VAR C: Camera; VAR N: Matrix);
VAR T, R: Matrix;
BEGIN
	(* translation of camera to origin *)
	T := identity; T[0, 3] := -C.pos[0]; T[1, 3] := -C.pos[1]; T[2, 3] := -C.pos[2];
	
	(* rotation of camera axes into world coordinate axes *)
	R[0, 0] := C.u[0]; R[0, 1] := C.u[1]; R[0, 2] := C.u[2]; R[0, 3] := 0;
	R[1, 0] := C.v[0]; R[1, 1] := C.v[1]; R[1, 2] := C.v[2]; R[1, 3] := 0;
	R[2, 0] := C.w[0]; R[2, 1] := C.w[1]; R[2, 2] := C.w[2]; R[2, 3] := 0;
	ConcatMatrix(R, T, N)
END GetCameraTrafo;

PROCEDURE WriteCamera* (VAR R: Files.Rider; VAR C: Camera);
BEGIN
	Files.WriteReal(R, C.fov);
	WriteVector(R, C.pos); WriteVector(R, C.u); WriteVector(R, C.v); WriteVector(R, C.w);
END WriteCamera;

PROCEDURE ReadCamera* (VAR R: Files.Rider; VAR C: Camera);
BEGIN
	Files.ReadReal(R, C.fov);
	ReadVector(R, C.pos); ReadVector(R, C.u); ReadVector(R, C.v); ReadVector(R, C.w)
END ReadCamera;


(**--- Worlds ---**)

(** notify clients of changes **)
PROCEDURE Update* (w: World);
BEGIN
	IF locked IN w.state THEN
		INCL(w.state, needUpdate)
	ELSE
		Gadgets.Update(w)
	END
END Update;

(** enable/disable update messages **)
PROCEDURE EnableUpdate* (w: World; enable: BOOLEAN);
BEGIN
	IF enable THEN
		EXCL(w.state, locked);
		IF needUpdate IN w.state THEN
			EXCL(w.state, needUpdate);
			Gadgets.Update(w)
		END
	ELSE
		INCL(w.state, locked)
	END
END EnableUpdate;


(* find selected shape (if only one is selected) *)
PROCEDURE GetSelection (w: World);

	PROCEDURE CountSelected (s: Shape);
	VAR sub: Shape;
	BEGIN
		(* count shape if it is selected and its parent is not *)
		IF (selected IN s.state) & ((s.parent = NIL) OR ~(selected IN s.parent.state)) THEN
			w.selShape := s;
			INC(w.selCount)
		END;
		
		(* count selected subshapes *)
		sub := s.subshapes;
		WHILE sub # NIL DO
			CountSelected(sub);
			sub := sub.next
		END
	END CountSelected;

BEGIN
	w.selCount := 0;
	CountSelected(w.shape);
	IF w.selCount # 1 THEN
		w.selShape := NIL
	END
END GetSelection;

(** select a shape and its subshapes **)
PROCEDURE SelectShape* (w: World; shape: Shape; sel: BOOLEAN);
VAR enabled: BOOLEAN;

	PROCEDURE Select (s: Shape);
	VAR sub: Shape;
	BEGIN
		(* mark selection state in shape *)
		IF sel THEN
			INCL(s.state, selected)
		ELSE
			EXCL(s.state, selected)
		END;
		
		(* propagate selection state to subshapes *)
		sub := s.subshapes;
		WHILE sub # NIL DO
			Select(sub);
			sub := sub.next
		END;
		
		Update(w)
	END Select;

BEGIN
	enabled := ~(locked IN w.state);
	EnableUpdate(w, FALSE);
	Select(shape);
	w.time := Oberon.Time();
	GetSelection(w);
	EnableUpdate(w, enabled)
END SelectShape;


(** shade shape polygons according to shape base color and light sources (shades subshapes, too) **)
PROCEDURE ShadeShape* (w: World; shape: Shape);
VAR s: Shape; l: Light; k, sum, d: REAL; i: INTEGER;
	  poly: Polygon; color: ARRAY 3 OF REAL; dir, normal: Vector; ref: PointRef; lightRef: LightRef;
BEGIN
	(* shade subshapes *)
	s := shape.subshapes;
	WHILE s # NIL DO
		ShadeShape(w, s);
		s := s.next
	END;
	
	(* grayscale ?? *)
	IF (shape.color[0] = shape.color[1]) & (shape.color[0] = shape.color[2]) THEN 
		shape.grayscale := TRUE 
	ELSE 
		shape.grayscale := FALSE 
	END;
	
	(* shade polygons with constant shading *)
	poly := shape.polygons;
	WHILE poly # NIL DO
		(* initialize point intensities *)
		ref := poly.contour;
		IF ref # NIL THEN
			REPEAT
				ref.inten := w.ambient; ref.light := NIL;
				ref := ref.next;
			UNTIL (ref = poly.contour) OR (ref = NIL)
		END;
		
		(* sum up intensity of every light source in shape hierarchy *)
		sum := 0; s := shape;
		REPEAT
			l := s.lights;
			WHILE l # NIL DO
				(* constant shading of polygons *)
				IF l.type = DirectLight THEN	(* accept only direct light sources for constant shading *)
					k := DotProd(poly.normal, l.dir);	
					IF k < 0.0 THEN k := 0.0 END;
					sum := sum + l.inten * k;
				END;
				
				(* gouraud shading of polygons *)
				IF (gouraud IN shape.state) & (poly.contour # NIL) THEN
					ref := poly.contour; normal := poly.normal;
					REPEAT
						IF smooth IN shape.state THEN	(* use average point normals  to calc point intensities*)
							normal := ref.p.normal
						END;
						Normalize(normal);
						IF l.type = DirectLight THEN
							k := DotProd(normal, l.dir);	
						ELSE
							MakeVector(ref.p.wc, l.dir, dir);
							Normalize(dir);
							d := Distance(l.dir, ref.p.wc) * Dist; 
							k := DotProd(normal, dir) / d;
						END;
						IF k > 0.0 THEN ref.inten := ref.inten + l.inten * k * shape.diffuse END;
						IF specular IN shape.state THEN		(* see also  AppPointSpecial *)
							NEW(lightRef); 
							IF l.type = PointLight THEN 
								k := DotProd(normal, dir) * 2;
								d := Distance(l.dir, ref.p.wc) * DistSpec;
								IF k > 0.0 THEN
									lightRef.R[0] := normal[0] * k - dir[0]; lightRef.R[1] := normal[1] * k - dir[1]; 
									lightRef.R[2] := normal[2] * k - dir[2];
									lightRef.factor := shape.speccoef / d;
									Normalize(lightRef.R)
								ELSE
									lightRef.factor := 0
								END;
							ELSE 
								k := DotProd(normal, l.dir) * 2;
								IF k > 0.0 THEN
									lightRef.R[0] := normal[0] * k - l.dir[0]; lightRef.R[1] := normal[1] * k - l.dir[1]; 
									lightRef.R[2] := normal[2] * k - l.dir[2];
									lightRef.factor := shape.speccoef;
									Normalize(lightRef.R)
								ELSE
									lightRef.factor := 0
								END;
							END;
							lightRef.light := l;
							lightRef.next := ref.light; ref.light := lightRef;
						END;
						ref := ref.next;
					UNTIL (ref = poly.contour) OR (ref = NIL)
				END;
				
				l := l.next
			END;
			s := s.parent
		UNTIL s = NIL;
		
		(* set shaded color of polygon *)
		k := w.ambient + sum * shape.diffuse;
		FOR i := 0 TO 2 DO
			color[i] := k * shape.color[i];
			IF color[i] > 1.0 THEN	(* color intensities are restricted to range 0..1 *)
				color[i] := 1.0
			END
		END;
		poly.col := Dim3Paint.GetColor(color,1, FALSE);
		IF poly.texture # NIL THEN	(* shade texture with constant shading *)
			Dim3Paint.ShadeTexture(poly.texture.basePict, poly.texture.shadedPict, poly.texture.numPict, poly.texture.transparent, k);
(*			IF ~(gouraud IN shape.state) THEN	(* shade texture with constant shading *)
				Dim3Paint.ShadeTexture(poly.texture.basePict, poly.texture.shadedPict, poly.texture.numPict, poly.texture.transparent, k);
			ELSE	(* shade texture with gouraud shading *)
				Texts.WriteString(W, "gouraud shaded textures not implemented yet"); Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf); HALT(111);
			END;*)
		END;
		poly := poly.next
	END;
END ShadeShape;

(** invert color of each polygon for temporary highlighting **)
PROCEDURE HighlightShape* (w: World; shape: Shape);

	PROCEDURE Highlight (shape: Shape);
	VAR s: Shape; i: INTEGER; max: REAL;
	BEGIN
		(* highlight subshapes *)
		s := shape.subshapes;
		WHILE s # NIL DO
			Highlight(s);
			s := s.next
		END;
		
		(* highlight shape by inverting its color *)
		IF shape.color[0] >= shape.color[1] THEN
			IF shape.color[0] >= shape.color[2] THEN max := shape.color[0]
			ELSE max := shape.color[2]
			END
		ELSE
			IF shape.color[1] >= shape.color[2] THEN max := shape.color[1]
			ELSE max := shape.color[2]
			END
		END;
		IF max > 0.5 THEN
			FOR i := 0 TO 2 DO shape.color[i] := shape.color[i] * 0.5 END
		ELSE
			FOR i := 0 TO 2 DO shape.color[i] := shape.color[i] * 2.0 END
		END
	END Highlight;

BEGIN
	Highlight(shape);
	ShadeShape(w, shape)
END HighlightShape;

(** change color of Selection to col **)
PROCEDURE ColorSelection* (w: World; VAR col: Color);
	PROCEDURE ColorShape (s: Shape);
	VAR sub: Shape;
	BEGIN
		sub := s.subshapes;
		WHILE sub # NIL DO
			ColorShape(sub);
			sub := sub.next
		END;
		IF selected IN s.state THEN
			s.color := col
		END
	END ColorShape;

BEGIN
	ColorShape(w.shape);
	ShadeShape(w, w.shape);
	Update(w)
END ColorSelection;


PROCEDURE Neutralize* (w: World);
BEGIN
	SelectShape(w, w.shape, FALSE);
	w.time := -1;
	Update(w)
END Neutralize;

PROCEDURE InitWorld* (w: World);
BEGIN
	NEW(w.shape);
	InitShape(w.shape, identity, white, 0.5, 1.0, 10, FALSE, FALSE, FALSE, FALSE);
	w.bspTree := NIL;
	w.ambient := 1;
	w.horizon := FALSE;
	w.time := -1;
	Update(w)
END InitWorld;

PROCEDURE FreeWorld* (w: World);
BEGIN
	FreeShape(w.shape);
	BSPFree(w.bspTree);
	InitWorld(w)
END FreeWorld;

(* set up clipping planes *)
PROCEDURE InitClippingPlanes;
CONST s = 0.70710678;	(* 1/sqrt(2) *)
BEGIN
	InitVector(clip[0].normal, -s,  0, s); clip[0].dist := 0;
	InitVector(clip[1].normal,  s,  0, s); clip[1].dist := 0;
	InitVector(clip[2].normal,  0, -s, s); clip[2].dist := 0;
	InitVector(clip[3].normal,  0,  s, s); clip[3].dist := 0;
	InitVector(clip[4].normal,  0,  0, 1); clip[4].dist := -hither
END InitClippingPlanes;

PROCEDURE WorldHandler* (w: Objects.Object; VAR M: Objects.ObjMsg);
VAR w0: World;
BEGIN
	WITH w: World DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				(* otherwise handle world attributes *)
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN
						M.class := Objects.String; M.s := "Dim3Engine.NewWorld"; M.res := 0
					ELSIF M.name = "SkyColor" THEN
						M.class := Objects.Int; M.i := w.skyCol; M.res := 0
					ELSIF M.name = "GroundColor" THEN
						M.class := Objects.Int; M.i := w.gndCol; M.res := 0
					ELSIF M.name = "Ambient" THEN
						M.class := Objects.Real; M.x := ENTIER(1024*w.ambient + 0.5)/1024.0; M.res := 0
					ELSE
						Gadgets.objecthandle(w, M)
					END
				ELSIF M.id = Objects.set THEN
					IF (M.name = "SkyColor") & (M.class = Objects.Int) THEN
						
						w.skyCol := Dim3Base.GetRealColor(SHORT(M.i)); M.res := 0;
						Update(w)
					ELSIF (M.name = "GroundColor") & (M.class = Objects.Int) THEN
						w.gndCol := Dim3Base.GetRealColor(SHORT(M.i)); M.res := 0;
						Update(w)
					ELSIF M.name = "Ambient" THEN
						IF M.class = Objects.Real THEN
							w.ambient := M.x; M.res := 0;
							ShadeShape(w, w.shape);
							Update(w)
						ELSIF M.class = Objects.LongReal THEN
							w.ambient := SHORT(M.y); M.res := 0;
							ShadeShape(w, w.shape);
							Update(w)
						END
					ELSE
						Gadgets.objecthandle(w, M)
					END
				ELSIF M.id = Objects.enum THEN
					M.Enum("SkyColor");
					M.Enum("GroundColor");
					M.Enum("Ambient");
					Gadgets.objecthandle(w, M)
				ELSE
					Gadgets.objecthandle(w, M)
				END
			END
		
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteReal(M.R, w.ambient);
					WriteShape(M.R, w.shape);
					Files.WriteInt(M.R, w.skyCol);
					Files.WriteInt(M.R, w.gndCol);
					Files.WriteBool(M.R, w.horizon)
				ELSIF M.id = Objects.load THEN
					FreeShape(w.shape); BSPFree(w.bspTree);
					w.bspTree := NIL; w.time := -1;
					Files.ReadReal(M.R, w.ambient);
					ReadShape(M.R, w.shape);
					CalcBound(w.shape);
					CalcShapePlanes(w.shape);
					ShadeShape(w, w.shape);
					ReorderPolygons(w.shape);
					InsertShape(w.shape, w.bspTree);
					Files.ReadInt(M.R, w.skyCol);
					Files.ReadInt(M.R, w.gndCol);
					Files.ReadBool(M.R, w.horizon)
				END;
				Gadgets.objecthandle(w, M)
			END
		
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = w.stamp THEN
					M.obj := w.dlink
				ELSE
					NEW(w0);
					w.stamp := M.stamp; w.dlink := w0;
					w0.handle := w.handle; w.ref := 0; w.lib := NIL; w.slink := NIL;
					w0.state := w.state;
					w0.skyCol := w.skyCol; w0.gndCol := w.skyCol;
					w0.ambient := w.ambient;
					w0.horizon := w.horizon;
					IF M.id = Objects.shallow THEN
						w0.attr := w.attr;
						w0.shape := w.shape;
						w0.bspTree := w.bspTree;
						w0.time := w.time; w0.selCount := w.selCount; w0.selShape := w.selShape
					ELSIF M.id = Objects.deep THEN	(* deep copy not implemented; an empty scene will result, instead *)
						Attributes.CopyAttributes(w.attr, w0.attr);
						NEW(w0.shape);
						InitShape(w0.shape, w.shape.T, w.shape.color, w.shape.diffuse, w.shape.speccoef, w.shape.specexpo,
										gouraud IN w.shape.state, smooth IN w.shape.state, dither IN w.shape.state, specular IN w.shape.state);
						w0.bspTree := NIL;
						w0.time := -1; w0.selCount := 0; w0.selShape := NIL
					END;
					M.obj := w0
				END
			END
		
		ELSE
			Gadgets.objecthandle(w, M)
		END
	END
END WorldHandler;

PROCEDURE NewWorld*;
VAR w: World;
BEGIN
	NEW(w);
	w.state := {};
	w.skyCol := Dim3Base.GetRealColor(SKY);
	w.gndCol := Dim3Base.GetRealColor(GND);
	
	w.handle := WorldHandler; w.ref := 0; w.lib := NIL; w.slink := NIL;
	InitWorld(w);
	Objects.NewObj := w
END NewWorld;

(** add a shape to the world **)
PROCEDURE AddShape* (w: World; s: Shape);
BEGIN
	AddSubshape(w.shape, s);
	CalcBound(s);
	UpdateBound(s);
	CalcShapePlanes(s);
	ShadeShape(w, s);
	ReorderPolygons(s);
	InsertShape(s, w.bspTree);
END AddShape;

(** print statistical information in log **)
PROCEDURE Statistics* (w: World);
VAR pts, polys, shps: INTEGER;

	PROCEDURE CountShapeData(s: Shape);
	VAR sub: Shape; p: Point; poly: Polygon;
	BEGIN
		INC(shps);
		p := s.points;
		WHILE p # NIL DO INC(pts); p := p.next END;
		poly := s.polygons;
		WHILE poly # NIL DO INC(polys); poly := poly.next END;
		sub := s.subshapes;
		WHILE sub # NIL DO
			CountShapeData(sub);
			sub := sub.next
		END
	END CountShapeData;			

BEGIN
	pts := 0; polys := 0; shps := 0;
	CountShapeData(w.shape);
	Texts.WriteInt(W, shps-1, 0); Texts.WriteString(W, " shapes, containing ");
	Texts.WriteInt(W, pts, 0); Texts.WriteString(W, " points and ");
	Texts.WriteInt(W, polys, 0); Texts.WriteString(W, " polygons");
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Statistics;

(* draw horizon in display*)
PROCEDURE DrawHorizon (wld: World; VAR C: Camera; P: Pictures.Picture);
CONST
	eps = 1.0E-5;
	xL = -10.0; xR = -xL;
	xmin = -1000; xmax = -xmin; ymin = xmin; ymax = xmax;
VAR
	angle, sx, sz, cx, cz, z, x1, y1, x2, y2: REAL; u, w: Vector; R00, R02, R10, R12: REAL;
	contour: PointRef; p: ARRAY 5 OF Point; i: INTEGER;
	
	PROCEDURE DrawPoly (col: INTEGER; xa, ya, xb, yb, xc, yc, xd, yd, xe, ye: REAL);
	VAR x, y, i: ARRAY  maxVertices OF REAL; n: INTEGER;
	BEGIN
		InitVector(p[0].vrc, xa, ya, -1); InitVector(p[1].vrc, xb, yb, -1); InitVector(p[2].vrc, xc, yc, -1);
		InitVector(p[3].vrc, xd, yd, -1); InitVector(p[4].vrc, xe, ye, -1);
		ClipPoly(contour, x, y, i, i, i, i, i, n, FALSE, FALSE);
		IF n > 1 THEN
			Dim3Paint.DrawPolygon(P, col, FALSE, x, y, n)
		END
	END DrawPoly;
	
BEGIN
	(* rotate around y *)
	IF C.w[0]*C.w[0] + C.w[2]*C.w[2] >= eps THEN
		angle := -Atan2(C.w[0], C.w[2]); sx := Math.sin(angle); cx := Math.cos(angle)
	ELSE
		angle := 0; sx := 0; cx := 1
	END;
	InitVector(u, cx*C.u[0] + sx*C.u[2], C.u[1], -sx*C.u[0] + cx*C.u[2]);
	InitVector(w, cx*C.w[0] + sx*C.w[2], C.w[1], -sx*C.w[0] + cx*C.w[2]);
	
	(* rotate w-axis into z-axis *)
	angle := Atan2(w[1], w[2]); sx := Math.sin(angle); cx := Math.cos(angle);
	InitVector(u, u[0], cx*u[1] - sx*u[2], sx*u[1] + cx*u[2]);
	
	(* rotate u-axis into x-axis *)
	angle := -Atan2(u[1], u[0]); sz := Math.sin(angle); cz := Math.cos(angle);
	
	(* horizon transformation *)
	R00 := C.zx*cz; R02 := C.zx*sx*sz;
	R10 := C.zy*sz; R12 := -C.zy*sx*cz;
	IF cx < 0.001 THEN z := 0.001 ELSE z := cx END;
	x1 := (xL*R00 - R02) / z; y1 := (xL*R10 - R12) / z;
	x2 := (xR*R00 - R02) / z; y2 := (xR*R10 - R12) / z;
	
	(* set up pentagon structure *)
	contour := NIL;
	NewPoint(p[4]); AppendPoint(contour, p[4]);
	FOR i := 3 TO 0 BY -1 DO
		NewPoint(p[i]); AppendPoint(contour, p[i]); p[i].next := p[i+1]
	END;
	
	(* draw sky and ground polygon *)
	IF x2 >= x1 THEN
		IF y2 >= y1 THEN
			DrawPoly(wld.skyCol, x1, y1, x2, y2, x2, ymax, xmin, ymax, xmin, y1);
			DrawPoly(wld.gndCol, x1, y1, x1, ymin, xmax, ymin, xmax, y2, x2, y2);
		ELSE
			DrawPoly(wld.skyCol, x1, y1, x2, y2, xmax, y2, xmax, ymax, x1, ymax);
			DrawPoly(wld.gndCol, x1, y1, xmin, y1, xmin, ymin, x2, ymin, x2, y2);
		END
	ELSE
		IF y2 >= y1 THEN
			DrawPoly(wld.skyCol, x1, y1, x2, y2, xmin, y2, xmin, ymin, x1, ymin);
			DrawPoly(wld.gndCol, x1, y1, xmax, y1, xmax, ymax, x2, ymax, x2, y2);
		ELSE
			DrawPoly(wld.skyCol, x1, y1, x2, y2, x2, ymin, xmax, ymin, xmax, y1);
			DrawPoly(wld.gndCol, x1, y1, x1, ymax, xmin, ymax, xmin, y2, x2, y2);
		END
	END;
	
	(* clean up *)
	FreePointList(p[0]);
	FreeRefList(contour)
END DrawHorizon;

(** draw world in picture **)
PROCEDURE DrawDirect* (w: World; VAR C: Camera; P: Pictures.Picture);
VAR N: Matrix; zoom, sin: REAL; i: INTEGER; 
BEGIN
	sin := Math.sin(C.fov);
	C.zx := Math.cos(C.fov) / sin;	(* used to be compiler bug in DOS_Oberon, simplify when fixed *)
	C.zy := C.zx * P.width / P.height;	(* take picture aspect ratio into account *)
	GetCameraTrafo(C, N);
	FOR i := 0 TO 3 DO	(* scale to canonic view volume *)
		N[0, i] := N[0, i] * C.zx;
		N[1, i] := N[1, i] * C.zy
	END;
	zoom := Math.sqrt(C.zx*C.zx + C.zy*C.zy);	(* maximum zoom factor affects bounding radii *)
	CullShape(w.shape, C, N, zoom, {mustClip});
	(* draw horizon first*)
	IF w.horizon THEN
		DrawHorizon(w, C, P)
	ELSE
		Dim3Base.SetPicture(P);
		FOR i := 0 TO P.height - 1 DO
			Dim3Base.ReplConst(w.skyCol, 0, i, P.width)
		END;
	END;
	(* draw visible polygons *)
	tsList := NIL;
	IF P.height > numDynScreen THEN
		Dim3Paint.InitDynScreen(dynScreen,P.width, numDynScreen)
	ELSE
		Dim3Paint.InitDynScreen(dynScreen,P.width, P.height)
	END;
	
	DrawBSPDirect(w.bspTree, C, P, N);
	
	IF tsList # NIL THEN Dim3Paint.DrawTSList(P, tsList) END;
	
	Dim3Paint.FreeDSList(dynScreen, P.height);
END DrawDirect;

BEGIN
	Texts.OpenWriter(W);
	Texts.WriteString(W, "3D-Engine, David Ulrich 07.03.96"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	
	InitClippingPlanes;
	Dim3Paint.InitColors; 
	
	identity[0, 0] := 1; identity[0, 1] := 0; identity[0, 2] := 0; identity[0, 3] := 0;
	identity[1, 0] := 0; identity[1, 1] := 1; identity[1, 2] := 0; identity[1, 3] := 0;
	identity[2, 0] := 0; identity[2, 1] := 0; identity[2, 2] := 1; identity[2, 3] := 0;
	NullVector[0] := 0; NullVector[1] := 0;  NullVector[2] := 0;
	InitColor(white, 1, 1, 1); InitColor(black, 0, 0, 0);
END Dim3Engine.
