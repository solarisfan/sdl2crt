unit vgafont;

{$DEFINE VGAFONT}
{$I renderChar.inc}

initialization
begin
	//Logger.setLogLevel(LogError);
	Logger.log('Initializing font data');
(* Can use macros to compile module load font using file or embedded data *)	
{$IFDEF USEFONTFILE}
	tty_UseFontFile := true;
{$ELSE}
	tty_UseFontFile := false;
{$ENDIF}

	fontAry[S40x25].fileName := DefaultFontFile40X25;
	fontAry[S40x25].ptsize := 16;
	fontAry[S40x25].data := @VGA9x16x2[0];
	fontAry[S40x25].size := Length(VGA9x16x2);
	fontAry[S80x25].fileName := DefaultFontFile80X25;
	fontAry[S40x25].ptsize := 12;
	fontAry[S80x25].data := @VGA9x16[0];
	fontAry[S80x25].size := Length(VGA9x16);
	fontAry[S80x50].fileName := DefaultFontFile80X50;
	fontAry[S80x50].ptsize := 10;
	fontAry[S80x50].data := @VGA9x8[0];
	fontAry[S80x50].size := Length(VGA9x8);
end;

finalization
begin
	Logger.log('Finalize vgafont unit');
end;

end.
