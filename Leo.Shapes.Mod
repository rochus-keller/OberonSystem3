MODULE Shapes;	(** eos   **)

	(**
		Compatibility module for users using older version of Leonardo
	**)
	
	IMPORT
		Figures, LeoPaths;
		
	
	PROCEDURE NewPoint*;
	BEGIN
		LeoPaths.NewPoint	(* file format is compatible *)
	END NewPoint;
	
	PROCEDURE NewGroup*;
	BEGIN
		Figures.NewGroup
	END NewGroup;
	
	PROCEDURE NewFigureContainer*;
	BEGIN
		Figures.NewRoot	(* old file format is recognized and understood by new implementation *)
	END NewFigureContainer;
	
	PROCEDURE NewFigure*;
	BEGIN
		Figures.New	(* old file format is recognized and understood by new implementation *)
	END NewFigure;
	

END Shapes.
