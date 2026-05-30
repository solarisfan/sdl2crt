(* Simple testing program *)
program test;
uses sdl2crt;

var
  OrigMode : Word;
  c : Char;
begin
  OrigMode := LastMode;
  TextMode(CO40);
  repeat
    c := ReadKey;
    writel(c);
  until c = #24; (* until escape key is pressed *)
  (* Resetting TextMode will close the window. *)
  TextMode(OrigMode);
end.
