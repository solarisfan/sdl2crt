unit vgafont;

(* 
	Customization can be done in this file to tailor default 
	font handling like specifying full path to font file to be
	used by the module. 
	The embedded font data are extract from font file download from int10h.org.
	The embedded font only support the ASCII characters in the original PC.
	For additional character support, load font file acceptable by FreeType 2.
	For good character alignment use monospace font.
*)
{$DEFINE VGAFONT}
{$I renderChar.inc}

(* Specify full font path to be used by the compiled module *)
const
{$IF defined(LINUX)}
	DefaultFontFile1 = '/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf'; (* 40X25 *)
	DefaultFontFile2 = '/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf'; (* 80X25 *)
	DefaultFontFile3 = '/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf'; (* 80X50 *)
{$ELSEIF defined(WINDOWS)}
	DefaultFontFile1 = 'C:\Windows\Fonts\ARIALUNI.TTF'; (* 40X25 *)
	DefaultFontFile2 = 'C:\Windows\Fonts\ARIALUNI.TTF'; (* 80X25 *)
	DefaultFontFile3 = 'C:\Windows\Fonts\ARIALUNI.TTF'; (* 80X50 *)
{$ELSE}
	DefaultFontFile1 = '';
	DefaultFontFile2 = '';
	DefaultFontFile3 = '';
{$ENDIF}

initialization
begin
	Logger.log('Loading and setting font data');
(* Can use macros to compile module load font using file or embedded data *)	
{$IFDEF USEFONTFILE}
	tty_UseFontFile := true;
{$ELSE}
	tty_UseFontFile := false;
{$ENDIF}

	fontAry[M40x25].fileName := DefaultFontFile1;
	fontAry[M40x25].ptsize := 16;
	fontAry[M40x25].data := @VGA9x16x2[0];
	fontAry[M40x25].size := Length(VGA9x16x2);
	fontAry[M80x25].fileName := DefaultFontFile2;
	fontAry[M40x25].ptsize := 12;
	fontAry[M80x25].data := @VGA9x16[0];
	fontAry[M80x25].size := Length(VGA9x16);
	fontAry[M80x50].fileName := DefaultFontFile3;
	fontAry[M80x50].ptsize := 10;
	fontAry[M80x50].data := @VGA9x8[0];
	fontAry[M80x50].size := Length(VGA9x8);
end;

finalization
begin
	Logger.log('Finalize vgafont unit');
end;

end.
