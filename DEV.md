# Testing
Isolated pixel removal tends to remive thin diagonal lines, a consequence of using a 5 tap pattern.
## AOE2
Works!
Needs less agressive threshold settings (akin to TAA).
Activating Skip background disables the shader altogether.
## Deus Ex Mankind Divided
Tested with TAA: too blurry within recommended specs.
min thresh 0.3 uper thresh 0.45 was much better, with full highlight preservation
# TODO
- Transverse blending UI needs a description
## Half Life 2
The game as a whole doesn't work that well. Everything is blurred for some reason?
When I turn the shader on, it gets worse.
## Space Engineers
Works
## Skyrim
Works, but doesn't make things better when TAA is turned on.
Whenn FXAA is on it barely changes anything.