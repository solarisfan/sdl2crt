unit globals;
interface

(* 
	Customization can be done in this file to tailor default 
	font handling like specifying full path to font file to be
	used by the module. 
	The embedded font data are extract from font file download from int10h.org.
	The embedded font only support the ASCII characters in the original PC.
	For additional character support, load font file acceptable by FreeType 2.
	For good character alignment use monospace font.
*)

(* Specify full font path to be used by the compiled module *)
const
{$IF defined(LINUX)}
	DefaultFontFile40X25 = '/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf'; (* 40X25 *)
	DefaultFontFile80X25 = '/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf'; (* 80X25 *)
	DefaultFontFile80X50 = '/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf'; (* 80X50 *)
{$ELSEIF defined(WINDOWS)}
	DefaultFontFile40X25 = 'C:\Windows\Fonts\ARIALUNI.TTF'; (* 40X25 *)
	DefaultFontFile80X25 = 'C:\Windows\Fonts\ARIALUNI.TTF'; (* 80X25 *)
	DefaultFontFile80X50 = 'C:\Windows\Fonts\ARIALUNI.TTF'; (* 80X50 *)
{$ELSE}
	DefaultFontFile40X25 = '';
	DefaultFontFile80X25 = '';
	DefaultFontFile80X50 = '';
{$ENDIF}

type
	TScreenMode = (S40x25, S80x25, S80x50);
	
implementation	

begin	
end.
