Anomalous Pixel Blending (APB) is a shader designed to reduce the pixelated appearance of games. It achieves this by blending anomalous pixels with their surroundings in a smart way which takes into account local morphology and minimises blur.

APB works especially well with morphological anti-aliasing techniques (e.g., FXAA, CMAA, SMAA), as it catches many of the aliasing artifacts they miss. It can also be used to reduce sharpening artifacts.

If you encounter any issues, have suggestions for new features, or think some features could be improved, feel free to let me know. In fact, I would appreciate it as it would make the shader better and it would teach me new things. You can open an issue, create a PR, or contact me through Github or the ReShade forums.

# Installation

Open `AnomalousPixelBlending.fx` and click the download button in the top right corner. Save the file to the `reshade-shaders/Shaders` folder of the game where you want to use this shader, and you're good to go.

The markdown (\*.md) files are just documentation and can be ignored.

# How to use

APB is best applied after any anti-aliasing. This improves performance and prevents interference with edge detection.

For highly anti-aliased scenes, use more conservative settings to avoid blur. Refer to the UI control tooltips for precise recommendations.

APB can be applied before any sharpening shader for best sharpness, or after them to eliminate artifacts resulting from the sharpening. Be careful not to make the settings too aggressive, as that may undo the sharpening.

# Functionality & Configuration

APB works with a lower and an upper threshold. The lower threshold must always be less than or equal to the upper threshold. Deltas that fall between the two thresholds have their blending strength linearly interpolated between 0.0 and the blending strength.

Keep in mind that if you use driver-level sharpening effects (such as Radeon™ Image Sharpening) you may need more agressive settings to counteract the sharpening.

Everything else you need to know can be found in the UI of the shader itself as textual explanations and tooltips.

# Tested games

This shader should work everywhere, but here are the games I've tested it on:

- Age of Empires II HD edition
- Deus Ex: Mankind Divided
- Skyrim Special Edition (works, but doesn't have much to do)
- Space Engineers
- The Witcher 3 (Next-gen update, DX11 and DX12)

# Credits

Runs on Reshade by Crosire.

Thanks to Lordbean for inspiring this shader with this Image Softening algorithms.
