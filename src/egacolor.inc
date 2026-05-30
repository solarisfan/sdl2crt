
(* Mapped the defined constant color to actual RGB color *)

(* Normal color map *)
colorMap : array [0..15] of LongInt =
	(0, $0000DD, $00AA00, $00AAAA, $AA0000, $AA00AA, $AA5500, 
	 $AAAAAA, $555555, $5555FF, $55FF55, $55FFFF, $FF5555,
     $FF55FF, $FFFF55, $DDDDDD);
     
(* High intensity video color map *)
HicolorMap : array [0..15] of LongInt =
	(0, $0000FF, $00FF00, $00FFFF, $FF0000, $FF00FF, $FFAA00, 
	 $CCCCCC, $888888, $5555FF, $66FF66, $77FFFF, $FF5555,
     $FF55FF, $FFFF55, $FFFFFF);
     
(* Low intensity video color map *)
LocolorMap : array [0..15] of LongInt =
	(0, $000088, $008800, $008888, $880000, $880088, $AA5500, 
	 $888888, $333333, $333388, $33EE33, $33EEEE, $DD3333,
     $EE44EE, $EEEE33, $BBBBBB);
     
(* Background color map. Theoritically the same as normal color map,
   but can be alter to enhance aesthetic appearance *)
bgcolorMap : array [0..15] of LongInt =
	(0, $0000AA, $00AA00, $00AAAA, $AA0000, $AA00AA, $883300, 
	 $AAAAAA, $555555, $5555FF, $55FF55, $55FFFF, $FF5555,
     $FF55FF, $FFFF55, $FFFFFF);
