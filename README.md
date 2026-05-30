# Pascal sdl2crt unit
A pascal module implementing CRT unit using SDL2. Implementation is based on the functionality of Turbo Pascal. The unit is primary developed with Free Pascal compiler from https://www.freepascal.org/

Font data is from the site int10h.org<br>
https://int10h.org/oldschool-pc-fonts/  

You will need the SDL2 from SDL2-for-Pascal<br>
https://github.com/PascalGameDevelopment/SDL2-for-Pascal  

When Textmode is called, a new thread is initiated and a new SDL window is created. Most function/procedures in the unit are messages push into the SDL event queue.
