# Pascal sdl2crt unit
A pascal module implementing CRT unit using SDL2. Implementation is based on the functionality of Turbo Pascal. The unit is primary developed with Free Pascal compiler from https://www.freepascal.org/

Font data is from the site int10h.org<br>
https://int10h.org/oldschool-pc-fonts/  

You will need the Freetype library. On Linux system installing the freetype-dev package is sufficient. On the Windows system you will need the freetype.dll.<br>
https://freetype.org/download.html

You will need the SDL2 from SDL2-for-Pascal<br>
https://github.com/PascalGameDevelopment/SDL2-for-Pascal  

When Textmode is called, a new thread is initiated and a new SDL window is created. Most function/procedures in the unit are messages push into the SDL event queue. Upon program completion you can reset TextMode and the window will be closed. If TextMode is not reset, you can close the window and terminate the program manually.  
Keyboard input and the key stroke/character buffer are guarded by Free Pascal own critical section mechanism. Since this is basically a single consumer and a single producer model, I do not envision any problem. Text input is interpreted as UTF-8 stream. write statement can accept UTF-8 character stream, but not Unicode character.

Compiling the example can be as simple as<br>
>cd example<br>
>fpc -Fu../src -Fu\<location of SDL2 unit\> test.pas<br>

Added extended procedure:  
>TextModeFont(mode, full font file path)

This procedure extend the original TextMode procedure with the added parameter specifying the full path to the font file to be used in the rendering engine.

Modify the file **globals.pas** with the font file you wishes to be included by default.  
A compilation symbol USEFONTFILE, `-dUSEFONTFILE` , can be included in the compile command line to instruct module to load font file instead of using the embedded font.
