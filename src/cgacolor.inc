
(* 
	Mapped the defined CGA constant color to actual RGB color 
	with intensity correction
*)

(* Normal color map *)
colorMap : array [0..15] of LongInt =
	(0, $0000AA, $00AA00, $00AAAA, $AA0000, $AA00AA, $AA5500, $AAAAAA, 
	 $555555, $5555FF, $55FF55, $55FFFF, $FF5555, $FF55FF, $FFFF55, $FFFFFF);
     
(* High intensity video color map *)
HicolorMap : array [0..15] of LongInt =
	($555555, $5555FF, $55FF55, $55FFFF, $FF5555, $FF55FF, $FFFF55, $FFFFFF, 
	 $555555, $5555FF, $55FF55, $55FFFF, $FF5555, $FF55FF, $FFFF55, $FFFFFF);
     
(* Low intensity video color map *)
LocolorMap : array [0..15] of LongInt =
	(0, $0000AA, $00AA00, $00AAAA, $AA0000, $AA00AA, $AA5500, $AAAAAA, 
	 0, $0000AA, $00AA00, $00AAAA, $AA0000, $AA00AA, $AA5500, $AAAAAA);
     
(* Background color map. Theoritically the same as normal color map,
   but can be alter to enhance aesthetic appearance *)
bgcolorMap : array [0..15] of LongInt =
	(0, $0000AA, $00AA00, $00AAAA, $AA0000, $AA00AA, $883300, 
	 $AAAAAA, $555555, $5555FF, $55FF55, $55FFFF, $FF5555,
     $FF55FF, $FFFF55, $FFFFFF);
