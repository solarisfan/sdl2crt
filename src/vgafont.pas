unit vgafont;

{$DEFINE VGAFONT}
{$I renderChar.inc}


initialization
begin
	writeln(stderr, 'Initializing vgafont unit');
	fontAry[M40x25].fileName := 'vga9x16x2.ttf';
	fontAry[M40x25].data := @VGA9x16x2[0];
	fontAry[M40x25].size := Length(VGA9x16x2);
	fontAry[M80x25].fileName := 'vga9x16.ttf';
	fontAry[M80x25].data := @VGA9x16[0];
	fontAry[M80x25].size := Length(VGA9x16);
	fontAry[M80x50].fileName := 'vga9x8.ttf';
	fontAry[M80x50].data := @VGA9x8[0];
	fontAry[M80x50].size := Length(VGA9x8);
//	fontFile := 'cga.ttf';
//	fontFile := 'cga-2y.ttf';
//	fontFile := 'ega8x14.ttf';
//	fontFile := '/usr/share/fonts/truetype/ubuntu/UbuntuMono[wght].ttf';
//	fontFile := '/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf';
//	tty_init;
end;

finalization
begin
	writeln(stderr, 'Finalize vgafont unit');
end;

end.
